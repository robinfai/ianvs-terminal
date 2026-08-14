import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:fixnum/fixnum.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:ianvs_terminal/src/proto/frame_diff.pb.dart' as frame_pb;
import 'package:ianvs_terminal/src/transport/terminal_protobuf_frame_codec.dart';

/// Test-fixture builder for concise domain-model fixtures.
///
/// Product code never accepts this JSON shape; the runtime boundary is the
/// versioned Frame Packet v1 protobuf contract.
TerminalFrameDiff terminalFrameFromJson(Map<String, Object?> json) {
  final viewportRows = _nonNegativeInt(json['viewport_rows']);
  final viewportCols = _nonNegativeInt(json['viewport_cols']);
  final maxScrollback = _nonNegativeInt(json['scrollback_max_offset']);
  final cursor = _map(json['cursor']);
  final selection = _map(json['selection']);
  final modes = _map(json['modes']);
  final frame = TerminalFrameDiff(
    frameKind: json['frame_kind'] == 'delta'
        ? TerminalFrameKind.delta
        : TerminalFrameKind.snapshot,
    rows: _items(json['rows'], TerminalRow.tryFromJson),
    cursor: cursor == null
        ? const TerminalCursor(row: 0, col: 0, visible: false)
        : TerminalCursor.tryFromJson(cursor) ??
              const TerminalCursor(row: 0, col: 0, visible: false),
    selection: selection == null
        ? null
        : TerminalSelection.tryFromJson(selection),
    viewportRows: viewportRows,
    viewportCols: viewportCols,
    dirtyRanges: _items(json['dirty_ranges'], TerminalDirtyRange.tryFromJson),
    scrollbackOffset: _nonNegativeInt(
      json['scrollback_offset'],
    ).clamp(0, maxScrollback),
    scrollbackMaxOffset: maxScrollback,
    globalBottomRow: _optionalNonNegativeInt(json['global_bottom_row']),
    viewportStartRow: _nonNegativeInt(json['viewport_start_row']),
    viewportRowShift: _int(json['viewport_row_shift']),
    defaultForeground: _color(json['default_foreground']),
    defaultBackground: _color(json['default_background']),
    cursorColor: _color(json['cursor_color']),
    cursorGuideColor: _color(json['cursor_guide_color']),
    selectionBackground: _color(json['selection_background']),
    selectionForeground: _color(json['selection_foreground']),
    linkColor: _color(json['link_color']),
    cursorTextColor: _color(json['cursor_text_color']),
    tabColor: _color(json['tab_color']),
    pointerShape: TerminalPointerShape.fromWire(json['pointer_shape']),
    modes: modes == null
        ? TerminalFrameModes.empty
        : TerminalFrameModes.fromJson(modes),
    windowTitle: _string(json['window_title']),
    windowIconName: _string(json['window_icon_name']),
    fontFamily: _string(json['font_family']),
    hyperlinks: _items(json['hyperlinks'], TerminalHyperlinkRange.tryFromJson),
    sizedText: _items(
      json['sized_text'],
      TerminalSizedTextPlacement.tryFromJson,
    ),
    inlineImages: _items(
      json['inline_images'],
      TerminalInlineImage.tryFromJson,
    ),
    graphics: _items(json['graphics'], TerminalGraphicPlacement.tryFromJson),
    blocks: _items(json['blocks'], TerminalBlock.tryFromJson),
    inlineButtons: _items(
      json['inline_buttons'],
      TerminalInlineButton.tryFromJson,
    ),
  );
  return const TerminalProtobufFrameCodec().decode(
    _toProtobuf(frame).writeToBuffer(),
  );
}

Uint8List terminalFramePacketBytes({
  required String sessionId,
  required int sequence,
  required TerminalFrameDiff frame,
}) {
  final packet = frame_pb.TerminalFramePacketV1(
    schemaVersion: 1,
    contract: 'ianvs-terminal-frame-packet-v1',
    messageClass: 'frame',
    messageName: 'frame_diff',
    sessionId: sessionId,
    sequence: Int64(sequence),
    timestampMicros: Int64(sequence + 1),
    frameSchemaVersion: TerminalFrameDiff.currentFrameSchemaVersion,
    frame: _toProtobuf(frame),
  );
  return Uint8List.fromList(packet.writeToBuffer());
}

frame_pb.TerminalFrameDiff _toProtobuf(TerminalFrameDiff frame) {
  return frame_pb.TerminalFrameDiff(
    frameSchemaVersion: TerminalFrameDiff.currentFrameSchemaVersion,
    frameKind: switch (frame.frameKind) {
      TerminalFrameKind.snapshot =>
        frame_pb.TerminalFrameKind.TERMINAL_FRAME_KIND_SNAPSHOT,
      TerminalFrameKind.delta =>
        frame_pb.TerminalFrameKind.TERMINAL_FRAME_KIND_DELTA,
    },
    rows: [
      for (final row in frame.rows)
        frame_pb.TerminalRow(
          index: row.index,
          text: row.text,
          wrapped: row.wrapped,
          modifiedAtMicros: row.modifiedAt == null
              ? null
              : Int64(row.modifiedAt!.microsecondsSinceEpoch),
          styleRuns: [
            for (final run in row.styleRuns)
              frame_pb.TerminalStyleRun(
                start: run.start,
                end: run.end,
                foreground: _toColor(run.foreground),
                background: _toColor(run.background),
                underlineColor: _toColor(run.underlineColor),
                bold: run.bold,
                dim: run.dim,
                italic: run.italic,
                underline: run.underline,
                blink: run.blink,
                inverse: run.inverse,
              ),
          ],
          sourceRow: row.sourceRow,
          sourceEndRow: row.sourceEndRow,
        ),
    ],
    cursor: frame_pb.TerminalCursor(
      row: frame.cursor.row,
      col: frame.cursor.col,
      visible: frame.cursor.visible,
      highlightLine: frame.cursor.highlightLine,
      shape: frame.cursor.shape?.name,
      blink: frame.cursor.blink,
    ),
    selection: frame.selection == null
        ? null
        : frame_pb.TerminalSelection(
            present: true,
            startRow: frame.selection!.startRow,
            startCol: frame.selection!.startCol,
            endRow: frame.selection!.endRow,
            endCol: frame.selection!.endCol,
          ),
    viewportRows: frame.viewportRows,
    viewportCols: frame.viewportCols,
    dirtyRanges: [
      for (final range in frame.dirtyRanges)
        frame_pb.TerminalDirtyRange(
          start: range.start < 0 ? 0 : range.start,
          end: range.end < 0 ? 0 : range.end,
        ),
    ],
    scrollbackOffset: frame.scrollbackOffset,
    scrollbackMaxOffset: frame.scrollbackMaxOffset,
    globalBottomRow: frame.globalBottomRow == null
        ? null
        : Int64(frame.globalBottomRow!),
    viewportStartRow: frame.viewportStartRow,
    viewportRowShift: frame.viewportRowShift,
    defaultForeground: _toColor(frame.defaultForeground),
    defaultBackground: _toColor(frame.defaultBackground),
    cursorColor: _toColor(frame.cursorColor),
    cursorGuideColor: _toColor(frame.cursorGuideColor),
    selectionBackground: _toColor(frame.selectionBackground),
    selectionForeground: _toColor(frame.selectionForeground),
    linkColor: _toColor(frame.linkColor),
    cursorTextColor: _toColor(frame.cursorTextColor),
    tabColor: _toColor(frame.tabColor),
    pointerShape: frame.pointerShape?.wireName,
    modes: frame_pb.TerminalFrameModes(
      alternateScreen: frame.modes.alternateScreen,
      alternateScroll: frame.modes.alternateScroll,
      applicationCursor: frame.modes.applicationCursor,
      applicationKeypad: frame.modes.applicationKeypad,
      insertMode: frame.modes.insertMode,
      originMode: frame.modes.originMode,
      lineFeedNewLineMode: frame.modes.lineFeedNewLineMode,
      hideCursor: frame.modes.hideCursor,
      bracketedPaste: frame.modes.bracketedPaste,
      mimePaste: frame.modes.mimePaste,
      focusTracking: frame.modes.focusTracking,
      charProtected: frame.modes.charProtected,
      mouseMode: frame.modes.mouseMode,
      mouseEncoding: frame.modes.mouseEncoding,
      kittyKeyboardFlags: frame.modes.kittyKeyboardFlags,
      synchronizedOutput: frame.modes.synchronizedOutput,
    ),
    windowTitle: frame.windowTitle,
    windowIconName: frame.windowIconName,
    fontFamily: frame.fontFamily,
    hyperlinks: [
      for (final link in frame.hyperlinks)
        frame_pb.TerminalHyperlinkRange(
          row: link.row,
          startCol: link.startCol,
          endCol: link.endCol,
          uri: link.uri,
          protocolId: link.protocolId,
        ),
    ],
    sizedText: [
      for (final text in frame.sizedText)
        frame_pb.TerminalSizedTextPlacement(
          text: text.text,
          row: text.row,
          col: text.col,
          widthCells: text.widthCells,
          heightCells: text.heightCells,
          sourceRowOffsetCells: text.sourceRowOffsetCells,
          visibleHeightCells: text.visibleHeightCells,
          scale: text.scale,
          subscaleN: text.subscaleN,
          subscaleD: text.subscaleD,
          verticalAlign: text.verticalAlign,
          horizontalAlign: text.horizontalAlign,
          naturalWidth: text.naturalWidth,
          foreground: _toColor(text.foreground),
          background: _toColor(text.background),
          underlineColor: _toColor(text.underlineColor),
          bold: text.bold,
          dim: text.dim,
          italic: text.italic,
          underline: text.underline,
          blink: text.blink,
          inverse: text.inverse,
        ),
    ],
    inlineImages: [
      for (final image in frame.inlineImages)
        frame_pb.TerminalInlineImage(
          row: image.row,
          col: image.col,
          widthCells: image.widthCells,
          heightCells: image.heightCells,
          data: base64Encode(image.bytes),
          altText: image.altText,
        ),
    ],
    graphics: [
      for (final graphic in frame.graphics)
        frame_pb.TerminalGraphicPlacement(
          renderId: Int64(graphic.renderId),
          placementId: Int64(graphic.placementId),
          assetKey: frame_pb.TerminalGraphicAssetKey(
            assetId: Int64(graphic.assetKey.id),
            assetVersion: Int64(graphic.assetKey.version),
          ),
          protocol: graphic.protocol,
          row: graphic.row,
          col: graphic.col,
          widthPx: graphic.widthPx,
          heightPx: graphic.heightPx,
          widthCells: graphic.widthCells,
          heightCells: graphic.heightCells,
          sourceXOffsetPx: graphic.sourceXOffsetPx,
          visibleWidthPx: graphic.visibleWidthPx,
          sourceYOffsetPx: graphic.sourceYOffsetPx,
          visibleHeightPx: graphic.visibleHeightPx,
          zIndex: graphic.zIndex,
          xOffsetPx: graphic.xOffsetPx,
          yOffsetPx: graphic.yOffsetPx,
          preserveAspectRatio: graphic.preserveAspectRatio,
        ),
    ],
    blocks: [
      for (final block in frame.blocks)
        frame_pb.TerminalBlock(
          id: block.id,
          blockType: block.blockType,
          startRow: block.startRow,
          endRow: block.endRow,
          sourceStartRow: block.sourceStartRow,
          sourceEndRow: block.sourceEndRow,
          folded: block.folded,
          rendered: block.rendered,
          hiddenRows: block.hiddenRows,
        ),
    ],
    inlineButtons: [
      for (final button in frame.inlineButtons)
        frame_pb.TerminalInlineButton(
          id: Int64(button.id),
          kind: button.kind.name,
          row: button.row,
          col: button.col,
          code: button.code,
          icon: button.icon,
          blockId: button.blockId,
          valid: button.valid,
          widthCells: button.widthCells,
        ),
    ],
  );
}

frame_pb.ColorRgb? _toColor(Color? color) {
  if (color == null) {
    return null;
  }
  return frame_pb.ColorRgb(present: true, rgb: color.toARGB32() & 0xFFFFFF);
}

List<T> _items<T>(Object? value, T? Function(Map<String, Object?>) decode) {
  if (value is! List) {
    return <T>[];
  }
  return <T>[
    for (final item in value)
      if (_map(item) case final map?) ?decode(map),
  ];
}

Map<String, Object?>? _map(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    return null;
  }
  return value.cast<String, Object?>();
}

int _int(Object? value) => value is int ? value : 0;

String? _string(Object? value) => value is String ? value : null;

int _nonNegativeInt(Object? value) => _int(value).clamp(0, 0x7fffffff);

int? _optionalNonNegativeInt(Object? value) {
  return value is int && value >= 0 ? value : null;
}

Color? _color(Object? value) {
  if (value is! String) {
    return null;
  }
  final normalized = value.trim();
  if (!RegExp(r'^#(?:[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$').hasMatch(normalized)) {
    return null;
  }
  final rgb = normalized.length == 9
      ? normalized.substring(3)
      : normalized.substring(1);
  return Color(0xFF000000 | int.parse(rgb, radix: 16));
}
