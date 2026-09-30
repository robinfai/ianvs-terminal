import 'dart:async';
import 'dart:convert';

import 'package:app/features/ai/ai_api_client.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryAiStore implements AiConfigurationStore {
  MemoryAiStore([this.value = const AiConfiguration.mock()]);
  AiConfiguration? value;
  bool fail = false;
  @override
  Future<AiConfiguration?> read() async => value;
  @override
  Future<void> write(AiConfiguration? configuration) async {
    if (fail) throw StateError('locked');
    value = configuration;
  }
}

AiTerminalContext contextFor({
  String guard = 'root:1',
  AiBlockContext? lastBlock,
}) => AiTerminalContext(
  sessionId: 'one',
  contextId: 'root',
  guard: guard,
  screen: 'shell> ',
  cwd: '/tmp',
  canRunCommand: true,
  readyLease: 'lease',
  lastBlock: lastBlock,
);

class FakeTerminal implements AiTerminalPort {
  AiTerminalContext context = contextFor();
  final inputs = StreamController<void>.broadcast(sync: true);
  final writes = <AiAction>[];
  Completer<Map<String, Object?>>? execution;
  @override
  Stream<void> get userInput => inputs.stream;
  @override
  Future<AiTerminalContext> readContext() async => context;
  @override
  Future<Map<String, Object?>> execute(
    AiAction action,
    AiTerminalContext expected,
    AiCancellation cancellation,
  ) async {
    cancellation.check();
    if (context.guard != expected.guard) throw const AiFailure('stale_context');
    writes.add(action);
    return execution == null
        ? {'status': 'input_sent', 'terminal_context': context.toJson()}
        : execution!.future;
  }

  @override
  void dispose() => unawaited(inputs.close());
}

AiReply commandReply(String command, {String id = 'call-1'}) => AiReply(
  text: 'Proposed command',
  action: AiAction.fromToolCall({
    'id': id,
    'type': 'function',
    'function': {
      'name': 'run_command',
      'arguments': jsonEncode({'command': command, 'reason': 'Inspect files'}),
    },
  }),
);

class FakeApi implements AiApi {
  final requests = <List<Map<String, Object?>>>[];
  final cancellations = <AiCancellation>[];
  Future<AiReply> Function(int) respond = (_) async => commandReply('ls -la');
  @override
  Future<AiReply> complete(
    AiConfiguration configuration,
    List<Map<String, Object?>> messages,
    AiCancellation cancellation,
  ) async {
    requests.add(List.of(messages));
    cancellations.add(cancellation);
    return respond(requests.length);
  }
}

void main() {
  late AiSettingsController settings;
  late FakeTerminal terminal;
  late FakeApi api;
  late TerminalAiController controller;
  setUp(() async {
    settings = AiSettingsController(MemoryAiStore());
    await settings.loaded;
    terminal = FakeTerminal();
    api = FakeApi();
    controller = TerminalAiController(
      settings: settings,
      terminal: terminal,
      api: api,
    );
  });
  tearDown(() {
    controller.dispose();
    settings.dispose();
  });

  test(
    'natural language submits no terminal bytes before explicit approval',
    () async {
      api.respond = (step) async => step == 1
          ? commandReply('ls -la')
          : commandReply('pwd', id: 'call-2');
      await controller.ask('列出当前目录文件');
      expect(controller.phase, AiPhase.awaitingApproval);
      expect(terminal.writes, isEmpty);
      await controller.approve();
      expect(terminal.writes.map((a) => a.command), ['ls -la']);
      expect(controller.pending!.command, 'pwd');
      final result = api.requests.last.firstWhere((m) => m['role'] == 'tool');
      expect(
        jsonDecode(result['content']! as String),
        containsPair('status', 'input_sent'),
      );
      controller.reject();
      expect(terminal.writes, hasLength(1));
    },
  );

  test(
    'manual input cancels inference and late response cannot write',
    () async {
      final response = Completer<AiReply>();
      api.respond = (_) => response.future;
      final waiting = controller.ask('show me files');
      await Future<void>.delayed(Duration.zero);
      terminal.inputs.add(null);
      response.complete(commandReply('ls'));
      await waiting;
      expect(controller.pending, isNull);
      expect(controller.takenOver, isTrue);
      expect(api.cancellations.single.isCancelled, isTrue);
      await controller.approve();
      expect(terminal.writes, isEmpty);
    },
  );

  test(
    'SSH context changing during inference cannot bless stale approval',
    () async {
      final response = Completer<AiReply>();
      api.respond = (_) => response.future;
      final waiting = controller.ask('show me files');
      await Future<void>.delayed(Duration.zero);
      terminal.context = contextFor(guard: 'ssh:2');
      response.complete(commandReply('ls'));
      await waiting;
      await controller.approve();
      expect(controller.error, 'stale_context');
      expect(terminal.writes, isEmpty);
    },
  );

  test(
    'takeover during execution closes tool history before a new request',
    () async {
      await controller.ask('show me files');
      terminal.execution = Completer<Map<String, Object?>>();
      final executing = controller.approve();
      await Future<void>.delayed(Duration.zero);
      controller.takeOver();
      await controller.ask('explain current screen');
      final before = controller.pending;
      terminal.execution!.complete({'status': 'input_sent'});
      await executing;
      expect(controller.pending, same(before));
      final history = api.requests.last;
      expect(history.map((m) => m['role']), [
        'system',
        'user',
        'assistant',
        'tool',
        'user',
      ]);
      expect(
        jsonDecode(history[3]['content']! as String),
        containsPair('interrupted', true),
      );
    },
  );

  test(
    'command correction attaches command, error output, cwd and exit code',
    () async {
      terminal.context = contextFor(
        lastBlock: const AiBlockContext(
          command: 'gti status',
          output: 'zsh: command not found: gti',
          exitCode: 127,
          cwd: '/work',
        ),
      );
      await controller.correctLastCommand();
      final request =
          jsonDecode(api.requests.single.last['content']! as String) as Map;
      expect(request['selected_block'], {
        'command': 'gti status',
        'output': 'zsh: command not found: gti',
        'exit_code': 127,
        'cwd': '/work',
      });
      expect(terminal.writes, isEmpty);
    },
  );

  test('configuration change revokes a pending proposal', () async {
    await controller.ask('show me files');
    await settings.save(
      const AiConfiguration(
        endpoint: 'https://example.com/v1',
        apiKey: 'new',
        model: 'other',
      ),
    );
    expect(controller.pending, isNull);
    await controller.approve();
    expect(terminal.writes, isEmpty);
  });

  test('secure storage failure preserves previous configuration', () async {
    (settings.store as MemoryAiStore).fail = true;
    await expectLater(settings.save(null), throwsA(isA<AiFailure>()));
    expect(settings.configuration!.model, 'trail-mock');
  });

  test('no configured endpoint means no API or PTY request', () async {
    await settings.save(null);
    await controller.ask('list all files');
    expect(controller.error, 'configuration');
    expect(api.requests, isEmpty);
    expect(terminal.writes, isEmpty);
  });

  test(
    'natural language heuristic preserves executable commands and Unicode arguments',
    () {
      for (final text in [
        '请列出文件',
        '帮我修复报错',
        'show me all files',
        'how do I exit vim',
        '? explain this',
      ]) {
        expect(looksLikeNaturalLanguage(text), isTrue, reason: text);
      }
      for (final text in [
        'ls -la',
        'git status',
        'cat "中文文件"',
        'find . -name foo',
        './显示文件',
      ]) {
        expect(looksLikeNaturalLanguage(text), isFalse, reason: text);
      }
    },
  );

  test('interactive keys encode explicit control keys and UTF-8 text', () {
    final action = AiAction.fromToolCall({
      'id': 'vim',
      'function': {
        'name': 'send_keys',
        'arguments': jsonEncode({
          'reason': 'Insert text in vim',
          'keys': [
            {'key': 'ESC'},
            {'text': 'i你好'},
            {'key': 'ESC'},
            {'text': ':w'},
            {'key': 'ENTER'},
          ],
        }),
      },
    });
    expect(utf8.decode(action.inputBytes()), '\x1bi你好\x1b:w\r');
    expect(
      const AiKeyStroke.key('UP').encode(applicationCursor: true),
      '\x1bOA',
    );
    expect(
      () => AiKeyStroke.fromJson({'text': '\x1b:wq'}),
      throwsA(isA<AiFailure>()),
    );
    expect(
      () => AiKeyStroke.fromJson({'key': 'UNKNOWN'}),
      throwsA(isA<AiFailure>()),
    );
  });
}
