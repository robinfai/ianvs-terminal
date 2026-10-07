import 'dart:async';
import 'dart:convert';

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'terminal_ai_test.dart'
    show FakeApi, FakeTerminal, MemoryAiStore, commandReply, contextFor;

const source = AiBlockContext(
  id: 'block-7',
  command: 'make',
  output: 'failure at line 12',
  exitCode: 1,
  cwd: '/tmp',
  sourceSessionId: 'one',
  sourceContextId: 'root',
  sourceLineBase: 100,
  outputStartLine: 320,
  outputEndLine: 480,
  totalLines: 480,
);

class RangeTerminal extends FakeTerminal
    implements AiBlockReader, AiSubmissionInspector {
  final reads = <(String, int, int)>[];
  int sourceBase = 100;
  String? forcedSubmission;
  Map<String, Object?> receipt = {'outcome': 'unknown'};
  final inspections = <String>[];
  @override
  String? submissionFor(String actionId) => forcedSubmission;
  @override
  Future<Map<String, Object?>> inspectSubmission(String id) async {
    inspections.add(id);
    return receipt;
  }

  @override
  Future<AiBlockContext> readBlockRange(
    String blockId, {
    required int startLine,
    required int lineCount,
    required AiTerminalContext expected,
  }) async {
    reads.add((blockId, startLine, lineCount));
    return AiBlockContext(
      id: blockId,
      command: 'make',
      output: 'earlier evidence',
      exitCode: 1,
      cwd: '/tmp',
      sourceLineBase: sourceBase,
      outputStartLine: startLine,
      outputEndLine: startLine + lineCount,
      totalLines: 480,
    );
  }
}

AiAction rangeAction(String id, {Object start = 0, Object count = 50}) =>
    AiAction.fromToolCall({
      'id': 'read-range',
      'function': {
        'name': 'read_block',
        'arguments': jsonEncode({
          'block_id': id,
          'start_line': start,
          'line_count': count,
          'reason': 'Read earlier evidence',
        }),
      },
    });

void main() {
  late AiSettingsController settings;
  late RangeTerminal terminal;
  late FakeApi api;
  late TerminalAiController controller;
  setUp(() async {
    settings = AiSettingsController(MemoryAiStore());
    await settings.loaded;
    terminal = RangeTerminal();
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
    'selections with equal outer bounds retain distinct inner ranges',
    () async {
      AiBlockContext selected(int middle) => AiBlockContext(
        id: 'source',
        command: 'read',
        output: 'a\nb\nc',
        exitCode: 0,
        cwd: '/tmp',
        outputStartLine: 0,
        outputEndLine: 10,
        sourceLineBase: 100,
        outputRanges: [
          const AiBlockOutputRange(startLine: 0, endLine: 1, output: 'a'),
          AiBlockOutputRange(
            startLine: middle,
            endLine: middle + 1,
            output: 'b',
          ),
          const AiBlockOutputRange(startLine: 9, endLine: 10, output: 'c'),
        ],
      );
      controller.attachContext(selected(3));
      controller.attachContext(selected(5));
      expect(controller.attachments, hasLength(2));
      api.respond = (_) async => const AiReply(text: 'Read selected ranges');
      await controller.ask('Compare these two explicit selections');
      final content =
          jsonDecode(api.requests.last.last['content']! as String) as Map;
      final blocks = content['selected_blocks'] as List;
      expect(
        (blocks[0] as Map)['output_ranges'],
        selected(3).toJson()['output_ranges'],
      );
      expect(
        (blocks[1] as Map)['output_ranges'],
        selected(5).toJson()['output_ranges'],
      );
      expect(terminal.writes, isEmpty);
    },
  );

  test(
    'unknown submission recovery queries its original receipt and never writes again',
    () async {
      terminal.forcedSubmission = 'original-1';
      terminal.execution = Completer();
      await controller.ask('Inspect once');
      final approval = controller.approve();
      terminal.execution!.completeError(const AiFailure('submission_unknown'));
      await approval;
      final event = controller.transcript.last;
      expect(event.submissionId, 'original-1');
      expect(event.state, AiEntryState.unknown);
      terminal.receipt = {'outcome': 'accepted', 'blockId': 'original-output'};
      await controller.refreshContext();
      expect(controller.transcript.last.id, event.id);
      expect(controller.transcript.last.blockId, 'original-output');
      api.respond = (_) async =>
          const AiReply(text: 'Checked the original result');
      await controller.resume();
      expect(terminal.inspections, ['original-1']);
      expect(terminal.writes, hasLength(1));
      expect(api.requests.last.last['content'], contains('original-output'));
    },
  );

  test(
    'pause sends no input; interrupt sends one guarded Ctrl+C without inference',
    () async {
      terminal.context = const AiTerminalContext(
        sessionId: 'one',
        contextId: 'root',
        guard: 'running-1',
        screen: 'working',
        cwd: '/tmp',
        runningCommand: 'sleep 30',
      );
      final reply = Completer<AiReply>();
      api.respond = (_) => reply.future;
      final turn = controller.ask('Observe only');
      await Future<void>.delayed(Duration.zero);
      controller.takeOver();
      expect(terminal.writes, isEmpty);
      await Future.wait([
        controller.interruptCommand(),
        controller.interruptCommand(),
      ]);
      expect(terminal.writes, hasLength(1));
      expect(terminal.writes.single.keys.single.key, 'CTRL_C');
      expect(api.requests, hasLength(1));
      reply.complete(const AiReply(text: 'late reply'));
      await turn;
      expect(controller.transcript.any((e) => e.text == 'late reply'), isFalse);
    },
  );

  test(
    'target chosen in recovery cannot authorize a newer unseen target',
    () async {
      await controller.ask('Inspect');
      controller.takeOver();
      terminal.context = contextFor(guard: 'changed-again');
      await controller.resume(
        useCurrentTarget: true,
        expectedTargetGuard: 'shown-in-dialog',
      );
      expect(controller.error, 'stale_context');
      expect(api.requests, hasLength(1));
      expect(terminal.writes, isEmpty);
    },
  );

  test(
    'task switch preserves draft, attachments, history and revokes approval',
    () async {
      await controller.ask('Diagnose only; do not edit files');
      final first = controller.taskId;
      controller.setDraft('Explain the next step');
      controller.attachContext(source);
      controller.readingOffset = 245;
      controller.readingAnchor = (id: 'entry-2', offset: 45);
      controller.newTask();
      expect(controller.transcript, isEmpty);
      expect(controller.attachments, isEmpty);
      expect(controller.draft, isEmpty);
      controller.setDraft('Independent task');
      controller.selectTask(first);
      await Future<void>.delayed(Duration.zero);
      expect(controller.draft, 'Explain the next step');
      expect(controller.attachments.single, source);
      expect(controller.readingOffset, 245);
      expect(controller.readingAnchor, (id: 'entry-2', offset: 45));
      expect(
        controller.transcript.first.text,
        'Diagnose only; do not edit files',
      );
      expect(controller.transcript.last.state, AiEntryState.revoked);
      expect(controller.pending, isNull);
      expect(api.requests.length, 1);
      expect(terminal.writes, isEmpty);
    },
  );

  test('late model response cannot enter a newly selected task', () async {
    final response = Completer<AiReply>();
    api.respond = (_) => response.future;
    final turn = controller.ask('First task');
    await Future<void>.delayed(Duration.zero);
    controller.newTask();
    controller.setDraft('Second task');
    response.complete(commandReply('touch should-not-run'));
    await turn;
    expect(controller.transcript, isEmpty);
    expect(controller.pending, isNull);
    expect(controller.draft, 'Second task');
    expect(terminal.writes, isEmpty);
  });

  test('refresh cannot bless a proposal with a new guard', () async {
    await controller.ask('Inspect files');
    terminal.context = contextFor(guard: 'new-lease');
    await controller.refreshContext();
    await controller.approve();
    expect(controller.canApprove, isFalse);
    expect(controller.transcript.last.state, AiEntryState.revoked);
    expect(terminal.writes, isEmpty);
  });

  test(
    'edit requires review of a new revision and submits only that command',
    () async {
      await controller.ask('Inspect files');
      final old = controller.proposalRevision;
      controller.editPendingCommand('ls -a', revision: old);
      expect(controller.proposalRevision, greaterThan(old));
      await controller.approve(revision: old);
      expect(terminal.writes, isEmpty);
      api.respond = (_) async => const AiReply(text: 'Observed result');
      final revision = controller.proposalRevision;
      await Future.wait([
        controller.approve(revision: revision),
        controller.approve(revision: revision),
      ]);
      expect(terminal.writes.single.command, 'ls -a');
      final entry = controller.transcript.singleWhere((e) => e.action != null);
      expect(entry.state, AiEntryState.accepted);
      expect(entry.action!.command, 'ls -a');
      final result = api.requests.last.singleWhere((m) => m['role'] == 'tool');
      expect(result['content'], contains('ls -a'));
    },
  );

  test(
    'sent contexts are frozen and removing a draft attachment cannot erase evidence',
    () async {
      controller.attachContext(source);
      api.respond = (_) async => const AiReply(text: 'Analysis');
      await controller.ask('Explain this range');
      expect(controller.attachments, isEmpty);
      expect(controller.transcript.first.contexts.single, source);
      controller.attachContext(source);
      controller.removeAttachment(0);
      expect(
        controller.transcript.first.contexts.single.output,
        'failure at line 12',
      );
      final request =
          jsonDecode(api.requests.single.last['content']! as String) as Map;
      expect(
        ((request['selected_blocks'] as List).single
            as Map)['source_session_id'],
        'one',
      );
    },
  );

  test(
    'supplement cancels stale inference, preserves goal, and writes no terminal input',
    () async {
      final response = Completer<AiReply>();
      api.respond = (n) => n == 1
          ? response.future
          : Future.value(const AiReply(text: 'Read-only analysis'));
      final turn = controller.ask('Diagnose service');
      await Future<void>.delayed(Duration.zero);
      await controller.supplement('Do not restart or modify files');
      response.complete(commandReply('systemctl restart api'));
      await turn;
      expect(controller.pending, isNull);
      expect(jsonEncode(api.requests.last), contains('Diagnose service'));
      expect(
        jsonEncode(api.requests.last),
        contains('Do not restart or modify files'),
      );
      expect(controller.transcript.last.text, 'Read-only analysis');
      expect(terminal.writes, isEmpty);
    },
  );

  test('resume preserves unsent draft and attachments', () async {
    await controller.ask('Diagnose service');
    controller.takeOver();
    controller.setDraft('Unsent follow-up');
    controller.attachContext(source);
    api.respond = (_) async => const AiReply(text: 'Observed current state');
    await controller.resume();
    expect(controller.draft, 'Unsent follow-up');
    expect(controller.attachments.single, source);
    expect(
      controller.transcript.lastWhere((e) => e.role == 'user').contexts,
      isEmpty,
    );
    expect(terminal.writes, isEmpty);
  });

  test(
    'changed SSH node requires explicit target choice before resuming',
    () async {
      await controller.ask('Diagnose service');
      controller.takeOver();
      terminal.context = const AiTerminalContext(
        sessionId: 'one',
        contextId: 'node-b',
        guard: 'node-b:1',
        cwd: '/tmp',
        screen: 'node-b>',
        canRunCommand: true,
      );
      await controller.refreshContext();
      await controller.resume();
      expect(controller.error, 'target_changed');
      expect(api.requests.length, 1);
      api.respond = (_) async => const AiReply(text: 'Observed new target');
      await controller.resume(useCurrentTarget: true);
      expect(api.requests.length, 2);
      expect(controller.targetChanged, isFalse);
      expect(terminal.writes, isEmpty);
    },
  );

  test(
    'evicted source rows cannot silently replace a frozen evidence range',
    () async {
      controller.attachContext(source);
      terminal.sourceBase = 180;
      api.respond = (n) async => n == 1
          ? AiReply(
              text: '',
              action: rangeAction('block-7', start: 10, count: 25),
            )
          : const AiReply(text: 'Original range is unavailable');
      await controller.ask('Read the earlier failure');
      final result = api.requests.last.lastWhere(
        (entry) => entry['role'] == 'tool',
      );
      final content = jsonDecode(result['content']! as String) as Map;
      expect(content['error'], 'block_range_evicted');
      expect(content.containsKey('block'), isFalse);
      expect(terminal.writes, isEmpty);
    },
  );

  test(
    'read block reads an attached range without approval or PTY input',
    () async {
      controller.attachContext(source);
      api.respond = (n) async => n == 1
          ? AiReply(
              text: '',
              action: rangeAction('block-7', start: 10, count: 25),
            )
          : const AiReply(text: 'Found earlier evidence');
      await controller.ask('Read the earlier failure');
      expect(terminal.reads, [('block-7', 10, 25)]);
      expect(terminal.writes, isEmpty);
      expect(controller.pending, isNull);
      expect(api.requests.last.last['content'], contains('earlier evidence'));
    },
  );

  test(
    'read block cannot discover unrelated or cross-session evidence by guessed id',
    () async {
      api.respond = (n) async => n == 1
          ? AiReply(text: '', action: rangeAction('other-session-block'))
          : const AiReply(text: 'Need selected context');
      await controller.ask('Inspect output');
      expect(terminal.reads, isEmpty);
      expect(terminal.writes, isEmpty);
      expect(api.requests.last.last['content'], contains('block_unavailable'));
    },
  );

  test('range parser rejects unbounded and fractional ranges', () {
    for (final (start, count) in [(-1, 20), (0, 501), (0, 0), (0.5, 1)]) {
      expect(
        () => rangeAction('block-7', start: start, count: count),
        throwsA(isA<AiInvalidAction>()),
      );
    }
  });

  test(
    'unknown submission stays visible and resume does not resend it',
    () async {
      await controller.ask('Inspect files');
      terminal.execution = Completer<Map<String, Object?>>();
      final run = controller.approve();
      await Future<void>.delayed(Duration.zero);
      terminal.execution!.completeError(const AiFailure('submission_unknown'));
      await run;
      expect(controller.transcript.last.state, AiEntryState.unknown);
      api.respond = (_) async =>
          const AiReply(text: 'Inspect original submission; no retry');
      await controller.resume();
      expect(terminal.writes.length, 1);
      expect(controller.transcript.where((e) => e.action != null).length, 1);
    },
  );
}
