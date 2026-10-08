import 'package:app/features/shell/widgets/mobile_disconnected_session_notice.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

void main() {
  group(MobileDisconnectedSessionNotice, () {
    for (final brightness in Brightness.values) {
      for (final locale in [const Locale('en'), const Locale('zh')]) {
        for (final reconnected in [false, true]) {
          testWidgets(
            'keeps ${reconnected ? 'current connection' : 'reconnect'} action '
            'reachable at 320px in ${brightness.name} '
            'and ${locale.languageCode}',
            (tester) async {
              tester.view.physicalSize = const Size(320, 640);
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.reset);
              var calls = 0;
              await tester.pumpApp(
                Align(
                  alignment: Alignment.topCenter,
                  child: MobileDisconnectedSessionNotice(
                    sessionId: 'history',
                    reconnected: reconnected,
                    exitCode: 255,
                    onReconnect: () => calls++,
                  ),
                ),
                brightness: brightness,
                locale: locale,
                platform: TargetPlatform.iOS,
              );

              final l10n = tester
                  .element(find.byType(MobileDisconnectedSessionNotice))
                  .l10n;
              expect(
                find.text(l10n.mobileSessionDisconnectedTitle),
                findsOneWidget,
              );
              expect(
                find.text(l10n.mobileSessionExitCode(255)),
                findsOneWidget,
              );
              expect(
                find.text(
                  reconnected
                      ? l10n.mobileSessionReconnectedDetail
                      : l10n.mobileSessionDisconnectedDetail,
                ),
                findsOneWidget,
              );
              expect(
                find.text(
                  reconnected
                      ? l10n.mobileSessionOpenCurrent
                      : l10n.mobileSessionReconnect,
                ),
                findsOneWidget,
              );
              final button = find.byKey(
                const Key('mobile-disconnected-reconnect-history'),
              );
              final bounds = tester.getRect(button);
              expect(bounds.height, greaterThanOrEqualTo(44));
              expect(bounds.width, greaterThanOrEqualTo(44));
              expect(bounds.left, greaterThanOrEqualTo(0));
              expect(bounds.right, lessThanOrEqualTo(320));
              expect(button.hitTestable(), findsOneWidget);
              // The bottom edge of the touch target also activates the action.
              await tester.tapAt(Offset(bounds.center.dx, bounds.bottom - 1));
              expect(calls, 1);
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }

    for (final scenario in [
      (
        locale: const Locale('en'),
        brightness: Brightness.dark,
        reconnected: true,
      ),
      (
        locale: const Locale('zh'),
        brightness: Brightness.light,
        reconnected: false,
      ),
    ]) {
      testWidgets(
        'compact ${scenario.locale.languageCode} notice keeps its action and '
        'full explanation accessible in 64px height',
        (tester) async {
          tester.view.physicalSize = const Size(320, 240);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final semantics = tester.ensureSemantics();
          try {
            var calls = 0;
            await tester.pumpApp(
              Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  key: const Key('notice-window'),
                  width: double.infinity,
                  height: 64,
                  // Mirrors the short-space host without involving ShellScreen.
                  child: SingleChildScrollView(
                    child: MobileDisconnectedSessionNotice(
                      sessionId: 'history',
                      reconnected: scenario.reconnected,
                      compact: true,
                      exitCode: 255,
                      onReconnect: () => calls++,
                    ),
                  ),
                ),
              ),
              brightness: scenario.brightness,
              locale: scenario.locale,
              platform: TargetPlatform.iOS,
            );

            final l10n = tester
                .element(find.byType(MobileDisconnectedSessionNotice))
                .l10n;
            final detail = scenario.reconnected
                ? l10n.mobileSessionReconnectedDetail
                : l10n.mobileSessionDisconnectedDetail;
            expect(find.text(detail), findsNothing);
            expect(
              find.bySemanticsLabel(RegExp(RegExp.escape(detail))),
              findsWidgets,
            );
            final explanation = find.byTooltip(detail);
            await tester.ensureVisible(explanation);
            await tester.longPress(explanation);
            await tester.pumpAndSettle();
            expect(find.text(detail), findsOneWidget);

            final action = find.byKey(
              const Key('mobile-disconnected-reconnect-history'),
            );
            await tester.ensureVisible(action);
            await tester.pumpAndSettle();
            final bounds = tester.getRect(action);
            final visibleBounds = bounds.intersect(
              tester.getRect(find.byKey(const Key('notice-window'))),
            );
            expect(visibleBounds.height, greaterThanOrEqualTo(44));
            expect(visibleBounds.width, greaterThanOrEqualTo(44));
            await tester.tapAt(visibleBounds.center);
            expect(calls, 1);
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      'keeps retained output explanation without a reconnect action',
      (tester) async {
        await tester.pumpApp(
          const Align(
            alignment: Alignment.topCenter,
            child: MobileDisconnectedSessionNotice(
              sessionId: 'history',
              reconnected: false,
            ),
          ),
          platform: TargetPlatform.iOS,
        );
        final l10n = tester
            .element(find.byType(MobileDisconnectedSessionNotice))
            .l10n;
        expect(find.text(l10n.mobileSessionDisconnectedDetail), findsOneWidget);
        expect(find.byType(FilledButton), findsNothing);
        expect(find.textContaining('Exit code'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'uses the latest session and callback after reconnection changes',
      (tester) async {
        var originalCalls = 0;
        var currentCalls = 0;
        await tester.pumpApp(
          Align(
            alignment: Alignment.topCenter,
            child: MobileDisconnectedSessionNotice(
              sessionId: 'original',
              reconnected: false,
              onReconnect: () => originalCalls++,
            ),
          ),
          platform: TargetPlatform.iOS,
        );
        await tester.pumpApp(
          Align(
            alignment: Alignment.topCenter,
            child: MobileDisconnectedSessionNotice(
              sessionId: 'latest',
              reconnected: true,
              onReconnect: () => currentCalls++,
            ),
          ),
          platform: TargetPlatform.iOS,
        );
        expect(
          find.byKey(const Key('mobile-disconnected-reconnect-original')),
          findsNothing,
        );
        expect(find.text('Open current connection'), findsOneWidget);
        await tester.tap(
          find.byKey(const Key('mobile-disconnected-reconnect-latest')),
        );
        expect(originalCalls, 0);
        expect(currentCalls, 1);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
