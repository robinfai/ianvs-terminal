import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/ui/previews/mobile_prd_component_previews.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../helpers/pump_app.dart';

void main() {
  group('$MobilePrdComponentPreview production state catalogue', () {
    Future<void> mount(
      WidgetTester tester,
      MobilePrdPreviewComponent component, {
      bool dark = false,
      MobilePrdPreviewState state = MobilePrdPreviewState.defaultState,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 640);
      addTearDown(tester.view.reset);
      // Preview fixtures exercise real controller request/approval futures.
      // Start those futures outside FakeAsync, as the workspace tests do.
      await tester.runAsync(() async {
        await tester.pumpApp(
          MobilePrdComponentPreview(
            component: component,
            dark: dark,
            initialState: state,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
    }

    for (final component in MobilePrdPreviewComponent.values) {
      for (final dark in [false, true]) {
        testWidgets(
          'renders the real $component in ${dark ? 'dark' : 'light'} theme',
          (tester) async {
            try {
              await mount(tester, component, dark: dark);
              expect(tester.takeException(), isNull);
              switch (component) {
                case MobilePrdPreviewComponent.block:
                  expect(
                    find.byType(TerminalCommandBlocksView),
                    findsOneWidget,
                  );
                case MobilePrdPreviewComponent.readerHeader:
                  expect(find.byKey(const Key('block-reader')), findsOneWidget);
                  expect(
                    find.byKey(const Key('block-reader-close')),
                    findsOneWidget,
                  );
                case MobilePrdPreviewComponent.reviewPage:
                  expect(
                    find.byKey(const Key('ai-review-back')),
                    findsOneWidget,
                  );
                  expect(
                    find.byKey(const Key('ai-review-scroll')),
                    findsOneWidget,
                  );
                case MobilePrdPreviewComponent.contextChip:
                  expect(find.byType(InputChip), findsOneWidget);
                case MobilePrdPreviewComponent.composerShell:
                  expect(find.byKey(const Key('ai-prompt')), findsOneWidget);
                default:
                  expect(
                    find.byType(TerminalAiComponentPreview),
                    findsOneWidget,
                  );
              }
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
            }
          },
        );
      }
    }

    testWidgets(
      'selected composer uses the real editing selection and disabled state removes send permission',
      (tester) async {
        try {
          await mount(
            tester,
            MobilePrdPreviewComponent.composerShell,
            state: MobilePrdPreviewState.selected,
          );
          final input = tester
              .widget<TextField>(find.byKey(const Key('ai-prompt')))
              .controller!;
          expect(input.selection.baseOffset, 0);
          expect(input.selection.extentOffset, input.text.length);
          final selector = find.byKey(const Key('mobile-prd-preview-state'));
          await tester.tap(selector);
          await tester.pumpAndSettle();
          await tester.tap(find.text('disabled').last);
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<FilledButton>(find.byKey(const Key('ai-send')))
                .onPressed,
            isNull,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    for (final state in [
      MobilePrdPreviewState.loading,
      MobilePrdPreviewState.unknown,
      MobilePrdPreviewState.targetChanged,
      MobilePrdPreviewState.error,
    ]) {
      testWidgets('task status shows the controller fact $state', (
        tester,
      ) async {
        try {
          await mount(
            tester,
            MobilePrdPreviewComponent.taskStatus,
            state: state,
          );
          final status = tester
              .widget<Text>(find.byKey(const Key('ai-task-status')))
              .data!;
          expect(status, switch (state) {
            MobilePrdPreviewState.loading => contains('Thinking'),
            MobilePrdPreviewState.unknown => contains('Submission unknown'),
            MobilePrdPreviewState.targetChanged => contains('Target changed'),
            _ => contains('Terminal unavailable'),
          });
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      });
    }
  });
}
