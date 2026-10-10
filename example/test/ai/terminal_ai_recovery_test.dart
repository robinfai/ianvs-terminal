import 'dart:async';
import 'dart:convert';

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'terminal_ai_tasks_test.dart' show source;
import 'terminal_ai_test.dart'
    show FakeApi, FakeTerminal, MemoryAiStore, commandReply;

class RecoveringTerminal extends FakeTerminal implements AiSubmissionInspector {
  bool disconnected = false;
  int reads = 0;
  Completer<AiTerminalContext>? contextRead;
  final inspected = <String>[];
  Map<String, Object?> receipt = {'outcome': 'unknown'};

  @override
  Future<AiTerminalContext> readContext() async {
    reads++;
    if (disconnected) throw const AiFailure('session_unavailable');
    return contextRead?.future ?? context;
  }

  @override
  String? submissionFor(String actionId) => 'original-submission';

  @override
  Future<Map<String, Object?>> inspectSubmission(String id) async {
    inspected.add(id);
    return receipt;
  }
}

void main() {
  late AiSettingsController settings;
  late RecoveringTerminal terminal;
  late FakeApi api;
  late TerminalAiController controller;
  setUp(() async {
    settings = AiSettingsController(MemoryAiStore());
    await settings.loaded;
    terminal = RecoveringTerminal();
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
    'disconnect revokes approval; recovery keeps task, draft and attachments',
    () async {
      await controller.ask('Inspect without modifying files');
      final original = controller.transcript.last;
      controller.setDraft('Do not lose this follow-up');
      controller.attachContext(source);
      terminal.disconnected = true;
      await controller.refreshContext();
      expect(controller.canApprove, false);
      expect(controller.transcript.last.state, AiEntryState.revoked);
      await controller.approve();
      expect(terminal.writes, isEmpty);
      expect(controller.canResume, false);
      terminal.disconnected = false;
      await controller.refreshContext();
      expect(controller.canResume, true);
      expect(controller.transcript.last.id, original.id);
      expect(controller.draft, 'Do not lose this follow-up');
      expect(controller.attachments, [source]);
      expect(api.requests, hasLength(1));
      api.respond = (_) async => const AiReply(text: 'Fresh state inspected');
      await Future.wait([controller.resume(), controller.resume()]);
      expect(api.requests, hasLength(2));
      expect(terminal.writes, isEmpty);
      expect(controller.draft, 'Do not lose this follow-up');
    },
  );

  test('disconnect cancels inference and ignores its late proposal', () async {
    final reply = Completer<AiReply>();
    api.respond = (_) => reply.future;
    final turn = controller.ask('Inspect files');
    await Future<void>.delayed(Duration.zero);
    terminal.disconnected = true;
    await controller.refreshContext();
    expect(api.cancellations.single.isCancelled, true);
    reply.complete(commandReply('late command'));
    await turn;
    expect(controller.pending, isNull);
    expect(terminal.writes, isEmpty);
  });

  test(
    'terminal recovery cannot erase an independent authentication error',
    () async {
      api.respond = (_) async => throw const AiFailure('authentication');
      await controller.ask('Inspect files');
      terminal.disconnected = true;
      await controller.refreshContext();
      terminal.disconnected = false;
      await controller.refreshContext();
      expect(controller.error, 'authentication');
      expect(controller.canResume, false);
      expect(terminal.writes, isEmpty);
    },
  );

  test(
    'unknown receipt blocks continuation until the original submission is checked',
    () async {
      await controller.ask('Run once');
      terminal.execution = Completer();
      final run = controller.approve();
      terminal.execution!.completeError(const AiFailure('submission_unknown'));
      await run;
      api.respond = (_) async => const AiReply(text: 'Resumed');
      await controller.resume();
      expect(api.requests, hasLength(1));
      await controller.refreshContext();
      expect(controller.canResume, false);
      expect(terminal.inspected, ['original-submission']);
      terminal.receipt = {'outcome': 'accepted', 'blockId': 'original-block'};
      await controller.refreshContext();
      expect(controller.transcript.last.blockId, 'original-block');
      expect(controller.canResume, true);
      await controller.resume();
      expect(terminal.writes, hasLength(1));
      expect(api.requests, hasLength(2));
    },
  );

  test(
    'disconnected native receipts can resolve acceptance without resuming',
    () async {
      await controller.ask('Run once');
      terminal.execution = Completer();
      final run = controller.approve();
      terminal.execution!.completeError(const AiFailure('submission_unknown'));
      await run;
      terminal.disconnected = true;
      terminal.receipt = {'outcome': 'accepted', 'blockId': 'retained-block'};
      controller.setDraft('Retained follow-up');
      await controller.refreshContext();
      expect(terminal.inspected, ['original-submission']);
      expect(controller.transcript.last.blockId, 'retained-block');
      expect(controller.transcript.last.state, AiEntryState.accepted);
      expect(controller.terminalError, 'session_unavailable');
      expect(controller.error, isNull);
      expect(controller.canResume, false);
      expect(controller.canApprove, false);
      expect(controller.draft, 'Retained follow-up');
      await controller.resume();
      await controller.approve();
      expect(terminal.writes, hasLength(1));
      expect(api.requests, hasLength(1));
    },
  );

  test(
    'supplement during submission is visibly deferred and sent only after explicit resume',
    () async {
      await controller.ask('Inspect once');
      terminal.execution = Completer();
      final executing = controller.approve();
      await Future<void>.delayed(Duration.zero);
      controller.attachContext(source);
      await controller.supplement('Do not restart or change any files');
      expect(controller.hasUnresolvedSubmission, isTrue);
      expect(controller.hasDeferredSupplement, isTrue);
      final saved = controller.transcript.singleWhere(
        (e) => e.state == AiEntryState.deferred,
      );
      expect(saved.text, 'Do not restart or change any files');
      expect(saved.contexts, [source]);
      expect(api.requests, hasLength(1));
      expect(terminal.writes, hasLength(1));
      expect(controller.draft, isEmpty);
      expect(controller.attachments, isEmpty);

      controller.setDraft('A newer unsent draft');
      await controller.resume();
      expect(api.requests, hasLength(1));
      terminal.receipt = {'outcome': 'accepted', 'blockId': 'original-block'};
      await controller.refreshContext();
      expect(controller.hasDeferredSupplement, isTrue);
      expect(api.requests, hasLength(1));

      api.respond = (_) async => const AiReply(text: 'Read-only follow-up');
      await controller.resume();
      final request =
          jsonDecode(api.requests.last.last['content']! as String) as Map;
      expect(request['saved_user_requirements'], [saved.text]);
      expect((request['selected_blocks'] as List).single, source.toJson());
      expect(
        request['original_submissions'].toString(),
        contains('original-block'),
      );
      expect(controller.hasDeferredSupplement, isFalse);
      expect(
        controller.transcript.singleWhere((e) => e.id == saved.id).state,
        AiEntryState.message,
      );
      expect(controller.draft, 'A newer unsent draft');
      terminal.execution!.complete({'status': 'input_sent'});
      await executing;
      expect(terminal.writes, hasLength(1));
      expect(api.requests, hasLength(2));
    },
  );

  test('discarding a saved requirement never sends it to the model', () async {
    await controller.ask('Inspect once');
    terminal.execution = Completer();
    final executing = controller.approve();
    await Future<void>.delayed(Duration.zero);
    await controller.supplement('An obsolete requirement');
    final saved = controller.transcript.last;
    controller.discardDeferredSupplement(saved.id);
    expect(controller.hasDeferredSupplement, isFalse);
    expect(controller.transcript.last.state, AiEntryState.revoked);
    terminal.receipt = {'outcome': 'accepted', 'blockId': 'original-block'};
    await controller.refreshContext();
    api.respond = (_) async => const AiReply(text: 'Observed current state');
    await controller.resume();
    expect(jsonEncode(api.requests.last), isNot(contains(saved.text)));
    terminal.execution!.complete({'status': 'input_sent'});
    await executing;
    expect(terminal.writes, hasLength(1));
  });

  test(
    'saved legacy evidence retains its source after a target change',
    () async {
      await controller.ask('Inspect once');
      terminal.execution = Completer();
      final executing = controller.approve();
      await Future<void>.delayed(Duration.zero);
      controller.attachContext(
        const AiBlockContext(
          id: 'old-output',
          command: 'make',
          output: 'original failure',
          exitCode: 1,
          cwd: '/tmp',
          outputEndLine: 1,
        ),
      );
      await controller.supplement('Explain this original output only');
      final saved = controller.transcript.last;
      expect(saved.contexts.single.sourceSessionId, 'one');
      terminal.receipt = {'outcome': 'accepted', 'blockId': 'original-block'};
      terminal.context = const AiTerminalContext(
        sessionId: 'new-session',
        contextId: 'new-node',
        guard: 'new-guard',
        screen: 'new>',
        cwd: '/new',
        canRunCommand: true,
      );
      await controller.refreshContext();
      api.respond = (_) async => const AiReply(text: 'Source retained');
      await controller.resume(
        useCurrentTarget: true,
        expectedTargetGuard: 'new-guard',
      );
      final request =
          jsonDecode(api.requests.last.last['content']! as String) as Map;
      final evidence = (request['selected_blocks'] as List).single as Map;
      expect(evidence['source_session_id'], 'one');
      expect(evidence['source_context_id'], 'root');
      expect(
        controller.transcript
            .singleWhere((e) => e.id == saved.id)
            .target
            ?.sessionId,
        'one',
      );
      terminal.execution!.complete({'status': 'input_sent'});
      await executing;
      expect(terminal.writes, hasLength(1));
    },
  );

  test(
    'ending follow-up retains unknown history and only a new task can start new work',
    () async {
      await controller.ask('Run once');
      final oldTask = controller.taskId;
      terminal.execution = Completer();
      final executing = controller.approve();
      terminal.execution!.completeError(const AiFailure('submission_unknown'));
      await executing;
      terminal.disconnected = true;
      await controller.refreshContext();
      final unknown = controller.transcript.last;
      expect(controller.canEndFollowUp, isTrue);
      controller.endFollowUp();
      expect(controller.followUpEnded, isTrue);
      expect(controller.hasUnresolvedSubmission, isTrue);
      expect(controller.transcript.last.id, unknown.id);
      expect(controller.canResume, isFalse);
      expect(controller.canApprove, isFalse);
      expect(controller.canRunUserCommand, isFalse);
      await controller.ask('Do not send this from the ended task');
      await controller.resume();
      await controller.approve();
      expect(api.requests, hasLength(1));
      expect(terminal.writes, hasLength(1));

      controller.newTask();
      expect(controller.followUpEnded, isFalse);
      expect(controller.transcript, isEmpty);
      expect(terminal.writes, hasLength(1));
      terminal.disconnected = false;
      api.respond = (_) async => const AiReply(text: 'Independent analysis');
      await controller.ask(
        'Inspect the current screen without running a command',
      );
      expect(api.requests, hasLength(2));
      expect(terminal.writes, hasLength(1));
      expect(jsonEncode(api.requests.last), isNot(contains('Run once')));
      controller.selectTask(oldTask);
      await Future<void>.delayed(Duration.zero);
      expect(controller.followUpEnded, isTrue);
      expect(controller.hasUnresolvedSubmission, isTrue);
      expect(controller.transcript.last.submissionId, unknown.submissionId);
      // Later evidence can correct the fact, but cannot reopen the old task.
      terminal.receipt = {'outcome': 'accepted', 'blockId': 'original-block'};
      await controller.refreshContext();
      expect(controller.transcript.last.state, AiEntryState.accepted);
      expect(controller.followUpEnded, isTrue);
      expect(controller.canResume, isFalse);
    },
  );

  test(
    'simultaneous terminal checks share one read and do not send input',
    () async {
      terminal.contextRead = Completer();
      final first = controller.refreshContext();
      final second = controller.refreshContext();
      expect(identical(first, second), true);
      expect(controller.checkingTerminal, true);
      await Future<void>.delayed(Duration.zero);
      expect(terminal.reads, 1);
      terminal.contextRead!.complete(terminal.context);
      await Future.wait([first, second]);
      expect(controller.checkingTerminal, false);
      expect(terminal.writes, isEmpty);
      expect(api.requests, isEmpty);
    },
  );

  test(
    'terminal failure during explicit interrupt can be checked without retry',
    () async {
      terminal.context = const AiTerminalContext(
        sessionId: 'one',
        contextId: 'root',
        guard: 'running',
        screen: 'working',
        runningCommand: 'sleep 30',
      );
      await controller.refreshContext();
      terminal.execution = Completer();
      final interrupt = controller.interruptCommand();
      terminal.execution!.completeError(const AiFailure('session_unavailable'));
      await interrupt;
      expect(controller.terminalError, 'session_unavailable');
      expect(controller.canInterrupt, false);
      expect(controller.error, isNull);
      await controller.refreshContext();
      expect(controller.terminalError, isNull);
      expect(terminal.writes, hasLength(1));
      expect(api.requests, isEmpty);
    },
  );

  test('late failed check cannot change the newly selected task', () async {
    terminal.contextRead = Completer();
    final check = controller.refreshContext();
    await Future<void>.delayed(Duration.zero);
    controller.newTask();
    controller.setDraft('New task draft');
    terminal.contextRead!.completeError(const AiFailure('session_unavailable'));
    await check;
    expect(controller.terminalError, isNull);
    expect(controller.draft, 'New task draft');
    expect(terminal.writes, isEmpty);
  });

  test(
    'takeover closes tool history and continues only after checking receipt',
    () async {
      await controller.ask('Inspect once');
      terminal.execution = Completer();
      final executing = controller.approve();
      await Future<void>.delayed(Duration.zero);
      controller.takeOver();
      await controller.ask('Explain current screen');
      expect(api.requests, hasLength(1));
      terminal.receipt = {'outcome': 'accepted', 'blockId': 'original-block'};
      await controller.refreshContext();
      api.respond = (_) async => const AiReply(text: 'Read existing result');
      await controller.ask(controller.draft);
      terminal.execution!.complete({'status': 'input_sent'});
      await executing;
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
      expect(terminal.writes, hasLength(1));
      expect(controller.canApprove, false);
    },
  );
}
