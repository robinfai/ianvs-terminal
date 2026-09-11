import 'package:app/features/recording/mobile_replay_player.dart';
import 'package:app/features/terminal/terminal.dart' as terminal;
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Driver implements terminal.TerminalReplayDriver {
  @override
  Duration position = Duration.zero;
  @override
  Duration get duration => const Duration(minutes: 2);
  @override
  void advanceTo(Duration sourceOffset) => position = sourceOffset;
  @override
  void seekTo(Duration sourceOffset) => position = sourceOffset;
}

void main() {
  for (final size in [
    const Size(375, 667),
    const Size(402, 874),
    const Size(874, 402),
  ]) {
    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets('player fits $size at $scale without competing controls', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);
        final driver = _Driver();
        final controller = terminal.TerminalReplayController(
          driver: driver,
          navigationOffsets: const [
            Duration.zero,
            Duration(seconds: 30),
            Duration(minutes: 2),
          ],
          initialTimeMode: terminal.TerminalReplayTimeMode.realTime,
        );
        addTearDown(controller.dispose);
        final viewportFocus = FocusNode(debugLabel: 'read-only-replay-test');
        addTearDown(viewportFocus.dispose);
        final searches = <String>[];
        var closed = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildIanvsTerminalTheme(
              scale == 2 ? Brightness.dark : Brightness.light,
              platform: TargetPlatform.iOS,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              resizeToAvoidBottomInset: false,
              body: SafeArea(
                child: MobileReplayPlayer(
                  controller: controller,
                  title: 'Deployment / production-server',
                  details: 'Keystrokes redacted',
                  recordedViewportSize: const Size(800, 480),
                  viewport: Focus(
                    autofocus: true,
                    focusNode: viewportFocus,
                    child: const ColoredBox(
                      color: Colors.black,
                      child: Text('Terminal output'),
                    ),
                  ),
                  onClose: () => closed = true,
                  onSearchChanged: searches.add,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (scale == 1) {
          expect(
            tester
                .getSize(find.byKey(const Key('mobile-replay-transport')))
                .height,
            lessThanOrEqualTo(108),
          );
        }
        expect(viewportFocus.hasFocus, isFalse);
        expect(find.byKey(const Key('mobile-replay-search')), findsNothing);
        expect(
          find.byKey(const Key('mobile-replay-options-sheet')),
          findsNothing,
        );
        for (final key in [
          'mobile-replay-toggle',
          'mobile-replay-back-ten',
          'mobile-replay-forward-ten',
          'mobile-replay-close',
        ]) {
          final target = tester.getSize(find.byKey(Key(key)));
          expect(target.width, greaterThanOrEqualTo(44));
          expect(target.height, greaterThanOrEqualTo(44));
        }
        await tester.tap(find.byKey(const Key('mobile-replay-forward-ten')));
        await tester.pump();
        expect(driver.position, const Duration(seconds: 10));
        await tester.tap(find.byKey(const Key('mobile-replay-back-ten')));
        await tester.pump();
        expect(driver.position, Duration.zero);
        await tester.tap(find.byKey(const Key('mobile-replay-toggle')));
        await tester.pump(const Duration(milliseconds: 200));
        expect(controller.state.isPlaying, isTrue);
        if (size == const Size(402, 874) && scale == 1) {
          final progress = tester.getRect(
            find.byKey(const Key('mobile-replay-progress')),
          );
          final drag = await tester.startGesture(
            Offset(progress.left + progress.width * .3, progress.center.dy),
          );
          await drag.moveTo(
            Offset(progress.left + progress.width * .6, progress.center.dy),
          );
          await tester.pump();
          expect(controller.state.isPlaying, isFalse);
          await drag.up();
          await tester.pump();
          expect(controller.state.isPlaying, isTrue);
          expect(
            controller.state.presentationPosition.inSeconds,
            inInclusiveRange(50, 90),
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await tester.pump();
          expect(controller.state.isPlaying, isFalse);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          controller.play();
        }
        await tester.tap(find.byKey(const Key('mobile-replay-open-search')));
        await tester.pumpAndSettle();
        expect(controller.state.isPlaying, isFalse);
        expect(find.byKey(const Key('mobile-replay-progress')), findsNothing);
        await tester.enterText(
          find.byKey(const Key('mobile-replay-search')),
          'deploy',
        );
        await tester.pump();
        expect(searches.last, 'deploy');
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('mobile-replay-close-search')));
        await tester.pumpAndSettle();
        expect(searches.last, '');
        await tester.tap(find.byKey(const Key('mobile-replay-more')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.byKey(const Key('mobile-replay-speed-2.0')),
          120,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('mobile-replay-options-sheet')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        for (
          var i = 0;
          i < 8 &&
              find
                  .byKey(const Key('mobile-replay-speed-2.0'))
                  .hitTestable()
                  .evaluate()
                  .isEmpty;
          i++
        ) {
          await tester.drag(
            find.byKey(const Key('mobile-replay-options-sheet')),
            const Offset(0, -100),
          );
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const Key('mobile-replay-speed-2.0')));
        await tester.pump();
        expect(controller.state.speed, 2);
        Navigator.of(
          tester.element(find.byKey(const Key('mobile-replay-options-sheet'))),
        ).pop();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('mobile-replay-content-only')));
        await tester.pump();
        expect(find.byKey(const Key('mobile-replay-toggle')), findsNothing);
        await tester.tap(find.byKey(const Key('mobile-replay-show-controls')));
        await tester.pump();
        expect(find.byKey(const Key('mobile-replay-toggle')), findsOneWidget);
        await tester.tap(find.byKey(const Key('mobile-replay-close')));
        expect(closed, isTrue);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
