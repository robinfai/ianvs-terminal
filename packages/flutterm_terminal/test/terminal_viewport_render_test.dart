import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart';
import 'package:flutterm_terminal/src/terminal/render_terminal_viewport.dart';

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

class _RenderViewportHarness extends LeafRenderObjectWidget {
  const _RenderViewportHarness({
    required this.controller,
    required this.selectionController,
    required this.colors,
  });

  final TerminalViewportController controller;
  final SelectionController selectionController;
  final TerminalViewportColors colors;

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
      ..colors = colors;
  }
}
