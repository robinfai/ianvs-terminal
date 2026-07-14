import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import '../config/terminal_config.dart';
import '../proto/frame_diff.pb.dart' as frame_pb;
import '../transport/terminal_frame_validation_limits.dart';
import '../transport/terminal_wire_compatibility.dart';

enum TerminalFrameKind { snapshot, delta }

enum TerminalPointerShape {
  alias('alias'),
  cell('cell'),
  copy('copy'),
  crosshair('crosshair'),
  basic('default'),
  eastResize('e-resize'),
  eastWestResize('ew-resize'),
  grab('grab'),
  grabbing('grabbing'),
  help('help'),
  move('move'),
  northResize('n-resize'),
  northEastResize('ne-resize'),
  northEastSouthWestResize('nesw-resize'),
  noDrop('no-drop'),
  notAllowed('not-allowed'),
  northSouthResize('ns-resize'),
  northWestResize('nw-resize'),
  northWestSouthEastResize('nwse-resize'),
  pointer('pointer'),
  progress('progress'),
  southResize('s-resize'),
  southEastResize('se-resize'),
  southWestResize('sw-resize'),
  text('text'),
  verticalText('vertical-text'),
  westResize('w-resize'),
  wait('wait'),
  zoomIn('zoom-in'),
  zoomOut('zoom-out');

  const TerminalPointerShape(this.wireName);

  final String wireName;

  static TerminalPointerShape? fromWire(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    for (final shape in values) {
      if (shape.wireName == value) {
        return shape;
      }
    }
    return null;
  }
}

const int _maxInlineImageEncodedLength =
    ((TerminalFrameValidationLimits.maxInlineImageDecodedBytes + 2) ~/ 3) * 4;
const int _maxTerminalFontFamilyBytes = 256;

class TerminalStyleRun {
  const TerminalStyleRun({
    required this.start,
    required this.end,
    this.foreground,
    this.background,
    this.underlineColor,
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
  final Color? underlineColor;
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
      underlineColor: _colorFromHex(_stringFromJson(json['underline_color'])),
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
    this.mimePaste = false,
    this.focusTracking = false,
    this.charProtected = false,
    this.mouseMode = 'off',
    this.mouseEncoding = 'default',
    this.kittyKeyboardFlags = 0,
    this.synchronizedOutput = false,
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
  final bool mimePaste;
  final bool focusTracking;
  final bool charProtected;
  final String mouseMode;
  final String mouseEncoding;
  final int kittyKeyboardFlags;
  final bool synchronizedOutput;

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
      mimePaste: _boolFromJson(json['mime_paste'], fallback: false),
      focusTracking: _boolFromJson(json['focus_tracking'], fallback: false),
      charProtected: _boolFromJson(json['char_protected'], fallback: false),
      mouseMode: _terminalMouseModeFromJson(json['mouse_mode']),
      mouseEncoding: _terminalMouseEncodingFromJson(json['mouse_encoding']),
      kittyKeyboardFlags: _nonNegativeIntFromJson(json['kitty_keyboard_flags']),
      synchronizedOutput: _boolFromJson(
        json['synchronized_output'],
        fallback: false,
      ),
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
    this.sourceRow,
    this.sourceEndRow,
  });

  final int index;
  final String text;
  final bool wrapped;
  final DateTime? modifiedAt;
  final List<TerminalStyleRun> styleRuns;
  final int? sourceRow;
  final int? sourceEndRow;

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
    final sourceRow = _optionalNonNegativeIntFromJson(json['source_row']);
    final sourceEndRow = _optionalNonNegativeIntFromJson(
      json['source_end_row'],
    );
    if (sourceRow != null && sourceEndRow != null && sourceEndRow < sourceRow) {
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
        maxEntries: TerminalFrameValidationLimits.maxStyleRunsPerRow,
      ),
      sourceRow: sourceRow ?? sourceEndRow,
      sourceEndRow: sourceEndRow ?? sourceRow,
    );
  }
}

class TerminalBlock {
  const TerminalBlock({
    required this.id,
    required this.startRow,
    required this.endRow,
    required this.sourceStartRow,
    required this.sourceEndRow,
    required this.folded,
    required this.hiddenRows,
    this.blockType,
    this.rendered = false,
  });

  final String id;
  final String? blockType;
  final int startRow;
  final int endRow;
  final int sourceStartRow;
  final int sourceEndRow;
  final bool folded;
  final bool rendered;
  final int hiddenRows;

  bool get canFold => sourceEndRow > sourceStartRow;

  static TerminalBlock? tryFromJson(Map<String, Object?> json) {
    final id = _nonEmptyTrimmedStringFromJson(json['id']);
    final blockType = _nonEmptyTrimmedStringFromJson(
      json['block_type'] ?? json['type'],
    );
    final startRow = _intOrNullFromJson(json['start_row']);
    final endRow = _intOrNullFromJson(json['end_row']);
    final sourceStartRow = _intOrNullFromJson(json['source_start_row']);
    final sourceEndRow = _intOrNullFromJson(json['source_end_row']);
    if (id == null ||
        id.runes.length > TerminalFrameValidationLimits.maxBlockIdChars ||
        (blockType != null &&
            blockType.runes.length >
                TerminalFrameValidationLimits.maxBlockTypeChars) ||
        startRow == null ||
        startRow < 0 ||
        endRow == null ||
        endRow < startRow ||
        sourceStartRow == null ||
        sourceStartRow < 0 ||
        sourceEndRow == null ||
        sourceEndRow < sourceStartRow) {
      return null;
    }
    return TerminalBlock(
      id: id,
      blockType: blockType,
      startRow: startRow,
      endRow: endRow,
      sourceStartRow: sourceStartRow,
      sourceEndRow: sourceEndRow,
      folded: _boolFromJson(json['folded'], fallback: false),
      rendered: _boolFromJson(json['rendered'], fallback: false),
      hiddenRows: _nonNegativeIntFromJson(json['hidden_rows']),
    );
  }
}

enum TerminalInlineButtonKind { copy, custom }

class TerminalInlineButton {
  const TerminalInlineButton({
    required this.id,
    required this.kind,
    required this.row,
    required this.col,
    required this.valid,
    this.code,
    this.icon,
    this.blockId,
    this.widthCells = TerminalFrameValidationLimits.inlineButtonWidthCells,
  });

  final int id;
  final TerminalInlineButtonKind kind;
  final int row;
  final int col;
  final int? code;
  final String? icon;
  final String? blockId;
  final bool valid;
  final int widthCells;

  static TerminalInlineButton? tryFromJson(Map<String, Object?> json) {
    final id = _intOrNullFromJson(json['id']);
    final kind = switch (_stringFromJson(json['kind'])) {
      'copy' => TerminalInlineButtonKind.copy,
      'custom' => TerminalInlineButtonKind.custom,
      _ => null,
    };
    final row = _intOrNullFromJson(json['row']);
    final col = _intOrNullFromJson(json['col']);
    final widthCells = _intOrNullFromJson(json['width_cells']);
    final code = _intOrNullFromJson(json['code']);
    final icon = _nonEmptyTrimmedStringFromJson(json['icon']);
    final blockId = _nonEmptyTrimmedStringFromJson(
      json['block_id'] ?? json['block'],
    );
    if (id == null ||
        id <= 0 ||
        kind == null ||
        row == null ||
        row < 0 ||
        col == null ||
        col < 0 ||
        widthCells != TerminalFrameValidationLimits.inlineButtonWidthCells ||
        (kind == TerminalInlineButtonKind.custom &&
            (code == null ||
                code <= 0 ||
                icon == null ||
                icon.runes.length >
                    TerminalFrameValidationLimits.maxInlineButtonIconChars)) ||
        (kind == TerminalInlineButtonKind.copy &&
            (blockId == null ||
                blockId.runes.length >
                    TerminalFrameValidationLimits.maxBlockIdChars))) {
      return null;
    }
    return TerminalInlineButton(
      id: id,
      kind: kind,
      row: row,
      col: col,
      code: kind == TerminalInlineButtonKind.custom ? code : null,
      icon: kind == TerminalInlineButtonKind.custom ? icon : null,
      blockId: kind == TerminalInlineButtonKind.copy ? blockId : null,
      valid: _boolFromJson(json['valid'], fallback: false),
      widthCells: widthCells!,
    );
  }
}

class TerminalInlineButtonActivation {
  const TerminalInlineButtonActivation._({
    required this.activated,
    this.kind,
    this.text,
  });

  const TerminalInlineButtonActivation.rejected() : this._(activated: false);

  final bool activated;
  final TerminalInlineButtonKind? kind;
  final String? text;

  static TerminalInlineButtonActivation fromJson(Map<String, Object?> json) {
    if (json['activated'] != true) {
      return const TerminalInlineButtonActivation.rejected();
    }
    return switch (_stringFromJson(json['kind'])) {
      'copy' => TerminalInlineButtonActivation._(
        activated: true,
        kind: TerminalInlineButtonKind.copy,
        text: _stringFromJson(json['text']),
      ),
      'custom' => const TerminalInlineButtonActivation._(
        activated: true,
        kind: TerminalInlineButtonKind.custom,
      ),
      _ => const TerminalInlineButtonActivation.rejected(),
    };
  }
}

class TerminalCursor {
  const TerminalCursor({
    required this.row,
    required this.col,
    required this.visible,
    this.highlightLine = false,
    this.shape,
    this.blink,
  });

  final int row;
  final int col;
  final bool visible;
  final bool highlightLine;
  final TerminalCursorShape? shape;
  final bool? blink;

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
    return TerminalCursor(
      row: row,
      col: col,
      visible: visible,
      highlightLine: json['highlight_line'] is bool
          ? json['highlight_line']! as bool
          : false,
      shape: _terminalCursorShapeFromWire(json['shape']),
      blink: json['blink'] is bool ? json['blink']! as bool : null,
    );
  }
}

TerminalCursorShape? _terminalCursorShapeFromWire(Object? value) {
  return switch (value) {
    'block' => TerminalCursorShape.block,
    'underline' => TerminalCursorShape.underline,
    'beam' => TerminalCursorShape.beam,
    _ => null,
  };
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
    this.protocolId,
  });

  final int row;
  final int startCol;
  final int endCol;
  final String uri;
  final String? protocolId;

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
      protocolId: _nonEmptyTrimmedStringFromJson(json['protocol_id']),
    );
  }
}

class TerminalSizedTextPlacement {
  const TerminalSizedTextPlacement({
    required this.text,
    required this.row,
    required this.col,
    required this.widthCells,
    required this.heightCells,
    required this.sourceRowOffsetCells,
    required this.visibleHeightCells,
    required this.scale,
    required this.subscaleN,
    required this.subscaleD,
    required this.verticalAlign,
    required this.horizontalAlign,
    required this.naturalWidth,
    this.foreground,
    this.background,
    this.underlineColor,
    this.bold = false,
    this.dim = false,
    this.italic = false,
    this.underline = false,
    this.blink = false,
    this.inverse = false,
  });

  final String text;
  final int row;
  final int col;
  final int widthCells;
  final int heightCells;
  final int sourceRowOffsetCells;
  final int visibleHeightCells;
  final int scale;
  final int subscaleN;
  final int subscaleD;
  final int verticalAlign;
  final int horizontalAlign;
  final bool naturalWidth;
  final Color? foreground;
  final Color? background;
  final Color? underlineColor;
  final bool bold;
  final bool dim;
  final bool italic;
  final bool underline;
  final bool blink;
  final bool inverse;

  static TerminalSizedTextPlacement? tryFromJson(Map<String, Object?> json) {
    final text = _stringFromJson(json['text']);
    final row = _intOrNullFromJson(json['row']);
    final col = _intOrNullFromJson(json['col']);
    final widthCells = _intOrNullFromJson(json['width_cells']);
    final heightCells = _intOrNullFromJson(json['height_cells']);
    final sourceRowOffsetCells = _nonNegativeIntFromJson(
      json['source_row_offset_cells'],
    );
    final visibleHeightCells = _intOrNullFromJson(json['visible_height_cells']);
    final scale = _intOrNullFromJson(json['scale']);
    final subscaleN = _nonNegativeIntFromJson(json['subscale_n']);
    final subscaleD = _nonNegativeIntFromJson(json['subscale_d']);
    final verticalAlign = _nonNegativeIntFromJson(json['vertical_align']);
    final horizontalAlign = _nonNegativeIntFromJson(json['horizontal_align']);
    if (text == null ||
        text.isEmpty ||
        text.length > 4096 ||
        utf8.encode(text).length > 4096 ||
        row == null ||
        row < 0 ||
        col == null ||
        col < 0 ||
        widthCells == null ||
        widthCells <= 0 ||
        widthCells > 49 ||
        heightCells == null ||
        heightCells <= 0 ||
        heightCells > 7 ||
        sourceRowOffsetCells >= heightCells ||
        visibleHeightCells == null ||
        visibleHeightCells <= 0 ||
        sourceRowOffsetCells + visibleHeightCells > heightCells ||
        scale == null ||
        scale < 1 ||
        scale > 7 ||
        subscaleN > 15 ||
        subscaleD > 15 ||
        (subscaleD > 0 && subscaleN >= subscaleD) ||
        verticalAlign > 2 ||
        horizontalAlign > 2) {
      return null;
    }
    return TerminalSizedTextPlacement(
      text: text,
      row: row,
      col: col,
      widthCells: widthCells,
      heightCells: heightCells,
      sourceRowOffsetCells: sourceRowOffsetCells,
      visibleHeightCells: visibleHeightCells,
      scale: scale,
      subscaleN: subscaleD == 0 ? 0 : subscaleN,
      subscaleD: subscaleD,
      verticalAlign: verticalAlign,
      horizontalAlign: horizontalAlign,
      naturalWidth: _boolFromJson(json['natural_width'], fallback: false),
      foreground: _colorFromHex(_stringFromJson(json['foreground'])),
      background: _colorFromHex(_stringFromJson(json['background'])),
      underlineColor: _colorFromHex(_stringFromJson(json['underline_color'])),
      bold: _boolFromJson(json['bold'], fallback: false),
      dim: _boolFromJson(json['dim'], fallback: false),
      italic: _boolFromJson(json['italic'], fallback: false),
      underline: _boolFromJson(json['underline'], fallback: false),
      blink: _boolFromJson(json['blink'], fallback: false),
      inverse: _boolFromJson(json['inverse'], fallback: false),
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
    if (bytes.isEmpty ||
        bytes.length >
            TerminalFrameValidationLimits.maxInlineImageDecodedBytes) {
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

class TerminalGraphicAssetKey {
  const TerminalGraphicAssetKey({required this.id, required this.version});

  final int id;
  final int version;

  factory TerminalGraphicAssetKey.fromJson(Map<String, Object?> json) {
    final key = TerminalGraphicAssetKey.tryFromJson(json);
    if (key == null) {
      throw const FormatException('Invalid terminal graphic asset key payload');
    }
    return key;
  }

  static TerminalGraphicAssetKey? tryFromJson(Map<String, Object?> json) {
    final id = _intOrNullFromJson(json['asset_id'] ?? json['id']);
    final version = _intOrNullFromJson(
      json['asset_version'] ?? json['version'],
    );
    if (id == null || id <= 0 || version == null || version <= 0) {
      return null;
    }
    return TerminalGraphicAssetKey(id: id, version: version);
  }

  @override
  bool operator ==(Object other) {
    return other is TerminalGraphicAssetKey &&
        other.id == id &&
        other.version == version;
  }

  @override
  int get hashCode => Object.hash(id, version);
}

class TerminalGraphicPlacement {
  const TerminalGraphicPlacement({
    int? renderId,
    required this.placementId,
    required this.assetKey,
    required this.protocol,
    required this.row,
    required this.col,
    required this.widthPx,
    required this.heightPx,
    required this.widthCells,
    required this.heightCells,
    this.sourceXOffsetPx = 0,
    int? visibleWidthPx,
    this.sourceYOffsetPx = 0,
    int? visibleHeightPx,
    this.zIndex = 0,
    this.xOffsetPx = 0,
    this.yOffsetPx = 0,
    this.preserveAspectRatio = true,
  }) : renderId = renderId ?? placementId,
       visibleWidthPx = visibleWidthPx ?? widthPx - sourceXOffsetPx,
       visibleHeightPx = visibleHeightPx ?? heightPx - sourceYOffsetPx;

  final int renderId;
  final int placementId;
  final TerminalGraphicAssetKey assetKey;
  final String protocol;
  final int row;
  final int col;
  final int widthPx;
  final int heightPx;
  final int widthCells;
  final int heightCells;
  final int sourceXOffsetPx;
  final int visibleWidthPx;
  final int sourceYOffsetPx;
  final int visibleHeightPx;
  final int zIndex;
  final int xOffsetPx;
  final int yOffsetPx;
  final bool preserveAspectRatio;

  factory TerminalGraphicPlacement.fromJson(Map<String, Object?> json) {
    final placement = TerminalGraphicPlacement.tryFromJson(json);
    if (placement == null) {
      throw const FormatException('Invalid terminal graphic placement payload');
    }
    return placement;
  }

  static TerminalGraphicPlacement? tryFromJson(Map<String, Object?> json) {
    final placementId = _intOrNullFromJson(
      json['placement_id'] ?? json['placementId'],
    );
    final renderId = _intOrNullFromJson(json['render_id'] ?? json['renderId']);
    final assetKey = TerminalGraphicAssetKey.tryFromJson(json);
    final protocol = _nonEmptyTrimmedStringFromJson(json['protocol']);
    final row = _intOrNullFromJson(json['row']);
    final col = _intOrNullFromJson(json['col'] ?? json['column']);
    final widthPx = _intOrNullFromJson(json['width_px'] ?? json['widthPx']);
    final heightPx = _intOrNullFromJson(json['height_px'] ?? json['heightPx']);
    final widthCells = _intOrNullFromJson(
      json['width_cells'] ?? json['widthCells'],
    );
    final heightCells = _intOrNullFromJson(
      json['height_cells'] ?? json['heightCells'],
    );
    final sourceXOffsetPx = _nonNegativeIntFromJson(
      json['source_x_offset_px'] ?? json['sourceXOffsetPx'],
    );
    final visibleWidthPx = _intOrNullFromJson(
      json['visible_width_px'] ?? json['visibleWidthPx'],
    );
    final sourceYOffsetPx = _nonNegativeIntFromJson(
      json['source_y_offset_px'] ?? json['sourceYOffsetPx'],
    );
    final visibleHeightPx = _intOrNullFromJson(
      json['visible_height_px'] ?? json['visibleHeightPx'],
    );
    if (placementId == null ||
        placementId < 0 ||
        assetKey == null ||
        protocol == null ||
        row == null ||
        row < 0 ||
        col == null ||
        col < 0 ||
        widthPx == null ||
        widthPx <= 0 ||
        heightPx == null ||
        heightPx <= 0 ||
        widthCells == null ||
        widthCells <= 0 ||
        heightCells == null ||
        heightCells <= 0 ||
        sourceXOffsetPx >= widthPx ||
        (visibleWidthPx != null &&
            (visibleWidthPx <= 0 ||
                visibleWidthPx > widthPx - sourceXOffsetPx)) ||
        sourceYOffsetPx >= heightPx ||
        (visibleHeightPx != null &&
            (visibleHeightPx <= 0 ||
                visibleHeightPx > heightPx - sourceYOffsetPx))) {
      return null;
    }
    return TerminalGraphicPlacement(
      renderId: renderId == null || renderId <= 0 ? placementId : renderId,
      placementId: placementId,
      assetKey: assetKey,
      protocol: protocol,
      row: row,
      col: col,
      widthPx: widthPx,
      heightPx: heightPx,
      widthCells: widthCells,
      heightCells: heightCells,
      sourceXOffsetPx: sourceXOffsetPx,
      visibleWidthPx: visibleWidthPx ?? widthPx - sourceXOffsetPx,
      sourceYOffsetPx: sourceYOffsetPx,
      visibleHeightPx: visibleHeightPx ?? heightPx - sourceYOffsetPx,
      zIndex: _intFromJson(json['z_index'] ?? json['zIndex'], fallback: 0),
      xOffsetPx: _nonNegativeIntFromJson(
        json['x_offset_px'] ?? json['xOffsetPx'],
      ),
      yOffsetPx: _nonNegativeIntFromJson(
        json['y_offset_px'] ?? json['yOffsetPx'],
      ),
      preserveAspectRatio: _boolFromJson(
        json['preserve_aspect_ratio'] ?? json['preserveAspectRatio'],
        fallback: true,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TerminalGraphicPlacement &&
        other.renderId == renderId &&
        other.placementId == placementId &&
        other.assetKey == assetKey &&
        other.protocol == protocol &&
        other.row == row &&
        other.col == col &&
        other.widthPx == widthPx &&
        other.heightPx == heightPx &&
        other.widthCells == widthCells &&
        other.heightCells == heightCells &&
        other.sourceXOffsetPx == sourceXOffsetPx &&
        other.visibleWidthPx == visibleWidthPx &&
        other.sourceYOffsetPx == sourceYOffsetPx &&
        other.visibleHeightPx == visibleHeightPx &&
        other.zIndex == zIndex &&
        other.xOffsetPx == xOffsetPx &&
        other.yOffsetPx == yOffsetPx &&
        other.preserveAspectRatio == preserveAspectRatio;
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
    renderId,
    placementId,
    assetKey,
    protocol,
    row,
    col,
    widthPx,
    heightPx,
    widthCells,
    heightCells,
    sourceXOffsetPx,
    visibleWidthPx,
    sourceYOffsetPx,
    visibleHeightPx,
    zIndex,
    xOffsetPx,
    yOffsetPx,
    preserveAspectRatio,
  ]);
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
  static const currentFrameSchemaVersion =
      TerminalWireCompatibility.currentFrameSchemaVersion;

  const TerminalFrameDiff({
    this.frameSchemaVersion = currentFrameSchemaVersion,
    this.frameKind = TerminalFrameKind.snapshot,
    required this.rows,
    required this.cursor,
    required this.viewportRows,
    required this.viewportCols,
    required this.dirtyRanges,
    required this.scrollbackOffset,
    required this.scrollbackMaxOffset,
    this.globalBottomRow,
    this.viewportStartRow = 0,
    this.viewportRowShift = 0,
    this.defaultForeground,
    this.defaultBackground,
    this.cursorColor,
    this.cursorGuideColor,
    this.selectionBackground,
    this.selectionForeground,
    this.linkColor,
    this.cursorTextColor,
    this.tabColor,
    this.pointerShape,
    this.modes = TerminalFrameModes.empty,
    this.selection,
    this.windowTitle,
    this.windowIconName,
    this.fontFamily,
    this.hyperlinks = const [],
    this.sizedText = const [],
    this.inlineImages = const [],
    this.graphics = const [],
    this.blocks = const [],
    this.inlineButtons = const [],
  });

  final String frameSchemaVersion;
  final TerminalFrameKind frameKind;
  final List<TerminalRow> rows;
  final TerminalCursor cursor;
  final TerminalSelection? selection;
  final int viewportRows;
  final int viewportCols;
  final List<TerminalDirtyRange> dirtyRanges;
  final int scrollbackOffset;
  final int scrollbackMaxOffset;

  /// Absolute row of the bottom of the terminal history, when supplied by the
  /// native producer. `null` identifies legacy frames that predate this field;
  /// zero is a valid value for a one-row terminal with no history.
  final int? globalBottomRow;
  final int viewportStartRow;
  final int viewportRowShift;
  final Color? defaultForeground;
  final Color? defaultBackground;
  final Color? cursorColor;
  final Color? cursorGuideColor;
  final Color? selectionBackground;
  final Color? selectionForeground;
  final Color? linkColor;
  final Color? cursorTextColor;
  final Color? tabColor;
  final TerminalPointerShape? pointerShape;
  final TerminalFrameModes modes;
  final String? windowTitle;
  final String? windowIconName;
  final String? fontFamily;
  final List<TerminalHyperlinkRange> hyperlinks;
  final List<TerminalSizedTextPlacement> sizedText;
  final List<TerminalInlineImage> inlineImages;
  final List<TerminalGraphicPlacement> graphics;
  final List<TerminalBlock> blocks;
  final List<TerminalInlineButton> inlineButtons;

  bool get hasExplicitSourceRowMapping =>
      rows.any((row) => row.sourceRow != null || row.sourceEndRow != null);

  int? mappedSourceRowForViewportRow(int viewportRow) {
    if (viewportRow < 0) {
      return null;
    }
    for (final row in rows) {
      if (row.index != viewportRow) {
        continue;
      }
      if (row.sourceRow != null) {
        return row.sourceRow;
      }
      return hasExplicitSourceRowMapping
          ? null
          : viewportStartRow + viewportRow;
    }
    return hasExplicitSourceRowMapping ? null : viewportStartRow + viewportRow;
  }

  int? mappedSourceEndRowForViewportRow(int viewportRow) {
    if (viewportRow < 0) {
      return null;
    }
    for (final row in rows) {
      if (row.index != viewportRow) {
        continue;
      }
      if (row.sourceEndRow != null || row.sourceRow != null) {
        return row.sourceEndRow ?? row.sourceRow;
      }
      return hasExplicitSourceRowMapping
          ? null
          : viewportStartRow + viewportRow;
    }
    return hasExplicitSourceRowMapping ? null : viewportStartRow + viewportRow;
  }

  int sourceRowForViewportRow(int viewportRow) {
    return mappedSourceRowForViewportRow(viewportRow) ??
        viewportStartRow + viewportRow.clamp(0, viewportRows).toInt();
  }

  int sourceEndRowForViewportRow(int viewportRow) {
    return mappedSourceEndRowForViewportRow(viewportRow) ??
        viewportStartRow + viewportRow.clamp(0, viewportRows).toInt();
  }

  int? viewportRowForSourceRow(int sourceRow) {
    if (sourceRow < 0) {
      return null;
    }
    final explicitMapping = hasExplicitSourceRowMapping;
    for (final row in rows) {
      if (explicitMapping &&
          row.sourceRow == null &&
          row.sourceEndRow == null) {
        continue;
      }
      final start = row.sourceRow ?? viewportStartRow + row.index;
      final end = row.sourceEndRow ?? start;
      if (sourceRow >= start && sourceRow <= end) {
        return row.index;
      }
    }
    return null;
  }

  static const empty = TerminalFrameDiff(
    frameSchemaVersion: currentFrameSchemaVersion,
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
    final viewportRows = _nativeDimensionFromJson(json['viewport_rows']);
    final viewportCols = _nativeDimensionFromJson(json['viewport_cols']);
    final scrollbackMaxOffset = _nonNegativeIntFromJson(
      json['scrollback_max_offset'],
    );
    final scrollbackOffset = _nonNegativeIntFromJson(
      json['scrollback_offset'],
    ).clamp(0, scrollbackMaxOffset).toInt();
    return TerminalFrameDiff(
      frameSchemaVersion: TerminalWireCompatibility.frameSchemaVersion(
        json['frame_schema_version'],
      ),
      frameKind: _terminalFrameKindFromWire(json['frame_kind']),
      rows: _rowsFromJson(json['rows'], viewportRows, viewportCols),
      cursor: cursorJson == null
          ? const TerminalCursor(row: 0, col: 0, visible: false)
          : TerminalCursor.tryFromJson(cursorJson) ??
                const TerminalCursor(row: 0, col: 0, visible: false),
      selection: selectionJson == null
          ? null
          : TerminalSelection.tryFromJson(selectionJson),
      viewportRows: viewportRows,
      viewportCols: viewportCols,
      dirtyRanges: _dirtyRangesFromJson(json['dirty_ranges'], viewportRows),
      scrollbackOffset: scrollbackOffset,
      scrollbackMaxOffset: scrollbackMaxOffset,
      globalBottomRow: _optionalNonNegativeIntFromJson(
        json['global_bottom_row'],
      ),
      viewportStartRow: _nonNegativeIntFromJson(json['viewport_start_row']),
      viewportRowShift: _intFromJson(json['viewport_row_shift'], fallback: 0),
      defaultForeground: _colorFromHex(
        _stringFromJson(json['default_foreground']),
      ),
      defaultBackground: _colorFromHex(
        _stringFromJson(json['default_background']),
      ),
      cursorColor: _colorFromHex(_stringFromJson(json['cursor_color'])),
      cursorGuideColor: _colorFromHex(
        _stringFromJson(json['cursor_guide_color']),
      ),
      selectionBackground: _colorFromHex(
        _stringFromJson(json['selection_background']),
      ),
      selectionForeground: _colorFromHex(
        _stringFromJson(json['selection_foreground']),
      ),
      linkColor: _colorFromHex(_stringFromJson(json['link_color'])),
      cursorTextColor: _colorFromHex(
        _stringFromJson(json['cursor_text_color']),
      ),
      tabColor: _colorFromHex(_stringFromJson(json['tab_color'])),
      pointerShape: TerminalPointerShape.fromWire(json['pointer_shape']),
      modes: modesJson == null
          ? TerminalFrameModes.empty
          : TerminalFrameModes.fromJson(modesJson),
      windowTitle: _stringFromJson(json['window_title']),
      windowIconName: _stringFromJson(json['window_icon_name']),
      fontFamily: _terminalFontFamilyFromWire(json['font_family']),
      hyperlinks: _hyperlinksFromJson(json['hyperlinks'], viewportRows),
      sizedText: _sizedTextFromJson(
        json['sized_text'],
        viewportRows,
        viewportCols,
      ),
      inlineImages: _inlineImagesFromJson(
        json['inline_images'],
        viewportRows,
        viewportCols,
      ),
      graphics: _normalizeGraphics(
        graphics: _graphicsFromJson(json['graphics']),
        viewportRows: viewportRows,
        viewportCols: viewportCols,
      ),
      blocks: _blocksFromJson(json['blocks'], viewportRows),
      inlineButtons: _inlineButtonsFromJson(
        json['inline_buttons'],
        viewportRows,
        viewportCols,
      ),
    );
  }

  factory TerminalFrameDiff.fromProtobufBytes(List<int> bytes) {
    final frame_pb.TerminalFrameDiff proto;
    try {
      proto = frame_pb.TerminalFrameDiff.fromBuffer(bytes);
    } on Object {
      throw const FormatException(
        'Invalid terminal frame diff protobuf payload',
      );
    }
    return _terminalFrameDiffFromProtobuf(proto);
  }
}

List<TerminalRow> _rowsFromJson(
  Object? value,
  int viewportRows,
  int viewportCols,
) {
  if (viewportRows <= 0 || value is! List) {
    return const <TerminalRow>[];
  }
  final maxEntries = TerminalFrameValidationLimits.maxViewportBoundedEntries(
    viewportRows,
  );
  final scanLimit = TerminalFrameValidationLimits.maxEntriesToScan(maxEntries);
  final rowsByIndex = <int, TerminalRow>{};
  var entriesScanned = 0;
  for (final entry in value) {
    if (entriesScanned >= scanLimit) {
      break;
    }
    entriesScanned += 1;
    final json = _jsonMapFromJson(entry);
    if (json == null) {
      continue;
    }
    final row = TerminalRow.tryFromJson(json);
    if (row == null || row.index < 0 || row.index >= viewportRows) {
      continue;
    }
    final replacesExisting = rowsByIndex.containsKey(row.index);
    if (!replacesExisting && rowsByIndex.length >= maxEntries) {
      continue;
    }
    rowsByIndex[row.index] = _rowBoundedToViewportCols(row, viewportCols);
  }
  final sortedIndexes = rowsByIndex.keys.toList(growable: false)..sort();
  return [for (final index in sortedIndexes) rowsByIndex[index]!];
}

TerminalRow _rowBoundedToViewportCols(TerminalRow row, int viewportCols) {
  if (viewportCols <= 0) {
    return TerminalRow(
      index: row.index,
      text: '',
      wrapped: row.wrapped,
      modifiedAt: row.modifiedAt,
      sourceRow: row.sourceRow,
      sourceEndRow: row.sourceEndRow,
    );
  }

  final cells = TerminalTextCells.fromText(row.text);
  if (cells.cellCount <= viewportCols) {
    return row;
  }

  return TerminalRow(
    index: row.index,
    text: _sliceTextToCompleteColumns(cells, viewportCols),
    wrapped: row.wrapped,
    modifiedAt: row.modifiedAt,
    styleRuns: row.styleRuns,
    sourceRow: row.sourceRow,
    sourceEndRow: row.sourceEndRow,
  );
}

String _sliceTextToCompleteColumns(TerminalTextCells cells, int endColumn) {
  final clampedEnd = cells.clampColumn(endColumn);
  if (clampedEnd <= 0) {
    return '';
  }

  var lastIndex = clampedEnd - 1;
  while (lastIndex > 0 && cells.cells[lastIndex].isContinuation) {
    lastIndex -= 1;
  }
  final lastCell = cells.cells[lastIndex];
  if (lastCell.column + lastCell.columnSpan > clampedEnd) {
    return cells.sliceColumns(0, lastCell.column);
  }
  return cells.sliceColumns(0, clampedEnd);
}

List<TerminalDirtyRange> _dirtyRangesFromJson(Object? value, int viewportRows) {
  return _normalizeDirtyRanges(
    _jsonListFromJson(
      value,
      (json) {
        final range = TerminalDirtyRange.tryFromJson(json);
        if (range == null) {
          return null;
        }
        final start = range.start.clamp(0, viewportRows).toInt();
        final end = range.end.clamp(start, viewportRows).toInt();
        if (start >= end) {
          return null;
        }
        return TerminalDirtyRange(start: start, end: end);
      },
      maxEntries: TerminalFrameValidationLimits.maxViewportBoundedEntries(
        viewportRows,
      ),
    ),
    viewportRows,
  );
}

List<TerminalHyperlinkRange> _hyperlinksFromJson(
  Object? value,
  int viewportRows,
) {
  if (viewportRows <= 0) {
    return const <TerminalHyperlinkRange>[];
  }
  return _jsonListFromJson(value, (json) {
    final range = TerminalHyperlinkRange.tryFromJson(json);
    if (range == null || range.row >= viewportRows) {
      return null;
    }
    return range;
  }, maxEntries: TerminalFrameValidationLimits.maxHyperlinksPerFrame);
}

List<TerminalSizedTextPlacement> _sizedTextFromJson(
  Object? value,
  int viewportRows,
  int viewportCols,
) {
  return _jsonListFromJson(
    value,
    (json) {
      final placement = TerminalSizedTextPlacement.tryFromJson(json);
      if (placement == null ||
          placement.row >= viewportRows ||
          placement.col >= viewportCols ||
          placement.col + placement.widthCells > viewportCols ||
          placement.row + placement.visibleHeightCells > viewportRows) {
        return null;
      }
      return placement;
    },
    maxEntries: TerminalFrameValidationLimits.maxSizedTextPlacementsPerFrame,
  );
}

List<TerminalInlineImage> _inlineImagesFromJson(
  Object? value,
  int viewportRows,
  int viewportCols,
) {
  return _jsonListFromJson(value, (json) {
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
        col == null ||
        widthCells == null ||
        heightCells == null) {
      return null;
    }
    return TerminalFrameValidationLimits.decodeViewportBounded(
      row: row,
      col: col,
      widthCells: widthCells,
      heightCells: heightCells,
      viewportRows: viewportRows,
      viewportCols: viewportCols,
      decode: ({required widthCells, required heightCells}) {
        final image = TerminalInlineImage.tryFromJson(json);
        if (image == null) {
          return null;
        }
        return TerminalInlineImage(
          row: image.row,
          col: image.col,
          widthCells: widthCells,
          heightCells: heightCells,
          bytes: image.bytes,
          altText: image.altText,
        );
      },
    );
  }, maxEntries: TerminalFrameValidationLimits.maxInlineImagesPerFrame);
}

List<TerminalGraphicPlacement> _graphicsFromJson(Object? value) {
  return _jsonListFromJson(value, TerminalGraphicPlacement.tryFromJson);
}

List<TerminalBlock> _blocksFromJson(Object? value, int viewportRows) {
  if (viewportRows <= 0) {
    return const <TerminalBlock>[];
  }
  return _jsonListFromJson(value, (json) {
    final block = TerminalBlock.tryFromJson(json);
    if (block == null ||
        block.startRow >= viewportRows ||
        block.endRow >= viewportRows) {
      return null;
    }
    return block;
  }, maxEntries: TerminalFrameValidationLimits.maxBlocksPerFrame);
}

List<TerminalInlineButton> _inlineButtonsFromJson(
  Object? value,
  int viewportRows,
  int viewportCols,
) {
  return _jsonListFromJson(value, (json) {
    final button = TerminalInlineButton.tryFromJson(json);
    if (button == null ||
        button.row >= viewportRows ||
        button.col >= viewportCols ||
        button.col + button.widthCells > viewportCols) {
      return null;
    }
    return button;
  }, maxEntries: TerminalFrameValidationLimits.maxInlineButtonsPerFrame);
}

TerminalFrameDiff _terminalFrameDiffFromProtobuf(
  frame_pb.TerminalFrameDiff proto,
) {
  final viewportRows = _clampedNativeDimension(proto.viewportRows);
  final viewportCols = _clampedNativeDimension(proto.viewportCols);
  final scrollbackMaxOffset = proto.scrollbackMaxOffset;
  final scrollbackOffset = proto.scrollbackOffset
      .clamp(0, scrollbackMaxOffset)
      .toInt();
  return TerminalFrameDiff(
    frameSchemaVersion: TerminalWireCompatibility.frameSchemaVersion(
      proto.hasFrameSchemaVersion() ? proto.frameSchemaVersion : null,
    ),
    frameKind: _terminalFrameKindFromProtobuf(proto.frameKind),
    rows: _rowsFromProtobuf(proto.rows, viewportRows, viewportCols),
    cursor: proto.hasCursor()
        ? _terminalCursorFromProtobuf(proto.cursor)
        : const TerminalCursor(row: 0, col: 0, visible: false),
    selection: proto.hasSelection()
        ? _terminalSelectionFromProtobuf(proto.selection)
        : null,
    viewportRows: viewportRows,
    viewportCols: viewportCols,
    dirtyRanges: _dirtyRangesFromProtobuf(proto.dirtyRanges, viewportRows),
    scrollbackOffset: scrollbackOffset,
    scrollbackMaxOffset: scrollbackMaxOffset,
    globalBottomRow: proto.hasGlobalBottomRow()
        ? _optionalNonNegativeFrameScalar(proto.globalBottomRow.toInt())
        : null,
    viewportStartRow: proto.viewportStartRow,
    viewportRowShift: proto.viewportRowShift,
    defaultForeground: _colorFromProtobuf(
      hasValue: proto.hasDefaultForeground(),
      value: proto.defaultForeground,
    ),
    defaultBackground: _colorFromProtobuf(
      hasValue: proto.hasDefaultBackground(),
      value: proto.defaultBackground,
    ),
    cursorColor: _colorFromProtobuf(
      hasValue: proto.hasCursorColor(),
      value: proto.cursorColor,
    ),
    cursorGuideColor: _colorFromProtobuf(
      hasValue: proto.hasCursorGuideColor(),
      value: proto.cursorGuideColor,
    ),
    selectionBackground: _colorFromProtobuf(
      hasValue: proto.hasSelectionBackground(),
      value: proto.selectionBackground,
    ),
    selectionForeground: _colorFromProtobuf(
      hasValue: proto.hasSelectionForeground(),
      value: proto.selectionForeground,
    ),
    linkColor: _colorFromProtobuf(
      hasValue: proto.hasLinkColor(),
      value: proto.linkColor,
    ),
    cursorTextColor: _colorFromProtobuf(
      hasValue: proto.hasCursorTextColor(),
      value: proto.cursorTextColor,
    ),
    tabColor: _colorFromProtobuf(
      hasValue: proto.hasTabColor(),
      value: proto.tabColor,
    ),
    pointerShape: proto.hasPointerShape()
        ? TerminalPointerShape.fromWire(proto.pointerShape)
        : null,
    modes: proto.hasModes()
        ? _terminalFrameModesFromProtobuf(proto.modes)
        : TerminalFrameModes.empty,
    windowTitle: proto.hasWindowTitle() ? proto.windowTitle : null,
    windowIconName: proto.hasWindowIconName() ? proto.windowIconName : null,
    fontFamily: proto.hasFontFamily()
        ? _terminalFontFamilyFromWire(proto.fontFamily)
        : null,
    hyperlinks: _hyperlinksFromProtobuf(proto.hyperlinks, viewportRows),
    sizedText: _sizedTextFromProtobuf(
      proto.sizedText,
      viewportRows,
      viewportCols,
    ),
    inlineImages: _inlineImagesFromProtobuf(
      proto.inlineImages,
      viewportRows,
      viewportCols,
    ),
    graphics: _normalizeGraphics(
      graphics: proto.graphics.map(_terminalGraphicFromProtobuf),
      viewportRows: viewportRows,
      viewportCols: viewportCols,
    ),
    blocks: _boundedProtobufItems(
      proto.blocks,
      (block) => _terminalBlockFromProtobuf(block, viewportRows),
      maxEntries: TerminalFrameValidationLimits.maxBlocksPerFrame,
    ),
    inlineButtons: _boundedProtobufItems(
      proto.inlineButtons,
      (button) =>
          _terminalInlineButtonFromProtobuf(button, viewportRows, viewportCols),
      maxEntries: TerminalFrameValidationLimits.maxInlineButtonsPerFrame,
    ),
  );
}

TerminalFrameKind _terminalFrameKindFromProtobuf(
  frame_pb.TerminalFrameKind value,
) {
  return switch (TerminalWireCompatibility.frameKindFromProtobuf(value.value)) {
    TerminalWireFrameKind.delta => TerminalFrameKind.delta,
    TerminalWireFrameKind.snapshot => TerminalFrameKind.snapshot,
  };
}

List<TerminalRow> _rowsFromProtobuf(
  Iterable<frame_pb.TerminalRow> rows,
  int viewportRows,
  int viewportCols,
) {
  if (viewportRows <= 0) {
    return const <TerminalRow>[];
  }
  final maxEntries = TerminalFrameValidationLimits.maxViewportBoundedEntries(
    viewportRows,
  );
  final scanLimit = TerminalFrameValidationLimits.maxEntriesToScan(maxEntries);
  final rowsByIndex = <int, TerminalRow>{};
  var entriesScanned = 0;
  for (final row in rows) {
    if (entriesScanned >= scanLimit) {
      break;
    }
    entriesScanned += 1;
    if (row.index >= viewportRows) {
      continue;
    }
    final replacesExisting = rowsByIndex.containsKey(row.index);
    if (!replacesExisting && rowsByIndex.length >= maxEntries) {
      continue;
    }
    rowsByIndex[row.index] = _rowBoundedToViewportCols(
      _terminalRowFromProtobuf(row),
      viewportCols,
    );
  }
  final sortedIndexes = rowsByIndex.keys.toList(growable: false)..sort();
  return <TerminalRow>[for (final index in sortedIndexes) rowsByIndex[index]!];
}

TerminalRow _terminalRowFromProtobuf(frame_pb.TerminalRow row) {
  final sourceRow = row.hasSourceRow() ? row.sourceRow : null;
  final sourceEndRow = row.hasSourceEndRow() ? row.sourceEndRow : null;
  return TerminalRow(
    index: row.index,
    text: row.text,
    wrapped: row.wrapped,
    modifiedAt: _dateTimeFromProtobufMicros(row),
    styleRuns: _boundedProtobufItems(
      row.styleRuns,
      _terminalStyleRunFromProtobuf,
      maxEntries: TerminalFrameValidationLimits.maxStyleRunsPerRow,
    ),
    sourceRow: sourceRow ?? sourceEndRow,
    sourceEndRow:
        sourceRow != null && sourceEndRow != null && sourceEndRow < sourceRow
        ? sourceRow
        : sourceEndRow ?? sourceRow,
  );
}

TerminalBlock? _terminalBlockFromProtobuf(
  frame_pb.TerminalBlock block,
  int viewportRows,
) {
  final decoded = TerminalBlock.tryFromJson(<String, Object?>{
    'id': block.id,
    'block_type': block.blockType,
    'start_row': block.startRow,
    'end_row': block.endRow,
    'source_start_row': block.sourceStartRow,
    'source_end_row': block.sourceEndRow,
    'folded': block.folded,
    'rendered': block.rendered,
    'hidden_rows': block.hiddenRows,
  });
  if (decoded == null ||
      decoded.startRow >= viewportRows ||
      decoded.endRow >= viewportRows) {
    return null;
  }
  return decoded;
}

TerminalInlineButton? _terminalInlineButtonFromProtobuf(
  frame_pb.TerminalInlineButton button,
  int viewportRows,
  int viewportCols,
) {
  final decoded = TerminalInlineButton.tryFromJson(<String, Object?>{
    'id': button.id.toInt(),
    'kind': button.kind,
    'row': button.row,
    'col': button.col,
    'code': button.hasCode() ? button.code : null,
    'icon': button.icon,
    'block_id': button.blockId,
    'valid': button.valid,
    'width_cells': button.widthCells,
  });
  if (decoded == null ||
      decoded.row >= viewportRows ||
      decoded.col + decoded.widthCells > viewportCols) {
    return null;
  }
  return decoded;
}

TerminalStyleRun? _terminalStyleRunFromProtobuf(frame_pb.TerminalStyleRun run) {
  if (run.end <= run.start) {
    return null;
  }
  return TerminalStyleRun(
    start: run.start,
    end: run.end,
    foreground: _colorFromProtobuf(
      hasValue: run.hasForeground(),
      value: run.foreground,
    ),
    background: _colorFromProtobuf(
      hasValue: run.hasBackground(),
      value: run.background,
    ),
    underlineColor: _colorFromProtobuf(
      hasValue: run.hasUnderlineColor(),
      value: run.underlineColor,
    ),
    bold: run.bold,
    dim: run.dim,
    italic: run.italic,
    underline: run.underline,
    blink: run.blink,
    inverse: run.inverse,
  );
}

DateTime? _dateTimeFromProtobufMicros(frame_pb.TerminalRow row) {
  if (!row.hasModifiedAtMicros()) {
    return null;
  }
  final micros = row.modifiedAtMicros.toInt();
  if (micros <= 0) {
    return null;
  }
  try {
    return DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
  } on Object {
    return null;
  }
}

TerminalCursor _terminalCursorFromProtobuf(frame_pb.TerminalCursor cursor) {
  return TerminalCursor(
    row: cursor.row,
    col: cursor.col,
    visible: cursor.visible,
    highlightLine: cursor.highlightLine,
    shape: cursor.hasShape()
        ? _terminalCursorShapeFromWire(cursor.shape)
        : null,
    blink: cursor.hasBlink() ? cursor.blink : null,
  );
}

TerminalSelection? _terminalSelectionFromProtobuf(
  frame_pb.TerminalSelection selection,
) {
  if (!selection.present) {
    return null;
  }
  return TerminalSelection(
    startRow: selection.startRow,
    startCol: selection.startCol,
    endRow: selection.endRow,
    endCol: selection.endCol,
  );
}

TerminalFrameModes _terminalFrameModesFromProtobuf(
  frame_pb.TerminalFrameModes modes,
) {
  return TerminalFrameModes(
    alternateScreen: modes.alternateScreen,
    alternateScroll: modes.alternateScroll,
    applicationCursor: modes.applicationCursor,
    applicationKeypad: modes.applicationKeypad,
    insertMode: modes.insertMode,
    originMode: modes.originMode,
    lineFeedNewLineMode: modes.lineFeedNewLineMode,
    hideCursor: modes.hideCursor,
    bracketedPaste: modes.bracketedPaste,
    mimePaste: modes.mimePaste,
    focusTracking: modes.focusTracking,
    charProtected: modes.charProtected,
    mouseMode: _terminalMouseModeFromJson(modes.mouseMode),
    mouseEncoding: _terminalMouseEncodingFromJson(modes.mouseEncoding),
    kittyKeyboardFlags: modes.kittyKeyboardFlags,
    synchronizedOutput: modes.synchronizedOutput,
  );
}

TerminalHyperlinkRange? _terminalHyperlinkFromProtobuf(
  frame_pb.TerminalHyperlinkRange hyperlink,
) {
  final uri = _nonEmptyTrimmedProtoString(
    hasValue: hyperlink.hasUri(),
    value: hyperlink.uri,
  );
  if (hyperlink.endCol <= hyperlink.startCol || uri == null) {
    return null;
  }
  return TerminalHyperlinkRange(
    row: hyperlink.row,
    startCol: hyperlink.startCol,
    endCol: hyperlink.endCol,
    uri: uri,
    protocolId: _nonEmptyTrimmedProtoString(
      hasValue: hyperlink.hasProtocolId(),
      value: hyperlink.protocolId,
    ),
  );
}

List<TerminalHyperlinkRange> _hyperlinksFromProtobuf(
  Iterable<frame_pb.TerminalHyperlinkRange> hyperlinks,
  int viewportRows,
) {
  if (viewportRows <= 0) {
    return const <TerminalHyperlinkRange>[];
  }
  return _boundedProtobufItems(hyperlinks, (hyperlink) {
    final decoded = _terminalHyperlinkFromProtobuf(hyperlink);
    if (decoded == null || decoded.row >= viewportRows) {
      return null;
    }
    return decoded;
  }, maxEntries: TerminalFrameValidationLimits.maxHyperlinksPerFrame);
}

TerminalSizedTextPlacement? _terminalSizedTextFromProtobuf(
  frame_pb.TerminalSizedTextPlacement placement,
) {
  final text = placement.hasText() ? placement.text : '';
  final widthCells = placement.hasWidthCells() ? placement.widthCells : 0;
  final heightCells = placement.hasHeightCells() ? placement.heightCells : 0;
  final sourceRowOffsetCells = placement.hasSourceRowOffsetCells()
      ? placement.sourceRowOffsetCells
      : 0;
  final visibleHeightCells = placement.hasVisibleHeightCells()
      ? placement.visibleHeightCells
      : 0;
  final scale = placement.hasScale() ? placement.scale : 0;
  final subscaleN = placement.hasSubscaleN() ? placement.subscaleN : 0;
  final subscaleD = placement.hasSubscaleD() ? placement.subscaleD : 0;
  final verticalAlign = placement.hasVerticalAlign()
      ? placement.verticalAlign
      : 0;
  final horizontalAlign = placement.hasHorizontalAlign()
      ? placement.horizontalAlign
      : 0;
  if (text.isEmpty ||
      text.length > 4096 ||
      utf8.encode(text).length > 4096 ||
      widthCells < 1 ||
      widthCells > 49 ||
      heightCells < 1 ||
      heightCells > 7 ||
      sourceRowOffsetCells >= heightCells ||
      visibleHeightCells < 1 ||
      sourceRowOffsetCells + visibleHeightCells > heightCells ||
      scale < 1 ||
      scale > 7 ||
      subscaleN > 15 ||
      subscaleD > 15 ||
      (subscaleD > 0 && subscaleN >= subscaleD) ||
      verticalAlign > 2 ||
      horizontalAlign > 2) {
    return null;
  }
  return TerminalSizedTextPlacement(
    text: text,
    row: placement.hasRow() ? placement.row : 0,
    col: placement.hasCol() ? placement.col : 0,
    widthCells: widthCells,
    heightCells: heightCells,
    sourceRowOffsetCells: sourceRowOffsetCells,
    visibleHeightCells: visibleHeightCells,
    scale: scale,
    subscaleN: subscaleD == 0 ? 0 : subscaleN,
    subscaleD: subscaleD,
    verticalAlign: verticalAlign,
    horizontalAlign: horizontalAlign,
    naturalWidth: placement.naturalWidth,
    foreground: _colorFromProtobuf(
      hasValue: placement.hasForeground(),
      value: placement.foreground,
    ),
    background: _colorFromProtobuf(
      hasValue: placement.hasBackground(),
      value: placement.background,
    ),
    underlineColor: _colorFromProtobuf(
      hasValue: placement.hasUnderlineColor(),
      value: placement.underlineColor,
    ),
    bold: placement.bold,
    dim: placement.dim,
    italic: placement.italic,
    underline: placement.underline,
    blink: placement.blink,
    inverse: placement.inverse,
  );
}

List<TerminalSizedTextPlacement> _sizedTextFromProtobuf(
  Iterable<frame_pb.TerminalSizedTextPlacement> placements,
  int viewportRows,
  int viewportCols,
) {
  return _boundedProtobufItems(
    placements,
    (placement) {
      final decoded = _terminalSizedTextFromProtobuf(placement);
      if (decoded == null ||
          decoded.row >= viewportRows ||
          decoded.col >= viewportCols ||
          decoded.col + decoded.widthCells > viewportCols ||
          decoded.row + decoded.visibleHeightCells > viewportRows) {
        return null;
      }
      return decoded;
    },
    maxEntries: TerminalFrameValidationLimits.maxSizedTextPlacementsPerFrame,
  );
}

TerminalInlineImage? _terminalInlineImageFromProtobuf(
  frame_pb.TerminalInlineImage image,
) {
  final encoded = image.hasData() ? image.data : '';
  if (encoded.isEmpty || encoded.length > _maxInlineImageEncodedLength) {
    return null;
  }
  final Uint8List bytes;
  try {
    bytes = base64.decode(encoded);
  } on FormatException {
    return null;
  }
  if (bytes.isEmpty ||
      bytes.length > TerminalFrameValidationLimits.maxInlineImageDecodedBytes) {
    return null;
  }
  final widthCells = image.hasWidthCells() ? image.widthCells : 1;
  final heightCells = image.hasHeightCells() ? image.heightCells : 1;
  if (widthCells <= 0 || heightCells <= 0) {
    return null;
  }
  return TerminalInlineImage(
    row: image.hasRow() ? image.row : 0,
    col: image.hasCol() ? image.col : 0,
    widthCells: widthCells,
    heightCells: heightCells,
    bytes: bytes,
    altText: image.hasAltText() ? image.altText : null,
  );
}

List<TerminalInlineImage> _inlineImagesFromProtobuf(
  Iterable<frame_pb.TerminalInlineImage> images,
  int viewportRows,
  int viewportCols,
) {
  return _boundedProtobufItems(images, (image) {
    final row = image.hasRow() ? image.row : 0;
    final col = image.hasCol() ? image.col : 0;
    final widthCells = image.hasWidthCells() ? image.widthCells : 1;
    final heightCells = image.hasHeightCells() ? image.heightCells : 1;
    return TerminalFrameValidationLimits.decodeViewportBounded(
      row: row,
      col: col,
      widthCells: widthCells,
      heightCells: heightCells,
      viewportRows: viewportRows,
      viewportCols: viewportCols,
      decode: ({required widthCells, required heightCells}) {
        final decoded = _terminalInlineImageFromProtobuf(image);
        if (decoded == null) {
          return null;
        }
        return TerminalInlineImage(
          row: decoded.row,
          col: decoded.col,
          widthCells: widthCells,
          heightCells: heightCells,
          bytes: decoded.bytes,
          altText: decoded.altText,
        );
      },
    );
  }, maxEntries: TerminalFrameValidationLimits.maxInlineImagesPerFrame);
}

TerminalGraphicPlacement? _terminalGraphicFromProtobuf(
  frame_pb.TerminalGraphicPlacement graphic,
) {
  if (!graphic.hasAssetKey()) {
    return null;
  }
  final assetKey = graphic.assetKey;
  final protocol = _nonEmptyTrimmedProtoString(
    hasValue: graphic.hasProtocol(),
    value: graphic.protocol,
  );
  final placementId = graphic.placementId.toInt();
  final decodedRenderId = graphic.renderId.toInt();
  final renderId = graphic.hasRenderId() && decodedRenderId > 0
      ? decodedRenderId
      : placementId;
  final assetId = assetKey.assetId.toInt();
  final assetVersion = assetKey.assetVersion.toInt();
  final widthPx = graphic.widthPx;
  final heightPx = graphic.heightPx;
  final widthCells = graphic.widthCells;
  final heightCells = graphic.heightCells;
  final sourceXOffsetPx = graphic.sourceXOffsetPx;
  final visibleWidthPx = graphic.hasVisibleWidthPx()
      ? graphic.visibleWidthPx
      : widthPx - sourceXOffsetPx;
  final sourceYOffsetPx = graphic.sourceYOffsetPx;
  final visibleHeightPx = graphic.hasVisibleHeightPx()
      ? graphic.visibleHeightPx
      : heightPx - sourceYOffsetPx;
  if (assetId <= 0 ||
      assetVersion <= 0 ||
      protocol == null ||
      widthPx <= 0 ||
      heightPx <= 0 ||
      widthCells <= 0 ||
      heightCells <= 0 ||
      sourceXOffsetPx >= widthPx ||
      visibleWidthPx <= 0 ||
      visibleWidthPx > widthPx - sourceXOffsetPx ||
      sourceYOffsetPx >= heightPx ||
      visibleHeightPx <= 0 ||
      visibleHeightPx > heightPx - sourceYOffsetPx) {
    return null;
  }
  return TerminalGraphicPlacement(
    renderId: renderId,
    placementId: placementId,
    assetKey: TerminalGraphicAssetKey(id: assetId, version: assetVersion),
    protocol: protocol,
    row: graphic.row,
    col: graphic.col,
    widthPx: widthPx,
    heightPx: heightPx,
    widthCells: widthCells,
    heightCells: heightCells,
    sourceXOffsetPx: sourceXOffsetPx,
    visibleWidthPx: visibleWidthPx,
    sourceYOffsetPx: sourceYOffsetPx,
    visibleHeightPx: visibleHeightPx,
    zIndex: graphic.zIndex,
    xOffsetPx: graphic.xOffsetPx < 0 ? 0 : graphic.xOffsetPx,
    yOffsetPx: graphic.yOffsetPx < 0 ? 0 : graphic.yOffsetPx,
    preserveAspectRatio: graphic.preserveAspectRatio,
  );
}

Color? _colorFromProtobuf({
  required bool hasValue,
  required frame_pb.ColorRgb value,
}) {
  if (!hasValue || !value.present || value.rgb > 0xFFFFFF) {
    return null;
  }
  return Color(0xFF000000 | value.rgb);
}

String? _nonEmptyTrimmedProtoString({
  required bool hasValue,
  required String value,
}) {
  if (!hasValue) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
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
  if (normalized.length < 2) {
    return normalized;
  }

  normalized.sort((left, right) {
    final byStart = left.start.compareTo(right.start);
    return byStart == 0 ? left.end.compareTo(right.end) : byStart;
  });
  final merged = <TerminalDirtyRange>[];
  var currentStart = normalized.first.start;
  var currentEnd = normalized.first.end;
  for (final range in normalized.skip(1)) {
    if (range.start <= currentEnd) {
      if (range.end > currentEnd) {
        currentEnd = range.end;
      }
      continue;
    }
    merged.add(TerminalDirtyRange(start: currentStart, end: currentEnd));
    currentStart = range.start;
    currentEnd = range.end;
  }
  merged.add(TerminalDirtyRange(start: currentStart, end: currentEnd));
  return merged;
}

List<TerminalDirtyRange> _dirtyRangesFromProtobuf(
  Iterable<frame_pb.TerminalDirtyRange> ranges,
  int viewportRows,
) {
  if (viewportRows <= 0) {
    return const <TerminalDirtyRange>[];
  }
  return _normalizeDirtyRanges(
    _boundedProtobufItems(
      ranges,
      (range) {
        final start = range.start.clamp(0, viewportRows).toInt();
        final end = range.end.clamp(start, viewportRows).toInt();
        if (start >= end) {
          return null;
        }
        return TerminalDirtyRange(start: start, end: end);
      },
      maxEntries: TerminalFrameValidationLimits.maxViewportBoundedEntries(
        viewportRows,
      ),
    ),
    viewportRows,
  );
}

List<TOutput> _boundedProtobufItems<TInput, TOutput>(
  Iterable<TInput> values,
  TOutput? Function(TInput value) decode, {
  required int maxEntries,
}) {
  final decoded = <TOutput>[];
  final maxEntriesToScan = TerminalFrameValidationLimits.maxEntriesToScan(
    maxEntries,
  );
  var entriesScanned = 0;
  for (final value in values) {
    if (entriesScanned >= maxEntriesToScan) {
      break;
    }
    entriesScanned += 1;
    final item = decode(value);
    if (item == null) {
      continue;
    }
    decoded.add(item);
    if (decoded.length >= maxEntries) {
      break;
    }
  }
  return decoded;
}

List<T> _jsonListFromJson<T>(
  Object? value,
  T? Function(Map<String, Object?> json) decode, {
  int? maxEntries,
}) {
  if (value is! List) {
    return <T>[];
  }
  final items = <T>[];
  final entries = maxEntries == null
      ? value
      : value.take(TerminalFrameValidationLimits.maxEntriesToScan(maxEntries));
  for (final entry in entries) {
    final json = _jsonMapFromJson(entry);
    if (json == null) {
      continue;
    }
    final item = decode(json);
    if (item != null) {
      items.add(item);
      if (maxEntries != null && items.length >= maxEntries) {
        break;
      }
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

class TerminalRenderIntent {
  const TerminalRenderIntent._({
    required this.rebuildAllRows,
    required this.dirtyRowIndexes,
    required this.dirtyStart,
    required this.dirtyEnd,
    required this.rowCacheShift,
  });

  static const none = TerminalRenderIntent._(
    rebuildAllRows: false,
    dirtyRowIndexes: <int>{},
    dirtyStart: null,
    dirtyEnd: null,
    rowCacheShift: 0,
  );

  factory TerminalRenderIntent.fromFrame(
    TerminalFrameDiff frame, {
    required bool hasNewFrame,
    bool forceFullRowVisualRebuild = false,
  }) {
    if (!hasNewFrame && !forceFullRowVisualRebuild) {
      return none;
    }
    final rowCacheShift =
        hasNewFrame && frame.frameKind == TerminalFrameKind.delta
        ? frame.viewportRowShift
        : 0;
    final dirtyExtent = hasNewFrame
        ? _dirtyRowExtentForRanges(frame.dirtyRanges, frame.viewportRows)
        : null;
    if (forceFullRowVisualRebuild ||
        frame.frameKind == TerminalFrameKind.snapshot) {
      return TerminalRenderIntent._(
        rebuildAllRows: true,
        dirtyRowIndexes: const <int>{},
        dirtyStart: dirtyExtent?.start,
        dirtyEnd: dirtyExtent?.end,
        rowCacheShift: rowCacheShift,
      );
    }

    final dirtyRows = _dirtyRowIndexesForRanges(
      frame.dirtyRanges,
      frame.viewportRows,
    );
    return TerminalRenderIntent._(
      rebuildAllRows: false,
      dirtyRowIndexes: Set<int>.unmodifiable(dirtyRows),
      dirtyStart: dirtyExtent?.start,
      dirtyEnd: dirtyExtent?.end,
      rowCacheShift: rowCacheShift,
    );
  }

  final bool rebuildAllRows;
  final Set<int> dirtyRowIndexes;
  final int? dirtyStart;
  final int? dirtyEnd;
  final int rowCacheShift;

  bool get shiftsRowCache => rowCacheShift != 0;
  bool get hasDirtyExtent =>
      dirtyStart != null && dirtyEnd != null && dirtyStart! < dirtyEnd!;
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
    final nextViewportRows = _clampedNativeDimension(nextFrame.viewportRows);
    final nextViewportCols = _clampedNativeDimension(nextFrame.viewportCols);
    if (frame.viewportRows <= 0 ||
        frame.viewportCols <= 0 ||
        frame.rows.isEmpty ||
        frame.viewportRows != nextViewportRows ||
        frame.viewportCols != nextViewportCols) {
      return applySnapshot(nextFrame, capturedAt: capturedAt);
    }
    final scrollbackMaxOffset = _nonNegativeFrameScalar(
      nextFrame.scrollbackMaxOffset,
    );
    final scrollbackOffset = nextFrame.scrollbackOffset
        .clamp(0, scrollbackMaxOffset)
        .toInt();

    final mergedRows = _mergeViewportRows(
      currentRows: _shiftViewportRows(
        rows: frame.rows,
        viewportRows: nextViewportRows,
        rowShift: nextFrame.viewportRowShift,
      ),
      incomingRows: nextFrame.rows,
      viewportRows: nextViewportRows,
      modifiedAt: capturedAt,
    );
    final dirtyRanges = _mergeDirtyRangesWithRows(
      dirtyRanges: nextFrame.dirtyRanges,
      rows: nextFrame.rows,
      viewportRows: nextViewportRows,
    );
    final mergedHyperlinks = _mergeHyperlinks(
      currentRanges: _shiftHyperlinks(
        ranges: frame.hyperlinks,
        viewportRows: nextViewportRows,
        rowShift: nextFrame.viewportRowShift,
      ),
      incomingRanges: nextFrame.hyperlinks,
      dirtyRanges: dirtyRanges,
      viewportRows: nextViewportRows,
    );
    final mergedInlineImages = _mergeInlineImages(
      currentImages: _shiftInlineImages(
        images: frame.inlineImages,
        viewportRows: nextViewportRows,
        viewportCols: nextViewportCols,
        rowShift: nextFrame.viewportRowShift,
      ),
      incomingImages: nextFrame.inlineImages,
      dirtyRanges: dirtyRanges,
      viewportRows: nextViewportRows,
      viewportCols: nextViewportCols,
    );
    final mergedGraphics = _normalizeGraphics(
      graphics: nextFrame.graphics,
      viewportRows: nextViewportRows,
      viewportCols: nextViewportCols,
    );

    return TerminalViewportState(
      frame: TerminalFrameDiff(
        frameSchemaVersion: nextFrame.frameSchemaVersion,
        frameKind: nextFrame.frameKind,
        rows: mergedRows,
        cursor: _validFrameCursor(nextFrame.cursor),
        selection: _validFrameSelection(nextFrame.selection),
        viewportRows: nextViewportRows,
        viewportCols: nextViewportCols,
        dirtyRanges: dirtyRanges,
        scrollbackOffset: scrollbackOffset,
        scrollbackMaxOffset: scrollbackMaxOffset,
        globalBottomRow: _optionalNonNegativeFrameScalar(
          nextFrame.globalBottomRow,
        ),
        viewportStartRow: _nonNegativeFrameScalar(nextFrame.viewportStartRow),
        viewportRowShift: nextFrame.viewportRowShift,
        defaultForeground:
            nextFrame.defaultForeground ?? frame.defaultForeground,
        defaultBackground:
            nextFrame.defaultBackground ?? frame.defaultBackground,
        cursorColor: nextFrame.cursorColor ?? frame.cursorColor,
        cursorGuideColor: nextFrame.cursorGuideColor ?? frame.cursorGuideColor,
        selectionBackground:
            nextFrame.selectionBackground ?? frame.selectionBackground,
        selectionForeground:
            nextFrame.selectionForeground ?? frame.selectionForeground,
        linkColor: nextFrame.linkColor ?? frame.linkColor,
        cursorTextColor: nextFrame.cursorTextColor ?? frame.cursorTextColor,
        tabColor: nextFrame.tabColor ?? frame.tabColor,
        pointerShape: nextFrame.pointerShape,
        modes: nextFrame.modes,
        windowTitle: nextFrame.windowTitle,
        windowIconName: nextFrame.windowIconName,
        fontFamily: nextFrame.fontFamily ?? frame.fontFamily,
        hyperlinks: mergedHyperlinks,
        sizedText: nextFrame.sizedText,
        inlineImages: mergedInlineImages,
        graphics: mergedGraphics,
        blocks: _normalizeBlocks(nextFrame.blocks, nextViewportRows),
        inlineButtons: _normalizeInlineButtons(
          nextFrame.inlineButtons,
          nextViewportRows,
          nextViewportCols,
        ),
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

int? _optionalNonNegativeIntFromJson(Object? value) {
  final parsed = _wholeIntFromJson(value);
  return parsed == null || parsed < 0 ? null : parsed;
}

int _nativeDimensionFromJson(Object? value) {
  return _nonNegativeIntFromJson(
    value,
  ).clamp(0, TerminalFrameValidationLimits.maxNativeDimension).toInt();
}

int _clampedNativeDimension(int value) {
  return value
      .clamp(0, TerminalFrameValidationLimits.maxNativeDimension)
      .toInt();
}

int _nonNegativeFrameScalar(int value) {
  return value < 0 ? 0 : value;
}

int? _optionalNonNegativeFrameScalar(int? value) {
  return value == null || value < 0 ? null : value;
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

String? _terminalFontFamilyFromWire(Object? value) {
  final family = _stringFromJson(value)?.trim();
  if (family == null ||
      family.isEmpty ||
      utf8.encode(family).length > _maxTerminalFontFamilyBytes ||
      family.runes.any(
        (rune) => rune <= 0x1f || (rune >= 0x7f && rune <= 0x9f),
      )) {
    return null;
  }
  return family;
}

String? _nonEmptyTrimmedStringFromJson(Object? value) {
  final text = _stringFromJson(value)?.trim();
  return text == null || text.isEmpty ? null : text;
}

String _terminalMouseModeFromJson(Object? value) {
  final normalized = value is String ? value.trim().toLowerCase() : null;
  return switch (normalized) {
    'x10' => 'x10',
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
    'sgr_pixels' || 'sgr-pixels' || 'sgrpixels' => 'sgr_pixels',
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

TerminalFrameKind _terminalFrameKindFromWire(Object? value) {
  return switch (TerminalWireCompatibility.frameKindFromJson(value)) {
    TerminalWireFrameKind.delta => TerminalFrameKind.delta,
    TerminalWireFrameKind.snapshot => TerminalFrameKind.snapshot,
  };
}

TerminalFrameDiff _normalizeSnapshotFrame(
  TerminalFrameDiff frame, {
  DateTime? capturedAt,
}) {
  final viewportRows = _clampedNativeDimension(frame.viewportRows);
  final viewportCols = _clampedNativeDimension(frame.viewportCols);
  final scrollbackMaxOffset = _nonNegativeFrameScalar(
    frame.scrollbackMaxOffset,
  );
  final scrollbackOffset = frame.scrollbackOffset
      .clamp(0, scrollbackMaxOffset)
      .toInt();
  return TerminalFrameDiff(
    frameSchemaVersion: frame.frameSchemaVersion,
    frameKind: TerminalFrameKind.snapshot,
    rows: _normalizeViewportRows(
      rows: frame.rows,
      viewportRows: viewportRows,
      modifiedAt: capturedAt,
    ),
    cursor: _validFrameCursor(frame.cursor),
    selection: _validFrameSelection(frame.selection),
    viewportRows: viewportRows,
    viewportCols: viewportCols,
    dirtyRanges: _fullViewportDirtyRanges(viewportRows),
    scrollbackOffset: scrollbackOffset,
    scrollbackMaxOffset: scrollbackMaxOffset,
    globalBottomRow: _optionalNonNegativeFrameScalar(frame.globalBottomRow),
    viewportStartRow: _nonNegativeFrameScalar(frame.viewportStartRow),
    viewportRowShift: 0,
    defaultForeground: frame.defaultForeground,
    defaultBackground: frame.defaultBackground,
    cursorColor: frame.cursorColor,
    cursorGuideColor: frame.cursorGuideColor,
    selectionBackground: frame.selectionBackground,
    selectionForeground: frame.selectionForeground,
    linkColor: frame.linkColor,
    cursorTextColor: frame.cursorTextColor,
    tabColor: frame.tabColor,
    pointerShape: frame.pointerShape,
    modes: frame.modes,
    windowTitle: frame.windowTitle,
    windowIconName: frame.windowIconName,
    fontFamily: frame.fontFamily,
    hyperlinks: _boundedHyperlinks(
      frame.hyperlinks.where(
        (range) => _isValidHyperlinkInViewport(range, viewportRows),
      ),
    ),
    sizedText: frame.sizedText
        .where(
          (placement) =>
              placement.row >= 0 &&
              placement.row < viewportRows &&
              placement.col >= 0 &&
              placement.col + placement.widthCells <= viewportCols &&
              placement.row + placement.visibleHeightCells <= viewportRows,
        )
        .take(TerminalFrameValidationLimits.maxSizedTextPlacementsPerFrame)
        .toList(growable: false),
    inlineImages: _normalizeInlineImages(
      images: frame.inlineImages,
      viewportRows: viewportRows,
      viewportCols: viewportCols,
    ),
    graphics: _normalizeGraphics(
      graphics: frame.graphics,
      viewportRows: viewportRows,
      viewportCols: viewportCols,
    ),
    blocks: _normalizeBlocks(frame.blocks, viewportRows),
    inlineButtons: _normalizeInlineButtons(
      frame.inlineButtons,
      viewportRows,
      viewportCols,
    ),
  );
}

List<TerminalInlineButton> _normalizeInlineButtons(
  Iterable<TerminalInlineButton> buttons,
  int viewportRows,
  int viewportCols,
) {
  return buttons
      .where(
        (button) =>
            button.id > 0 &&
            button.row >= 0 &&
            button.row < viewportRows &&
            button.col >= 0 &&
            button.col + button.widthCells <= viewportCols &&
            button.widthCells ==
                TerminalFrameValidationLimits.inlineButtonWidthCells,
      )
      .take(TerminalFrameValidationLimits.maxInlineButtonsPerFrame)
      .toList(growable: false);
}

List<TerminalBlock> _normalizeBlocks(
  Iterable<TerminalBlock> blocks,
  int viewportRows,
) {
  if (viewportRows <= 0) {
    return const <TerminalBlock>[];
  }
  return blocks
      .where(
        (block) =>
            block.id.isNotEmpty &&
            block.id.runes.length <=
                TerminalFrameValidationLimits.maxBlockIdChars &&
            block.startRow >= 0 &&
            block.startRow < viewportRows &&
            block.endRow >= block.startRow &&
            block.endRow < viewportRows &&
            block.sourceStartRow >= 0 &&
            block.sourceEndRow >= block.sourceStartRow,
      )
      .take(TerminalFrameValidationLimits.maxBlocksPerFrame)
      .toList(growable: false);
}

List<TerminalDirtyRange> _fullViewportDirtyRanges(int viewportRows) {
  if (viewportRows <= 0) {
    return const <TerminalDirtyRange>[];
  }
  return <TerminalDirtyRange>[TerminalDirtyRange(start: 0, end: viewportRows)];
}

TerminalCursor _validFrameCursor(TerminalCursor cursor) {
  if (cursor.row < 0 || cursor.col < 0) {
    return const TerminalCursor(row: 0, col: 0, visible: false);
  }
  return cursor;
}

TerminalSelection? _validFrameSelection(TerminalSelection? selection) {
  if (selection == null ||
      selection.startRow < 0 ||
      selection.startCol < 0 ||
      selection.endRow < 0 ||
      selection.endCol < 0) {
    return null;
  }
  return selection;
}

Set<int> _dirtyRowIndexesForRanges(
  List<TerminalDirtyRange> dirtyRanges,
  int viewportRows,
) {
  final dirtyRows = <int>{};
  for (final range in dirtyRanges) {
    final start = range.start.clamp(0, viewportRows).toInt();
    final end = range.end.clamp(start, viewportRows).toInt();
    for (var row = start; row < end; row += 1) {
      dirtyRows.add(row);
    }
  }
  return dirtyRows;
}

TerminalDirtyRange? _dirtyRowExtentForRanges(
  List<TerminalDirtyRange> dirtyRanges,
  int viewportRows,
) {
  if (viewportRows <= 0 || dirtyRanges.isEmpty) {
    return null;
  }
  var start = viewportRows;
  var end = 0;
  for (final range in dirtyRanges) {
    final rangeStart = range.start.clamp(0, viewportRows).toInt();
    final rangeEnd = range.end.clamp(rangeStart, viewportRows).toInt();
    if (rangeStart >= rangeEnd) {
      continue;
    }
    start = rangeStart < start ? rangeStart : start;
    end = rangeEnd > end ? rangeEnd : end;
  }
  if (start >= end) {
    return null;
  }
  return TerminalDirtyRange(start: start, end: end);
}

List<TerminalDirtyRange> _mergeDirtyRangesWithRows({
  required List<TerminalDirtyRange> dirtyRanges,
  required List<TerminalRow> rows,
  required int viewportRows,
}) {
  dirtyRanges = _normalizeDirtyRanges(dirtyRanges, viewportRows);
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
  final mergedRows = _rowsCoverViewport(currentRows, viewportRows)
      ? List<TerminalRow>.of(currentRows, growable: false)
      : _normalizeViewportRows(rows: currentRows, viewportRows: viewportRows);
  if (incomingRows.isEmpty) {
    return mergedRows;
  }

  for (final row in incomingRows) {
    if (row.index < 0 || row.index >= viewportRows) {
      continue;
    }
    final currentRow = mergedRows[row.index];
    mergedRows[row.index] =
        row.modifiedAt == null && _sameRowVisualContent(currentRow, row)
        ? currentRow
        : _rowWithFallbackModifiedAt(row, modifiedAt);
  }

  return mergedRows;
}

bool _rowsCoverViewport(List<TerminalRow> rows, int viewportRows) {
  if (rows.length != viewportRows) {
    return false;
  }
  for (var index = 0; index < rows.length; index += 1) {
    if (rows[index].index != index) {
      return false;
    }
  }
  return true;
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
      sourceRow: sourceRow.sourceRow,
      sourceEndRow: sourceRow.sourceEndRow,
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
    sourceRow: row.sourceRow,
    sourceEndRow: row.sourceEndRow,
  );
}

bool _sameRowVisualContent(TerminalRow left, TerminalRow right) {
  return left.text == right.text &&
      left.wrapped == right.wrapped &&
      left.sourceRow == right.sourceRow &&
      left.sourceEndRow == right.sourceEndRow &&
      _sameStyleRuns(left.styleRuns, right.styleRuns);
}

bool _sameStyleRuns(List<TerminalStyleRun> left, List<TerminalStyleRun> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (!_sameStyleRun(left[index], right[index])) {
      return false;
    }
  }
  return true;
}

bool _sameStyleRun(TerminalStyleRun left, TerminalStyleRun right) {
  return left.start == right.start &&
      left.end == right.end &&
      left.foreground == right.foreground &&
      left.background == right.background &&
      left.bold == right.bold &&
      left.dim == right.dim &&
      left.italic == right.italic &&
      left.underline == right.underline &&
      left.blink == right.blink &&
      left.inverse == right.inverse;
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
    return _boundedHyperlinks(
      currentRanges.where(
        (range) => _isValidHyperlinkInViewport(range, viewportRows),
      ),
    );
  }

  final merged = <TerminalHyperlinkRange>[
    for (final range in currentRanges)
      if (!dirtyRows.contains(range.row) &&
          _isValidHyperlinkInViewport(range, viewportRows))
        range,
    for (final range in incomingRanges)
      if (_isValidHyperlinkInViewport(range, viewportRows)) range,
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
  return _boundedHyperlinks(merged);
}

List<TerminalHyperlinkRange> _shiftHyperlinks({
  required List<TerminalHyperlinkRange> ranges,
  required int viewportRows,
  required int rowShift,
}) {
  if (rowShift == 0) {
    return _boundedHyperlinks(
      ranges.where((range) => _isValidHyperlinkInViewport(range, viewportRows)),
    );
  }

  final shifted = <TerminalHyperlinkRange>[];
  for (final range in ranges) {
    if (!_isValidHyperlinkRange(range)) {
      continue;
    }
    final nextRow = range.row + rowShift;
    if (nextRow < 0 || nextRow >= viewportRows) {
      continue;
    }
    if (shifted.length >= TerminalFrameValidationLimits.maxHyperlinksPerFrame) {
      break;
    }
    shifted.add(
      TerminalHyperlinkRange(
        row: nextRow,
        startCol: range.startCol,
        endCol: range.endCol,
        uri: range.uri,
        protocolId: range.protocolId,
      ),
    );
  }
  return shifted;
}

List<TerminalHyperlinkRange> _boundedHyperlinks(
  Iterable<TerminalHyperlinkRange> ranges,
) {
  return ranges
      .take(TerminalFrameValidationLimits.maxHyperlinksPerFrame)
      .toList(growable: false);
}

bool _isValidHyperlinkInViewport(
  TerminalHyperlinkRange range,
  int viewportRows,
) {
  return range.row >= 0 &&
      range.row < viewportRows &&
      _isValidHyperlinkRange(range);
}

bool _isValidHyperlinkRange(TerminalHyperlinkRange range) {
  return range.startCol >= 0 &&
      range.endCol > range.startCol &&
      range.uri.trim().isNotEmpty;
}

List<TerminalInlineImage> _mergeInlineImages({
  required List<TerminalInlineImage> currentImages,
  required List<TerminalInlineImage> incomingImages,
  required List<TerminalDirtyRange> dirtyRanges,
  required int viewportRows,
  required int viewportCols,
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
    for (final image in _normalizeInlineImages(
      images: currentImages,
      viewportRows: viewportRows,
      viewportCols: viewportCols,
    ))
      if (dirtyRows.isEmpty || !imageTouchesDirtyRows(image)) image,
    ..._normalizeInlineImages(
      images: incomingImages,
      viewportRows: viewportRows,
      viewportCols: viewportCols,
    ),
  ];
  merged.sort((left, right) {
    final byRow = left.row.compareTo(right.row);
    if (byRow != 0) {
      return byRow;
    }
    return left.col.compareTo(right.col);
  });
  return _boundedInlineImages(merged);
}

List<TerminalInlineImage> _shiftInlineImages({
  required List<TerminalInlineImage> images,
  required int viewportRows,
  required int viewportCols,
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
    final clampedImage = _clampInlineImageToViewport(
      shiftedImage,
      viewportRows: viewportRows,
      viewportCols: viewportCols,
    );
    if (clampedImage != null) {
      if (shifted.length >=
          TerminalFrameValidationLimits.maxInlineImagesPerFrame) {
        break;
      }
      shifted.add(clampedImage);
    }
  }
  return shifted;
}

List<TerminalInlineImage> _normalizeInlineImages({
  required List<TerminalInlineImage> images,
  required int viewportRows,
  required int viewportCols,
}) {
  return _boundedInlineImages([
    for (final image in images)
      ?_clampInlineImageToViewport(
        image,
        viewportRows: viewportRows,
        viewportCols: viewportCols,
      ),
  ]);
}

List<TerminalInlineImage> _boundedInlineImages(
  Iterable<TerminalInlineImage> images,
) {
  return images
      .take(TerminalFrameValidationLimits.maxInlineImagesPerFrame)
      .toList(growable: false);
}

TerminalInlineImage? _clampInlineImageToViewport(
  TerminalInlineImage image, {
  required int viewportRows,
  required int viewportCols,
}) {
  if (image.row < 0 ||
      image.row >= viewportRows ||
      image.col < 0 ||
      image.col >= viewportCols ||
      image.widthCells <= 0 ||
      image.heightCells <= 0 ||
      image.bytes.isEmpty) {
    return null;
  }
  final maxWidthCells = viewportCols - image.col;
  final maxHeightCells = viewportRows - image.row;
  if (maxWidthCells <= 0 || maxHeightCells <= 0) {
    return null;
  }
  final widthCells = image.widthCells.clamp(1, maxWidthCells).toInt();
  final heightCells = image.heightCells.clamp(1, maxHeightCells).toInt();
  if (widthCells == image.widthCells && heightCells == image.heightCells) {
    return image;
  }
  return TerminalInlineImage(
    row: image.row,
    col: image.col,
    widthCells: widthCells,
    heightCells: heightCells,
    bytes: image.bytes,
    altText: image.altText,
  );
}

List<TerminalGraphicPlacement> _normalizeGraphics({
  required Iterable<TerminalGraphicPlacement?> graphics,
  required int viewportRows,
  required int viewportCols,
}) {
  final normalized = <TerminalGraphicPlacement>[];
  for (final graphic in graphics) {
    if (graphic == null ||
        _graphicInvalid(graphic, viewportRows, viewportCols)) {
      continue;
    }
    normalized.add(graphic);
  }
  normalized.sort((left, right) {
    final byZ = left.zIndex.compareTo(right.zIndex);
    if (byZ != 0) {
      return byZ;
    }
    final byRow = left.row.compareTo(right.row);
    if (byRow != 0) {
      return byRow;
    }
    return left.col.compareTo(right.col);
  });
  return List<TerminalGraphicPlacement>.unmodifiable(normalized);
}

bool _graphicInvalid(
  TerminalGraphicPlacement graphic,
  int viewportRows,
  int viewportCols,
) {
  return graphic.row < 0 ||
      graphic.row >= viewportRows ||
      graphic.col < 0 ||
      graphic.col >= viewportCols ||
      graphic.widthPx <= 0 ||
      graphic.heightPx <= 0 ||
      graphic.widthCells <= 0 ||
      graphic.heightCells <= 0 ||
      graphic.sourceXOffsetPx < 0 ||
      graphic.sourceXOffsetPx >= graphic.widthPx ||
      graphic.visibleWidthPx <= 0 ||
      graphic.visibleWidthPx > graphic.widthPx - graphic.sourceXOffsetPx ||
      graphic.sourceYOffsetPx < 0 ||
      graphic.sourceYOffsetPx >= graphic.heightPx ||
      graphic.visibleHeightPx <= 0 ||
      graphic.visibleHeightPx > graphic.heightPx - graphic.sourceYOffsetPx ||
      graphic.assetKey.id <= 0 ||
      graphic.assetKey.version <= 0;
}

int _terminalDisplayWidthForGrapheme(String grapheme) {
  final runes = grapheme.runes.toList(growable: false);
  final regionalIndicatorCount = runes.where(_isRegionalIndicatorRune).length;
  if (regionalIndicatorCount == 2 ||
      _isEmojiZwjSequence(runes) ||
      _hasEmojiPresentationSelector(runes) ||
      _isKeycapSequence(runes) ||
      _hasEmojiModifierSequence(runes) ||
      _isEmojiTagSequence(runes)) {
    return 2;
  }

  var width = 0;
  final sumVisibleWidths = runes.contains(0x200D);
  for (final rune in runes) {
    if (_isZeroWidthRune(rune)) {
      continue;
    }
    final runeWidth = _isWideRune(rune) ? 2 : 1;
    if (sumVisibleWidths) {
      width += runeWidth;
    } else if (runeWidth > width) {
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
            (previousWasJoiner && _isEmojiSequenceRune(rune)) ||
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
      rune == 0x00AD ||
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
      (rune >= 0x1BCA0 && rune <= 0x1BCA3) ||
      (rune >= 0x1F3FB && rune <= 0x1F3FF) ||
      _isEmojiTagRune(rune) ||
      rune == 0xE0001 ||
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

bool _isSkinToneModifierRune(int rune) {
  return rune >= 0x1F3FB && rune <= 0x1F3FF;
}

bool _isEmojiModifierBaseRune(int rune) {
  return rune == 0x261D ||
      rune == 0x26F9 ||
      (rune >= 0x270A && rune <= 0x270D) ||
      rune == 0x1F385 ||
      (rune >= 0x1F3C2 && rune <= 0x1F3C4) ||
      rune == 0x1F3C7 ||
      (rune >= 0x1F3CA && rune <= 0x1F3CC) ||
      (rune >= 0x1F442 && rune <= 0x1F443) ||
      (rune >= 0x1F446 && rune <= 0x1F450) ||
      (rune >= 0x1F466 && rune <= 0x1F469) ||
      rune == 0x1F46E ||
      (rune >= 0x1F470 && rune <= 0x1F478) ||
      rune == 0x1F47C ||
      (rune >= 0x1F481 && rune <= 0x1F483) ||
      (rune >= 0x1F485 && rune <= 0x1F487) ||
      rune == 0x1F4AA ||
      (rune >= 0x1F574 && rune <= 0x1F575) ||
      rune == 0x1F57A ||
      rune == 0x1F590 ||
      (rune >= 0x1F595 && rune <= 0x1F596) ||
      (rune >= 0x1F645 && rune <= 0x1F647) ||
      (rune >= 0x1F64B && rune <= 0x1F64F) ||
      rune == 0x1F6A3 ||
      (rune >= 0x1F6B4 && rune <= 0x1F6B6) ||
      rune == 0x1F6C0 ||
      rune == 0x1F6CC ||
      rune == 0x1F90C ||
      rune == 0x1F90F ||
      (rune >= 0x1F918 && rune <= 0x1F91F) ||
      rune == 0x1F926 ||
      (rune >= 0x1F930 && rune <= 0x1F939) ||
      (rune >= 0x1F93D && rune <= 0x1F93E) ||
      rune == 0x1F977 ||
      (rune >= 0x1F9B5 && rune <= 0x1F9B6) ||
      (rune >= 0x1F9B8 && rune <= 0x1F9B9) ||
      rune == 0x1F9BB ||
      (rune >= 0x1F9CD && rune <= 0x1F9CF) ||
      (rune >= 0x1F9D1 && rune <= 0x1F9DD) ||
      (rune >= 0x1FAC3 && rune <= 0x1FAC5) ||
      (rune >= 0x1FAF0 && rune <= 0x1FAF8);
}

bool _hasEmojiModifierSequence(List<int> runes) {
  int? lastBase;
  for (final rune in runes) {
    if (_isSkinToneModifierRune(rune)) {
      return lastBase != null && _isEmojiModifierBaseRune(lastBase);
    }
    if (_isVariationSelectorRune(rune) ||
        rune == 0x200D ||
        _isEmojiTagRune(rune) ||
        _isZeroWidthRune(rune)) {
      continue;
    }
    lastBase = rune;
  }
  return false;
}

bool _isEmojiTagRune(int rune) {
  return rune >= 0xE0020 && rune <= 0xE007F;
}

bool _isEmojiTagSequence(List<int> runes) {
  if (runes.isEmpty || runes.first != 0x1F3F4) {
    return false;
  }
  var sawTagSpec = false;
  for (var index = 1; index < runes.length; index += 1) {
    final rune = runes[index];
    if (rune == 0xE007F) {
      return sawTagSpec && index == runes.length - 1;
    }
    if (!_isEmojiTagRune(rune)) {
      return false;
    }
    sawTagSpec = true;
  }
  return false;
}

bool _isEmojiZwjSequence(List<int> runes) {
  return runes.contains(0x200D) && runes.any(_isEmojiSequenceRune);
}

bool _isEmojiSequenceRune(int rune) {
  return (rune >= 0x2600 && rune <= 0x27BF) ||
      (rune >= 0x1F000 && rune <= 0x1FFFF);
}

bool _hasEmojiPresentationSelector(List<int> runes) {
  int? lastBase;
  for (final rune in runes) {
    if (rune == 0xFE0F) {
      return lastBase != null && _isEmojiVariationBaseRune(lastBase);
    }
    if (_isVariationSelectorRune(rune) || _isZeroWidthRune(rune)) {
      continue;
    }
    lastBase = rune;
  }
  return false;
}

bool _isVariationSelectorRune(int rune) {
  return (rune >= 0xFE00 && rune <= 0xFE0F) ||
      (rune >= 0xE0100 && rune <= 0xE01EF);
}

bool _isEmojiVariationBaseRune(int rune) {
  return _isEmojiSequenceRune(rune) ||
      rune == 0x00A9 ||
      rune == 0x00AE ||
      rune == 0x203C ||
      rune == 0x2049 ||
      rune == 0x2122 ||
      rune == 0x2139 ||
      (rune >= 0x2194 && rune <= 0x2199) ||
      (rune >= 0x21A9 && rune <= 0x21AA) ||
      (rune >= 0x231A && rune <= 0x231B) ||
      rune == 0x2328 ||
      rune == 0x23CF ||
      (rune >= 0x23E9 && rune <= 0x23F3) ||
      (rune >= 0x23F8 && rune <= 0x23FA) ||
      rune == 0x24C2 ||
      (rune >= 0x25AA && rune <= 0x25AB) ||
      rune == 0x25B6 ||
      rune == 0x25C0 ||
      (rune >= 0x25FB && rune <= 0x25FE) ||
      (rune >= 0x2934 && rune <= 0x2935) ||
      (rune >= 0x2B05 && rune <= 0x2B07) ||
      (rune >= 0x2B1B && rune <= 0x2B1C) ||
      rune == 0x2B50 ||
      rune == 0x2B55;
}

bool _isKeycapSequence(List<int> runes) {
  if (runes.isEmpty || !_isKeycapBaseRune(runes.first)) {
    return false;
  }
  return (runes.length == 2 && runes[1] == 0x20E3) ||
      (runes.length == 3 && runes[1] == 0xFE0F && runes[2] == 0x20E3);
}

bool _isKeycapBaseRune(int rune) {
  return (rune >= 0x30 && rune <= 0x39) || rune == 0x23 || rune == 0x2A;
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
