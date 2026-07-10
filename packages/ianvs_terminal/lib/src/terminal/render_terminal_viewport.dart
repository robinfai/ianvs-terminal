import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../config/terminal_config.dart';
import '../runtime/terminal_benchmarking.dart';
import 'selection_controller.dart';
import 'terminal_models.dart';
import 'terminal_viewport.dart';
import 'terminal_viewport_colors.dart';

enum TerminalGlyphPlacementPolicy {
  baselineLeft,
  boxDrawingHorizontal,
  boxDrawingVertical,
  boxDrawingTopLeftArc,
  boxDrawingTopRightArc,
  boxDrawingBottomLeftArc,
  boxDrawingBottomRightArc,
  powerlineRightArrow,
  powerlineLeftArrow,
  powerlineLeftCap,
  powerlineRightCap,
}

enum TerminalGlyphClass { text, nerdIcon, boxDrawingCustom, powerlineCustom }

class TerminalResolvedStyle {
  const TerminalResolvedStyle({
    required this.start,
    required this.end,
    required this.foreground,
    required this.background,
  });

  final int start;
  final int end;
  final Color foreground;
  final Color? background;
}

class TerminalResolvedCell {
  const TerminalResolvedCell({
    required this.column,
    required this.text,
    required this.foreground,
    required this.background,
    required this.fontWeight,
    required this.glyphClass,
    required this.usesCustomGeometry,
    required this.placementPolicy,
    required this.drawOffset,
    required this.placementRect,
    required this.baselineY,
    required this.glyphBaseline,
    required this.scaleX,
    required this.scaleY,
  });

  final int column;
  final String text;
  final Color foreground;
  final Color? background;
  final FontWeight fontWeight;
  final TerminalGlyphClass glyphClass;
  final bool usesCustomGeometry;
  final TerminalGlyphPlacementPolicy placementPolicy;
  final Offset drawOffset;
  final Rect placementRect;
  final double baselineY;
  final double glyphBaseline;
  final double scaleX;
  final double scaleY;
}

class TerminalResolvedBackgroundSpan {
  const TerminalResolvedBackgroundSpan({
    required this.startColumn,
    required this.endColumn,
    required this.background,
    required this.rect,
  });

  final int startColumn;
  final int endColumn;
  final Color background;
  final Rect rect;
}

class TerminalRowTextMetrics {
  const TerminalRowTextMetrics({
    required this.alphabeticBaseline,
    required this.ascent,
    required this.descent,
    required this.textTopInset,
    required this.textHeight,
  });

  final double alphabeticBaseline;
  final double ascent;
  final double descent;
  final double textTopInset;
  final double textHeight;
}

final TerminalRowTextMetrics terminalFallbackRowTextMetrics =
    TerminalRowTextMetrics(
      alphabeticBaseline: terminalFallbackCellSize.height,
      ascent: terminalFallbackCellSize.height,
      descent: 0,
      textTopInset: 0,
      textHeight: terminalFallbackCellSize.height,
    );

const double _smartCursorContrastRatio = 4.5;
const int _maxGlyphParagraphCacheEntries = 1024;

class RenderTerminalViewport extends RenderBox {
  RenderTerminalViewport({
    required TerminalViewportController controller,
    required SelectionController selectionController,
    required bool cursorVisible,
    required TerminalFontConfig font,
    required TerminalCursorConfig cursor,
    required double devicePixelRatio,
    required TerminalViewportColors colors,
    List<TerminalSearchMatch> searchMatches = const [],
    int activeSearchMatchIndex = -1,
    TerminalSearchHighlightStyle searchHighlightStyle =
        const TerminalSearchHighlightStyle(),
    TerminalBenchmarkEventSink? benchmarkEventSink,
  }) : _controller = controller,
       _selectionController = selectionController,
       _cursorVisible = cursorVisible,
       _font = font,
       _cursor = cursor,
       _devicePixelRatio = devicePixelRatio,
       _colors = colors,
       _searchMatches = searchMatches,
       _activeSearchMatchIndex = activeSearchMatchIndex,
       _searchHighlightStyle = searchHighlightStyle,
       _benchmarkEventSink = benchmarkEventSink {
    _controller.addListener(markNeedsPaint);
    _selectionController.addListener(markNeedsPaint);
  }

  TerminalViewportController _controller;
  SelectionController _selectionController;
  TerminalFontConfig _font;
  TerminalCursorConfig _cursor;
  double _devicePixelRatio;
  bool _cursorVisible = true;
  TerminalViewportColors _colors;
  List<TerminalSearchMatch> _searchMatches;
  int _activeSearchMatchIndex;
  TerminalSearchHighlightStyle _searchHighlightStyle;
  TerminalBenchmarkEventSink? _benchmarkEventSink;
  final Map<int, _CachedRowLayout> _rowLayoutCache = {};
  final Map<int, _CachedGlyphParagraph> _glyphParagraphCache = {};
  final Map<int, _CachedRowVisual> _rowVisualCache = {};
  final Paint _canvasPaint = Paint()..isAntiAlias = false;
  final Paint _rowBackgroundPaint = Paint()..isAntiAlias = false;
  final Paint _selectionPaint = Paint()..isAntiAlias = false;
  final Paint _cursorPaint = Paint()..isAntiAlias = false;
  final Paint _searchFillPaint = Paint()..isAntiAlias = true;
  final Paint _searchBorderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  final Paint _hyperlinkPaint = Paint()..isAntiAlias = true;
  final Paint _customGeometryFillPaint = Paint()..isAntiAlias = false;
  final Paint _customGeometryStrokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.butt
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
  final Set<int> _activeRowIndexesScratch = <int>{};
  final List<String> _debugPaintedRowTextsScratch = <String>[];
  final List<int> _debugRebuiltRowIndexesScratch = <int>[];
  final Map<int, List<TerminalResolvedStyle>> _debugResolvedStyles = {};
  final Map<int, List<TerminalResolvedCell>> _debugResolvedCells = {};
  final Map<int, List<TerminalResolvedBackgroundSpan>> _debugBackgroundSpans =
      {};
  final Map<int, int> _rowPictureBuildCounts = {};
  final List<Rect> _debugHyperlinkUnderlineRects = <Rect>[];
  int _paragraphBuilds = 0;
  Size _cellSize = terminalFallbackCellSize;
  double _cellBaseline = terminalFallbackCellSize.height;
  TerminalRowTextMetrics _rowTextMetrics = terminalFallbackRowTextMetrics;
  final List<Rect> _debugSearchHighlightRects = <Rect>[];
  Rect? _paintedCursorRect;
  Color? _debugCursorColor;
  _MeasuredCellMetrics? _cachedCellMetrics;
  TerminalRowTextMetrics? _cachedMeasuredRowTextMetrics;
  int? _textMetricsSignature;
  int _lastPaintedFrameVersion = -1;
  bool _needsFullRowVisualRebuild = true;
  Rect _localPaintBounds = Rect.zero;

  set controller(TerminalViewportController value) {
    if (identical(value, _controller)) {
      return;
    }
    _controller.removeListener(markNeedsPaint);
    _controller = value;
    _controller.addListener(markNeedsPaint);
    _lastPaintedFrameVersion = -1;
    _needsFullRowVisualRebuild = true;
    markNeedsPaint();
  }

  set selectionController(SelectionController value) {
    if (identical(value, _selectionController)) {
      return;
    }
    _selectionController.removeListener(markNeedsPaint);
    _selectionController = value;
    _selectionController.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) {
      return;
    }
    _devicePixelRatio = value;
    _invalidateVisualCaches();
    markNeedsPaint();
  }

  set font(TerminalFontConfig value) {
    if (_sameFontConfig(value, _font)) {
      return;
    }
    _font = value;
    _invalidateVisualCaches();
    _glyphParagraphCache.clear();
    _cachedCellMetrics = null;
    _cachedMeasuredRowTextMetrics = null;
    _textMetricsSignature = null;
    markNeedsPaint();
  }

  set cursor(TerminalCursorConfig value) {
    if (_cursor.shape == value.shape && _cursor.blink == value.blink) {
      return;
    }
    _cursor = value;
    markNeedsPaint();
  }

  set cursorVisible(bool value) {
    if (_cursorVisible == value) {
      return;
    }
    _cursorVisible = value;
    markNeedsPaint();
  }

  set colors(TerminalViewportColors value) {
    if (value == _colors) {
      return;
    }
    _colors = value;
    _invalidateVisualCaches();
    _glyphParagraphCache.clear();
    markNeedsPaint();
  }

  set searchMatches(List<TerminalSearchMatch> value) {
    if (_sameSearchMatches(value, _searchMatches)) {
      return;
    }
    _searchMatches = value;
    markNeedsPaint();
  }

  set activeSearchMatchIndex(int value) {
    if (value == _activeSearchMatchIndex) {
      return;
    }
    _activeSearchMatchIndex = value;
    markNeedsPaint();
  }

  set searchHighlightStyle(TerminalSearchHighlightStyle value) {
    if (value == _searchHighlightStyle) {
      return;
    }
    _searchHighlightStyle = value;
    markNeedsPaint();
  }

  set benchmarkEventSink(TerminalBenchmarkEventSink? value) {
    _benchmarkEventSink = value;
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void performLayout() {
    size = constraints.biggest.isFinite
        ? constraints.biggest
        : const Size(640, 480);
    _localPaintBounds = Offset.zero & size;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final benchmarkEnabled = _benchmarkEventSink != null;
    final hasNewFrame = _lastPaintedFrameVersion != _controller.frameVersion;
    final paintWatch = benchmarkEnabled ? (Stopwatch()..start()) : null;
    final paragraphBuildsBefore = benchmarkEnabled ? _paragraphBuilds : 0;
    if (hasNewFrame) {
      _activeRowIndexesScratch.clear();
    }
    if (kDebugMode) {
      _debugPaintedRowTextsScratch.clear();
      _debugRebuiltRowIndexesScratch.clear();
      _debugSearchHighlightRects.clear();
      _debugHyperlinkUnderlineRects.clear();
    }
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.clipRect(_localPaintBounds);
    final frame = _controller.frame;
    final canvasBackground = _canvasBackgroundFor(frame);
    _canvasPaint.color = canvasBackground;
    canvas.drawRect(_localPaintBounds, _canvasPaint);

    _syncTextMetrics();
    _controller.updateMeasuredCellSize(_cellSize);
    final selection = _selectionController.selectionForFrame(frame);
    var rowsVisited = 0;
    var pictureDrawCount = 0;
    var rowCacheHits = 0;
    var rowCacheMisses = 0;
    final renderIntent = TerminalRenderIntent.fromFrame(
      frame,
      hasNewFrame: hasNewFrame,
      forceFullRowVisualRebuild: _needsFullRowVisualRebuild,
    );
    if (renderIntent.shiftsRowCache) {
      _shiftRowCaches(renderIntent.rowCacheShift, frame.viewportRows);
    }
    final shouldRebuildAllRows = renderIntent.rebuildAllRows;
    final dirtyRowIndexes = renderIntent.dirtyRowIndexes;
    final searchHighlightsByRow = _searchHighlightsByRow(frame);

    for (final row in frame.rows) {
      if (benchmarkEnabled) {
        rowsVisited += 1;
      }
      if (hasNewFrame) {
        _activeRowIndexesScratch.add(row.index);
      }
      if (kDebugMode) {
        _debugPaintedRowTextsScratch.add(row.text);
      }
      final rowNeedsRebuild =
          shouldRebuildAllRows ||
          dirtyRowIndexes.contains(row.index) ||
          !_rowVisualCache.containsKey(row.index);
      final activeSelection = selection;
      final selectionTouchesRow =
          activeSelection != null &&
          row.index >= activeSelection.startRow &&
          row.index <= activeSelection.endRow;
      final rowLayout = rowNeedsRebuild || selectionTouchesRow
          ? _rowLayoutFor(row, frame)
          : null;
      if (rowNeedsRebuild) {
        _rebuildRowVisual(row: row, rowLayout: rowLayout!);
        if (benchmarkEnabled) {
          rowCacheMisses += 1;
        }
      } else {
        if (benchmarkEnabled) {
          rowCacheHits += 1;
        }
      }
      final rowVisual = _rowVisualCache[row.index];
      final y = row.index * _cellSize.height;
      final backgroundSpans =
          rowVisual?.backgroundSpans ??
          const <TerminalResolvedBackgroundSpan>[];
      for (final span in backgroundSpans) {
        _rowBackgroundPaint.color = span.background;
        canvas.drawRect(span.rect.shift(Offset(0, y)), _rowBackgroundPaint);
      }
      _paintSearchHighlightsForRow(
        canvas,
        searchHighlightsByRow[row.index] ?? const <_SearchHighlightSpan>[],
      );
      if (selectionTouchesRow) {
        final rowCellCount = rowVisual?.cellCount ?? rowLayout?.cellCount ?? 0;
        final selectedStart = _selectionController.isBlockSelection
            ? activeSelection.startCol
            : (row.index == activeSelection.startRow
                  ? activeSelection.startCol
                  : 0);
        final selectedEnd = _selectionController.isBlockSelection
            ? activeSelection.endCol
            : (row.index == activeSelection.endRow
                  ? activeSelection.endCol
                  : rowCellCount);
        final clampedStart = selectedStart.clamp(0, rowCellCount);
        final clampedEnd = selectedEnd.clamp(clampedStart, rowCellCount);
        _selectionPaint.color = _colors.selection;
        canvas.drawRect(
          Rect.fromLTWH(
            clampedStart * _cellSize.width,
            y,
            (clampedEnd - clampedStart) * _cellSize.width,
            _cellSize.height,
          ),
          _selectionPaint,
        );
      }
      if (rowVisual != null) {
        canvas.save();
        canvas.translate(0, y);
        canvas.drawPicture(rowVisual.picture);
        canvas.restore();
        if (benchmarkEnabled) {
          pictureDrawCount += 1;
        }
      }
      _paintHyperlinkUnderlinesForRow(canvas, frame, row.index, y);
    }
    if (hasNewFrame) {
      _pruneInactiveRowCaches(_activeRowIndexesScratch);
      _lastPaintedFrameVersion = _controller.frameVersion;
    }
    _needsFullRowVisualRebuild = false;

    if (frame.cursor.visible && _cursorVisible) {
      final cursorRect = _cursorRect(frame.cursor);
      final cursorColor = _cursorPaintColorFor(frame);
      _paintedCursorRect = cursorRect;
      if (kDebugMode) {
        _debugCursorColor = cursorColor;
      }
      _cursorPaint.color = cursorColor;
      canvas.drawRect(cursorRect, _cursorPaint);
      if (_cursor.shape == TerminalCursorShape.block) {
        _paintCursorText(canvas, frame, frame.cursor, cursorColor);
      }
    } else {
      _paintedCursorRect = null;
      if (kDebugMode) {
        _debugCursorColor = null;
      }
    }
    canvas.restore();
    paintWatch?.stop();
    _emitBenchmarkPaintEvent(
      frame: frame,
      renderIntent: renderIntent,
      hasNewFrame: hasNewFrame,
      rowsVisited: rowsVisited,
      pictureDrawCount: pictureDrawCount,
      rowCacheHits: rowCacheHits,
      rowCacheMisses: rowCacheMisses,
      paragraphBuildCount: _paragraphBuilds - paragraphBuildsBefore,
      paintMicros: paintWatch?.elapsedMicroseconds ?? 0,
    );
  }

  void _emitBenchmarkPaintEvent({
    required TerminalFrameDiff frame,
    required TerminalRenderIntent renderIntent,
    required bool hasNewFrame,
    required int rowsVisited,
    required int pictureDrawCount,
    required int rowCacheHits,
    required int rowCacheMisses,
    required int paragraphBuildCount,
    required int paintMicros,
  }) {
    final sink = _benchmarkEventSink;
    if (sink == null) {
      return;
    }
    sink(<String, Object?>{
      'schema_version': 'ianvs-bench-flutter-render-v1',
      'timestamp_micros': DateTime.now().microsecondsSinceEpoch,
      'session_id': 'render',
      'frame_version': _controller.frameVersion,
      'frame_kind': frame.frameKind.name,
      'paint_kind': hasNewFrame ? 'frame' : 'non_frame',
      'has_new_frame': hasNewFrame,
      'viewport_row_shift': frame.viewportRowShift,
      'viewport_rows': frame.viewportRows,
      'dirty_row_count': _benchmarkDirtyRowCount(
        frame,
        renderIntent,
        hasNewFrame: hasNewFrame,
      ),
      'rows_visited': rowsVisited,
      'picture_draw_count': pictureDrawCount,
      'row_visual_rebuild_count': rowCacheMisses,
      'row_cache_hits': rowCacheHits,
      'row_cache_misses': rowCacheMisses,
      'paragraph_build_count': paragraphBuildCount,
      'paint_micros': paintMicros,
      'debug_collection_enabled': kDebugMode,
    });
  }

  TerminalCellPosition debugCellForOffset(Offset offset) =>
      _cellForOffset(offset);
  Size get debugCellSize => _cellSize;
  double get debugCellBaseline => _cellBaseline;
  TerminalRowTextMetrics get debugRowTextMetrics => _rowTextMetrics;
  int get debugParagraphBuilds => _paragraphBuilds;
  int get debugGlyphParagraphCacheSize => _glyphParagraphCache.length;
  List<String> get debugLastPaintedRowTexts =>
      List<String>.unmodifiable(_debugPaintedRowTextsScratch);
  List<int> get debugLastRebuiltRowIndexes =>
      List<int>.unmodifiable(_debugRebuiltRowIndexesScratch);
  List<Rect> get debugSearchHighlightRects =>
      List<Rect>.unmodifiable(_debugSearchHighlightRects);
  List<Rect> get debugHyperlinkUnderlineRects =>
      List<Rect>.unmodifiable(_debugHyperlinkUnderlineRects);
  bool get debugCursorVisible {
    final frame = _controller.frame;
    return frame.cursor.visible && _cursorVisible;
  }

  Color? get debugCursorColor => _debugCursorColor;
  Color get debugCanvasBackground => _canvasBackgroundFor(_controller.frame);

  int debugRowPictureBuildsForRow(int row) => _rowPictureBuildCounts[row] ?? 0;

  List<TerminalResolvedStyle> debugResolvedStylesForRow(int row) =>
      List<TerminalResolvedStyle>.unmodifiable(
        _debugResolvedStyles[row] ?? const <TerminalResolvedStyle>[],
      );

  List<TerminalResolvedCell> debugResolvedCellsForRow(int row) =>
      List<TerminalResolvedCell>.unmodifiable(
        (_debugResolvedCells[row] ?? const <TerminalResolvedCell>[]).map(
          (cell) =>
              _resolvedCellWithAbsoluteRowOffset(cell, row * _cellSize.height),
        ),
      );

  List<TerminalResolvedBackgroundSpan> debugBackgroundSpansForRow(int row) =>
      List<TerminalResolvedBackgroundSpan>.unmodifiable(
        (_debugBackgroundSpans[row] ?? const <TerminalResolvedBackgroundSpan>[])
            .map(
              (span) => _backgroundSpanWithAbsoluteRowOffset(
                span,
                row * _cellSize.height,
              ),
            ),
      );

  Rect? get debugCursorRect => _paintedCursorRect;
  Rect? get debugCaretCellRect {
    final frame = _controller.frame;
    final cursor = frame.cursor;
    if (!cursor.visible ||
        frame.viewportRows <= 0 ||
        frame.viewportCols <= 0 ||
        cursor.row < 0 ||
        cursor.col < 0 ||
        cursor.row >= frame.viewportRows ||
        cursor.col >= frame.viewportCols) {
      return null;
    }
    return _cursorBlockRect(cursor);
  }

  TerminalViewportColors get debugColors => _colors;

  void _invalidateVisualCaches() {
    for (final rowVisual in _rowVisualCache.values) {
      rowVisual.picture.dispose();
    }
    _rowVisualCache.clear();
    _rowLayoutCache.clear();
    if (kDebugMode) {
      _debugResolvedStyles.clear();
      _debugResolvedCells.clear();
      _debugBackgroundSpans.clear();
      _debugRebuiltRowIndexesScratch.clear();
      _rowPictureBuildCounts.clear();
    }
    _needsFullRowVisualRebuild = true;
  }

  void _shiftRowCaches(int rowShift, int viewportRows) {
    if (rowShift == 0 || viewportRows <= 0) {
      return;
    }
    _shiftIndexedCache<_CachedRowVisual>(
      _rowVisualCache,
      rowShift,
      viewportRows,
      onDrop: (rowVisual) => rowVisual.picture.dispose(),
    );
    _shiftIndexedCache<_CachedRowLayout>(
      _rowLayoutCache,
      rowShift,
      viewportRows,
    );
    if (kDebugMode) {
      _shiftIndexedCache<List<TerminalResolvedStyle>>(
        _debugResolvedStyles,
        rowShift,
        viewportRows,
      );
      _shiftIndexedCache<List<TerminalResolvedCell>>(
        _debugResolvedCells,
        rowShift,
        viewportRows,
      );
      _shiftIndexedCache<List<TerminalResolvedBackgroundSpan>>(
        _debugBackgroundSpans,
        rowShift,
        viewportRows,
      );
      _shiftIndexedCache<int>(_rowPictureBuildCounts, rowShift, viewportRows);
    }
  }

  Map<int, List<_SearchHighlightSpan>> _searchHighlightsByRow(
    TerminalFrameDiff frame,
  ) {
    if (_searchMatches.isEmpty ||
        frame.viewportRows <= 0 ||
        frame.viewportCols <= 0 ||
        _cellSize.width <= 0 ||
        _cellSize.height <= 0) {
      return const <int, List<_SearchHighlightSpan>>{};
    }

    final highlightsByRow = <int, List<_SearchHighlightSpan>>{};
    for (var index = 0; index < _searchMatches.length; index += 1) {
      final match = _searchMatches[index];
      if (match.startCol < 0 ||
          match.endCol <= match.startCol ||
          match.text.isEmpty) {
        continue;
      }
      final relativeRow = match.row - frame.viewportStartRow;
      if (relativeRow < 0 || relativeRow >= frame.viewportRows) {
        continue;
      }
      final startCol = match.startCol.clamp(0, frame.viewportCols).toInt();
      if (startCol >= frame.viewportCols) {
        continue;
      }
      final endCol = match.endCol
          .clamp(startCol + 1, frame.viewportCols)
          .toInt();
      if (endCol <= startCol) {
        continue;
      }
      final rect = _snapRect(
        Rect.fromLTWH(
          startCol * _cellSize.width,
          relativeRow * _cellSize.height,
          (endCol - startCol) * _cellSize.width,
          _cellSize.height,
        ),
      );
      highlightsByRow
          .putIfAbsent(relativeRow, () => <_SearchHighlightSpan>[])
          .add(_SearchHighlightSpan(index: index, rect: rect));
    }
    return highlightsByRow;
  }

  void _paintSearchHighlightsForRow(
    Canvas canvas,
    List<_SearchHighlightSpan> highlights,
  ) {
    if (highlights.isEmpty) {
      return;
    }
    final style = _searchHighlightStyle;
    final radiusValue = style.radius.isFinite
        ? math.max(0.0, style.radius)
        : 0.0;
    final radius = Radius.circular(radiusValue);
    for (final highlight in highlights) {
      final isActive = highlight.index == _activeSearchMatchIndex;
      final rrect = RRect.fromRectAndRadius(highlight.rect, radius);
      if (kDebugMode) {
        _debugSearchHighlightRects.add(highlight.rect);
      }
      _searchFillPaint.color = isActive ? style.activeFill : style.inactiveFill;
      canvas.drawRRect(rrect, _searchFillPaint);
      if (isActive) {
        _searchBorderPaint
          ..color = style.activeBorder
          ..strokeWidth = _snapLogical(1);
        canvas.drawRRect(rrect, _searchBorderPaint);
      }
    }
  }

  void _paintHyperlinkUnderlinesForRow(
    Canvas canvas,
    TerminalFrameDiff frame,
    int rowIndex,
    double rowY,
  ) {
    if (frame.hyperlinks.isEmpty ||
        frame.viewportCols <= 0 ||
        _cellSize.width <= 0 ||
        _cellSize.height <= 0) {
      return;
    }
    final color = _foregroundWithMinimumContrast(
      frame.defaultForeground ?? _colors.foreground,
      _canvasBackgroundFor(frame),
    ).withValues(alpha: 0.82);
    final devicePixelRatio = _devicePixelRatio.isFinite && _devicePixelRatio > 0
        ? _devicePixelRatio
        : 1.0;
    final strokeWidth = _snapLogical(math.max(1.0 / devicePixelRatio, 1.0));
    final underlineY = _snapLogicalY(
      rowY +
          math.min(
            _cellSize.height - strokeWidth,
            _rowTextMetrics.alphabeticBaseline +
                math.max(1.0, _rowTextMetrics.descent * 0.35),
          ),
    );
    final dashLength = math.max(2.0, _cellSize.width * 0.48);
    final gapLength = math.max(2.0, _cellSize.width * 0.28);
    _hyperlinkPaint
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    for (final hyperlink in frame.hyperlinks) {
      if (hyperlink.row != rowIndex) {
        continue;
      }
      final startCol = hyperlink.startCol.clamp(0, frame.viewportCols).toInt();
      final endCol = hyperlink.endCol
          .clamp(startCol, frame.viewportCols)
          .toInt();
      if (endCol <= startCol) {
        continue;
      }
      final left = _snapLogicalX(startCol * _cellSize.width);
      final right = _snapLogicalX(endCol * _cellSize.width);
      if (kDebugMode) {
        _debugHyperlinkUnderlineRects.add(
          Rect.fromLTRB(
            left,
            underlineY - strokeWidth / 2,
            right,
            underlineY + strokeWidth / 2,
          ),
        );
      }
      var x = left;
      while (x < right) {
        final dashEnd = math.min(right, x + dashLength);
        canvas.drawLine(
          Offset(x, underlineY),
          Offset(dashEnd, underlineY),
          _hyperlinkPaint,
        );
        x += dashLength + gapLength;
      }
    }
  }

  _CachedRowLayout _rowLayoutFor(TerminalRow row, TerminalFrameDiff frame) {
    final signature = Object.hashAll([
      row.text,
      _colors.foreground.toARGB32(),
      _canvasBackgroundFor(frame).toARGB32(),
      _colors.minimumContrastRatio,
      frame.defaultForeground?.toARGB32(),
      frame.defaultBackground?.toARGB32(),
      for (final entry in row.styleRuns)
        Object.hash(
          entry.start,
          entry.end,
          entry.foreground,
          entry.background,
          entry.bold,
          entry.dim,
          entry.italic,
          entry.underline,
          entry.blink,
          entry.inverse,
        ),
    ]);
    final cached = _rowLayoutCache[row.index];
    if (cached != null && cached.signature == signature) {
      return cached;
    }

    final textCells = TerminalTextCells.fromText(row.text);
    final canvasBackground = _canvasBackgroundFor(frame);
    final defaultRawForeground = frame.defaultForeground ?? _colors.foreground;
    final defaultForeground = _foregroundWithMinimumContrast(
      defaultRawForeground,
      canvasBackground,
    );
    final cellStyles = List<_ResolvedCellStyle>.filled(
      textCells.cellCount,
      _ResolvedCellStyle(
        rawForeground: defaultRawForeground,
        foreground: defaultForeground,
        background: null,
        fontWeight: FontWeight.w400,
        fontStyle: FontStyle.normal,
        decoration: TextDecoration.none,
      ),
    );
    final resolvedStyles = kDebugMode ? <TerminalResolvedStyle>[] : null;
    for (final run in row.styleRuns) {
      if (run.start < 0 || run.end <= run.start) {
        continue;
      }
      final start = textCells.clampColumn(run.start);
      final end = run.end.clamp(start, textCells.cellCount).toInt();
      if (start >= end) {
        continue;
      }
      final resolvedStyle = _resolvedCellStyleFor(
        run,
        defaultForeground: defaultRawForeground,
        defaultBackground: frame.defaultBackground,
        canvasBackground: canvasBackground,
      );
      resolvedStyles?.add(
        TerminalResolvedStyle(
          start: start,
          end: end,
          foreground: resolvedStyle.foreground,
          background: resolvedStyle.background,
        ),
      );
      for (var column = start; column < end; column += 1) {
        cellStyles[column] = resolvedStyle;
      }
    }

    final cells = <_PaintCell>[];
    for (final textCell in textCells.cells) {
      final style = cellStyles[textCell.column];
      final glyph = textCell.text;
      final placementPolicy = _placementPolicyForGlyph(glyph);
      final glyphClass = _glyphClassForGlyph(glyph, placementPolicy);
      final foreground = glyphClass == TerminalGlyphClass.powerlineCustom
          ? style.rawForeground
          : style.foreground;
      final usesCustomGeometry = _usesCustomGeometryFor(placementPolicy);
      ui.Paragraph? paragraph;
      Size glyphSize = Size.zero;
      double alphabeticBaseline = 0;
      if (!usesCustomGeometry &&
          (glyph.trim().isNotEmpty ||
              style.decoration != TextDecoration.none)) {
        final glyphParagraph = _glyphParagraphFor(glyph, style);
        paragraph = glyphParagraph.paragraph;
        glyphSize = glyphParagraph.size;
        alphabeticBaseline = glyphParagraph.alphabeticBaseline;
      }
      cells.add(
        _PaintCell(
          column: textCell.column,
          columnSpan: textCell.columnSpan,
          text: glyph,
          foreground: foreground,
          background: style.background,
          fontWeight: style.fontWeight,
          fontStyle: style.fontStyle,
          decoration: style.decoration,
          glyphClass: glyphClass,
          paragraph: paragraph,
          glyphSize: glyphSize,
          alphabeticBaseline: alphabeticBaseline,
          usesCustomGeometry: usesCustomGeometry,
          placementPolicy: placementPolicy,
          isContinuation: textCell.isContinuation,
        ),
      );
    }

    final rowLayout = _CachedRowLayout(
      signature: signature,
      cellCount: textCells.cellCount,
      cells: cells,
    );
    _rowLayoutCache[row.index] = rowLayout;
    if (kDebugMode) {
      _debugResolvedStyles[row.index] = resolvedStyles!;
    }
    _paragraphBuilds += 1;
    return rowLayout;
  }

  void _syncTextMetrics() {
    final signature = Object.hash(
      _font.family,
      Object.hashAll(_font.fallback),
      _font.size,
      _font.lineHeight,
      _devicePixelRatio,
    );
    if (_textMetricsSignature != signature ||
        _cachedCellMetrics == null ||
        _cachedMeasuredRowTextMetrics == null) {
      _cachedCellMetrics = _measureCellMetrics();
      _cachedMeasuredRowTextMetrics = _measureRowTextMetrics();
      _textMetricsSignature = signature;
    }
    _cellSize = _cachedCellMetrics!.size;
    _cellBaseline = _cachedCellMetrics!.alphabeticBaseline;
    _rowTextMetrics = _cachedMeasuredRowTextMetrics!;
  }

  void _rebuildRowVisual({
    required TerminalRow row,
    required _CachedRowLayout rowLayout,
  }) {
    const rowY = 0.0;
    final backgroundSpans = _backgroundSpansForCells(rowLayout.cells, rowY);
    final debugCells = kDebugMode ? <TerminalResolvedCell>[] : null;
    final recorder = ui.PictureRecorder();
    final pictureCanvas = Canvas(recorder);

    for (final cell in rowLayout.cells) {
      if (cell.isContinuation) {
        continue;
      }
      final placement = _placementForCell(cell, rowY);
      final paragraph = cell.paragraph;
      if (cell.usesCustomGeometry) {
        _paintCustomGeometry(pictureCanvas, cell, placement.rect);
      } else if (paragraph != null) {
        pictureCanvas.save();
        pictureCanvas.translate(
          placement.drawOffset.dx,
          placement.drawOffset.dy,
        );
        if (placement.scaleX != 1 || placement.scaleY != 1) {
          pictureCanvas.scale(placement.scaleX, placement.scaleY);
        }
        pictureCanvas.drawParagraph(paragraph, Offset.zero);
        pictureCanvas.restore();
      }
      debugCells?.add(
        TerminalResolvedCell(
          column: cell.column,
          text: cell.text,
          foreground: cell.foreground,
          background: cell.background,
          fontWeight: cell.fontWeight,
          glyphClass: cell.glyphClass,
          usesCustomGeometry: cell.usesCustomGeometry,
          placementPolicy: cell.placementPolicy,
          drawOffset: placement.drawOffset,
          placementRect: placement.rect,
          baselineY: placement.baselineY,
          glyphBaseline: cell.alphabeticBaseline,
          scaleX: placement.scaleX,
          scaleY: placement.scaleY,
        ),
      );
    }

    _rowVisualCache.remove(row.index)?.picture.dispose();
    _rowVisualCache[row.index] = _CachedRowVisual(
      signature: rowLayout.signature,
      picture: recorder.endRecording(),
      cellCount: rowLayout.cellCount,
      backgroundSpans: backgroundSpans,
    );
    if (kDebugMode) {
      _debugResolvedCells[row.index] = debugCells!;
      _debugBackgroundSpans[row.index] = backgroundSpans;
      _rowPictureBuildCounts[row.index] =
          (_rowPictureBuildCounts[row.index] ?? 0) + 1;
      _debugRebuiltRowIndexesScratch.add(row.index);
    }
  }

  TerminalResolvedCell _resolvedCellWithAbsoluteRowOffset(
    TerminalResolvedCell cell,
    double rowOffset,
  ) {
    return TerminalResolvedCell(
      column: cell.column,
      text: cell.text,
      foreground: cell.foreground,
      background: cell.background,
      fontWeight: cell.fontWeight,
      glyphClass: cell.glyphClass,
      usesCustomGeometry: cell.usesCustomGeometry,
      placementPolicy: cell.placementPolicy,
      drawOffset: cell.drawOffset.translate(0, rowOffset),
      placementRect: cell.placementRect.shift(Offset(0, rowOffset)),
      baselineY: cell.baselineY + rowOffset,
      glyphBaseline: cell.glyphBaseline,
      scaleX: cell.scaleX,
      scaleY: cell.scaleY,
    );
  }

  TerminalResolvedBackgroundSpan _backgroundSpanWithAbsoluteRowOffset(
    TerminalResolvedBackgroundSpan span,
    double rowOffset,
  ) {
    return TerminalResolvedBackgroundSpan(
      startColumn: span.startColumn,
      endColumn: span.endColumn,
      background: span.background,
      rect: span.rect.shift(Offset(0, rowOffset)),
    );
  }

  void _pruneInactiveRowCaches(Set<int> activeRowIndexes) {
    _rowVisualCache.removeWhere((key, rowVisual) {
      if (activeRowIndexes.contains(key)) {
        return false;
      }
      rowVisual.picture.dispose();
      return true;
    });
    _rowLayoutCache.removeWhere((key, _) => !activeRowIndexes.contains(key));
    if (kDebugMode) {
      _debugResolvedStyles.removeWhere(
        (key, _) => !activeRowIndexes.contains(key),
      );
      _debugResolvedCells.removeWhere(
        (key, _) => !activeRowIndexes.contains(key),
      );
      _debugBackgroundSpans.removeWhere(
        (key, _) => !activeRowIndexes.contains(key),
      );
      _rowPictureBuildCounts.removeWhere(
        (key, _) => !activeRowIndexes.contains(key),
      );
    }
  }

  void _shiftIndexedCache<T>(
    Map<int, T> cache,
    int rowShift,
    int viewportRows, {
    void Function(T value)? onDrop,
  }) {
    if (cache.isEmpty) {
      return;
    }
    final shifted = <int, T>{};
    for (final entry in cache.entries) {
      final nextRow = entry.key + rowShift;
      if (nextRow < 0 || nextRow >= viewportRows) {
        onDrop?.call(entry.value);
        continue;
      }
      shifted[nextRow] = entry.value;
    }
    cache
      ..clear()
      ..addAll(shifted);
  }

  TerminalGlyphPlacementPolicy _placementPolicyForGlyph(String glyph) {
    return switch (glyph) {
      '─' => TerminalGlyphPlacementPolicy.boxDrawingHorizontal,
      '│' => TerminalGlyphPlacementPolicy.boxDrawingVertical,
      '╭' => TerminalGlyphPlacementPolicy.boxDrawingTopLeftArc,
      '╮' => TerminalGlyphPlacementPolicy.boxDrawingTopRightArc,
      '╰' => TerminalGlyphPlacementPolicy.boxDrawingBottomLeftArc,
      '╯' => TerminalGlyphPlacementPolicy.boxDrawingBottomRightArc,
      '' => TerminalGlyphPlacementPolicy.powerlineRightArrow,
      '' => TerminalGlyphPlacementPolicy.powerlineLeftArrow,
      '' => TerminalGlyphPlacementPolicy.powerlineLeftCap,
      '' => TerminalGlyphPlacementPolicy.powerlineRightCap,
      _ => TerminalGlyphPlacementPolicy.baselineLeft,
    };
  }

  bool _usesCustomGeometryFor(TerminalGlyphPlacementPolicy placementPolicy) {
    return placementPolicy != TerminalGlyphPlacementPolicy.baselineLeft;
  }

  TerminalGlyphClass _glyphClassForGlyph(
    String glyph,
    TerminalGlyphPlacementPolicy placementPolicy,
  ) {
    switch (placementPolicy) {
      case TerminalGlyphPlacementPolicy.boxDrawingHorizontal:
      case TerminalGlyphPlacementPolicy.boxDrawingVertical:
      case TerminalGlyphPlacementPolicy.boxDrawingTopLeftArc:
      case TerminalGlyphPlacementPolicy.boxDrawingTopRightArc:
      case TerminalGlyphPlacementPolicy.boxDrawingBottomLeftArc:
      case TerminalGlyphPlacementPolicy.boxDrawingBottomRightArc:
        return TerminalGlyphClass.boxDrawingCustom;
      case TerminalGlyphPlacementPolicy.powerlineRightArrow:
      case TerminalGlyphPlacementPolicy.powerlineLeftArrow:
      case TerminalGlyphPlacementPolicy.powerlineLeftCap:
      case TerminalGlyphPlacementPolicy.powerlineRightCap:
        return TerminalGlyphClass.powerlineCustom;
      case TerminalGlyphPlacementPolicy.baselineLeft:
        break;
    }
    return _isNerdFontGlyph(glyph)
        ? TerminalGlyphClass.nerdIcon
        : TerminalGlyphClass.text;
  }

  bool _isNerdFontGlyph(String glyph) {
    if (glyph.isEmpty) {
      return false;
    }
    final codePoint = glyph.runes.first;
    return (codePoint >= 0xE000 && codePoint <= 0xF8FF) ||
        (codePoint >= 0xF0000 && codePoint <= 0xFFFFD) ||
        (codePoint >= 0x100000 && codePoint <= 0x10FFFD);
  }

  _ResolvedCellStyle _resolvedCellStyleFor(
    TerminalStyleRun run, {
    required Color defaultForeground,
    required Color? defaultBackground,
    required Color canvasBackground,
  }) {
    var rawForeground = run.foreground ?? defaultForeground;
    var background = run.background ?? defaultBackground ?? canvasBackground;
    var paintBackground =
        run.inverse ||
        (run.background != null &&
            !_isDefaultLikeBackground(
              background,
              defaultBackground,
              canvasBackground,
            ));

    if (run.inverse) {
      final swapped = background;
      background = rawForeground;
      rawForeground = swapped;
      paintBackground = true;
    }
    final contrastBackground = paintBackground ? background : canvasBackground;
    if (run.dim) {
      rawForeground = Color.alphaBlend(
        rawForeground.withValues(alpha: rawForeground.a * 0.65),
        contrastBackground,
      );
    }
    final foreground = _foregroundWithMinimumContrast(
      rawForeground,
      contrastBackground,
    );

    return _ResolvedCellStyle(
      rawForeground: rawForeground,
      foreground: foreground,
      background: paintBackground ? background : null,
      fontWeight: run.bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: run.italic ? FontStyle.italic : FontStyle.normal,
      decoration: run.underline
          ? TextDecoration.underline
          : TextDecoration.none,
    );
  }

  bool _isDefaultLikeBackground(
    Color background,
    Color? backendDefaultBackground,
    Color canvasBackground,
  ) {
    final backgroundValue = background.toARGB32();
    return backgroundValue == canvasBackground.toARGB32() ||
        backgroundValue == backendDefaultBackground?.toARGB32();
  }

  Color _canvasBackgroundFor(TerminalFrameDiff frame) {
    return frame.defaultBackground ?? _colors.canvasBackground;
  }

  Color _foregroundWithMinimumContrast(Color foreground, Color background) {
    return _foregroundWithContrastRatio(
      foreground,
      background,
      _minimumContrastRatio,
    );
  }

  Color _cursorPaintColorFor(TerminalFrameDiff frame) {
    final cursorColor = frame.cursorColor ?? _colors.cursor;
    if (!_colors.smartCursorColor) {
      return cursorColor;
    }
    final background = _cursorBackgroundFor(frame);
    return _foregroundWithContrastRatio(
      cursorColor,
      background,
      math.max(_minimumContrastRatio, _smartCursorContrastRatio),
    );
  }

  void _paintCursorText(
    Canvas canvas,
    TerminalFrameDiff frame,
    TerminalCursor cursor,
    Color cursorColor,
  ) {
    final cell = _cursorCellFor(cursor);
    if (cell == null || cell.isContinuation || cell.text.isEmpty) {
      return;
    }

    final foreground = _cursorTextColorFor(frame, cursorColor);
    final placement = _placementForCell(cell, cursor.row * _cellSize.height);
    canvas.save();
    canvas.clipRect(_cursorBlockRect(cursor));
    if (cell.usesCustomGeometry) {
      _paintCustomGeometry(
        canvas,
        cell,
        placement.rect,
        foreground: foreground,
      );
    } else {
      final paragraph = _glyphParagraphFor(
        cell.text,
        _ResolvedCellStyle(
          rawForeground: foreground,
          foreground: foreground,
          background: cell.background,
          fontWeight: cell.fontWeight,
          fontStyle: cell.fontStyle,
          decoration: cell.decoration,
        ),
      ).paragraph;
      canvas.save();
      canvas.translate(placement.drawOffset.dx, placement.drawOffset.dy);
      if (placement.scaleX != 1 || placement.scaleY != 1) {
        canvas.scale(placement.scaleX, placement.scaleY);
      }
      canvas.drawParagraph(paragraph, Offset.zero);
      canvas.restore();
    }
    canvas.restore();
  }

  Color _cursorTextColorFor(TerminalFrameDiff frame, Color cursorColor) {
    return _foregroundWithContrastRatio(
      _cursorBackgroundFor(frame),
      cursorColor,
      math.max(_minimumContrastRatio, _smartCursorContrastRatio),
    );
  }

  Color _cursorBackgroundFor(TerminalFrameDiff frame) {
    final cursor = frame.cursor;
    return _cursorCellFor(cursor)?.background ?? _canvasBackgroundFor(frame);
  }

  double get _minimumContrastRatio {
    final ratio = _colors.minimumContrastRatio;
    return ratio.isFinite ? ratio.clamp(1.0, 21.0).toDouble() : 1.0;
  }

  Color _foregroundWithContrastRatio(
    Color foreground,
    Color background,
    double ratio,
  ) {
    final targetRatio = ratio.isFinite
        ? ratio.clamp(1.0, 21.0).toDouble()
        : 1.0;
    if (targetRatio <= 1 ||
        _contrastRatio(foreground, background) >= targetRatio) {
      return foreground;
    }

    const black = Color(0xFF000000);
    const white = Color(0xFFFFFFFF);
    final target =
        _contrastRatio(black, background) >= _contrastRatio(white, background)
        ? black
        : white;
    var low = 0.0;
    var high = 1.0;
    var best = target;
    for (var step = 0; step < 16; step += 1) {
      final midpoint = (low + high) / 2;
      final candidate = Color.lerp(foreground, target, midpoint)!;
      if (_contrastRatio(candidate, background) >= targetRatio) {
        best = candidate;
        high = midpoint;
      } else {
        low = midpoint;
      }
    }
    return best;
  }

  double _contrastRatio(Color foreground, Color background) {
    final effectiveForeground = _opaqueColorOnBackground(
      foreground,
      background,
    );
    final foregroundLuminance = _relativeLuminance(effectiveForeground);
    final backgroundLuminance = _relativeLuminance(background);
    final lighter = math.max(foregroundLuminance, backgroundLuminance);
    final darker = math.min(foregroundLuminance, backgroundLuminance);
    return (lighter + 0.05) / (darker + 0.05);
  }

  Color _opaqueColorOnBackground(Color color, Color background) {
    if (color.a >= 1) {
      return color;
    }
    return Color.alphaBlend(color, background);
  }

  double _relativeLuminance(Color color) {
    return 0.2126 * _linearizedColorComponent(color.r) +
        0.7152 * _linearizedColorComponent(color.g) +
        0.0722 * _linearizedColorComponent(color.b);
  }

  double _linearizedColorComponent(double component) {
    if (component <= 0.03928) {
      return component / 12.92;
    }
    return math.pow((component + 0.055) / 1.055, 2.4).toDouble();
  }

  _CachedGlyphParagraph _glyphParagraphFor(
    String text,
    _ResolvedCellStyle style,
  ) {
    final signature = Object.hash(
      text,
      style.foreground.toARGB32(),
      _font.family,
      Object.hashAll(_font.fallback),
      _font.size,
      _font.lineHeight,
      style.fontWeight,
      style.fontStyle,
      style.decoration,
    );
    final cached = _glyphParagraphCache.remove(signature);
    if (cached != null) {
      _glyphParagraphCache[signature] = cached;
      return cached;
    }
    final builder = ui.ParagraphBuilder(_paragraphStyle())
      ..pushStyle(
        _textStyle(
          color: style.foreground,
          fontWeight: style.fontWeight,
          fontStyle: style.fontStyle,
          decoration: style.decoration,
        ),
      )
      ..addText(text)
      ..pop();
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: math.max(size.width, 100000.0)));
    final glyphParagraph = _CachedGlyphParagraph(
      paragraph: paragraph,
      size: Size(paragraph.maxIntrinsicWidth, paragraph.height),
      alphabeticBaseline: paragraph.alphabeticBaseline,
    );
    _cacheGlyphParagraph(signature, glyphParagraph);
    return glyphParagraph;
  }

  void _cacheGlyphParagraph(
    int signature,
    _CachedGlyphParagraph glyphParagraph,
  ) {
    _glyphParagraphCache[signature] = glyphParagraph;
    while (_glyphParagraphCache.length > _maxGlyphParagraphCacheEntries) {
      _glyphParagraphCache.remove(_glyphParagraphCache.keys.first);
    }
  }

  _MeasuredCellMetrics _measureCellMetrics() {
    final builder = ui.ParagraphBuilder(_paragraphStyle())
      ..pushStyle(_textStyle())
      ..addText('W')
      ..pop();
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
    return _MeasuredCellMetrics(
      size: Size(paragraph.maxIntrinsicWidth, paragraph.height),
      alphabeticBaseline: paragraph.alphabeticBaseline,
    );
  }

  TerminalRowTextMetrics _measureRowTextMetrics() {
    final builder = ui.ParagraphBuilder(_paragraphStyle())
      ..pushStyle(_textStyle())
      ..addText('Hg')
      ..pop();
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
    final lineMetrics = paragraph.computeLineMetrics();
    final line = lineMetrics.isNotEmpty ? lineMetrics.first : null;
    if (line == null) {
      return terminalFallbackRowTextMetrics;
    }
    return TerminalRowTextMetrics(
      alphabeticBaseline: paragraph.alphabeticBaseline,
      ascent: line.ascent,
      descent: line.descent,
      textTopInset: paragraph.alphabeticBaseline - line.ascent,
      textHeight: line.ascent + line.descent,
    );
  }

  _PlacedCell _placementForCell(_PaintCell cell, double rowY) {
    final cellLeft = cell.column * _cellSize.width;
    final cellRight = cellLeft + (cell.columnSpan * _cellSize.width);
    final targetBaselineY = _snapLogicalY(
      rowY +
          ((_cellSize.height - _rowTextMetrics.textHeight) / 2) +
          _rowTextMetrics.ascent,
    );
    final horizontalBleed = math.min(_cellSize.width * 0.10, 1.0);
    final capBleed = horizontalBleed * 0.5;

    if (cell.usesCustomGeometry) {
      final rect = _snapRect(switch (cell.placementPolicy) {
        TerminalGlyphPlacementPolicy.boxDrawingHorizontal ||
        TerminalGlyphPlacementPolicy.boxDrawingVertical ||
        TerminalGlyphPlacementPolicy.boxDrawingTopLeftArc ||
        TerminalGlyphPlacementPolicy.boxDrawingTopRightArc ||
        TerminalGlyphPlacementPolicy.boxDrawingBottomLeftArc ||
        TerminalGlyphPlacementPolicy.boxDrawingBottomRightArc => Rect.fromLTWH(
          cellLeft,
          rowY,
          _cellSize.width,
          _cellSize.height,
        ),
        TerminalGlyphPlacementPolicy.powerlineRightArrow => Rect.fromLTWH(
          cellLeft,
          rowY,
          _cellSize.width + horizontalBleed,
          _cellSize.height,
        ),
        TerminalGlyphPlacementPolicy.powerlineLeftArrow => Rect.fromLTWH(
          cellLeft - horizontalBleed,
          rowY,
          _cellSize.width + horizontalBleed,
          _cellSize.height,
        ),
        TerminalGlyphPlacementPolicy.powerlineRightCap => Rect.fromLTWH(
          cellLeft,
          rowY,
          _cellSize.width + capBleed,
          _cellSize.height,
        ),
        TerminalGlyphPlacementPolicy.powerlineLeftCap => Rect.fromLTWH(
          cellLeft - capBleed,
          rowY,
          _cellSize.width + capBleed,
          _cellSize.height,
        ),
        TerminalGlyphPlacementPolicy.baselineLeft => throw StateError(
          'baselineLeft glyphs do not use custom geometry',
        ),
      });

      return _PlacedCell(
        drawOffset: rect.topLeft,
        rect: rect,
        scaleX: 1,
        scaleY: 1,
        baselineY: targetBaselineY,
      );
    }

    const scaleX = 1.0;
    const scaleY = 1.0;
    final scaledWidth = cell.glyphSize.width;
    final scaledHeight = cell.glyphSize.height;
    final drawOffset = Offset(switch (cell.placementPolicy) {
      TerminalGlyphPlacementPolicy.baselineLeft ||
      TerminalGlyphPlacementPolicy.boxDrawingHorizontal ||
      TerminalGlyphPlacementPolicy.boxDrawingVertical ||
      TerminalGlyphPlacementPolicy.boxDrawingTopLeftArc ||
      TerminalGlyphPlacementPolicy.boxDrawingTopRightArc ||
      TerminalGlyphPlacementPolicy.boxDrawingBottomLeftArc ||
      TerminalGlyphPlacementPolicy.boxDrawingBottomRightArc => _snapLogicalX(
        cellLeft,
      ),
      TerminalGlyphPlacementPolicy.powerlineRightArrow ||
      TerminalGlyphPlacementPolicy.powerlineRightCap => _snapLogicalX(cellLeft),
      TerminalGlyphPlacementPolicy.powerlineLeftArrow ||
      TerminalGlyphPlacementPolicy.powerlineLeftCap => _snapLogicalX(
        cellRight - scaledWidth,
      ),
    }, targetBaselineY - cell.alphabeticBaseline);

    return _PlacedCell(
      drawOffset: drawOffset,
      rect: Rect.fromLTWH(
        drawOffset.dx,
        drawOffset.dy,
        scaledWidth,
        scaledHeight,
      ),
      scaleX: scaleX,
      scaleY: scaleY,
      baselineY: targetBaselineY,
    );
  }

  List<TerminalResolvedBackgroundSpan> _backgroundSpansForCells(
    List<_PaintCell> cells,
    double rowY,
  ) {
    final spans = <TerminalResolvedBackgroundSpan>[];
    var startColumn = -1;
    Color? currentBackground;

    void flush(int endColumn) {
      if (currentBackground == null ||
          startColumn < 0 ||
          startColumn >= endColumn) {
        return;
      }
      spans.add(
        TerminalResolvedBackgroundSpan(
          startColumn: startColumn,
          endColumn: endColumn,
          background: currentBackground,
          rect: Rect.fromLTRB(
            _snapLogicalX(startColumn * _cellSize.width),
            _snapLogicalY(rowY),
            _snapLogicalX(endColumn * _cellSize.width),
            _snapLogicalY(rowY + _cellSize.height),
          ),
        ),
      );
    }

    for (final cell in cells) {
      if (cell.background == null) {
        flush(cell.column);
        startColumn = -1;
        currentBackground = null;
        continue;
      }
      if (currentBackground == null) {
        startColumn = cell.column;
        currentBackground = cell.background;
        continue;
      }
      if (currentBackground.toARGB32() != cell.background!.toARGB32()) {
        flush(cell.column);
        startColumn = cell.column;
        currentBackground = cell.background;
      }
    }

    if (currentBackground != null && cells.isNotEmpty) {
      flush(cells.last.column + 1);
    }

    return spans;
  }

  Rect _cursorRect(TerminalCursor cursor) {
    return switch (_cursor.shape) {
      TerminalCursorShape.block => _cursorBlockRect(cursor),
      TerminalCursorShape.beam => _cursorBeamRect(cursor),
      TerminalCursorShape.underline => _cursorUnderlineRect(cursor),
    };
  }

  Rect _cursorBlockRect(TerminalCursor cursor) {
    return _snapRect(_cursorCellRect(cursor));
  }

  Rect _cursorBeamRect(TerminalCursor cursor) {
    final devicePixelRatio = _devicePixelRatio.isFinite && _devicePixelRatio > 0
        ? _devicePixelRatio
        : 1.0;
    final thickness = math.max(1.0, 2.0 / devicePixelRatio);
    final left = cursor.col * _cellSize.width;
    final top = cursor.row * _cellSize.height;
    return _snapRect(Rect.fromLTWH(left, top, thickness, _cellSize.height));
  }

  Rect _cursorUnderlineRect(TerminalCursor cursor) {
    final devicePixelRatio = _devicePixelRatio.isFinite && _devicePixelRatio > 0
        ? _devicePixelRatio
        : 1.0;
    final thickness = math.max(1.0, 2.0 / devicePixelRatio);
    final cellRect = _cursorCellRect(cursor);
    final bottom = cellRect.bottom;
    return _snapRect(
      Rect.fromLTRB(
        cellRect.left,
        math.max(cellRect.top, bottom - thickness),
        cellRect.right,
        bottom,
      ),
    );
  }

  Rect _cursorCellRect(TerminalCursor cursor) {
    var column = cursor.col;
    var columnSpan = 1;
    final cell = _cursorCellFor(cursor);
    if (cell != null) {
      column = cell.column;
      columnSpan = math.max(1, cell.columnSpan);
    }
    return Rect.fromLTWH(
      column * _cellSize.width,
      cursor.row * _cellSize.height,
      columnSpan * _cellSize.width,
      _cellSize.height,
    );
  }

  _PaintCell? _cursorCellFor(TerminalCursor cursor) {
    final rowLayout = _rowLayoutCache[cursor.row];
    if (rowLayout == null) {
      return null;
    }
    for (final cell in rowLayout.cells) {
      if (cursor.col >= cell.column &&
          cursor.col < cell.column + cell.columnSpan) {
        return cell;
      }
    }
    return null;
  }

  ui.ParagraphStyle _paragraphStyle() {
    return ui.ParagraphStyle(
      fontFamily: _font.family,
      fontSize: _font.size,
      height: _font.lineHeight,
    );
  }

  ui.TextStyle _textStyle({
    Color? color,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    TextDecoration? decoration,
  }) {
    return ui.TextStyle(
      color: color,
      fontFamily: _font.family,
      fontFamilyFallback: _font.fallback,
      fontSize: _font.size,
      height: _font.lineHeight,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      decoration: decoration,
    );
  }

  void _paintCustomGeometry(
    Canvas canvas,
    _PaintCell cell,
    Rect rect, {
    Color? foreground,
  }) {
    final color = foreground ?? cell.foreground;
    final fillPaint = _customGeometryFillPaint..color = color;
    final strokePaint = _customGeometryStrokePaint
      ..color = color
      ..strokeWidth = _boxDrawingStrokeWidth();
    final capRadius = Radius.circular(rect.height / 2);
    final midX = _snapLogicalX(rect.center.dx);
    final midY = _snapLogicalY(rect.center.dy);
    final halfStroke = strokePaint.strokeWidth / 2;
    final horizontalRect = _snapRect(
      Rect.fromLTRB(
        rect.left,
        midY - halfStroke,
        rect.right,
        midY + halfStroke,
      ),
    );
    final verticalRect = _snapRect(
      Rect.fromLTRB(
        midX - halfStroke,
        rect.top,
        midX + halfStroke,
        rect.bottom,
      ),
    );
    switch (cell.placementPolicy) {
      case TerminalGlyphPlacementPolicy.boxDrawingHorizontal:
        canvas.drawRect(horizontalRect, fillPaint);
        return;
      case TerminalGlyphPlacementPolicy.boxDrawingVertical:
        canvas.drawRect(verticalRect, fillPaint);
        return;
      case TerminalGlyphPlacementPolicy.boxDrawingTopLeftArc:
        canvas.drawPath(
          Path()
            ..moveTo(midX, rect.bottom)
            ..quadraticBezierTo(midX, midY, rect.right, midY),
          strokePaint,
        );
        return;
      case TerminalGlyphPlacementPolicy.boxDrawingTopRightArc:
        canvas.drawPath(
          Path()
            ..moveTo(rect.left, midY)
            ..quadraticBezierTo(midX, midY, midX, rect.bottom),
          strokePaint,
        );
        return;
      case TerminalGlyphPlacementPolicy.boxDrawingBottomLeftArc:
        canvas.drawPath(
          Path()
            ..moveTo(midX, rect.top)
            ..quadraticBezierTo(midX, midY, rect.right, midY),
          strokePaint,
        );
        return;
      case TerminalGlyphPlacementPolicy.boxDrawingBottomRightArc:
        canvas.drawPath(
          Path()
            ..moveTo(rect.left, midY)
            ..quadraticBezierTo(midX, midY, midX, rect.top),
          strokePaint,
        );
        return;
      case TerminalGlyphPlacementPolicy.powerlineRightArrow:
        canvas.drawPath(
          Path()
            ..moveTo(rect.left, rect.top)
            ..lineTo(rect.right, rect.center.dy)
            ..lineTo(rect.left, rect.bottom)
            ..close(),
          fillPaint,
        );
        return;
      case TerminalGlyphPlacementPolicy.powerlineLeftArrow:
        canvas.drawPath(
          Path()
            ..moveTo(rect.right, rect.top)
            ..lineTo(rect.left, rect.center.dy)
            ..lineTo(rect.right, rect.bottom)
            ..close(),
          fillPaint,
        );
        return;
      case TerminalGlyphPlacementPolicy.powerlineLeftCap:
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            rect,
            topLeft: capRadius,
            bottomLeft: capRadius,
          ),
          fillPaint,
        );
        return;
      case TerminalGlyphPlacementPolicy.powerlineRightCap:
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            rect,
            topRight: capRadius,
            bottomRight: capRadius,
          ),
          fillPaint,
        );
        return;
      case TerminalGlyphPlacementPolicy.baselineLeft:
        return;
    }
  }

  double _boxDrawingStrokeWidth() {
    final dpr = _devicePixelRatio.isFinite && _devicePixelRatio > 0
        ? _devicePixelRatio
        : 1.0;
    return _snapLogical(
      math.max(1.0 / dpr, math.min(_cellSize.width, _cellSize.height) * 0.12),
    );
  }

  double _snapLogicalX(double value) => _snapLogical(value);

  double _snapLogicalY(double value) => _snapLogical(value);

  double _snapLogical(double value) {
    if (!value.isFinite ||
        !_devicePixelRatio.isFinite ||
        _devicePixelRatio <= 0) {
      return value;
    }
    return (value * _devicePixelRatio).roundToDouble() / _devicePixelRatio;
  }

  Rect _snapRect(Rect rect) {
    final left = _snapLogicalX(rect.left);
    final top = _snapLogicalY(rect.top);
    final right = math.max(left, _snapLogicalX(rect.right));
    final bottom = math.max(top, _snapLogicalY(rect.bottom));
    return Rect.fromLTRB(left, top, right, bottom);
  }

  TerminalCellPosition _cellForOffset(Offset offset) {
    final row = (offset.dy / _cellSize.height).floor().clamp(0, 9999);
    final col = (offset.dx / _cellSize.width).floor().clamp(0, 9999);
    return TerminalCellPosition(row, col);
  }

  @override
  void dispose() {
    _controller.removeListener(markNeedsPaint);
    _selectionController.removeListener(markNeedsPaint);
    for (final rowVisual in _rowVisualCache.values) {
      rowVisual.picture.dispose();
    }
    super.dispose();
  }
}

int _benchmarkDirtyRowCount(
  TerminalFrameDiff frame,
  TerminalRenderIntent renderIntent, {
  required bool hasNewFrame,
}) {
  if (!hasNewFrame) {
    return 0;
  }
  if (renderIntent.rebuildAllRows) {
    return frame.viewportRows;
  }
  if (renderIntent.dirtyRowIndexes.isNotEmpty) {
    return renderIntent.dirtyRowIndexes.length;
  }
  var count = 0;
  for (final range in frame.dirtyRanges) {
    count += math.max(0, range.end - range.start);
  }
  return count;
}

bool _sameFontConfig(TerminalFontConfig left, TerminalFontConfig right) {
  return left.family == right.family &&
      left.size == right.size &&
      left.lineHeight == right.lineHeight &&
      _sameStringList(left.fallback, right.fallback);
}

bool _sameStringList(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

bool _sameSearchMatches(
  List<TerminalSearchMatch> left,
  List<TerminalSearchMatch> right,
) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    final leftMatch = left[index];
    final rightMatch = right[index];
    if (leftMatch.row != rightMatch.row ||
        leftMatch.startCol != rightMatch.startCol ||
        leftMatch.endCol != rightMatch.endCol ||
        leftMatch.text != rightMatch.text ||
        leftMatch.scrollbackOffset != rightMatch.scrollbackOffset) {
      return false;
    }
  }
  return true;
}

class _SearchHighlightSpan {
  const _SearchHighlightSpan({required this.index, required this.rect});

  final int index;
  final Rect rect;
}

class _ResolvedCellStyle {
  const _ResolvedCellStyle({
    required this.rawForeground,
    required this.foreground,
    required this.background,
    required this.fontWeight,
    required this.fontStyle,
    required this.decoration,
  });

  final Color rawForeground;
  final Color foreground;
  final Color? background;
  final FontWeight fontWeight;
  final FontStyle fontStyle;
  final TextDecoration decoration;
}

class _PaintCell {
  const _PaintCell({
    required this.column,
    required this.columnSpan,
    required this.text,
    required this.foreground,
    required this.background,
    required this.fontWeight,
    required this.fontStyle,
    required this.decoration,
    required this.glyphClass,
    required this.paragraph,
    required this.glyphSize,
    required this.alphabeticBaseline,
    required this.usesCustomGeometry,
    required this.placementPolicy,
    this.isContinuation = false,
  });

  final int column;
  final int columnSpan;
  final String text;
  final Color foreground;
  final Color? background;
  final FontWeight fontWeight;
  final FontStyle fontStyle;
  final TextDecoration decoration;
  final TerminalGlyphClass glyphClass;
  final ui.Paragraph? paragraph;
  final Size glyphSize;
  final double alphabeticBaseline;
  final bool usesCustomGeometry;
  final TerminalGlyphPlacementPolicy placementPolicy;
  final bool isContinuation;
}

class _CachedRowLayout {
  const _CachedRowLayout({
    required this.signature,
    required this.cellCount,
    required this.cells,
  });

  final int signature;
  final int cellCount;
  final List<_PaintCell> cells;
}

class _CachedGlyphParagraph {
  const _CachedGlyphParagraph({
    required this.paragraph,
    required this.size,
    required this.alphabeticBaseline,
  });

  final ui.Paragraph paragraph;
  final Size size;
  final double alphabeticBaseline;
}

class _CachedRowVisual {
  const _CachedRowVisual({
    required this.signature,
    required this.picture,
    required this.cellCount,
    required this.backgroundSpans,
  });

  final int signature;
  final ui.Picture picture;
  final int cellCount;
  final List<TerminalResolvedBackgroundSpan> backgroundSpans;
}

class _MeasuredCellMetrics {
  const _MeasuredCellMetrics({
    required this.size,
    required this.alphabeticBaseline,
  });

  final Size size;
  final double alphabeticBaseline;
}

class _PlacedCell {
  const _PlacedCell({
    required this.drawOffset,
    required this.rect,
    required this.scaleX,
    required this.scaleY,
    required this.baselineY,
  });

  final Offset drawOffset;
  final Rect rect;
  final double scaleX;
  final double scaleY;
  final double baselineY;
}
