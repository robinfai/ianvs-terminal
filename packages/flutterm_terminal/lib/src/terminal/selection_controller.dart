import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'terminal_models.dart';

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

  void begin(
    TerminalCellPosition cell, {
    bool block = false,
    int viewportStartRow = 0,
  }) {
    _mode = block ? SelectionMode.block : SelectionMode.linear;
    _selection = TerminalSelection(
      startRow: viewportStartRow + cell.row,
      startCol: cell.col,
      endRow: viewportStartRow + cell.row,
      endCol: cell.col,
    );
    notifyListeners();
  }

  void update(TerminalCellPosition cell, {int viewportStartRow = 0}) {
    final current = _selection;
    if (current == null) {
      return;
    }
    _selection = TerminalSelection(
      startRow: current.startRow,
      startCol: current.startCol,
      endRow: viewportStartRow + cell.row,
      endCol: cell.col,
    );
    notifyListeners();
  }

  void clear() {
    _selection = null;
    _mode = SelectionMode.linear;
    notifyListeners();
  }

  TerminalSelection? selectionForFrame(TerminalFrameDiff frame) {
    final normalized = selection;
    if (normalized == null || frame.viewportRows <= 0) {
      return null;
    }
    final frameStartRow = frame.viewportStartRow;
    final frameEndRow = frameStartRow + frame.viewportRows - 1;
    if (normalized.endRow < frameStartRow ||
        normalized.startRow > frameEndRow) {
      return null;
    }

    final startsBeforeFrame = normalized.startRow < frameStartRow;
    final endsAfterFrame = normalized.endRow > frameEndRow;
    return TerminalSelection(
      startRow: math.max(0, normalized.startRow - frameStartRow),
      startCol: _mode == SelectionMode.block || !startsBeforeFrame
          ? normalized.startCol
          : 0,
      endRow: math.min(
        frame.viewportRows - 1,
        normalized.endRow - frameStartRow,
      ),
      endCol: _mode == SelectionMode.block || !endsAfterFrame
          ? normalized.endCol
          : frame.viewportCols,
    );
  }

  String textForFrame(TerminalFrameDiff frame) {
    final normalized = selectionForFrame(frame);
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
      final rowCells = TerminalTextCells.fromText(row.text);
      final start = rowIndex == normalized.startRow ? normalized.startCol : 0;
      final end = rowIndex == normalized.endRow
          ? normalized.endCol
          : rowCells.cellCount;
      if (start < rowCells.cellCount) {
        buffer.write(rowCells.sliceColumns(start, end));
      }
      if (rowIndex != normalized.endRow && !row.wrapped) {
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
      final rowCells = TerminalTextCells.fromText(row.text);
      final start = rowCells.clampColumn(normalized.startCol);
      final end = normalized.endCol.clamp(start, rowCells.cellCount).toInt();
      lines.add(rowCells.sliceColumns(start, end));
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
