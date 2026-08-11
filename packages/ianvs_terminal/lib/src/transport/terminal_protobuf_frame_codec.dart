import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import '../config/terminal_config.dart';
import '../contracts/terminal_frame_normalization_policy.dart';
import '../contracts/terminal_frame_validation_limits.dart';
import '../contracts/terminal_wire_compatibility.dart';
import '../proto/frame_diff.pb.dart' as frame_pb;
import '../terminal/terminal_frame_decode_ports.dart';
import '../terminal/terminal_models.dart';

const int _maxInlineImageEncodedLength =
    ((TerminalFrameValidationLimits.maxInlineImageDecodedBytes + 2) ~/ 3) * 4;

/// Transport adapter that decodes generated protobuf data into pure terminal
/// domain models.
final class TerminalProtobufFrameCodec implements TerminalBinaryFrameCodecPort {
  const TerminalProtobufFrameCodec();

  @override
  TerminalFrameDiff decode(List<int> bytes) {
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

/// Transitional source-level migration facade for the former
/// `TerminalFrameDiff.fromProtobufBytes` factory.
// This deprecation is intentionally introduced with 2.0 so internal workspace
// consumers have one full major release to migrate to the transport codec.
// ignore: remove_deprecations_in_breaking_versions
@Deprecated(
  'Use const TerminalProtobufFrameCodec().decode(bytes). '
  'This facade will be removed in the next major version.',
)
abstract final class LegacyTerminalFrameDiffProtobuf {
  static TerminalFrameDiff fromProtobufBytes(List<int> bytes) {
    return const TerminalProtobufFrameCodec().decode(bytes);
  }
}

TerminalFrameDiff _terminalFrameDiffFromProtobuf(
  frame_pb.TerminalFrameDiff proto,
) {
  final viewportRows = TerminalFrameNormalizationPolicy.clampNativeDimension(
    proto.viewportRows,
  );
  final viewportCols = TerminalFrameNormalizationPolicy.clampNativeDimension(
    proto.viewportCols,
  );
  final scrollbackMaxOffset = proto.scrollbackMaxOffset;
  final scrollbackOffset = proto.scrollbackOffset.clamp(0, scrollbackMaxOffset);
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
        ? TerminalFrameNormalizationPolicy.optionalNonNegativeScalar(
            proto.globalBottomRow.toInt(),
          )
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
        ? TerminalFrameNormalizationPolicy.fontFamily(proto.fontFamily)
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
  return TerminalFrameNormalizationPolicy.normalizedRows(
    values: rows,
    viewportRows: viewportRows,
    viewportCols: viewportCols,
    rawIndexOf: (row) => row.index,
    decode: _terminalRowFromProtobuf,
    indexOf: (row) => row.index,
    boundToColumns: (row, viewportCols) =>
        row.boundedToViewportColumns(viewportCols),
  );
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
        ? TerminalCursorShape.fromWire(cursor.shape)
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
    mouseMode: TerminalFrameNormalizationPolicy.mouseMode(modes.mouseMode),
    mouseEncoding: TerminalFrameNormalizationPolicy.mouseEncoding(
      modes.mouseEncoding,
    ),
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
  if (protocol == null) {
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

List<TerminalDirtyRange> _dirtyRangesFromProtobuf(
  Iterable<frame_pb.TerminalDirtyRange> ranges,
  int viewportRows,
) {
  final maxEntries = TerminalFrameValidationLimits.maxViewportBoundedEntries(
    viewportRows,
  );
  final scanLimit = TerminalFrameValidationLimits.maxEntriesToScan(maxEntries);
  return _normalizeDirtyRanges(
    ranges
        .take(scanLimit)
        .map((range) => TerminalDirtyRange(start: range.start, end: range.end)),
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

List<TerminalDirtyRange> _normalizeDirtyRanges(
  Iterable<TerminalDirtyRange> ranges,
  int viewportRows,
) {
  return TerminalFrameNormalizationPolicy.normalizeDirtyRanges(
    ranges: ranges,
    viewportRows: viewportRows,
    startOf: (range) => range.start,
    endOf: (range) => range.end,
    create: (start, end) => TerminalDirtyRange(start: start, end: end),
  );
}

List<TerminalGraphicPlacement> _normalizeGraphics({
  required Iterable<TerminalGraphicPlacement?> graphics,
  required int viewportRows,
  required int viewportCols,
}) {
  return TerminalFrameNormalizationPolicy.normalizeGraphics(
    graphics: graphics,
    viewportRows: viewportRows,
    viewportCols: viewportCols,
    rowOf: (graphic) => graphic.row,
    colOf: (graphic) => graphic.col,
    widthPxOf: (graphic) => graphic.widthPx,
    heightPxOf: (graphic) => graphic.heightPx,
    widthCellsOf: (graphic) => graphic.widthCells,
    heightCellsOf: (graphic) => graphic.heightCells,
    sourceXOffsetPxOf: (graphic) => graphic.sourceXOffsetPx,
    visibleWidthPxOf: (graphic) => graphic.visibleWidthPx,
    sourceYOffsetPxOf: (graphic) => graphic.sourceYOffsetPx,
    visibleHeightPxOf: (graphic) => graphic.visibleHeightPx,
    assetIdOf: (graphic) => graphic.assetKey.id,
    assetVersionOf: (graphic) => graphic.assetKey.version,
    zIndexOf: (graphic) => graphic.zIndex,
  );
}
