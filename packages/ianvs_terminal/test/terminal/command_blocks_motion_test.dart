import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import 'command_blocks_test.dart' show block;

void main() {
  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    for (final reduced in [false, true]) {
      testWidgets(
        'block overlays respect motion and return focus: $platform / $reduced',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = platform == TargetPlatform.iOS
              ? const Size(390, 844)
              : const Size(960, 800);
          addTearDown(tester.view.reset);
          tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
              FakeAccessibilityFeatures(disableAnimations: reduced);
          addTearDown(
            tester
                .binding
                .platformDispatcher
                .clearAccessibilityFeaturesTestValue,
          );
          final original = block('retained', lineCount: 25);
          final reinsertions = <String>[];
          final controller = CommandBlockController(
            request: (request) => request['id'] == null
                ? {
                    'blocks': [original],
                  }
                : {'block': original},
          )..refresh();
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: platform),
              home: Scaffold(
                body: TerminalCommandBlocksView(
                  controller: controller,
                  onReinput: reinsertions.add,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final actions = find
              .byWidgetPredicate(
                (w) =>
                    w is PopupMenuButton<String> &&
                    w.tooltip == 'Block actions',
              )
              .first;
          final triggerFocus = Focus.of(
            tester.element(
              find.descendant(of: actions, matching: find.byType(Icon)).first,
            ),
          );
          triggerFocus.requestFocus();
          await tester.pump();
          await tester.tap(actions);
          await tester.pump();
          final menuItem = find.text('Copy command');
          expect(
            ModalRoute.of(tester.element(menuItem))!.animation!.isCompleted,
            reduced,
          );
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(menuItem, findsNothing);
          expect(triggerFocus.hasFocus, true);

          await tester.tap(actions);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Export as Markdown…'));
          for (var i = 0; i < 4; i++) {
            await tester.pump();
          }
          final dialog = find.byType(AlertDialog);
          expect(
            ModalRoute.of(tester.element(dialog))!.animation!.isCompleted,
            reduced,
          );
          await tester.pumpAndSettle();
          expect(find.text('Export block'), findsOneWidget);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();

          await tester.tap(actions);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Open output reader'));
          for (var i = 0; i < 4; i++) {
            await tester.pump();
          }
          final reader = find.byKey(const Key('block-reader'));
          if (reduced) {
            final bounds = tester.getRect(reader);
            expect(bounds, Offset.zero & tester.view.physicalSize);
            await tester.pump(const Duration(milliseconds: 1));
            expect(tester.getRect(reader), bounds);
            expect(
              find.ancestor(of: reader, matching: find.byType(SlideTransition)),
              findsNothing,
            );
          } else {
            expect(
              ModalRoute.of(tester.element(reader))!.animation!.isCompleted,
              false,
            );
          }
          await tester.pumpAndSettle();
          if (platform == TargetPlatform.macOS) {
            await tester.dragFrom(
              const Offset(4, 180),
              const Offset(240, 0),
              kind: PointerDeviceKind.mouse,
            );
            await tester.pumpAndSettle();
            expect(
              reader,
              findsOneWidget,
              reason: 'A mouse drag at the reader edge must not navigate back.',
            );
          }
          await tester.tap(find.byKey(const Key('block-reader-actions')));
          await tester.pump();
          expect(
            ModalRoute.of(
              tester.element(find.text('Copy command')),
            )!.animation!.isCompleted,
            reduced,
          );
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(reader, findsOneWidget);
          await tester.tap(find.byKey(const Key('block-reader-close')));
          await tester.pumpAndSettle();
          expect(reader, findsNothing);
          expect(controller.blocks.single.command, 'echo retained');
          expect(reinsertions, isEmpty);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
