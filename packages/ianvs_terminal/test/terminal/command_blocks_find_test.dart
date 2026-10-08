import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

class _SearchOutput {
  final queriedIds = <String>[];
  final text = const {
    'first': 'needle from the first task',
    'second': 'needle from the second task',
  };

  Map<String, Object?> _block(String id, {String query = ''}) {
    final matches = text[id]!.contains(query);
    return {
      'id': id,
      'command': 'echo $id',
      'cwd': '/tmp',
      'running': false,
      'exitCode': 0,
      'columns': 80,
      'offset': 0,
      'totalLines': 1,
      'matchingLines': matches ? 1 : 0,
      'nextOffset': null,
      'lines': [
        if (matches)
          {'index': 0, 'source_row': 100, 'text': text[id], 'wrapped': false},
      ],
    };
  }

  Map<String, Object?> request(Map<String, Object?> request) {
    final id = request['id'] as String?;
    if (id == null) {
      return {
        'blocks': [for (final id in text.keys) _block(id)],
      };
    }
    final query = request['query'] as String? ?? '';
    if (query.isNotEmpty) queriedIds.add(id);
    return {'block': _block(id, query: query)};
  }
}

class _EvictingOutput {
  int sourceBase = 1000;
  bool running = false;
  final pageAdvances = <int>[];
  final requests = <Map<String, Object?>>[];
  static const needleSource = 1100;
  static const sourceEnd = 1200;
  static const needle = 'needle at immutable source 1100';

  List<int> get pageOffsets => [
    for (final request in requests)
      if (request['id'] != null &&
          request['query'] == null &&
          request['limit'] == null)
        request['offset']! as int,
  ];

  Map<String, Object?> _block({
    String query = '',
    int offset = 0,
    int limit = 200,
    bool preview = false,
  }) {
    final count = sourceEnd - sourceBase;
    final filtered = query.isNotEmpty;
    final start = preview
        ? (count - 2).clamp(0, count)
        : offset.clamp(0, count);
    final indices = filtered
        ? <int>[if (needleSource >= sourceBase) needleSource - sourceBase]
        : <int>[for (var i = start; i < count && i < start + limit; i++) i];
    return {
      'id': 'first',
      'command': 'echo first',
      'cwd': '/tmp',
      'running': running,
      'exitCode': running ? null : 0,
      'evicted': sourceBase != 1000,
      'columns': 80,
      'offset': filtered ? 0 : start,
      'totalLines': count,
      'matchingLines': filtered ? indices.length : count,
      'nextOffset': !filtered && start + indices.length < count
          ? start + indices.length
          : null,
      'lines': [
        for (final i in indices)
          {
            'index': i,
            'source_row': sourceBase + i,
            'text': sourceBase + i == needleSource
                ? needle
                : 'ordinary source ${sourceBase + i}',
            'wrapped': false,
          },
      ],
    };
  }

  Map<String, Object?> request(Map<String, Object?> request) {
    requests.add(Map.of(request));
    if (request['id'] == null) {
      return {
        'blocks': [_block(preview: true)],
      };
    }
    if (request['query'] == null &&
        request['limit'] == null &&
        pageAdvances.isNotEmpty) {
      sourceBase += pageAdvances.removeAt(0);
    }
    return {
      'block': _block(
        query: request['query'] as String? ?? '',
        offset: request['offset'] as int? ?? 0,
        limit: request['limit'] as int? ?? 200,
      ),
    };
  }
}

Future<void> _pumpBlocks(
  WidgetTester tester,
  CommandBlockController controller, {
  List<CommandBlockTimelineItem>? timeline,
  bool phone = false,
}) async {
  if (phone) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        platform: phone ? TargetPlatform.iOS : TargetPlatform.macOS,
      ),
      home: Scaffold(
        body: TerminalCommandBlocksView(
          controller: controller,
          timeline: timeline,
          showToolbar: phone,
          onReinput: (_) => fail('Finding output must not re-input commands'),
        ),
      ),
    ),
  );
}

Future<void> _findNeedle(
  WidgetTester tester,
  CommandBlockController controller, {
  String? activeId,
  bool toolbar = false,
}) async {
  if (toolbar) {
    await tester.tap(find.byTooltip('Find in blocks'));
  } else {
    await tester.tap(find.text('echo first'));
    if (activeId == null) {
      controller.clearSelection();
    } else {
      controller.select(activeId);
    }
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  }
  await tester.pump();
  await tester.enterText(find.byType(TextField), 'needle');
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

void main() {
  group('$TerminalCommandBlocksView find', () {
    late _SearchOutput output;
    late CommandBlockController controller;

    setUp(() {
      output = _SearchOutput();
      controller = CommandBlockController(request: output.request)..refresh();
    });

    tearDown(() => controller.dispose());

    for (final scoped in [true, false]) {
      testWidgets(
        scoped
            ? 'finds and opens only blocks in the current task timeline'
            : 'finds and opens all session blocks when timeline is null',
        (tester) async {
          await _pumpBlocks(
            tester,
            controller,
            timeline: scoped
                ? const [CommandBlockTimelineItem.block('first')]
                : null,
          );
          await tester.pumpAndSettle();
          await _findNeedle(tester, controller);

          expect(output.queriedIds, scoped ? ['first'] : ['second', 'first']);
          expect(find.text(output.text['first']!), findsOneWidget);
          expect(
            find.text(output.text['second']!),
            scoped ? findsNothing : findsOneWidget,
          );
          final target = scoped ? 'first' : 'second';
          await tester.tap(find.text(output.text[target]!));
          await tester.pumpAndSettle();
          expect(controller.activeId, target);
          expect(
            find.byKey(ValueKey('command-block-$target')).hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }

    testWidgets('ignores an active block outside the current task timeline', (
      tester,
    ) async {
      await _pumpBlocks(
        tester,
        controller,
        timeline: const [CommandBlockTimelineItem.block('first')],
      );
      await tester.pumpAndSettle();
      await _findNeedle(tester, controller, activeId: 'second');

      expect(output.queriedIds, ['first']);
      expect(find.text(output.text['first']!), findsOneWidget);
      expect(find.text(output.text['second']!), findsNothing);
      expect(find.text('This block'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('replaces find results when the task timeline changes', (
      tester,
    ) async {
      await _pumpBlocks(
        tester,
        controller,
        timeline: const [CommandBlockTimelineItem.block('first')],
      );
      await tester.pumpAndSettle();
      await _findNeedle(tester, controller);
      expect(find.text(output.text['first']!), findsOneWidget);
      output.queriedIds.clear();

      await _pumpBlocks(
        tester,
        controller,
        timeline: const [CommandBlockTimelineItem.block('second')],
      );
      expect(find.text(output.text['first']!), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(output.queriedIds, ['second']);
      expect(find.text(output.text['first']!), findsNothing);
      expect(find.text(output.text['second']!), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('$CommandBlockController source range paging', () {
    late _EvictingOutput output;
    late CommandBlockController controller;
    const range = CommandBlockReadRange(
      startLine: 100,
      endLine: 101,
      sourceLineBase: 1000,
    );

    setUp(() {
      output = _EvictingOutput();
      controller = CommandBlockController(request: output.request)..refresh();
    });

    tearDown(() => controller.dispose());

    test('relocates the same source row when the retained floor has moved', () {
      output.sourceBase = 1010;

      expect(controller.pageRange('first', range), isTrue);

      final page = controller.displayBlock(controller.blocks.single);
      expect(page.offset, 90);
      expect(page.lines.first.sourceRow, _EvictingOutput.needleSource);
      expect(page.lines.first.text, _EvictingOutput.needle);
    });

    test('validates and retries a floor change between metadata and page', () {
      output.pageAdvances.add(10);

      expect(controller.pageRange('first', range), isTrue);

      expect(output.pageOffsets, [100, 90]);
      final page = controller.displayBlock(controller.blocks.single);
      expect(page.lines.first.sourceRow, _EvictingOutput.needleSource);
      expect(page.lines.first.text, _EvictingOutput.needle);
    });

    test(
      'does not publish a neighboring row when paging evicts the target',
      () {
        final original = controller.displayBlock(controller.blocks.single);
        output.pageAdvances.add(101);

        expect(controller.pageRange('first', range), isFalse);

        expect(
          controller.displayBlock(controller.blocks.single),
          same(original),
        );
        expect(controller.errors['first'], 'Output is no longer available');
        expect(output.pageOffsets, [100]);
      },
    );

    test('bounds retries while the retained floor keeps moving', () {
      final original = controller.displayBlock(controller.blocks.single);
      output.pageAdvances.addAll([1, 1, 1, 1]);

      expect(controller.pageRange('first', range), isFalse);

      expect(output.pageOffsets, [100, 99, 98]);
      expect(controller.displayBlock(controller.blocks.single), same(original));
      expect(controller.errors['first'], 'Output is no longer available');
    });
  });

  group('$TerminalCommandBlocksView source-aware find', () {
    late _EvictingOutput output;
    late CommandBlockController controller;

    setUp(() {
      output = _EvictingOutput();
      controller = CommandBlockController(request: output.request)..refresh();
    });

    tearDown(() => controller.dispose());

    for (final phone in [false, true]) {
      testWidgets(
        'opens the original source row after eviction on ${phone ? 'phone' : 'desktop'}',
        (tester) async {
          await _pumpBlocks(tester, controller, phone: phone);
          await tester.pumpAndSettle();
          await _findNeedle(tester, controller, toolbar: phone);
          expect(find.text(_EvictingOutput.needle), findsOneWidget);

          // Refreshes may change row indices without changing source identity.
          // They must not trigger a new global scan on every output update.
          for (var i = 0; i < 5; i++) {
            output.sourceBase += 2;
            controller.refresh();
            await tester.pump(const Duration(milliseconds: 200));
          }
          await tester.pumpAndSettle();
          expect(
            output.requests.where((r) => r['query'] == 'needle'),
            hasLength(1),
          );

          // Also handle output that arrives before the next controller refresh.
          output.sourceBase += 5;
          await tester.tap(find.text(_EvictingOutput.needle));
          await tester.pumpAndSettle();
          if (phone) {
            final reader = find.byKey(const Key('block-reader-scroll'));
            final scroll = tester.widget<ListView>(reader).controller!;
            final viewport = tester.widget<TerminalViewport>(
              find.byType(TerminalViewport).first,
            );
            final height = viewport.controller.measuredCellSize!.height;
            expect(scroll.offset, closeTo(85 * height, 1));
            expect(
              viewport.controller.frame.rows.any(
                (row) => row.text == _EvictingOutput.needle,
              ),
              isTrue,
            );
          } else {
            final page = controller.displayBlock(controller.blocks.single);
            expect(page.offset, 85);
            expect(page.lines.first.sourceRow, _EvictingOutput.needleSource);
            expect(page.lines.first.text, _EvictingOutput.needle);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );

      testWidgets(
        'reports an evicted search target on ${phone ? 'phone' : 'desktop'}',
        (tester) async {
          await _pumpBlocks(tester, controller, phone: phone);
          await tester.pumpAndSettle();
          await _findNeedle(tester, controller, toolbar: phone);
          output.sourceBase = _EvictingOutput.needleSource + 1;

          await tester.tap(find.text(_EvictingOutput.needle));
          await tester.pumpAndSettle();

          if (phone) {
            expect(
              find.byKey(const Key('block-reader-evidence-unavailable')),
              findsOneWidget,
            );
            expect(find.byKey(const Key('block-reader-scroll')), findsNothing);
          } else {
            expect(
              find.text('The matching output is no longer available'),
              findsOneWidget,
            );
            expect(controller.activeId, isNull);
            expect(output.pageOffsets, isEmpty);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }

    testWidgets('opens a running block match in the stable source reader', (
      tester,
    ) async {
      output.running = true;
      controller.refresh();
      await _pumpBlocks(tester, controller);
      await tester.pumpAndSettle();
      await _findNeedle(tester, controller);
      output.sourceBase += 10;

      await tester.tap(find.text(_EvictingOutput.needle));
      await tester.pumpAndSettle();

      final reader = find.byKey(const Key('block-reader-scroll'));
      final scroll = tester.widget<ListView>(reader).controller!;
      final viewport = tester.widget<TerminalViewport>(
        find.byType(TerminalViewport).first,
      );
      final height = viewport.controller.measuredCellSize!.height;
      expect(scroll.offset, closeTo(90 * height, 1));
      expect(
        tester
            .widgetList<CommandBlockTerminal>(find.byType(CommandBlockTerminal))
            .any(
              (page) => page.block.lines.any(
                (row) =>
                    row.sourceRow == _EvictingOutput.needleSource &&
                    row.index == 90,
              ),
            ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
