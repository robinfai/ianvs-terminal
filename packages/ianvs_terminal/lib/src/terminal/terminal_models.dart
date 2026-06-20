import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

enum TerminalFrameKind { snapshot, delta }

const int _maxInlineImageDecodedBytes = 4 * 1024 * 1024;
const int _maxInlineImageEncodedLength =
    ((_maxInlineImageDecodedBytes + 2) ~/ 3) * 4;
const int _maxFrameViewportRows = 512;
const int _maxFrameViewportCols = 512;

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
    final run = TerminalStyleRun.tryFromJson(json);
    if (run == null) {
      throw const FormatException('Invalid terminal style run payload');
    }
    return run;
  }

  static TerminalStyleRun? tryFromJson(Map<String, Object?> json) {
    final start = _intOrNullFromJson(json['start']);
    final end = _intOrNullFromJson(json['end']);
    if (start == null || start < 0 || end == null || end <= start) {
      return null;
    }
    return TerminalStyleRun(
      start: start,
      end: end,
      foreground: _colorFromHex(_stringFromJson(json['foreground'])),
      background: _colorFromHex(_stringFromJson(json['background'])),
      bold: _boolFromJson(json['bold'], fallback: false),
      dim: _boolFromJson(json['dim'], fallback: false),
      italic: _boolFromJson(json['italic'], fallback: false),
      underline: _boolFromJson(json['underline'], fallback: false),
      blink: _boolFromJson(json['blink'], fallback: false),
      inverse: _boolFromJson(json['inverse'], fallback: false),
    );
  }
}

class TerminalFrameModes {
  const TerminalFrameModes({
    this.alternateScreen = false,
    this.alternateScroll = false,
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

  final bool alternateScreen;
  final bool alternateScroll;
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
      alternateScreen: _boolFromJson(json['alternate_screen'], fallback: false),
      alternateScroll: _boolFromJson(json['alternate_scroll'], fallback: false),
      applicationCursor: _boolFromJson(
        json['application_cursor'],
        fallback: false,
      ),
      applicationKeypad: _boolFromJson(
        json['application_keypad'],
        fallback: false,
      ),
      insertMode: _boolFromJson(json['insert_mode'], fallback: false),
      originMode: _boolFromJson(json['origin_mode'], fallback: false),
      lineFeedNewLineMode: _boolFromJson(
        json['line_feed_new_line_mode'],
        fallback: false,
      ),
      hideCursor: _boolFromJson(json['hide_cursor'], fallback: false),
      bracketedPaste: _boolFromJson(json['bracketed_paste'], fallback: false),
      focusTracking: _boolFromJson(json['focus_tracking'], fallback: false),
      charProtected: _boolFromJson(json['char_protected'], fallback: false),
      mouseMode: _terminalMouseModeFromJson(json['mouse_mode']),
      mouseEncoding: _terminalMouseEncodingFromJson(json['mouse_encoding']),
    );
  }
}

class TerminalRow {
  const TerminalRow({
    required this.index,
    required this.text,
    this.wrapped = false,
    this.modifiedAt,
    this.styleRuns = const [],
  });

  final int index;
  final String text;
  final bool wrapped;
  final DateTime? modifiedAt;
  final List<TerminalStyleRun> styleRuns;

  factory TerminalRow.fromJson(Map<String, Object?> json) {
    final row = TerminalRow.tryFromJson(json);
    if (row == null) {
      throw const FormatException('Invalid terminal row payload');
    }
    return row;
  }

  static TerminalRow? tryFromJson(Map<String, Object?> json) {
    final index = _intOrNullFromJson(json['index']);
    final text = _stringFromJson(json['text']);
    if (index == null || text == null) {
      return null;
    }
    return TerminalRow(
      index: index,
      text: text,
      wrapped: _boolFromJson(json['wrapped'], fallback: false),
      modifiedAt: _dateTimeFromJson(
        json['modified_at'] ??
            json['modifiedAt'] ??
            json['timestamp'] ??
            json['last_modified'],
      ),
      styleRuns: _jsonListFromJson(
        json['style_runs'],
        TerminalStyleRun.tryFromJson,
      ),
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
    final cursor = TerminalCursor.tryFromJson(json);
    if (cursor == null) {
      throw const FormatException('Invalid terminal cursor payload');
    }
    return cursor;
  }

  static TerminalCursor? tryFromJson(Map<String, Object?> json) {
    final row = _intOrNullFromJson(json['row']);
    final col = _intOrNullFromJson(json['col']);
    final visible = json['visible'];
    if (row == null || row < 0 || col == null || col < 0 || visible is! bool) {
      return null;
    }
    return TerminalCursor(row: row, col: col, visible: visible);
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

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'start_row': startRow,
      'start_col': startCol,
      'end_row': endRow,
      'end_col': endCol,
    };
  }

  factory TerminalSelection.fromJson(Map<String, Object?> json) {
    final selection = TerminalSelection.tryFromJson(json);
    if (selection == null) {
      throw const FormatException('Invalid terminal selection payload');
    }
    return selection;
  }

  static TerminalSelection? tryFromJson(Map<String, Object?> json) {
    final startRow = _intOrNullFromJson(json['start_row']);
    final startCol = _intOrNullFromJson(json['start_col']);
    final endRow = _intOrNullFromJson(json['end_row']);
    final endCol = _intOrNullFromJson(json['end_col']);
    if (startRow == null ||
        startRow < 0 ||
        startCol == null ||
        startCol < 0 ||
        endRow == null ||
        endRow < 0 ||
        endCol == null ||
        endCol < 0) {
      return null;
    }
    return TerminalSelection(
      startRow: startRow,
      startCol: startCol,
      endRow: endRow,
      endCol: endCol,
    );
  }
}

class TerminalDirtyRange {
  const TerminalDirtyRange({required this.start, required this.end});

  final int start;
  final int end;

  factory TerminalDirtyRange.fromJson(Map<String, Object?> json) {
    final range = TerminalDirtyRange.tryFromJson(json);
    if (range == null) {
      throw const FormatException('Invalid terminal dirty range payload');
    }
    return range;
  }

  static TerminalDirtyRange? tryFromJson(Map<String, Object?> json) {
    final start = _intOrNullFromJson(json['start']);
    final end = _intOrNullFromJson(json['end']);
    if (start == null || end == null) {
      return null;
    }
    return TerminalDirtyRange(start: start, end: end);
  }
}

class TerminalHyperlinkRange {
  const TerminalHyperlinkRange({
    required this.row,
    required this.startCol,
    required this.endCol,
    required this.uri,
  });

  final int row;
  final int startCol;
  final int endCol;
  final String uri;

  factory TerminalHyperlinkRange.fromJson(Map<String, Object?> json) {
    final range = TerminalHyperlinkRange.tryFromJson(json);
    if (range == null) {
      throw const FormatException('Invalid terminal hyperlink payload');
    }
    return range;
  }

  static TerminalHyperlinkRange? tryFromJson(Map<String, Object?> json) {
    final row = _intOrNullFromJson(json['row']);
    final startCol = _intOrNullFromJson(json['start_col']);
    final endCol = _intOrNullFromJson(json['end_col']);
    final uri = _nonEmptyTrimmedStringFromJson(json['uri']);
    if (row == null || startCol == null || endCol == null || uri == null) {
      return null;
    }
    if (row < 0 || startCol < 0 || endCol <= startCol) {
      return null;
    }
    return TerminalHyperlinkRange(
      row: row,
      startCol: startCol,
      endCol: endCol,
      uri: uri,
    );
  }
}

class TerminalInlineImage {
  const TerminalInlineImage({
    required this.row,
    required this.col,
    required this.widthCells,
    required this.heightCells,
    required this.bytes,
    this.altText,
  });

  final int row;
  final int col;
  final int widthCells;
  final int heightCells;
  final Uint8List bytes;
  final String? altText;

  factory TerminalInlineImage.fromJson(Map<String, Object?> json) {
    final image = TerminalInlineImage.tryFromJson(json);
    if (image == null) {
      throw const FormatException('Invalid inline image payload');
    }
    return image;
  }

  static TerminalInlineImage? tryFromJson(Map<String, Object?> json) {
    final encoded =
        _stringFromJson(json['data']) ?? _stringFromJson(json['base64']) ?? '';
    if (encoded.isEmpty || encoded.length > _maxInlineImageEncodedLength) {
      return null;
    }
    final Uint8List bytes;
    try {
      bytes = base64.decode(encoded);
    } on FormatException {
      return null;
    }
    if (bytes.isEmpty || bytes.length > _maxInlineImageDecodedBytes) {
      return null;
    }
    final row = _optionalIntFromJson(json['row'], fallback: 0);
    final col = _optionalIntFromJson(
      json['col'] ?? json['column'],
      fallback: 0,
    );
    final widthCells = _optionalIntFromJson(
      json['width_cells'] ?? json['widthCells'],
      fallback: 1,
    );
    final heightCells = _optionalIntFromJson(
      json['height_cells'] ?? json['heightCells'],
      fallback: 1,
    );
    if (row == null ||
        row < 0 ||
        col == null ||
        col < 0 ||
        widthCells == null ||
        widthCells <= 0 ||
        heightCells == null ||
        heightCells <= 0) {
      return null;
    }
    return TerminalInlineImage(
      row: row,
      col: col,
      widthCells: widthCells,
      heightCells: heightCells,
      bytes: bytes,
      altText:
          _stringFromJson(json['alt']) ?? _stringFromJson(json['alt_text']),
    );
  }
}

enum TerminalSearchMode {
  smartCaseSubstring,
  caseSensitiveSubstring,
  caseInsensitiveSubstring,
  caseSensitiveRegex,
  caseInsensitiveRegex;

  String get wireName {
    return switch (this) {
      TerminalSearchMode.smartCaseSubstring => 'smart_case_substring',
      TerminalSearchMode.caseSensitiveSubstring => 'case_sensitive_substring',
      TerminalSearchMode.caseInsensitiveSubstring =>
        'case_insensitive_substring',
      TerminalSearchMode.caseSensitiveRegex => 'case_sensitive_regex',
      TerminalSearchMode.caseInsensitiveRegex => 'case_insensitive_regex',
    };
  }
}

class TerminalSearchResult {
  const TerminalSearchResult({required this.matches, this.errorText});

  final List<TerminalSearchMatch> matches;
  final String? errorText;

  static const empty = TerminalSearchResult(matches: <TerminalSearchMatch>[]);
}

class TerminalSearchMatch {
  const TerminalSearchMatch({
    required this.row,
    required this.startCol,
    required this.endCol,
    required this.text,
    required this.scrollbackOffset,
  });

  final int row;
  final int startCol;
  final int endCol;
  final String text;
  final int scrollbackOffset;

  factory TerminalSearchMatch.fromJson(Map<String, Object?> json) {
    final match = TerminalSearchMatch.tryFromJson(json);
    if (match == null) {
      throw const FormatException('Invalid terminal search match payload');
    }
    return match;
  }

  static TerminalSearchMatch? tryFromJson(Map<String, Object?> json) {
    final row = _intOrNullFromJson(json['row']);
    final startCol = _intOrNullFromJson(json['start_col']);
    final endCol = _intOrNullFromJson(json['end_col']);
    final text = _stringFromJson(json['text']);
    if (row == null ||
        row < 0 ||
        startCol == null ||
        startCol < 0 ||
        endCol == null ||
        endCol <= startCol ||
        text == null ||
        text.isEmpty) {
      return null;
    }
    return TerminalSearchMatch(
      row: row,
      startCol: startCol,
      endCol: endCol,
      text: text,
      scrollbackOffset: _nonNegativeIntFromJson(json['scrollback_offset']),
    );
  }
}

class TerminalFrameDiff {
  const TerminalFrameDiff({
    this.frameKind = TerminalFrameKind.snapshot,
    required this.rows,
    required this.cursor,
    required this.viewportRows,
    required this.viewportCols,
    required this.dirtyRanges,
    required this.scrollbackOffset,
    required this.scrollbackMaxOffset,
    this.viewportStartRow = 0,
    this.viewportRowShift = 0,
    this.modes = TerminalFrameModes.empty,
    this.selection,
    this.windowTitle,
    this.windowIconName,
    this.hyperlinks = const [],
    this.inlineImages = const [],
  });

  final TerminalFrameKind frameKind;
  final List<TerminalRow> rows;
  final TerminalCursor cursor;
  final TerminalSelection? selection;
  final int viewportRows;
  final int viewportCols;
  final List<TerminalDirtyRange> dirtyRanges;
  final int scrollbackOffset;
  final int scrollbackMaxOffset;
  final int viewportStartRow;
  final int viewportRowShift;
  final TerminalFrameModes modes;
  final String? windowTitle;
  final String? windowIconName;
  final List<TerminalHyperlinkRange> hyperlinks;
  final List<TerminalInlineImage> inlineImages;

  static const empty = TerminalFrameDiff(
    frameKind: TerminalFrameKind.snapshot,
    rows: [],
    cursor: TerminalCursor(row: 0, col: 0, visible: false),
    viewportRows: 0,
    viewportCols: 0,
    dirtyRanges: [],
    scrollbackOffset: 0,
    scrollbackMaxOffset: 0,
    viewportRowShift: 0,
    modes: TerminalFrameModes.empty,
  );

  factory TerminalFrameDiff.fromJson(Map<String, Object?> json) {
    final cursorJson = _jsonMapFromJson(json['cursor']);
    final selectionJson = _jsonMapFromJson(json['selection']);
    final modesJson = _jsonMapFromJson(json['modes']);
    final viewportRows = _boundedNonNegativeIntFromJson(
      json['viewport_rows'],
      max: _maxFrameViewportRows,
    );
    final viewportCols = _boundedNonNegativeIntFromJson(
      json['viewport_cols'],
      max: _maxFrameViewportCols,
    );
    final scrollbackMaxOffset = _nonNegativeIntFromJson(
      json['scrollback_max_offset'],
    );
    final scrollbackOffset = _nonNegativeIntFromJson(
      json['scrollback_offset'],
    ).clamp(0, scrollbackMaxOffset).toInt();
    return TerminalFrameDiff(
      frameKind: _terminalFrameKindFromWire(
        _stringFromJson(json['frame_kind']),
      ),
      rows: _jsonListFromJson(
        json['rows'],
        TerminalRow.tryFromJson,
        maxItems: viewportRows,
      ),
      cursor: cursorJson == null
          ? const TerminalCursor(row: 0, col: 0, visible: false)
          : TerminalCursor.tryFromJson(cursorJson) ??
                const TerminalCursor(row: 0, col: 0, visible: false),
      selection: selectionJson == null
          ? null
          : TerminalSelection.tryFromJson(selectionJson),
      viewportRows: viewportRows,
      viewportCols: viewportCols,
      dirtyRanges: _normalizeDirtyRanges(
        _jsonListFromJson(json['dirty_ranges'], TerminalDirtyRange.tryFromJson),
        viewportRows,
      ),
      scrollbackOffset: scrollbackOffset,
      scrollbackMaxOffset: scrollbackMaxOffset,
      viewportStartRow: _nonNegativeIntFromJson(json['viewport_start_row']),
      viewportRowShift: _intFromJson(json['viewport_row_shift'], fallback: 0),
      modes: modesJson == null
          ? TerminalFrameModes.empty
          : TerminalFrameModes.fromJson(modesJson),
      windowTitle: _stringFromJson(json['window_title']),
      windowIconName: _stringFromJson(json['window_icon_name']),
      hyperlinks: _jsonListFromJson(
        json['hyperlinks'],
        TerminalHyperlinkRange.tryFromJson,
      ),
      inlineImages: _inlineImagesFromJson(json['inline_images']),
    );
  }
}

List<TerminalInlineImage> _inlineImagesFromJson(Object? value) {
  return _jsonListFromJson(value, TerminalInlineImage.tryFromJson);
}

List<TerminalDirtyRange> _normalizeDirtyRanges(
  List<TerminalDirtyRange> ranges,
  int viewportRows,
) {
  if (viewportRows <= 0 || ranges.isEmpty) {
    return const <TerminalDirtyRange>[];
  }

  final normalized = <TerminalDirtyRange>[];
  for (final range in ranges) {
    final start = range.start.clamp(0, viewportRows).toInt();
    final end = range.end.clamp(start, viewportRows).toInt();
    if (start < end) {
      normalized.add(TerminalDirtyRange(start: start, end: end));
    }
  }
  return normalized;
}

List<T> _jsonListFromJson<T>(
  Object? value,
  T? Function(Map<String, Object?> json) decode, {
  int? maxItems,
}) {
  if (value is! List) {
    return <T>[];
  }
  final items = <T>[];
  final itemLimit = maxItems?.clamp(0, value.length).toInt();
  for (final entry in value) {
    if (itemLimit != null && items.length >= itemLimit) {
      break;
    }
    final json = _jsonMapFromJson(entry);
    if (json == null) {
      continue;
    }
    final item = decode(json);
    if (item != null) {
      items.add(item);
    }
  }
  return items;
}

Map<String, Object?>? _jsonMapFromJson(Object? value) {
  if (value is! Map) {
    return null;
  }
  final json = <String, Object?>{};
  value.forEach((key, value) {
    if (key is String) {
      json[key] = value;
    }
  });
  return json;
}

class TerminalViewportState {
  const TerminalViewportState({required this.frame});

  final TerminalFrameDiff frame;

  static const empty = TerminalViewportState(frame: TerminalFrameDiff.empty);

  TerminalViewportState applyFrame(
    TerminalFrameDiff nextFrame, {
    DateTime? capturedAt,
  }) {
    return switch (nextFrame.frameKind) {
      TerminalFrameKind.snapshot => applySnapshot(
        nextFrame,
        capturedAt: capturedAt,
      ),
      TerminalFrameKind.delta => applyDelta(nextFrame, capturedAt: capturedAt),
    };
  }

  TerminalViewportState applySnapshot(
    TerminalFrameDiff nextFrame, {
    DateTime? capturedAt,
  }) {
    return TerminalViewportState(
      frame: _normalizeSnapshotFrame(nextFrame, capturedAt: capturedAt),
    );
  }

  TerminalViewportState applyDelta(
    TerminalFrameDiff nextFrame, {
    DateTime? capturedAt,
  }) {
    if (frame.viewportRows <= 0 ||
        frame.viewportCols <= 0 ||
        frame.rows.isEmpty ||
        frame.viewportRows != nextFrame.viewportRows ||
        frame.viewportCols != nextFrame.viewportCols) {
      return applySnapshot(nextFrame, capturedAt: capturedAt);
    }

    final mergedRows = _mergeViewportRows(
      currentRows: _shiftViewportRows(
        rows: frame.rows,
        viewportRows: nextFrame.viewportRows,
        rowShift: nextFrame.viewportRowShift,
      ),
      incomingRows: nextFrame.rows,
      viewportRows: nextFrame.viewportRows,
      modifiedAt: capturedAt,
    );
    final dirtyRanges = _mergeDirtyRangesWithRows(
      dirtyRanges: nextFrame.dirtyRanges,
      rows: nextFrame.rows,
      viewportRows: nextFrame.viewportRows,
    );
    final mergedHyperlinks = _mergeHyperlinks(
      currentRanges: _shiftHyperlinks(
        ranges: frame.hyperlinks,
        viewportRows: nextFrame.viewportRows,
        rowShift: nextFrame.viewportRowShift,
      ),
      incomingRanges: nextFrame.hyperlinks,
      dirtyRanges: dirtyRanges,
      viewportRows: nextFrame.viewportRows,
    );
    final mergedInlineImages = _mergeInlineImages(
      currentImages: _shiftInlineImages(
        images: frame.inlineImages,
        viewportRows: nextFrame.viewportRows,
        rowShift: nextFrame.viewportRowShift,
      ),
      incomingImages: nextFrame.inlineImages,
      dirtyRanges: dirtyRanges,
      viewportRows: nextFrame.viewportRows,
    );

    return TerminalViewportState(
      frame: TerminalFrameDiff(
        frameKind: nextFrame.frameKind,
        rows: mergedRows,
        cursor: nextFrame.cursor,
        selection: nextFrame.selection,
        viewportRows: nextFrame.viewportRows,
        viewportCols: nextFrame.viewportCols,
        dirtyRanges: dirtyRanges,
        scrollbackOffset: nextFrame.scrollbackOffset,
        scrollbackMaxOffset: nextFrame.scrollbackMaxOffset,
        viewportStartRow: nextFrame.viewportStartRow,
        viewportRowShift: nextFrame.viewportRowShift,
        modes: nextFrame.modes,
        windowTitle: nextFrame.windowTitle,
        windowIconName: nextFrame.windowIconName,
        hyperlinks: mergedHyperlinks,
        inlineImages: mergedInlineImages,
      ),
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
    this.columnSpan = 1,
    this.isContinuation = false,
  });

  final int column;
  final String text;
  final int codeUnitStart;
  final int codeUnitEnd;
  final int columnSpan;
  final bool isContinuation;
}

class TerminalTextCells {
  TerminalTextCells._({
    required this.text,
    required List<TerminalTextCell> cells,
  }) : cells = List<TerminalTextCell>.unmodifiable(cells);

  factory TerminalTextCells.fromText(String text) {
    final cells = <TerminalTextCell>[];
    var column = 0;

    for (final grapheme in _terminalGraphemeClusters(text)) {
      final columnSpan = _terminalDisplayWidthForGrapheme(grapheme.text);
      cells.add(
        TerminalTextCell(
          column: column,
          text: grapheme.text,
          codeUnitStart: grapheme.codeUnitStart,
          codeUnitEnd: grapheme.codeUnitEnd,
          columnSpan: columnSpan,
        ),
      );
      for (var continuation = 1; continuation < columnSpan; continuation += 1) {
        cells.add(
          TerminalTextCell(
            column: column + continuation,
            text: '',
            codeUnitStart: grapheme.codeUnitStart,
            codeUnitEnd: grapheme.codeUnitEnd,
            isContinuation: true,
          ),
        );
      }
      column += columnSpan;
    }

    return TerminalTextCells._(text: text, cells: cells);
  }

  final String text;
  final List<TerminalTextCell> cells;

  int get cellCount => cells.length;

  int clampColumn(int value) => value.clamp(0, cellCount).toInt();

  int columnForCodeUnit(int value) {
    final clamped = value.clamp(0, text.length).toInt();
    for (final cell in cells) {
      if (cell.codeUnitEnd > clamped) {
        return cell.column;
      }
    }
    return cellCount;
  }

  int codeUnitForColumn(int value) {
    final clamped = clampColumn(value);
    if (clamped >= cellCount) {
      return text.length;
    }
    return cells[clamped].codeUnitStart;
  }

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
  final trimmed = value.trim();
  final normalized = trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
  if (normalized.length != 6 && normalized.length != 8) {
    return null;
  }
  final parsed = int.tryParse(normalized, radix: 16);
  if (parsed == null) {
    return null;
  }
  return Color(normalized.length == 6 ? 0xFF000000 | parsed : parsed);
}

int _intFromJson(Object? value, {required int fallback}) {
  return _wholeIntFromJson(value) ?? fallback;
}

int? _optionalIntFromJson(Object? value, {required int fallback}) {
  if (value == null) {
    return fallback;
  }
  return _wholeIntFromJson(value);
}

int _nonNegativeIntFromJson(Object? value) {
  final parsed = _intFromJson(value, fallback: 0);
  return parsed < 0 ? 0 : parsed;
}

int _boundedNonNegativeIntFromJson(Object? value, {required int max}) {
  return _nonNegativeIntFromJson(value).clamp(0, max).toInt();
}

int? _intOrNullFromJson(Object? value) {
  return _wholeIntFromJson(value);
}

int? _wholeIntFromJson(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num && value.isFinite) {
    final parsed = value.toInt();
    if (value == parsed) {
      return parsed;
    }
  }
  return null;
}

bool _boolFromJson(Object? value, {required bool fallback}) {
  if (value is bool) {
    return value;
  }
  return fallback;
}

String? _stringFromJson(Object? value) {
  if (value is String) {
    return value;
  }
  return null;
}

String? _nonEmptyTrimmedStringFromJson(Object? value) {
  final text = _stringFromJson(value)?.trim();
  return text == null || text.isEmpty ? null : text;
}

String _terminalMouseModeFromJson(Object? value) {
  final normalized = value is String ? value.trim().toLowerCase() : null;
  return switch (normalized) {
    'normal' => 'normal',
    'button_event' => 'button_event',
    'any_event' => 'any_event',
    _ => 'off',
  };
}

String _terminalMouseEncodingFromJson(Object? value) {
  final normalized = value is String ? value.trim().toLowerCase() : null;
  return switch (normalized) {
    'sgr' => 'sgr',
    'urxvt' => 'urxvt',
    'utf8' => 'utf8',
    _ => 'default',
  };
}

DateTime? _dateTimeFromJson(Object? value) {
  if (value is String) {
    final normalized = value.trim();
    if (normalized.isNotEmpty) {
      return DateTime.tryParse(normalized);
    }
    return null;
  }
  if (value is num && value.isFinite) {
    try {
      final milliseconds = value >= 100000000000
          ? value.toInt()
          : (value * 1000).toInt();
      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    } on Object {
      return null;
    }
  }
  return null;
}

TerminalFrameKind _terminalFrameKindFromWire(String? value) {
  return switch (value?.trim().toLowerCase()) {
    'delta' => TerminalFrameKind.delta,
    _ => TerminalFrameKind.snapshot,
  };
}

TerminalFrameDiff _normalizeSnapshotFrame(
  TerminalFrameDiff frame, {
  DateTime? capturedAt,
}) {
  return TerminalFrameDiff(
    frameKind: TerminalFrameKind.snapshot,
    rows: _normalizeViewportRows(
      rows: frame.rows,
      viewportRows: frame.viewportRows,
      modifiedAt: capturedAt,
    ),
    cursor: frame.cursor,
    selection: frame.selection,
    viewportRows: frame.viewportRows,
    viewportCols: frame.viewportCols,
    dirtyRanges: _fullViewportDirtyRanges(frame.viewportRows),
    scrollbackOffset: frame.scrollbackOffset,
    scrollbackMaxOffset: frame.scrollbackMaxOffset,
    viewportStartRow: frame.viewportStartRow,
    viewportRowShift: 0,
    modes: frame.modes,
    windowTitle: frame.windowTitle,
    windowIconName: frame.windowIconName,
    hyperlinks: frame.hyperlinks
        .where((range) {
          return range.row >= 0 && range.row < frame.viewportRows;
        })
        .toList(growable: false),
    inlineImages: frame.inlineImages
        .where((image) {
          return image.row >= 0 &&
              image.row < frame.viewportRows &&
              image.widthCells > 0 &&
              image.heightCells > 0 &&
              image.bytes.isNotEmpty;
        })
        .toList(growable: false),
  );
}

List<TerminalDirtyRange> _fullViewportDirtyRanges(int viewportRows) {
  if (viewportRows <= 0) {
    return const <TerminalDirtyRange>[];
  }
  return <TerminalDirtyRange>[TerminalDirtyRange(start: 0, end: viewportRows)];
}

List<TerminalDirtyRange> _mergeDirtyRangesWithRows({
  required List<TerminalDirtyRange> dirtyRanges,
  required List<TerminalRow> rows,
  required int viewportRows,
}) {
  final dirtyRows = <int>{};
  for (final range in dirtyRanges) {
    final start = range.start.clamp(0, viewportRows).toInt();
    final end = range.end.clamp(start, viewportRows).toInt();
    for (var row = start; row < end; row += 1) {
      dirtyRows.add(row);
    }
  }
  for (final row in rows) {
    if (row.index >= 0 && row.index < viewportRows) {
      dirtyRows.add(row.index);
    }
  }
  if (dirtyRows.isEmpty) {
    return const <TerminalDirtyRange>[];
  }

  final sortedRows = dirtyRows.toList(growable: false)..sort();
  final ranges = <TerminalDirtyRange>[];
  var start = sortedRows.first;
  var end = start + 1;
  for (final row in sortedRows.skip(1)) {
    if (row == end) {
      end += 1;
      continue;
    }
    ranges.add(TerminalDirtyRange(start: start, end: end));
    start = row;
    end = row + 1;
  }
  ranges.add(TerminalDirtyRange(start: start, end: end));
  return ranges;
}

List<TerminalRow> _normalizeViewportRows({
  required List<TerminalRow> rows,
  required int viewportRows,
  DateTime? modifiedAt,
}) {
  if (viewportRows <= 0) {
    return const <TerminalRow>[];
  }

  final rowsByIndex = <int, TerminalRow>{};
  for (final row in rows) {
    if (row.index < 0 || row.index >= viewportRows) {
      continue;
    }
    rowsByIndex[row.index] = _rowWithFallbackModifiedAt(row, modifiedAt);
  }

  return List<TerminalRow>.generate(viewportRows, (index) {
    return rowsByIndex[index] ?? TerminalRow(index: index, text: '');
  }, growable: false);
}

List<TerminalRow> _mergeViewportRows({
  required List<TerminalRow> currentRows,
  required List<TerminalRow> incomingRows,
  required int viewportRows,
  DateTime? modifiedAt,
}) {
  final normalizedCurrent = _normalizeViewportRows(
    rows: currentRows,
    viewportRows: viewportRows,
  );
  if (incomingRows.isEmpty) {
    return normalizedCurrent;
  }

  final rowsByIndex = <int, TerminalRow>{};
  for (final row in incomingRows) {
    if (row.index < 0 || row.index >= viewportRows) {
      continue;
    }
    rowsByIndex[row.index] = _rowWithFallbackModifiedAt(row, modifiedAt);
  }

  return List<TerminalRow>.generate(viewportRows, (index) {
    return rowsByIndex[index] ?? normalizedCurrent[index];
  }, growable: false);
}

List<TerminalRow> _shiftViewportRows({
  required List<TerminalRow> rows,
  required int viewportRows,
  required int rowShift,
}) {
  final normalizedRows = _normalizeViewportRows(
    rows: rows,
    viewportRows: viewportRows,
  );
  if (rowShift == 0) {
    return normalizedRows;
  }

  return List<TerminalRow>.generate(viewportRows, (index) {
    final previousIndex = index - rowShift;
    if (previousIndex < 0 || previousIndex >= viewportRows) {
      return TerminalRow(index: index, text: '');
    }
    final sourceRow = normalizedRows[previousIndex];
    return TerminalRow(
      index: index,
      text: sourceRow.text,
      wrapped: sourceRow.wrapped,
      modifiedAt: sourceRow.modifiedAt,
      styleRuns: sourceRow.styleRuns,
    );
  }, growable: false);
}

TerminalRow _rowWithFallbackModifiedAt(TerminalRow row, DateTime? modifiedAt) {
  if (row.modifiedAt != null || modifiedAt == null || row.text.trim().isEmpty) {
    return row;
  }
  return TerminalRow(
    index: row.index,
    text: row.text,
    wrapped: row.wrapped,
    modifiedAt: modifiedAt,
    styleRuns: row.styleRuns,
  );
}

List<TerminalHyperlinkRange> _mergeHyperlinks({
  required List<TerminalHyperlinkRange> currentRanges,
  required List<TerminalHyperlinkRange> incomingRanges,
  required List<TerminalDirtyRange> dirtyRanges,
  required int viewportRows,
}) {
  final dirtyRows = <int>{
    for (final range in dirtyRanges)
      for (var row = range.start; row < range.end; row += 1)
        if (row >= 0 && row < viewportRows) row,
  };
  if (dirtyRows.isEmpty) {
    return currentRanges
        .where((range) => range.row >= 0 && range.row < viewportRows)
        .toList(growable: false);
  }

  final merged = <TerminalHyperlinkRange>[
    for (final range in currentRanges)
      if (!dirtyRows.contains(range.row) &&
          range.row >= 0 &&
          range.row < viewportRows)
        range,
    for (final range in incomingRanges)
      if (range.row >= 0 && range.row < viewportRows) range,
  ];
  merged.sort((left, right) {
    final byRow = left.row.compareTo(right.row);
    if (byRow != 0) {
      return byRow;
    }
    final byStart = left.startCol.compareTo(right.startCol);
    if (byStart != 0) {
      return byStart;
    }
    return left.endCol.compareTo(right.endCol);
  });
  return merged;
}

List<TerminalHyperlinkRange> _shiftHyperlinks({
  required List<TerminalHyperlinkRange> ranges,
  required int viewportRows,
  required int rowShift,
}) {
  if (rowShift == 0) {
    return ranges
        .where((range) => range.row >= 0 && range.row < viewportRows)
        .toList(growable: false);
  }

  final shifted = <TerminalHyperlinkRange>[];
  for (final range in ranges) {
    final nextRow = range.row + rowShift;
    if (nextRow < 0 || nextRow >= viewportRows) {
      continue;
    }
    shifted.add(
      TerminalHyperlinkRange(
        row: nextRow,
        startCol: range.startCol,
        endCol: range.endCol,
        uri: range.uri,
      ),
    );
  }
  return shifted;
}

List<TerminalInlineImage> _mergeInlineImages({
  required List<TerminalInlineImage> currentImages,
  required List<TerminalInlineImage> incomingImages,
  required List<TerminalDirtyRange> dirtyRanges,
  required int viewportRows,
}) {
  final dirtyRows = <int>{
    for (final range in dirtyRanges)
      for (var row = range.start; row < range.end; row += 1)
        if (row >= 0 && row < viewportRows) row,
  };
  bool imageTouchesDirtyRows(TerminalInlineImage image) {
    final start = image.row.clamp(0, viewportRows).toInt();
    final end = (image.row + image.heightCells)
        .clamp(start, viewportRows)
        .toInt();
    for (var row = start; row < end; row += 1) {
      if (dirtyRows.contains(row)) {
        return true;
      }
    }
    return false;
  }

  final merged = <TerminalInlineImage>[
    for (final image in currentImages)
      if (!_inlineImageInvalid(image, viewportRows) &&
          (dirtyRows.isEmpty || !imageTouchesDirtyRows(image)))
        image,
    for (final image in incomingImages)
      if (!_inlineImageInvalid(image, viewportRows)) image,
  ];
  merged.sort((left, right) {
    final byRow = left.row.compareTo(right.row);
    if (byRow != 0) {
      return byRow;
    }
    return left.col.compareTo(right.col);
  });
  return merged;
}

List<TerminalInlineImage> _shiftInlineImages({
  required List<TerminalInlineImage> images,
  required int viewportRows,
  required int rowShift,
}) {
  final shifted = <TerminalInlineImage>[];
  for (final image in images) {
    final nextRow = image.row + rowShift;
    final shiftedImage = TerminalInlineImage(
      row: nextRow,
      col: image.col,
      widthCells: image.widthCells,
      heightCells: image.heightCells,
      bytes: image.bytes,
      altText: image.altText,
    );
    if (_inlineImageInvalid(shiftedImage, viewportRows)) {
      continue;
    }
    shifted.add(shiftedImage);
  }
  return shifted;
}

bool _inlineImageInvalid(TerminalInlineImage image, int viewportRows) {
  return image.row < 0 ||
      image.row >= viewportRows ||
      image.col < 0 ||
      image.widthCells <= 0 ||
      image.heightCells <= 0 ||
      image.bytes.isEmpty;
}

int _terminalDisplayWidthForGrapheme(String grapheme) {
  var width = 0;
  for (final rune in grapheme.runes) {
    if (_isZeroWidthRune(rune)) {
      continue;
    }
    final runeWidth = _isWideRune(rune) ? 2 : 1;
    if (runeWidth > width) {
      width = runeWidth;
    }
  }
  return width == 0 ? 1 : width;
}

List<_TerminalGraphemeCluster> _terminalGraphemeClusters(String text) {
  final clusters = <_TerminalGraphemeCluster>[];
  final buffer = StringBuffer();
  var clusterStart = 0;
  var codeUnitOffset = 0;
  var previousWasJoiner = false;
  var regionalIndicatorRunLength = 0;

  void flushCurrentCluster() {
    if (buffer.isEmpty) {
      return;
    }
    clusters.add(
      _TerminalGraphemeCluster(
        text: buffer.toString(),
        codeUnitStart: clusterStart,
        codeUnitEnd: codeUnitOffset,
      ),
    );
    buffer.clear();
    previousWasJoiner = false;
  }

  for (final rune in text.runes) {
    final runeText = String.fromCharCode(rune);
    final isRegionalIndicator = _isRegionalIndicatorRune(rune);
    final attachesToPrevious =
        buffer.isNotEmpty &&
        (_isZeroWidthRune(rune) ||
            previousWasJoiner ||
            (isRegionalIndicator && regionalIndicatorRunLength.isOdd));
    if (!attachesToPrevious) {
      flushCurrentCluster();
      clusterStart = codeUnitOffset;
      regionalIndicatorRunLength = 0;
    }
    buffer.write(runeText);
    codeUnitOffset += runeText.length;
    previousWasJoiner = rune == 0x200D;
    regionalIndicatorRunLength = isRegionalIndicator
        ? regionalIndicatorRunLength + 1
        : 0;
  }
  flushCurrentCluster();
  return clusters;
}

bool _isZeroWidthRune(int rune) {
  return (rune >= 0x0000 && rune <= 0x001F) ||
      (rune >= 0x007F && rune <= 0x009F) ||
      rune == 0x200C ||
      rune == 0x200D ||
      (rune >= 0x0300 && rune <= 0x036F) ||
      (rune >= 0x0483 && rune <= 0x0489) ||
      (rune >= 0x0591 && rune <= 0x05BD) ||
      rune == 0x05BF ||
      (rune >= 0x05C1 && rune <= 0x05C2) ||
      rune == 0x05C4 ||
      rune == 0x05C5 ||
      rune == 0x05C7 ||
      (rune >= 0x0610 && rune <= 0x061A) ||
      (rune >= 0x064B && rune <= 0x065F) ||
      rune == 0x0670 ||
      (rune >= 0x06D6 && rune <= 0x06ED) ||
      (rune >= 0x0711 && rune <= 0x0711) ||
      (rune >= 0x0730 && rune <= 0x074A) ||
      (rune >= 0x07A6 && rune <= 0x07B0) ||
      (rune >= 0x07EB && rune <= 0x07F3) ||
      (rune >= 0x0816 && rune <= 0x0819) ||
      (rune >= 0x081B && rune <= 0x0823) ||
      (rune >= 0x0825 && rune <= 0x0827) ||
      (rune >= 0x0829 && rune <= 0x082D) ||
      (rune >= 0x0859 && rune <= 0x085B) ||
      (rune >= 0x08D3 && rune <= 0x08E1) ||
      (rune >= 0x08E3 && rune <= 0x0902) ||
      rune == 0x093A ||
      rune == 0x093C ||
      (rune >= 0x0941 && rune <= 0x0948) ||
      rune == 0x094D ||
      (rune >= 0x0951 && rune <= 0x0957) ||
      (rune >= 0x0962 && rune <= 0x0963) ||
      (rune >= 0x0981 && rune <= 0x0981) ||
      rune == 0x09BC ||
      rune == 0x09CD ||
      (rune >= 0x09E2 && rune <= 0x09E3) ||
      rune == 0x0A01 ||
      rune == 0x0A02 ||
      rune == 0x0A3C ||
      rune == 0x0A41 ||
      rune == 0x0A42 ||
      rune == 0x0A47 ||
      rune == 0x0A48 ||
      rune == 0x0A4B ||
      rune == 0x0A4D ||
      (rune >= 0x0A51 && rune <= 0x0A51) ||
      (rune >= 0x0A70 && rune <= 0x0A71) ||
      (rune >= 0x0A75 && rune <= 0x0A75) ||
      (rune >= 0x0A81 && rune <= 0x0A82) ||
      rune == 0x0ABC ||
      rune == 0x0AC1 ||
      rune == 0x0AC5 ||
      rune == 0x0AC7 ||
      rune == 0x0AC8 ||
      rune == 0x0ACD ||
      (rune >= 0x0AE2 && rune <= 0x0AE3) ||
      (rune >= 0x0AFA && rune <= 0x0AFF) ||
      (rune >= 0x0B01 && rune <= 0x0B01) ||
      rune == 0x0B3C ||
      rune == 0x0B3F ||
      rune == 0x0B41 ||
      rune == 0x0B42 ||
      rune == 0x0B4D ||
      (rune >= 0x0B55 && rune <= 0x0B56) ||
      (rune >= 0x0B62 && rune <= 0x0B63) ||
      rune == 0x0B82 ||
      rune == 0x0BC0 ||
      rune == 0x0BCD ||
      (rune >= 0x0C00 && rune <= 0x0C00) ||
      rune == 0x0C04 ||
      (rune >= 0x0C3E && rune <= 0x0C40) ||
      (rune >= 0x0C46 && rune <= 0x0C48) ||
      (rune >= 0x0C4A && rune <= 0x0C4D) ||
      (rune >= 0x0C55 && rune <= 0x0C56) ||
      (rune >= 0x0C62 && rune <= 0x0C63) ||
      (rune >= 0x0C81 && rune <= 0x0C81) ||
      rune == 0x0CBC ||
      rune == 0x0CBF ||
      rune == 0x0CC6 ||
      rune == 0x0CCC ||
      rune == 0x0CCD ||
      (rune >= 0x0CE2 && rune <= 0x0CE3) ||
      (rune >= 0x0D00 && rune <= 0x0D01) ||
      (rune >= 0x0D3B && rune <= 0x0D3C) ||
      rune == 0x0D41 ||
      rune == 0x0D42 ||
      rune == 0x0D4D ||
      (rune >= 0x0D62 && rune <= 0x0D63) ||
      rune == 0x0D81 ||
      rune == 0x0DCA ||
      rune == 0x0DD2 ||
      rune == 0x0DD4 ||
      (rune >= 0x0DD6 && rune <= 0x0DD6) ||
      rune == 0x0E31 ||
      (rune >= 0x0E34 && rune <= 0x0E3A) ||
      (rune >= 0x0E47 && rune <= 0x0E4E) ||
      rune == 0x0EB1 ||
      (rune >= 0x0EB4 && rune <= 0x0EBC) ||
      (rune >= 0x0EC8 && rune <= 0x0ECD) ||
      rune == 0x0F18 ||
      rune == 0x0F19 ||
      rune == 0x0F35 ||
      rune == 0x0F37 ||
      rune == 0x0F39 ||
      (rune >= 0x0F71 && rune <= 0x0F7E) ||
      (rune >= 0x0F80 && rune <= 0x0F84) ||
      (rune >= 0x0F86 && rune <= 0x0F87) ||
      (rune >= 0x0F8D && rune <= 0x0F97) ||
      (rune >= 0x0F99 && rune <= 0x0FBC) ||
      rune == 0x0FC6 ||
      (rune >= 0x102D && rune <= 0x1030) ||
      (rune >= 0x1032 && rune <= 0x1037) ||
      rune == 0x1039 ||
      rune == 0x103A ||
      (rune >= 0x103D && rune <= 0x103E) ||
      (rune >= 0x1058 && rune <= 0x1059) ||
      (rune >= 0x105E && rune <= 0x1060) ||
      rune == 0x1071 ||
      (rune >= 0x1072 && rune <= 0x1074) ||
      rune == 0x1082 ||
      (rune >= 0x1085 && rune <= 0x1086) ||
      rune == 0x108D ||
      rune == 0x109D ||
      (rune >= 0x135D && rune <= 0x135F) ||
      (rune >= 0x1712 && rune <= 0x1714) ||
      (rune >= 0x1732 && rune <= 0x1734) ||
      (rune >= 0x1752 && rune <= 0x1753) ||
      (rune >= 0x1772 && rune <= 0x1773) ||
      (rune >= 0x17B4 && rune <= 0x17B5) ||
      (rune >= 0x17B7 && rune <= 0x17BD) ||
      rune == 0x17C6 ||
      (rune >= 0x17C9 && rune <= 0x17D3) ||
      rune == 0x17DD ||
      (rune >= 0x180B && rune <= 0x180F) ||
      (rune >= 0x1885 && rune <= 0x1886) ||
      rune == 0x18A9 ||
      (rune >= 0x1920 && rune <= 0x1922) ||
      (rune >= 0x1927 && rune <= 0x1928) ||
      rune == 0x1932 ||
      (rune >= 0x1939 && rune <= 0x193B) ||
      (rune >= 0x1A17 && rune <= 0x1A18) ||
      rune == 0x1A1B ||
      rune == 0x1A56 ||
      (rune >= 0x1A58 && rune <= 0x1A5E) ||
      rune == 0x1A60 ||
      rune == 0x1A62 ||
      (rune >= 0x1A65 && rune <= 0x1A6C) ||
      (rune >= 0x1A73 && rune <= 0x1A7C) ||
      rune == 0x1A7F ||
      (rune >= 0x1AB0 && rune <= 0x1ACE) ||
      (rune >= 0x1B00 && rune <= 0x1B03) ||
      rune == 0x1B34 ||
      rune == 0x1B36 ||
      (rune >= 0x1B37 && rune <= 0x1B3A) ||
      rune == 0x1B3C ||
      rune == 0x1B42 ||
      (rune >= 0x1B6B && rune <= 0x1B73) ||
      (rune >= 0x1B80 && rune <= 0x1B81) ||
      (rune >= 0x1BA2 && rune <= 0x1BA5) ||
      (rune >= 0x1BA8 && rune <= 0x1BA9) ||
      (rune >= 0x1BAB && rune <= 0x1BAD) ||
      rune == 0x1BE6 ||
      (rune >= 0x1BE8 && rune <= 0x1BE9) ||
      rune == 0x1BED ||
      (rune >= 0x1BEF && rune <= 0x1BF1) ||
      (rune >= 0x1C2C && rune <= 0x1C33) ||
      (rune >= 0x1C36 && rune <= 0x1C37) ||
      (rune >= 0x1CD0 && rune <= 0x1CD2) ||
      (rune >= 0x1CD4 && rune <= 0x1CE0) ||
      (rune >= 0x1CE2 && rune <= 0x1CE8) ||
      rune == 0x1CED ||
      rune == 0x1CF4 ||
      rune == 0x1CF8 ||
      rune == 0x1CF9 ||
      (rune >= 0x1DC0 && rune <= 0x1DFF) ||
      (rune >= 0x200B && rune <= 0x200F) ||
      (rune >= 0x202A && rune <= 0x202E) ||
      (rune >= 0x2060 && rune <= 0x2064) ||
      (rune >= 0x2066 && rune <= 0x206F) ||
      (rune >= 0x20D0 && rune <= 0x20F0) ||
      (rune >= 0xFE00 && rune <= 0xFE0F) ||
      rune == 0xFEFF ||
      (rune >= 0xFFF9 && rune <= 0xFFFB) ||
      (rune >= 0x1F3FB && rune <= 0x1F3FF) ||
      (rune >= 0xE0100 && rune <= 0xE01EF);
}

bool _isWideRune(int rune) {
  return (rune >= 0x1100 && rune <= 0x115F) ||
      rune == 0x2329 ||
      rune == 0x232A ||
      (rune >= 0x2E80 && rune <= 0x303E) ||
      (rune >= 0x3040 && rune <= 0xA4CF) ||
      (rune >= 0xAC00 && rune <= 0xD7A3) ||
      (rune >= 0xF900 && rune <= 0xFAFF) ||
      (rune >= 0xFE10 && rune <= 0xFE19) ||
      (rune >= 0xFE30 && rune <= 0xFE6F) ||
      (rune >= 0xFF00 && rune <= 0xFF60) ||
      (rune >= 0xFFE0 && rune <= 0xFFE6) ||
      (rune >= 0x1F1E6 && rune <= 0x1F1FF) ||
      (rune >= 0x1F300 && rune <= 0x1FAFF) ||
      (rune >= 0x20000 && rune <= 0x2FFFD) ||
      (rune >= 0x30000 && rune <= 0x3FFFD);
}

bool _isRegionalIndicatorRune(int rune) {
  return rune >= 0x1F1E6 && rune <= 0x1F1FF;
}

class _TerminalGraphemeCluster {
  const _TerminalGraphemeCluster({
    required this.text,
    required this.codeUnitStart,
    required this.codeUnitEnd,
  });

  final String text;
  final int codeUnitStart;
  final int codeUnitEnd;
}
