import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/recording/replay_viewport_layout.dart';

void main() {
  testWidgets('recorded viewport scales down proportionally to fit', (
    tester,
  ) async {
    const contentKey = Key('recorded-content');
    const availableFrameKey = Key('available-frame');
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            key: availableFrameKey,
            width: 400,
            height: 240,
            child: ReplayViewportFit(
              recordedViewportSize: Size(800, 400),
              contentKey: contentKey,
              child: ColoredBox(color: Colors.black),
            ),
          ),
        ),
      ),
    );

    expect(tester.getRect(find.byKey(contentKey)).size, const Size(400, 200));
    expect(
      tester.getTopLeft(find.byKey(contentKey)).dy,
      tester.getTopLeft(find.byKey(availableFrameKey)).dy,
    );
    expect(
      tester.getCenter(find.byKey(contentKey)).dx,
      tester.getCenter(find.byKey(availableFrameKey)).dx,
    );
    expect(
      find.bySemanticsLabel('Replay viewport fit 50 percent'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('recorded viewport is not enlarged above 100 percent', (
    tester,
  ) async {
    const contentKey = Key('recorded-content');

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 1000,
            height: 600,
            child: ReplayViewportFit(
              recordedViewportSize: Size(400, 200),
              contentKey: contentKey,
              child: ColoredBox(color: Colors.black),
            ),
          ),
        ),
      ),
    );

    expect(tester.getRect(find.byKey(contentKey)).size, const Size(400, 200));
  });

  testWidgets('floating replay dock moves from its handle and can reset', (
    tester,
  ) async {
    const dockKey = Key('floating-dock');
    const handleKey = Key('dock-handle');
    Size? availableSize;
    final dragStates = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 800,
            height: 600,
            child: ReplayFloatingStage(
              recordedViewportSize: const Size(800, 600),
              dragHandleColor: Colors.white,
              floatingDockKey: dockKey,
              dragHandleKey: handleKey,
              onAvailableSizeChanged: (value) {
                availableSize = value;
              },
              onDockDragStateChanged: dragStates.add,
              viewport: const ColoredBox(color: Colors.black),
              dock: const SizedBox(
                height: 100,
                child: ColoredBox(color: Colors.blue),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(availableSize, const Size(800, 600));
    final initialTop = tester.getTopLeft(find.byKey(dockKey)).dy;

    await tester.drag(find.byKey(handleKey), const Offset(0, -140));
    await tester.pumpAndSettle();

    final movedTop = tester.getTopLeft(find.byKey(dockKey)).dy;
    expect(movedTop, lessThan(initialTop - 100));
    expect(dragStates, <bool>[true, false]);

    await tester.tap(find.byKey(handleKey));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(handleKey));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.byKey(dockKey)).dy, closeTo(initialTop, 1));
  });
}
