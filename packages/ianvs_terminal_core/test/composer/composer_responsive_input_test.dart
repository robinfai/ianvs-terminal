import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';

import '../helpers/pump_app.dart';

void main() {
  group('$TerminalComposerView transactional draft editing', () {
    late TerminalComposerController controller;
    late FocusNode focus;
    late int submissions;
    late int aiRequests;

    setUp(() {
      submissions = 0;
      aiRequests = 0;
      focus = FocusNode();
      controller =
          TerminalComposerController(
              targetId: 'session-one',
              text: 'printf "原始路径"\npwd',
              provider: (query, _) async => CompletionBatch(query, const []),
              submit: (_) async {
                submissions++;
                return ComposerSubmissionOutcome.accepted;
              },
            )
            ..updateShell(
              contextKey: 'root',
              cwd: '/tmp',
              dialect: 'zsh',
              lease: 'ready-1',
              ownership: ComposerOwnership.ready,
            )
            ..updateIntentContext(
              const InputIntentContext(
                scope: 'session-one:root',
                commandNames: {'printf', 'pwd'},
              ),
            );
    });

    tearDown(() {
      controller.dispose();
      focus.dispose();
    });

    Future<void> mount(
      WidgetTester tester, {
      Size size = const Size(390, 844),
      Brightness brightness = Brightness.light,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      await tester.pumpApp(
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: TerminalComposerView(
                controller: controller,
                focusNode: focus,
                targetLabel: 'ops@staging',
                onAskAi: (_) => aiRequests++,
              ),
            ),
          ),
        ),
        theme: ThemeData(
          useMaterial3: true,
          platform: TargetPlatform.iOS,
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();
    }

    test(
      'previews intent without changing the live text or manual override',
      () {
        controller.chooseInputIntent(InputIntentChoice.ai);
        final before = controller.editor.value;
        expect(
          controller
              .previewInputIntent(
                const TextEditingValue(text: 'pwd'),
                InputIntentChoice.command,
              )
              .intent,
          InputIntent.command,
        );
        expect(
          controller
              .previewInputIntent(
                const TextEditingValue(text: '请解释日志'),
                InputIntentChoice.automatic,
              )
              .intent,
          InputIntent.ai,
        );
        expect(controller.editor.value, before);
        expect(controller.inputIntent.choice, InputIntentChoice.ai);
        expect(controller.intentDecision.intent, InputIntent.ai);
      },
    );

    testWidgets('Done saves text and selection as one undoable unsent edit', (
      tester,
    ) async {
      controller.editor.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 8,
      );
      final before = controller.editor.value;
      await mount(tester);
      try {
        await tester.tap(find.byKey(const Key('composer-expand-draft')));
        await tester.pumpAndSettle();
        final editor = tester
            .widget<TextField>(find.byKey(const Key('composer-draft-editor')))
            .controller!;
        expect(editor.selection, before.selection);
        const changed = TextEditingValue(
          text: 'printf "新路径 🧭"\npwd\necho done',
          selection: TextSelection(baseOffset: 7, extentOffset: 12),
        );
        editor.value = changed;
        await tester.pump();
        expect(controller.editor.value, before);
        await tester.tap(find.byKey(const Key('composer-draft-done')));
        await tester.pumpAndSettle();
        expect(controller.editor.value, changed);
        expect(submissions, 0);
        expect(aiRequests, 0);
        controller.undo();
        expect(controller.editor.value, before);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets(
      'Escape cancels temporary text and intent without changing the source selection',
      (tester) async {
        controller.editor.selection = const TextSelection(
          baseOffset: 1,
          extentOffset: 7,
        );
        final before = controller.editor.value;
        await mount(tester);
        try {
          await tester.tap(find.byKey(const Key('composer-expand-draft')));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('composer-draft-editor')),
            'discard this',
          );
          await tester.tap(find.byKey(const Key('composer-draft-intent')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.widgetWithText(CheckedPopupMenuItem<InputIntentChoice>, 'AI'),
          );
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('composer-draft-page')), findsNothing);
          expect(controller.editor.value, before);
          expect(controller.inputIntent.choice, InputIntentChoice.automatic);
          expect(submissions, 0);
          expect(aiRequests, 0);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    testWidgets(
      'does not save after an external ABA edit of the same source draft',
      (tester) async {
        await mount(tester);
        try {
          final before = controller.editor.value;
          await tester.tap(find.byKey(const Key('composer-expand-draft')));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('composer-draft-editor')),
            'stale temporary text',
          );
          controller.editor.text = 'newer live edit';
          controller.editor.value = before;
          await tester.pump();
          await tester.tap(find.byKey(const Key('composer-draft-done')));
          await tester.pump();
          expect(find.byKey(const Key('composer-draft-page')), findsOneWidget);
          expect(controller.editor.value, before);
          await tester.tap(find.byKey(const Key('composer-draft-cancel')));
          await tester.pumpAndSettle();
          expect(submissions, 0);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    testWidgets(
      'software Return preserves the draft without submitting and hardware Shift Enter inserts a newline',
      (tester) async {
        controller.editor.text = 'pwd';
        await mount(tester);
        try {
          await tester.showKeyboard(find.byKey(const Key('composer-editor')));
          await tester.testTextInput.receiveAction(TextInputAction.newline);
          await tester.pump();
          expect(submissions, 0);
          expect(aiRequests, 0);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          // The real edit schedules a 100 ms completion refresh. Finish it
          // before the externally owned controller reaches test teardown.
          await tester.pumpAndSettle();
          expect(controller.editor.text, 'pwd\n');
          expect(submissions, 0);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    testWidgets(
      'reducing motion opens the draft without a sliding transition',
      (tester) async {
        tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await mount(tester);
        try {
          await tester.tap(find.byKey(const Key('composer-expand-draft')));
          await tester.pump();
          await tester.pump();
          final page = find.byKey(const Key('composer-draft-page'));
          expect(page, findsOneWidget);
          final route = ModalRoute.of(tester.element(page))!;
          expect(route.animation!.isCompleted, isTrue);
          expect(tester.getTopLeft(page), Offset.zero);
          expect(submissions, 0);
          await tester.tap(find.byKey(const Key('composer-draft-cancel')));
          await tester.pumpAndSettle();
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    testWidgets(
      'a short window scrolls to full-size editing and hide-keyboard controls',
      (tester) async {
        await mount(tester, size: const Size(320, 95));
        try {
          expect(tester.takeException(), isNull);
          final expand = find.byKey(const Key('composer-expand-draft'));
          await tester.ensureVisible(expand);
          await tester.pumpAndSettle();
          expect(tester.getSize(expand).height, greaterThanOrEqualTo(44));
          await tester.tap(expand);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final cancel = find.byKey(const Key('composer-draft-cancel'));
          await tester.ensureVisible(cancel);
          await tester.pumpAndSettle();
          expect(tester.getSize(cancel).height, greaterThanOrEqualTo(44));
          expect(
            find.byKey(const Key('composer-draft-intent')),
            findsOneWidget,
          );
          await tester.tap(cancel);
          await tester.pumpAndSettle();
          expect(submissions, 0);
          expect(aiRequests, 0);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    for (final size in [
      const Size(320, 600),
      const Size(390, 844),
      const Size(844, 145),
    ]) {
      for (final brightness in Brightness.values) {
        testWidgets(
          'keeps multiline text, visible intent and reachable editing controls at $size $brightness',
          (tester) async {
            controller.editor.text = 'pwd\nprintf "中文"\npwd\npwd\npwd\npwd';
            final before = controller.editor.value;
            await mount(tester, size: size, brightness: brightness);
            try {
              expect(find.text('Auto · Command'), findsOneWidget);
              expect(controller.editor.value, before);
              final button = find.byKey(const Key('composer-expand-draft'));
              expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
              await tester.tap(button);
              await tester.pumpAndSettle();
              expect(
                find.byKey(const Key('composer-draft-page')),
                findsOneWidget,
              );
              expect(tester.takeException(), isNull);
              await tester.tap(find.byKey(const Key('composer-draft-cancel')));
              await tester.pumpAndSettle();
              expect(controller.editor.value, before);
              expect(submissions, 0);
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
            }
          },
        );
      }
    }
  });
}
