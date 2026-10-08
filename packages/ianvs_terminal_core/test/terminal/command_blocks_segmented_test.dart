import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';

import '../helpers/pump_app.dart';

/// Parent rows straddle a child command's output. Native pages address owned
/// rows, while their indices retain the physical gap occupied by that child.
class _SegmentedOutput {
  int base = 1000;
  final sources = <int>[
    for (var i = 1000; i < 1160; i++) i,
    for (var i = 2000; i < 2160; i++) i,
  ];
  final requests = <Map<String, Object?>>[];

  String text(int source) =>
      '${source == 1002 || source == 2020 ? 'needle ' : ''}parent $source';

  Map<String, Object?> request(Map<String, Object?> args) {
    requests.add(Map.of(args));
    final retained = sources.where((source) => source >= base).toList();
    final query = args['query'] as String? ?? '';
    final matches = retained
        .where((source) => text(source).contains(query))
        .toList();
    final preview = args['id'] == null;
    final limit = preview ? 4 : (args['limit'] as int? ?? 16).clamp(1, 32);
    final int offset;
    if (args['sourceLine'] case final int source) {
      offset = matches.indexOf(base + source);
      if (offset < 0) return {'error': 'Source line is no longer available'};
    } else if (preview || args['tail'] == true) {
      offset = (matches.length - limit).clamp(0, matches.length);
    } else {
      offset = (args['offset'] as int? ?? 0).clamp(0, matches.length);
    }
    final end = (offset + limit).clamp(0, matches.length);
    final block = <String, Object?>{
      'id': 'parent',
      'command': 'parent shell',
      'columns': 80,
      'exitCode': 0,
      'segmented': true,
      'evicted': base > 1000,
      'totalLines': retained.length,
      'sourceLineCount': retained.isEmpty ? 0 : retained.last - base + 1,
      'matchingLines': matches.length,
      'offset': offset,
      'nextOffset': end < matches.length ? end : null,
      'lines': [
        for (final source in matches.sublist(offset, end))
          {
            'index': source - base,
            'source_row': source,
            'text': text(source),
            'wrapped': source == 1159,
          },
      ],
    };
    return preview
        ? {
            'blocks': [block],
          }
        : {'block': block};
  }
}

Future<void> _mountReader(
  WidgetTester tester,
  CommandBlockController controller, {
  double? initialRow,
  CommandBlockReadRange? initialRange,
  ValueChanged<CommandBlock>? onAttach,
}) async {
  tester.view.physicalSize = const Size(900, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpApp(
    Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showCommandBlockReader(
            context,
            controller: controller,
            id: 'parent',
            initialRow: controller.readingStates.containsKey('parent')
                ? null
                : initialRow,
            initialRange: initialRange,
            onAttachRange: onAttach,
          ),
          child: const Text('Read'),
        ),
      ),
    ),
    theme: ThemeData(platform: TargetPlatform.macOS),
  );
  await tester.tap(find.text('Read'));
  await tester.pumpAndSettle();
}

ScrollController _scroll(WidgetTester tester) => tester
    .widget<ListView>(find.byKey(const Key('block-reader-scroll')))
    .controller!;

double _rowHeight(WidgetTester tester) => tester
    .widget<TerminalViewport>(find.byType(TerminalViewport).first)
    .controller
    .measuredCellSize!
    .height;

SelectionController _selection(WidgetTester tester) => tester
    .widget<CommandBlockTerminal>(find.byType(CommandBlockTerminal).first)
    .selectionController!;

void main() {
  group('$CommandBlockController segmented output', () {
    late _SegmentedOutput output;
    late CommandBlockController controller;

    setUp(() {
      output = _SegmentedOutput();
      controller = CommandBlockController(request: output.request)..refresh();
    });

    tearDown(() => controller.dispose());

    test('keeps physical range bounds separate from the output row count', () {
      final block = controller.blocks.single;
      expect(block.totalLines, 320);
      expect(block.sourceLineCount, 1160);
      expect(block.segmented, isTrue);
      expect(
        const CommandBlockReadRange(
          startLine: 1020,
          endLine: 1021,
          sourceLineBase: 1000,
        ).resolveStart(block),
        1020,
      );
      expect(
        CommandBlock.fromJson({
          'id': 'legacy',
          'command': '',
          'totalLines': 12,
        })!.sourceLineCount,
        12,
      );
    });

    test(
      'opens an exact source row after the child output gap and eviction',
      () {
        output.base += 10;

        expect(
          controller.pageRange(
            'parent',
            const CommandBlockReadRange(
              startLine: 1020,
              endLine: 1021,
              sourceLineBase: 1000,
            ),
          ),
          isTrue,
        );

        final page = controller.displayBlock(controller.blocks.single);
        expect(page.offset, 170);
        expect(page.lines.first.index, 1010);
        expect(page.lines.first.sourceRow, 2020);
      },
    );

    test('rejects a source row belonging only to the child', () {
      final previous = controller.displayBlock(controller.blocks.single);

      expect(
        controller.pageRange(
          'parent',
          const CommandBlockReadRange(
            startLine: 200,
            endLine: 201,
            sourceLineBase: 1000,
          ),
        ),
        isFalse,
      );

      expect(controller.displayBlock(controller.blocks.single), same(previous));
      expect(controller.errors['parent'], 'Output is no longer available');
    });

    test(
      'copies a selection that starts beyond the output row count',
      () async {
        final text = await controller.outputText(
          'parent',
          selection: const TerminalSelection(
            startRow: 1020,
            startCol: 0,
            endRow: 1040,
            endCol: 80,
          ),
          expectedSourceBase: 1000,
        );

        expect(
          text,
          [
            for (var row = 2020; row <= 2040; row++) output.text(row),
          ].join('\n'),
        );
        expect(
          output.requests.any((request) => request['sourceLine'] == 1020),
          isTrue,
        );
      },
    );

    test(
      'copies only parent rows across the gap without joining wrapped text',
      () async {
        expect(
          await controller.outputText(
            'parent',
            selection: const TerminalSelection(
              startRow: 158,
              startCol: 0,
              endRow: 1001,
              endCol: 80,
            ),
          ),
          'parent 1158\nparent 1159\nparent 2000\nparent 2001',
        );
      },
    );

    test('copies filtered selected source rows across the gap', () async {
      expect(
        await controller.outputText(
          'parent',
          filter: const CommandBlockFilter(query: 'needle'),
          selection: const TerminalSelection(
            startRow: 2,
            startCol: 0,
            endRow: 1020,
            endCol: 80,
          ),
        ),
        'needle parent 1002\nneedle parent 2020',
      );
    });
  });

  group('segmented command block reader', () {
    late _SegmentedOutput output;
    late CommandBlockController controller;

    setUp(() {
      output = _SegmentedOutput();
      controller = CommandBlockController(request: output.request)..refresh();
    });

    tearDown(() => controller.dispose());

    testWidgets('opens a source range at its output ordinal', (tester) async {
      await _mountReader(
        tester,
        controller,
        initialRange: const CommandBlockReadRange(
          startLine: 1020,
          endLine: 1021,
          sourceLineBase: 1000,
        ),
      );

      expect(_scroll(tester).offset, closeTo(180 * _rowHeight(tester), 1));
      expect(
        tester
            .widgetList<CommandBlockTerminal>(find.byType(CommandBlockTerminal))
            .any(
              (page) => page.block.lines.any(
                (row) => row.sourceRow == 2020 && row.index == 1020,
              ),
            ),
        isTrue,
      );
      expect(
        find.byKey(const Key('block-reader-evidence-unavailable')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'does not open a neighboring row for a child-only source range',
      (tester) async {
        await _mountReader(
          tester,
          controller,
          initialRange: const CommandBlockReadRange(
            startLine: 200,
            endLine: 201,
            sourceLineBase: 1000,
          ),
        );

        expect(
          find.byKey(const Key('block-reader-evidence-unavailable')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('block-reader-scroll')), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('restores the same physical row after closing and eviction', (
      tester,
    ) async {
      await _mountReader(tester, controller, initialRow: 1020);
      final before = _scroll(tester).offset;
      final height = _rowHeight(tester);
      expect(before, closeTo(180 * height, 1));
      await tester.tap(find.byKey(const Key('block-reader-close')));
      await tester.pumpAndSettle();
      final source = controller.readingStates['parent']!.sourceRow;
      output.base += 50;
      controller.refresh();

      await tester.tap(find.text('Read'));
      await tester.pumpAndSettle();

      expect(_scroll(tester).offset, closeTo(before - 50 * height, .1));
      expect(controller.readingStates['parent']!.sourceRow, source);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'find navigates by display ordinals and keeps physical highlights',
      (tester) async {
        await _mountReader(tester, controller);
        await tester.tap(find.byKey(const Key('block-reader-find')));
        await tester.pump();
        await tester.enterText(
          find.byKey(const Key('block-reader-find-query')),
          'needle',
        );
        await tester.pumpAndSettle();
        expect(find.text('Matching lines 1/2'), findsOneWidget);

        await tester.tap(find.byKey(const Key('block-reader-find-next')));
        await tester.pumpAndSettle();

        expect(find.text('Matching lines 2/2'), findsOneWidget);
        expect(_scroll(tester).offset, closeTo(180 * _rowHeight(tester), 1));
        expect(
          tester
              .widgetList<CommandBlockTerminal>(
                find.byType(CommandBlockTerminal),
              )
              .any(
                (page) =>
                    page.highlightedRow == 1020 &&
                    page.block.lines.any((row) => row.index == 1020),
              ),
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('keeps selection and reading position after source eviction', (
      tester,
    ) async {
      await _mountReader(tester, controller, initialRow: 1020);
      _selection(tester).setSelection(
        const TerminalSelection(
          startRow: 1020,
          startCol: 0,
          endRow: 1021,
          endCol: 4,
        ),
      );
      await tester.pumpAndSettle();
      final before = _scroll(tester).offset;
      final height = _rowHeight(tester);

      output.base += 10;
      controller.refresh();
      await tester.pumpAndSettle();

      expect(_scroll(tester).offset, closeTo(before - 10 * height, .1));
      expect(_selection(tester).selection?.startRow, 1010);
      expect(_selection(tester).selection?.endRow, 1011);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'preserves reading position when old parent segments are discarded',
      (tester) async {
        await _mountReader(tester, controller, initialRow: 1020);
        final before = _scroll(tester).offset;
        final height = _rowHeight(tester);
        output.sources.removeRange(0, 40);

        controller.refresh();
        await tester.pumpAndSettle();

        expect(_scroll(tester).offset, closeTo(before - 40 * height, .1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('attaches filtered source rows beyond the output row count', (
      tester,
    ) async {
      CommandBlock? attached;
      controller.filter('parent', const CommandBlockFilter(query: 'needle'));
      await _mountReader(
        tester,
        controller,
        onAttach: (block) => attached = block,
      );
      _selection(tester).setSelection(
        const TerminalSelection(
          startRow: 2,
          startCol: 0,
          endRow: 1020,
          endCol: 4,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Attach 2 selected lines to AI'), findsOneWidget);

      await tester.tap(find.byKey(const Key('block-reader-attach')));
      await tester.pumpAndSettle();

      expect(attached!.lines.map((row) => row.index), [2, 1020]);
      expect(attached!.visibleOutput, 'needle parent 1002\nneedle parent 2020');
      expect(attached!.sourceLineCount, 1160);
      expect(attached!.segmented, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'attaches only selected parent rows and retains source span metadata',
      (tester) async {
        CommandBlock? attached;
        await _mountReader(
          tester,
          controller,
          onAttach: (block) => attached = block,
        );
        _selection(tester).setSelection(
          const TerminalSelection(
            startRow: 158,
            startCol: 0,
            endRow: 1001,
            endCol: 4,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Attach 4 selected lines to AI'), findsOneWidget);

        await tester.tap(find.byKey(const Key('block-reader-attach')));
        await tester.pumpAndSettle();

        expect(attached!.lines.map((row) => row.index), [158, 159, 1000, 1001]);
        expect(attached!.lines.map((row) => row.sourceRow), [
          1158,
          1159,
          2000,
          2001,
        ]);
        expect(attached!.totalLines, 320);
        expect(attached!.sourceLineCount, 1160);
        expect(attached!.segmented, isTrue);
        expect(attached!.offset, 158);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });
}
