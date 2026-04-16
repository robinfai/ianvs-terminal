import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'terminal_painter_models.dart';

enum SelectionMode { linear, block }

class SelectionController extends ChangeNotifier {
  TerminalSelection? _selection;
  SelectionMode _mode = SelectionMode.linear;

  TerminalSelection? get selection {
    final current = _selection;
    if (current == null) {
      return null;
    }
    return switch (_mode) {
      SelectionMode.linear => current.normalized(),
      SelectionMode.block => TerminalSelection(
        startRow: math.min(current.startRow, current.endRow),
        startCol: math.min(current.startCol, current.endCol),
        endRow: math.max(current.startRow, current.endRow),
        endCol: math.max(current.startCol, current.endCol),
      ),
    };
  }

  bool get isBlockSelection => _mode == SelectionMode.block;

  void begin(TerminalCellPosition cell, {bool block = false}) {
    _mode = block ? SelectionMode.block : SelectionMode.linear;
    _selection = TerminalSelection(
      startRow: cell.row,
      startCol: cell.col,
      endRow: cell.row,
      endCol: cell.col,
    );
    notifyListeners();
  }

  void update(TerminalCellPosition cell) {
    final current = _selection;
    if (current == null) {
      return;
    }
    _selection = TerminalSelection(
      startRow: current.startRow,
      startCol: current.startCol,
      endRow: cell.row,
      endCol: cell.col,
    );
    notifyListeners();
  }

  void clear() {
    _selection = null;
    _mode = SelectionMode.linear;
    notifyListeners();
  }

  String textForFrame(TerminalFrameDiff frame) {
    final normalized = selection;
    if (normalized == null) {
      return '';
    }
    return switch (_mode) {
      SelectionMode.linear => _linearTextForFrame(frame, normalized),
      SelectionMode.block => _blockTextForFrame(frame, normalized),
    };
  }

  String _linearTextForFrame(
    TerminalFrameDiff frame,
    TerminalSelection normalized,
  ) {
    final buffer = StringBuffer();
    for (
      var rowIndex = normalized.startRow;
      rowIndex <= normalized.endRow;
      rowIndex += 1
    ) {
      final row = frame.rows.firstWhere(
        (entry) => entry.index == rowIndex,
        orElse: () => const TerminalRow(index: 0, text: ''),
      );
      final start = rowIndex == normalized.startRow ? normalized.startCol : 0;
      final end = rowIndex == normalized.endRow
          ? normalized.endCol
          : row.text.length;
      if (start < row.text.length) {
        buffer.write(row.text.substring(start, end.clamp(0, row.text.length)));
      }
      if (rowIndex != normalized.endRow) {
        buffer.writeln();
      }
    }
    return buffer.toString();
  }

  String _blockTextForFrame(
    TerminalFrameDiff frame,
    TerminalSelection normalized,
  ) {
    final lines = <String>[];
    for (
      var rowIndex = normalized.startRow;
      rowIndex <= normalized.endRow;
      rowIndex += 1
    ) {
      final row = _rowFor(frame, rowIndex);
      final start = normalized.startCol.clamp(0, row.text.length);
      final end = normalized.endCol.clamp(start, row.text.length);
      lines.add(row.text.substring(start, end));
    }
    return lines.join('\n');
  }

  TerminalRow _rowFor(TerminalFrameDiff frame, int rowIndex) {
    return frame.rows.firstWhere(
      (entry) => entry.index == rowIndex,
      orElse: () => const TerminalRow(index: 0, text: ''),
    );
  }
}
