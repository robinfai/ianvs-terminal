import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';

import 'selection_controller.dart';
import 'terminal_painter_models.dart';
import 'terminal_viewport.dart';

class RenderTerminalViewport extends RenderBox {
  RenderTerminalViewport({
    required TerminalViewportController controller,
    required SelectionController selectionController,
    required ValueChanged<int> onScrollLines,
    required double devicePixelRatio,
  }) : _controller = controller,
       _selectionController = selectionController,
       _onScrollLines = onScrollLines,
       _devicePixelRatio = devicePixelRatio {
    _controller.addListener(markNeedsPaint);
    _selectionController.addListener(markNeedsPaint);
  }

  TerminalViewportController _controller;
  SelectionController _selectionController;
  ValueChanged<int> _onScrollLines;
  double _devicePixelRatio;
  double _pendingScrollLines = 0.0;
  final Map<int, _CachedParagraph> _paragraphCache = {};
  int _paragraphBuilds = 0;
  Size _cellSize = const Size(9, 18);
  List<String> _debugLastPaintedRowTexts = const [];

  set controller(TerminalViewportController value) {
    if (identical(value, _controller)) {
      return;
    }
    _controller.removeListener(markNeedsPaint);
    _controller = value;
    _controller.addListener(markNeedsPaint);
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

  set onScrollLines(ValueChanged<int> value) {
    _onScrollLines = value;
  }

  set devicePixelRatio(double value) {
    _devicePixelRatio = value;
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
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF111827),
    );

    final frame = _controller.frame;
    _cellSize = _measureCellSize();
    final selection = _selectionController.selection;
    final paintedRowTexts = <String>[];

    for (final row in frame.rows) {
      paintedRowTexts.add(row.text);
      final paragraph = _paragraphForRow(row);
      final y = row.index * _cellSize.height;
      if (selection != null &&
          row.index >= selection.startRow &&
          row.index <= selection.endRow) {
        final selectedStart = row.index == selection.startRow
            ? selection.startCol
            : 0;
        final selectedEnd = row.index == selection.endRow
            ? selection.endCol
            : row.text.length;
        canvas.drawRect(
          Rect.fromLTWH(
            selectedStart * _cellSize.width,
            y,
            (selectedEnd - selectedStart).clamp(0, row.text.length) *
                _cellSize.width,
            _cellSize.height,
          ),
          Paint()..color = const Color(0x663B82F6),
        );
      }
      canvas.drawParagraph(paragraph, Offset(0, y));
    }
    _debugLastPaintedRowTexts = paintedRowTexts;

    if (frame.cursor.visible) {
      canvas.drawRect(
        Rect.fromLTWH(
          frame.cursor.col * _cellSize.width,
          frame.cursor.row * _cellSize.height,
          _cellSize.width,
          _cellSize.height,
        ),
        Paint()
          ..color = const Color(0xFFBBF7D0)
          ..style = PaintingStyle.stroke
          ..strokeWidth = _devicePixelRatio.clamp(1, 2),
      );
    }
    canvas.restore();
  }

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent) {
      _selectionController.begin(_cellForOffset(event.localPosition));
    } else if (event is PointerMoveEvent && event.buttons != 0) {
      _selectionController.update(_cellForOffset(event.localPosition));
    } else if (event is PointerScrollEvent) {
      _pendingScrollLines += event.scrollDelta.dy / _cellSize.height;
      final deltaLines = _pendingScrollLines.round();
      if (deltaLines != 0) {
        _pendingScrollLines -= deltaLines;
        _onScrollLines(deltaLines);
      }
    }
  }

  TerminalCellPosition debugCellForOffset(Offset offset) =>
      _cellForOffset(offset);
  int get debugParagraphBuilds => _paragraphBuilds;
  List<String> get debugLastPaintedRowTexts =>
      List<String>.unmodifiable(_debugLastPaintedRowTexts);

  ui.Paragraph _paragraphForRow(TerminalRow row) {
    final signature = Object.hash(
      row.text,
      row.styleRuns.map(
        (entry) => Object.hash(
          entry.start,
          entry.end,
          entry.foreground,
          entry.background,
          entry.bold,
          entry.italic,
          entry.underline,
          entry.inverse,
        ),
      ),
    );
    final cached = _paragraphCache[row.index];
    if (cached != null && cached.signature == signature) {
      return cached.paragraph;
    }

    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontFamily: 'Menlo', fontSize: 14, height: 1.2),
    );
    if (row.styleRuns.isEmpty) {
      builder.pushStyle(ui.TextStyle(color: const Color(0xFFF8FAFC)));
      builder.addText(row.text);
      builder.pop();
    } else {
      var cursor = 0;
      for (final run in row.styleRuns) {
        if (cursor < run.start && cursor < row.text.length) {
          builder.pushStyle(ui.TextStyle(color: const Color(0xFFF8FAFC)));
          builder.addText(
            row.text.substring(cursor, run.start.clamp(0, row.text.length)),
          );
          builder.pop();
        }
        final end = run.end.clamp(run.start, row.text.length);
        final backgroundPaint = run.background == null
            ? null
            : (Paint()..color = run.background!);
        builder.pushStyle(
          ui.TextStyle(
            color: run.foreground ?? const Color(0xFFF8FAFC),
            background: backgroundPaint,
            fontWeight: run.bold ? FontWeight.w700 : FontWeight.w400,
            fontStyle: run.italic ? FontStyle.italic : FontStyle.normal,
            decoration: run.underline
                ? TextDecoration.underline
                : TextDecoration.none,
          ),
        );
        builder.addText(
          row.text.substring(run.start.clamp(0, row.text.length), end),
        );
        builder.pop();
        cursor = end;
      }
      if (cursor < row.text.length) {
        builder.pushStyle(ui.TextStyle(color: const Color(0xFFF8FAFC)));
        builder.addText(row.text.substring(cursor));
        builder.pop();
      }
    }
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: size.width));
    _paragraphCache[row.index] = _CachedParagraph(
      signature: signature,
      paragraph: paragraph,
    );
    _paragraphBuilds += 1;
    return paragraph;
  }

  Size _measureCellSize() {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontFamily: 'Menlo', fontSize: 14, height: 1.2),
    )..addText('W');
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
    return Size(paragraph.maxIntrinsicWidth, paragraph.height);
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
    super.dispose();
  }
}

class _CachedParagraph {
  const _CachedParagraph({required this.signature, required this.paragraph});

  final int signature;
  final ui.Paragraph paragraph;
}
