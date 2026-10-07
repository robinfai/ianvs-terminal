import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.iOS,
    TargetPlatform.android,
  ]) {
    for (final reduced in [false, true]) {
      testWidgets('page and dialog motion respects $reduced on $platform', (
        tester,
      ) async {
        tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: reduced);
        addTearDown(
          tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: buildIanvsTerminalTheme(
              Brightness.light,
              platform: platform,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (context) => Scaffold(
                        key: const Key('destination'),
                        body: TextButton(
                          onPressed: () => showDialog<void>(
                            context: context,
                            animationStyle: appDialogAnimation(context),
                            builder: (_) =>
                                const AlertDialog(title: Text('Dialog')),
                          ),
                          child: const Text('Open dialog'),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Open page'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open page'));
        await tester.pump();
        await tester.pump();
        final destination = find.byKey(const Key('destination'));
        final before = tester.getRect(destination);
        await tester.pump(const Duration(milliseconds: 1));
        if (reduced) {
          expect(
            before,
            Offset.zero &
                (tester.view.physicalSize / tester.view.devicePixelRatio),
          );
          expect(tester.getRect(destination), before);
          expect(
            find.ancestor(
              of: destination,
              matching: find.byType(SlideTransition),
            ),
            findsNothing,
          );
          expect(
            find.ancestor(
              of: destination,
              matching: find.byType(FadeTransition),
            ),
            findsNothing,
          );
        } else {
          expect(
            ModalRoute.of(tester.element(destination))!.animation!.isCompleted,
            isFalse,
          );
        }
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open dialog'));
        await tester.pump();
        final route = ModalRoute.of(tester.element(find.byType(AlertDialog)))!;
        expect(route.animation!.isCompleted, reduced);
        await tester.pumpAndSettle();
        Navigator.of(tester.element(find.byType(AlertDialog))).pop();
        await tester.pumpAndSettle();
        Navigator.of(tester.element(destination)).pop();
        await tester.pumpAndSettle();
        expect(find.text('Open page'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
