import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

Map<String, Object?> block(
  String id, {
  bool running = false,
  int columns = 80,
  int lineCount = 1,
}) => {
  'id': id,
  'command': 'echo $id',
  'cwd': '~/project',
  'running': running,
  'exitCode': running ? null : 0,
  'columns': columns,
  'cursorLine': 0,
  'cursorColumn': 4,
  'totalLines': lineCount,
  'matchingLines': lineCount,
  'lines': [
    for (var i = 0; i < lineCount; i++)
      {'index': i, 'text': 'text', 'wrapped': false},
  ],
};

void main() {
  test('native list budget stays bounded unless the host composes sources', () {
    final blocks = [for (var i = 0; i < 256; i++) block('block-$i')];
    final native = CommandBlockController(request: (_) => {'blocks': blocks});
    final composed = CommandBlockController(
      request: (_) => {'blocks': blocks},
      maximumBlocks: null,
    );
    addTearDown(native.dispose);
    addTearDown(composed.dispose);
    native.refresh();
    composed.refresh();
    expect(native.blocks, hasLength(128));
    expect(composed.blocks, hasLength(256));
  });
  test('command decoding matches native 64 KiB UTF-8 limit', () {
    for (final command in ['x' * 65536, '😀' * 16384]) {
      final parsed = CommandBlock.fromJson({
        ...block('long'),
        'command': command,
      });
      expect(parsed?.command, command);
      expect(
        CommandBlock.fromJson({...block('long'), 'command': '${command}x'}),
        isNull,
      );
    }
  });
  for (final scene in [
    (size: const Size(900, 900), font: const TerminalFontConfig(), scale: 1.0),
    (
      size: const Size(640, 620),
      font: const TerminalFontConfig(size: 18, lineHeight: 1.6),
      scale: 1.0,
    ),
    (size: const Size(360, 330), font: const TerminalFontConfig(), scale: 2.0),
  ]) {
    testWidgets(
      'whole block fits one third, uses full rows and expands at $scene',
      (tester) async {
        tester.view.physicalSize = scene.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final controller = CommandBlockController(
          request: (_) => {
            'blocks': [block('long', lineCount: 100), block('short')],
          },
        )..refresh();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.macOS),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scene.scale)),
              child: child!,
            ),
            home: Scaffold(
              body: TerminalCommandBlocksView(
                controller: controller,
                font: scene.font,
                onReinput: (_) {},
              ),
            ),
          ),
        );
        for (var i = 0; i < 8; i++) {
          await tester.pump();
        }
        final budget =
            tester.getSize(find.byType(CommandTimelineView)).height / 3;
        final whole = find.byKey(const ValueKey('command-block-long'));
        final output = find.byKey(const ValueKey('block-terminal-long'));
        expect(tester.getSize(whole).height, lessThanOrEqualTo(budget));
        expect(
          tester
              .getSize(find.byKey(const ValueKey('command-block-short')))
              .height,
          lessThanOrEqualTo(budget),
        );
        final viewport = tester.widget<TerminalViewport>(
          find.descendant(of: output, matching: find.byType(TerminalViewport)),
        );
        final cellHeight = viewport.controller.measuredCellSize!.height;
        final visibleRows = tester.getSize(output).height / cellHeight;
        expect(visibleRows, closeTo(visibleRows.roundToDouble(), .01));
        expect(viewport.controller.frame.rows, hasLength(100));
        await tester.tap(find.byKey(const ValueKey('block-expand-long')));
        for (var i = 0; i < 12; i++) {
          await tester.pump();
        }
        expect(tester.getSize(whole).height, greaterThan(budget));
        expect(tester.getSize(output).height, closeTo(cellHeight * 100, .01));
        controller.refresh();
        await tester.pump();
        expect(controller.expandedOutput, contains('long'));
        await tester.tap(find.byKey(const ValueKey('block-expand-long')));
        for (var i = 0; i < 12; i++) {
          await tester.pump();
        }
        expect(tester.getSize(whole).height, lessThanOrEqualTo(budget));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
    );
  }

  for (final running in [false, true]) {
    testWidgets(
      'capped output keeps pixel scrolling and inertia during refresh, running: $running',
      (tester) async {
        final source = block('scroll', running: running, lineCount: 60);
        final controller = CommandBlockController(
          request: (_) => {
            'blocks': [source],
          },
        )..refresh();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TerminalCommandBlocksView(
                controller: controller,
                onReinput: (_) {},
              ),
            ),
          ),
        );
        for (var i = 0; i < 8; i++) {
          await tester.pump();
        }
        final output = find.byKey(const ValueKey('block-terminal-scroll'));
        final inner = tester
            .widget<SingleChildScrollView>(
              find.byKey(const ValueKey('block-output-scroll-scroll')),
            )
            .controller!;
        final outer = tester
            .widget<CommandTimelineView>(find.byType(CommandTimelineView))
            .controller;
        final point = tester.getCenter(output);
        final start = inner.offset;
        final outerStart = outer.offset;
        expect(start, greaterThan(500));
        await tester.sendEventToBinding(
          PointerScrollEvent(position: point, scrollDelta: const Offset(0, -4)),
        );
        await tester.pump();
        expect(inner.offset, closeTo(start - 4, .1));
        expect(outer.offset, outerStart);
        final trackpad = await tester.createGesture(
          kind: PointerDeviceKind.trackpad,
        );
        await trackpad.panZoomStart(point);
        await trackpad.panZoomUpdate(
          point,
          pan: const Offset(0, 30),
          timeStamp: const Duration(milliseconds: 16),
        );
        await tester.pump(const Duration(milliseconds: 16));
        var previous = inner.offset;
        for (var step = 1; step <= 8; step++) {
          await trackpad.panZoomUpdate(
            point,
            pan: Offset(0, 30 + 32.0 * step),
            timeStamp: Duration(milliseconds: 16 + step * 16),
          );
          await tester.pump(const Duration(milliseconds: 16));
          expect(inner.offset, closeTo(previous - 32, .1));
          previous = inner.offset;
          (source['lines']! as List<Map<String, Object>>).last['text'] =
              'update $step';
          controller.refresh();
          await tester.pump();
          expect(inner.offset, closeTo(previous, .1));
        }
        await trackpad.panZoomEnd(timeStamp: const Duration(milliseconds: 160));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        expect(inner.offset, lessThan(previous - 10));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
      variant: const TargetPlatformVariant({TargetPlatform.macOS}),
    );
  }

  testWidgets('short-window find remains reachable and Escape closes it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 220);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = CommandBlockController(
      request: (_) => {
        'blocks': [block('done')],
      },
    )..refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalCommandBlocksView(
            controller: controller,
            onReinput: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Find in blocks'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets(
    'offscreen bookmarks reveal lazily built blocks and wheel scroll is not pulled back',
    (tester) async {
      final rows = [for (var i = 0; i < 100; i++) block('$i')];
      final controller = CommandBlockController(
        request: (_) => {'blocks': rows},
      )..refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalCommandBlocksView(
              controller: controller,
              onReinput: (_) {},
            ),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      controller.select('0', reveal: true);
      for (var i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('echo 0').hitTestable(), findsOneWidget);
      controller.select('99', reveal: true);
      for (var i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('echo 99').hitTestable(), findsOneWidget);
      final view = tester.widget<CommandTimelineView>(
        find.byType(CommandTimelineView),
      );
      final scroll = view.controller;
      controller.clearSelection();
      final bottom = scroll.offset;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(
            find.byType(TerminalViewport).hitTestable().last,
          ),
          scrollDelta: const Offset(0, -100),
        ),
      );
      await tester.pump();
      expect(scroll.offset, lessThan(bottom - 20));
      final before = scroll.offset;
      rows.last['exitCode'] = 1;
      controller.refresh();
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      expect(scroll.offset, closeTo(before, 1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets(
    'block output passes pixel wheel deltas to vertical and horizontal scrollables',
    (tester) async {
      final controller = CommandBlockController(
        request: (_) => {
          'blocks': [block('wide', columns: 180, lineCount: 60)],
        },
      )..refresh();
      controller.expandedOutput.add('wide');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalCommandBlocksView(
              controller: controller,
              onReinput: (_) {},
            ),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      final list = find.byType(CommandTimelineView);
      final scroll = tester.widget<CommandTimelineView>(list).controller;
      final point = tester.getCenter(list);
      expect(
        tester.getRect(find.byType(TerminalViewport)).contains(point),
        isTrue,
      );
      final before = scroll.offset;
      await tester.sendEventToBinding(
        PointerScrollEvent(position: point, scrollDelta: const Offset(0, -4)),
      );
      await tester.pump();
      expect(scroll.offset, closeTo(before - 4, .1));
      final horizontal = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(CommandBlockTerminal),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.right,
              ),
            ),
          )
          .position;
      expect(horizontal.maxScrollExtent, greaterThan(80));
      await tester.sendEventToBinding(
        PointerScrollEvent(position: point, scrollDelta: const Offset(64, 0)),
      );
      await tester.pump();
      expect(horizontal.pixels, closeTo(64, .1));
      expect(scroll.offset, closeTo(before - 4, .1));
      final trackpad = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      await trackpad.panZoomStart(point);
      await trackpad.panZoomUpdate(
        point,
        pan: const Offset(-40, 0),
        timeStamp: const Duration(milliseconds: 16),
      );
      await tester.pump(const Duration(milliseconds: 16));
      final beforePan = horizontal.pixels;
      await trackpad.panZoomUpdate(
        point,
        pan: const Offset(-104, 0),
        timeStamp: const Duration(milliseconds: 32),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(horizontal.pixels, closeTo(beforePan + 64, .1));
      expect(horizontal.isScrollingNotifier.value, isTrue);
      expect(scroll.offset, closeTo(before - 4, .1));
      await trackpad.panZoomEnd(timeStamp: const Duration(milliseconds: 48));
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );

  for (final running in [false, true]) {
    testWidgets(
      'one trackpad gesture crosses block boundaries and survives source refreshes (running: $running)',
      (tester) async {
        final rows = [for (var i = 0; i < 16; i++) block('$i', lineCount: 10)];
        rows.last['running'] = running;
        rows.last['exitCode'] = running ? null : 0;
        final controller = CommandBlockController(
          request: (_) => {'blocks': rows},
        )..refresh();
        controller.expandedOutput.addAll(
          rows.map((row) => row['id']! as String),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TerminalCommandBlocksView(
                controller: controller,
                onReinput: (_) {},
              ),
            ),
          ),
        );
        for (var i = 0; i < 6; i++) {
          await tester.pump();
        }
        final scroll = tester
            .widget<CommandTimelineView>(find.byType(CommandTimelineView))
            .controller;
        final terminal = find.byType(TerminalViewport).hitTestable().last;
        final point = tester.getCenter(terminal);
        final trackpad = await tester.createGesture(
          kind: PointerDeviceKind.trackpad,
        );
        await trackpad.panZoomStart(point);
        await trackpad.panZoomUpdate(
          point,
          pan: const Offset(0, 40),
          timeStamp: const Duration(milliseconds: 16),
        );
        await tester.pump(const Duration(milliseconds: 16));
        var previous = scroll.offset;
        for (var step = 1; step <= 16; step++) {
          final visibleController = tester
              .widget<TerminalViewport>(
                find.byType(TerminalViewport).hitTestable().first,
              )
              .controller;
          final visible = find.byWidgetPredicate(
            (widget) =>
                widget is TerminalViewport &&
                widget.controller == visibleController,
          );
          final beforeY = tester.getTopLeft(visible).dy;
          await trackpad.panZoomUpdate(
            point,
            pan: Offset(0, 40 + 64.0 * step),
            timeStamp: Duration(milliseconds: 16 + 16 * step),
          );
          await tester.pump(const Duration(milliseconds: 16));
          expect(
            tester.getTopLeft(visible).dy,
            closeTo(beforeY + 64, .1),
            reason: 'step $step',
          );
          expect(scroll.position.isScrollingNotifier.value, isTrue);
          previous = scroll.offset;
          final lines = rows.last['lines']! as List<Map<String, Object>>;
          lines.last['text'] = 'refresh $step';
          controller.refresh();
          await tester.pump();
          expect(scroll.offset, closeTo(previous, .1));
        }
        await trackpad.panZoomEnd(timeStamp: const Duration(milliseconds: 288));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        final momentum = scroll.offset;
        expect(momentum, lessThan(previous - 10));
        await tester.pump(const Duration(milliseconds: 80));
        expect(scroll.offset, lessThan(momentum - 10));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
      variant: const TargetPlatformVariant({TargetPlatform.macOS}),
    );
  }

  test(
    'range selection, bookmarks, paging and eviction stay session-local',
    () {
      var rows = [block('a'), block('b'), block('c')];
      final controller = CommandBlockController(
        request: (request) => request['id'] == null
            ? {'blocks': rows}
            : {'block': rows.firstWhere((b) => b['id'] == request['id'])},
      );
      addTearDown(controller.dispose);
      controller.refresh();
      controller.select('a');
      controller.select('c', extend: true);
      expect(controller.selected, {'a', 'b', 'c'});
      controller.toggleBookmark('b');
      controller.toggleExpandedOutput('b');
      controller.move(-1, bookmarked: true);
      expect(controller.activeId, 'b');
      controller.page('b', 0);
      rows = [block('b', columns: 40), block('c')];
      controller.refresh();
      expect(controller.displayBlock(controller.blocks.first).columns, 40);
      expect(controller.selected, {'b'});
      rows = [block('c')];
      controller.refresh();
      expect(controller.bookmarks, isEmpty);
      expect(controller.expandedOutput, isEmpty);
      expect(controller.activeId, isNull);
    },
  );

  test('copy ignores filters and joins soft wraps across pages', () async {
    final queries = <Map<String, Object?>>[];
    final controller = CommandBlockController(
      request: (query) {
        queries.add(query);
        if (query['id'] == null) {
          return {
            'blocks': [block('a')],
          };
        }
        return {
          'block': {
            ...block('a'),
            'nextOffset': query['offset'] == 0 ? 1 : null,
            'lines': [
              {
                'index': query['offset'],
                'text': query['offset'] == 0 ? 'hello ' : 'world',
                'wrapped': query['offset'] == 0,
              },
            ],
          },
        };
      },
    );
    addTearDown(controller.dispose);
    controller.refresh();
    controller.filter('a', const CommandBlockFilter(query: 'hidden'));
    queries.clear();
    expect(await controller.outputText('a'), 'hello world');
    expect(queries.every((query) => !query.containsKey('query')), isTrue);
  });

  testWidgets(
    'running block owns focus and PTY input; completed terminal is read-only',
    (tester) async {
      var running = true;
      final sink = _Sink();
      final focus = FocusNode();
      final controller = CommandBlockController(
        request: (_) => {
          'blocks': [block('live', running: running)],
        },
      );
      final input = TerminalInputController(
        sessionId: 'pty',
        runtime: sink,
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => 'paste',
      );
      controller.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalCommandBlocksView(
              controller: controller,
              onReinput: (_) {},
              liveInput: input,
              liveFocus: focus,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(TerminalViewport), findsOneWidget);
      expect(focus.hasFocus, isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(sink.writes.single, [3]);
      running = false;
      controller.refresh();
      await tester.pump();
      final terminal = tester.widget<TerminalViewport>(
        find.byType(TerminalViewport),
      );
      terminal.inputController.sendText('must not reach PTY');
      await terminal.inputController.pasteClipboard();
      expect(sink.writes, hasLength(1));
      expect(terminal.controller.frame.rows.single.text, 'text');
      expect(terminal.controller.frame.cursor.visible, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      focus.dispose();
    },
  );

  testWidgets('re-input edits only, folding preserves terminal source', (
    tester,
  ) async {
    final controller = CommandBlockController(
      request: (_) => {
        'blocks': [block('done')],
      },
    );
    addTearDown(controller.dispose);
    controller.refresh();
    String? draft;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalCommandBlocksView(
            controller: controller,
            onReinput: (value) => draft = value,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Block actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insert into Composer'));
    await tester.pumpAndSettle();
    expect(draft, 'echo done');
    controller.toggleCollapsed('done');
    await tester.pump();
    expect(find.byType(TerminalViewport), findsNothing);
    controller.toggleCollapsed('done');
    await tester.pump();
    expect(find.byType(TerminalViewport), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _Sink implements TerminalInputSink {
  final writes = <Uint8List>[];
  @override
  void sendInput(String sessionId, Uint8List bytes) => writes.add(bytes);
}
