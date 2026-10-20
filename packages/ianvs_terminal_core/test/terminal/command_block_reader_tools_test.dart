import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';
import 'package:ianvs_terminal_core/src/terminal/render_terminal_viewport.dart';

class _Output {
  int base = 1000;
  int count = 400;
  final requests = <Map<String, Object?>>[];
  final hits = <int>{12, 130, 300};

  Map<String, Object?> request(Map<String, Object?> args) {
    requests.add(Map.of(args));
    final indices = [
      for (var i = 0; i < count; i++)
        if (args['query'] != 'keep' || hits.contains(base - 1000 + i)) i,
    ];
    final offset = args['offset'] as int? ?? 0;
    final limit = args['limit'] as int? ?? 6;
    final page = <String, Object?>{
      'id': 'log',
      'command': 'read log',
      'cwd': '/fixture',
      'exitCode': 0,
      'totalLines': count,
      'matchingLines': indices.length,
      'offset': offset,
      'columns': 50,
      'evicted': base > 1000,
      'nextOffset': offset + limit < indices.length ? offset + limit : null,
      'lines': [
        for (final i in indices.skip(offset).take(limit))
          {
            'index': i,
            'source_row': base + i,
            'wrapped': false,
            'text': hits.contains(base - 1000 + i)
                ? '中文 needle evidence ${base + i}'
                : 'context ${base + i}',
          },
      ],
    };
    return args['id'] == null
        ? {
            'blocks': [page],
          }
        : {'block': page};
  }
}

Future<CommandBlockController> _mount(
  WidgetTester tester,
  _Output output, {
  bool filtered = false,
  Size size = const Size(900, 640),
  bool phone = false,
  bool dark = false,
  ValueChanged<CommandBlock>? onAttach,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = CommandBlockController(request: output.request)..refresh();
  addTearDown(controller.dispose);
  if (filtered) {
    controller.filter('log', const CommandBlockFilter(query: 'keep'));
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        platform: phone ? TargetPlatform.iOS : TargetPlatform.macOS,
        brightness: dark ? Brightness.dark : Brightness.light,
      ),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showCommandBlockReader(
            context,
            controller: controller,
            id: 'log',
            onAttachRange: onAttach,
          ),
          child: const Text('Read'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Read'));
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  final query = find.byKey(const Key('block-reader-find-query'));
  final next = find.byKey(const Key('block-reader-find-next'));
  final previous = find.byKey(const Key('block-reader-find-previous'));
  SelectionController selection(WidgetTester tester) => tester
      .widget<CommandBlockTerminal>(find.byType(CommandBlockTerminal).first)
      .selectionController!;
  ScrollController scroll(WidgetTester tester) => tester
      .widget<ListView>(find.byKey(const Key('block-reader-scroll')))
      .controller!;
  Future<void> search(WidgetTester tester, String text) async {
    await tester.tap(find.byKey(const Key('block-reader-find')));
    await tester.pump();
    await tester.enterText(query, text);
    await tester.pumpAndSettle();
  }

  testWidgets('find keeps context and selection across native pages', (
    tester,
  ) async {
    final output = _Output();
    final c = await _mount(tester, output, onAttach: (_) {});
    selection(tester).setSelection(
      const TerminalSelection(startRow: 14, startCol: 0, endRow: 16, endCol: 3),
    );
    await tester.pumpAndSettle();
    expect(find.text('Attach 3 selected lines to AI'), findsOneWidget);
    await search(tester, 'NEEDLE');
    expect(find.text('Matching lines 1/3'), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-line-numbers-0')), findsOneWidget);
    expect(c.filtering, isEmpty);
    expect(selection(tester).selection?.startRow, 14);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('Matching lines 2/3'), findsOneWidget);
    final page = tester
        .widgetList<CommandBlockTerminal>(find.byType(CommandBlockTerminal))
        .firstWhere((p) => p.block.lines.any((r) => r.index == 130));
    expect(page.highlightedRow, 130);
    final highlights = find
        .byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_TerminalViewportSurface',
        )
        .evaluate()
        .map((e) => e.findRenderObject())
        .whereType<RenderTerminalViewport>()
        .expand((r) => r.debugSearchHighlightRects);
    expect(highlights, hasLength(1));
    expect(highlights.single.height, greaterThan(0));
    expect(page.block.lines.any((r) => r.text.startsWith('context')), true);
    final anchor = scroll(tester).offset;
    output.count += 20;
    c.refresh();
    await tester.pumpAndSettle();
    expect(scroll(tester).offset, closeTo(anchor, .1));
    expect(find.text('Matching lines 2/3'), findsOneWidget);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('Matching lines 3/3'), findsOneWidget);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('Matching lines 1/3'), findsOneWidget);
    await tester.tap(previous);
    await tester.pumpAndSettle();
    expect(find.text('Matching lines 3/3'), findsOneWidget);
    expect(
      output.requests
          .where((r) => r['limit'] != null)
          .every((r) => (r['limit']! as int) <= 128),
      true,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(query, findsNothing);
    expect(find.byKey(const Key('block-reader')), findsOneWidget);
    expect(selection(tester).selection?.endRow, 16);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('clear search keeps reader, reading position and selection', (
    tester,
  ) async {
    await _mount(tester, _Output(), phone: true, size: const Size(390, 640));
    selection(tester).setSelection(
      const TerminalSelection(startRow: 12, startCol: 0, endRow: 13, endCol: 3),
    );
    await search(tester, 'needle');
    await tester.tap(next);
    await tester.pumpAndSettle();
    final before = scroll(tester).offset;
    final clear = find.byKey(const Key('block-reader-find-clear'));
    expect(tester.getSize(clear).height, greaterThanOrEqualTo(44));
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(query).controller!.text, isEmpty);
    expect(tester.widget<TextField>(query).focusNode!.hasFocus, isTrue);
    expect(scroll(tester).offset, closeTo(before, .1));
    expect(selection(tester).selection?.startRow, 12);
    expect(find.byKey(const Key('block-reader')), findsOneWidget);
    expect(find.text('Find in displayed output'), findsOneWidget);
    expect(clear, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filtered selection counts only displayed original rows', (
    tester,
  ) async {
    CommandBlock? attached;
    final c = await _mount(
      tester,
      _Output(),
      filtered: true,
      onAttach: (b) => attached = b,
    );
    selection(tester).setSelection(
      const TerminalSelection(
        startRow: 12,
        startCol: 0,
        endRow: 300,
        endCol: 4,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Attach 3 selected lines to AI'), findsOneWidget);
    await search(tester, 'needle');
    expect(find.text('Matching lines 1/3'), findsOneWidget);
    expect(c.appliedFilter('log')?.query, 'keep');
    expect(
      tester.widget<Text>(find.byKey(const Key('block-reader-range'))).data,
      contains('Lines 13–301'),
    );
    await tester.tap(find.byKey(const Key('block-reader-attach')));
    await tester.pumpAndSettle();
    expect(attached!.lines.map((r) => r.index), [12, 130, 300]);
    expect(attached!.visibleOutput, isNot(contains('context')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('find cancels stale queries and reconciles source eviction', (
    tester,
  ) async {
    final output = _Output();
    final c = await _mount(tester, output);
    await search(tester, 'needle');
    await tester.tap(next);
    await tester.pumpAndSettle();
    final anchor = scroll(tester).offset;
    output.base += 20;
    output.count -= 20;
    c.refresh();
    await tester.pumpAndSettle();
    expect(find.text('Matching lines 1/2'), findsOneWidget);
    expect(scroll(tester).offset, lessThan(anchor));
    expect(
      tester
          .widgetList<CommandBlockTerminal>(find.byType(CommandBlockTerminal))
          .any((p) => p.highlightedRow == 110),
      true,
    );
    await tester.enterText(query, 'needle');
    await tester.enterText(query, 'absent');
    await tester.pumpAndSettle();
    expect(find.text('Matching lines 0/0'), findsOneWidget);
    expect(tester.widget<IconButton>(next).onPressed, isNull);
    await tester.enterText(query, 'context');
    await tester.tap(find.byKey(const Key('block-reader-close')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [
    const Size(320, 568),
    const Size(568, 320),
    const Size(568, 180),
  ]) {
    testWidgets('fixed text phone reader controls fit $size', (tester) async {
      await _mount(
        tester,
        _Output(),
        size: size,
        phone: true,
        dark: true,
        onAttach: (_) {},
      );
      selection(tester).setSelection(
        const TerminalSelection(
          startRow: 12,
          startCol: 0,
          endRow: 14,
          endCol: 3,
        ),
      );
      await tester.pumpAndSettle();
      await search(tester, 'needle');
      expect(
        tester.getSize(find.byKey(const Key('block-reader-attach'))).height,
        greaterThanOrEqualTo(44),
      );
      expect(
        tester.getSize(find.byKey(const Key('block-reader-scroll'))).height,
        greaterThan(size.height < 200 ? 20 : 80),
      );
      final gutter = find.byKey(const ValueKey('reader-line-numbers-0'));
      final before = tester.getTopLeft(gutter).dx;
      final horizontal = tester
          .widget<SingleChildScrollView>(
            find.byWidgetPredicate(
              (w) =>
                  w is SingleChildScrollView &&
                  w.scrollDirection == Axis.horizontal,
            ),
          )
          .controller!;
      horizontal.jumpTo(horizontal.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(gutter).dx, closeTo(before, .1));
      expect(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('reader-line-number-background-0')),
            )
            .dx,
        closeTo(0, .1),
        reason: 'Scrolled text must not leak through the left gutter margin',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
