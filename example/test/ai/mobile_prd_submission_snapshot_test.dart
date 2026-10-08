import 'dart:async';
import 'dart:convert';

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import 'terminal_ai_test.dart' show FakeApi, FakeTerminal, MemoryAiStore;

class _PendingContextRead {
  final started = Completer<void>();
  final result = Completer<AiTerminalContext>();
}

class _DelayedContextTerminal extends FakeTerminal {
  _PendingContextRead? _nextRead;

  _PendingContextRead pauseNextRead() {
    assert(_nextRead == null, 'Only one context read can be paused at a time.');
    return _nextRead = _PendingContextRead();
  }

  @override
  Future<AiTerminalContext> readContext() {
    final pending = _nextRead;
    _nextRead = null;
    if (pending == null) return super.readContext();
    pending.started.complete();
    return pending.result.future;
  }
}

AiBlockContext _source({
  String id = 'failed-command',
  int sourceBase = 100,
  int startLine = 2,
  String output = 'Original failure evidence',
}) => AiBlockContext(
  id: id,
  command: 'make check',
  output: output,
  exitCode: 1,
  cwd: '/tmp',
  sourceSessionId: 'one',
  sourceContextId: 'root',
  sourceLineBase: sourceBase,
  outputStartLine: startLine,
  outputEndLine: startLine + 1,
  totalLines: 12,
);

Map<String, Object?> _sentUserRequest(FakeApi api) {
  final message = api.requests.single.lastWhere(
    (message) => message['role'] == 'user',
  );
  return jsonDecode(message['content']! as String) as Map<String, Object?>;
}

List<Map<String, Object?>> _sentSources(FakeApi api) {
  final sources = _sentUserRequest(api)['selected_blocks'];
  return sources == null
      ? const []
      : (sources as List<Object?>).cast<Map<String, Object?>>();
}

void main() {
  group('$TerminalAiController mobile PRD submission snapshot', () {
    late AiSettingsController settings;
    late _DelayedContextTerminal terminal;
    late FakeApi api;
    late TerminalAiController controller;
    late AiBlockContext originalSource;

    setUp(() async {
      settings = AiSettingsController(MemoryAiStore());
      await settings.loaded;
      terminal = _DelayedContextTerminal();
      api = FakeApi()
        ..respond = (_) async => const AiReply(text: 'Evidence reviewed.');
      controller = TerminalAiController(
        settings: settings,
        terminal: terminal,
        api: api,
      );
      originalSource = _source();
      await controller.refreshContext();
    });

    tearDown(() {
      controller.dispose();
      settings.dispose();
    });

    group('ask while reading terminal context', () {
      test(
        'sends and clears an unchanged draft and its original source',
        () async {
          controller.setDraft('Explain this failure');
          controller.attachContext(originalSource);
          final pending = terminal.pauseNextRead();

          final turn = controller.ask(controller.draft);
          await pending.started.future;
          pending.result.complete(terminal.context);
          await turn;

          expect(_sentUserRequest(api)['request'], 'Explain this failure');
          expect(_sentSources(api), [originalSource.toJson()]);
          expect(controller.draft, isEmpty);
          expect(controller.attachments, isEmpty);
          expect(terminal.writes, isEmpty);
        },
      );

      test(
        'sends the original request without clearing a newly edited draft',
        () async {
          controller.setDraft('Explain this failure');
          controller.attachContext(originalSource);
          final pending = terminal.pauseNextRead();

          final turn = controller.ask(controller.draft);
          await pending.started.future;
          controller.setDraft('Keep this next question for later');
          pending.result.complete(terminal.context);
          await turn;

          expect(_sentUserRequest(api)['request'], 'Explain this failure');
          expect(_sentSources(api), [originalSource.toJson()]);
          expect(controller.draft, 'Keep this next question for later');
          expect(
            controller.transcript
                .where((entry) => entry.role == 'user')
                .single
                .text,
            'Explain this failure',
          );
          expect(terminal.writes, isEmpty);
        },
      );

      test(
        'does not clear a later edit that returns to the same text',
        () async {
          controller.setDraft('Explain this failure');
          final pending = terminal.pauseNextRead();

          final turn = controller.ask(controller.draft);
          await pending.started.future;
          controller.setDraft('A different next question');
          controller.setDraft('Explain this failure');
          pending.result.complete(terminal.context);
          await turn;

          expect(_sentUserRequest(api)['request'], 'Explain this failure');
          expect(controller.draft, 'Explain this failure');
          expect(terminal.writes, isEmpty);
        },
      );

      test(
        'keeps a removed attachment in the already submitted request',
        () async {
          controller.setDraft('Explain this failure');
          controller.attachContext(originalSource);
          final pending = terminal.pauseNextRead();

          final turn = controller.ask(controller.draft);
          await pending.started.future;
          controller.removeAttachment(0);
          pending.result.complete(terminal.context);
          await turn;

          expect(_sentSources(api), [originalSource.toJson()]);
          expect(
            controller.transcript
                .where((entry) => entry.role == 'user')
                .single
                .contexts,
            [originalSource],
          );
          expect(controller.attachments, isEmpty);
          expect(terminal.writes, isEmpty);
        },
      );

      test(
        'keeps a newly attached source unsent for the next request',
        () async {
          controller.setDraft('Explain this failure');
          controller.attachContext(originalSource);
          final laterSource = _source(id: 'next-command');
          final pending = terminal.pauseNextRead();

          final turn = controller.ask(controller.draft);
          await pending.started.future;
          controller.attachContext(laterSource);
          pending.result.complete(terminal.context);
          await turn;

          expect(_sentSources(api), [originalSource.toJson()]);
          expect(controller.attachments, [laterSource]);
          expect(terminal.writes, isEmpty);
        },
      );

      test(
        'does not replace sent evidence with a newer range of the same block',
        () async {
          controller.setDraft('Explain this failure');
          controller.attachContext(originalSource);
          final replacement = _source(
            sourceBase: 300,
            startLine: 7,
            output: 'A different retained source range',
          );
          final pending = terminal.pauseNextRead();

          final turn = controller.ask(controller.draft);
          await pending.started.future;
          controller.removeAttachment(0);
          controller.attachContext(replacement);
          pending.result.complete(terminal.context);
          await turn;

          expect(_sentSources(api), [originalSource.toJson()]);
          expect(controller.attachments, [replacement]);
          expect(terminal.writes, isEmpty);
        },
      );

      test(
        'task switching cancels the old request without consuming either draft',
        () async {
          controller.setDraft('Original task question');
          controller.attachContext(originalSource);
          final originalTask = controller.taskId;
          final pending = terminal.pauseNextRead();

          final turn = controller.ask(controller.draft);
          await pending.started.future;
          controller.newTask();
          final nextTask = controller.taskId;
          final nextSource = _source(id: 'next-task-source');
          controller.setDraft('The next task draft');
          controller.attachContext(nextSource);
          pending.result.complete(terminal.context);
          await turn;

          expect(controller.taskId, nextTask);
          expect(controller.draft, 'The next task draft');
          expect(controller.attachments, [nextSource]);
          expect(controller.transcript, isEmpty);
          expect(api.requests, isEmpty);
          expect(terminal.writes, isEmpty);

          controller.selectTask(originalTask);
          await controller.refreshContext();
          expect(controller.draft, 'Original task question');
          expect(controller.attachments, [originalSource]);
          expect(controller.transcript, isEmpty);
        },
      );
    });

    group('removeAttachment', () {
      test(
        'keeps the same draft in AI intent after removing its last source',
        () {
          controller.setDraft('./script');
          controller.attachContext(originalSource);
          expect(controller.inputIntentDecision().intent, InputIntent.ai);
          expect(controller.inputIntentChoice, InputIntentChoice.automatic);

          controller.removeAttachment(0);

          expect(controller.draft, './script');
          expect(controller.attachments, isEmpty);
          expect(controller.inputIntentDecision().intent, InputIntent.ai);
          expect(api.requests, isEmpty);
          expect(terminal.writes, isEmpty);
        },
      );
    });
  });
}
