import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

class _Output {
  int count = 420;
  bool running = false;
  final requests = <int>[];
  Map<String, Object?> snapshot(Map<String, Object?> request) {
    final full = request['id'] != null;
    final start = full
        ? request['offset'] as int? ?? 0
        : (count - 48).clamp(0, count);
    final limit = full ? request['limit'] as int? ?? 2048 : 48;
    final end = (start + limit).clamp(0, count);
    if (full) requests.add(start);
    final block = <String, Object?>{
      'id': 'long',
      'command': 'seq 1 $count',
      'cwd': '/srv/app',
      'columns': 40,
      'running': running,
      'exitCode': running ? null : 0,
      'offset': start,
      'totalLines': count,
      'matchingLines': count,
      'nextOffset': end < count ? end : null,
      'lines': [
        for (var i = start; i < end; i++)
          {
            'index': i,
            'source_row': i + 100,
            'text': 'output ${i + 1}',
            'wrapped': false,
          },
      ],
    };
    return full
        ? {'block': block}
        : {
            'blocks': [block],
          };
  }
}

Future<void> _mount(
  WidgetTester tester,
  CommandBlockController controller, {
  Size size = const Size(390, 844),
  double scale = 1,
  bool dark = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        platform: TargetPlatform.iOS,
        brightness: dark ? Brightness.dark : Brightness.light,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: TerminalCommandBlocksView(
          controller: controller,
          onReinput: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'compact previews keep six rows and height when keyboard opens',
    (tester) async {
      final output = _Output();
      final controller = CommandBlockController(request: output.snapshot)
        ..refresh();
      await _mount(tester, controller);
      final block = find.byKey(const ValueKey('command-block-long'));
      final height = tester.getSize(block).height;
      final terminal = tester.widget<TerminalViewport>(
        find.byType(TerminalViewport),
      );
      expect(terminal.controller.frame.rows.length, 6);
      expect(terminal.controller.frame.rows.first.text, 'output 415');
      expect(tester.testTextInput.hasAnyClients, isFalse);
      expect(
        find.byKey(const ValueKey('block-output-scroll-long')),
        findsNothing,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 340);
      await tester.pumpAndSettle();
      expect(tester.getSize(block).height, height);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'viewport resize follows the preview tail only before manual reading',
    (tester) async {
      final output = _Output();
      final controller = CommandBlockController(request: output.snapshot)
        ..refresh();
      await _mount(tester, controller);
      tester.view.physicalSize = const Size(390, 200);
      await tester.pumpAndSettle();
      final list = find.byType(CommandTimelineView);
      final scroll = tester.widget<CommandTimelineView>(list).controller;
      expect(scroll.offset, scroll.position.maxScrollExtent);
      expect(
        find.byKey(const ValueKey('block-expand-long')).hitTestable(),
        findsOneWidget,
      );
      await tester.drag(list, const Offset(0, 100));
      await tester.pumpAndSettle();
      final reading = scroll.offset;
      tester.view.physicalSize = const Size(390, 180);
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(reading, .1));
      expect(scroll.offset, lessThan(scroll.position.maxScrollExtent));
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'touch reader crosses native pages without jumping or opening IME',
    (tester) async {
      final output = _Output();
      final controller = CommandBlockController(request: output.snapshot)
        ..refresh();
      await _mount(tester, controller);
      final previewPosition = tester.getTopLeft(
        find.byKey(const ValueKey('command-block-long')),
      );
      await tester.tap(find.byKey(const ValueKey('block-expand-long')));
      await tester.pumpAndSettle();
      final reader = find.byKey(const Key('block-reader-scroll'));
      final scroll = tester.widget<ListView>(reader).controller!;
      expect(scroll.offset, 0);
      expect(output.requests, contains(0));
      expect(tester.testTextInput.hasAnyClients, isFalse);
      await tester.tapAt(tester.getTopLeft(reader) + const Offset(70, 15));
      await tester.pump();
      expect(tester.testTextInput.hasAnyClients, isFalse);
      for (var i = 0; i < 8; i++) {
        final before = scroll.offset;
        await tester.timedDragFrom(
          tester.getCenter(reader),
          const Offset(0, -250),
          const Duration(milliseconds: 400),
        );
        await tester.pumpAndSettle();
        expect(scroll.offset, greaterThan(before + 150));
        final retained = scroll.offset;
        controller.setAppearance(dividers: i.isEven);
        await tester.pumpAndSettle();
        expect(scroll.offset, closeTo(retained, .1));
      }
      expect(output.requests.any((offset) => offset >= 128), isTrue);
      final retained = scroll.offset;
      await tester.tap(find.byKey(const Key('block-reader-close')));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('command-block-long'))),
        previewPosition,
      );
      await tester.tap(find.byKey(const ValueKey('block-expand-long')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ListView>(reader).controller!.offset,
        closeTo(retained, .1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'running output pauses follow on touch and resumes only explicitly',
    (tester) async {
      final output = _Output()..running = true;
      final controller = CommandBlockController(request: output.snapshot)
        ..refresh();
      await _mount(tester, controller);
      await tester.tap(find.byKey(const ValueKey('block-expand-long')));
      await tester.pumpAndSettle();
      final reader = find.byKey(const Key('block-reader-scroll'));
      final scroll = tester.widget<ListView>(reader).controller!;
      expect(scroll.offset, scroll.position.maxScrollExtent);
      final gesture = await tester.startGesture(
        tester.getCenter(reader),
        kind: PointerDeviceKind.touch,
      );
      await gesture.moveBy(const Offset(0, 50));
      await tester.pump(const Duration(milliseconds: 16));
      for (var i = 0; i < 6; i++) {
        final previous = scroll.offset;
        await gesture.moveBy(const Offset(0, 35));
        await tester.pump(const Duration(milliseconds: 16));
        expect(scroll.offset, lessThan(previous));
        final reading = scroll.offset;
        output.count += 5;
        controller.refresh();
        await tester.pump();
        expect(scroll.offset, closeTo(reading, .1));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      final reading = scroll.offset;
      output.count += 40;
      controller.refresh();
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(reading, .1));
      await tester.tap(find.byKey(const Key('block-reader-latest')));
      await tester.pumpAndSettle();
      expect(scroll.offset, scroll.position.maxScrollExtent);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS}),
  );

  for (final size in [
    const Size(360, 640),
    const Size(844, 390),
    const Size(360, 330),
  ]) {
    testWidgets(
      'large dark text supports compact previews and reader at $size',
      (tester) async {
        final output = _Output();
        final controller = CommandBlockController(request: output.snapshot)
          ..refresh();
        await _mount(tester, controller, size: size, scale: 2, dark: true);
        await tester.ensureVisible(
          find.byKey(const ValueKey('block-expand-long')),
        );
        await tester.tap(find.byKey(const ValueKey('block-expand-long')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('block-reader')), findsOneWidget);
        expect(tester.testTextInput.hasAnyClients, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
      variant: const TargetPlatformVariant({TargetPlatform.iOS}),
    );
  }
}
