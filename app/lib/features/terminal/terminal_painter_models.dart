import 'dart:ui';

class TerminalStyleRun {
  const TerminalStyleRun({
    required this.start,
    required this.end,
    this.foreground,
    this.background,
    this.bold = false,
    this.dim = false,
    this.italic = false,
    this.underline = false,
    this.blink = false,
    this.inverse = false,
  });

  final int start;
  final int end;
  final Color? foreground;
  final Color? background;
  final bool bold;
  final bool dim;
  final bool italic;
  final bool underline;
  final bool blink;
  final bool inverse;

  factory TerminalStyleRun.fromJson(Map<String, Object?> json) {
    return TerminalStyleRun(
      start: json['start']! as int,
      end: json['end']! as int,
      foreground: _colorFromHex(json['foreground'] as String?),
      background: _colorFromHex(json['background'] as String?),
      bold: json['bold'] as bool? ?? false,
      dim: json['dim'] as bool? ?? false,
      italic: json['italic'] as bool? ?? false,
      underline: json['underline'] as bool? ?? false,
      blink: json['blink'] as bool? ?? false,
      inverse: json['inverse'] as bool? ?? false,
    );
  }
}

class TerminalFrameModes {
  const TerminalFrameModes({
    this.applicationCursor = false,
    this.applicationKeypad = false,
    this.insertMode = false,
    this.originMode = false,
    this.lineFeedNewLineMode = false,
    this.hideCursor = false,
    this.bracketedPaste = false,
    this.focusTracking = false,
    this.charProtected = false,
    this.mouseMode = 'off',
    this.mouseEncoding = 'default',
  });

  final bool applicationCursor;
  final bool applicationKeypad;
  final bool insertMode;
  final bool originMode;
  final bool lineFeedNewLineMode;
  final bool hideCursor;
  final bool bracketedPaste;
  final bool focusTracking;
  final bool charProtected;
  final String mouseMode;
  final String mouseEncoding;

  static const empty = TerminalFrameModes();

  factory TerminalFrameModes.fromJson(Map<String, Object?> json) {
    return TerminalFrameModes(
      applicationCursor: json['application_cursor'] as bool? ?? false,
      applicationKeypad: json['application_keypad'] as bool? ?? false,
      insertMode: json['insert_mode'] as bool? ?? false,
      originMode: json['origin_mode'] as bool? ?? false,
      lineFeedNewLineMode: json['line_feed_new_line_mode'] as bool? ?? false,
      hideCursor: json['hide_cursor'] as bool? ?? false,
      bracketedPaste: json['bracketed_paste'] as bool? ?? false,
      focusTracking: json['focus_tracking'] as bool? ?? false,
      charProtected: json['char_protected'] as bool? ?? false,
      mouseMode: json['mouse_mode'] as String? ?? 'off',
      mouseEncoding: json['mouse_encoding'] as String? ?? 'default',
    );
  }
}

class TerminalRow {
  const TerminalRow({
    required this.index,
    required this.text,
    this.wrapped = false,
    this.styleRuns = const [],
  });

  final int index;
  final String text;
  final bool wrapped;
  final List<TerminalStyleRun> styleRuns;

  factory TerminalRow.fromJson(Map<String, Object?> json) {
    return TerminalRow(
      index: json['index']! as int,
      text: json['text']! as String,
      wrapped: json['wrapped'] as bool? ?? false,
      styleRuns: (json['style_runs'] as List<dynamic>? ?? const [])
          .map(
            (entry) => TerminalStyleRun.fromJson(entry as Map<String, Object?>),
          )
          .toList(),
    );
  }
}

class TerminalCursor {
  const TerminalCursor({
    required this.row,
    required this.col,
    required this.visible,
  });

  final int row;
  final int col;
  final bool visible;

  factory TerminalCursor.fromJson(Map<String, Object?> json) {
    return TerminalCursor(
      row: json['row']! as int,
      col: json['col']! as int,
      visible: json['visible']! as bool,
    );
  }
}

class TerminalSelection {
  const TerminalSelection({
    required this.startRow,
    required this.startCol,
    required this.endRow,
    required this.endCol,
  });

  final int startRow;
  final int startCol;
  final int endRow;
  final int endCol;

  TerminalSelection normalized() {
    if (startRow < endRow || (startRow == endRow && startCol <= endCol)) {
      return this;
    }
    return TerminalSelection(
      startRow: endRow,
      startCol: endCol,
      endRow: startRow,
      endCol: startCol,
    );
  }

  factory TerminalSelection.fromJson(Map<String, Object?> json) {
    return TerminalSelection(
      startRow: json['start_row']! as int,
      startCol: json['start_col']! as int,
      endRow: json['end_row']! as int,
      endCol: json['end_col']! as int,
    );
  }
}

class TerminalDirtyRange {
  const TerminalDirtyRange({required this.start, required this.end});

  final int start;
  final int end;

  factory TerminalDirtyRange.fromJson(Map<String, Object?> json) {
    return TerminalDirtyRange(
      start: json['start']! as int,
      end: json['end']! as int,
    );
  }
}

class TerminalFrameDiff {
  const TerminalFrameDiff({
    required this.rows,
    required this.cursor,
    required this.viewportRows,
    required this.viewportCols,
    required this.dirtyRanges,
    required this.scrollbackOffset,
    required this.scrollbackMaxOffset,
    this.modes = TerminalFrameModes.empty,
    this.selection,
    this.windowTitle,
    this.windowIconName,
  });

  final List<TerminalRow> rows;
  final TerminalCursor cursor;
  final TerminalSelection? selection;
  final int viewportRows;
  final int viewportCols;
  final List<TerminalDirtyRange> dirtyRanges;
  final int scrollbackOffset;
  final int scrollbackMaxOffset;
  final TerminalFrameModes modes;
  final String? windowTitle;
  final String? windowIconName;

  static const empty = TerminalFrameDiff(
    rows: [],
    cursor: TerminalCursor(row: 0, col: 0, visible: false),
    viewportRows: 0,
    viewportCols: 0,
    dirtyRanges: [],
    scrollbackOffset: 0,
    scrollbackMaxOffset: 0,
    modes: TerminalFrameModes.empty,
  );

  factory TerminalFrameDiff.fromJson(Map<String, Object?> json) {
    return TerminalFrameDiff(
      rows: (json['rows'] as List<dynamic>? ?? const [])
          .map((entry) => TerminalRow.fromJson(entry as Map<String, Object?>))
          .toList(),
      cursor: TerminalCursor.fromJson(json['cursor']! as Map<String, Object?>),
      selection: json['selection'] == null
          ? null
          : TerminalSelection.fromJson(
              json['selection']! as Map<String, Object?>,
            ),
      viewportRows: json['viewport_rows']! as int,
      viewportCols: json['viewport_cols']! as int,
      dirtyRanges: (json['dirty_ranges'] as List<dynamic>? ?? const [])
          .map(
            (entry) =>
                TerminalDirtyRange.fromJson(entry as Map<String, Object?>),
          )
          .toList(),
      scrollbackOffset: json['scrollback_offset'] as int? ?? 0,
      scrollbackMaxOffset: json['scrollback_max_offset'] as int? ?? 0,
      modes: json['modes'] == null
          ? TerminalFrameModes.empty
          : TerminalFrameModes.fromJson(json['modes']! as Map<String, Object?>),
      windowTitle: json['window_title'] as String?,
      windowIconName: json['window_icon_name'] as String?,
    );
  }
}

class TerminalCellPosition {
  const TerminalCellPosition(this.row, this.col);

  final int row;
  final int col;
}

class TerminalTextCell {
  const TerminalTextCell({
    required this.column,
    required this.text,
    required this.codeUnitStart,
    required this.codeUnitEnd,
  });

  final int column;
  final String text;
  final int codeUnitStart;
  final int codeUnitEnd;
}

class TerminalTextCells {
  TerminalTextCells._({
    required this.text,
    required List<TerminalTextCell> cells,
  }) : cells = List<TerminalTextCell>.unmodifiable(cells);

  factory TerminalTextCells.fromText(String text) {
    final cells = <TerminalTextCell>[];
    var codeUnitOffset = 0;
    var column = 0;

    for (final rune in text.runes) {
      final runeText = String.fromCharCode(rune);
      final nextOffset = codeUnitOffset + runeText.length;
      cells.add(
        TerminalTextCell(
          column: column,
          text: runeText,
          codeUnitStart: codeUnitOffset,
          codeUnitEnd: nextOffset,
        ),
      );
      codeUnitOffset = nextOffset;
      column += 1;
    }

    return TerminalTextCells._(text: text, cells: cells);
  }

  final String text;
  final List<TerminalTextCell> cells;

  int get cellCount => cells.length;

  int clampColumn(int value) => value.clamp(0, cellCount).toInt();

  String sliceColumns(int start, int end) {
    final clampedStart = clampColumn(start);
    final clampedEnd = end.clamp(clampedStart, cellCount).toInt();
    if (clampedStart >= clampedEnd) {
      return '';
    }

    return text.substring(
      cells[clampedStart].codeUnitStart,
      cells[clampedEnd - 1].codeUnitEnd,
    );
  }
}

Color? _colorFromHex(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  final normalized = value.replaceFirst('#', '');
  return Color(int.parse('FF$normalized', radix: 16));
}
