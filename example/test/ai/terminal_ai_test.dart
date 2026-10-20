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
  commandNames: const {
    'ls',
    'pwd',
    'echo',
    'printf',
    'touch',
    'git',
    'cat',
    'find',
  },
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
  // This default proposes successive operations. A retry test must explicitly
  // reuse its call ID, as the provider ID identifies one write per task.
  Future<AiReply> Function(int) respond = (step) async =>
      commandReply('ls -la', id: 'call-$step');
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

  AiReply observationReply(int waitMs, int id) => AiReply(
    text: '',
    action: AiAction.fromToolCall({
      'id': 'observe-$id',
      'function': {
        'name': 'read_screen',
        'arguments': jsonEncode({
          'reason': 'Wait for command',
          'wait_ms': waitMs,
        }),
      },
    }),
  );

  const running = AiTerminalContext(
    sessionId: 'one',
    contextId: 'root',
    guard: 'running-1',
    screen: 'Building…',
    runningCommand: 'make',
  );

  test(
    'bounded observation wakes on command completion without input',
    () async {
      terminal.context = running;
      api.respond = (step) async => step == 1
          ? observationReply(30000, step)
          : const AiReply(text: 'Command completed');
      final turn = controller.ask('Build the project');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.phase, AiPhase.observing);
      expect(controller.busy, isTrue);
      expect(controller.canApprove, isFalse);
      terminal.context = contextFor(guard: 'finished-1');
      await turn.timeout(const Duration(seconds: 1));
      final result =
          jsonDecode(api.requests.last.last['content']! as String)
              as Map<String, Object?>;
      final observation = result['observation']! as Map<String, Object?>;
      expect(observation['state_changed'], isTrue);
      expect(observation['wait_expired'], isFalse);
      expect(terminal.writes, isEmpty);
    },
  );

  test(
    'observation timeout retains running state and never reports command failure',
    () async {
      terminal.context = running;
      api.respond = (step) async => step == 1
          ? observationReply(30, step)
          : const AiReply(text: 'Still running');
      await controller.ask('Observe build');
      final result =
          jsonDecode(api.requests.last.last['content']! as String)
              as Map<String, Object?>;
      final observation = result['observation']! as Map<String, Object?>;
      expect(observation['wait_expired'], isTrue);
      expect(result['running_command'], 'make');
      expect(result.containsKey('error'), isFalse);
      expect(terminal.writes, isEmpty);
    },
  );

  test(
    'interactive screens return immediately even when a wait was requested',
    () async {
      terminal.context = const AiTerminalContext(
        sessionId: 'one',
        contextId: 'root',
        guard: 'vim',
        screen: '-- INSERT --',
        runningCommand: 'vim',
        alternateScreen: true,
      );
      api.respond = (step) async => step == 1
          ? observationReply(30000, step)
          : const AiReply(text: 'Inspect editor');
      await controller.ask('Check editor').timeout(const Duration(seconds: 1));
      expect(terminal.writes, isEmpty);
      expect(api.requests, hasLength(2));
    },
  );

  test(
    'takeover cancels waiting; resume reads fresh state and still requires approval',
    () async {
      terminal.context = running;
      api.respond = (step) async => observationReply(30000, step);
      final turn = controller.ask('Keep the original files');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      terminal.inputs.add(null);
      await turn.timeout(const Duration(seconds: 1));
      expect(controller.takenOver, isTrue);
      expect(controller.canResume, isTrue);
      expect(api.requests, hasLength(1));
      terminal.context = contextFor(guard: 'fresh-2');
      api.respond = (_) async => commandReply('pwd', id: 'resumed');
      await controller.resume();
      expect(controller.context!.guard, 'fresh-2');
      expect(controller.canApprove, isTrue);
      expect(terminal.writes, isEmpty);
      expect(
        jsonEncode(api.requests.last),
        contains('Keep the original files'),
      );
      expect(jsonEncode(api.requests.last), contains('do not resend'));
      expect(
        controller.transcript.lastWhere((e) => e.role == 'user').text,
        'Continue task',
      );
    },
  );

  test(
    'old observations compact without losing approved action receipts',
    () async {
      api.respond = (step) async => step == 1
          ? commandReply('pwd')
          : step < 14
          ? observationReply(0, step)
          : const AiReply(text: 'Done');
      await controller.ask('Inspect only');
      await controller.approve();
      expect(terminal.writes, hasLength(1));
      final request = api.requests.last;
      final calls = request.where((m) => m['tool_calls'] != null).toList();
      expect(calls, hasLength(2));
      expect(jsonEncode(calls.first), contains('run_command'));
      expect(jsonEncode(calls.last), contains('read_screen'));
      for (var i = 0; i < request.length; i++) {
        if (request[i]['role'] != 'tool') continue;
        expect(
          ((request[i - 1]['tool_calls']! as List).single as Map)['id'],
          request[i]['tool_call_id'],
        );
      }
    },
  );

  test(
    'resume after request failure cannot duplicate a submitted command',
    () async {
      api.respond = (step) async {
        if (step == 1) return commandReply('printf once');
        throw const AiFailure('timeout');
      };
      await controller.ask('Print once');
      await controller.approve();
      expect(controller.canResume, isTrue);
      api.respond = (_) async => const AiReply(text: 'Already completed');
      await Future.wait([controller.resume(), controller.resume()]);
      expect(terminal.writes, hasLength(1));
      expect(api.requests, hasLength(3));
      expect(controller.canResume, isFalse);
      controller.clear();
      expect(controller.phase, AiPhase.idle);
      expect(controller.transcript, isEmpty);
    },
  );

  test(
    'distinct observations retain earlier output needed for the task',
    () async {
      api.respond = (step) async {
        if (step == 2) {
          terminal.context = const AiTerminalContext(
            sessionId: 'one',
            contextId: 'root',
            guard: 'root:1',
            screen: 'New output replaced earlier screen',
            canRunCommand: true,
          );
        }
        return step <= 2
            ? observationReply(0, step)
            : const AiReply(text: 'Done');
      };
      await controller.ask('Compare both screens');
      final tools = api.requests.last
          .where((m) => m['role'] == 'tool')
          .toList();
      expect(tools, hasLength(2));
      expect(tools.first['content'], contains('shell> '));
      expect(
        tools.last['content'],
        contains('New output replaced earlier screen'),
      );
    },
  );

  test(
    'observation wait validates bounds and block context exposes truncation',
    () {
      for (final wait in [-1, 30001, 1.5, '10']) {
        expect(
          () => AiAction.fromToolCall({
            'id': 'bad',
            'function': {
              'name': 'read_screen',
              'arguments': jsonEncode({'reason': 'Wait', 'wait_ms': wait}),
            },
          }),
          throwsA(isA<AiInvalidAction>()),
        );
      }
      final block = AiBlockContext(
        id: 'block-1',
        command: 'make',
        output: 'x' * 17000,
        exitCode: null,
        cwd: '/tmp',
        running: true,
        totalLines: 500,
        outputStartLine: 340,
      ).toJson();
      expect(block['id'], 'block-1');
      expect(block['running'], isTrue);
      expect(block.containsKey('output_start_line'), false);
      expect(block['output_line_mapping_unavailable'], true);
      expect(block['output_truncated'], isTrue);
      expect((block['output']! as String).length, 16000);
    },
  );

  test(
    'long approved turns preserve the request and complete tool pairs',
    () async {
      final longTerminal = FakeTerminal();
      final longApi = FakeApi()
        ..respond = (step) async => step < 86
            ? commandReply('printf $step', id: 'call-$step')
            : const AiReply(text: 'Finished');
      final longController = TerminalAiController(
        settings: settings,
        terminal: longTerminal,
        api: longApi,
        maxSteps: 100,
      );
      addTearDown(longController.dispose);
      await longController.ask('Keep this original task objective');
      while (longController.canApprove) {
        await longController.approve();
      }
      expect(longController.phase, AiPhase.idle);
      expect(longTerminal.writes, hasLength(85));
      for (final request in longApi.requests) {
        expect(request[1]['role'], 'user');
        expect(request[1]['content'], contains('original task objective'));
        expect(request.where((m) => m['role'] == 'user'), hasLength(1));
        expect(
          jsonEncode(request.skip(1).toList()).length,
          lessThanOrEqualTo(192000),
        );
        for (var index = 2; index < request.length; index++) {
          if (request[index]['role'] != 'tool') continue;
          final calls = request[index - 1]['tool_calls']! as List;
          expect((calls.single as Map)['id'], request[index]['tool_call_id']);
        }
      }
    },
  );

  test(
    'default turn budget still stops without approving another write',
    () async {
      await controller.ask('Inspect the session');
      while (controller.canApprove) {
        await controller.approve();
      }
      expect(controller.error, 'step_limit');
      expect(terminal.writes, hasLength(24));
    },
  );

  test(
    'a follow-up retains the goal after a long turn hits its limit',
    () async {
      terminal.context = AiTerminalContext(
        sessionId: 'one',
        contextId: 'root',
        guard: 'root:1',
        screen: 'output\n' * 2000,
        lastBlock: AiBlockContext(
          command: 'long-running-command',
          output: 'result\n' * 2000,
          exitCode: 0,
          cwd: '/tmp',
        ),
      );
      await controller.ask(
        'Build the requested tool without graphical libraries',
      );
      while (controller.canApprove) {
        await controller.approve();
      }
      expect(controller.error, 'step_limit');
      api.respond = (_) async =>
          const AiReply(text: 'Resuming the original task');
      await controller.ask('Continue the original task');
      final users = api.requests.last
          .where((message) => message['role'] == 'user')
          .map((message) => jsonDecode(message['content']! as String) as Map)
          .toList();
      expect(users.map((message) => message['request']), [
        'Build the requested tool without graphical libraries',
        'Continue the original task',
      ]);
      expect(
        jsonEncode(api.requests.last.skip(1).toList()).length,
        lessThanOrEqualTo(192000),
      );
      expect(terminal.writes, hasLength(24));
    },
  );

  test('many follow-ups preserve earlier goals and user constraints', () async {
    api.respond = (_) async => const AiReply(text: 'Acknowledged');
    await controller.ask('Recover the project and keep the original files');
    await controller.ask('Write the result under /tmp/recovered');
    for (var i = 0; i < 40; i++) {
      await controller.ask('Continue step $i');
    }
    final request = api.requests.last;
    expect(jsonEncode(request), contains('keep the original files'));
    expect(jsonEncode(request), contains('/tmp/recovered'));
    expect(request.where((m) => m['role'] == 'user'), hasLength(42));
    expect(controller.error, isNull);
    expect(terminal.writes, isEmpty);
  });

  test(
    'compaction preserves selected blocks and the latest observation',
    () async {
      const selected = AiBlockContext(
        command: 'failed-original-command',
        output: 'failure details',
        exitCode: 1,
        cwd: '/original',
      );
      await controller.ask(
        'Repair this block and preserve its input',
        block: selected,
      );
      for (var i = 0; i < 20; i++) {
        await controller.approve();
        controller.reject();
        terminal.context = AiTerminalContext(
          sessionId: 'one',
          contextId: 'root',
          guard: 'root:1',
          screen: 'fresh observation $i',
        );
        await controller.ask('Continue with constraint $i');
      }
      final messages = api.requests.last.skip(1).toList();
      final first = jsonDecode(messages.first['content']! as String) as Map;
      expect(first['selected_block'], selected.toJson());
      expect(
        first,
        contains('terminal_context'),
      ); // Unique initial evidence remains.
      for (var i = 0; i < 20; i++) {
        expect(jsonEncode(messages), contains('fresh observation $i'));
      }
      final user = messages.lastWhere((m) => m['role'] == 'user');
      expect(user['content'], contains('fresh observation 19'));
      expect(jsonEncode(messages).length, lessThanOrEqualTo(192000));
      for (var i = 0; i < messages.length; i++) {
        if (messages[i]['role'] != 'tool') continue;
        final calls = messages[i - 1]['tool_calls']! as List;
        expect((calls.single as Map)['id'], messages[i]['tool_call_id']);
      }
    },
  );

  test(
    'snapshot compression uses valid references and retains unique evidence',
    () async {
      api.respond = (_) async => const AiReply(text: 'Observed');
      for (var i = 0; i < 8; i++) {
        await controller.ask('Keep constraint $i');
      }
      terminal.context = const AiTerminalContext(
        sessionId: 'one',
        contextId: 'root',
        guard: 'changed',
        screen: 'Unique new evidence',
        cwd: '/tmp',
      );
      await controller.ask('Compare the latest evidence');
      final sources = <String>{};
      for (final message in api.requests.last) {
        if (message['role'] != 'user' && message['role'] != 'tool') continue;
        final content = jsonDecode(message['content']! as String) as Map;
        if (content['terminal_context_id'] case final String id) {
          sources.add(id);
        }
        if (content['terminal_context_unchanged_from']
            case final String reference) {
          expect(sources, contains(reference));
        }
      }
      expect(sources, hasLength(2));
      expect(jsonEncode(api.requests.last), contains('Unique new evidence'));
      expect(terminal.writes, isEmpty);
    },
  );

  test(
    'full request history stops explicitly and a new conversation recovers',
    () async {
      api.respond = (_) async => const AiReply(text: 'Acknowledged');
      for (var i = 0; i < 64; i++) {
        await controller.ask('Keep constraint $i');
        expect(controller.error, isNull);
      }
      final requestsBeforeLimit = api.requests.length;
      await controller.ask('One more constraint');
      expect(controller.error, 'conversation_limit');
      expect(api.requests, hasLength(requestsBeforeLimit));
      expect(terminal.writes, isEmpty);
      controller.clear();
      await controller.ask('A new independent goal');
      expect(controller.error, isNull);
      expect(api.requests.last, hasLength(2));
      expect(
        api.requests.last.last['content'],
        contains('A new independent goal'),
      );
      expect(jsonEncode(api.requests.last), isNot(contains('Keep constraint')));
    },
  );

  test(
    'request text size limit never silently drops human constraints',
    () async {
      api.respond = (_) async => const AiReply(text: 'Acknowledged');
      for (var i = 0; i < 30 && controller.error == null; i++) {
        await controller.ask('Constraint $i: ${'x' * 15000}');
      }
      expect(controller.error, 'conversation_limit');
      for (final request in api.requests) {
        expect(jsonEncode(request), contains('Constraint 0:'));
        expect(
          jsonEncode(request.skip(1).toList()).length,
          lessThanOrEqualTo(192000),
        );
      }
      expect(terminal.writes, isEmpty);
    },
  );

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
    'rejected proposals can be repaired but still require approval',
    () async {
      api.respond = (step) async {
        if (step == 1) {
          throw const AiInvalidAction('Text exceeds 4096 UTF-16 code units.');
        }
        return commandReply('pwd');
      };
      await controller.ask('Inspect current directory');
      expect(controller.phase, AiPhase.awaitingApproval);
      expect(terminal.writes, isEmpty);
      expect(api.requests.last.last['role'], 'system');
      expect(
        api.requests.last.last['content'],
        contains('No terminal input was sent'),
      );
      expect(api.requests.last.where((m) => m['role'] == 'user'), hasLength(1));
      expect(api.requests.last.where((m) => m['role'] == 'tool'), isEmpty);
      api.respond = (_) async => const AiReply(text: 'Done');
      await controller.approve();
      expect(terminal.writes.single.command, 'pwd');
      expect(api.requests.last.last['role'], 'tool');
    },
  );

  test(
    'invalid proposal repairs are bounded without writing terminal input',
    () async {
      api.respond = (_) async =>
          throw const AiInvalidAction('Unsupported key.');
      await controller.ask('Inspect current directory');
      expect(controller.error, 'invalid_action');
      expect(api.requests, hasLength(3));
      expect(terminal.writes, isEmpty);
      expect(controller.pending, isNull);
    },
  );

  for (final repairs in [true, false]) {
    test(
      'failed evidence needs a diagnosis before approval: repaired=$repairs',
      () async {
        controller.attachContext(
          const AiBlockContext(
            id: 'failed',
            command: 'check',
            output: 'connection refused',
            exitCode: 7,
            cwd: '/tmp',
            totalLines: 1,
            outputEndLine: 1,
          ),
        );
        final action = commandReply('cat check.sh').action!;
        api.respond = (step) async => repairs && step == 2
            ? AiReply(
                text:
                    'The connection was refused; cause unknown. [block:failed:1-1]',
                action: action,
              )
            : AiReply(text: '', action: action);
        await controller.ask('Diagnose the attached failure');
        expect(terminal.writes, isEmpty);
        expect(api.requests, hasLength(repairs ? 2 : 3));
        expect(api.requests[1].last['content'], contains('source citation'));
        expect(controller.canApprove, repairs);
        expect(
          controller.transcript.where((entry) => entry.action != null),
          hasLength(repairs ? 1 : 0),
        );
        if (repairs) {
          expect(controller.error, isNull);
          expect(
            controller.transcript
                .where((entry) => entry.role == 'assistant')
                .single
                .text,
            contains('cause unknown'),
          );
        } else {
          expect(controller.error, 'invalid_action');
          expect(controller.pending, isNull);
        }
      },
    );
  }

  test(
    'takeover cancels a replacement proposal and cannot authorize input',
    () async {
      final response = Completer<AiReply>();
      api.respond = (step) async {
        if (step == 1) throw const AiInvalidAction('Unsupported key.');
        return response.future;
      };
      final waiting = controller.ask('Inspect current directory');
      await Future<void>.delayed(Duration.zero);
      expect(api.requests, hasLength(2));
      terminal.inputs.add(null);
      response.complete(commandReply('pwd'));
      await waiting;
      await controller.approve();
      expect(controller.takenOver, isTrue);
      expect(controller.pending, isNull);
      expect(terminal.writes, isEmpty);
    },
  );

  test('uncertain execution never triggers an automatic repair', () async {
    await controller.ask('Inspect current directory');
    terminal.execution = Completer<Map<String, Object?>>();
    final executing = controller.approve();
    terminal.execution!.completeError(const AiFailure('connection'));
    await executing;
    expect(api.requests, hasLength(1));
    expect(terminal.writes, hasLength(1));
    expect(controller.error, 'connection');
  });

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
    'takeover during unconfirmed execution holds a new request as draft',
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
      expect(api.requests, hasLength(1));
      expect(controller.draft, 'explain current screen');
      expect(controller.hasUnresolvedSubmission, true);
      expect(controller.canApprove, false);
      expect(controller.canResume, false);
      expect(terminal.writes, hasLength(1));
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
        'output_start_line': 0,
        'output_truncated': false,
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
        expect(
          looksLikeNaturalLanguage(
            text,
            commandNames: const {'ls', 'git', 'cat', 'find'},
          ),
          isFalse,
          reason: text,
        );
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
