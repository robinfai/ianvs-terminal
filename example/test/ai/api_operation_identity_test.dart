import 'dart:convert';

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'terminal_ai_test.dart'
    show FakeApi, FakeTerminal, MemoryAiStore, commandReply;

class _ReceiptTerminal extends FakeTerminal implements AiSubmissionInspector {
  final submissions = <String, String>{};
  final receipts = <String, Map<String, Object?>>{};
  bool loseNextReceipt = false;

  @override
  Future<Map<String, Object?>> execute(
    AiAction action,
    AiTerminalContext expected,
    AiCancellation cancellation,
  ) async {
    await super.execute(action, expected, cancellation);
    final id = 'submission-${writes.length}';
    submissions[action.id] = id;
    receipts[id] = {'outcome': 'accepted', 'blockId': 'block-${writes.length}'};
    if (loseNextReceipt) {
      loseNextReceipt = false;
      throw const AiFailure('submission_unknown');
    }
    return {
      'status': 'input_sent',
      'submission_id': id,
      'block_id': 'block-${writes.length}',
      'terminal_context': context.toJson(),
    };
  }

  @override
  String? submissionFor(String actionId) => submissions[actionId];

  @override
  Future<Map<String, Object?>> inspectSubmission(String id) async =>
      receipts[id] ?? {'outcome': 'unknown'};
}

AiReply _keysReply(String text, {String id = 'input-1'}) => AiReply(
  text: 'Enter the requested text',
  action: AiAction.fromToolCall({
    'id': id,
    'function': {
      'name': 'send_keys',
      'arguments': jsonEncode({
        'keys': [
          {'text': text},
        ],
        'reason': 'Enter the requested text',
      }),
    },
  }),
);

Map<String, Object?> _lastToolResult(FakeApi api) =>
    jsonDecode(
          api.requests.last.lastWhere(
                (message) => message['role'] == 'tool',
              )['content']!
              as String,
        )
        as Map<String, Object?>;

void main() {
  late AiSettingsController settings;
  late _ReceiptTerminal terminal;
  late FakeApi api;
  late TerminalAiController controller;

  setUp(() async {
    settings = AiSettingsController(MemoryAiStore());
    await settings.loaded;
    terminal = _ReceiptTerminal();
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
    'repeated API command ID returns the original receipt without input',
    () async {
      api.respond = (step) async => step <= 2
          ? commandReply('touch once', id: 'write-once')
          : const AiReply(text: 'Original submission inspected');
      await controller.ask('Create the file once');
      await controller.approve();
      // A repeated model call must not become another effective approval.
      await controller.approve();

      expect(terminal.writes, hasLength(1));
      expect(controller.pending, isNull);
      expect(
        controller.transcript.where((entry) => entry.action != null),
        hasLength(1),
      );
      final replay = _lastToolResult(api);
      expect(replay['submission_id'], 'submission-1');
      expect(replay['block_id'], 'block-1');
      expect(replay['operation_replayed'], isTrue);
      expect(replay['state'], 'accepted');
    },
  );

  test('repeated API key operation does not deliver the keys twice', () async {
    api.respond = (step) async => step <= 2
        ? _keysReply('hello')
        : const AiReply(text: 'Original input inspected');
    await controller.ask('Enter hello once');
    await controller.approve();
    await controller.approve();

    expect(terminal.writes, hasLength(1));
    expect(terminal.writes.single.keys.single.text, 'hello');
    expect(controller.pending, isNull);
    expect(_lastToolResult(api)['operation_replayed'], isTrue);
  });

  test(
    'same API ID with changed parameters is refused with the original receipt',
    () async {
      api.respond = (step) async => switch (step) {
        1 => commandReply('touch first', id: 'same-operation'),
        2 => commandReply('touch different', id: 'same-operation'),
        _ => const AiReply(text: 'Conflict inspected'),
      };
      await controller.ask('Create the first file');
      await controller.approve();
      await controller.approve();

      expect(terminal.writes.map((action) => action.command), ['touch first']);
      expect(controller.pending, isNull);
      final conflict = _lastToolResult(api);
      expect(conflict['error'], 'operation_id_conflict');
      expect(
        conflict['original_result'],
        containsPair('submission_id', 'submission-1'),
      );
      expect(
        controller.transcript.where((entry) => entry.action != null),
        hasLength(1),
      );
    },
  );

  test(
    'a fresh API ID may intentionally execute the same command again',
    () async {
      api.respond = (step) async => step <= 2
          ? commandReply('pwd', id: 'operation-$step')
          : const AiReply(text: 'Two separate operations observed');
      await controller.ask('Check twice');
      await controller.approve();
      expect(terminal.writes, hasLength(1));
      expect(controller.pending?.id, 'operation-2');
      await controller.approve();

      expect(terminal.writes.map((action) => action.id), [
        'operation-1',
        'operation-2',
      ]);
      expect(
        controller.transcript
            .where((entry) => entry.submissionId != null)
            .map((entry) => entry.submissionId),
        ['submission-1', 'submission-2'],
      );
    },
  );

  test(
    'JSON parameter order does not turn a repeated operation into a conflict',
    () async {
      api.respond = (step) async => switch (step) {
        1 => commandReply('pwd', id: 'same-json'),
        2 => AiReply(
          text: '',
          action: AiAction.fromToolCall({
            'id': 'same-json',
            'function': {
              'name': 'run_command',
              'arguments': '{"reason":"Inspect files","command":"pwd"}',
            },
          }),
        ),
        _ => const AiReply(text: 'Same operation observed'),
      };
      await controller.ask('Check the directory');
      await controller.approve();

      expect(terminal.writes, hasLength(1));
      expect(_lastToolResult(api)['error'], isNull);
      expect(_lastToolResult(api)['operation_replayed'], isTrue);
    },
  );

  test('a conflict cannot replace the cached original result', () async {
    api.respond = (step) async => switch (step) {
      1 || 3 => commandReply('pwd', id: 'stable-operation'),
      2 => _keysReply('different input', id: 'stable-operation'),
      _ => const AiReply(text: 'Original receipt recovered'),
    };
    await controller.ask('Check the directory once');
    await controller.approve();

    expect(terminal.writes, hasLength(1));
    final conflict =
        jsonDecode(api.requests[2].last['content']! as String) as Map;
    expect(conflict['error'], 'operation_id_conflict');
    final replay = _lastToolResult(api);
    expect(replay['error'], isNull);
    expect(replay['submission_id'], 'submission-1');
    expect(replay['block_id'], 'block-1');
  });

  test(
    'host editing executes one version and retry preserves its actual receipt',
    () async {
      api.respond = (step) async => step <= 2
          ? commandReply('touch original', id: 'edited-operation')
          : const AiReply(text: 'Edited action observed');
      await controller.ask('Create the requested file');
      controller.editPendingCommand(
        'touch edited',
        revision: controller.proposalRevision,
      );
      await controller.approve();

      expect(terminal.writes.single.command, 'touch edited');
      expect(
        controller.transcript
            .where((entry) => entry.action != null)
            .map((entry) => entry.state),
        [AiEntryState.revoked, AiEntryState.accepted],
      );
      final approved = _lastToolResult(api)['approved_action']! as Map;
      final function = approved['function']! as Map;
      expect(
        jsonDecode(function['arguments']! as String),
        containsPair('command', 'touch edited'),
      );
      expect(_lastToolResult(api)['submission_id'], 'submission-1');
    },
  );

  test(
    'a rejected operation remains rejected when the API repeats it',
    () async {
      api.respond = (step) async => step <= 2
          ? commandReply('touch declined', id: 'declined-operation')
          : const AiReply(text: 'Declined action inspected');
      await controller.ask('Propose a file creation');
      controller.reject();
      await controller.ask('Explain the original proposal');
      await controller.approve();

      expect(terminal.writes, isEmpty);
      expect(controller.pending, isNull);
      expect(_lastToolResult(api)['state'], 'rejected');
      expect(_lastToolResult(api)['cancelled'], isTrue);
    },
  );

  test(
    'supplement keeps operation identity while a new task has its own IDs',
    () async {
      api.respond = (step) async => step.isOdd
          ? commandReply('pwd', id: 'provider-operation')
          : const AiReply(text: 'Directory observed');
      await controller.ask('Check the directory');
      final originalTask = controller.taskId;
      await controller.approve();
      await controller.supplement('Keep the original directory constraint');
      expect(controller.taskId, originalTask);
      expect(terminal.writes, hasLength(1));
      expect(controller.pending, isNull);
      expect(_lastToolResult(api)['operation_replayed'], isTrue);

      controller.newTask();
      await controller.ask('Check in a separate task');
      expect(controller.pending?.id, 'provider-operation');
      await controller.approve();
      expect(terminal.writes, hasLength(2));
      expect(
        controller.transcript
            .where((entry) => entry.action != null)
            .single
            .submissionId,
        'submission-2',
      );

      controller.selectTask(originalTask);
      await controller.refreshContext();
      await controller.ask('Inspect the first task again');
      expect(terminal.writes, hasLength(2));
      expect(_lastToolResult(api)['submission_id'], 'submission-1');
    },
  );

  test(
    'a lost receipt is reconciled on the original operation before retry',
    () async {
      api.respond = (step) async => step <= 2
          ? commandReply('touch once', id: 'uncertain-operation')
          : const AiReply(text: 'Original receipt observed');
      terminal.loseNextReceipt = true;
      await controller.ask('Create the file once');
      await controller.approve();
      expect(controller.hasUnresolvedSubmission, isTrue);
      expect(controller.canResume, isFalse);

      await controller.refreshContext();
      expect(controller.hasUnresolvedSubmission, isFalse);
      await controller.resume();

      expect(terminal.writes, hasLength(1));
      final replay = _lastToolResult(api);
      expect(replay['state'], 'accepted');
      expect(replay['submission_id'], 'submission-1');
      expect(replay['block_id'], 'block-1');
      expect(controller.pending, isNull);
    },
  );

  test(
    'replayed evidence retains its source after explicit target change',
    () async {
      terminal.context = const AiTerminalContext(
        sessionId: 'one',
        contextId: 'root',
        guard: 'original-guard',
        screen: 'Original screen',
        cwd: '/tmp',
        canRunCommand: true,
        readyLease: 'original-lease',
        lastBlock: AiBlockContext(
          id: 'original-source',
          command: 'pwd',
          output: '/tmp\n',
          exitCode: 0,
          cwd: '/tmp',
          outputEndLine: 1,
        ),
      );
      api.respond = (step) async => switch (step) {
        1 || 3 => commandReply('pwd', id: 'original-operation'),
        2 => throw const AiFailure('network'),
        _ => const AiReply(text: 'Original evidence inspected'),
      };
      await controller.ask('Observe once');
      await controller.approve();
      terminal.context = const AiTerminalContext(
        sessionId: 'two',
        contextId: 'root',
        guard: 'new-guard',
        screen: 'New screen',
        cwd: '/tmp',
        canRunCommand: true,
        readyLease: 'new-lease',
      );
      await controller.refreshContext();
      await controller.resume(useCurrentTarget: true);

      expect(terminal.writes, hasLength(1));
      expect(_lastToolResult(api)['source_session_id'], 'one');
      final supplied = controller.transcript.last.suppliedEvidence!;
      expect(
        supplied
            .where((range) => range.id == 'original-source')
            .map((range) => range.sessionId)
            .toSet(),
        {'one'},
      );
      expect(
        controller.transcript
            .where((entry) => entry.action != null)
            .single
            .target
            ?.sessionId,
        'one',
      );
    },
  );

  test(
    'a later human action ID collision cannot replace the API receipt',
    () async {
      api.respond = (step) async => step.isOdd
          ? commandReply('pwd', id: 'human-5')
          : const AiReply(text: 'Directory observed');
      await controller.ask('Observe the directory');
      await controller.approve();
      await controller.runUserCommand('echo manual');
      expect(terminal.writes.last.id, 'human-5');
      expect(terminal.writes, hasLength(2));

      await controller.ask('Inspect the original AI operation');
      expect(terminal.writes, hasLength(2));
      expect(_lastToolResult(api)['submission_id'], 'submission-1');
      expect(_lastToolResult(api)['block_id'], 'block-1');
    },
  );
}
