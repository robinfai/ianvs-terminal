import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart';

import 'package:app/features/terminal/render_terminal_viewport.dart';
import 'package:app/features/terminal/selection_controller.dart';
import 'package:app/features/terminal/terminal_input_controller.dart';
import 'package:app/features/terminal/terminal_painter_models.dart';
import 'package:app/features/terminal/terminal_viewport.dart';
import 'package:app/ffi/flutterm_core.dart';

import '../support/fake_core_bindings.dart';

void main() {
  testWidgets(
    'terminal viewport maps pointer offsets to cells and caches paragraphs',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [
              TerminalRow(
                index: 0,
                text: 'echo hello',
                styleRuns: [TerminalStyleRun(start: 0, end: 10)],
              ),
              TerminalRow(index: 1, text: 'pwd'),
            ],
            cursor: TerminalCursor(row: 1, col: 1, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 2)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        coreClient: TerminalCoreClient(FakeCoreBindings()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;

      expect(renderObject.debugCellForOffset(const Offset(20, 10)).row, 0);
      final buildsAfterFirstPaint = renderObject.debugParagraphBuilds;

      controller.updateFrame(
        const TerminalFrameDiff(
          rows: [
            TerminalRow(index: 0, text: 'echo hello'),
            TerminalRow(index: 1, text: 'pwd /tmp'),
          ],
          cursor: TerminalCursor(row: 1, col: 4, visible: true),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 1, end: 2)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );
      await tester.pump();

      expect(
        renderObject.debugParagraphBuilds,
        lessThan(buildsAfterFirstPaint + 3),
      );
      expect(controller.measuredCellSize, renderObject.debugCellSize);
      expect(controller.measuredCellSize!.width, greaterThan(0));
      expect(controller.measuredCellSize!.height, greaterThan(0));
    },
  );

  testWidgets(
    'terminal viewport maps upward wheel motion into positive scrollback deltas',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'hello')],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        coreClient: TerminalCoreClient(FakeCoreBindings()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );
      final scrollLines = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: scrollLines.add,
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(TerminalViewport));
      await tester.sendEventToBinding(
        PointerScrollEvent(position: center, scrollDelta: const Offset(0, -40)),
      );
      await tester.pump();
      expect(scrollLines, isNotEmpty);
      expect(scrollLines.single.abs(), greaterThan(1));
      expect(scrollLines.single, isPositive);
    },
  );

  testWidgets(
    'terminal viewport translates trackpad pan updates into positive scrollback deltas',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'hello')],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        coreClient: TerminalCoreClient(FakeCoreBindings()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );
      final scrollLines = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: scrollLines.add,
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(TerminalViewport));
      final trackpad = TestPointer(1, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(trackpad.panZoomStart(center));
      await tester.sendEventToBinding(
        trackpad.panZoomUpdate(center, pan: const Offset(0, -36)),
      );
      await tester.pump();
      await tester.sendEventToBinding(trackpad.panZoomEnd());

      expect(scrollLines, isNotEmpty);
      expect(scrollLines.single, isPositive);
    },
  );

  test(
    'terminal text style keeps a nerd-font fallback ahead of generic system fonts',
    () {
      expect(terminalPrimaryFontFamily, 'JetBrainsMono Nerd Font Mono');
      expect(terminalFontFamilyFallback, isNotEmpty);
      expect(terminalFontFamilyFallback.first, 'Menlo');
      expect(terminalFontFamilyFallback, contains('Apple Symbols'));
    },
  );

  testWidgets(
    'terminal viewport resolves powerline rows into terminal cells and keeps cursor aligned by cell column',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [
              TerminalRow(
                index: 0,
                text: '󰀵a',
                styleRuns: [
                  TerminalStyleRun(
                    start: 0,
                    end: 1,
                    foreground: Color(0xFF11111B),
                    background: Color(0xFFF38BA8),
                  ),
                  TerminalStyleRun(
                    start: 1,
                    end: 2,
                    foreground: Color(0xFFFAB387),
                    background: Color(0xFFF38BA8),
                  ),
                  TerminalStyleRun(
                    start: 2,
                    end: 3,
                    foreground: Color(0xFF11111B),
                    background: Color(0xFFFAB387),
                  ),
                ],
              ),
            ],
            cursor: TerminalCursor(row: 0, col: 3, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        coreClient: TerminalCoreClient(FakeCoreBindings()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;

      final cells = renderObject.debugResolvedCellsForRow(0);
      expect(cells.map((cell) => cell.text).toList(), ['󰀵', '', 'a']);
      expect(cells.map((cell) => cell.glyphClass).toList(), [
        TerminalGlyphClass.nerdIcon,
        TerminalGlyphClass.powerlineCustom,
        TerminalGlyphClass.text,
      ]);
      expect(cells.map((cell) => cell.background?.toARGB32()).toList(), [
        const Color(0xFFF38BA8).toARGB32(),
        const Color(0xFFF38BA8).toARGB32(),
        const Color(0xFFFAB387).toARGB32(),
      ]);
      expect(cells.map((cell) => cell.foreground.toARGB32()).toList(), [
        const Color(0xFF11111B).toARGB32(),
        const Color(0xFFFAB387).toARGB32(),
        const Color(0xFF11111B).toARGB32(),
      ]);

      final cursorRect = renderObject.debugCursorRect!;
      expect(cursorRect.left, 3 * renderObject.debugCellSize.width);
      expect(cursorRect.width, renderObject.debugCellSize.width);
    },
  );

  testWidgets(
    'terminal viewport positions regular glyphs using shared row text metrics',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'A')],
            cursor: TerminalCursor(row: 0, col: 1, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        coreClient: TerminalCoreClient(FakeCoreBindings()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;
      final cell = renderObject.debugResolvedCellsForRow(0).single;
      final rowTextMetrics = renderObject.debugRowTextMetrics;
      final targetBaselineY = _snapToDevicePixel(
        ((renderObject.debugCellSize.height - rowTextMetrics.textHeight) / 2) +
            rowTextMetrics.ascent,
        tester.view.devicePixelRatio,
      );

      expect(cell.placementPolicy, TerminalGlyphPlacementPolicy.baselineLeft);
      expect(cell.usesCustomGeometry, isFalse);
      expect(cell.drawOffset.dx, 0);
      expect(rowTextMetrics.textHeight, greaterThan(0));
      expect(
        cell.drawOffset.dy,
        closeTo(targetBaselineY - cell.glyphBaseline, 0.001),
      );
      expect(cell.baselineY, closeTo(targetBaselineY, 0.001));
      expect(
        cell.drawOffset.dy + cell.glyphBaseline,
        closeTo(cell.baselineY, 0.001),
      );
    },
  );

  testWidgets(
    'terminal viewport aligns letters and nerd-font glyphs to the same baseline',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'A󰀵B')],
            cursor: TerminalCursor(row: 0, col: 3, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        coreClient: TerminalCoreClient(FakeCoreBindings()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;
      final cells = renderObject.debugResolvedCellsForRow(0);

      expect(cells.map((cell) => cell.text).toList(), ['A', '󰀵', 'B']);
      expect(cells.map((cell) => cell.glyphClass).toList(), [
        TerminalGlyphClass.text,
        TerminalGlyphClass.nerdIcon,
        TerminalGlyphClass.text,
      ]);
      expect(cells.every((cell) => !cell.usesCustomGeometry), isTrue);
      expect(cells[0].baselineY, closeTo(cells[1].baselineY, 0.001));
      expect(cells[1].baselineY, closeTo(cells[2].baselineY, 0.001));
      expect(
        cells[0].drawOffset.dy + cells[0].glyphBaseline,
        closeTo(cells[0].baselineY, 0.001),
      );
      expect(
        cells[1].drawOffset.dy + cells[1].glyphBaseline,
        closeTo(cells[1].baselineY, 0.001),
      );
      expect(
        cells[2].drawOffset.dy + cells[2].glyphBaseline,
        closeTo(cells[2].baselineY, 0.001),
      );
    },
  );

  testWidgets(
    'terminal viewport keeps supplementary PUA icons out of the powerline lane',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: '󰀵')],
            cursor: TerminalCursor(row: 0, col: 2, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        coreClient: TerminalCoreClient(FakeCoreBindings()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;
      final cells = renderObject.debugResolvedCellsForRow(0);

      expect(cells.map((cell) => cell.text).toList(), ['󰀵', '']);
      expect(cells.map((cell) => cell.glyphClass).toList(), [
        TerminalGlyphClass.nerdIcon,
        TerminalGlyphClass.powerlineCustom,
      ]);
      expect(cells[0].usesCustomGeometry, isFalse);
      expect(cells[1].usesCustomGeometry, isTrue);
    },
  );

  testWidgets(
    'terminal viewport gives powerline glyphs directional placement and bleed',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [
              TerminalRow(
                index: 0,
                text: '',
                styleRuns: [
                  TerminalStyleRun(
                    start: 0,
                    end: 1,
                    foreground: Color(0xFFFAB387),
                    background: Color(0xFFF38BA8),
                  ),
                  TerminalStyleRun(
                    start: 1,
                    end: 2,
                    foreground: Color(0xFFF38BA8),
                    background: Color(0xFFFAB387),
                  ),
                  TerminalStyleRun(
                    start: 2,
                    end: 3,
                    foreground: Color(0xFFB4BEFE),
                    background: Color(0xFFF38BA8),
                  ),
                  TerminalStyleRun(
                    start: 3,
                    end: 4,
                    foreground: Color(0xFFF38BA8),
                    background: Color(0xFFB4BEFE),
                  ),
                ],
              ),
            ],
            cursor: TerminalCursor(row: 0, col: 4, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        coreClient: TerminalCoreClient(FakeCoreBindings()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;
      final cells = renderObject.debugResolvedCellsForRow(0);
      final cellWidth = renderObject.debugCellSize.width;
      final dpr = tester.view.devicePixelRatio;

      expect(cells.map((cell) => cell.placementPolicy).toList(), [
        TerminalGlyphPlacementPolicy.powerlineRightArrow,
        TerminalGlyphPlacementPolicy.powerlineLeftArrow,
        TerminalGlyphPlacementPolicy.powerlineLeftCap,
        TerminalGlyphPlacementPolicy.powerlineRightCap,
      ]);
      expect(cells.every((cell) => cell.usesCustomGeometry), isTrue);
      expect(cells[0].placementRect.right, greaterThan(cellWidth));
      expect(cells[1].placementRect.left, lessThan(cellWidth));
      expect(cells[2].placementRect.left, lessThan(2 * cellWidth));
      expect(
        cells[2].placementRect.right,
        closeTo(_snapToDevicePixel(3 * cellWidth, dpr), 0.001),
      );
      expect(
        cells[3].placementRect.left,
        closeTo(_snapToDevicePixel(3 * cellWidth, dpr), 0.001),
      );
      expect(cells[3].placementRect.right, greaterThan(4 * cellWidth));
      expect(
        cells[2].placementRect.width,
        lessThan(cells[0].placementRect.width),
      );
      expect(
        cells[3].placementRect.width,
        lessThan(cells[1].placementRect.width),
      );
      expect(cells[0].placementRect.top, closeTo(0, 0.001));
      expect(
        cells[0].placementRect.bottom,
        closeTo(renderObject.debugCellSize.height, 0.001),
      );
      expect(cells[1].placementRect.top, closeTo(0, 0.001));
      expect(
        cells[1].placementRect.bottom,
        closeTo(renderObject.debugCellSize.height, 0.001),
      );
      expect(cells[2].placementRect.top, closeTo(0, 0.001));
      expect(
        cells[2].placementRect.bottom,
        closeTo(renderObject.debugCellSize.height, 0.001),
      );
      expect(cells[3].placementRect.top, closeTo(0, 0.001));
      expect(
        cells[3].placementRect.bottom,
        closeTo(renderObject.debugCellSize.height, 0.001),
      );
    },
  );

  testWidgets(
    'terminal viewport coalesces adjacent same-color cells into continuous background spans',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [
              TerminalRow(
                index: 0,
                text: 'abc',
                styleRuns: [
                  TerminalStyleRun(
                    start: 0,
                    end: 3,
                    foreground: Color(0xFF11111B),
                    background: Color(0xFFF38BA8),
                  ),
                  TerminalStyleRun(
                    start: 3,
                    end: 4,
                    foreground: Color(0xFF11111B),
                    background: Color(0xFFFAB387),
                  ),
                ],
              ),
            ],
            cursor: TerminalCursor(row: 0, col: 4, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        coreClient: TerminalCoreClient(FakeCoreBindings()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;
      final spans = renderObject.debugBackgroundSpansForRow(0);
      final cellWidth = renderObject.debugCellSize.width;
      final dpr = tester.view.devicePixelRatio;

      expect(spans, hasLength(2));
      expect(spans[0].startColumn, 0);
      expect(spans[0].endColumn, 3);
      expect(spans[0].rect.left, 0);
      expect(
        spans[0].rect.width,
        closeTo(
          _snapToDevicePixel(3 * cellWidth, dpr) - _snapToDevicePixel(0, dpr),
          0.001,
        ),
      );
      expect(spans[1].startColumn, 3);
      expect(spans[1].endColumn, 4);
      expect(
        spans[1].rect.left,
        closeTo(_snapToDevicePixel(3 * cellWidth, dpr), 0.001),
      );
      expect(
        spans[1].rect.width,
        closeTo(
          _snapToDevicePixel(4 * cellWidth, dpr) -
              _snapToDevicePixel(3 * cellWidth, dpr),
          0.001,
        ),
      );
    },
  );

  testWidgets(
    'terminal viewport advances the next glyph after a wide CJK character',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: '你a')],
            cursor: TerminalCursor(row: 0, col: 3, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        coreClient: TerminalCoreClient(FakeCoreBindings()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;
      final cells = renderObject.debugResolvedCellsForRow(0);
      final cellWidth = renderObject.debugCellSize.width;

      expect(cells, hasLength(2));
      expect(cells[0].text, '你');
      expect(cells[0].column, 0);
      expect(cells[1].text, 'a');
      expect(cells[1].column, 2);
      expect(cells[1].drawOffset.dx, closeTo(2 * cellWidth, 0.001));
    },
  );

  testWidgets(
    'terminal viewport keeps emoji zwj clusters on one wide glyph slot',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: '👨‍👩‍👧a')],
            cursor: TerminalCursor(row: 0, col: 3, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        coreClient: TerminalCoreClient(FakeCoreBindings()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;
      final cells = renderObject.debugResolvedCellsForRow(0);
      final cellWidth = renderObject.debugCellSize.width;

      expect(cells, hasLength(2));
      expect(cells[0].text, '👨‍👩‍👧');
      expect(cells[0].column, 0);
      expect(cells[1].text, 'a');
      expect(cells[1].column, 2);
      expect(cells[1].drawOffset.dx, closeTo(2 * cellWidth, 0.001));
    },
  );

  testWidgets(
    'terminal viewport snaps baselines, background spans, and powerline rects to device pixels',
    (tester) async {
      tester.view.devicePixelRatio = 2.5;
      tester.view.physicalSize = const Size(2400, 1600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [
              TerminalRow(
                index: 0,
                text: 'A󰀵B',
                styleRuns: [
                  TerminalStyleRun(
                    start: 0,
                    end: 3,
                    foreground: Color(0xFF11111B),
                    background: Color(0xFFF38BA8),
                  ),
                  TerminalStyleRun(
                    start: 3,
                    end: 4,
                    foreground: Color(0xFF11111B),
                    background: Color(0xFFFAB387),
                  ),
                ],
              ),
            ],
            cursor: TerminalCursor(row: 0, col: 4, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        coreClient: TerminalCoreClient(FakeCoreBindings()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;
      final cells = renderObject.debugResolvedCellsForRow(0);
      final spans = renderObject.debugBackgroundSpansForRow(0);
      final dpr = tester.view.devicePixelRatio;

      for (final cell in cells.where((cell) => !cell.usesCustomGeometry)) {
        expect(
          cell.drawOffset.dy + cell.glyphBaseline,
          closeTo(cell.baselineY, 0.001),
        );
        expect(_isSnappedToDevicePixel(cell.baselineY, dpr), isTrue);
      }
      for (final cell in cells.where((cell) => cell.usesCustomGeometry)) {
        expect(_isSnappedToDevicePixel(cell.baselineY, dpr), isTrue);
      }
      for (final span in spans) {
        _expectRectSnapped(span.rect, dpr);
      }
      for (final cell in cells.where((cell) => cell.usesCustomGeometry)) {
        _expectRectSnapped(cell.placementRect, dpr);
      }
    },
  );

  testWidgets(
    'terminal cursor blinks while focused and the frame cursor is visible',
    (tester) async {
      final focusNode = FocusNode(debugLabel: 'terminal-test-focus');
      addTearDown(focusNode.dispose);

      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'ready')],
            cursor: TerminalCursor(row: 0, col: 2, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        coreClient: TerminalCoreClient(FakeCoreBindings()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
                focusNode: focusNode,
              ),
            ),
          ),
        ),
      );

      focusNode.requestFocus();
      await tester.pump();

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;

      expect(renderObject.debugCursorVisible, isTrue);

      await tester.pump(const Duration(milliseconds: 700));

      expect(renderObject.debugCursorVisible, isFalse);

      await tester.pump(const Duration(milliseconds: 700));

      expect(renderObject.debugCursorVisible, isTrue);
    },
  );

  testWidgets(
    'terminal cursor stops blinking and resets visible when focus is lost',
    (tester) async {
      final focusNode = FocusNode(debugLabel: 'terminal-test-focus');
      final nextFocusNode = FocusNode(debugLabel: 'terminal-test-next-focus');
      addTearDown(focusNode.dispose);
      addTearDown(nextFocusNode.dispose);

      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'ready')],
            cursor: TerminalCursor(row: 0, col: 2, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        coreClient: TerminalCoreClient(FakeCoreBindings()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  width: 400,
                  height: 200,
                  child: TerminalViewport(
                    controller: controller,
                    selectionController: selectionController,
                    inputController: inputController,
                    onScrollLines: (_) {},
                    onScrollToOffset: (_) {},
                    focusNode: focusNode,
                  ),
                ),
                Focus(
                  focusNode: nextFocusNode,
                  child: const SizedBox(width: 1, height: 1),
                ),
              ],
            ),
          ),
        ),
      );

      focusNode.requestFocus();
      await tester.pump();

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;

      await tester.pump(const Duration(milliseconds: 700));
      expect(renderObject.debugCursorVisible, isFalse);

      nextFocusNode.requestFocus();
      await tester.pump();
      await tester.pump();

      expect(focusNode.hasFocus, isFalse);
      expect(nextFocusNode.hasFocus, isTrue);

      expect(renderObject.debugCursorVisible, isTrue);

      await tester.pump(const Duration(milliseconds: 700));
      expect(renderObject.debugCursorVisible, isTrue);
    },
  );

  testWidgets(
    'terminal cursor resets visible when the frame cursor hides and shows again',
    (tester) async {
      final focusNode = FocusNode(debugLabel: 'terminal-test-focus');
      addTearDown(focusNode.dispose);

      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'ready')],
            cursor: TerminalCursor(row: 0, col: 2, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        coreClient: TerminalCoreClient(FakeCoreBindings()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
                focusNode: focusNode,
              ),
            ),
          ),
        ),
      );

      focusNode.requestFocus();
      await tester.pump();

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;

      await tester.pump(const Duration(milliseconds: 700));
      expect(renderObject.debugCursorVisible, isFalse);

      controller.updateFrame(
        const TerminalFrameDiff(
          rows: [TerminalRow(index: 0, text: 'ready')],
          cursor: TerminalCursor(row: 0, col: 2, visible: false),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );
      await tester.pump();

      controller.updateFrame(
        const TerminalFrameDiff(
          rows: [TerminalRow(index: 0, text: 'ready')],
          cursor: TerminalCursor(row: 0, col: 2, visible: true),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );
      await tester.pump();

      expect(renderObject.debugCursorVisible, isTrue);

      await tester.pump(const Duration(milliseconds: 700));
      expect(renderObject.debugCursorVisible, isFalse);
    },
  );

  testWidgets(
    'terminal viewport rebinds focus and controller updates after widget rebuild',
    (tester) async {
      final focusNodeA = FocusNode(debugLabel: 'terminal-test-focus-a');
      final focusNodeB = FocusNode(debugLabel: 'terminal-test-focus-b');
      addTearDown(focusNodeA.dispose);
      addTearDown(focusNodeB.dispose);

      final controllerA = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'ready')],
            cursor: TerminalCursor(row: 0, col: 2, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );
      final controllerB = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'ready')],
            cursor: TerminalCursor(row: 0, col: 2, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        coreClient: TerminalCoreClient(FakeCoreBindings()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      Widget buildViewport({
        required TerminalViewportController controller,
        required FocusNode focusNode,
      }) {
        return MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
                focusNode: focusNode,
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(
        buildViewport(controller: controllerA, focusNode: focusNodeA),
      );

      focusNodeA.requestFocus();
      await tester.pump();

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;

      await tester.pump(const Duration(milliseconds: 700));
      expect(renderObject.debugCursorVisible, isFalse);

      await tester.pumpWidget(
        buildViewport(controller: controllerB, focusNode: focusNodeB),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(renderObject.debugCursorVisible, isTrue);

      focusNodeB.requestFocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(renderObject.debugCursorVisible, isFalse);
    },
  );

  testWidgets(
    'terminal viewport preserves trailing-space styles and resolves inverse colors',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [
              TerminalRow(
                index: 0,
                text: 'abc   ',
                styleRuns: [
                  TerminalStyleRun(
                    start: 0,
                    end: 6,
                    foreground: Color(0xFF22C55E),
                    background: Color(0xFFEF4444),
                    inverse: true,
                  ),
                ],
              ),
            ],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        coreClient: TerminalCoreClient(FakeCoreBindings()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );

      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;

      expect(renderObject.debugLastPaintedRowTexts.single, 'abc   ');

      final resolvedStyle = renderObject.debugResolvedStylesForRow(0).single;
      expect(resolvedStyle.start, 0);
      expect(resolvedStyle.end, 6);
      expect(
        resolvedStyle.foreground.toARGB32(),
        const Color(0xFFEF4444).toARGB32(),
      );
      expect(
        resolvedStyle.background?.toARGB32(),
        const Color(0xFF22C55E).toARGB32(),
      );
    },
  );

  testWidgets(
    'terminal viewport only shows a scrollbar for overflow and dragging it uses absolute offsets',
    (tester) async {
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'hello')],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );

      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        coreClient: TerminalCoreClient(FakeCoreBindings()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );
      final scrollToOffsets = <int>[];
      final scrollLines = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: scrollLines.add,
                onScrollToOffset: scrollToOffsets.add,
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(terminalScrollbarTrackKey), findsNothing);
      expect(find.byKey(terminalScrollbarThumbKey), findsNothing);

      controller.updateFrame(
        const TerminalFrameDiff(
          rows: [TerminalRow(index: 0, text: 'hello')],
          cursor: TerminalCursor(row: 0, col: 0, visible: true),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 120,
        ),
      );
      await tester.pump();

      expect(find.byKey(terminalScrollbarTrackKey), findsOneWidget);
      expect(find.byKey(terminalScrollbarThumbKey), findsOneWidget);

      await tester.drag(
        find.byKey(terminalScrollbarThumbKey),
        const Offset(0, -60),
      );
      await tester.pump();

      expect(scrollToOffsets, isNotEmpty);
      expect(scrollToOffsets.last, greaterThan(0));
      expect(scrollLines, isEmpty);
      expect(selectionController.selection, isNull);
    },
  );
}

double _snapToDevicePixel(double value, double devicePixelRatio) {
  if (!value.isFinite || !devicePixelRatio.isFinite || devicePixelRatio <= 0) {
    return value;
  }
  return (value * devicePixelRatio).roundToDouble() / devicePixelRatio;
}

bool _isSnappedToDevicePixel(double value, double devicePixelRatio) {
  final deviceValue = value * devicePixelRatio;
  return (deviceValue - deviceValue.roundToDouble()).abs() < 0.001;
}

void _expectRectSnapped(Rect rect, double devicePixelRatio) {
  expect(_isSnappedToDevicePixel(rect.left, devicePixelRatio), isTrue);
  expect(_isSnappedToDevicePixel(rect.top, devicePixelRatio), isTrue);
  expect(_isSnappedToDevicePixel(rect.right, devicePixelRatio), isTrue);
  expect(_isSnappedToDevicePixel(rect.bottom, devicePixelRatio), isTrue);
}
