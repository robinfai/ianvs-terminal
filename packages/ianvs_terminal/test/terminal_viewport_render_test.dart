import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:ianvs_terminal/src/terminal/render_terminal_cursor_overlay.dart';
import 'package:ianvs_terminal/src/terminal/render_terminal_viewport.dart';
import 'package:ianvs_terminal/src/terminal/terminal_cursor_overlay_experiment.dart';
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
          graphics: [
            TerminalGraphicPlacement(
              renderId: 11,
              placementId: 11,
              assetKey: TerminalGraphicAssetKey(id: 7, version: 1),
              protocol: 'kitty',
              row: 0,
              col: 1,
              widthPx: 1,
              heightPx: 1,
              widthCells: 1,
              heightCells: 1,
            ),
          ],
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
      expect(event['graphics_revision'], 1);
      expect(event['graphics_asset_revision'], 1);
    },
  );

  testWidgets(
    'render viewport reports non-frame paints without stale dirty rows',
    (tester) async {
      final benchmarkEvents = <Map<String, Object?>>[];
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [
              TerminalRow(index: 0, text: 'alpha'),
              TerminalRow(index: 1, text: 'beta'),
            ],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 2,
            viewportCols: 20,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 2)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );
      final selectionController = SelectionController();
      addTearDown(controller.dispose);

      Widget viewport({required bool cursorVisible}) {
        return Directionality(
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
                cursorVisible: cursorVisible,
                benchmarkEventSink: benchmarkEvents.add,
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(viewport(cursorVisible: false));
      await tester.pump();
      benchmarkEvents.clear();

      await tester.pumpWidget(viewport(cursorVisible: true));
      await tester.pump();

      final renderEvents = benchmarkEvents
          .where(
            (event) =>
                event['schema_version'] == 'ianvs-bench-flutter-render-v1',
          )
          .toList(growable: false);
      expect(renderEvents, hasLength(1));
      final event = renderEvents.single;
      expect(event['paint_kind'], 'non_frame');
      expect(event['has_new_frame'], isFalse);
      expect(event['dirty_row_count'], 0);
      expect(event['rows_visited'], 2);
      expect(event['picture_draw_count'], 2);
      expect(event['row_visual_rebuild_count'], 0);
      expect(event['row_cache_hits'], 2);
      expect(event['row_cache_misses'], 0);
      expect(event['debug_collection_enabled'], isTrue);

      final renderObject = tester.renderObject<RenderTerminalViewport>(
        find.byType(_RenderViewportHarness),
      );
      expect(renderObject.debugLastPaintedRowTexts, ['alpha', 'beta']);
      expect(renderObject.debugLastRebuiltRowIndexes, isEmpty);
    },
  );

  testWidgets(
    'block cursor repaints custom geometry without rebuilding its row',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      final benchmarkEvents = <Map<String, Object?>>[];
      final boundaryKey = GlobalKey();
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: '─')],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 1,
            viewportCols: 2,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );
      final selectionController = SelectionController();
      addTearDown(controller.dispose);

      Widget viewport({required bool cursorVisible}) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: boundaryKey,
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
                  cursorVisible: cursorVisible,
                  benchmarkEventSink: benchmarkEvents.add,
                ),
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(viewport(cursorVisible: false));
      await tester.pump();
      benchmarkEvents.clear();

      await tester.pumpWidget(viewport(cursorVisible: true));
      await tester.pump();

      final renderObject = tester.renderObject<RenderTerminalViewport>(
        find.byType(_RenderViewportHarness),
      );
      final cell = renderObject.debugResolvedCellsForRow(0).single;
      expect(cell.text, '─');
      expect(cell.usesCustomGeometry, isTrue);
      expect(cell.glyphClass, TerminalGlyphClass.boxDrawingCustom);
      expect(renderObject.debugLastRebuiltRowIndexes, isEmpty);

      final renderEvent = benchmarkEvents.singleWhere(
        (event) => event['schema_version'] == 'ianvs-bench-flutter-render-v1',
      );
      expect(renderEvent['paint_kind'], 'non_frame');
      expect(renderEvent['has_new_frame'], isFalse);
      expect(renderEvent['dirty_row_count'], 0);
      expect(renderEvent['rows_visited'], 1);
      expect(renderEvent['picture_draw_count'], 1);
      expect(renderEvent['row_visual_rebuild_count'], 0);
      expect(renderEvent['row_cache_hits'], 1);
      expect(renderEvent['row_cache_misses'], 0);

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
          throw StateError('Failed to read custom cursor image bytes.');
        }
        expect(
          _countPixelsDifferentFrom(
            byteData.buffer.asUint8List(),
            imageWidth: image.width,
            sampleRect: cursorRect!,
            color: cursorColor!,
          ),
          greaterThan(0),
        );
      } finally {
        image.dispose();
      }
    },
  );

  test('custom geometry rendering does not construct Paint per call', () {
    final source = _renderTerminalViewportSource();
    final methodStart = source.indexOf('  void _paintCustomGeometry(');
    final methodEnd = source.indexOf(
      '  double _boxDrawingStrokeWidth()',
      methodStart,
    );

    expect(methodStart, greaterThanOrEqualTo(0));
    expect(methodEnd, greaterThan(methodStart));
    expect(
      source.substring(methodStart, methodEnd),
      isNot(contains('Paint()')),
    );
  });

  test('painted cursor rect remains available outside debug collection', () {
    final source = _renderTerminalViewportSource();
    final paintStart = source.indexOf(
      '  void paint(PaintingContext context, Offset offset)',
    );
    final paintEnd = source.indexOf(
      '  void _emitBenchmarkPaintEvent(',
      paintStart,
    );

    expect(paintStart, greaterThanOrEqualTo(0));
    expect(paintEnd, greaterThan(paintStart));
    expect(source, contains('Rect? _paintedCursorRect;'));
    expect(
      source,
      contains('Rect? get debugCursorRect => _paintedCursorRect;'),
    );
    final paintSource = source.substring(paintStart, paintEnd);
    expect(
      paintSource,
      contains('_paintedCursorRect = cursorRect;\n      if (kDebugMode)'),
    );
    expect(
      paintSource,
      contains('_paintedCursorRect = null;\n      if (kDebugMode)'),
    );
  });

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

  testWidgets('invalid direct style runs do not affect cells', (tester) async {
    final renderObject = await _pumpRenderViewport(
      tester,
      row: const TerminalRow(
        index: 0,
        text: 'abc',
        styleRuns: [
          TerminalStyleRun(start: -2, end: 2, background: Color(0xFF00FF00)),
          TerminalStyleRun(start: 2, end: 1, background: Color(0xFFFF0000)),
          TerminalStyleRun(start: 1, end: 3, background: Color(0xFF0000FF)),
        ],
      ),
    );

    final spans = renderObject.debugBackgroundSpansForRow(0);
    expect(spans, hasLength(1));
    expect(spans.single.startColumn, 1);
    expect(spans.single.endColumn, 3);
    expect(spans.single.background, const Color(0xFF0000FF));
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

  testWidgets('non-finite contrast ratio falls back to default contrast', (
    tester,
  ) async {
    final renderObject = await _pumpRenderViewport(
      tester,
      row: const TerminalRow(
        index: 0,
        text: 'ghost',
        styleRuns: [
          TerminalStyleRun(start: 0, end: 5, foreground: Color(0xFF687378)),
        ],
      ),
      colors: const TerminalViewportColors(
        canvasBackground: Color(0xFF10141A),
        foreground: Color(0xFFE5E7EB),
        cursor: Color(0xFFE5E7EB),
        selection: Color(0x663B82F6),
        scrollbarTrack: Color(0x00000000),
        scrollbarThumb: Color(0x00000000),
        minimumContrastRatio: double.nan,
      ),
    );

    final resolvedStyle = renderObject.debugResolvedStylesForRow(0).single;

    expect(resolvedStyle.foreground, const Color(0xFF687378));
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

  testWidgets('search highlights tolerate non-finite radius', (tester) async {
    final renderObject = await _pumpRenderViewportFrame(
      tester,
      frame: const TerminalFrameDiff(
        rows: [TerminalRow(index: 0, text: 'ready')],
        cursor: TerminalCursor(row: 0, col: 0, visible: false),
        viewportRows: 1,
        viewportCols: 8,
        dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
      ),
      searchMatches: const [
        TerminalSearchMatch(
          row: 0,
          startCol: 1,
          endCol: 4,
          text: 'ead',
          scrollbackOffset: 0,
        ),
      ],
      activeSearchMatchIndex: 0,
      searchHighlightStyle: const TerminalSearchHighlightStyle(
        radius: double.nan,
      ),
    );

    expect(renderObject.debugSearchHighlightRects, hasLength(1));
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

  testWidgets('search highlights skip invalid direct matches', (tester) async {
    final renderObject = await _pumpRenderViewportFrame(
      tester,
      frame: const TerminalFrameDiff(
        rows: [
          TerminalRow(index: 0, text: 'row zero'),
          TerminalRow(index: 1, text: 'row one'),
        ],
        cursor: TerminalCursor(row: 0, col: 0, visible: false),
        viewportRows: 2,
        viewportCols: 6,
        dirtyRanges: [TerminalDirtyRange(start: 0, end: 2)],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
        viewportStartRow: 30,
      ),
      searchMatches: const [
        TerminalSearchMatch(
          row: 30,
          startCol: -1,
          endCol: 2,
          text: 'bad',
          scrollbackOffset: 0,
        ),
        TerminalSearchMatch(
          row: 30,
          startCol: 4,
          endCol: 3,
          text: 'bad',
          scrollbackOffset: 0,
        ),
        TerminalSearchMatch(
          row: 31,
          startCol: 0,
          endCol: 1,
          text: '',
          scrollbackOffset: 0,
        ),
        TerminalSearchMatch(
          row: 31,
          startCol: 4,
          endCol: 12,
          text: 'ok',
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
        cellSize.width * 4,
        cellSize.height,
        cellSize.width * 2,
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

  testWidgets(
    'terminal viewport synchronizes graphics cache only for live asset revisions',
    (tester) async {
      const assetV1 = TerminalGraphicAssetKey(id: 7, version: 1);
      const assetV2 = TerminalGraphicAssetKey(id: 7, version: 2);
      final cache = _RecordingTerminalGraphicsCache();
      final controller = TerminalViewportController()
        ..updateFrame(_graphicFrame(assetV1));
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
      addTearDown(cache.dispose);
      addTearDown(controller.dispose);
      addTearDown(runtime.dispose);

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
      expect(cache.liveKeySets, hasLength(1));
      expect(cache.liveKeySets.last, {assetV1});

      controller.updateFrame(
        _graphicFrame(
          assetV1,
          frameKind: TerminalFrameKind.delta,
          text: 'updated image',
        ),
      );
      await tester.pump();
      expect(cache.liveKeySets, hasLength(1));

      controller.updateFrame(
        _graphicFrame(assetV1, frameKind: TerminalFrameKind.delta, col: 2),
      );
      await tester.pump();
      expect(cache.liveKeySets, hasLength(1));

      controller.updateFrame(
        _graphicFrame(assetV2, frameKind: TerminalFrameKind.delta, col: 2),
      );
      await tester.pump();
      expect(cache.liveKeySets, hasLength(2));
      expect(cache.liveKeySets.last, {assetV2});

      controller.updateFrame(
        _emptyGraphicFrame(frameKind: TerminalFrameKind.delta),
      );
      await tester.pump();
      expect(cache.liveKeySets, hasLength(3));
      expect(cache.liveKeySets.last, isEmpty);
    },
  );

  testWidgets(
    'terminal viewport forces graphics cache sync after cache or controller replacement',
    (tester) async {
      final firstCache = _RecordingTerminalGraphicsCache();
      final secondCache = _RecordingTerminalGraphicsCache();
      final firstController = TerminalViewportController();
      final secondController = TerminalViewportController();
      final selectionController = SelectionController();
      final runtime = TerminalRuntimeController(
        backend: _NoopPtyBackend(),
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(firstCache.dispose);
      addTearDown(secondCache.dispose);
      addTearDown(firstController.dispose);
      addTearDown(secondController.dispose);
      addTearDown(runtime.dispose);

      Widget viewport(
        TerminalViewportController controller,
        TerminalGraphicsCache cache,
      ) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 160,
            height: 48,
            child: TerminalViewport(
              controller: controller,
              selectionController: selectionController,
              inputController: TerminalInputController(
                sessionId: '1',
                runtime: runtime,
                readFrame: () => controller.frame,
                readSelection: () => '',
                copySelection: (_) async {},
                readClipboard: () async => '',
              ),
              onScrollLines: (_) {},
              onScrollToOffset: (_) {},
              graphicsCache: cache,
            ),
          ),
        );
      }

      expect(firstController.graphicsAssetRevision, 0);
      expect(secondController.graphicsAssetRevision, 0);

      await tester.pumpWidget(viewport(firstController, firstCache));
      await tester.pump();
      expect(firstCache.liveKeySets, [<TerminalGraphicAssetKey>{}]);

      await tester.pumpWidget(viewport(firstController, secondCache));
      await tester.pump();
      expect(firstCache.liveKeySets, hasLength(1));
      expect(secondCache.liveKeySets, [<TerminalGraphicAssetKey>{}]);

      await tester.pumpWidget(viewport(secondController, secondCache));
      await tester.pump();
      expect(secondCache.liveKeySets, [
        <TerminalGraphicAssetKey>{},
        <TerminalGraphicAssetKey>{},
      ]);

      await tester.pumpWidget(viewport(secondController, secondCache));
      await tester.pump();
      expect(secondCache.liveKeySets, hasLength(2));
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

  test(
    'terminal cursor visual key compares every rendering input by value',
    () {
      final key = _terminalCursorVisualKey();
      final equalKey = key.copyWith(
        fontFallback: List<String>.of(key.fontFallback),
      );

      expect(key, equalKey);
      expect(key.hashCode, equalKey.hashCode);
      for (final change in _terminalCursorVisualKeyChanges(key)) {
        expect(change.key, isNot(key), reason: change.field);
      }
    },
  );

  test('terminal cursor overlay does not expand the debug renderer API', () {
    final source = _renderTerminalViewportSource();

    expect(source, isNot(contains('bool paintCursorOnSurface = true')));
    expect(source, isNot(contains('ValueGetter<bool>? cursorBlinkVisibility')));
    expect(
      source,
      isNot(contains('TerminalCursorVisualSnapshot? get cursorVisualSnapshot')),
    );
  });

  test(
    'terminal cursor snapshot cache rebuilds and disposes for every key field while reusing an equal key',
    () {
      final key = _terminalCursorVisualKey();
      for (final change in _terminalCursorVisualKeyChanges(key)) {
        final cache = TerminalCursorVisualSnapshotCache();
        var builds = 0;

        TerminalCursorVisualSnapshot build(TerminalCursorVisualKey value) {
          builds += 1;
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawRect(
            const Rect.fromLTWH(0, 0, 1, 1),
            Paint()..color = Colors.white,
          );
          return TerminalCursorVisualSnapshot(
            key: value,
            picture: recorder.endRecording(),
            rect: const Rect.fromLTWH(30, 40, 20, 20),
            color: Colors.white,
          );
        }

        final initial = cache.resolve(key: key, build: build);
        final initialPicture = initial.picture;
        final equal = cache.resolve(
          key: key.copyWith(fontFallback: List<String>.of(key.fontFallback)),
          build: build,
        );
        expect(equal, same(initial), reason: change.field);
        expect(builds, 1, reason: change.field);
        expect(initialPicture.debugDisposed, isFalse, reason: change.field);

        final rebuilt = cache.resolve(key: change.key, build: build);
        expect(rebuilt, isNot(same(initial)), reason: change.field);
        expect(builds, 2, reason: change.field);
        expect(initialPicture.debugDisposed, isTrue, reason: change.field);
        expect(cache.livePictureCount, 1, reason: change.field);

        final rebuiltPicture = rebuilt.picture;
        cache.dispose();
        expect(rebuiltPicture.debugDisposed, isTrue, reason: change.field);
        expect(cache.livePictureCount, 0, reason: change.field);
      }
    },
  );

  testWidgets(
    'terminal cursor overlay pixels and device alignment match surface block beam and underline at DPR 1 and 2 for ASCII and wide CJK',
    (tester) async {
      for (final devicePixelRatio in const <double>[1, 2]) {
        for (final shape in TerminalCursorShape.values) {
          for (final text in const <String>['A', '界']) {
            final surface = await _captureTerminalCursorPixels(
              tester,
              mode: TerminalCursorExperimentMode.surface,
              devicePixelRatio: devicePixelRatio,
              shape: shape,
              text: text,
            );
            final overlay = await _captureTerminalCursorPixels(
              tester,
              mode: TerminalCursorExperimentMode.overlay,
              devicePixelRatio: devicePixelRatio,
              shape: shape,
              text: text,
            );
            final caseName =
                '${shape.name} cursor over $text at DPR $devicePixelRatio';

            expect(
              overlay.bytes,
              orderedEquals(surface.bytes),
              reason: caseName,
            );
            _expectRectClose(overlay.cursorRect, surface.cursorRect);
            _expectRectDeviceAligned(
              overlay.cursorRect,
              devicePixelRatio,
              reason: caseName,
            );
            if (shape == TerminalCursorShape.block && text == '界') {
              expect(
                overlay.cursorRect.width,
                moreOrLessEquals(overlay.cellSize.width * 2, epsilon: 0.001),
                reason: caseName,
              );
            }
          }
        }
      }
    },
  );

  testWidgets(
    'terminal cursor overlay block pixels match surface inverse glyph custom geometry and smart contrast',
    (tester) async {
      final cases =
          <
            ({
              String name,
              String text,
              List<TerminalStyleRun> styleRuns,
              TerminalViewportColors colors,
            })
          >[
            (
              name: 'inverse glyph',
              text: 'A',
              styleRuns: const <TerminalStyleRun>[
                TerminalStyleRun(
                  start: 0,
                  end: 1,
                  foreground: Color(0xFFEF4444),
                  background: Color(0xFF22C55E),
                  inverse: true,
                ),
              ],
              colors: TerminalViewportColors.dark.copyWith(
                cursor: const Color(0xFF2563EB),
                smartCursorColor: false,
              ),
            ),
            (
              name: 'custom geometry',
              text: '─',
              styleRuns: const <TerminalStyleRun>[
                TerminalStyleRun(
                  start: 0,
                  end: 1,
                  foreground: Color(0xFFE5E7EB),
                  background: Color(0xFF10141A),
                ),
              ],
              colors: TerminalViewportColors.dark.copyWith(
                cursor: const Color(0xFF2563EB),
                smartCursorColor: false,
              ),
            ),
            (
              name: 'smart contrast',
              text: 'A',
              styleRuns: const <TerminalStyleRun>[
                TerminalStyleRun(
                  start: 0,
                  end: 1,
                  foreground: Color(0xFFE5E7EB),
                  background: Color(0xFF10141A),
                ),
              ],
              colors: TerminalViewportColors.dark.copyWith(
                cursor: const Color(0xFF10141A),
                smartCursorColor: true,
                minimumContrastRatio: 4.5,
              ),
            ),
          ];

      for (final testCase in cases) {
        final surface = await _captureTerminalCursorPixels(
          tester,
          mode: TerminalCursorExperimentMode.surface,
          devicePixelRatio: 2,
          shape: TerminalCursorShape.block,
          text: testCase.text,
          styleRuns: testCase.styleRuns,
          colors: testCase.colors,
        );
        final overlay = await _captureTerminalCursorPixels(
          tester,
          mode: TerminalCursorExperimentMode.overlay,
          devicePixelRatio: 2,
          shape: TerminalCursorShape.block,
          text: testCase.text,
          styleRuns: testCase.styleRuns,
          colors: testCase.colors,
        );

        expect(
          overlay.bytes,
          orderedEquals(surface.bytes),
          reason: testCase.name,
        );
        expect(overlay.cursorColor, surface.cursorColor, reason: testCase.name);
        if (testCase.name == 'smart contrast') {
          expect(
            overlay.cursorColor?.toARGB32(),
            isNot(const Color(0xFF10141A).toARGB32()),
          );
        }
      }
    },
  );

  testWidgets(
    'terminal cursor overlay blink emits one bounded cursor event without surface repaint and reuses its picture',
    (tester) async {
      final events = <Map<String, Object?>>[];
      final focusNode = FocusNode(debugLabel: 'terminal-overlay-test');
      final controller = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: <TerminalRow>[TerminalRow(index: 0, text: 'ready')],
            cursor: TerminalCursor(row: 0, col: 2, visible: true),
            viewportRows: 1,
            viewportCols: 20,
            dirtyRanges: <TerminalDirtyRange>[
              TerminalDirtyRange(start: 0, end: 1),
            ],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
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
        sessionId: 'cursor-overlay',
        runtime: runtime,
        readFrame: () => controller.frame,
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );
      addTearDown(focusNode.dispose);
      addTearDown(controller.dispose);
      addTearDown(selectionController.dispose);
      addTearDown(runtime.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 320,
            height: 96,
            child: TerminalViewport(
              controller: controller,
              selectionController: selectionController,
              inputController: inputController,
              focusNode: focusNode,
              onScrollLines: (_) {},
              onScrollToOffset: (_) {},
              benchmarkEventSink: events.add,
            ),
          ),
        ),
      );
      focusNode.requestFocus();
      await tester.pump();
      final renderObject = tester.allRenderObjects
          .whereType<RenderTerminalViewport>()
          .last;
      final pictureBeforeBlink = terminalCursorVisualSnapshotFor(
        renderObject,
      )!.picture;
      events.clear();

      await tester.pump(const Duration(milliseconds: 700));

      final cursorEvents = events
          .where(
            (event) =>
                event['schema_version'] == 'ianvs-bench-flutter-cursor-v1',
          )
          .toList(growable: false);
      expect(cursorEvents, hasLength(1));
      expect(
        events.where(
          (event) => event['schema_version'] == 'ianvs-bench-flutter-render-v1',
        ),
        isEmpty,
      );
      expect(
        terminalCursorVisualSnapshotFor(renderObject)!.picture,
        same(pictureBeforeBlink),
      );
      final event = cursorEvents.single;
      final paintArea = (event['paint_bounds_area']! as num).toDouble();
      final cellWidth = (event['cell_width_px']! as num).toDouble();
      final cellHeight = (event['cell_height_px']! as num).toDouble();
      final dpr = (event['device_pixel_ratio']! as num).toDouble();
      final byteLimit =
          (2 * cellWidth * dpr).ceil() * (cellHeight * dpr).ceil() * 4;
      expect(paintArea, greaterThan(0));
      expect(paintArea, lessThanOrEqualTo(2 * cellWidth * cellHeight));
      expect(event['cursor_picture_live_count'], 1);
      expect(event['overlay_layer_count'], 1);
      expect(
        event['cursor_picture_estimated_bytes'],
        lessThanOrEqualTo(byteLimit),
      );
      expect(find.byKey(terminalCursorOverlayKey), findsOneWidget);
    },
  );

  testWidgets('terminal cursor overlay preserves exact nine-layer stack order', (
    tester,
  ) async {
    final imageBytes = base64.decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADUlEQVR42mP8z8BQDwAFgwJ/lWnU2wAAAABJRU5ErkJggg==',
    );
    final focusNode = FocusNode(debugLabel: 'terminal-overlay-stack');
    final controller = TerminalViewportController()
      ..updateFrame(
        TerminalFrameDiff(
          rows: <TerminalRow>[
            TerminalRow(
              index: 0,
              text: 'link layer',
              modifiedAt: DateTime(2026, 7, 10, 12),
            ),
          ],
          cursor: const TerminalCursor(row: 0, col: 0, visible: true),
          viewportRows: 2,
          viewportCols: 12,
          dirtyRanges: const <TerminalDirtyRange>[
            TerminalDirtyRange(start: 0, end: 1),
          ],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 4,
          hyperlinks: const <TerminalHyperlinkRange>[
            TerminalHyperlinkRange(
              row: 0,
              startCol: 0,
              endCol: 4,
              uri: 'https://example.com/docs',
            ),
          ],
          inlineImages: <TerminalInlineImage>[
            TerminalInlineImage(
              row: 0,
              col: 5,
              widthCells: 1,
              heightCells: 1,
              bytes: imageBytes,
              altText: 'pixel',
            ),
          ],
          graphics: const <TerminalGraphicPlacement>[
            TerminalGraphicPlacement(
              renderId: 901,
              placementId: 901,
              assetKey: TerminalGraphicAssetKey(id: 91, version: 1),
              protocol: 'kitty',
              row: 0,
              col: 6,
              widthPx: 8,
              heightPx: 16,
              widthCells: 1,
              heightCells: 1,
              zIndex: -1,
            ),
            TerminalGraphicPlacement(
              renderId: 902,
              placementId: 902,
              assetKey: TerminalGraphicAssetKey(id: 92, version: 1),
              protocol: 'kitty',
              row: 0,
              col: 7,
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
    final cache = TerminalGraphicsCache(loadAsset: (_) async => null);
    final runtime = TerminalRuntimeController(
      backend: _NoopPtyBackend(),
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    final inputController = TerminalInputController(
      sessionId: 'cursor-overlay-stack',
      runtime: runtime,
      readFrame: () => controller.frame,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );
    addTearDown(focusNode.dispose);
    addTearDown(controller.dispose);
    addTearDown(selectionController.dispose);
    addTearDown(cache.dispose);
    addTearDown(runtime.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalCursorExperimentScope(
            mode: TerminalCursorExperimentMode.overlay,
            child: SizedBox(
              width: 400,
              height: 160,
              child: TerminalViewport(
                controller: controller,
                selectionController: selectionController,
                inputController: inputController,
                focusNode: focusNode,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
                graphicsCache: cache,
                showLineTimestamps: true,
              ),
            ),
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'ni',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    final surface = tester.allRenderObjects
        .whereType<RenderTerminalViewport>()
        .last;
    final pointer = TestPointer(77, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(
        surface.localToGlobal(
          Offset(surface.debugCellSize.width, surface.debugCellSize.height / 2),
        ),
      ),
    );
    await tester.pump();

    const belowGraphicKey = Key('terminal-graphic-901');
    const inlineImageKey = Key('terminal-inline-image-0-5');
    const aboveGraphicKey = Key('terminal-graphic-902');
    const timestampKey = Key('terminal-line-timestamp-0');
    const composingKey = Key('terminal-composing-overlay');
    final stackElement = tester
        .elementList(find.byType(Stack))
        .singleWhere(
          (element) =>
              _elementSubtreeContainsKey(element, belowGraphicKey) &&
              _elementSubtreeContainsKey(element, terminalCursorOverlayKey) &&
              _elementSubtreeContainsKey(element, inlineImageKey) &&
              _elementSubtreeContainsKey(element, aboveGraphicKey) &&
              _elementSubtreeContainsKey(element, timestampKey) &&
              _elementSubtreeContainsKey(element, terminalScrollbarTrackKey) &&
              _elementSubtreeContainsKey(element, composingKey) &&
              _elementSubtreeContainsKey(element, terminalLinkTooltipKey),
        );
    final indexes = <int>[
      _directChildIndexContainingKey(stackElement, belowGraphicKey),
      _directChildIndexContainingWidgetTypeName(
        stackElement,
        '_TerminalViewportSurface',
      ),
      _directChildIndexContainingKey(stackElement, terminalCursorOverlayKey),
      _directChildIndexContainingKey(stackElement, inlineImageKey),
      _directChildIndexContainingKey(stackElement, aboveGraphicKey),
      _directChildIndexContainingKey(stackElement, timestampKey),
      _directChildIndexContainingKey(stackElement, terminalScrollbarTrackKey),
      _directChildIndexContainingKey(stackElement, composingKey),
      _directChildIndexContainingKey(stackElement, terminalLinkTooltipKey),
    ];
    expect(indexes, orderedEquals(List<int>.generate(9, (index) => index)));
    expect(_directChildCount(stackElement), 9);
  });
}

TerminalCursorVisualKey _terminalCursorVisualKey() {
  return TerminalCursorVisualKey(
    frameVersion: 7,
    cursorRow: 2,
    cursorCol: 3,
    cursorVisible: true,
    cursorShape: TerminalCursorShape.block,
    resolvedForeground: const Color(0xFFE5E7EB),
    resolvedBackground: const Color(0xFF10141A),
    resolvedCursor: const Color(0xFFFFFFFF),
    cellSize: const Size(10, 20),
    devicePixelRatio: 2,
    fontFamily: 'monospace',
    fontFallback: const <String>['Menlo'],
    fontSize: 14,
    lineHeight: 1.2,
    glyphText: '界',
    glyphUsesCustomGeometry: false,
    glyphCustomGeometryKind: 'none',
    glyphColumn: 3,
    glyphColumnSpan: 2,
    glyphPlacementRect: const Rect.fromLTWH(30, 40, 20, 20),
    glyphDrawOffset: const Offset(30, 40),
    glyphScaleX: 1,
    glyphScaleY: 1,
    glyphFontWeight: FontWeight.w700,
    glyphFontStyle: FontStyle.italic,
    glyphDecoration: TextDecoration.underline,
    glyphIsContinuation: false,
    cursorEnabled: true,
    cursorBlinkEnabled: true,
  );
}

List<({String field, TerminalCursorVisualKey key})>
_terminalCursorVisualKeyChanges(TerminalCursorVisualKey key) {
  return <({String field, TerminalCursorVisualKey key})>[
    (field: 'frameVersion', key: key.copyWith(frameVersion: 8)),
    (field: 'cursorRow', key: key.copyWith(cursorRow: 4)),
    (field: 'cursorCol', key: key.copyWith(cursorCol: 5)),
    (field: 'cursorVisible', key: key.copyWith(cursorVisible: false)),
    (
      field: 'cursorShape',
      key: key.copyWith(cursorShape: TerminalCursorShape.beam),
    ),
    (
      field: 'resolvedForeground',
      key: key.copyWith(resolvedForeground: Colors.red),
    ),
    (
      field: 'resolvedBackground',
      key: key.copyWith(resolvedBackground: Colors.blue),
    ),
    (field: 'resolvedCursor', key: key.copyWith(resolvedCursor: Colors.green)),
    (field: 'cellSize', key: key.copyWith(cellSize: const Size(11, 20))),
    (field: 'devicePixelRatio', key: key.copyWith(devicePixelRatio: 1)),
    (field: 'fontFamily', key: key.copyWith(fontFamily: 'Menlo')),
    (
      field: 'fontFallback',
      key: key.copyWith(fontFallback: const <String>['Monaco']),
    ),
    (field: 'fontSize', key: key.copyWith(fontSize: 15)),
    (field: 'lineHeight', key: key.copyWith(lineHeight: 1.4)),
    (field: 'glyphText', key: key.copyWith(glyphText: 'A')),
    (
      field: 'glyphUsesCustomGeometry',
      key: key.copyWith(glyphUsesCustomGeometry: true),
    ),
    (
      field: 'glyphCustomGeometryKind',
      key: key.copyWith(glyphCustomGeometryKind: 'boxDrawingHorizontal'),
    ),
    (field: 'glyphColumn', key: key.copyWith(glyphColumn: 2)),
    (field: 'glyphColumnSpan', key: key.copyWith(glyphColumnSpan: 1)),
    (
      field: 'glyphPlacementRect',
      key: key.copyWith(
        glyphPlacementRect: const Rect.fromLTWH(20, 40, 10, 20),
      ),
    ),
    (
      field: 'glyphDrawOffset',
      key: key.copyWith(glyphDrawOffset: const Offset(20, 40)),
    ),
    (field: 'glyphScaleX', key: key.copyWith(glyphScaleX: 2)),
    (field: 'glyphScaleY', key: key.copyWith(glyphScaleY: 2)),
    (
      field: 'glyphFontWeight',
      key: key.copyWith(glyphFontWeight: FontWeight.w400),
    ),
    (
      field: 'glyphFontStyle',
      key: key.copyWith(glyphFontStyle: FontStyle.normal),
    ),
    (
      field: 'glyphDecoration',
      key: key.copyWith(glyphDecoration: TextDecoration.lineThrough),
    ),
    (
      field: 'glyphIsContinuation',
      key: key.copyWith(glyphIsContinuation: true),
    ),
    (field: 'cursorEnabled', key: key.copyWith(cursorEnabled: false)),
    (field: 'cursorBlinkEnabled', key: key.copyWith(cursorBlinkEnabled: false)),
  ];
}

Future<({Uint8List bytes, Rect cursorRect, Size cellSize, Color? cursorColor})>
_captureTerminalCursorPixels(
  WidgetTester tester, {
  required TerminalCursorExperimentMode mode,
  required double devicePixelRatio,
  required TerminalCursorShape shape,
  required String text,
  List<TerminalStyleRun>? styleRuns,
  TerminalViewportColors colors = TerminalViewportColors.dark,
}) async {
  tester.view.devicePixelRatio = devicePixelRatio;
  tester.view.physicalSize = Size(
    320 * devicePixelRatio,
    96 * devicePixelRatio,
  );
  final boundaryKey = GlobalKey();
  final focusNode = FocusNode(debugLabel: 'terminal-cursor-pixel-test');
  final selectionController = SelectionController();
  final controller = TerminalViewportController()
    ..updateFrame(
      TerminalFrameDiff(
        rows: <TerminalRow>[
          TerminalRow(
            index: 0,
            text: text,
            styleRuns:
                styleRuns ??
                <TerminalStyleRun>[
                  TerminalStyleRun(
                    start: 0,
                    end: text == '界' ? 2 : 1,
                    foreground: const Color(0xFFE5E7EB),
                    background: const Color(0xFF10141A),
                  ),
                ],
          ),
        ],
        cursor: const TerminalCursor(row: 0, col: 0, visible: true),
        viewportRows: 1,
        viewportCols: 8,
        dirtyRanges: const <TerminalDirtyRange>[
          TerminalDirtyRange(start: 0, end: 1),
        ],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
        defaultForeground: const Color(0xFFE5E7EB),
        defaultBackground: const Color(0xFF10141A),
      ),
    );
  final runtime = TerminalRuntimeController(
    backend: _NoopPtyBackend(),
    copyToClipboard: (_) async {},
    readClipboard: () async => '',
    enableSessionPolling: false,
  );
  final inputController = TerminalInputController(
    sessionId: 'cursor-pixel-${mode.name}-${shape.name}',
    runtime: runtime,
    readFrame: () => controller.frame,
    readSelection: () => '',
    copySelection: (_) async {},
    readClipboard: () async => '',
  );

  try {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: TerminalCursorExperimentScope(
          mode: mode,
          child: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: 160,
                height: 48,
                child: TerminalViewport(
                  controller: controller,
                  selectionController: selectionController,
                  inputController: inputController,
                  focusNode: focusNode,
                  onScrollLines: (_) {},
                  onScrollToOffset: (_) {},
                  colors: colors,
                  cursor: TerminalCursorConfig(shape: shape, blink: false),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final renderObject = tester.allRenderObjects
        .whereType<RenderTerminalViewport>()
        .last;
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await _runUiAsync(
      tester,
      () => boundary.toImage(pixelRatio: devicePixelRatio),
    );
    try {
      final byteData = await _runUiAsync(
        tester,
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      if (byteData == null) {
        throw StateError('Failed to read terminal cursor image bytes.');
      }
      return (
        bytes: Uint8List.fromList(byteData.buffer.asUint8List()),
        cursorRect: renderObject.debugCursorRect!,
        cellSize: renderObject.debugCellSize,
        cursorColor: renderObject.debugCursorColor,
      );
    } finally {
      image.dispose();
    }
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    focusNode.dispose();
    selectionController.dispose();
    runtime.dispose();
    controller.dispose();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  }
}

void _expectRectDeviceAligned(
  Rect rect,
  double devicePixelRatio, {
  required String reason,
}) {
  for (final edge in <double>[rect.left, rect.top, rect.right, rect.bottom]) {
    final physical = edge * devicePixelRatio;
    expect(
      physical,
      moreOrLessEquals(physical.roundToDouble(), epsilon: 0.001),
      reason: reason,
    );
  }
}

int _directChildCount(Element parent) {
  var count = 0;
  parent.visitChildElements((_) => count += 1);
  return count;
}

TerminalFrameDiff _emptyGraphicFrame({
  TerminalFrameKind frameKind = TerminalFrameKind.snapshot,
}) {
  return TerminalFrameDiff(
    frameKind: frameKind,
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
  TerminalFrameKind frameKind = TerminalFrameKind.snapshot,
  String text = 'image',
}) {
  return TerminalFrameDiff(
    frameKind: frameKind,
    rows: [TerminalRow(index: 0, text: text)],
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

class _RecordingTerminalGraphicsCache extends TerminalGraphicsCache {
  _RecordingTerminalGraphicsCache() : super(loadAsset: (_) async => null);

  final List<Set<TerminalGraphicAssetKey>> liveKeySets =
      <Set<TerminalGraphicAssetKey>>[];

  @override
  void evictExcept(Set<TerminalGraphicAssetKey> liveKeys) {
    liveKeySets.add(
      Set<TerminalGraphicAssetKey>.unmodifiable(
        Set<TerminalGraphicAssetKey>.of(liveKeys),
      ),
    );
    super.evictExcept(liveKeys);
  }
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
  TerminalSearchHighlightStyle searchHighlightStyle =
      const TerminalSearchHighlightStyle(),
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
            searchHighlightStyle: searchHighlightStyle,
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
  TerminalViewportColors colors = const TerminalViewportColors(
    canvasBackground: Color(0xFF10141A),
    foreground: Color(0xFFE5E7EB),
    cursor: Color(0xFFE5E7EB),
    selection: Color(0x663B82F6),
    scrollbarTrack: Color(0x00000000),
    scrollbarThumb: Color(0x00000000),
  ),
  TerminalSearchHighlightStyle searchHighlightStyle =
      const TerminalSearchHighlightStyle(),
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
      colors: colors,
      searchMatches: searchMatches,
      activeSearchMatchIndex: activeSearchMatchIndex,
      searchHighlightStyle: searchHighlightStyle,
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
    this.searchHighlightStyle = const TerminalSearchHighlightStyle(),
    this.cursorVisible = false,
    this.benchmarkEventSink,
  });

  final TerminalViewportController controller;
  final SelectionController selectionController;
  final TerminalViewportColors colors;
  final List<TerminalSearchMatch> searchMatches;
  final int activeSearchMatchIndex;
  final TerminalSearchHighlightStyle searchHighlightStyle;
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
      searchHighlightStyle: searchHighlightStyle,
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
      ..searchHighlightStyle = searchHighlightStyle
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

String _renderTerminalViewportSource() {
  final candidates = <File>[
    File('lib/src/terminal/render_terminal_viewport.dart'),
    File(
      'packages/ianvs_terminal/lib/src/terminal/render_terminal_viewport.dart',
    ),
  ];
  return candidates
      .singleWhere((candidate) => candidate.existsSync())
      .readAsStringSync();
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
