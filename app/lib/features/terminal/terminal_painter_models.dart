import 'dart:ui';

class TerminalStyleRun {
  const TerminalStyleRun({
    required this.start,
    required this.end,
    this.foreground,
    this.background,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.inverse = false,
  });

  final int start;
  final int end;
  final Color? foreground;
  final Color? background;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool inverse;

  factory TerminalStyleRun.fromJson(Map<String, Object?> json) {
    return TerminalStyleRun(
      start: json['start']! as int,
      end: json['end']! as int,
      foreground: _colorFromHex(json['foreground'] as String?),
      background: _colorFromHex(json['background'] as String?),
      bold: json['bold'] as bool? ?? false,
      italic: json['italic'] as bool? ?? false,
      underline: json['underline'] as bool? ?? false,
      inverse: json['inverse'] as bool? ?? false,
    );
  }
}

class TerminalRow {
  const TerminalRow({
    required this.index,
    required this.text,
    this.styleRuns = const [],
  });

  final int index;
  final String text;
  final List<TerminalStyleRun> styleRuns;

  factory TerminalRow.fromJson(Map<String, Object?> json) {
    return TerminalRow(
      index: json['index']! as int,
      text: json['text']! as String,
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

Color? _colorFromHex(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  final normalized = value.replaceFirst('#', '');
  return Color(int.parse('FF$normalized', radix: 16));
}
