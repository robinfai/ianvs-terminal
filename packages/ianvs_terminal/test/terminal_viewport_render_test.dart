import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:ianvs_terminal/src/terminal/render_terminal_viewport.dart';

void main() {
  testWidgets('near-canvas run backgrounds do not create row blocks', (
    tester,
  ) async {
    final renderObject = await _pumpRenderViewport(
      tester,
      row: const TerminalRow(
        index: 0,
        text: 'install.sh',
        styleRuns: [
          TerminalStyleRun(
            start: 0,
            end: 10,
            foreground: Color(0xFFE5E7EB),
            background: Color(0xFF151B22),
          ),
        ],
      ),
    );

    expect(renderObject.debugBackgroundSpansForRow(0), isEmpty);
  });

  testWidgets('distinct run backgrounds still render as highlight spans', (
    tester,
  ) async {
    final renderObject = await _pumpRenderViewport(
      tester,
      row: const TerminalRow(
        index: 0,
        text: 'highlight',
        styleRuns: [
          TerminalStyleRun(
            start: 0,
            end: 9,
            foreground: Color(0xFF111111),
            background: Color(0xFF00FF00),
          ),
        ],
      ),
    );

    final spans = renderObject.debugBackgroundSpansForRow(0);
    expect(spans, hasLength(1));
    expect(spans.single.background, const Color(0xFF00FF00));
  });

  testWidgets(
    'light terminal suppresses black background on ls padding spaces only',
    (tester) async {
      final renderObject = await _pumpRenderViewport(
        tester,
        row: const TerminalRow(
          index: 0,
          text: 'Documents    Downloads',
          styleRuns: [
            TerminalStyleRun(start: 0, end: 9),
            TerminalStyleRun(
              start: 9,
              end: 13,
              foreground: Color(0xFF111111),
              background: Color(0xFF000000),
            ),
            TerminalStyleRun(start: 13, end: 22),
          ],
        ),
        colors: TerminalViewportColors.light,
      );

      expect(renderObject.debugBackgroundSpansForRow(0), isEmpty);
    },
  );

  testWidgets('light terminal preserves black background behind text', (
    tester,
  ) async {
    final renderObject = await _pumpRenderViewport(
      tester,
      row: const TerminalRow(
        index: 0,
        text: 'ERR',
        styleRuns: [
          TerminalStyleRun(
            start: 0,
            end: 3,
            foreground: Color(0xFFFFFFFF),
            background: Color(0xFF000000),
          ),
        ],
      ),
      colors: TerminalViewportColors.light,
    );

    final spans = renderObject.debugBackgroundSpansForRow(0);
    expect(spans, hasLength(1));
    expect(spans.single.startColumn, 0);
    expect(spans.single.endColumn, 3);
    expect(spans.single.background, const Color(0xFF000000));
  });

  testWidgets('autosuggestion foreground renders as a visible ghost run', (
    tester,
  ) async {
    final renderObject = await _pumpRenderViewport(
      tester,
      row: const TerminalRow(
        index: 0,
        text: 'g ghost-suggestion',
        styleRuns: [
          TerminalStyleRun(start: 0, end: 1),
          TerminalStyleRun(start: 1, end: 18, foreground: Color(0xFF687378)),
        ],
      ),
      colors: const TerminalViewportColors(
        canvasBackground: Color(0xFF10141A),
        foreground: Color(0xFFE5E7EB),
        cursor: Color(0xFFE5E7EB),
        selection: Color(0x663B82F6),
        scrollbarTrack: Color(0x00000000),
        scrollbarThumb: Color(0x00000000),
        minimumContrastRatio: 4.5,
      ),
    );

    final ghostStyle = renderObject
        .debugResolvedStylesForRow(0)
        .singleWhere((style) => style.start == 1 && style.end == 18);

    expect(ghostStyle.foreground, isNot(const Color(0xFF10141A)));
    expect(ghostStyle.foreground, isNot(const Color(0xFFE5E7EB)));
    expect(ghostStyle.background, isNull);
  });

  testWidgets('search highlights align to snapped terminal cells', (
    tester,
  ) async {
    final renderObject = await _pumpRenderViewportFrame(
      tester,
      frame: TerminalFrameDiff(
        rows: List<TerminalRow>.generate(
          4,
          (index) => TerminalRow(index: index, text: 'row $index'),
        ),
        cursor: const TerminalCursor(row: 0, col: 0, visible: false),
        viewportRows: 4,
        viewportCols: 8,
        dirtyRanges: const [TerminalDirtyRange(start: 0, end: 4)],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
        viewportStartRow: 10,
      ),
      searchMatches: const [
        TerminalSearchMatch(
          row: 11,
          startCol: 2,
          endCol: 5,
          text: 'ERR',
          scrollbackOffset: 0,
        ),
        TerminalSearchMatch(
          row: 13,
          startCol: 6,
          endCol: 12,
          text: 'edge',
          scrollbackOffset: 0,
        ),
      ],
      activeSearchMatchIndex: 0,
    );

    final cellSize = renderObject.debugCellSize;
    final rects = renderObject.debugSearchHighlightRects;

    expect(rects, hasLength(2));
    _expectRectClose(
      rects[0],
      Rect.fromLTWH(
        cellSize.width * 2,
        cellSize.height,
        cellSize.width * 3,
        cellSize.height,
      ),
    );
    _expectRectClose(
      rects[1],
      Rect.fromLTWH(
        cellSize.width * 6,
        cellSize.height * 3,
        cellSize.width * 2,
        cellSize.height,
      ),
    );
  });

  testWidgets('search highlights skip matches outside visible rows', (
    tester,
  ) async {
    final renderObject = await _pumpRenderViewportFrame(
      tester,
      frame: TerminalFrameDiff(
        rows: List<TerminalRow>.generate(
          3,
          (index) => TerminalRow(index: index, text: 'row $index'),
        ),
        cursor: const TerminalCursor(row: 0, col: 0, visible: false),
        viewportRows: 3,
        viewportCols: 12,
        dirtyRanges: const [TerminalDirtyRange(start: 0, end: 3)],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
        viewportStartRow: 20,
      ),
      searchMatches: const [
        TerminalSearchMatch(
          row: 19,
          startCol: 0,
          endCol: 4,
          text: 'skip',
          scrollbackOffset: 0,
        ),
        TerminalSearchMatch(
          row: 21,
          startCol: 1,
          endCol: 5,
          text: 'keep',
          scrollbackOffset: 0,
        ),
        TerminalSearchMatch(
          row: 23,
          startCol: 0,
          endCol: 4,
          text: 'skip',
          scrollbackOffset: 0,
        ),
      ],
    );

    final cellSize = renderObject.debugCellSize;
    final rects = renderObject.debugSearchHighlightRects;

    expect(rects, hasLength(1));
    _expectRectClose(
      rects.single,
      Rect.fromLTWH(
        cellSize.width,
        cellSize.height,
        cellSize.width * 4,
        cellSize.height,
      ),
    );
  });

  testWidgets('search highlights stay on expected wrapped visible rows', (
    tester,
  ) async {
    final renderObject = await _pumpRenderViewportFrame(
      tester,
      frame: const TerminalFrameDiff(
        rows: [
          TerminalRow(index: 0, text: 'drwxr-xr-x luobinghui staff long-name'),
          TerminalRow(index: 1, text: 'ns'),
          TerminalRow(index: 2, text: 'drwxr-xr-x luobinghui staff'),
        ],
        cursor: TerminalCursor(row: 0, col: 0, visible: false),
        viewportRows: 3,
        viewportCols: 40,
        dirtyRanges: [TerminalDirtyRange(start: 0, end: 3)],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
        viewportStartRow: 70,
      ),
      searchMatches: const [
        TerminalSearchMatch(
          row: 70,
          startCol: 12,
          endCol: 15,
          text: 'luo',
          scrollbackOffset: 0,
        ),
        TerminalSearchMatch(
          row: 71,
          startCol: 0,
          endCol: 2,
          text: 'ns',
          scrollbackOffset: 0,
        ),
        TerminalSearchMatch(
          row: 72,
          startCol: 12,
          endCol: 15,
          text: 'luo',
          scrollbackOffset: 0,
        ),
      ],
    );

    final cellSize = renderObject.debugCellSize;
    final rects = renderObject.debugSearchHighlightRects;

    expect(rects, hasLength(3));
    _expectRectClose(
      rects[0],
      Rect.fromLTWH(
        cellSize.width * 12,
        0,
        cellSize.width * 3,
        cellSize.height,
      ),
    );
    _expectRectClose(
      rects[1],
      Rect.fromLTWH(0, cellSize.height, cellSize.width * 2, cellSize.height),
    );
    _expectRectClose(
      rects[2],
      Rect.fromLTWH(
        cellSize.width * 12,
        cellSize.height * 2,
        cellSize.width * 3,
        cellSize.height,
      ),
    );
  });
}

Future<RenderTerminalViewport> _pumpRenderViewport(
  WidgetTester tester, {
  required TerminalRow row,
  TerminalViewportColors colors = const TerminalViewportColors(
    canvasBackground: Color(0xFF10141A),
    foreground: Color(0xFFE5E7EB),
    cursor: Color(0xFFE5E7EB),
    selection: Color(0x663B82F6),
    scrollbarTrack: Color(0x00000000),
    scrollbarThumb: Color(0x00000000),
  ),
}) async {
  final controller = TerminalViewportController()
    ..updateFrame(
      TerminalFrameDiff(
        rows: [row],
        cursor: const TerminalCursor(row: 0, col: 0, visible: false),
        viewportRows: 1,
        viewportCols: 20,
        dirtyRanges: const [TerminalDirtyRange(start: 0, end: 1)],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
      ),
    );
  final selectionController = SelectionController();

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 320,
          height: 32,
          child: _RenderViewportHarness(
            controller: controller,
            selectionController: selectionController,
            colors: colors,
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  addTearDown(controller.dispose);
  return tester.renderObject(find.byType(_RenderViewportHarness));
}

Future<RenderTerminalViewport> _pumpRenderViewportFrame(
  WidgetTester tester, {
  required TerminalFrameDiff frame,
  List<TerminalSearchMatch> searchMatches = const [],
  int activeSearchMatchIndex = -1,
}) async {
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = TerminalViewportController()..updateFrame(frame);
  final selectionController = SelectionController();

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 320,
          height: 96,
          child: _RenderViewportHarness(
            controller: controller,
            selectionController: selectionController,
            colors: const TerminalViewportColors(
              canvasBackground: Color(0xFF10141A),
              foreground: Color(0xFFE5E7EB),
              cursor: Color(0xFFE5E7EB),
              selection: Color(0x663B82F6),
              scrollbarTrack: Color(0x00000000),
              scrollbarThumb: Color(0x00000000),
            ),
            searchMatches: searchMatches,
            activeSearchMatchIndex: activeSearchMatchIndex,
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  addTearDown(controller.dispose);
  return tester.renderObject(find.byType(_RenderViewportHarness));
}

class _RenderViewportHarness extends LeafRenderObjectWidget {
  const _RenderViewportHarness({
    required this.controller,
    required this.selectionController,
    required this.colors,
    this.searchMatches = const [],
    this.activeSearchMatchIndex = -1,
  });

  final TerminalViewportController controller;
  final SelectionController selectionController;
  final TerminalViewportColors colors;
  final List<TerminalSearchMatch> searchMatches;
  final int activeSearchMatchIndex;

  @override
  RenderTerminalViewport createRenderObject(BuildContext context) {
    return RenderTerminalViewport(
      controller: controller,
      selectionController: selectionController,
      cursorVisible: false,
      font: const TerminalFontConfig(),
      cursor: const TerminalCursorConfig(),
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      colors: colors,
      searchMatches: searchMatches,
      activeSearchMatchIndex: activeSearchMatchIndex,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderTerminalViewport renderObject,
  ) {
    renderObject
      ..controller = controller
      ..selectionController = selectionController
      ..cursorVisible = false
      ..font = const TerminalFontConfig()
      ..cursor = const TerminalCursorConfig()
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..colors = colors
      ..searchMatches = searchMatches
      ..activeSearchMatchIndex = activeSearchMatchIndex;
  }
}

void _expectRectClose(Rect actual, Rect expected) {
  expect(actual.left, moreOrLessEquals(expected.left, epsilon: 0.001));
  expect(actual.top, moreOrLessEquals(expected.top, epsilon: 0.001));
  expect(actual.width, moreOrLessEquals(expected.width, epsilon: 0.001));
  expect(actual.height, moreOrLessEquals(expected.height, epsilon: 0.001));
}
