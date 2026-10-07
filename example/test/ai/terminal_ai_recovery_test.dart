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
