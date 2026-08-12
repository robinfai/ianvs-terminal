import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:ianvs_terminal/src/proto/frame_diff.pb.dart' as frame_pb;
import 'package:ianvs_terminal/src/transport/terminal_protobuf_frame_codec.dart';

/// Test-only builder for the sole current native Frame Packet v1 contract.
///
/// Product code never accepts the concise map shape used by example tests.
TerminalFrameDiff terminalFrameFixtureFromJson(Map<String, Object?> json) {
  return const TerminalProtobufFrameCodec().decode(
    _frameProtoFromFixture(json).writeToBuffer(),
  );
}

Uint8List terminalFramePacketFixture({
  required String sessionId,
  required int sequence,
  required Map<String, Object?> frame,
}) {
  final proto = frame_pb.TerminalFramePacketV1(
    schemaVersion: 1,
    contract: 'ianvs-terminal-frame-packet-v1',
    messageClass: 'frame',
    messageName: 'frame_diff',
    sessionId: sessionId,
    sequence: Int64(sequence),
    timestampMicros: Int64(sequence + 1),
    frameSchemaVersion: TerminalFrameDiff.currentFrameSchemaVersion,
    frame: _frameProtoFromFixture(frame),
  );
  return Uint8List.fromList(proto.writeToBuffer());
}

frame_pb.TerminalFrameDiff _frameProtoFromFixture(Map<String, Object?> json) {
  final cursor = _map(json['cursor']);
  final selection = _map(json['selection']);
  final modes = _map(json['modes']);
  final maxOffset = _nonNegativeInt(json['scrollback_max_offset']);
  return frame_pb.TerminalFrameDiff(
    frameSchemaVersion: TerminalFrameDiff.currentFrameSchemaVersion,
    frameKind: json['frame_kind'] == 'delta'
        ? frame_pb.TerminalFrameKind.TERMINAL_FRAME_KIND_DELTA
        : frame_pb.TerminalFrameKind.TERMINAL_FRAME_KIND_SNAPSHOT,
    rows: _maps(json['rows']).map(
      (row) => frame_pb.TerminalRow(
        index: _int(row['index']),
        text: row['text'] is String ? row['text']! as String : '',
        wrapped: row['wrapped'] == true,
        modifiedAtMicros: _dateTimeMicros(row['modified_at']),
        styleRuns: _maps(row['style_runs']).map(_styleRunProto),
        sourceRow: _optionalNonNegativeInt(row['source_row']),
        sourceEndRow: _optionalNonNegativeInt(row['source_end_row']),
      ),
    ),
    cursor: frame_pb.TerminalCursor(
      row: _nonNegativeInt(cursor?['row']),
      col: _nonNegativeInt(cursor?['col']),
      visible: cursor?['visible'] == true,
      highlightLine: cursor?['highlight_line'] == true,
      shape: cursor?['shape'] is String ? cursor!['shape']! as String : '',
      blink: cursor?['blink'] == true,
    ),
    selection: selection == null
        ? null
        : frame_pb.TerminalSelection(
            present: true,
            startRow: _nonNegativeInt(selection['start_row']),
            startCol: _nonNegativeInt(selection['start_col']),
            endRow: _nonNegativeInt(selection['end_row']),
            endCol: _nonNegativeInt(selection['end_col']),
          ),
    viewportRows: _nonNegativeInt(json['viewport_rows']),
    viewportCols: _nonNegativeInt(json['viewport_cols']),
    dirtyRanges: _maps(json['dirty_ranges']).map(
      (range) => frame_pb.TerminalDirtyRange(
        start: _nonNegativeInt(range['start']),
        end: _nonNegativeInt(range['end']),
      ),
    ),
    scrollbackOffset: _nonNegativeInt(
      json['scrollback_offset'],
    ).clamp(0, maxOffset),
    scrollbackMaxOffset: maxOffset,
    globalBottomRow: json['global_bottom_row'] is int
        ? Int64(json['global_bottom_row']! as int)
        : null,
    viewportStartRow: _nonNegativeInt(json['viewport_start_row']),
    viewportRowShift: _int(json['viewport_row_shift']),
    defaultForeground: _colorProto(json['default_foreground']),
    defaultBackground: _colorProto(json['default_background']),
    cursorColor: _colorProto(json['cursor_color']),
    cursorGuideColor: _colorProto(json['cursor_guide_color']),
    selectionBackground: _colorProto(json['selection_background']),
    selectionForeground: _colorProto(json['selection_foreground']),
    linkColor: _colorProto(json['link_color']),
    cursorTextColor: _colorProto(json['cursor_text_color']),
    tabColor: _colorProto(json['tab_color']),
    pointerShape: _string(json['pointer_shape']),
    modes: modes == null ? null : _modesProto(modes),
    windowTitle: json['window_title'] is String
        ? json['window_title']! as String
        : null,
    windowIconName: json['window_icon_name'] is String
        ? json['window_icon_name']! as String
        : null,
    fontFamily: json['font_family'] is String
        ? json['font_family']! as String
        : null,
    hyperlinks: _maps(json['hyperlinks']).map(
      (link) => frame_pb.TerminalHyperlinkRange(
        row: _nonNegativeInt(link['row']),
        startCol: _nonNegativeInt(link['start_col']),
        endCol: _nonNegativeInt(link['end_col']),
        uri: _string(link['uri']),
        protocolId: _string(link['protocol_id']),
      ),
    ),
    sizedText: _maps(json['sized_text']).map(_sizedTextProto),
    inlineImages: _maps(json['inline_images']).map(
      (image) => frame_pb.TerminalInlineImage(
        data: _string(image['data']),
        mimeType: _string(image['mime_type']),
        row: _nonNegativeInt(image['row']),
        col: _nonNegativeInt(image['col']),
        widthCells: _positiveInt(image['width_cells'], fallback: 1),
        heightCells: _positiveInt(image['height_cells'], fallback: 1),
        altText: _string(image['alt_text']),
      ),
    ),
    graphics: _maps(json['graphics']).map(_graphicProto),
    blocks: _maps(json['blocks']).map(
      (block) => frame_pb.TerminalBlock(
        id: _string(block['id']),
        blockType: _string(block['block_type']),
        startRow: _nonNegativeInt(block['start_row']),
        endRow: _nonNegativeInt(block['end_row']),
        sourceStartRow: _nonNegativeInt(block['source_start_row']),
        sourceEndRow: _nonNegativeInt(block['source_end_row']),
        folded: block['folded'] == true,
        hiddenRows: _nonNegativeInt(block['hidden_rows']),
        rendered: block['rendered'] == true,
      ),
    ),
    inlineButtons: _maps(json['inline_buttons']).map(
      (button) => frame_pb.TerminalInlineButton(
        id: Int64(_nonNegativeInt(button['id'])),
        kind: _string(button['kind']),
        row: _nonNegativeInt(button['row']),
        col: _nonNegativeInt(button['col']),
        code: button['code'] is int ? button['code']! as int : null,
        icon: _string(button['icon']),
        blockId: _string(button['block_id']),
        valid: button['valid'] == true,
        widthCells: _positiveInt(button['width_cells'], fallback: 1),
      ),
    ),
  );
}

frame_pb.TerminalStyleRun _styleRunProto(Map<String, Object?> run) {
  return frame_pb.TerminalStyleRun(
    start: _nonNegativeInt(run['start']),
    end: _nonNegativeInt(run['end']),
    foreground: _colorProto(run['foreground']),
    background: _colorProto(run['background']),
    underlineColor: _colorProto(run['underline_color']),
    bold: run['bold'] == true,
    dim: run['dim'] == true,
    italic: run['italic'] == true,
    underline: run['underline'] == true,
    blink: run['blink'] == true,
    inverse: run['inverse'] == true,
  );
}

frame_pb.TerminalFrameModes _modesProto(Map<String, Object?> modes) {
  return frame_pb.TerminalFrameModes(
    alternateScreen: modes['alternate_screen'] == true,
    alternateScroll: modes['alternate_scroll'] == true,
    applicationCursor: modes['application_cursor'] == true,
    applicationKeypad: modes['application_keypad'] == true,
    insertMode: modes['insert_mode'] == true,
    originMode: modes['origin_mode'] == true,
    lineFeedNewLineMode: modes['line_feed_new_line_mode'] == true,
    hideCursor: modes['hide_cursor'] == true,
    bracketedPaste: modes['bracketed_paste'] == true,
    mimePaste: modes['mime_paste'] == true,
    focusTracking: modes['focus_tracking'] == true,
    charProtected: modes['char_protected'] == true,
    mouseMode: _string(modes['mouse_mode']),
    mouseEncoding: _string(modes['mouse_encoding']),
    kittyKeyboardFlags: _nonNegativeInt(modes['kitty_keyboard_flags']),
    synchronizedOutput: modes['synchronized_output'] == true,
  );
}

frame_pb.TerminalSizedTextPlacement _sizedTextProto(
  Map<String, Object?> placement,
) {
  return frame_pb.TerminalSizedTextPlacement(
    text: _string(placement['text']),
    row: _nonNegativeInt(placement['row']),
    col: _nonNegativeInt(placement['col']),
    widthCells: _nonNegativeInt(placement['width_cells']),
    heightCells: _nonNegativeInt(placement['height_cells']),
    sourceRowOffsetCells: _nonNegativeInt(placement['source_row_offset_cells']),
    visibleHeightCells: _nonNegativeInt(placement['visible_height_cells']),
    scale: _nonNegativeInt(placement['scale']),
    subscaleN: _nonNegativeInt(placement['subscale_n']),
    subscaleD: _nonNegativeInt(placement['subscale_d']),
    verticalAlign: _nonNegativeInt(placement['vertical_align']),
    horizontalAlign: _nonNegativeInt(placement['horizontal_align']),
    naturalWidth: placement['natural_width'] == true,
    foreground: _colorProto(placement['foreground']),
    background: _colorProto(placement['background']),
    underlineColor: _colorProto(placement['underline_color']),
    bold: placement['bold'] == true,
    dim: placement['dim'] == true,
    italic: placement['italic'] == true,
    underline: placement['underline'] == true,
    blink: placement['blink'] == true,
    inverse: placement['inverse'] == true,
  );
}

frame_pb.TerminalGraphicPlacement _graphicProto(Map<String, Object?> graphic) {
  final assetKey = _map(graphic['asset_key']);
  return frame_pb.TerminalGraphicPlacement(
    placementId: Int64(_nonNegativeInt(graphic['placement_id'])),
    renderId: Int64(_nonNegativeInt(graphic['render_id'])),
    assetKey: frame_pb.TerminalGraphicAssetKey(
      assetId: Int64(_nonNegativeInt(assetKey?['asset_id'])),
      assetVersion: Int64(_nonNegativeInt(assetKey?['asset_version'])),
    ),
    protocol: _string(graphic['protocol']),
    row: _nonNegativeInt(graphic['row']),
    col: _nonNegativeInt(graphic['col']),
    widthPx: _nonNegativeInt(graphic['width_px']),
    heightPx: _nonNegativeInt(graphic['height_px']),
    widthCells: _nonNegativeInt(graphic['width_cells']),
    heightCells: _nonNegativeInt(graphic['height_cells']),
    sourceXOffsetPx: _nonNegativeInt(graphic['source_x_offset_px']),
    visibleWidthPx: _nonNegativeInt(graphic['visible_width_px']),
    sourceYOffsetPx: _nonNegativeInt(graphic['source_y_offset_px']),
    visibleHeightPx: _nonNegativeInt(graphic['visible_height_px']),
    zIndex: _int(graphic['z_index']),
    xOffsetPx: _nonNegativeInt(graphic['x_offset_px']),
    yOffsetPx: _nonNegativeInt(graphic['y_offset_px']),
    preserveAspectRatio: graphic['preserve_aspect_ratio'] == true,
  );
}

frame_pb.ColorRgb? _colorProto(Object? value) {
  if (value is! String) return null;
  final normalized = value.trim();
  var digits = normalized.startsWith('#')
      ? normalized.substring(1)
      : normalized;
  if (RegExp(r'^[fF]{2}[0-9a-fA-F]{6}$').hasMatch(digits)) {
    digits = digits.substring(2);
  }
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(digits)) return null;
  return frame_pb.ColorRgb(present: true, rgb: int.parse(digits, radix: 16));
}

Int64? _dateTimeMicros(Object? value) {
  if (value is! String) return null;
  final parsed = DateTime.tryParse(value);
  return parsed == null ? null : Int64(parsed.toUtc().microsecondsSinceEpoch);
}

Map<String, Object?>? _map(Object? value) {
  return value is Map ? value.cast<String, Object?>() : null;
}

Iterable<Map<String, Object?>> _maps(Object? value) sync* {
  if (value is! List) return;
  for (final item in value) {
    final mapped = _map(item);
    if (mapped != null) yield mapped;
  }
}

int _int(Object? value) => value is int ? value : 0;

int _nonNegativeInt(Object? value) => _int(value).clamp(0, 1 << 31);

int? _optionalNonNegativeInt(Object? value) {
  return value is int ? value.clamp(0, 1 << 31) : null;
}

int _positiveInt(Object? value, {required int fallback}) {
  final decoded = _int(value);
  return decoded > 0 ? decoded : fallback;
}

String? _string(Object? value) => value is String ? value : null;
