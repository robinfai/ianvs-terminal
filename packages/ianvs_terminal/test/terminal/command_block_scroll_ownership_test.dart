import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import 'command_blocks_test.dart' show block;

class _NestedBlock {
  final outer = ScrollController(initialScrollOffset: 100);
  final ValueNotifier<bool> visible = ValueNotifier(true);

  Future<void> mount(WidgetTester tester, {int columns = 80}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: SingleChildScrollView(
            controller: outer,
            child: Column(
              children: [
                const SizedBox(height: 200),
                ValueListenableBuilder(
                  valueListenable: visible,
                  builder: (_, showing, _) => showing
                      ? CommandBlockTerminal(
                          block: CommandBlock.fromJson(
                            block('boundary', lineCount: 80, columns: columns),
                          )!,
                          maxHeight: 120,
                        )
                      : const SizedBox(height: 120),
                ),
                const SizedBox(height: 1200),
              ],
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
  }

  ScrollController inner(WidgetTester tester) => tester
      .widget<SingleChildScrollView>(
        find.byKey(const ValueKey('block-output-scroll-boundary')),
      )
      .controller!;

  Offset point(WidgetTester tester) =>
      tester.getCenter(find.byType(CommandBlockTerminal));

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    outer.dispose();
    visible.dispose();
  }
}

Future<void> _pan(
  WidgetTester tester,
  TestGesture gesture,
  Offset point,
  Offset pan,
  int ms,
) async {
  await gesture.panZoomUpdate(
    point,
    pan: pan,
    timeStamp: Duration(milliseconds: ms),
  );
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  for (final delegateToTimeline in [false, true]) {
    testWidgets(
      'DPR position replacement preserves the same trackpad gesture, outer: $delegateToTimeline',
      (tester) async {
        final fixture = _NestedBlock();
        TestGesture? gesture;
        addTearDown(tester.view.reset);
        try {
          await fixture.mount(tester);
          final inner = fixture.inner(tester);
          if (!delegateToTimeline) {
            inner.jumpTo(inner.position.maxScrollExtent / 2);
            await tester.pump();
          }
          final owner = delegateToTimeline ? fixture.outer : inner;
          final bystander = delegateToTimeline ? inner : fixture.outer;
          final bystanderBefore = bystander.offset;
          final point = fixture.point(tester);
          gesture = await tester.createGesture(
            kind: PointerDeviceKind.trackpad,
          );
          await gesture.panZoomStart(point);
          await _pan(tester, gesture, point, const Offset(0, -40), 16);
          await _pan(tester, gesture, point, const Offset(0, -90), 32);
          final beforeReplacement = owner.offset;
          final oldInner = inner.position;
          final oldOuter = fixture.outer.position;
          // Cross-density screen moves rebuild both scroll positions without
          // changing the logical window geometry or starting another gesture.
          tester.view.physicalSize = tester.view.physicalSize * 2;
          tester.view.devicePixelRatio = tester.view.devicePixelRatio * 2;
          await tester.pump();
          expect(inner.position, isNot(same(oldInner)));
          expect(fixture.outer.position, isNot(same(oldOuter)));
          await _pan(tester, gesture, point, const Offset(0, -140), 48);
          expect(owner.offset, closeTo(beforeReplacement + 50, .1));
          expect(bystander.offset, closeTo(bystanderBefore, .1));
          await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 64));
          gesture = null;
          final beforeInertia = owner.offset;
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 80));
          expect(owner.offset, greaterThan(beforeInertia));
          await tester.pumpAndSettle();
          expect(owner.position.isScrollingNotifier.value, isFalse);
          expect(bystander.offset, closeTo(bystanderBefore, .1));
          expect(tester.takeException(), isNull);
        } finally {
          if (gesture != null) await gesture.panZoomEnd();
          await fixture.close(tester);
        }
      },
      variant: const TargetPlatformVariant({TargetPlatform.macOS}),
    );
  }

  for (final trackpad in [false, true]) {
    testWidgets(
      'a new ${trackpad ? 'trackpad' : 'wheel'} gesture at the output boundary scrolls the timeline once',
      (tester) async {
        final fixture = _NestedBlock();
        try {
          await fixture.mount(tester);
          final inner = fixture.inner(tester);
          final outer = fixture.outer;
          expect(inner.offset, inner.position.maxScrollExtent);
          final end = inner.offset;
          final before = outer.offset;
          final point = tester.getCenter(find.byType(CommandBlockTerminal));
          if (trackpad) {
            final gesture = await tester.createGesture(
              kind: PointerDeviceKind.trackpad,
            );
            await gesture.panZoomStart(point);
            await gesture.panZoomUpdate(
              point,
              pan: const Offset(0, -40),
              timeStamp: const Duration(milliseconds: 16),
            );
            await tester.pump(const Duration(milliseconds: 16));
            await gesture.panZoomUpdate(
              point,
              pan: const Offset(0, -90),
              timeStamp: const Duration(milliseconds: 32),
            );
            await tester.pump(const Duration(milliseconds: 16));
            expect(outer.offset, greaterThan(before + 40));
            expect(outer.offset, lessThanOrEqualTo(before + 90));
            expect(inner.offset, end);
            await gesture.panZoomEnd(
              timeStamp: const Duration(milliseconds: 48),
            );
            final beforeInertia = outer.offset;
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 80));
            expect(outer.offset, greaterThan(beforeInertia));
            expect(inner.offset, end);
          } else {
            await tester.sendEventToBinding(
              PointerScrollEvent(
                position: point,
                scrollDelta: const Offset(0, 50),
              ),
            );
            await tester.pump();
            expect(outer.offset, closeTo(before + 50, .1));
            expect(inner.offset, end);
          }
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.close(tester);
        }
      },
      variant: const TargetPlatformVariant({TargetPlatform.macOS}),
    );
  }

  testWidgets(
    'reaching an edge keeps the same gesture inside output until the next gesture',
    (tester) async {
      final fixture = _NestedBlock();
      try {
        await fixture.mount(tester);
        final inner = fixture.inner(tester);
        final end = inner.position.maxScrollExtent;
        inner.jumpTo(end - 60);
        await tester.pump();
        final before = fixture.outer.offset;
        final point = fixture.point(tester);
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.trackpad,
        );
        await gesture.panZoomStart(point);
        await _pan(tester, gesture, point, const Offset(0, -30), 16);
        await _pan(tester, gesture, point, const Offset(0, -70), 32);
        expect(inner.offset, greaterThan(end - 60));
        expect(inner.offset, lessThan(end));
        await _pan(tester, gesture, point, const Offset(0, -120), 48);
        await _pan(tester, gesture, point, const Offset(0, -170), 64);
        expect(inner.offset, greaterThanOrEqualTo(end));
        expect(fixture.outer.offset, before);
        final overscrolled = inner.offset;
        await _pan(tester, gesture, point, const Offset(0, -120), 80);
        expect(inner.offset, lessThan(overscrolled));
        expect(fixture.outer.offset, before);
        await _pan(tester, gesture, point, const Offset(0, -190), 96);
        await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 112));
        await tester.pumpAndSettle();
        expect(inner.offset, end);
        expect(fixture.outer.offset, before);

        final next = await tester.createGesture(
          kind: PointerDeviceKind.trackpad,
        );
        await next.panZoomStart(point);
        await _pan(tester, next, point, const Offset(0, -40), 16);
        await _pan(tester, next, point, const Offset(0, -90), 32);
        expect(fixture.outer.offset, closeTo(before + 50, .1));
        expect(inner.offset, end);
        await next.panZoomEnd(timeStamp: const Duration(milliseconds: 48));
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
      }
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );

  for (final atStart in [false, true]) {
    testWidgets(
      'boundary-selected timeline retains a reversing trackpad gesture, top: $atStart',
      (tester) async {
        final fixture = _NestedBlock();
        try {
          await fixture.mount(tester);
          final inner = fixture.inner(tester);
          if (atStart) inner.jumpTo(0);
          await tester.pump();
          final innerBefore = inner.offset;
          final outerBefore = fixture.outer.offset;
          final sign = atStart ? 1.0 : -1.0;
          final point = fixture.point(tester);
          final gesture = await tester.createGesture(
            kind: PointerDeviceKind.trackpad,
          );
          await gesture.panZoomStart(point);
          await _pan(tester, gesture, point, Offset(0, sign * 40), 16);
          await _pan(tester, gesture, point, Offset(0, sign * 90), 32);
          expect(fixture.outer.offset, closeTo(outerBefore - sign * 50, .1));
          await _pan(tester, gesture, point, Offset(0, sign * 50), 48);
          expect(fixture.outer.offset, closeTo(outerBefore - sign * 10, .1));
          expect(inner.offset, innerBefore);
          await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 64));
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.close(tester);
        }
      },
      variant: const TargetPlatformVariant({TargetPlatform.macOS}),
    );
  }

  testWidgets(
    'horizontal trackpad reading leaves both vertical positions unchanged',
    (tester) async {
      final fixture = _NestedBlock();
      try {
        await fixture.mount(tester, columns: 240);
        final inner = fixture.inner(tester);
        final horizontal = tester
            .stateList<ScrollableState>(
              find.descendant(
                of: find.byType(CommandBlockTerminal),
                matching: find.byType(Scrollable),
              ),
            )
            .singleWhere(
              (state) =>
                  axisDirectionToAxis(state.position.axisDirection) ==
                  Axis.horizontal,
            )
            .position;
        expect(horizontal.maxScrollExtent, greaterThan(90));
        final innerBefore = inner.offset;
        final outerBefore = fixture.outer.offset;
        final point = fixture.point(tester);
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.trackpad,
        );
        await gesture.panZoomStart(point);
        await _pan(tester, gesture, point, const Offset(-40, 0), 16);
        await _pan(tester, gesture, point, const Offset(-90, 0), 32);
        expect(horizontal.pixels, closeTo(50, .1));
        expect(inner.offset, innerBefore);
        expect(fixture.outer.offset, outerBefore);
        await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 48));
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
      }
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );

  for (final (wholeTree, replacePosition) in [
    (false, false),
    (true, false),
    (false, true),
    (true, true),
  ]) {
    testWidgets(
      'unmounting output cancels its delegated trackpad drag safely, whole tree: $wholeTree, replaced: $replacePosition',
      (tester) async {
        final fixture = _NestedBlock();
        addTearDown(tester.view.reset);
        try {
          await fixture.mount(tester);
          final point = fixture.point(tester);
          final gesture = await tester.createGesture(
            kind: PointerDeviceKind.trackpad,
          );
          await gesture.panZoomStart(point);
          await _pan(tester, gesture, point, const Offset(0, -40), 16);
          await _pan(tester, gesture, point, const Offset(0, -90), 32);
          if (replacePosition) {
            tester.view.physicalSize = tester.view.physicalSize * 2;
            tester.view.devicePixelRatio = tester.view.devicePixelRatio * 2;
            await tester.pump();
          }
          if (wholeTree) {
            await tester.pumpWidget(const SizedBox.shrink());
          } else {
            fixture.visible.value = false;
            await tester.pump();
          }
          await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 48));
          await tester.pumpAndSettle();
          if (!wholeTree) {
            expect(fixture.outer.hasClients, isTrue);
            expect(fixture.outer.position.isScrollingNotifier.value, isFalse);
          }
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.close(tester);
        }
      },
      variant: const TargetPlatformVariant({TargetPlatform.macOS}),
    );
  }

  testWidgets(
    'a boundary-owned gesture keeps scrolling across lazy block lifetimes',
    (tester) async {
      final rows = [for (var i = 0; i < 24; i++) block('$i', lineCount: 80)];
      final controller = CommandBlockController(
        request: (_) => {'blocks': rows},
      )..refresh();
      final outer = ScrollController(initialScrollOffset: 600);
      final following = ValueNotifier(false);
      TestGesture? gesture;
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.macOS),
            home: Scaffold(
              body: TerminalCommandBlocksView(
                controller: controller,
                scrollController: outer,
                followTail: following,
                showToolbar: false,
                onReinput: (_) => fail('Scrolling must not re-input a command'),
              ),
            ),
          ),
        );
        for (var i = 0; i < 8; i++) {
          await tester.pump();
        }
        final origin = find.byType(CommandBlockTerminal).hitTestable().first;
        final originState = tester.state(origin);
        final blockId = tester.widget<CommandBlockTerminal>(origin).block.id;
        final inner = tester
            .widget<SingleChildScrollView>(
              find.byKey(ValueKey('block-output-scroll-$blockId')),
            )
            .controller!;
        expect(inner.offset, inner.position.maxScrollExtent);
        final point = tester.getCenter(origin);
        gesture = await tester.createGesture(kind: PointerDeviceKind.trackpad);
        await gesture.panZoomStart(point);
        await _pan(tester, gesture, point, const Offset(0, -40), 16);
        var previous = outer.offset;
        for (var step = 1; step <= 24; step++) {
          await _pan(
            tester,
            gesture,
            point,
            Offset(0, -40 - 64.0 * step),
            16 + 16 * step,
          );
          expect(
            outer.offset,
            closeTo(previous + 64, .1),
            reason: 'step $step',
          );
          previous = outer.offset;
          controller.refresh();
          await tester.pump();
          expect(outer.offset, closeTo(previous, .1));
        }
        expect(originState.mounted, isTrue);
        await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 416));
        gesture = null;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        expect(outer.offset, greaterThan(previous + 10));
        expect(originState.mounted, isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        if (gesture != null) {
          await gesture.panZoomEnd();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        outer.dispose();
        following.dispose();
      }
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );
}
