import 'dart:ui' as ui;

import 'package:app/ui/app_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../../../packages/ianvs_terminal/test/composer/composer_theme_test.dart'
    show contrast;

Future<Color> _pixel(
  WidgetTester tester,
  GlobalKey boundary,
  Offset point,
) async => (await tester.runAsync(() async {
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final local = render.globalToLocal(point);
  final image = await render.toImage(pixelRatio: 1);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final offset = (local.dy.floor() * image.width + local.dx.floor()) * 4;
    return Color.fromARGB(
      data.getUint8(offset + 3),
      data.getUint8(offset),
      data.getUint8(offset + 1),
      data.getUint8(offset + 2),
    );
  } finally {
    image.dispose();
  }
}))!;

bool _focused(WidgetTester tester, Finder button) => tester
    .widget<InkWell>(
      find.descendant(of: button, matching: find.byType(InkWell)),
    )
    .statesController!
    .value
    .contains(WidgetState.focused);

Future<void> _reverseTab(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pumpAndSettle();
}

void main() {
  for (final brightness in Brightness.values) {
    for (final highContrast in [false, true]) {
      testWidgets(
        'hovered primary action retains a distinct keyboard focus ring: '
        '${brightness.name}/contrast=$highContrast',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(900, 600);
          addTearDown(tester.view.reset);
          final semantics = tester.ensureSemantics();
          final boundary = GlobalKey();
          var submissions = 0;
          final model =
              TerminalComposerController(
                targetId: 'focus-fixture',
                text: 'echo focus',
                debounce: const Duration(days: 1),
                provider: (query, _) async => CompletionBatch(query, const []),
                submit: (_) async {
                  submissions++;
                  return ComposerSubmissionOutcome.accepted;
                },
              )..updateShell(
                contextKey: 'ready',
                cwd: '/fixture',
                dialect: 'zsh',
                ownership: ComposerOwnership.ready,
                lease: 'ready',
              );
          await tester.pumpWidget(
            MaterialApp(
              theme: buildIanvsTerminalTheme(
                brightness,
                platform: TargetPlatform.macOS,
                highContrast: highContrast,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(highContrast: highContrast),
                child: child!,
              ),
              home: Scaffold(
                body: RepaintBoundary(
                  key: boundary,
                  child: Center(
                    child: TerminalComposerView(
                      controller: model,
                      targetLabel: 'Local Shell',
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final button = find.byKey(const Key('composer-primary-action'));
          final material = find.descendant(
            of: button,
            matching: find.byType(Material),
          );
          final originalBounds = tester.getRect(material);
          final innerEdge = Offset(
            originalBounds.center.dx,
            originalBounds.top + 2.5,
          );
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          try {
            await mouse.addPointer(location: Offset.zero);
            await mouse.moveTo(tester.getCenter(button));
            await tester.pumpAndSettle();
            expect(_focused(tester, button), isFalse);
            final hovered = await _pixel(tester, boundary, innerEdge);
            for (var i = 0; i < 20 && !_focused(tester, button); i++) {
              await _reverseTab(tester);
            }
            expect(_focused(tester, button), isTrue);
            expect(tester.getRect(material), originalBounds);
            final focused = await _pixel(tester, boundary, innerEdge);
            expect(
              focused,
              isNot(hovered),
              reason: 'Keyboard focus must add visible feedback under hover.',
            );
            final fill = await _pixel(
              tester,
              boundary,
              Offset(originalBounds.center.dx, originalBounds.top + 5.5),
            );
            final outerEdge = await _pixel(
              tester,
              boundary,
              Offset(originalBounds.center.dx, originalBounds.top + .5),
            );
            final outside = await _pixel(
              tester,
              boundary,
              Offset(originalBounds.center.dx, originalBounds.top - 2.5),
            );
            expect(
              contrast(focused, fill),
              greaterThanOrEqualTo(3),
              reason: 'Focus edge must contrast the actual hovered fill.',
            );
            expect(
              contrast(outerEdge, outside),
              greaterThanOrEqualTo(3),
              reason: 'The outer edge must remain visible against the Dock.',
            );
            expect(submissions, 0);
            expect(model.editor.text, 'echo focus');
            final data = tester.getSemantics(button).getSemanticsData();
            expect(data.flagsCollection.isButton, isTrue);
            expect(data.flagsCollection.isEnabled, ui.Tristate.isTrue);
            expect(data.flagsCollection.isFocused, ui.Tristate.isTrue);
            expect(data.hasAction(ui.SemanticsAction.tap), isTrue);

            await _reverseTab(tester);
            expect(_focused(tester, button), isFalse);
            expect(await _pixel(tester, boundary, innerEdge), hovered);
            expect(tester.getRect(material), originalBounds);
            expect(submissions, 0);
            for (var i = 0; i < 20 && !_focused(tester, button); i++) {
              await _reverseTab(tester);
            }
            expect(_focused(tester, button), isTrue);
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            // Successful submit keeps its busy indicator running until receipt.
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 250));
            expect(submissions, 1);
            expect(tester.getRect(material), originalBounds);
            expect(tester.takeException(), isNull);
          } finally {
            await mouse.removePointer();
            await tester.pumpWidget(const SizedBox.shrink());
            model.dispose();
            semantics.dispose();
          }
        },
        variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      );
    }
  }
}
