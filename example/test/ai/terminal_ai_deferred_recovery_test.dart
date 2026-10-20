import 'dart:async';
import 'dart:convert';

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/l10n/generated/app_localizations.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'terminal_ai_recovery_test.dart' show RecoveringTerminal;
import 'terminal_ai_tasks_test.dart' show source;
import 'terminal_ai_test.dart' show FakeApi, MemoryAiStore;

void main() {
  late AiSettingsController settings;
  late RecoveringTerminal terminal;
  late FakeApi api;
  late TerminalAiController controller;

  Future<void> prepare() async {
    settings = AiSettingsController(MemoryAiStore());
    await settings.loaded;
    terminal = RecoveringTerminal();
    api = FakeApi();
    controller = TerminalAiController(
      settings: settings,
      terminal: terminal,
      api: api,
    );
    await controller.ask('Run original command once');
    terminal.execution = Completer();
    final submitted = controller.approve();
    terminal.execution!.completeError(const AiFailure('submission_unknown'));
    await submitted;
    api.respond = (_) async => const AiReply(text: 'Fresh result inspected');
  }

  tearDown(() {
    controller.dispose();
    settings.dispose();
  });

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildIanvsTerminalTheme(
          Brightness.light,
          platform: TargetPlatform.macOS,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TerminalAiWorkspace(controller: controller, onClose: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'source chips disclose partial and evicted output before opening',
    (tester) async {
      await prepare();
      controller.attachContext(
        const AiBlockContext(
          id: 'partial-output',
          command: 'make test',
          output: 'tail',
          exitCode: 1,
          cwd: '/tmp',
          outputStartLine: 10,
          outputEndLine: 12,
          totalLines: 12,
          evicted: true,
        ),
      );
      await mount(tester);
      expect(
        find.text('Partial output · Earlier output evicted'),
        findsOneWidget,
      );
      final chip = tester.widget<InputChip>(find.byType(InputChip));
      expect(chip.tooltip, contains('Partial output · Earlier output evicted'));
      expect(api.requests, hasLength(1));
      expect(terminal.writes, hasLength(1));
    },
  );

  testWidgets('unknown requirements wait for receipt and explicit continue', (
    tester,
  ) async {
    await prepare();
    controller.attachContext(source);
    await mount(tester);
    await tester.enterText(
      find.byKey(const Key('ai-prompt')),
      'Do not change any files',
    );
    expect(find.text('Save requirement'), findsOneWidget);
    await tap(tester, find.byKey(const Key('ai-send')));
    final saved = controller.transcript.singleWhere(
      (entry) => entry.state == AiEntryState.deferred,
    );
    expect(saved.text, 'Do not change any files');
    expect(saved.contexts, [source]);
    expect(controller.draft, isEmpty);
    expect(controller.attachments, isEmpty);
    expect(api.requests, hasLength(1));
    expect(terminal.writes, hasLength(1));
    expect(
      find.text(
        'Saved, not sent. Check the original submission, then explicitly continue.',
      ),
      findsOneWidget,
    );

    await tap(tester, find.byKey(const Key('ai-check-terminal')));
    expect(controller.hasUnresolvedSubmission, isTrue);
    expect(find.byKey(const Key('ai-resume')), findsNothing);
    terminal.receipt = {'outcome': 'accepted', 'blockId': 'original-block'};
    await tap(tester, find.byKey(const Key('ai-check-terminal')));
    expect(controller.hasDeferredSupplement, isTrue);
    expect(api.requests, hasLength(1));
    expect(find.byTooltip('Send saved requirements'), findsOneWidget);
    await tap(tester, find.byKey(const Key('ai-resume')));
    expect(
      api.requests.length,
      2,
      reason:
          '${controller.phase} / ${controller.error} / ${controller.canResume}',
    );
    expect(terminal.writes, hasLength(1));
    final request =
        jsonDecode(api.requests.last.last['content']! as String)
            as Map<String, Object?>;
    expect(request['saved_user_requirements'], ['Do not change any files']);
    expect(
      jsonEncode(request['selected_blocks']),
      contains('failure at line 12'),
    );
    expect(controller.hasDeferredSupplement, isFalse);
    expect(
      controller.transcript.singleWhere((entry) => entry.id == saved.id).state,
      AiEntryState.message,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'removing an unsent requirement preserves its record without sending',
    (tester) async {
      await prepare();
      await mount(tester);
      await tester.enterText(
        find.byKey(const Key('ai-prompt')),
        'Discard this constraint',
      );
      await tap(tester, find.byKey(const Key('ai-send')));
      final saved = controller.transcript.singleWhere(
        (entry) => entry.state == AiEntryState.deferred,
      );
      await tap(
        tester,
        find.byKey(ValueKey('ai-discard-supplement-${saved.id}')),
      );
      expect(
        controller.transcript
            .singleWhere((entry) => entry.id == saved.id)
            .state,
        AiEntryState.revoked,
      );
      expect(
        find.text('Saved requirement withdrawn; it was not sent.'),
        findsOneWidget,
      );
      terminal.receipt = {'outcome': 'accepted', 'blockId': 'original-block'};
      await tap(tester, find.byKey(const Key('ai-check-terminal')));
      await tap(tester, find.byKey(const Key('ai-resume')));
      expect(
        jsonEncode(api.requests.last),
        isNot(contains('Discard this constraint')),
      );
      expect(
        api.requests.length,
        2,
        reason:
            '${controller.phase} / ${controller.error} / ${controller.canResume}',
      );
      expect(terminal.writes, hasLength(1));
    },
  );

  testWidgets(
    'ending unknown follow-up keeps receipts and starts only an independent task',
    (tester) async {
      await prepare();
      final originalTask = controller.taskId;
      final originalEntry = controller.transcript.last;
      controller.setDraft('Keep this unsent draft');
      controller.attachContext(source);
      await mount(tester);
      final staleSend = tester
          .widget<FilledButton>(find.byKey(const Key('ai-send')))
          .onPressed!;
      await tap(tester, find.byKey(const Key('ai-end-follow-up')));
      staleSend();
      await tester.pumpAndSettle();
      expect(controller.followUpEnded, isTrue);
      expect(controller.hasUnresolvedSubmission, isTrue);
      expect(controller.transcript.last.id, originalEntry.id);
      expect(
        controller.transcript.last.submissionId,
        originalEntry.submissionId,
      );
      expect(controller.draft, 'Keep this unsent draft');
      expect(controller.attachments, [source]);
      expect(
        tester.widget<TextField>(find.byKey(const Key('ai-prompt'))).readOnly,
        isTrue,
      );
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('ai-send'))).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('ai-expand-draft')))
            .onPressed,
        isNull,
      );
      expect(
        find.byKey(ValueKey('ai-context-delete-${source.id}')).hitTestable(),
        findsNothing,
      );
      expect(find.byKey(const Key('ai-resume')), findsNothing);
      expect(api.requests, hasLength(1));
      expect(terminal.writes, hasLength(1));

      await tap(tester, find.byKey(const Key('ai-check-terminal')));
      expect(terminal.inspected, contains('original-submission'));
      expect(controller.hasUnresolvedSubmission, isTrue);
      await tap(tester, find.byKey(const Key('ai-new-independent-task')));
      expect(controller.taskId, isNot(originalTask));
      expect(controller.followUpEnded, isFalse);
      expect(controller.transcript, isEmpty);
      expect(controller.draft, isEmpty);
      expect(api.requests, hasLength(1));
      expect(terminal.writes, hasLength(1));
      await tap(tester, find.byTooltip('Session tasks'));
      await tap(
        tester,
        find.ancestor(
          of: find.text('Run original command once · Follow-up ended'),
          matching: find.byType(CheckedPopupMenuItem<String>),
        ),
      );
      expect(controller.taskId, originalTask);
      expect(controller.followUpEnded, isTrue);
      expect(controller.hasUnresolvedSubmission, isTrue);
      expect(controller.draft, 'Keep this unsent draft');
      expect(
        tester.widget<TextField>(find.byKey(const Key('ai-prompt'))).readOnly,
        isTrue,
      );

      terminal.receipt = {'outcome': 'accepted', 'blockId': 'original-block'};
      await controller.refreshContext();
      await tester.pumpAndSettle();
      expect(controller.hasUnresolvedSubmission, isFalse);
      expect(controller.followUpEnded, isTrue);
      expect(controller.transcript.last.blockId, 'original-block');
      expect(find.text('Follow-up ended · read-only'), findsOneWidget);
      expect(find.byKey(const Key('ai-new-independent-task')), findsOneWidget);
      expect(find.byKey(const Key('ai-resume')), findsNothing);
      expect(api.requests, hasLength(1));
      expect(terminal.writes, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}
