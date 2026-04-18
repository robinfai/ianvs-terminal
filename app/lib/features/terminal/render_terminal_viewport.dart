import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'selection_controller.dart';
import 'terminal_painter_models.dart';
import 'terminal_viewport.dart';

const String terminalPrimaryFontFamily = 'JetBrainsMono Nerd Font Mono';
const Color terminalDefaultForeground = Color(0xFFF8FAFC);
const Color terminalDefaultBackground = Color(0xFF000000);
const Color terminalCursorColor = Color(0xFFBBF7D0);
const List<String> terminalFontFamilyFallback = <String>[
  'Menlo',
  'JetBrainsMono Nerd Font',
  'SF Mono',
  'Monaco',
  'Apple Symbols',
];

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

class RenderTerminalViewport extends RenderBox {
  RenderTerminalViewport({
    required TerminalViewportController controller,
    required SelectionController selectionController,
    required bool cursorVisible,
    required double devicePixelRatio,
  }) : _controller = controller,
       _selectionController = selectionController,
       _cursorVisible = cursorVisible,
       _devicePixelRatio = devicePixelRatio {
    _controller.addListener(markNeedsPaint);
    _selectionController.addListener(markNeedsPaint);
  }

  TerminalViewportController _controller;
  SelectionController _selectionController;
  double _devicePixelRatio;
  bool _cursorVisible = true;
  final Map<int, _CachedParagraph> _paragraphCache = {};
  final Map<int, List<TerminalResolvedStyle>> _debugResolvedStyles = {};
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

  set devicePixelRatio(double value) {
    _devicePixelRatio = value;
  }

  set cursorVisible(bool value) {
    _cursorVisible = value;
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
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF000000),
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
        final selectedStart = _selectionController.isBlockSelection
            ? selection.startCol
            : (row.index == selection.startRow ? selection.startCol : 0);
        final selectedEnd = _selectionController.isBlockSelection
            ? selection.endCol
            : (row.index == selection.endRow
                  ? selection.endCol
                  : row.text.length);
        final clampedStart = selectedStart.clamp(0, row.text.length);
        final clampedEnd = selectedEnd.clamp(clampedStart, row.text.length);
        canvas.drawRect(
          Rect.fromLTWH(
            clampedStart * _cellSize.width,
            y,
            (clampedEnd - clampedStart) * _cellSize.width,
            _cellSize.height,
          ),
          Paint()..color = const Color(0x663B82F6),
        );
      }
      canvas.drawParagraph(paragraph, Offset(0, y));
    }
    _debugLastPaintedRowTexts = paintedRowTexts;

    if (frame.cursor.visible && _cursorVisible) {
      canvas.drawRect(
        Rect.fromLTWH(
          frame.cursor.col * _cellSize.width,
          frame.cursor.row * _cellSize.height,
          _cellSize.width,
          _cellSize.height,
        ),
        Paint()
          ..color = terminalCursorColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = _devicePixelRatio.clamp(1, 2),
      );
    }
    canvas.restore();
  }

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent) {
      _selectionController.begin(
        _cellForOffset(event.localPosition),
        block: HardwareKeyboard.instance.isAltPressed,
      );
    } else if (event is PointerMoveEvent && event.buttons != 0) {
      _selectionController.update(_cellForOffset(event.localPosition));
    }
  }

  TerminalCellPosition debugCellForOffset(Offset offset) =>
      _cellForOffset(offset);
  Size get debugCellSize => _cellSize;
  int get debugParagraphBuilds => _paragraphBuilds;
  List<String> get debugLastPaintedRowTexts =>
      List<String>.unmodifiable(_debugLastPaintedRowTexts);
  bool get debugCursorVisible {
    final frame = _controller.frame;
    return frame.cursor.visible && _cursorVisible;
  }

  List<TerminalResolvedStyle> debugResolvedStylesForRow(int row) =>
      List<TerminalResolvedStyle>.unmodifiable(
        _debugResolvedStyles[row] ?? const <TerminalResolvedStyle>[],
      );

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
      ui.ParagraphStyle(
        fontFamily: terminalPrimaryFontFamily,
        fontSize: 14,
        height: 1.2,
      ),
    );
    final resolvedStyles = <TerminalResolvedStyle>[];
    if (row.styleRuns.isEmpty) {
      builder.pushStyle(
        ui.TextStyle(
          color: terminalDefaultForeground,
          fontFamily: terminalPrimaryFontFamily,
          fontFamilyFallback: terminalFontFamilyFallback,
        ),
      );
      builder.addText(row.text);
      builder.pop();
    } else {
      var cursor = 0;
      for (final run in row.styleRuns) {
        if (cursor < run.start && cursor < row.text.length) {
          builder.pushStyle(
            ui.TextStyle(
              color: terminalDefaultForeground,
              fontFamily: terminalPrimaryFontFamily,
              fontFamilyFallback: terminalFontFamilyFallback,
            ),
          );
          builder.addText(
            row.text.substring(cursor, run.start.clamp(0, row.text.length)),
          );
          builder.pop();
        }
        final end = run.end.clamp(run.start, row.text.length);
        var foreground = run.foreground ?? terminalDefaultForeground;
        var background = run.background ?? terminalDefaultBackground;

        if (run.inverse) {
          final swapped = background;
          background = foreground;
          foreground = swapped;
        }

        final backgroundPaint = (run.background == null && !run.inverse)
            ? null
            : (Paint()..color = background);
        resolvedStyles.add(
          TerminalResolvedStyle(
            start: run.start,
            end: end,
            foreground: foreground,
            background: backgroundPaint?.color,
          ),
        );
        builder.pushStyle(
          ui.TextStyle(
            color: foreground,
            background: backgroundPaint,
            fontFamily: terminalPrimaryFontFamily,
            fontFamilyFallback: terminalFontFamilyFallback,
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
        builder.pushStyle(
          ui.TextStyle(
            color: terminalDefaultForeground,
            fontFamily: terminalPrimaryFontFamily,
            fontFamilyFallback: terminalFontFamilyFallback,
          ),
        );
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
    _debugResolvedStyles[row.index] = resolvedStyles;
    _paragraphBuilds += 1;
    return paragraph;
  }

  Size _measureCellSize() {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        fontFamily: terminalPrimaryFontFamily,
        fontSize: 14,
        height: 1.2,
      ),
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
