import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/features/ai/acp/agent_backend.dart';
import 'package:app/features/ai/ai_api_client.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_connections.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_runtime.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

class _Store implements AiConfigurationStore {
  @override
  Future<AiConfiguration?> read() async => const AiConfiguration.mock();
  @override
  Future<void> write(AiConfiguration? configuration) async {}
}

class _Api implements AiApi {
  AiAction action = _keys;
  int proposalRequest = 1;
  final requests = <List<Map<String, Object?>>>[];
  @override
  Future<AiReply> complete(
    AiConfiguration configuration,
    List<Map<String, Object?>> messages,
    AiCancellation cancellation,
  ) async {
    cancellation.check();
    requests.add(List.of(messages));
    return requests.length == proposalRequest
        ? AiReply(text: 'Inspect the current application.', action: action)
        : const AiReply(text: 'Fresh screen inspected; no input replayed.');
  }
}

// Keep the production AI runtime and connection routing. Only the existing
// PTY/runtime boundary is replaced; accepted writes are recorded as raw bytes.
class _Runtime extends Fake implements TerminalRuntimeController {
  final events = StreamController<TerminalSessionInputEvent>.broadcast(
    sync: true,
  );
  final writes = <String>[];
  void Function()? onInput;
  bool acceptInput = true;
  bool ready = false;
  bool alternate = false;
  String screen = 'application> ';
  String receiptOutcome = 'unknown';
  String? submittedId;
  int submissions = 0;
  final inspected = <String>[];

  @override
  Stream<TerminalSessionInputEvent> get inputEvents => events.stream;
  @override
  bool hasSession(String sessionId) => true;
  @override
  bool isZmodemTransferActive(String sessionId) => false;
  @override
  Map<String, Object?>? liveScreen(String sessionId) => {
    'text': screen,
    'alternateScreen': alternate,
  };
  @override
  Map<String, Object?>? commandBlocks(
    String sessionId, [
    Map<String, Object?> payload = const {},
  ]) => {'blocks': <Object?>[]};
  @override
  Map<String, Object?>? composerRequest(
    String sessionId,
    String operation,
    Map<String, Object?> payload,
  ) {
    switch (operation) {
      case 'composer.submit':
        submissions++;
        submittedId = payload['submissionId']! as String;
        return {'outcome': 'unknown'};
      case 'composer.receipt':
        inspected.add(payload['submissionId']! as String);
        return {
          'submissionId': submittedId,
          'outcome': receiptOutcome,
          if (receiptOutcome == 'accepted') 'blockId': 'original-block',
        };
      default:
        return {
          'contextId': 'root',
          'cwd': '/tmp',
          'state': ready ? 'ready' : 'running',
          if (ready) 'lease': 'ready-lease',
        };
    }
  }

  @override
  bool trySendInput(String sessionId, Uint8List bytes, {Object? origin}) {
    if (!acceptInput) return false;
    writes.add(utf8.decode(bytes));
    events.add(TerminalSessionInputEvent(sessionId, bytes, origin: origin));
    onInput?.call();
    return true;
  }
}

class _Agent implements AgentBackend {
  final prompts = <Map<String, Object?>>[];
  final firstFinished = Completer<void>();
  Map<String, Object?>? originalResult;
  Map<String, Object?>? inspectedResult;
  @override
  Future<void> prompt(
    String prompt, {
    required AgentToolHandler tools,
    required AgentEventHandler events,
    required AiCancellation cancellation,
  }) async {
    prompts.add((jsonDecode(prompt) as Map).cast<String, Object?>());
    if (prompts.length > 1) {
      inspectedResult = await tools('inspect_submission', {
        'operation_id': 'keys-original',
      });
      return;
    }
    try {
      final observed = await tools('get_terminal_state', {});
      originalResult = await tools('send_keys', {
        ...((jsonDecode(
                  (_keys.rawCall['function']! as Map)['arguments']! as String,
                ))
                as Map)
            .cast<String, Object?>(),
        'operation_id': 'keys-original',
        'context_version': observed['context_version'],
      });
      cancellation.check();
    } finally {
      firstFinished.complete();
    }
  }

  @override
  Future<void> dispose() async {}
}

AiAction get _keys => AiAction.fromToolCall({
  'id': 'keys-one',
  'function': {
    'name': 'send_keys',
    'arguments': jsonEncode({
      'keys': [
        {'key': 'ESC'},
        {'text': ':status'},
        {'key': 'ENTER'},
      ],
      'reason': 'Inspect application status.',
    }),
  },
});

void main() {
  group('$TerminalAiController input recovery', () {
    late AiSettingsController settings;
    late _Runtime runtime;
    late _Api api;
    late _Agent agent;
    late TerminalAiConnections connections;
    late TerminalAiController controller;

    setUp(() async {
      settings = AiSettingsController(_Store());
      await settings.loaded;
      runtime = _Runtime();
      api = _Api();
      agent = _Agent();
      final terminal = TerminalAiRuntime(
        sessionId: 'one',
        runtime: runtime,
        readPane: () => const TerminalPane(
          sessionId: 'one',
          title: 'Current terminal',
          profileId: 'local',
        ),
        isReadOnly: () => false,
      );
      connections = TerminalAiConnections(
        sessionId: 'one',
        terminal: terminal,
        requestBlocks: runtime.commandBlocks,
      );
      controller = TerminalAiController(
        settings: settings,
        terminal: connections,
        api: api,
        agentFactory: (_) => agent,
      );
    });

    tearDown(() async {
      controller.dispose();
      settings.dispose();
      await runtime.events.close();
    });

    for (final count in [0, 1, 3]) {
      test(
        'pause after $count accepted steps resumes without replay',
        () async {
          final sent = Completer<void>();
          runtime.onInput = () {
            if (runtime.writes.length == count) sent.complete();
          };
          await controller.ask('Inspect application status');
          final approval = controller.approve();
          if (count > 0) await sent.future;
          controller.takeOver();
          await approval;
          final entry = controller.transcript.singleWhere(
            (e) => e.action != null,
          );
          expect(entry.inputProgress?.sent, count);
          expect(entry.inputProgress?.total, 3);
          expect(entry.inputProgress?.writeUncertain, isFalse);
          expect(entry.submissionId, isNull);
          expect(
            entry.state,
            count == 0
                ? AiEntryState.revoked
                : count == 3
                ? AiEntryState.accepted
                : AiEntryState.interrupted,
          );
          expect(controller.hasUnresolvedSubmission, isFalse);
          expect(controller.canResume, isTrue);
          runtime.screen = 'fresh state after pause';
          await controller.resume();
          expect(
            runtime.writes,
            ['\x1b', ':status', '\r'].take(count).toList(),
          );
          expect(runtime.submissions, 0);
          expect(api.requests, hasLength(2));
          final history = api.requests.last;
          final resumed = jsonDecode(history.last['content']! as String) as Map;
          expect(
            (resumed['terminal_context'] as Map)['screen'],
            runtime.screen,
          );
          final original =
              (resumed['original_submissions'] as List).single as Map;
          expect((original['input_progress'] as Map)['sent_count'], count);
          final result =
              jsonDecode(
                    history.singleWhere((m) => m['role'] == 'tool')['content']!
                        as String,
                  )
                  as Map;
          expect((result['input_progress'] as Map)['sent_count'], count);
          expect(
            (result['input_progress'] as Map)['sent_keys'],
            hasLength(count),
          );
          expect(result['instruction'], contains('Do not replay sent_keys'));
        },
      );
    }

    test(
      'an unconfirmed write retains its accepted prefix and stays blocked',
      () async {
        runtime.onInput = () => runtime.acceptInput = false;
        await controller.ask('Inspect application status');
        await controller.approve();
        await controller.refreshContext();
        final entry = controller.transcript.singleWhere(
          (e) => e.action != null,
        );
        expect(entry.state, AiEntryState.unknown);
        expect(entry.inputProgress?.sent, 1);
        expect(entry.inputProgress?.writeUncertain, isTrue);
        expect(controller.canResume, isFalse);
        await controller.resume();
        expect(api.requests, hasLength(1));
        expect(runtime.writes, ['\x1b']);
      },
    );

    for (final reconnect in [false, true]) {
      test(
        'reused provider ids cannot reconcile another task${reconnect ? ' after reconnect' : ''}',
        () async {
          runtime.onInput = () => runtime.acceptInput = false;
          await controller.ask('Inspect application status');
          final originalTask = controller.taskId;
          final originalAction = controller.pending!;
          await controller.approve();
          expect(controller.hasUnresolvedSubmission, isTrue);
          if (reconnect) {
            controller.prepareForConnectionChange();
            connections.reconnect(
              sessionId: 'two',
              terminal: TerminalAiRuntime(
                sessionId: 'two',
                runtime: runtime,
                readPane: () => const TerminalPane(
                  sessionId: 'two',
                  title: 'Reconnected terminal',
                  profileId: 'local',
                ),
                isReadOnly: () => false,
              ),
            );
          }
          controller.newTask();
          runtime.onInput = null;
          runtime.acceptInput = true;
          runtime.alternate = true;
          api.action = _keys;
          api.proposalRequest = 2;
          await controller.ask('Inspect this separate task');
          expect(controller.pending!.id, originalAction.id);
          expect(identical(controller.pending, originalAction), isFalse);
          await controller.approve();
          expect(controller.hasUnresolvedSubmission, isFalse);
          controller.selectTask(originalTask);
          await controller.refreshContext();
          final entry = controller.transcript.singleWhere(
            (e) => e.action != null,
          );
          expect(entry.state, AiEntryState.unknown);
          expect(entry.inputProgress?.sent, 1);
          expect(entry.inputProgress?.writeUncertain, isTrue);
          expect(controller.canResume, isFalse);
        },
      );
    }

    test(
      'unknown commands still require their original native receipt',
      () async {
        runtime.ready = true;
        api.action = AiAction.fromToolCall({
          'id': 'command-one',
          'function': {
            'name': 'run_command',
            'arguments': jsonEncode({
              'command': 'pwd',
              'reason': 'Inspect directory',
            }),
          },
        });
        await controller.ask('Inspect the directory');
        await controller.approve();
        await controller.refreshContext();
        expect(controller.hasUnresolvedSubmission, isTrue);
        expect(controller.canResume, isFalse);
        await controller.resume();
        expect(api.requests, hasLength(1));
        runtime.receiptOutcome = 'accepted';
        await controller.refreshContext();
        expect(controller.canResume, isTrue);
        await controller.resume();
        expect(runtime.submissions, 1);
        expect(runtime.inspected, everyElement(runtime.submittedId));
        expect(api.requests, hasLength(2));
      },
    );

    test(
      'ACP keeps the sent prefix in cancellation and inspection results',
      () async {
        await settings.save(
          const AiConfiguration.acp(agentCommand: '/fixture'),
        );
        final sent = Completer<void>();
        runtime.onInput = sent.complete;
        await controller.ask('Inspect application status');
        final approval = controller.approve();
        await sent.future;
        controller.takeOver();
        await approval;
        await agent.firstFinished.future;
        await Future<void>.delayed(Duration.zero);
        expect(
          (agent.originalResult!['input_progress']! as Map)['sent_count'],
          1,
        );
        expect(
          agent.originalResult!['instruction'],
          contains('Do not replay sent_keys'),
        );
        runtime.screen = 'fresh state after pause';
        await controller.resume();
        expect(agent.prompts, hasLength(2));
        expect(
          (agent.inspectedResult!['input_progress']! as Map)['sent_count'],
          1,
        );
        expect(runtime.writes, ['\x1b']);
        expect(controller.phase, AiPhase.idle);
      },
    );
  });
}
