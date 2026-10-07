import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';

import 'command_blocks_test.dart' show block;

Future<void> _mount(
  WidgetTester tester,
  CommandBlockController blocks,
  ScrollController scroll,
  ValueNotifier<bool> following, {
  TargetPlatform platform = TargetPlatform.macOS,
}) async {
  tester.view.physicalSize = platform == TargetPlatform.iOS
      ? const Size(390, 600)
      : const Size(960, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      home: Scaffold(
        body: TerminalCommandBlocksView(
          controller: blocks,
          scrollController: scroll,
          followTail: following,
          onReinput: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _wheel(WidgetTester tester, Offset point, double delta) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(position: point, scrollDelta: Offset(0, delta)),
  );
  await tester.pumpAndSettle();
}

Offset _listPoint(WidgetTester tester) =>
    tester.getTopLeft(find.byType(CommandTimelineView)) + const Offset(3, 180);

void main() {
  testWidgets(
    'wheel releases immediately and reattaches near the bottom',
    (tester) async {
      final rows = [for (var i = 0; i < 20; i++) block('$i')];
      final blocks = CommandBlockController(request: (_) => {'blocks': rows})
        ..refresh();
      final scroll = ScrollController();
      final following = ValueNotifier(true);
      await _mount(tester, blocks, scroll, following);
      expect(scroll.position.extentAfter, lessThan(.1));

      await _wheel(tester, _listPoint(tester), -4);
      final reading = scroll.offset;
      expect(following.value, isFalse);
      expect(scroll.position.extentAfter, closeTo(4, .1));
      rows.add(block('new-output'));
      blocks.refresh();
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(reading, .1));

      // Downward movement ending two terminal rows from the end is magnetic.
      await _wheel(
        tester,
        _listPoint(tester),
        scroll.position.extentAfter - 12,
      );
      expect(following.value, isTrue);
      expect(scroll.position.extentAfter, lessThan(.1));
      rows.add(block('more-output'));
      blocks.refresh();
      await tester.pumpAndSettle();
      expect(scroll.position.extentAfter, lessThan(.1));
      tester.view.physicalSize = const Size(960, 650);
      await tester.pumpAndSettle();
      expect(scroll.position.extentAfter, lessThan(.1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      blocks.dispose();
      scroll.dispose();
      following.dispose();
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );

  testWidgets(
    'phone drag waits for release and preserves direction changes',
    (tester) async {
      final rows = [for (var i = 0; i < 20; i++) block('$i')];
      final blocks = CommandBlockController(request: (_) => {'blocks': rows})
        ..refresh();
      final scroll = ScrollController();
      final following = ValueNotifier(true);
      await _mount(
        tester,
        blocks,
        scroll,
        following,
        platform: TargetPlatform.iOS,
      );
      following.value = false;
      scroll.jumpTo(scroll.position.maxScrollExtent - 150);
      await tester.pumpAndSettle();

      final drag = await tester.startGesture(_listPoint(tester));
      await drag.moveBy(const Offset(0, -30));
      await tester.pump();
      await drag.moveBy(Offset(0, -(scroll.position.extentAfter - 12)));
      await tester.pump();
      expect(following.value, isFalse);
      expect(scroll.position.isScrollingNotifier.value, isTrue);
      final held = scroll.offset;
      rows.last['exitCode'] = 1;
      blocks.refresh();
      await tester.pump();
      expect(scroll.offset, closeTo(held, .1));
      expect(scroll.position.isScrollingNotifier.value, isTrue);

      // Reverse upward inside the magnetic zone: releasing must not pull back.
      await drag.moveBy(const Offset(0, 4));
      await tester.pump(const Duration(milliseconds: 500));
      await drag.up();
      await tester.pumpAndSettle();
      expect(following.value, isFalse);
      expect(scroll.position.extentAfter, greaterThan(1));

      final down = await tester.startGesture(_listPoint(tester));
      await down.moveBy(const Offset(0, -20));
      await tester.pump();
      await down.moveBy(const Offset(0, -4));
      await tester.pump(const Duration(milliseconds: 500));
      await down.up();
      await tester.pumpAndSettle();
      expect(following.value, isTrue);
      expect(scroll.position.extentAfter, lessThan(.1));
      rows.add(block('new-output'));
      blocks.refresh();
      await tester.pumpAndSettle();
      expect(scroll.position.extentAfter, lessThan(.1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      blocks.dispose();
      scroll.dispose();
      following.dispose();
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'inner output has its own magnet and never detaches the list',
    (tester) async {
      final rows = [
        for (var i = 0; i < 10; i++) block('$i'),
        block('live', running: true, lineCount: 80, columns: 180),
      ];
      final blocks = CommandBlockController(request: (_) => {'blocks': rows})
        ..refresh();
      final scroll = ScrollController();
      final following = ValueNotifier(true);
      await _mount(tester, blocks, scroll, following);
      final output = find.byKey(const ValueKey('block-output-scroll-live'));
      final inner = tester.widget<SingleChildScrollView>(output).controller!;
      final point = tester.getCenter(output);
      expect(inner.position.extentAfter, lessThan(.1));
      await tester.sendEventToBinding(
        PointerScrollEvent(position: point, scrollDelta: const Offset(20, 0)),
      );
      await tester.pumpAndSettle();
      expect(following.value, isTrue);
      await _wheel(tester, point, -4);
      expect(following.value, isTrue);
      final reading = inner.offset;
      rows.last = block('live', running: true, lineCount: 84, columns: 180);
      blocks.refresh();
      await tester.pumpAndSettle();
      expect(inner.offset, closeTo(reading, .1));
      expect(scroll.position.extentAfter, lessThan(.1));
      await _wheel(tester, point, inner.position.extentAfter - 12);
      expect(inner.position.extentAfter, lessThan(.1));
      rows.last = block('live', running: true, lineCount: 88, columns: 180);
      blocks.refresh();
      await tester.pumpAndSettle();
      expect(inner.position.extentAfter, lessThan(.1));
      expect(following.value, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      blocks.dispose();
      scroll.dispose();
      following.dispose();
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );

  testWidgets(
    'restoration stays detached and keyboard End restores follow',
    (tester) async {
      final rows = [for (var i = 0; i < 20; i++) block('$i')];
      final blocks = CommandBlockController(request: (_) => {'blocks': rows})
        ..refresh();
      final scroll = ScrollController();
      final following = ValueNotifier(true);
      await _mount(tester, blocks, scroll, following);
      following.value = false;
      scroll.jumpTo(scroll.position.maxScrollExtent - 12);
      final reading = scroll.offset;
      rows.last['exitCode'] = 1;
      blocks.refresh();
      await tester.pumpAndSettle();
      expect(following.value, isFalse);
      expect(scroll.offset, closeTo(reading, .1));

      final focus = tester
          .widget<Focus>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Focus &&
                  widget.focusNode?.debugLabel == 'Command blocks',
            ),
          )
          .focusNode!;
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(following.value, isTrue);
      expect(scroll.position.extentAfter, lessThan(.1));
      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.pumpAndSettle();
      expect(following.value, isFalse);
      final page = scroll.offset;
      rows.add(block('new-output'));
      blocks.refresh();
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(page, .1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      blocks.dispose();
      scroll.dispose();
      following.dispose();
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );
}
