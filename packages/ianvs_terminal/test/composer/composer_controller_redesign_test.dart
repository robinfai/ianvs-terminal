import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/src/composer/completion_models.dart';
import 'package:ianvs_terminal/src/composer/terminal_composer_controller.dart';
import 'package:ianvs_terminal/src/composer/terminal_composer_view.dart';

TerminalComposerController create({
  String text = 'echo original',
  ComposerSubmit? submit,
  CompletionProvider? provider,
}) => TerminalComposerController(
  targetId: 'redesign-session',
  text: text,
  submit: submit,
  provider: provider ?? (query, _) async => CompletionBatch(query, const []),
  // These cases trigger queries explicitly; keep background debounce out of
  // the order of submission, editing and response assertions.
  debounce: const Duration(days: 1),
);

void ready(TerminalComposerController model, {String lease = 'lease-1'}) =>
    model.updateShell(
      contextKey: lease,
      cwd: '/tmp/composer-redesign',
      ownership: ComposerOwnership.ready,
      lease: lease,
      dialect: 'zsh',
    );

void edit(TerminalComposerController model, String text) {
  model.editor.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
}

Future<void> settleQuery() => Future<void>.delayed(Duration.zero);

CompletionEdit candidate(CompletionQuery query, String text) => CompletionEdit(
  itemId: text,
  label: text,
  detail: 'Command',
  kind: 'command',
  source: 'catalog',
  start: 0,
  end: query.value.text.length,
  newText: text,
  cursor: text.length,
);

void main() {
  group('submission feedback', () {
    for (final outcome in [
      ComposerSubmissionOutcome.accepted,
      ComposerSubmissionOutcome.rejected,
    ]) {
      test('$outcome ends the pending transaction', () async {
        final model = create(submit: (_) async => outcome);
        addTearDown(model.dispose);
        ready(model);
        final original = model.editor.value;

        await model.run();

        expect(model.pendingSubmission, isNull);
        expect(model.canRecoverDraft, isFalse);
        expect(
          model.executionStatus,
          outcome == ComposerSubmissionOutcome.rejected
              ? 'submission_rejected'
              : '',
        );
        if (outcome == ComposerSubmissionOutcome.rejected) {
          expect(model.editor.value, original);
        }
        ready(model, lease: 'lease-2');
        edit(model, 'missing');
        model.completeOnTab();
        await settleQuery();
        final current = model.editor.value;
        final ownership = model.ownership;
        model.recoverDraft();
        expect(model.pendingSubmission, isNull);
        expect(model.editor.value, current);
        expect(model.ownership, ownership);
      });
    }

    for (final result in ['ok', 'unsupported_context', 'error']) {
      test(
        'unknown survives $result completion feedback and shell polling',
        () async {
          var submits = 0;
          final model = create(
            submit: (_) async {
              submits++;
              return ComposerSubmissionOutcome.unknown;
            },
            provider: (query, _) async {
              if (result == 'error') throw StateError('Completion unavailable');
              return CompletionBatch(query, const [], status: result);
            },
          );
          addTearDown(model.dispose);
          ready(model);
          await model.run();
          final pending = model.pendingSubmission;
          expect(model.status, 'unknown_outcome');

          edit(model, 'next draft');
          model.completeOnTab();
          await settleQuery();

          expect(model.status, 'unknown_outcome');
          expect(model.pendingSubmission, same(pending));
          expect(model.executionStatus, 'unknown_outcome');
          expect(model.completionStatus, switch (result) {
            'ok' => 'no_completions',
            'error' => 'completion_unavailable',
            _ => 'unsupported_context',
          });
          expect(model.canRecoverDraft, isTrue);
          expect(model.canRun, isFalse);
          ready(model, lease: 'lease-2');
          expect(model.ownership, ComposerOwnership.unknown);
          await model.run();
          expect(submits, 1);
          expect(model.status, 'unknown_outcome');
          expect(model.editor.text, 'next draft');
        },
      );
    }

    test(
      'unknown remains visible while querying and changing policy',
      () async {
        final responses = <Completer<CompletionBatch>>[];
        final queries = <CompletionQuery>[];
        final cancellations = <CompletionCancellation>[];
        final model = create(
          submit: (_) async => ComposerSubmissionOutcome.unknown,
          provider: (query, cancellation) {
            final response = Completer<CompletionBatch>();
            responses.add(response);
            queries.add(query);
            cancellations.add(cancellation);
            return response.future;
          },
        );
        addTearDown(model.dispose);
        ready(model);
        await model.run();

        model.requestCompletions();
        expect(model.loading, isTrue);
        expect(model.executionStatus, 'unknown_outcome');
        expect(model.status, 'unknown_outcome');
        expect(model.allowsLocalSuggestions(cancellations.first), isFalse);
        model.toggleLocalSuggestions();
        expect(cancellations.first.isCancelled, isTrue);
        expect(model.status, 'unknown_outcome');
        responses.first.complete(CompletionBatch(queries.first, const []));
        await settleQuery();
        expect(responses, hasLength(2));
        expect(model.loading, isTrue);
        expect(model.allowsLocalSuggestions(cancellations.last), isFalse);
        responses.last.complete(
          CompletionBatch(queries.last, [
            candidate(queries.last, 'echo other'),
          ]),
        );
        await settleQuery();

        expect(model.executionStatus, 'unknown_outcome');
        expect(model.completionStatus, isEmpty);
        model.status = 'completion_selection';
        expect(model.status, 'unknown_outcome');
        expect(model.completionStatus, 'completion_selection');
        model.status = '';
        expect(model.status, 'unknown_outcome');
        expect(model.canRun, isFalse);
      },
    );

    for (final text in ['next draft', 'echo original']) {
      test(
        'late acceptance preserves a newly edited $text and its undo',
        () async {
          final response = Completer<ComposerSubmissionOutcome>();
          var submits = 0;
          final model = create(
            submit: (_) {
              submits++;
              return response.future;
            },
          );
          addTearDown(model.dispose);
          ready(model);
          final running = model.performPrimaryAction();
          final pending = model.pendingSubmission;
          expect(model.primaryAction, ComposerPrimaryAction.disabled);
          expect(model.canRecoverDraft, isFalse);
          model.recoverDraft();
          expect(model.pendingSubmission, same(pending));
          expect(model.ownership, ComposerOwnership.submitting);

          // Returning to identical text is still a newer editor revision.
          edit(model, 'intermediate');
          model.editor.value = TextEditingValue(
            text: text,
            selection: const TextSelection(baseOffset: 2, extentOffset: 4),
          );
          final newer = model.editor.value;
          await model.performPrimaryAction();
          response.complete(ComposerSubmissionOutcome.accepted);
          await running;

          expect(submits, 1);
          expect(model.editor.value, newer);
          expect(model.pendingSubmission, isNull);
          expect(model.canRecoverDraft, isFalse);
          expect(model.canUndo, isTrue);
          model.undo();
          expect(model.editor.text, 'intermediate');
        },
      );
    }

    test(
      'rejection preserves selection and a later run starts a new transaction',
      () async {
        final submissions = <ComposerSubmission>[];
        final response = Completer<ComposerSubmissionOutcome>();
        final model = create(
          submit: (submission) {
            submissions.add(submission);
            return submissions.length == 1
                ? Future.value(ComposerSubmissionOutcome.rejected)
                : response.future;
          },
        );
        addTearDown(model.dispose);
        ready(model);
        model.editor.selection = const TextSelection(
          baseOffset: 2,
          extentOffset: 8,
        );
        final original = model.editor.value;
        await model.performPrimaryAction();
        expect(model.editor.value, original);
        expect(model.executionStatus, 'submission_rejected');
        expect(model.pendingSubmission, isNull);

        ready(model, lease: 'lease-2');
        final second = model.performPrimaryAction();
        expect(model.executionStatus, isEmpty);
        expect(model.completionStatus, isEmpty);
        expect(model.ownership, ComposerOwnership.submitting);
        expect(submissions, hasLength(2));
        expect(submissions.last.id, isNot(submissions.first.id));
        expect(submissions.last.lease, 'lease-2');
        response.complete(ComposerSubmissionOutcome.accepted);
        await second;
        expect(model.pendingSubmission, isNull);
      },
    );

    for (final newDraft in [false, true]) {
      test(
        'explicit unknown recovery ${newDraft ? 'keeps the new draft' : 'restores the submitted draft'} without retry',
        () async {
          var submits = 0;
          final model = create(
            submit: (_) async {
              submits++;
              return ComposerSubmissionOutcome.unknown;
            },
          );
          addTearDown(model.dispose);
          ready(model);
          model.editor.selection = const TextSelection(
            baseOffset: 2,
            extentOffset: 8,
          );
          final original = model.editor.value;
          await model.performPrimaryAction();
          if (newDraft) {
            model.editor.value = const TextEditingValue(
              text: 'next command',
              selection: TextSelection(baseOffset: 1, extentOffset: 4),
            );
          } else {
            model.clearDraft();
          }
          final current = model.editor.value;
          ready(model, lease: 'lease-2');
          expect(model.canRun, isFalse);

          model.recoverDraft();

          expect(model.editor.value, newDraft ? current : original);
          expect(model.pendingSubmission, isNull);
          expect(model.canRecoverDraft, isFalse);
          expect(model.executionStatus, isEmpty);
          expect(model.ownership, ComposerOwnership.draft);
          expect(model.readyLease, isNull);
          await model.performPrimaryAction();
          expect(submits, 1);
        },
      );
    }

    test('unknown recovery cannot discard an active IME composition', () async {
      final model = create(
        submit: (_) async => ComposerSubmissionOutcome.unknown,
      );
      addTearDown(model.dispose);
      ready(model);
      await model.run();
      model.editor.value = const TextEditingValue(
        text: '拼音',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      );
      final original = model.editor.value;
      final pending = model.pendingSubmission;
      expect(model.canRecoverDraft, isFalse);
      model.recoverDraft();
      expect(model.editor.value, original);
      expect(model.pendingSubmission, same(pending));
      expect(model.executionStatus, 'unknown_outcome');
    });
  });

  group('shared primary action', () {
    test('history adopts first, then a distinct action executes', () async {
      final submissions = <ComposerSubmission>[];
      final model = create(
        text: 'git',
        submit: (submission) async {
          submissions.add(submission);
          return ComposerSubmissionOutcome.accepted;
        },
      );
      addTearDown(model.dispose);
      ready(model);
      model.updateHistory(['git status']);
      expect(model.hasHistory, isTrue);
      expect(model.dialect, 'zsh');
      model.toggleHistory();
      expect(model.primaryAction, ComposerPrimaryAction.acceptHistory);
      expect(model.canPerformPrimaryAction, isTrue);
      expect(model.canRun, isFalse);

      await model.performPrimaryAction();

      expect(model.editor.text, 'git status');
      expect(model.historyOpen, isFalse);
      expect(submissions, isEmpty);
      expect(model.primaryAction, ComposerPrimaryAction.run);
      await model.performPrimaryAction();
      expect(submissions.single.query.value.text, 'git status');
    });

    test(
      'empty history results disable execution of the search string',
      () async {
        var submits = 0;
        final model = create(
          text: 'unmatched search',
          submit: (_) async {
            submits++;
            return ComposerSubmissionOutcome.accepted;
          },
        );
        addTearDown(model.dispose);
        ready(model);
        expect(model.hasHistory, isFalse);
        model.updateHistory(['git status']);
        model.openHistory();
        expect(model.hasHistory, isTrue);
        expect(model.historyItems, isEmpty);
        expect(model.primaryAction, ComposerPrimaryAction.disabled);
        expect(model.canPerformPrimaryAction, isFalse);
        await model.performPrimaryAction();
        expect(submits, 0);
        expect(model.editor.text, 'unmatched search');
        expect(model.historyOpen, isTrue);
      },
    );

    test('selected completion is adopted without execution', () async {
      final submissions = <ComposerSubmission>[];
      final model = create(
        text: 'git sta',
        submit: (submission) async {
          submissions.add(submission);
          return ComposerSubmissionOutcome.accepted;
        },
        provider: (query, _) async =>
            CompletionBatch(query, [candidate(query, 'git status')]),
      );
      addTearDown(model.dispose);
      ready(model);
      model.requestCompletions();
      await settleQuery();
      model.selectNext(1);
      expect(model.primaryAction, ComposerPrimaryAction.acceptCompletion);

      await model.performPrimaryAction();

      expect(model.editor.text, 'git status');
      expect(model.completionMenuOpen, isFalse);
      expect(submissions, isEmpty);
      expect(model.primaryAction, ComposerPrimaryAction.run);
      await model.performPrimaryAction();
      expect(submissions.single.query.value.text, 'git status');
    });

    test('an unselected completion is not implicitly adopted', () async {
      ComposerSubmission? sent;
      final model = create(
        text: 'git sta',
        submit: (submission) async {
          sent = submission;
          return ComposerSubmissionOutcome.accepted;
        },
        provider: (query, _) async =>
            CompletionBatch(query, [candidate(query, 'git status')]),
      );
      addTearDown(model.dispose);
      ready(model);
      model.requestCompletions();
      await settleQuery();
      expect(model.selectedIndex, -1);
      expect(model.primaryAction, ComposerPrimaryAction.run);
      await model.performPrimaryAction();
      expect(sent!.query.value.text, 'git sta');
    });

    test('grey text is not adopted by the primary execution action', () async {
      ComposerSubmission? sent;
      final model = create(
        text: 'git',
        submit: (submission) async {
          sent = submission;
          return ComposerSubmissionOutcome.accepted;
        },
      );
      addTearDown(model.dispose);
      ready(model);
      model.updateHistory(['git status']);
      expect(model.inlineSuggestion, ' status');
      expect(model.primaryAction, ComposerPrimaryAction.run);
      await model.performPrimaryAction();
      expect(sent!.query.value.text, 'git');
    });

    test('only editing remains possible without a ready shell', () async {
      var submits = 0;
      final model = create(
        text: 'git sta',
        submit: (_) async {
          submits++;
          return ComposerSubmissionOutcome.accepted;
        },
        provider: (query, _) async =>
            CompletionBatch(query, [candidate(query, 'git status')]),
      );
      addTearDown(model.dispose);
      expect(model.primaryAction, ComposerPrimaryAction.disabled);
      model.requestCompletions();
      await settleQuery();
      model.selectNext(1);
      expect(model.primaryAction, ComposerPrimaryAction.acceptCompletion);
      await model.performPrimaryAction();
      expect(model.editor.text, 'git status');
      expect(model.primaryAction, ComposerPrimaryAction.disabled);
      await model.performPrimaryAction();
      expect(submits, 0);
    });

    test('IME, inactive and raw ownership suppress primary actions', () async {
      var submits = 0;
      final model = create(
        submit: (_) async {
          submits++;
          return ComposerSubmissionOutcome.accepted;
        },
      );
      addTearDown(model.dispose);
      ready(model);
      model.editor.value = const TextEditingValue(
        text: '拼音',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      );
      final composing = model.editor.value;
      expect(model.primaryAction, ComposerPrimaryAction.disabled);
      model.clearDraft();
      model.toggleHistory();
      await model.performPrimaryAction();
      expect(model.editor.value, composing);
      expect(model.historyOpen, isFalse);
      edit(model, 'echo ready');
      model.setActive(false);
      expect(model.primaryAction, ComposerPrimaryAction.disabled);
      await model.performPrimaryAction();
      model.setActive(true);
      for (final owner in [
        ComposerOwnership.running,
        ComposerOwnership.suspended,
      ]) {
        model.updateShell(
          contextKey: owner.name,
          cwd: '/tmp/composer-redesign',
          ownership: owner,
        );
        expect(model.primaryAction, ComposerPrimaryAction.disabled);
        await model.performPrimaryAction();
      }
      expect(submits, 0);
    });
  });

  group('local editing actions', () {
    test('history availability follows ownership, focus activity and IME', () {
      final model = create();
      addTearDown(model.dispose);
      expect(model.canOpenHistory, isTrue);
      ready(model);
      expect(model.canOpenHistory, isTrue);
      model.setActive(false);
      expect(model.canOpenHistory, isFalse);
      model.setActive(true);
      model.editor.value = const TextEditingValue(
        text: '拼音',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      );
      expect(model.canOpenHistory, isFalse);
      edit(model, 'echo');
      for (final owner in [
        ComposerOwnership.running,
        ComposerOwnership.suspended,
        ComposerOwnership.submitting,
      ]) {
        // An in-flight ownership is deliberately not unlocked by later polls.
        model.ownership = owner;
        expect(model.canOpenHistory, isFalse);
      }
      model.ownership = ComposerOwnership.unknown;
      expect(model.canOpenHistory, isFalse);
    });

    test('history toggle restores the pre-search draft and selection', () {
      final model = create(text: 'git');
      addTearDown(model.dispose);
      model.editor.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 3,
      );
      final original = model.editor.value;
      model.updateHistory(['git status', 'git log']);
      model.toggleHistory();
      edit(model, 'log');
      expect(model.historyItems, ['git log']);
      model.toggleHistory();
      expect(model.historyOpen, isFalse);
      expect(model.editor.value, original);
    });

    test(
      'clear from history remains undoable to the draft, not the filter',
      () {
        final model = create(text: 'git');
        addTearDown(model.dispose);
        model.editor.selection = const TextSelection(
          baseOffset: 1,
          extentOffset: 3,
        );
        final original = model.editor.value;
        model.updateHistory(['git status', 'git log']);
        model.toggleHistory();
        edit(model, 'log');

        model.clearDraft();

        expect(model.historyOpen, isFalse);
        expect(model.editor.text, isEmpty);
        expect(model.canUndo, isTrue);
        model.undo();
        expect(model.editor.value, original);
        expect(model.canRedo, isTrue);
        model.redo();
        expect(model.editor.text, isEmpty);
      },
    );

    test(
      'transient completion feedback expires with its document or request',
      () async {
        final model = create();
        addTearDown(model.dispose);
        model.completeOnTab();
        await settleQuery();
        expect(model.completionStatus, 'no_completions');
        model.editor.selection = const TextSelection.collapsed(offset: 2);
        expect(model.completionStatus, isEmpty);
        model.status = 'completion_unavailable';
        model.requestCompletions();
        expect(model.completionStatus, isEmpty);
        await settleQuery();
        model.status = 'unsupported_context';
        model.updateShell(
          contextKey: 'new-context',
          cwd: '/tmp/new',
          ownership: ComposerOwnership.draft,
        );
        expect(model.completionStatus, isEmpty);
      },
    );
  });

  group('desktop event routing', () {
    Future<void> mount(
      WidgetTester tester,
      TerminalComposerController model,
      FocusNode focus, {
      FocusOnKeyEventCallback? onAncestorKey,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: Focus(
              canRequestFocus: false,
              onKeyEvent: onAncestorKey,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: TerminalComposerView(
                  controller: model,
                  targetLabel: 'Local shell',
                  focusNode: focus,
                  autofocus: true,
                  onUseTerminal: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'modified Tab reaches the host without requesting completion',
      (tester) async {
        var queries = 0;
        var hostKeys = 0;
        final model = create(
          provider: (query, _) async {
            queries++;
            return CompletionBatch(query, const []);
          },
        );
        final focus = FocusNode();
        addTearDown(model.dispose);
        addTearDown(focus.dispose);
        await mount(
          tester,
          model,
          focus,
          onAncestorKey: (_, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.tab &&
                HardwareKeyboard.instance.isControlPressed) {
              hostKeys++;
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        expect(hostKeys, 2);
        expect(queries, 0);
        expect(focus.hasFocus, isTrue);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets(
      'automatic-suggestions mouse click retains command editing focus',
      (tester) async {
        final model = create();
        final focus = FocusNode();
        addTearDown(model.dispose);
        addTearDown(focus.dispose);
        await mount(tester, model, focus);
        final gesture = await tester.startGesture(
          tester.getCenter(
            find.byKey(const Key('composer-automatic-suggestions-toggle')),
          ),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
        expect(model.localSuggestions, isTrue);
        expect(focus.hasFocus, isTrue);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets(
      'desktop semantic actions have names and announce suggestion state',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          var submits = 0;
          final model = create(
            text: 'git',
            submit: (_) async {
              submits++;
              return ComposerSubmissionOutcome.accepted;
            },
            provider: (query, _) async =>
                CompletionBatch(query, [candidate(query, 'git status')]),
          );
          final focus = FocusNode();
          addTearDown(model.dispose);
          addTearDown(focus.dispose);
          ready(model);
          model.updateHistory(['git status']);
          await mount(tester, model, focus);

          SemanticsFinder namedAction(String label) {
            final finder = find.semantics.byLabel(label);
            expect(finder, findsOne);
            final data = finder.evaluate().single.getSemanticsData();
            expect(data.flagsCollection.isButton, isTrue);
            expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
            return finder;
          }

          // macOS AX exposed tooltip-only icons as unnamed buttons, and did
          // not include toggled state in the automatic-suggestions button name.
          var automatic = namedAction('Automatic suggestions · Off');
          expect(
            automatic
                .evaluate()
                .single
                .getSemanticsData()
                .flagsCollection
                .isToggled,
            ui.Tristate.isFalse,
          );
          tester.semantics.tap(automatic);
          await tester.pumpAndSettle();
          expect(model.localSuggestions, isTrue);
          automatic = namedAction('Automatic suggestions · On');
          expect(
            automatic
                .evaluate()
                .single
                .getSemanticsData()
                .flagsCollection
                .isToggled,
            ui.Tristate.isTrue,
          );
          tester.semantics.tap(automatic);
          await tester.pumpAndSettle();
          expect(model.localSuggestions, isFalse);
          namedAction('Automatic suggestions · Off');

          tester.semantics.tap(namedAction('More command actions'));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('composer-copy-draft')), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(focus.hasFocus, isTrue);

          model.requestCompletions();
          await tester.pumpAndSettle();
          expect(model.completionMenuOpen, isTrue);
          tester.semantics.tap(namedAction('Close completions'));
          await tester.pumpAndSettle();
          expect(model.completionMenuOpen, isFalse);
          expect(model.editor.text, 'git');

          final draft = model.editor.value;
          model.openHistory();
          edit(model, 'status');
          await tester.pumpAndSettle();
          tester.semantics.tap(namedAction('Close history and restore draft'));
          await tester.pumpAndSettle();
          expect(model.historyOpen, isFalse);
          expect(model.editor.value, draft);
          expect(submits, 0);
        } finally {
          semantics.dispose();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    for (final history in [true, false]) {
      testWidgets(
        'a desktop click can adopt a ${history ? 'history' : 'completion'} row across pointer frames',
        (tester) async {
          var submits = 0;
          final model = create(
            text: 'git',
            submit: (_) async {
              submits++;
              return ComposerSubmissionOutcome.accepted;
            },
            provider: (query, _) async =>
                CompletionBatch(query, [candidate(query, 'git status')]),
          );
          final focus = FocusNode();
          addTearDown(model.dispose);
          addTearDown(focus.dispose);
          ready(model);
          model.updateHistory(['git status']);
          await mount(tester, model, focus);
          if (history) {
            model.openHistory();
          } else {
            model.requestCompletions();
          }
          await tester.pumpAndSettle();
          final gesture = await tester.startGesture(
            tester.getCenter(find.text('git status', findRichText: true)),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump();
          await gesture.up();
          await tester.pumpAndSettle();
          expect(model.editor.text, 'git status');
          expect(model.historyOpen, isFalse);
          expect(model.completionMenuOpen, isFalse);
          expect(focus.hasFocus, isTrue);
          expect(submits, 0);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      );
    }

    testWidgets(
      'More keyboard activation cannot submit the editor draft',
      (tester) async {
        var submits = 0;
        final model = create(
          submit: (_) async {
            submits++;
            return ComposerSubmissionOutcome.accepted;
          },
        );
        final focus = FocusNode();
        addTearDown(model.dispose);
        addTearDown(focus.dispose);
        ready(model);
        await mount(tester, model, focus);
        await tester.tap(find.byKey(const Key('composer-more-actions')));
        await tester.pumpAndSettle();
        expect(focus.hasFocus, isFalse);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(submits, 0);
        expect(model.editor.text, 'echo original');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  });
}
