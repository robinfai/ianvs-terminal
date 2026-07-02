import '../runtime/terminal_benchmarking.dart';
import 'terminal_models.dart';

const String terminalGraphicsDiagnosticSchemaVersion =
    'ianvs-terminal-graphics-diagnostic-v1';

void emitTerminalGraphicsDiagnostic(
  TerminalBenchmarkEventSink? sink, {
  required String layer,
  required String event,
  String? sessionId,
  TerminalGraphicAssetKey? assetKey,
  Iterable<TerminalGraphicPlacement>? graphics,
  Map<String, Object?> fields = const <String, Object?>{},
}) {
  if (sink == null) {
    return;
  }
  final eventMap = <String, Object?>{
    'schema_version': terminalGraphicsDiagnosticSchemaVersion,
    'timestamp_micros': DateTime.now().microsecondsSinceEpoch,
    'layer': layer,
    'event': event,
    ...fields,
  };
  if (sessionId != null) {
    eventMap['session_id'] = sessionId;
  }
  if (assetKey != null) {
    eventMap['asset_key'] = terminalGraphicsAssetKeyJson(assetKey);
  }
  if (graphics != null) {
    eventMap.addAll(terminalGraphicsSummaryJson(graphics));
  }
  sink(eventMap);
}

Map<String, Object?> terminalGraphicsAssetKeyJson(TerminalGraphicAssetKey key) {
  return <String, Object?>{'id': key.id, 'version': key.version};
}

Map<String, Object?> terminalGraphicsSummaryJson(
  Iterable<TerminalGraphicPlacement> graphics,
) {
  final items = graphics.toList(growable: false);
  return <String, Object?>{
    'graphics_count': items.length,
    'graphics_signature': terminalGraphicsSignature(items),
    'graphics': [
      for (final graphic in items)
        <String, Object?>{
          'render_id': graphic.renderId,
          'placement_id': graphic.placementId,
          'asset_key': terminalGraphicsAssetKeyJson(graphic.assetKey),
          'protocol': graphic.protocol,
          'row': graphic.row,
          'col': graphic.col,
          'width_cells': graphic.widthCells,
          'height_cells': graphic.heightCells,
          'z_index': graphic.zIndex,
        },
    ],
  };
}

String terminalGraphicsSignature(Iterable<TerminalGraphicPlacement> graphics) {
  return graphics
      .map(
        (graphic) =>
            '${graphic.renderId}:${graphic.placementId}:'
            '${graphic.assetKey.id}/${graphic.assetKey.version}:'
            '${graphic.row},${graphic.col}:'
            '${graphic.widthCells}x${graphic.heightCells}:'
            '${graphic.zIndex}',
      )
      .join('|');
}
