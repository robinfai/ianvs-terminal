import 'package:flutter/foundation.dart';

import 'terminal_painter_models.dart';

class SelectionController extends ChangeNotifier {
  TerminalSelection? _selection;

  TerminalSelection? get selection => _selection?.normalized();

  void begin(TerminalCellPosition cell) {
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
    notifyListeners();
  }

  String textForFrame(TerminalFrameDiff frame) {
    final normalized = selection;
    if (normalized == null) {
      return '';
    }
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
}
