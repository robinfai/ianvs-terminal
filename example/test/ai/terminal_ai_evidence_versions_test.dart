import 'dart:async';
import 'dart:convert';

import 'package:app/features/ai/acp/agent_backend.dart';
import 'package:app/features/ai/ai_api_client.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store implements AiConfigurationStore {
  @override
  Future<AiConfiguration?> read() async => const AiConfiguration.mock();
  @override
  Future<void> write(AiConfiguration? configuration) async {}
}

class _Api implements AiApi {
  final requests = <List<Map<String, Object?>>>[];
  Future<AiReply> Function(int) respond = (_) async =>
      const AiReply(text: 'Finished reviewing output');

  @override
  Future<AiReply> complete(
    AiConfiguration configuration,
    List<Map<String, Object?>> messages,
    AiCancellation cancellation,
  ) async {
    requests.add(List.of(messages));
    return respond(requests.length);
  }

  List<Map<String, Object?>> get reads => [
    for (final message in requests.last)
      if (message['role'] == 'tool' &&
          (message['tool_call_id']! as String).startsWith('read-a-'))
        jsonDecode(message['content']! as String) as Map<String, Object?>,
  ];
}

class _Agent implements AgentBackend {
  Future<void> Function(AgentToolHandler) run = (_) async {};

  @override
  Future<void> prompt(
    String prompt, {
    required AgentToolHandler tools,
    required AgentEventHandler events,
    required AiCancellation cancellation,
  }) => run(tools);

  @override
  Future<void> dispose() async {}
}

class _Terminal implements AiTerminalPort, AiBlockReader {
  String sessionId = 'one';
  String? lastId;
  int aBase = 100;
  bool liveBaseKnown = true;
  final writes = <AiAction>[];
  final reads = <String>[];
  final input = StreamController<void>.broadcast(sync: true);

  AiBlockContext block(
    String id, {
    int start = 0,
    int count = 20,
    bool mapped = true,
    bool scoped = true,
  }) {
    final base = id == 'block-a' ? aBase : 500;
    return AiBlockContext(
      id: id,
      command: id,
      output: 'source rows ${base + start} through ${base + start + count - 1}',
      exitCode: 0,
      cwd: '/tmp',
      sourceSessionId: scoped ? sessionId : null,
      sourceContextId: 'root',
      sourceLineBase: mapped ? base : null,
      outputStartLine: start,
      outputEndLine: start + count,
      totalLines: 200,
    );
  }

  @override
  Future<AiTerminalContext> readContext() async => AiTerminalContext(
    sessionId: sessionId,
    contextId: 'root',
    guard: '$sessionId:$lastId',
    screen: '$lastId output',
    cwd: '/tmp',
    canRunCommand: lastId != 'block-b',
    readyLease: lastId == 'block-b' ? null : 'ready',
    runningCommand: lastId == 'block-b' ? 'producer-b' : null,
    lastBlock: lastId == null ? null : block(lastId!, mapped: liveBaseKnown),
  );

  @override
  Stream<void> get userInput => input.stream;

  @override
  Future<Map<String, Object?>> execute(
    AiAction action,
    AiTerminalContext expected,
    AiCancellation cancellation,
  ) async {
    cancellation.check();
    writes.add(action);
    lastId = action.command == 'producer-a' ? 'block-a' : 'block-b';
    return {
      'block_id': lastId,
      'terminal_context': (await readContext()).toJson(),
      'status': 'input_sent',
    };
  }

  @override
  Future<AiBlockContext> readBlockRange(
    String blockId, {
    required int startLine,
    required int lineCount,
    required AiTerminalContext expected,
  }) async {
    reads.add(blockId);
    return block(blockId, start: startLine, count: lineCount);
  }

  @override
  void dispose() => unawaited(input.close());
}

AiReply _command(String suffix) => AiReply(
  text: 'Start the requested producer',
  action: AiAction.fromToolCall({
    'id': 'command-$suffix',
    'function': {
      'name': 'run_command',
      'arguments': jsonEncode({
        'command': 'producer-$suffix',
        'reason': 'Produce the requested output',
      }),
    },
  }),
);

Map<String, Object?> _rangeArguments(int start) => {
  'block_id': 'block-a',
  'start_line': start,
  'line_count': 10,
  'reason': 'Read the output supplied in this task',
};

AiReply _read(int start) => AiReply(
  text: 'Read the earlier block',
  action: AiAction.fromToolCall({
    'id': 'read-a-$start',
    'function': {
      'name': 'read_block',
      'arguments': jsonEncode(_rangeArguments(start)),
    },
  }),
);

void main() {
  group('$TerminalAiController supplied source versions', () {
    late AiSettingsController settings;
    late _Terminal terminal;
    late _Api api;
    late _Agent agent;
    late TerminalAiController controller;

    setUp(() async {
      settings = AiSettingsController(_Store());
      await settings.loaded;
      terminal = _Terminal();
      api = _Api();
      agent = _Agent();
      controller = TerminalAiController(
        settings: settings,
        terminal: terminal,
        api: api,
        agentFactory: (_) => agent,
      );
    });

    tearDown(() {
      controller.dispose();
      settings.dispose();
    });

    for (final acp in [false, true]) {
      test(
        '${acp ? 'ACP' : 'API'} retains an older executed block version after the next command starts',
        () async {
          final acpReads = <Map<String, Object?>>[];
          if (acp) {
            await settings.save(
              const AiConfiguration.acp(agentCommand: '/fixture'),
            );
            agent.run = (tools) async {
              for (final suffix in ['a', 'b']) {
                final observed = await tools('get_terminal_state', {});
                await tools('run_command', {
                  'command': 'producer-$suffix',
                  'reason': 'Produce the requested output',
                  'operation_id': suffix,
                  'context_version': observed['context_version'],
                });
              }
              acpReads.add(await tools('read_block', _rangeArguments(0)));
              terminal.aBase = 180;
              acpReads.add(await tools('read_block', _rangeArguments(10)));
            };
          } else {
            api.respond = (n) async {
              if (n == 1) return _command('a');
              if (n == 2) return _command('b');
              if (n == 3) return _read(0);
              if (n == 4) {
                terminal.aBase = 180;
                return _read(10);
              }
              return const AiReply(text: 'Finished reviewing output');
            };
          }

          await controller.ask('Inspect A while B is producing output');
          await controller.approve();
          await controller.approve();

          final reads = acp ? acpReads : api.reads;
          expect(reads, hasLength(2));
          expect((reads[0]['block']! as Map)['source_line_base'], 100);
          expect(reads[1]['error'], 'block_range_evicted');
          expect(reads[1].containsKey('block'), isFalse);
          expect(terminal.writes, hasLength(2));
          expect(controller.error, isNull);
        },
      );
    }

    test(
      'remembers the first read_block result when earlier evidence was unmapped',
      () async {
        controller.attachContext(terminal.block('block-a', mapped: false));
        api.respond = (n) async {
          if (n == 1) return _read(0);
          if (n == 2) {
            terminal.aBase = 180;
            return _read(10);
          }
          return const AiReply(text: 'Output moved');
        };

        await controller.ask('Read this output in two pieces');

        expect((api.reads[0]['block']! as Map)['source_line_base'], 100);
        expect(api.reads[1]['error'], 'block_range_evicted');
        expect(terminal.writes, isEmpty);
      },
    );

    test(
      'a live UI refresh cannot replace evidence already sent for inference',
      () async {
        terminal.lastId = 'block-a';
        final inference = Completer<AiReply>();
        final started = Completer<void>();
        api.respond = (n) async {
          if (n == 1) {
            started.complete();
            return inference.future;
          }
          return const AiReply(text: 'Output moved');
        };
        final asking = controller.ask('Read the displayed range');
        await started.future;
        terminal.aBase = 180;
        await controller.refreshContext();
        expect(controller.context?.lastBlock?.sourceLineBase, 180);
        inference.complete(_read(10));
        await asking;

        expect(api.reads.single['error'], 'block_range_evicted');
        expect(terminal.writes, isEmpty);
      },
    );

    test(
      'unmapped new evidence cannot clear a reliable earlier version',
      () async {
        controller.attachContext(terminal.block('block-a'));
        await controller.ask('Keep this evidence');
        controller.attachContext(terminal.block('block-a', mapped: false));
        terminal.aBase = 180;
        api.respond = (n) async =>
            n == 2 ? _read(10) : const AiReply(text: 'Output moved');

        await controller.ask('Read the earlier range');

        expect(api.reads.single['error'], 'block_range_evicted');
        expect(terminal.writes, isEmpty);
      },
    );

    test(
      'a new task cannot inherit authorization for a prior task block',
      () async {
        controller.attachContext(terminal.block('block-a'));
        await controller.ask('Keep this evidence');
        controller.newTask();
        api.respond = (n) async =>
            n == 2 ? _read(10) : const AiReply(text: 'No supplied block');

        await controller.ask('Inspect the new task');

        expect(api.reads.single['error'], 'block_unavailable');
        expect(terminal.reads, isEmpty);
      },
    );

    test(
      'reconnection cannot authorize an old accepted block ID on the new session',
      () async {
        api.respond = (n) async => n == 1
            ? _command('a')
            : const AiReply(text: 'First command completed');
        await controller.ask('Inspect producer A');
        await controller.approve();
        expect(
          controller.transcript.any((e) => e.blockId == 'block-a'),
          isTrue,
        );
        controller.prepareForConnectionChange();
        terminal
          ..sessionId = 'two'
          ..lastId = 'block-b'
          ..aBase = 180;
        await controller.refreshContext();
        api.respond = (n) async => n == 3
            ? _read(10)
            : const AiReply(text: 'No supplied block on this session');

        await controller.resume(useCurrentTarget: true);

        expect(api.reads.single['error'], 'block_unavailable');
        expect(terminal.reads, isEmpty);
        expect(terminal.writes, hasLength(1));
      },
    );

    test(
      'resending history does not rebind an unscoped old selection after reconnect',
      () async {
        controller.attachContext(terminal.block('block-a', scoped: false));
        await controller.ask('Keep the old session evidence');
        controller.prepareForConnectionChange();
        terminal
          ..sessionId = 'two'
          ..lastId = 'block-a'
          ..aBase = 180
          ..liveBaseKnown = false;
        await controller.refreshContext();
        api.respond = (n) async =>
            n == 2 ? _read(10) : const AiReply(text: 'Read new session output');

        await controller.resume(useCurrentTarget: true);

        expect(api.reads.single['error'], isNull);
        expect((api.reads.single['block']! as Map)['source_line_base'], 180);
        expect(terminal.writes, isEmpty);
      },
    );

    test(
      'an unscoped old attachment cannot authorize an unseen block after reconnect',
      () async {
        controller.attachContext(terminal.block('block-a', scoped: false));
        await controller.ask('Keep the old session evidence');
        controller.prepareForConnectionChange();
        terminal
          ..sessionId = 'two'
          ..lastId = 'block-b'
          ..aBase = 180;
        await controller.refreshContext();
        api.respond = (n) async => n == 2
            ? _read(10)
            : const AiReply(text: 'No supplied block on this session');

        await controller.resume(useCurrentTarget: true);

        expect(api.reads.single['error'], 'block_unavailable');
        expect(terminal.reads, isEmpty);
        expect(terminal.writes, isEmpty);
      },
    );
  });
}
