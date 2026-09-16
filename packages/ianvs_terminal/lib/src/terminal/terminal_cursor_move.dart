import 'dart:math' as math;

import 'terminal_models.dart';

/// Best-effort arrow navigation, following xterm.js MoveToCell's normal/alternate
/// buffer split. The receiving application remains authoritative about editing.
/// Wide-cell continuations are not counted as separate editing steps. Complex
/// graphemes can still differ from the receiving application's editing units.
String terminalCursorMoveSequence(
  TerminalFrameDiff frame,
  TerminalCellPosition target,
) {
  final cols = frame.viewportCols;
  final rows = frame.viewportRows;
  if (cols <= 0 ||
      rows <= 0 ||
      frame.scrollbackOffset != 0 ||
      frame.modes.mouseMode != 'off' ||
      target.row < 0 ||
      target.row >= rows ||
      target.col < 0 ||
      target.col >= cols ||
      frame.cursor.row < 0 ||
      frame.cursor.row >= rows) {
    return '';
  }
  int? source(int row) {
    final start = frame.mappedSourceRowForViewportRow(row);
    final end = frame.mappedSourceEndRowForViewportRow(row);
    if (start == null ||
        start != end ||
        frame.blocks.any((block) => block.folded && block.startRow == row)) {
      return null;
    }
    return start;
  }

  final startRow = source(frame.cursor.row);
  final endRow = source(target.row);
  if (startRow == null || endRow == null) return '';
  // Source rows are relative to retained history (or the alternate buffer).
  // globalBottomRow is a lifetime counter and cannot be compared with them.
  // At scrollbackOffset == 0, the last projected row is the live screen bottom.
  final screenBottom = frame.mappedSourceEndRowForViewportRow(rows - 1);
  if (screenBottom != null &&
      (endRow > screenBottom || endRow < screenBottom - rows + 1)) {
    return '';
  }
  final textRows = <int, TerminalRow>{};
  for (final row in frame.rows) {
    final mapped = source(row.index);
    if (mapped != null) textRows[mapped] = row;
  }
  final cells = <int, TerminalTextCells>{};
  TerminalTextCells rowCells(int row) => cells.putIfAbsent(
    row,
    () => TerminalTextCells.fromText(textRows[row]?.text ?? ''),
  );
  int snap(int row, int col) {
    final content = rowCells(row);
    var result = col.clamp(0, cols);
    while (result > 0 &&
        result < content.cellCount &&
        content.isContinuationAt(result)) {
      result--;
    }
    return result;
  }

  final startCol = snap(startRow, frame.cursor.col);
  final endCol = snap(endRow, target.col);
  int distance(int fromRow, int fromCol, int toRow, int toCol) {
    final from = fromRow * cols + fromCol;
    final to = toRow * cols + toCol;
    final low = math.min(from, to);
    final high = math.max(from, to);
    var count = high - low;
    for (var row = low ~/ cols; row <= high ~/ cols; row++) {
      final content = rowCells(row);
      for (final cell in content.cells) {
        final offset = row * cols + cell.column;
        if (cell.column < cols &&
            cell.isContinuation &&
            offset >= low &&
            offset < high) {
          count--;
        }
      }
    }
    return count;
  }

  String arrows(String direction, int count) => List.filled(
    count,
    '\x1b${frame.modes.applicationCursor ? 'O' : '['}$direction',
  ).join();
  String horizontal(int fromRow, int fromCol, int toRow, int toCol) => arrows(
    toRow * cols + toCol < fromRow * cols + fromCol ? 'D' : 'C',
    distance(fromRow, fromCol, toRow, toCol),
  );
  if (!frame.modes.alternateScreen) {
    return horizontal(startRow, startCol, endRow, endCol);
  }

  // Our backend marks the line that wraps INTO the next line. xterm.js marks
  // the continuation line instead; consult the previous row here.
  int groupStart(int row) {
    var firstRow = row;
    while (textRows[firstRow - 1]?.wrapped ?? false) {
      firstRow--;
    }
    return firstRow;
  }

  final startGroup = groupStart(startRow);
  final endGroup = groupStart(endRow);
  if (startGroup == endGroup) {
    return horizontal(startRow, startCol, endRow, endCol);
  }
  var verticalSteps = 0;
  for (
    var row = math.min(startGroup, endGroup);
    row < math.max(startGroup, endGroup);
    row++
  ) {
    if (!(textRows[row]?.wrapped ?? false)) verticalSteps++;
  }
  return arrows('D', distance(startRow, startCol, startGroup, startCol)) +
      arrows(endGroup < startGroup ? 'A' : 'B', verticalSteps) +
      horizontal(endGroup, startCol, endRow, endCol);
}
