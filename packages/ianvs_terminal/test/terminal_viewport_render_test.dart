import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:ianvs_terminal/src/terminal/render_terminal_viewport.dart';
import 'package:ianvs_pty/ianvs_pty.dart';

void main() {
  testWidgets('exact-canvas run backgrounds do not create row blocks', (
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
            background: Color(0xFF10141A),
          ),
        ],
      ),
    );

    expect(renderObject.debugBackgroundSpansForRow(0), isEmpty);
  });

  testWidgets('backend default backgrounds do not create row blocks', (
    tester,
  ) async {
    final renderObject = await _pumpRenderViewportFrame(
      tester,
      frame: const TerminalFrameDiff(
        rows: [
          TerminalRow(
            index: 0,
            text: 'brew cleanup',
            styleRuns: [
              TerminalStyleRun(
                start: 0,
                end: 12,
                foreground: Color(0xFF111111),
                background: Color(0xFFF8F7F2),
              ),
            ],
          ),
        ],
        cursor: TerminalCursor(row: 0, col: 0, visible: false),
        viewportRows: 1,
        viewportCols: 20,
        dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
        defaultBackground: Color(0xFFF8F7F2),
      ),
    );

    expect(renderObject.debugBackgroundSpansForRow(0), isEmpty);
    expect(renderObject.debugCanvasBackground, const Color(0xFFF8F7F2));
  });

  testWidgets(
    'render viewport emits benchmark paint stats when sink is provided',
    (tester) async {
      final benchmarkEvents = <Map<String, Object?>>[];
      await _pumpRenderViewportFrame(
        tester,
        benchmarkEventSink: benchmarkEvents.add,
        frame: const TerminalFrameDiff(
          rows: [
            TerminalRow(index: 0, text: 'alpha'),
            TerminalRow(index: 1, text: 'beta'),
          ],
          cursor: TerminalCursor(row: 0, col: 0, visible: false),
          viewportRows: 2,
          viewportCols: 20,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 2)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );

      expect(benchmarkEvents, isNotEmpty);
      final event = benchmarkEvents.singleWhere(
        (event) => event['schema_version'] == 'ianvs-bench-flutter-render-v1',
      );
      expect(event['frame_kind'], 'snapshot');
      expect(event['viewport_rows'], 2);
      expect(event['dirty_row_count'], 2);
      expect(event['row_visual_rebuild_count'], 2);
      expect(event['row_cache_misses'], 2);
      expect(event['paint_micros'], isA<int>());
    },
  );

  testWidgets('subtle Codex panel backgrounds still render', (tester) async {
    final renderObject = await _pumpRenderViewport(
      tester,
      row: const TerminalRow(
        index: 0,
        text: 'OpenAI Codex',
        styleRuns: [
          TerminalStyleRun(
            start: 0,
            end: 12,
            foreground: Color(0xFFE5E7EB),
            background: Color(0xFF151B22),
          ),
        ],
      ),
    );

    final spans = renderObject.debugBackgroundSpansForRow(0);
    expect(spans, hasLength(1));
    expect(spans.single.startColumn, 0);
    expect(spans.single.endColumn, 12);
    expect(spans.single.background, const Color(0xFF151B22));
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

  testWidgets(
    'powerline glyphs use cell-snapped geometry while Nerd icons stay narrow',
    (tester) async {
      final renderObject = await _pumpRenderViewport(
        tester,
        row: const TerminalRow(index: 0, text: '󰣇a'),
      );

      final cells = renderObject.debugResolvedCellsForRow(0);
      expect(cells.map((cell) => cell.text), ['', '', '', '', '󰣇', 'a']);

      final cellSize = renderObject.debugCellSize;
      final devicePixelRatio = tester.view.devicePixelRatio;
      final bleed = math.min(cellSize.width * 0.10, 1.0);
      final capBleed = bleed * 0.5;

      expect(cells[0].glyphClass, TerminalGlyphClass.powerlineCustom);
      expect(
        cells[0].placementPolicy,
        TerminalGlyphPlacementPolicy.powerlineRightArrow,
      );
      expect(cells[0].usesCustomGeometry, isTrue);
      _expectRectClose(
        cells[0].placementRect,
        _snapRectForTest(
          Rect.fromLTWH(0, 0, cellSize.width + bleed, cellSize.height),
          devicePixelRatio,
        ),
      );

      expect(cells[1].glyphClass, TerminalGlyphClass.powerlineCustom);
      expect(
        cells[1].placementPolicy,
        TerminalGlyphPlacementPolicy.powerlineLeftArrow,
      );
      expect(cells[1].usesCustomGeometry, isTrue);
      _expectRectClose(
        cells[1].placementRect,
        _snapRectForTest(
          Rect.fromLTWH(
            cellSize.width - bleed,
            0,
            cellSize.width + bleed,
            cellSize.height,
          ),
          devicePixelRatio,
        ),
      );

      expect(
        cells[2].placementPolicy,
        TerminalGlyphPlacementPolicy.powerlineLeftCap,
      );
      _expectRectClose(
        cells[2].placementRect,
        _snapRectForTest(
          Rect.fromLTWH(
            (2 * cellSize.width) - capBleed,
            0,
            cellSize.width + capBleed,
            cellSize.height,
          ),
          devicePixelRatio,
        ),
      );

      expect(
        cells[3].placementPolicy,
        TerminalGlyphPlacementPolicy.powerlineRightCap,
      );
      _expectRectClose(
        cells[3].placementRect,
        _snapRectForTest(
          Rect.fromLTWH(
            3 * cellSize.width,
            0,
            cellSize.width + capBleed,
            cellSize.height,
          ),
          devicePixelRatio,
        ),
      );

      expect(cells[4].glyphClass, TerminalGlyphClass.nerdIcon);
      expect(cells[4].usesCustomGeometry, isFalse);
      expect(
        cells[4].placementPolicy,
        TerminalGlyphPlacementPolicy.baselineLeft,
      );
      expect(cells[4].column, 4);
      expect(cells[5].text, 'a');
      expect(cells[5].column, 5);
    },
  );

  testWidgets(
    'emoji clusters reserve wide render columns while Nerd icons stay narrow',
    (tester) async {
      const technologist = '👩\u{200D}💻';
      const flag = '🇺🇸';
      const nerdIcon = '󰣇';
      const combining = 'e\u0301';
      final renderObject = await _pumpRenderViewport(
        tester,
        row: const TerminalRow(
          index: 0,
          text: '$technologist$flag$nerdIcon${combining}X',
        ),
      );

      final cells = renderObject.debugResolvedCellsForRow(0);
      expect(
        cells.map((cell) => (cell.text, cell.column)).toList(growable: false),
        <(String, int)>[
          (technologist, 0),
          (flag, 2),
          (nerdIcon, 4),
          (combining, 5),
          ('X', 6),
        ],
      );

      final cellSize = renderObject.debugCellSize;
      for (final cell in cells) {
        expect(
          cell.drawOffset.dx,
          moreOrLessEquals(cell.column * cellSize.width, epsilon: 0.001),
          reason: '${cell.text} should draw at terminal column ${cell.column}',
        );
      }
      expect(cells[0].glyphClass, TerminalGlyphClass.text);
      expect(cells[1].glyphClass, TerminalGlyphClass.text);
      expect(cells[2].glyphClass, TerminalGlyphClass.nerdIcon);
      expect(cells[3].glyphClass, TerminalGlyphClass.text);
      expect(cells[4].glyphClass, TerminalGlyphClass.text);
    },
  );

  testWidgets(
    'emoji tag keycap and modifier clusters keep render columns stable',
    (tester) async {
      const scotlandFlag =
          '\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}';
      const textKeycap = '1\u{20E3}';
      const wavingHandMediumSkinTone = '👋🏽';
      const textAirplane = '✈︎';
      const plainModifier = 'a🏽';
      final renderObject = await _pumpRenderViewport(
        tester,
        row: const TerminalRow(
          index: 0,
          text:
              '$scotlandFlag$textKeycap$wavingHandMediumSkinTone'
              '$textAirplane${plainModifier}Z',
        ),
      );

      final cells = renderObject.debugResolvedCellsForRow(0);
      expect(
        cells.map((cell) => (cell.text, cell.column)).toList(growable: false),
        <(String, int)>[
          (scotlandFlag, 0),
          (textKeycap, 2),
          (wavingHandMediumSkinTone, 4),
          (textAirplane, 6),
          (plainModifier, 7),
          ('Z', 8),
        ],
      );

      final cellSize = renderObject.debugCellSize;
      for (final cell in cells) {
        expect(
          cell.drawOffset.dx,
          moreOrLessEquals(cell.column * cellSize.width, epsilon: 0.001),
          reason: '${cell.text} should draw at terminal column ${cell.column}',
        );
        expect(cell.glyphClass, TerminalGlyphClass.text);
      }
    },
  );

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

  testWidgets('block cursor spans the full width of a CJK wide cell', (
    tester,
  ) async {
    final renderObject = await _pumpRenderViewportFrame(
      tester,
      cursorVisible: true,
      frame: const TerminalFrameDiff(
        rows: [TerminalRow(index: 0, text: 'a你b')],
        cursor: TerminalCursor(row: 0, col: 1, visible: true),
        viewportRows: 1,
        viewportCols: 4,
        dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
      ),
    );

    final cellSize = renderObject.debugCellSize;
    final cursorRect = renderObject.debugCursorRect;

    expect(cursorRect, isNotNull);
    _expectRectClose(
      cursorRect!,
      Rect.fromLTWH(cellSize.width, 0, cellSize.width * 2, cellSize.height),
    );
  });

  testWidgets('block cursor keeps the covered CJK glyph visible', (
    tester,
  ) async {
    final boundaryKey = GlobalKey();
    final renderObject = await _pumpRenderViewportFrame(
      tester,
      cursorVisible: true,
      repaintBoundaryKey: boundaryKey,
      frame: const TerminalFrameDiff(
        rows: [TerminalRow(index: 0, text: '打')],
        cursor: TerminalCursor(row: 0, col: 0, visible: true),
        viewportRows: 1,
        viewportCols: 2,
        dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
      ),
    );

    final cursorRect = renderObject.debugCursorRect;
    final cursorColor = renderObject.debugCursorColor;

    expect(cursorRect, isNotNull);
    expect(cursorColor, isNotNull);

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundaryKey),
    );
    final image = await _runUiAsync(tester, () => boundary.toImage());
    try {
      final byteData = await _runUiAsync(
        tester,
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      if (byteData == null) {
        throw StateError('Failed to read cursor image bytes.');
      }

      final nonCursorPixels = _countPixelsDifferentFrom(
        byteData.buffer.asUint8List(),
        imageWidth: image.width,
        sampleRect: cursorRect!,
        color: cursorColor!,
      );

      expect(nonCursorPixels, greaterThan(0));
    } finally {
      image.dispose();
    }
  });

  testWidgets('terminal viewport renders resolved graphic placements', (
    tester,
  ) async {
    final cache = TerminalGraphicsCache(loadAsset: (_) async => null);
    addTearDown(cache.dispose);

    final controller = TerminalViewportController()
      ..updateFrame(
        const TerminalFrameDiff(
          rows: [TerminalRow(index: 0, text: 'image')],
          cursor: TerminalCursor(row: 0, col: 0, visible: false),
          viewportRows: 2,
          viewportCols: 8,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 2)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
          graphics: [
            TerminalGraphicPlacement(
              placementId: 11,
              assetKey: TerminalGraphicAssetKey(id: 7, version: 1),
              protocol: 'iterm',
              row: 0,
              col: 1,
              widthPx: 12,
              heightPx: 40,
              widthCells: 2,
              heightCells: 2,
              sourceYOffsetPx: 8,
              visibleHeightPx: 24,
            ),
          ],
        ),
      );
    final selectionController = SelectionController();
    final runtime = TerminalRuntimeController(
      backend: _NoopPtyBackend(),
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    final inputController = TerminalInputController(
      sessionId: '1',
      runtime: runtime,
      readFrame: () => controller.frame,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 160,
          height: 48,
          child: TerminalViewport(
            controller: controller,
            selectionController: selectionController,
            inputController: inputController,
            onScrollLines: (_) {},
            onScrollToOffset: (_) {},
            graphicsCache: cache,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('terminal-graphic-11')), findsOneWidget);
    final positioned = tester.widget<Positioned>(
      find.ancestor(
        of: find.byKey(const Key('terminal-graphic-11')),
        matching: find.byType(Positioned),
      ),
    );
    final devicePixelRatio = tester.view.devicePixelRatio;
    expect(positioned.width, 12 / devicePixelRatio);
    expect(positioned.height, 24 / devicePixelRatio);

    runtime.dispose();
    controller.dispose();
  });

  testWidgets(
    'terminal viewport positions graphics using viewport-relative rows',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);

      final cache = TerminalGraphicsCache(loadAsset: (_) async => null);
      addTearDown(cache.dispose);

      const contentPadding = EdgeInsets.fromLTRB(3, 5, 7, 11);
      const cellSize = Size(11, 19);
      final controller = TerminalViewportController()
        ..updateMeasuredCellSize(cellSize)
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [
              TerminalRow(index: 50, text: 'before'),
              TerminalRow(index: 51, text: 'image'),
              TerminalRow(index: 52, text: 'after'),
            ],
            cursor: TerminalCursor(row: 1, col: 0, visible: false),
            viewportRows: 3,
            viewportCols: 8,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 3)],
            scrollbackOffset: 7,
            scrollbackMaxOffset: 10,
            viewportStartRow: 50,
            graphics: [
              TerminalGraphicPlacement(
                renderId: 220,
                placementId: 220,
                assetKey: TerminalGraphicAssetKey(id: 17, version: 3),
                protocol: 'kitty',
                row: 1,
                col: 2,
                widthPx: 24,
                heightPx: 72,
                widthCells: 2,
                heightCells: 4,
                sourceXOffsetPx: 8,
                visibleWidthPx: 16,
                sourceYOffsetPx: 18,
                visibleHeightPx: 36,
                xOffsetPx: 4,
                yOffsetPx: 6,
              ),
            ],
          ),
        );
      final selectionController = SelectionController();
      final runtime = TerminalRuntimeController(
        backend: _NoopPtyBackend(),
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: runtime,
        readFrame: () => controller.frame,
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 160,
            height: 96,
            child: TerminalViewport(
              controller: controller,
              selectionController: selectionController,
              inputController: inputController,
              onScrollLines: (_) {},
              onScrollToOffset: (_) {},
              contentPadding: contentPadding,
              graphicsCache: cache,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final positioned = tester.widget<Positioned>(
        find.ancestor(
          of: find.byKey(const Key('terminal-graphic-220')),
          matching: find.byType(Positioned),
        ),
      );

      expect(
        positioned.left,
        moreOrLessEquals(
          contentPadding.left + 2 * cellSize.width + 4,
          epsilon: 0.001,
        ),
      );
      expect(
        positioned.top,
        moreOrLessEquals(
          contentPadding.top + cellSize.height + 6,
          epsilon: 0.001,
        ),
      );
      expect(positioned.width, moreOrLessEquals(16, epsilon: 0.001));
      expect(positioned.height, moreOrLessEquals(36, epsilon: 0.001));

      runtime.dispose();
      controller.dispose();
    },
  );

  testWidgets('terminal viewport layers graphics around text by z-index', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    final cache = TerminalGraphicsCache(loadAsset: (_) async => null);
    addTearDown(cache.dispose);

    final controller = TerminalViewportController()
      ..updateFrame(
        const TerminalFrameDiff(
          rows: [TerminalRow(index: 0, text: 'text')],
          cursor: TerminalCursor(row: 0, col: 0, visible: false),
          viewportRows: 1,
          viewportCols: 8,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
          graphics: [
            TerminalGraphicPlacement(
              renderId: 401,
              placementId: 401,
              assetKey: TerminalGraphicAssetKey(id: 41, version: 1),
              protocol: 'kitty',
              row: 0,
              col: 0,
              widthPx: 8,
              heightPx: 16,
              widthCells: 1,
              heightCells: 1,
              zIndex: -1,
            ),
            TerminalGraphicPlacement(
              renderId: 402,
              placementId: 402,
              assetKey: TerminalGraphicAssetKey(id: 42, version: 1),
              protocol: 'kitty',
              row: 0,
              col: 1,
              widthPx: 8,
              heightPx: 16,
              widthCells: 1,
              heightCells: 1,
              zIndex: 1,
            ),
          ],
        ),
      );
    final selectionController = SelectionController();
    final runtime = TerminalRuntimeController(
      backend: _NoopPtyBackend(),
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    final inputController = TerminalInputController(
      sessionId: '1',
      runtime: runtime,
      readFrame: () => controller.frame,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 160,
          height: 48,
          child: TerminalViewport(
            controller: controller,
            selectionController: selectionController,
            inputController: inputController,
            onScrollLines: (_) {},
            onScrollToOffset: (_) {},
            graphicsCache: cache,
          ),
        ),
      ),
    );
    await tester.pump();

    const belowGraphicKey = Key('terminal-graphic-401');
    const aboveGraphicKey = Key('terminal-graphic-402');
    expect(find.byKey(belowGraphicKey), findsOneWidget);
    expect(find.byKey(aboveGraphicKey), findsOneWidget);

    final stackElement = tester
        .elementList(find.byType(Stack))
        .firstWhere(
          (element) =>
              _elementSubtreeContainsKey(element, belowGraphicKey) &&
              _elementSubtreeContainsKey(element, aboveGraphicKey) &&
              _elementSubtreeContainsWidgetTypeName(
                element,
                '_TerminalViewportSurface',
              ),
        );
    final belowIndex = _directChildIndexContainingKey(
      stackElement,
      belowGraphicKey,
    );
    final surfaceIndex = _directChildIndexContainingWidgetTypeName(
      stackElement,
      '_TerminalViewportSurface',
    );
    final aboveIndex = _directChildIndexContainingKey(
      stackElement,
      aboveGraphicKey,
    );

    expect(belowIndex, lessThan(surfaceIndex));
    expect(surfaceIndex, lessThan(aboveIndex));

    runtime.dispose();
    controller.dispose();
  });

  testWidgets(
    'terminal viewport gives duplicate render-id graphics unique keys',
    (tester) async {
      final cache = TerminalGraphicsCache(loadAsset: (_) async => null);
      addTearDown(cache.dispose);

      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'tiles')],
            cursor: TerminalCursor(row: 0, col: 0, visible: false),
            viewportRows: 1,
            viewportCols: 8,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
            graphics: [
              TerminalGraphicPlacement(
                renderId: 501,
                placementId: 501,
                assetKey: TerminalGraphicAssetKey(id: 50, version: 1),
                protocol: 'kitty',
                row: 0,
                col: 0,
                widthPx: 16,
                heightPx: 16,
                widthCells: 1,
                heightCells: 1,
                sourceXOffsetPx: 0,
                visibleWidthPx: 8,
              ),
              TerminalGraphicPlacement(
                renderId: 501,
                placementId: 501,
                assetKey: TerminalGraphicAssetKey(id: 50, version: 1),
                protocol: 'kitty',
                row: 0,
                col: 1,
                widthPx: 16,
                heightPx: 16,
                widthCells: 1,
                heightCells: 1,
                sourceXOffsetPx: 8,
                visibleWidthPx: 8,
              ),
            ],
          ),
        );
      final selectionController = SelectionController();
      final runtime = TerminalRuntimeController(
        backend: _NoopPtyBackend(),
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: runtime,
        readFrame: () => controller.frame,
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 160,
            height: 48,
            child: TerminalViewport(
              controller: controller,
              selectionController: selectionController,
              inputController: inputController,
              onScrollLines: (_) {},
              onScrollToOffset: (_) {},
              graphicsCache: cache,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('terminal-graphic-501')), findsNothing);
      expect(
        find.byKey(const Key('terminal-graphic-501-0-0-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('terminal-graphic-501-8-0-1')),
        findsOneWidget,
      );

      runtime.dispose();
      controller.dispose();
    },
  );

  testWidgets('terminal viewport applies graphic source rectangle transform', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    final sourceImage = (await tester.runAsync(
      () => createTestImage(cache: false),
    ))!;
    addTearDown(sourceImage.dispose);
    final cache = TerminalGraphicsCache(
      loadAsset: (key) async => TerminalGraphicAsset(
        key: key,
        width: 2,
        height: 2,
        rgba: Uint8List.fromList(const <int>[
          255, 0, 0, 255, // top-left red
          0, 255, 0, 255, // top-right green
          0, 0, 255, 255, // bottom-left blue
          255, 255, 0, 255, // bottom-right yellow
        ]),
      ),
      decodeImage: (_, _, _) async => sourceImage.clone(),
    );
    addTearDown(cache.dispose);

    final controller = TerminalViewportController()
      ..updateFrame(
        const TerminalFrameDiff(
          rows: [TerminalRow(index: 0, text: '')],
          cursor: TerminalCursor(row: 0, col: 0, visible: false),
          viewportRows: 1,
          viewportCols: 1,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
          graphics: [
            TerminalGraphicPlacement(
              renderId: 303,
              placementId: 303,
              assetKey: TerminalGraphicAssetKey(id: 31, version: 1),
              protocol: 'kitty',
              row: 0,
              col: 0,
              widthPx: 2,
              heightPx: 2,
              widthCells: 1,
              heightCells: 1,
              sourceXOffsetPx: 1,
              visibleWidthPx: 1,
              sourceYOffsetPx: 1,
              visibleHeightPx: 1,
              preserveAspectRatio: false,
            ),
          ],
        ),
      );
    final selectionController = SelectionController();
    final runtime = TerminalRuntimeController(
      backend: _NoopPtyBackend(),
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    final inputController = TerminalInputController(
      sessionId: '1',
      runtime: runtime,
      readFrame: () => controller.frame,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 4,
          height: 4,
          child: TerminalViewport(
            controller: controller,
            selectionController: selectionController,
            inputController: inputController,
            onScrollLines: (_) {},
            onScrollToOffset: (_) {},
            graphicsCache: cache,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('terminal-graphic-303')), findsOneWidget);
    expect(find.byType(RawImage), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('terminal-graphic-303'))),
      const Size(1, 1),
    );
    expect(tester.getSize(find.byType(RawImage)), const Size(2, 2));

    final transform = tester.widget<Transform>(
      find.descendant(
        of: find.byKey(const Key('terminal-graphic-303')),
        matching: find.byType(Transform),
      ),
    );
    final storage = transform.transform.storage;
    expect(storage[12], moreOrLessEquals(-1, epsilon: 0.001));
    expect(storage[13], moreOrLessEquals(-1, epsilon: 0.001));

    runtime.dispose();
    controller.dispose();
  });

  testWidgets('terminal viewport uses placement id for graphic identity', (
    tester,
  ) async {
    final redImage = (await tester.runAsync(
      () => createTestImage(cache: false),
    ))!;
    final greenImage = (await tester.runAsync(
      () => createTestImage(cache: false),
    ))!;
    final cache = TerminalGraphicsCache(
      loadAsset: (key) async => TerminalGraphicAsset(
        key: key,
        width: 1,
        height: 1,
        rgba: Uint8List.fromList(
          key.id == 7
              ? const <int>[255, 0, 0, 255]
              : const <int>[0, 255, 0, 255],
        ),
      ),
      decodeImage: (rgba, width, height) async =>
          rgba[0] == 255 ? redImage : greenImage,
    );
    addTearDown(cache.dispose);

    final controller = TerminalViewportController()
      ..updateFrame(
        const TerminalFrameDiff(
          rows: [TerminalRow(index: 0, text: 'image')],
          cursor: TerminalCursor(row: 0, col: 0, visible: false),
          viewportRows: 2,
          viewportCols: 8,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 2)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
          graphics: [
            TerminalGraphicPlacement(
              renderId: 101,
              placementId: 101,
              assetKey: TerminalGraphicAssetKey(id: 7, version: 1),
              protocol: 'kitty',
              row: 0,
              col: 1,
              widthPx: 1,
              heightPx: 1,
              widthCells: 1,
              heightCells: 1,
            ),
            TerminalGraphicPlacement(
              renderId: 102,
              placementId: 102,
              assetKey: TerminalGraphicAssetKey(id: 8, version: 1),
              protocol: 'kitty',
              row: 0,
              col: 3,
              widthPx: 1,
              heightPx: 1,
              widthCells: 1,
              heightCells: 1,
            ),
          ],
        ),
      );
    final selectionController = SelectionController();
    final runtime = TerminalRuntimeController(
      backend: _NoopPtyBackend(),
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    final inputController = TerminalInputController(
      sessionId: '1',
      runtime: runtime,
      readFrame: () => controller.frame,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 160,
          height: 48,
          child: TerminalViewport(
            controller: controller,
            selectionController: selectionController,
            inputController: inputController,
            onScrollLines: (_) {},
            onScrollToOffset: (_) {},
            graphicsCache: cache,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('terminal-graphic-101')), findsOneWidget);
    expect(find.byKey(const Key('terminal-graphic-102')), findsOneWidget);
    expect(find.byType(RawImage), findsNWidgets(2));

    runtime.dispose();
    controller.dispose();
  });

  testWidgets(
    'terminal viewport keeps previous graphic while next asset loads',
    (tester) async {
      final firstImage = (await tester.runAsync(
        () => createTestImage(cache: false),
      ))!;
      final secondImage = (await tester.runAsync(
        () => createTestImage(cache: false),
      ))!;
      final secondCompleter = Completer<ui.Image>();
      final diagnosticEvents = <Map<String, Object?>>[];
      final cache = TerminalGraphicsCache(
        diagnosticSessionId: '1',
        diagnosticEventSink: diagnosticEvents.add,
        loadAsset: (key) async => TerminalGraphicAsset(
          key: key,
          width: 1,
          height: 1,
          rgba: Uint8List.fromList(<int>[
            key.version == 1 ? 255 : 0,
            key.version == 1 ? 0 : 255,
            0,
            255,
          ]),
        ),
        decodeImage: (rgba, width, height) async {
          if (rgba[0] == 255) {
            return firstImage;
          }
          return secondCompleter.future;
        },
      );
      addTearDown(cache.dispose);

      final controller = TerminalViewportController()
        ..updateFrame(
          _graphicFrame(const TerminalGraphicAssetKey(id: 7, version: 1)),
        );
      final selectionController = SelectionController();
      final runtime = TerminalRuntimeController(
        backend: _NoopPtyBackend(),
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: runtime,
        readFrame: () => controller.frame,
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 160,
            height: 48,
            child: TerminalViewport(
              controller: controller,
              selectionController: selectionController,
              inputController: inputController,
              onScrollLines: (_) {},
              onScrollToOffset: (_) {},
              graphicsCache: cache,
              benchmarkEventSink: diagnosticEvents.add,
              graphicsDiagnosticSessionId: '1',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final firstVisibleImage = tester
          .widget<RawImage>(find.byType(RawImage))
          .image;
      expect(firstVisibleImage, isNotNull);

      controller.updateFrame(
        _graphicFrame(const TerminalGraphicAssetKey(id: 7, version: 2), col: 2),
      );
      await tester.pump();
      await tester.pump();

      expect(
        tester.widget<RawImage>(find.byType(RawImage)).image,
        same(firstVisibleImage),
      );

      secondCompleter.complete(secondImage);
      await tester.pump();
      await tester.pump();

      final secondVisibleImage = tester
          .widget<RawImage>(find.byType(RawImage))
          .image;
      expect(secondVisibleImage, isNotNull);
      expect(secondVisibleImage, isNot(same(firstVisibleImage)));
      expect(
        diagnosticEvents
            .where(
              (event) =>
                  event['schema_version'] ==
                  'ianvs-terminal-graphics-diagnostic-v1',
            )
            .map((event) => (event['layer'], event['event']))
            .toList(),
        containsAllInOrder(<(Object?, Object?)>[
          ('graphics_cache', 'cache_store'),
          ('viewport_overlay', 'overlay_visible'),
          ('viewport_overlay', 'overlay_waiting_for_replacement'),
          ('graphics_cache', 'cache_store'),
          ('viewport_overlay', 'overlay_visible'),
        ]),
      );

      runtime.dispose();
      controller.dispose();
    },
  );

  testWidgets(
    'terminal viewport keeps animated graphic geometry stable across versions',
    (tester) async {
      final firstImage = (await tester.runAsync(
        () => createTestImage(cache: false),
      ))!;
      final secondImage = (await tester.runAsync(
        () => createTestImage(cache: false),
      ))!;
      final cache = TerminalGraphicsCache(
        loadAsset: (key) async => TerminalGraphicAsset(
          key: key,
          width: 1,
          height: 1,
          rgba: Uint8List.fromList(<int>[
            key.version == 1 ? 255 : 0,
            key.version == 2 ? 255 : 0,
            0,
            255,
          ]),
        ),
        decodeImage: (rgba, width, height) async =>
            rgba[0] == 255 ? firstImage : secondImage,
      );
      addTearDown(cache.dispose);

      final controller = TerminalViewportController()
        ..updateFrame(
          _graphicFrame(
            const TerminalGraphicAssetKey(id: 7, version: 1),
            renderId: 77,
            placementId: 77,
            col: 2,
          ),
        );
      final selectionController = SelectionController();
      final runtime = TerminalRuntimeController(
        backend: _NoopPtyBackend(),
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: runtime,
        readFrame: () => controller.frame,
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 160,
            height: 48,
            child: TerminalViewport(
              controller: controller,
              selectionController: selectionController,
              inputController: inputController,
              onScrollLines: (_) {},
              onScrollToOffset: (_) {},
              graphicsCache: cache,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      controller.updateFrame(controller.frame);
      await tester.pump();
      await tester.pump();

      final graphicFinder = find.byKey(const Key('terminal-graphic-77'));
      expect(graphicFinder, findsOneWidget);
      final firstTopLeft = tester.getTopLeft(graphicFinder);
      final firstSize = tester.getSize(graphicFinder);
      final firstVisibleImage = tester
          .widget<RawImage>(find.byType(RawImage))
          .image;
      expect(firstVisibleImage, isNotNull);

      controller.updateFrame(
        _graphicFrame(
          const TerminalGraphicAssetKey(id: 7, version: 2),
          renderId: 77,
          placementId: 77,
          col: 2,
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(graphicFinder, findsOneWidget);
      expect(tester.getTopLeft(graphicFinder), firstTopLeft);
      expect(tester.getSize(graphicFinder), firstSize);
      final secondVisibleImage = tester
          .widget<RawImage>(find.byType(RawImage))
          .image;
      expect(secondVisibleImage, isNotNull);
      expect(secondVisibleImage, isNot(same(firstVisibleImage)));

      runtime.dispose();
      controller.dispose();
    },
  );

  testWidgets(
    'terminal viewport preserves graphic overlay when render id changes',
    (tester) async {
      final image = (await tester.runAsync(
        () => createTestImage(cache: false),
      ))!;
      final diagnosticEvents = <Map<String, Object?>>[];
      final cache = TerminalGraphicsCache(
        diagnosticSessionId: '1',
        diagnosticEventSink: diagnosticEvents.add,
        loadAsset: (key) async => TerminalGraphicAsset(
          key: key,
          width: 1,
          height: 1,
          rgba: Uint8List.fromList(const <int>[255, 0, 0, 255]),
        ),
        decodeImage: (_, _, _) async => image,
      );
      addTearDown(cache.dispose);

      final controller = TerminalViewportController()
        ..updateFrame(
          _graphicFrame(
            const TerminalGraphicAssetKey(id: 7, version: 1),
            renderId: 11,
            placementId: 11,
            col: 1,
          ),
        );
      final selectionController = SelectionController();
      final runtime = TerminalRuntimeController(
        backend: _NoopPtyBackend(),
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: runtime,
        readFrame: () => controller.frame,
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 160,
            height: 48,
            child: TerminalViewport(
              controller: controller,
              selectionController: selectionController,
              inputController: inputController,
              onScrollLines: (_) {},
              onScrollToOffset: (_) {},
              graphicsCache: cache,
              benchmarkEventSink: diagnosticEvents.add,
              graphicsDiagnosticSessionId: '1',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final firstVisibleImage = tester
          .widget<RawImage>(find.byType(RawImage))
          .image;
      expect(firstVisibleImage, isNotNull);
      diagnosticEvents.clear();

      controller.updateFrame(
        _graphicFrame(
          const TerminalGraphicAssetKey(id: 7, version: 1),
          renderId: 12,
          placementId: 12,
          col: 2,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('terminal-graphic-12')), findsOneWidget);
      expect(
        tester.widget<RawImage>(find.byType(RawImage)).image,
        same(firstVisibleImage),
      );
      expect(
        diagnosticEvents.where(
          (event) =>
              event['layer'] == 'viewport_overlay' &&
              event['event'] == 'overlay_clear',
        ),
        isEmpty,
      );

      runtime.dispose();
      controller.dispose();
    },
  );

  testWidgets(
    'terminal viewport keeps previous graphic when placement swaps asset id',
    (tester) async {
      final firstImage = (await tester.runAsync(
        () => createTestImage(cache: false),
      ))!;
      final secondImage = (await tester.runAsync(
        () => createTestImage(cache: false),
      ))!;
      final secondCompleter = Completer<ui.Image>();
      final cache = TerminalGraphicsCache(
        loadAsset: (key) async => TerminalGraphicAsset(
          key: key,
          width: 1,
          height: 1,
          rgba: Uint8List.fromList(<int>[
            key.id == 7 ? 255 : 0,
            key.id == 7 ? 0 : 255,
            0,
            255,
          ]),
        ),
        decodeImage: (rgba, width, height) async {
          if (rgba[0] == 255) {
            return firstImage;
          }
          return secondCompleter.future;
        },
      );
      addTearDown(cache.dispose);

      final controller = TerminalViewportController()
        ..updateFrame(
          _graphicFrame(
            const TerminalGraphicAssetKey(id: 7, version: 1),
            renderId: 101,
            placementId: 11,
          ),
        );
      final selectionController = SelectionController();
      final runtime = TerminalRuntimeController(
        backend: _NoopPtyBackend(),
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: runtime,
        readFrame: () => controller.frame,
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 160,
            height: 48,
            child: TerminalViewport(
              controller: controller,
              selectionController: selectionController,
              inputController: inputController,
              onScrollLines: (_) {},
              onScrollToOffset: (_) {},
              graphicsCache: cache,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final firstVisibleImage = tester
          .widget<RawImage>(find.byType(RawImage))
          .image;
      expect(firstVisibleImage, isNotNull);

      controller.updateFrame(
        _graphicFrame(
          const TerminalGraphicAssetKey(id: 8, version: 1),
          renderId: 101,
          placementId: 11,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        tester.widget<RawImage>(find.byType(RawImage)).image,
        same(firstVisibleImage),
      );

      secondCompleter.complete(secondImage);
      await tester.pump();
      await tester.pump();

      final secondVisibleImage = tester
          .widget<RawImage>(find.byType(RawImage))
          .image;
      expect(secondVisibleImage, isNotNull);
      expect(secondVisibleImage, isNot(same(firstVisibleImage)));

      runtime.dispose();
      controller.dispose();
    },
  );

  testWidgets('terminal viewport keys graphic overlays by render id', (
    tester,
  ) async {
    final firstImage = (await tester.runAsync(
      () => createTestImage(cache: false),
    ))!;
    final secondImage = (await tester.runAsync(
      () => createTestImage(cache: false),
    ))!;
    final secondCompleter = Completer<ui.Image>();
    final cache = TerminalGraphicsCache(
      loadAsset: (key) async => TerminalGraphicAsset(
        key: key,
        width: 1,
        height: 1,
        rgba: Uint8List.fromList(<int>[
          key.id == 7 ? 255 : 0,
          key.id == 7 ? 0 : 255,
          0,
          255,
        ]),
      ),
      decodeImage: (rgba, width, height) async {
        if (rgba[0] == 255) {
          return firstImage;
        }
        return secondCompleter.future;
      },
    );
    addTearDown(cache.dispose);

    final controller = TerminalViewportController()
      ..updateFrame(
        _graphicFrame(
          const TerminalGraphicAssetKey(id: 7, version: 1),
          renderId: 101,
          placementId: 11,
        ),
      );
    final selectionController = SelectionController();
    final runtime = TerminalRuntimeController(
      backend: _NoopPtyBackend(),
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    final inputController = TerminalInputController(
      sessionId: '1',
      runtime: runtime,
      readFrame: () => controller.frame,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 160,
          height: 48,
          child: TerminalViewport(
            controller: controller,
            selectionController: selectionController,
            inputController: inputController,
            onScrollLines: (_) {},
            onScrollToOffset: (_) {},
            graphicsCache: cache,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final firstVisibleImage = tester
        .widget<RawImage>(find.byType(RawImage))
        .image;
    expect(firstVisibleImage, isNotNull);
    expect(find.byKey(const Key('terminal-graphic-101')), findsOneWidget);

    controller.updateFrame(
      _graphicFrame(
        const TerminalGraphicAssetKey(id: 8, version: 1),
        renderId: 101,
        placementId: 12,
        col: 3,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('terminal-graphic-101')), findsOneWidget);
    expect(
      tester.widget<RawImage>(find.byType(RawImage)).image,
      same(firstVisibleImage),
    );

    secondCompleter.complete(secondImage);
    await tester.pump();
    await tester.pump();

    final secondVisibleImage = tester
        .widget<RawImage>(find.byType(RawImage))
        .image;
    expect(secondVisibleImage, isNotNull);
    expect(secondVisibleImage, isNot(same(firstVisibleImage)));

    runtime.dispose();
    controller.dispose();
  });

  testWidgets('terminal viewport removes a graphic omitted by Rust', (
    tester,
  ) async {
    final image = (await tester.runAsync(() => createTestImage(cache: false)))!;
    final diagnosticEvents = <Map<String, Object?>>[];
    final cache = TerminalGraphicsCache(
      diagnosticSessionId: '1',
      diagnosticEventSink: diagnosticEvents.add,
      loadAsset: (key) async => TerminalGraphicAsset(
        key: key,
        width: 1,
        height: 1,
        rgba: Uint8List.fromList(const <int>[255, 0, 0, 255]),
      ),
      decodeImage: (rgba, width, height) async => image,
    );
    addTearDown(cache.dispose);

    final controller = TerminalViewportController()
      ..updateFrame(
        _graphicFrame(const TerminalGraphicAssetKey(id: 7, version: 1)),
      );
    final selectionController = SelectionController();
    final runtime = TerminalRuntimeController(
      backend: _NoopPtyBackend(),
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    final inputController = TerminalInputController(
      sessionId: '1',
      runtime: runtime,
      readFrame: () => controller.frame,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 160,
          height: 48,
          child: TerminalViewport(
            controller: controller,
            selectionController: selectionController,
            inputController: inputController,
            onScrollLines: (_) {},
            onScrollToOffset: (_) {},
            graphicsCache: cache,
            benchmarkEventSink: diagnosticEvents.add,
            graphicsDiagnosticSessionId: '1',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(RawImage), findsOneWidget);

    controller.updateFrame(_emptyGraphicFrame());
    await tester.pump();
    await tester.pump();

    expect(find.byType(RawImage), findsNothing);
    expect(
      diagnosticEvents
          .where(
            (event) =>
                event['schema_version'] ==
                'ianvs-terminal-graphics-diagnostic-v1',
          )
          .map((event) => (event['layer'], event['event']))
          .toList(),
      containsAllInOrder(<(Object?, Object?)>[
        ('graphics_cache', 'cache_store'),
        ('viewport_overlay', 'overlay_visible'),
        ('viewport_overlay', 'overlay_clear'),
      ]),
    );
    expect(
      diagnosticEvents.where(
        (event) =>
            event['layer'] == 'viewport_overlay' &&
            event['event'] == 'overlay_clear' &&
            event['reason'] == 'dispose' &&
            event['session_id'] == '1',
      ),
      isNotEmpty,
    );

    runtime.dispose();
    controller.dispose();
  });

  testWidgets(
    'terminal viewport does not resurrect omitted graphic after late decode',
    (tester) async {
      final image = (await tester.runAsync(
        () => createTestImage(cache: false),
      ))!;
      final decodeCompleter = Completer<ui.Image>();
      final cache = TerminalGraphicsCache(
        loadAsset: (key) async => TerminalGraphicAsset(
          key: key,
          width: 1,
          height: 1,
          rgba: Uint8List.fromList(const <int>[255, 0, 0, 255]),
        ),
        decodeImage: (_, _, _) => decodeCompleter.future,
      );
      addTearDown(cache.dispose);

      final controller = TerminalViewportController()
        ..updateFrame(
          _graphicFrame(const TerminalGraphicAssetKey(id: 7, version: 1)),
        );
      final selectionController = SelectionController();
      final runtime = TerminalRuntimeController(
        backend: _NoopPtyBackend(),
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: runtime,
        readFrame: () => controller.frame,
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 160,
            height: 48,
            child: TerminalViewport(
              controller: controller,
              selectionController: selectionController,
              inputController: inputController,
              onScrollLines: (_) {},
              onScrollToOffset: (_) {},
              graphicsCache: cache,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('terminal-graphic-11')), findsOneWidget);
      expect(find.byType(RawImage), findsNothing);

      controller.updateFrame(_emptyGraphicFrame());
      await tester.pump();

      expect(find.byKey(const Key('terminal-graphic-11')), findsNothing);

      decodeCompleter.complete(image);
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('terminal-graphic-11')), findsNothing);
      expect(find.byType(RawImage), findsNothing);
      expect(tester.takeException(), isNull);

      runtime.dispose();
      controller.dispose();
    },
  );

  testWidgets('terminal viewport evicts stale graphics on initial mount', (
    tester,
  ) async {
    final staleImages = [
      (await tester.runAsync(() => createTestImage(cache: false)))!,
      (await tester.runAsync(() => createTestImage(cache: false)))!,
    ];
    final liveImage = (await tester.runAsync(
      () => createTestImage(cache: false),
    ))!;
    var staleDecodeIndex = 0;
    final loadCounts = <TerminalGraphicAssetKey, int>{};
    final cache = TerminalGraphicsCache(
      loadAsset: (key) async {
        loadCounts.update(key, (value) => value + 1, ifAbsent: () => 1);
        final red = key.id == 99 ? 99 : 255;
        return TerminalGraphicAsset(
          key: key,
          width: 1,
          height: 1,
          rgba: Uint8List.fromList(<int>[red, 0, 0, 255]),
        );
      },
      decodeImage: (rgba, width, height) async {
        if (rgba[0] == 99) {
          return staleImages[staleDecodeIndex++];
        }
        return liveImage;
      },
    );
    addTearDown(cache.dispose);

    const staleKey = TerminalGraphicAssetKey(id: 99, version: 1);
    await cache.imageFor(staleKey);
    expect(loadCounts[staleKey], 1);

    final controller = TerminalViewportController()
      ..updateFrame(
        _graphicFrame(const TerminalGraphicAssetKey(id: 7, version: 1)),
      );
    final selectionController = SelectionController();
    final runtime = TerminalRuntimeController(
      backend: _NoopPtyBackend(),
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    final inputController = TerminalInputController(
      sessionId: '1',
      runtime: runtime,
      readFrame: () => controller.frame,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 160,
          height: 48,
          child: TerminalViewport(
            controller: controller,
            selectionController: selectionController,
            inputController: inputController,
            onScrollLines: (_) {},
            onScrollToOffset: (_) {},
            graphicsCache: cache,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await cache.imageFor(staleKey);
    expect(loadCounts[staleKey], 2);

    runtime.dispose();
    controller.dispose();
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

TerminalFrameDiff _emptyGraphicFrame() {
  return const TerminalFrameDiff(
    rows: [TerminalRow(index: 0, text: 'image')],
    cursor: TerminalCursor(row: 0, col: 0, visible: false),
    viewportRows: 2,
    viewportCols: 8,
    dirtyRanges: [TerminalDirtyRange(start: 0, end: 2)],
    scrollbackOffset: 0,
    scrollbackMaxOffset: 0,
  );
}

TerminalFrameDiff _graphicFrame(
  TerminalGraphicAssetKey assetKey, {
  int col = 1,
  int renderId = 11,
  int placementId = 11,
}) {
  return TerminalFrameDiff(
    rows: const [TerminalRow(index: 0, text: 'image')],
    cursor: const TerminalCursor(row: 0, col: 0, visible: false),
    viewportRows: 2,
    viewportCols: 8,
    dirtyRanges: const [TerminalDirtyRange(start: 0, end: 2)],
    scrollbackOffset: 0,
    scrollbackMaxOffset: 0,
    graphics: [
      TerminalGraphicPlacement(
        renderId: renderId,
        placementId: placementId,
        assetKey: assetKey,
        protocol: 'kitty',
        row: 0,
        col: col,
        widthPx: 1,
        heightPx: 1,
        widthCells: 1,
        heightCells: 1,
      ),
    ],
  );
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
  bool cursorVisible = false,
  GlobalKey? repaintBoundaryKey,
  TerminalBenchmarkEventSink? benchmarkEventSink,
}) async {
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = TerminalViewportController()..updateFrame(frame);
  final selectionController = SelectionController();

  final viewport = SizedBox(
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
      cursorVisible: cursorVisible,
      benchmarkEventSink: benchmarkEventSink,
    ),
  );

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: repaintBoundaryKey == null
            ? viewport
            : RepaintBoundary(key: repaintBoundaryKey, child: viewport),
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
    this.cursorVisible = false,
    this.benchmarkEventSink,
  });

  final TerminalViewportController controller;
  final SelectionController selectionController;
  final TerminalViewportColors colors;
  final List<TerminalSearchMatch> searchMatches;
  final int activeSearchMatchIndex;
  final bool cursorVisible;
  final TerminalBenchmarkEventSink? benchmarkEventSink;

  @override
  RenderTerminalViewport createRenderObject(BuildContext context) {
    return RenderTerminalViewport(
      controller: controller,
      selectionController: selectionController,
      cursorVisible: cursorVisible,
      font: const TerminalFontConfig(),
      cursor: const TerminalCursorConfig(),
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      colors: colors,
      searchMatches: searchMatches,
      activeSearchMatchIndex: activeSearchMatchIndex,
      benchmarkEventSink: benchmarkEventSink,
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
      ..cursorVisible = cursorVisible
      ..font = const TerminalFontConfig()
      ..cursor = const TerminalCursorConfig()
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..colors = colors
      ..searchMatches = searchMatches
      ..activeSearchMatchIndex = activeSearchMatchIndex
      ..benchmarkEventSink = benchmarkEventSink;
  }
}

void _expectRectClose(Rect actual, Rect expected) {
  expect(actual.left, moreOrLessEquals(expected.left, epsilon: 0.001));
  expect(actual.top, moreOrLessEquals(expected.top, epsilon: 0.001));
  expect(actual.width, moreOrLessEquals(expected.width, epsilon: 0.001));
  expect(actual.height, moreOrLessEquals(expected.height, epsilon: 0.001));
}

Rect _snapRectForTest(Rect rect, double devicePixelRatio) {
  double snap(double value) {
    if (!value.isFinite ||
        !devicePixelRatio.isFinite ||
        devicePixelRatio <= 0) {
      return value;
    }
    return (value * devicePixelRatio).roundToDouble() / devicePixelRatio;
  }

  final left = snap(rect.left);
  final top = snap(rect.top);
  final right = math.max(left, snap(rect.right));
  final bottom = math.max(top, snap(rect.bottom));
  return Rect.fromLTRB(left, top, right, bottom);
}

bool _elementSubtreeContainsKey(Element element, Key key) {
  if (element.widget.key == key) {
    return true;
  }
  var found = false;
  element.visitChildElements((child) {
    if (!found && _elementSubtreeContainsKey(child, key)) {
      found = true;
    }
  });
  return found;
}

bool _elementSubtreeContainsWidgetTypeName(Element element, String typeName) {
  if (element.widget.runtimeType.toString() == typeName) {
    return true;
  }
  var found = false;
  element.visitChildElements((child) {
    if (!found && _elementSubtreeContainsWidgetTypeName(child, typeName)) {
      found = true;
    }
  });
  return found;
}

int _directChildIndexContainingKey(Element parent, Key key) {
  return _directChildIndexWhere(
    parent,
    (child) => _elementSubtreeContainsKey(child, key),
  );
}

int _directChildIndexContainingWidgetTypeName(Element parent, String typeName) {
  return _directChildIndexWhere(
    parent,
    (child) => _elementSubtreeContainsWidgetTypeName(child, typeName),
  );
}

int _directChildIndexWhere(Element parent, bool Function(Element child) test) {
  final children = <Element>[];
  parent.visitChildElements(children.add);
  for (var index = 0; index < children.length; index += 1) {
    if (test(children[index])) {
      return index;
    }
  }
  return -1;
}

int _countPixelsDifferentFrom(
  Uint8List bytes, {
  required int imageWidth,
  required Rect sampleRect,
  required Color color,
}) {
  final left = sampleRect.left.floor();
  final top = sampleRect.top.floor();
  final right = sampleRect.right.ceil();
  final bottom = sampleRect.bottom.ceil();
  var count = 0;
  for (var y = top; y < bottom; y += 1) {
    for (var x = left; x < right; x += 1) {
      final offset = ((y * imageWidth) + x) * 4;
      final pixel = Color.fromARGB(
        bytes[offset + 3],
        bytes[offset],
        bytes[offset + 1],
        bytes[offset + 2],
      );
      if (pixel.toARGB32() != color.toARGB32()) {
        count += 1;
      }
    }
  }
  return count;
}

Future<T> _runUiAsync<T>(
  WidgetTester tester,
  Future<T> Function() operation,
) async {
  final result = await tester.runAsync(operation);
  return result as T;
}

class _NoopPtyBackend implements PtySessionBackend {
  @override
  void closeSession(String sessionId) {}

  @override
  String createSession(String sessionConfigJson) => '1';

  @override
  int ping() => 42;

  @override
  List<PtyEvent> pollEvents(String sessionId) => const <PtyEvent>[];

  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
    int cellWidth = 0,
    int cellHeight = 0,
  }) {}

  @override
  void scrollViewport(String sessionId, int deltaLines) {}

  @override
  void scrollViewportTo(String sessionId, int offset) {}

  @override
  String? takeFrameDiffJson(String sessionId) => null;

  @override
  void writeInput(String sessionId, List<int> bytes) {}
}
