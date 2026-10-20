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

class _DeferredAiStore implements AiConfigurationStore {
  final loaded = Completer<AiConfiguration?>();
  @override
  Future<AiConfiguration?> read() => loaded.future;
  @override
  Future<void> write(AiConfiguration? configuration) async {}
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
        'reattaching the same source object preserves its new attachment',
        () async {
          controller.setDraft('Explain this failure');
          controller.attachContext(originalSource);
          final pending = terminal.pauseNextRead();

          final turn = controller.ask(controller.draft);
          await pending.started.future;
          controller.removeAttachment(0);
          controller.attachContext(originalSource);
          pending.result.complete(terminal.context);
          await turn;

          expect(_sentSources(api), [originalSource.toJson()]);
          expect(controller.attachments, [originalSource]);
          expect(terminal.writes, isEmpty);
        },
      );

      test(
        'copies an explicit source list before awaiting the terminal',
        () async {
          controller.setDraft('Explain these sources');
          final sources = [originalSource];
          final pending = terminal.pauseNextRead();

          final turn = controller.ask(controller.draft, blocks: sources);
          await pending.started.future;
          sources
            ..clear()
            ..add(_source(id: 'unrequested-source'));
          pending.result.complete(terminal.context);
          await turn;

          expect(_sentSources(api), [originalSource.toJson()]);
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
          expect(controller.canRunUserCommand, isFalse);
          expect(api.requests, isEmpty);
          expect(terminal.writes, isEmpty);
        },
      );

      test(
        'preview cannot release the retained AI intent or change the draft',
        () {
          controller.setDraft('./script');
          controller.attachContext(originalSource);
          controller.removeAttachment(0);
          final revision = controller.draftRevision;

          expect(
            controller
                .previewInputIntent('pwd', InputIntentChoice.command)
                .intent,
            InputIntent.command,
          );
          expect(controller.draft, './script');
          expect(controller.draftRevision, revision);
          expect(controller.inputIntentChoice, InputIntentChoice.automatic);
          expect(controller.inputIntentDecision().intent, InputIntent.ai);
          expect(controller.canRunUserCommand, isFalse);

          controller.chooseInputIntent(InputIntentChoice.command);
          expect(controller.inputIntentDecision().intent, InputIntent.command);
          expect(controller.canRunUserCommand, isTrue);
          expect(controller.draftRevision, revision);
          expect(terminal.writes, isEmpty);
        },
      );

      test(
        'retained AI intent stays with its task and clears with the draft',
        () async {
          controller.setDraft('./script');
          controller.attachContext(originalSource);
          controller.removeAttachment(0);
          final originalTask = controller.taskId;

          controller.newTask();
          await controller.refreshContext();
          controller.setDraft('./script');
          expect(controller.inputIntentDecision().intent, InputIntent.command);
          controller.selectTask(originalTask);
          await controller.refreshContext();
          expect(controller.inputIntentDecision().intent, InputIntent.ai);

          controller.setDraft('');
          controller.setDraft('./script');
          expect(controller.inputIntentDecision().intent, InputIntent.command);
          expect(terminal.writes, isEmpty);
        },
      );
    });

    group('draft revision', () {
      test(
        'tracks text edits and send cleanup independently for each task',
        () async {
          controller.setDraft('Original draft');
          final originalTask = controller.taskId;
          final originalRevision = controller.draftRevision;
          controller.setDraft('Original draft', composing: true);
          controller.setDraft('Original draft');
          controller.attachContext(originalSource);
          controller.removeAttachment(0);
          controller.chooseInputIntent(InputIntentChoice.ai);
          expect(controller.draftRevision, originalRevision);

          controller.newTask();
          expect(controller.draftRevision, 0);
          controller.setDraft('Other task draft');
          controller.selectTask(originalTask);
          await controller.refreshContext();
          expect(controller.draftRevision, originalRevision);

          controller.setDraft('Edited draft');
          controller.setDraft('Original draft');
          expect(controller.draftRevision, originalRevision + 2);
          final sentRevision = controller.draftRevision;
          await controller.ask(controller.draft);
          expect(controller.draft, isEmpty);
          expect(controller.draftRevision, sentRevision + 1);
          expect(terminal.writes, isEmpty);
        },
      );

      test(
        'an accepted human command does not clear a later same-text edit',
        () async {
          controller.setDraft('pwd');
          terminal.execution = Completer<Map<String, Object?>>();
          final submission = controller.runUserCommand(controller.draft);
          controller.setDraft('A later draft');
          controller.setDraft('pwd');
          final editedRevision = controller.draftRevision;
          terminal.execution!.complete({'status': 'input_sent'});
          await submission;

          expect(controller.draft, 'pwd');
          expect(controller.draftRevision, editedRevision);
          expect(terminal.writes, hasLength(1));
          expect(api.requests, isEmpty);
        },
      );
    });
  });

  group('$TerminalAiController while loading settings', () {
    late _DeferredAiStore store;
    late AiSettingsController settings;
    late FakeTerminal terminal;
    late FakeApi api;
    late TerminalAiController controller;

    setUp(() {
      store = _DeferredAiStore();
      settings = AiSettingsController(store);
      terminal = FakeTerminal();
      api = FakeApi()
        ..respond = (_) async => const AiReply(text: 'Evidence reviewed.');
      controller = TerminalAiController(
        settings: settings,
        terminal: terminal,
        api: api,
      );
    });

    tearDown(() async {
      controller.dispose();
      settings.dispose();
      if (!store.loaded.isCompleted) {
        store.loaded.complete(const AiConfiguration.mock());
      }
      await settings.loaded;
    });

    test(
      'freezes the clicked draft and sources before settings finish loading',
      () async {
        final originalSource = _source();
        final nextSource = _source(id: 'next-source');
        controller.setDraft('Clicked request');
        controller.attachContext(originalSource);

        final turn = controller.ask(controller.draft);
        controller.setDraft('Keep the next draft');
        controller.removeAttachment(0);
        controller.attachContext(nextSource);
        store.loaded.complete(const AiConfiguration.mock());
        await turn;

        expect(_sentUserRequest(api)['request'], 'Clicked request');
        expect(_sentSources(api), [originalSource.toJson()]);
        expect(controller.draft, 'Keep the next draft');
        expect(controller.attachments, [nextSource]);
        expect(terminal.writes, isEmpty);
      },
    );

    test(
      'a delayed settings load cannot send or consume a different task',
      () async {
        controller.setDraft('Old task request');
        final originalSource = _source();
        controller.attachContext(originalSource);
        final originalTask = controller.taskId;

        final turn = controller.ask(controller.draft);
        controller.newTask();
        final nextTask = controller.taskId;
        final nextSource = _source(id: 'next-task-source');
        controller.setDraft('New task draft');
        controller.attachContext(nextSource);
        store.loaded.complete(const AiConfiguration.mock());
        await turn;

        expect(controller.taskId, nextTask);
        expect(controller.draft, 'New task draft');
        expect(controller.attachments, [nextSource]);
        expect(controller.transcript, isEmpty);
        expect(api.requests, isEmpty);
        expect(terminal.writes, isEmpty);

        controller.selectTask(originalTask);
        await controller.refreshContext();
        expect(controller.draft, 'Old task request');
        expect(controller.attachments, [originalSource]);
        expect(controller.transcript, isEmpty);
      },
    );
  });
}
