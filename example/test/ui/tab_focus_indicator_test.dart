import 'dart:math' as math;

import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final contrast in [false, true]) {
      for (final selected in [false, true]) {
        testWidgets('tab focus remains visible under hover: '
            '${brightness.name}, contrast=$contrast, selected=$selected', (
          tester,
        ) async {
          final focus = FocusNode();
          final after = FocusNode();
          var activations = 0;
          final theme = buildIanvsTerminalTheme(
            brightness,
            platform: TargetPlatform.macOS,
            highContrast: contrast,
          );
          final palette = theme.extension<AppThemeTokens>()!;
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(highContrast: contrast),
                child: child!,
              ),
              home: Scaffold(
                body: Material(
                  color: palette.panel,
                  child: Column(
                    children: [
                      SizedBox(
                        width: 320,
                        height: 44,
                        child: ShellTabComponentPreview(
                          tab: const TerminalTab(
                            sessionId: 'focus-tab',
                            title: 'Build',
                            profileId: 'fixture',
                          ),
                          selected: selected,
                          focusNode: focus,
                          onActivate: () => activations++,
                          onClose: () {},
                        ),
                      ),
                      TextButton(
                        focusNode: after,
                        onPressed: () {},
                        child: const Text('Next control'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final tab = find.byKey(const Key('shell-tab-focus-tab'));
          final material = find.descendant(
            of: tab,
            matching: find.byType(Material),
          );
          BorderSide paintedSide() =>
              (tester.widget<Material>(material).shape! as OutlinedBorder).side;
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          try {
            await mouse.addPointer(location: Offset.zero);
            await mouse.moveTo(tester.getCenter(tab));
            await tester.pumpAndSettle();
            final hoverSide = paintedSide();
            expect(activations, 0);
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pumpAndSettle();
            expect(focus.hasFocus, isTrue);
            final focusedSide = paintedSide();
            expect(focusedSide.color, palette.focusRing);
            expect(focusedSide.width, 2);
            expect(focusedSide, isNot(hoverSide));
            final surface = Color.alphaBlend(
              tester.widget<Material>(material).color!,
              palette.panel,
            );
            final a = focusedSide.color.computeLuminance();
            final b = surface.computeLuminance();
            expect(
              (math.max(a, b) + .05) / (math.min(a, b) + .05),
              greaterThanOrEqualTo(3),
            );
            expect(activations, 0);
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(activations, 1);
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pumpAndSettle();
            expect(after.hasFocus, isTrue);
            expect(paintedSide(), hoverSide);
            expect(activations, 1);
            expect(tester.takeException(), isNull);
          } finally {
            await mouse.removePointer();
            await tester.pumpWidget(const SizedBox.shrink());
            focus.dispose();
            after.dispose();
          }
        }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));
      }
    }
  }
}
