import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../config/terminal_config.dart';
import 'selection_controller.dart';
import 'terminal_models.dart';
import 'terminal_viewport.dart';
import 'terminal_viewport_colors.dart';

enum TerminalGlyphPlacementPolicy {
  baselineLeft,
  powerlineRightArrow,
  powerlineLeftArrow,
  powerlineLeftCap,
  powerlineRightCap,
}

enum TerminalGlyphClass { text, nerdIcon, powerlineCustom }

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

class RenderTerminalViewport extends RenderBox {
  RenderTerminalViewport({
    required TerminalViewportController controller,
    required SelectionController selectionController,
    required bool cursorVisible,
    required TerminalFontConfig font,
    required TerminalCursorConfig cursor,
    required double devicePixelRatio,
    required TerminalViewportColors colors,
  }) : _controller = controller,
       _selectionController = selectionController,
       _cursorVisible = cursorVisible,
       _font = font,
       _cursor = cursor,
       _devicePixelRatio = devicePixelRatio,
       _colors = colors {
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
  final Map<int, _CachedRowLayout> _rowLayoutCache = {};
  final Map<int, _CachedGlyphParagraph> _glyphParagraphCache = {};
  final Map<int, _CachedRowVisual> _rowVisualCache = {};
  final Map<int, List<TerminalResolvedStyle>> _debugResolvedStyles = {};
  final Map<int, List<TerminalResolvedCell>> _debugResolvedCells = {};
  final Map<int, List<TerminalResolvedBackgroundSpan>> _debugBackgroundSpans =
      {};
  final Map<int, int> _rowPictureBuildCounts = {};
  int _paragraphBuilds = 0;
  Size _cellSize = terminalFallbackCellSize;
  double _cellBaseline = terminalFallbackCellSize.height;
  TerminalRowTextMetrics _rowTextMetrics = terminalFallbackRowTextMetrics;
  List<String> _debugLastPaintedRowTexts = const [];
  List<int> _debugLastRebuiltRowIndexes = const [];
  Rect? _debugCursorRect;
  _MeasuredCellMetrics? _cachedCellMetrics;
  TerminalRowTextMetrics? _cachedMeasuredRowTextMetrics;
  int? _textMetricsSignature;
  int _lastPaintedFrameVersion = -1;
  bool _needsFullRowVisualRebuild = true;

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

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void performLayout() {
    size = constraints.biggest.isFinite
        ? constraints.biggest
        : const Size(640, 480);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = _colors.canvasBackground,
    );

    final frame = _controller.frame;
    _syncTextMetrics();
    _controller.updateMeasuredCellSize(_cellSize);
    final selection = _selectionController.selectionForFrame(frame);
    final paintedRowTexts = <String>[];
    final activeRowIndexes = <int>{};
    final rebuiltRowIndexes = <int>[];
    final hasNewFrame = _lastPaintedFrameVersion != _controller.frameVersion;
    if (hasNewFrame &&
        frame.frameKind == TerminalFrameKind.delta &&
        frame.viewportRowShift != 0) {
      _shiftRowCaches(frame.viewportRowShift, frame.viewportRows);
    }
    final shouldRebuildAllRows =
        _needsFullRowVisualRebuild ||
        (hasNewFrame && frame.frameKind == TerminalFrameKind.snapshot);
    final dirtyRowIndexes = shouldRebuildAllRows
        ? <int>{}
        : (hasNewFrame ? _dirtyRowIndexesFor(frame) : const <int>{});

    for (final row in frame.rows) {
      activeRowIndexes.add(row.index);
      paintedRowTexts.add(row.text);
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
          ? _rowLayoutFor(row)
          : null;
      if (rowNeedsRebuild) {
        _rebuildRowVisual(
          row: row,
          rowLayout: rowLayout!,
          rebuiltRowIndexes: rebuiltRowIndexes,
        );
      }
      final rowVisual = _rowVisualCache[row.index];
      final y = row.index * _cellSize.height;
      final backgroundSpans =
          rowVisual?.backgroundSpans ??
          const <TerminalResolvedBackgroundSpan>[];
      for (final span in backgroundSpans) {
        canvas.drawRect(
          span.rect.shift(Offset(0, y)),
          Paint()
            ..color = span.background
            ..isAntiAlias = false,
        );
      }
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
        canvas.drawRect(
          Rect.fromLTWH(
            clampedStart * _cellSize.width,
            y,
            (clampedEnd - clampedStart) * _cellSize.width,
            _cellSize.height,
          ),
          Paint()..color = _colors.selection,
        );
      }
      if (rowVisual != null) {
        canvas.save();
        canvas.translate(0, y);
        canvas.drawPicture(rowVisual.picture);
        canvas.restore();
      }
    }
    _pruneInactiveRowCaches(activeRowIndexes);
    _debugLastPaintedRowTexts = paintedRowTexts;
    _debugLastRebuiltRowIndexes = List<int>.unmodifiable(rebuiltRowIndexes);
    if (hasNewFrame) {
      _lastPaintedFrameVersion = _controller.frameVersion;
    }
    _needsFullRowVisualRebuild = false;

    if (frame.cursor.visible && _cursorVisible) {
      final cursorRect = _cursorRect(frame.cursor);
      _debugCursorRect = cursorRect;
      canvas.drawRect(
        cursorRect,
        Paint()
          ..color = _colors.cursor
          ..isAntiAlias = false,
      );
    } else {
      _debugCursorRect = null;
    }
    canvas.restore();
  }

  TerminalCellPosition debugCellForOffset(Offset offset) =>
      _cellForOffset(offset);
  Size get debugCellSize => _cellSize;
  double get debugCellBaseline => _cellBaseline;
  TerminalRowTextMetrics get debugRowTextMetrics => _rowTextMetrics;
  int get debugParagraphBuilds => _paragraphBuilds;
  List<String> get debugLastPaintedRowTexts =>
      List<String>.unmodifiable(_debugLastPaintedRowTexts);
  List<int> get debugLastRebuiltRowIndexes =>
      List<int>.unmodifiable(_debugLastRebuiltRowIndexes);
  bool get debugCursorVisible {
    final frame = _controller.frame;
    return frame.cursor.visible && _cursorVisible;
  }

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

  Rect? get debugCursorRect => _debugCursorRect;
  TerminalViewportColors get debugColors => _colors;

  void _invalidateVisualCaches() {
    for (final rowVisual in _rowVisualCache.values) {
      rowVisual.picture.dispose();
    }
    _rowVisualCache.clear();
    _rowLayoutCache.clear();
    _debugResolvedStyles.clear();
    _debugResolvedCells.clear();
    _debugBackgroundSpans.clear();
    _debugLastRebuiltRowIndexes = const [];
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

  _CachedRowLayout _rowLayoutFor(TerminalRow row) {
    final signature = Object.hashAll([
      row.text,
      _colors.foreground.toARGB32(),
      _colors.canvasBackground.toARGB32(),
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
    final cellStyles = List<_ResolvedCellStyle>.filled(
      textCells.cellCount,
      _ResolvedCellStyle(
        foreground: _colors.foreground,
        background: null,
        fontWeight: FontWeight.w400,
        fontStyle: FontStyle.normal,
        decoration: TextDecoration.none,
      ),
    );
    final resolvedStyles = <TerminalResolvedStyle>[];
    for (final run in row.styleRuns) {
      final start = textCells.clampColumn(run.start);
      final end = run.end.clamp(start, textCells.cellCount).toInt();
      if (start >= end) {
        continue;
      }
      final resolvedStyle = _resolvedCellStyleFor(run);
      resolvedStyles.add(
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
          foreground: style.foreground,
          background: style.background,
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
    _debugResolvedStyles[row.index] = resolvedStyles;
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

  Set<int> _dirtyRowIndexesFor(TerminalFrameDiff frame) {
    final dirtyRows = <int>{};
    for (final range in frame.dirtyRanges) {
      for (var rowIndex = range.start; rowIndex < range.end; rowIndex += 1) {
        dirtyRows.add(rowIndex);
      }
    }
    return dirtyRows;
  }

  void _rebuildRowVisual({
    required TerminalRow row,
    required _CachedRowLayout rowLayout,
    required List<int> rebuiltRowIndexes,
  }) {
    const rowY = 0.0;
    final backgroundSpans = _backgroundSpansForCells(rowLayout.cells, rowY);
    final debugCells = <TerminalResolvedCell>[];
    final recorder = ui.PictureRecorder();
    final pictureCanvas = Canvas(recorder);

    for (final cell in rowLayout.cells) {
      if (cell.isContinuation) {
        continue;
      }
      final placement = _placementForCell(cell, rowY);
      final paragraph = cell.paragraph;
      if (cell.usesCustomGeometry) {
        _paintPowerlineGeometry(pictureCanvas, cell, placement.rect);
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
      debugCells.add(
        TerminalResolvedCell(
          column: cell.column,
          text: cell.text,
          foreground: cell.foreground,
          background: cell.background,
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
    _debugResolvedCells[row.index] = debugCells;
    _debugBackgroundSpans[row.index] = backgroundSpans;
    _rowPictureBuildCounts[row.index] =
        (_rowPictureBuildCounts[row.index] ?? 0) + 1;
    rebuiltRowIndexes.add(row.index);
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
    final inactiveVisualRows = _rowVisualCache.keys
        .where((rowIndex) => !activeRowIndexes.contains(rowIndex))
        .toList(growable: false);
    for (final rowIndex in inactiveVisualRows) {
      _rowVisualCache.remove(rowIndex)?.picture.dispose();
    }
    _rowLayoutCache.removeWhere((key, _) => !activeRowIndexes.contains(key));
    _debugResolvedStyles.removeWhere(
      (key, _) => !activeRowIndexes.contains(key),
    );
    _debugResolvedCells.removeWhere(
      (key, _) => !activeRowIndexes.contains(key),
    );
    _debugBackgroundSpans.removeWhere(
      (key, _) => !activeRowIndexes.contains(key),
    );
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
    if (placementPolicy != TerminalGlyphPlacementPolicy.baselineLeft) {
      return TerminalGlyphClass.powerlineCustom;
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

  _ResolvedCellStyle _resolvedCellStyleFor(TerminalStyleRun run) {
    var foreground = run.foreground ?? _colors.foreground;
    var background = run.background ?? _colors.canvasBackground;

    if (run.inverse) {
      final swapped = background;
      background = foreground;
      foreground = swapped;
    }
    if (run.dim) {
      foreground = foreground.withValues(alpha: foreground.a * 0.65);
    }

    return _ResolvedCellStyle(
      foreground: foreground,
      background: (run.background == null && !run.inverse) ? null : background,
      fontWeight: run.bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: run.italic ? FontStyle.italic : FontStyle.normal,
      decoration: run.underline
          ? TextDecoration.underline
          : TextDecoration.none,
    );
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
    final cached = _glyphParagraphCache[signature];
    if (cached != null) {
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
    _glyphParagraphCache[signature] = glyphParagraph;
    return glyphParagraph;
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
        TerminalGlyphPlacementPolicy.baselineLeft => Rect.fromLTWH(
          cellLeft,
          rowY,
          _cellSize.width,
          _cellSize.height,
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
      TerminalGlyphPlacementPolicy.baselineLeft => _snapLogicalX(cellLeft),
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
    final left = cursor.col * _cellSize.width;
    final top = cursor.row * _cellSize.height;
    return _snapRect(
      Rect.fromLTWH(left, top, _cellSize.width, _cellSize.height),
    );
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
    final left = cursor.col * _cellSize.width;
    final top = cursor.row * _cellSize.height;
    final bottom = top + _cellSize.height;
    return _snapRect(
      Rect.fromLTRB(
        left,
        math.max(top, bottom - thickness),
        left + _cellSize.width,
        bottom,
      ),
    );
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

  void _paintPowerlineGeometry(Canvas canvas, _PaintCell cell, Rect rect) {
    final paint = Paint()
      ..color = cell.foreground
      ..isAntiAlias = true;
    final capRadius = Radius.circular(rect.height / 2);
    switch (cell.placementPolicy) {
      case TerminalGlyphPlacementPolicy.powerlineRightArrow:
        canvas.drawPath(
          Path()
            ..moveTo(rect.left, rect.top)
            ..lineTo(rect.right, rect.center.dy)
            ..lineTo(rect.left, rect.bottom)
            ..close(),
          paint,
        );
        return;
      case TerminalGlyphPlacementPolicy.powerlineLeftArrow:
        canvas.drawPath(
          Path()
            ..moveTo(rect.right, rect.top)
            ..lineTo(rect.left, rect.center.dy)
            ..lineTo(rect.right, rect.bottom)
            ..close(),
          paint,
        );
        return;
      case TerminalGlyphPlacementPolicy.powerlineLeftCap:
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            rect,
            topLeft: capRadius,
            bottomLeft: capRadius,
          ),
          paint,
        );
        return;
      case TerminalGlyphPlacementPolicy.powerlineRightCap:
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            rect,
            topRight: capRadius,
            bottomRight: capRadius,
          ),
          paint,
        );
        return;
      case TerminalGlyphPlacementPolicy.baselineLeft:
        return;
    }
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

class _ResolvedCellStyle {
  const _ResolvedCellStyle({
    required this.foreground,
    required this.background,
    required this.fontWeight,
    required this.fontStyle,
    required this.decoration,
  });

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
