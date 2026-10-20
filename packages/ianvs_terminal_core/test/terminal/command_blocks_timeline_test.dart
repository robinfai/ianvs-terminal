import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';

import 'command_blocks_test.dart' show block;

void main() {
  testWidgets('task timeline selects and attaches only its visible blocks', (
    tester,
  ) async {
    final controller = CommandBlockController(
      request: (_) => {
        'blocks': [block('first'), block('hidden'), block('last')],
      },
    )..refresh();
    List<CommandBlock>? attached;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: TerminalCommandBlocksView(
            controller: controller,
            onReinput: (_) => fail('Selection must not re-input'),
            showToolbar: false,
            timeline: const [
              CommandBlockTimelineItem.block('first'),
              CommandBlockTimelineItem.block('last'),
            ],
            onAttachBlocks: (blocks) => attached = blocks,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('echo first'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('echo last'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(controller.selected, {'first', 'last'});
    await tester.tap(find.byKey(const Key('blocks-attach-selection')));
    expect(attached!.map((b) => b.id), ['first', 'last']);
    expect(controller.blocks, hasLength(3));
    await tester.tap(find.byKey(const Key('blocks-clear-selection')));
    await tester.pump();
    expect(controller.selected, isEmpty);
    expect(find.byKey(const Key('blocks-attach-selection')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  for (final filtered in [false, true]) {
    testWidgets(
      'reader restores native line and selection after eviction (filter $filtered)',
      (tester) async {
        var base = 1000;
        Map<String, Object?> request(Map<String, Object?> args) {
          final indices = [
            for (var i = 0; i < 800; i++)
              if (args['query'] != 'match' || (base + i) % 4 == 0) i,
          ];
          final offset = args['offset'] as int? ?? 0;
          final limit = args['limit'] as int? ?? 6;
          final snapshot = {
            ...block('source', lineCount: 0),
            'totalLines': 800,
            'matchingLines': indices.length,
            'offset': offset,
            'evicted': base > 1000,
            'lines': [
              for (final i in indices.skip(offset).take(limit))
                {
                  'index': i,
                  'source_row': base + i,
                  'text': 'source ${base + i}',
                  'wrapped': false,
                },
            ],
          };
          return args['id'] == null
              ? {
                  'blocks': [snapshot],
                }
              : {'block': snapshot};
        }

        final controller = CommandBlockController(request: request)..refresh();
        if (filtered) {
          controller.filter('source', const CommandBlockFilter(query: 'match'));
        }
        Widget tree() => MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showCommandBlockReader(
                  context,
                  controller: controller,
                  id: 'source',
                ),
                child: const Text('Read'),
              ),
            ),
          ),
        );
        await tester.pumpWidget(tree());
        await tester.tap(find.text('Read'));
        await tester.pumpAndSettle();
        var scroll = tester
            .widget<ListView>(find.byKey(const Key('block-reader-scroll')))
            .controller!;
        final viewport = tester.widget<TerminalViewport>(
          find.byType(TerminalViewport).first,
        );
        final lineHeight = viewport.controller.measuredCellSize!.height;
        final offset = 8 + 90 * lineHeight + 5;
        scroll.jumpTo(offset);
        await tester.pumpAndSettle();
        final selection = tester
            .widget<CommandBlockTerminal>(
              find.byType(CommandBlockTerminal).first,
            )
            .selectionController!;
        final first = filtered ? 360 : 90;
        selection.setSelection(
          TerminalSelection(
            startRow: first,
            startCol: 2,
            endRow: first + (filtered ? 4 : 1),
            endCol: 8,
          ),
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('block-reader-close')));
        await tester.pumpAndSettle();
        // The original reader route has been disposed. Old native rows leave the
        // retained window while the user is back in the task.
        base += 40;
        controller.refresh();
        await tester.tap(find.text('Read'));
        await tester.pumpAndSettle();
        scroll = tester
            .widget<ListView>(find.byKey(const Key('block-reader-scroll')))
            .controller!;
        expect(
          scroll.offset,
          closeTo(offset - (filtered ? 10 : 40) * lineHeight, .1),
        );
        final restored = tester
            .widget<CommandBlockTerminal>(
              find.byType(CommandBlockTerminal).first,
            )
            .selectionController!
            .selection;
        expect(restored?.startRow, first - 40);
        expect(restored?.endRow, first + (filtered ? 4 : 1) - 40);
        expect(restored?.startCol, 2);
        expect(restored?.endCol, 8);
        await tester.fling(
          find.byKey(const Key('block-reader-scroll')),
          const Offset(0, -160),
          800,
        );
        await tester.pump(const Duration(milliseconds: 16));
        expect(scroll.position.isScrollingNotifier.value, true);
        final moving = scroll.offset;
        // More history is evicted even though totalLines and evicted=true
        // have not changed. Source identity must invalidate the cached page.
        base += 4;
        controller.refresh();
        await tester.pump();
        expect(
          scroll.offset,
          closeTo(moving - (filtered ? 1 : 4) * lineHeight, .1),
        );
        expect(scroll.position.isScrollingNotifier.value, true);
        final corrected = scroll.offset;
        await tester.pump(const Duration(milliseconds: 80));
        expect(scroll.offset, greaterThan(corrected + 5));
        await tester.pumpAndSettle();
        final activeSelection = tester
            .widget<CommandBlockTerminal>(
              find.byType(CommandBlockTerminal).first,
            )
            .selectionController!;
        expect(activeSelection.selection?.startRow, first - 44);
        base += 800;
        controller.refresh();
        await tester.pumpAndSettle();
        expect(
          activeSelection.selection,
          isNull,
          reason: 'Evicted selection cannot silently refer to newer rows',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  testWidgets('reading survives a message growing above the viewport', (
    tester,
  ) async {
    final controller = CommandBlockController(
      request: (_) => {'blocks': <Object>[]},
    )..refresh();
    final scroll = ScrollController();
    final following = ValueNotifier(false);
    final heights = List<double>.filled(30, 100);
    Widget tree() => MaterialApp(
      home: Scaffold(
        body: TerminalCommandBlocksView(
          controller: controller,
          onReinput: (_) {},
          showToolbar: false,
          scrollController: scroll,
          followTail: following,
          timeline: [
            for (var i = 0; i < heights.length; i++)
              CommandBlockTimelineItem.content(
                'message-$i',
                (_) => SizedBox(
                  key: ValueKey('message-body-$i'),
                  height: heights[i],
                  child: Text('Message $i'),
                ),
              ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(tree());
    await tester.pumpAndSettle();
    scroll.jumpTo(550);
    await tester.pumpAndSettle();
    final anchor = find.byKey(const ValueKey('message-body-5'));
    final y = tester.getTopLeft(anchor).dy;
    heights[4] = 180;
    await tester.pumpWidget(tree());
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(anchor).dy, closeTo(y, .1));
    expect(scroll.offset, closeTo(630, .1));
    heights[4] = 1000;
    await tester.pumpWidget(tree());
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(anchor).dy, closeTo(y, .1));
    expect(scroll.offset, closeTo(1450, .1));
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
    following.dispose();
    controller.dispose();
  });

  testWidgets('shared AI timeline preserves reading across native updates', (
    tester,
  ) async {
    final rows = <Map<String, Object?>>[
      for (var i = 0; i < 12; i++) block('$i', lineCount: 2),
    ];
    final controller = CommandBlockController(request: (_) => {'blocks': rows})
      ..refresh();
    final scroll = ScrollController();
    final following = ValueNotifier(true);
    final items = <CommandBlockTimelineItem>[
      for (var i = 0; i < 12; i++) ...[
        CommandBlockTimelineItem.content(
          'explain-$i',
          (_) => SizedBox(height: 60, child: Text('Explanation $i')),
        ),
        CommandBlockTimelineItem.block('$i'),
      ],
    ];
    Widget tree() => MaterialApp(
      theme: ThemeData(platform: TargetPlatform.macOS),
      home: Scaffold(
        body: TerminalCommandBlocksView(
          controller: controller,
          onReinput: (_) {},
          timeline: items,
          showToolbar: false,
          scrollController: scroll,
          followTail: following,
        ),
      ),
    );
    await tester.pumpWidget(tree());
    await tester.pumpAndSettle();
    following.value = false;
    scroll.jumpTo(620);
    await tester.pumpAndSettle();
    final anchor = find.byKey(const ValueKey('command-block-4'));
    expect(anchor, findsOneWidget);
    final before = tester.getTopLeft(anchor);
    rows[11] = block('11', running: true, lineCount: 80);
    controller.refresh();
    items.add(
      CommandBlockTimelineItem.content(
        'new-result',
        (_) => const Text('New evidence'),
      ),
    );
    await tester.pumpWidget(tree());
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(anchor), before);
    expect(following.value, false);
    following.value = true;
    await tester.pumpAndSettle();
    expect(scroll.position.extentAfter, lessThan(1));
    expect(find.text('New evidence'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    // The host retains ownership of the shared scroll state.
    scroll.dispose();
    following.dispose();
    controller.dispose();
  });

  testWidgets(
    'saved item anchor restores after remount with different heights',
    (tester) async {
      var scroll = CommandTimelineScrollController();
      final heights = List<double>.filled(40, 100);
      Widget tree() => MaterialApp(
        home: Scaffold(
          body: CommandTimelineView(
            controller: scroll,
            itemIds: [for (var i = 0; i < heights.length; i++) 'entry-$i'],
            itemBuilder: (_, i) => SizedBox(
              key: ValueKey('entry-body-$i'),
              height: heights[i],
              child: Text('Entry $i'),
            ),
            followTail: () => false,
          ),
        ),
      );
      await tester.pumpWidget(tree());
      await tester.pumpAndSettle();
      scroll.jumpTo(1550);
      await tester.pumpAndSettle();
      final anchor = scroll.readingAnchor!;
      expect(anchor.itemId, 'entry-15');
      expect(anchor.offset, 50);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
      for (var i = 0; i < 15; i++) {
        heights[i] = 140;
      }
      scroll = CommandTimelineScrollController(
        initialScrollOffset: anchor.scrollOffset,
      );
      await tester.pumpWidget(tree());
      await tester.pumpAndSettle();
      final restoring = scroll.restoreReadingAnchor(anchor);
      await tester.pumpAndSettle();
      expect(await restoring, true);
      expect(scroll.readingAnchor!.itemId, anchor.itemId);
      expect(scroll.readingAnchor!.offset, closeTo(50, .1));
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('entry-body-15'))).dy,
        closeTo(-50, .1),
      );
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );

  testWidgets('reader attaches original rows across native page boundaries', (
    tester,
  ) async {
    final requests = <(int, int)>[];
    Map<String, Object?> request(Map<String, Object?> args) {
      final start = args['offset'] as int? ?? 0;
      final count = args['limit'] as int? ?? 6;
      requests.add((start, count));
      final snapshot = <String, Object?>{
        ...block('source', lineCount: 0),
        'totalLines': 400,
        'matchingLines': 400,
        'offset': start,
        'lines': [
          for (var i = start; i < (start + count).clamp(0, 400); i++)
            {
              'index': i,
              'source_row': 1000 + i,
              'text': 'original row $i',
              'wrapped': false,
            },
        ],
      };
      return args['id'] == null
          ? {
              'blocks': [snapshot],
            }
          : {'block': snapshot};
    }

    final controller = CommandBlockController(request: request)..refresh();
    CommandBlock? attached;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showCommandBlockReader(
                context,
                controller: controller,
                id: 'source',
                onAttachRange: (block) => attached = block,
              ),
              child: const Text('Read output'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Read output'));
    await tester.pumpAndSettle();
    final page = tester.widget<CommandBlockTerminal>(
      find.byType(CommandBlockTerminal).first,
    );
    page.selectionController!.setSelection(
      const TerminalSelection(
        startRow: 126,
        startCol: 0,
        endRow: 130,
        endCol: 5,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('block-reader-attach')));
    await tester.pumpAndSettle();
    expect(attached!.lines.map((row) => row.index), [126, 127, 128, 129, 130]);
    expect(attached!.lines.first.sourceRow, 1126);
    expect(attached!.visibleOutput, contains('original row 130'));
    expect(requests, contains((126, 5)));
    expect(find.byKey(const Key('block-reader-scroll')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('height compensation preserves a running fling', (tester) async {
    final scroll = CommandTimelineScrollController();
    final heights = List<double>.filled(80, 100);
    Widget tree() => MaterialApp(
      home: Scaffold(
        body: CommandTimelineView(
          controller: scroll,
          itemIds: [for (var i = 0; i < heights.length; i++) 'entry-$i'],
          itemBuilder: (_, i) => SizedBox(
            key: ValueKey('entry-body-$i'),
            height: heights[i],
            child: Text('Entry $i'),
          ),
          followTail: () => false,
        ),
      ),
    );
    await tester.pumpWidget(tree());
    scroll.jumpTo(1000);
    await tester.pumpAndSettle();
    await tester.fling(
      find.byType(CommandTimelineView),
      const Offset(0, -300),
      1000,
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(scroll.position.isScrollingNotifier.value, true);
    final anchor = scroll.readingAnchor!;
    final index = int.parse(anchor.itemId.split('-').last);
    final visible = find.byKey(ValueKey('entry-body-$index'));
    final before = tester.getTopLeft(visible).dy;
    heights[index - 1] += 80;
    await tester.pumpWidget(tree());
    expect(tester.getTopLeft(visible).dy, closeTo(before, .1));
    expect(scroll.position.isScrollingNotifier.value, true);
    final after = scroll.offset;
    await tester.pump(const Duration(milliseconds: 80));
    expect(scroll.offset, greaterThan(after + 5));
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });

  testWidgets(
    'prepending and removing earlier messages keeps the visible identity',
    (tester) async {
      final scroll = CommandTimelineScrollController();
      final ids = [for (var i = 0; i < 30; i++) 'entry-$i'];
      Widget tree() => MaterialApp(
        home: Scaffold(
          body: CommandTimelineView(
            controller: scroll,
            itemIds: List.of(ids),
            itemBuilder: (_, i) => SizedBox(
              key: ValueKey('body-${ids[i]}'),
              height: 100,
              child: Text(ids[i]),
            ),
            followTail: () => false,
          ),
        ),
      );
      await tester.pumpWidget(tree());
      scroll.jumpTo(550);
      await tester.pumpAndSettle();
      final anchor = scroll.readingAnchor!;
      ids.insertAll(0, ['earlier-a', 'earlier-b']);
      await tester.pumpWidget(tree());
      await tester.pumpAndSettle();
      expect(scroll.readingAnchor!.itemId, anchor.itemId);
      expect(scroll.readingAnchor!.offset, closeTo(anchor.offset, .1));
      ids.removeRange(0, 3);
      await tester.pumpWidget(tree());
      await tester.pumpAndSettle();
      expect(scroll.readingAnchor!.itemId, anchor.itemId);
      expect(scroll.readingAnchor!.offset, closeTo(anchor.offset, .1));
      ids.insertAll(0, [for (var i = 0; i < 50; i++) 'older-page-$i']);
      await tester.pumpWidget(tree());
      await tester.pumpAndSettle();
      expect(scroll.readingAnchor!.itemId, anchor.itemId);
      expect(scroll.readingAnchor!.offset, closeTo(anchor.offset, .1));
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );

  for (final matches in [
    [126, 127],
    [126, 300],
    [126, 999],
  ]) {
    testWidgets(
      'filtered pointer selection attaches only original rows $matches',
      (tester) async {
        final requests = <Map<String, Object?>>[];
        Map<String, Object?> request(Map<String, Object?> args) {
          requests.add(Map.of(args));
          final indices = args['query'] == 'match'
              ? matches
              : [for (var i = 0; i < 1600; i++) i];
          final start = args['offset'] as int? ?? 0;
          final count = args['limit'] as int? ?? 160;
          final snapshot = <String, Object?>{
            ...block('source', lineCount: 0),
            'totalLines': 1600,
            'matchingLines': indices.length,
            'offset': start,
            'lines': [
              for (final i in indices.skip(start).take(count))
                {
                  'index': i,
                  'source_row': 1000 + i,
                  'text': 'original match row $i',
                  'wrapped': false,
                },
            ],
          };
          return args['id'] == null
              ? {
                  'blocks': [snapshot],
                }
              : {'block': snapshot};
        }

        final controller = CommandBlockController(request: request)..refresh();
        controller.filter('source', const CommandBlockFilter(query: 'match'));
        CommandBlock? attached;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showCommandBlockReader(
                    context,
                    controller: controller,
                    id: 'source',
                    onAttachRange: (b) => attached = b,
                  ),
                  child: const Text('Read'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Read'));
        await tester.pumpAndSettle();
        final viewport = find.byType(TerminalViewport);
        final rect = tester.getRect(viewport);
        final pointer = await tester.startGesture(
          Offset(rect.left + 2, rect.top + rect.height * .25),
          kind: PointerDeviceKind.mouse,
        );
        await pointer.moveTo(
          Offset(rect.left + 80, rect.top + rect.height * .75),
        );
        await pointer.up();
        await tester.pump();
        await tester.tap(find.byKey(const Key('block-reader-attach')));
        await tester.pumpAndSettle();
        expect(attached, isNotNull);
        expect(attached!.lines.map((row) => row.index), matches);
        expect(
          attached!.lines.map((row) => row.sourceRow),
          matches.map((i) => 1000 + i),
        );
        // Offsets address the filtered output sequence; the original physical
        // source indices remain on each attached row, including any gaps.
        expect(attached!.offset, 0);
        expect(attached!.totalLines, 1600);
        expect(
          attached!.visibleOutput,
          matches.map((i) => 'original match row $i').join('\n'),
        );
        expect(
          requests
              .where((r) => r['id'] != null)
              .every((r) => (r['limit'] as int? ?? 160) <= 500),
          true,
        );
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }
}
