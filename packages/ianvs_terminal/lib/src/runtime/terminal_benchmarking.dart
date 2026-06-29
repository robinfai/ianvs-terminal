import 'dart:ui';

import '../terminal/terminal_models.dart';

typedef TerminalBenchmarkEventSink = void Function(Map<String, Object?> event);

String terminalBenchmarkViewportHash(TerminalFrameDiff frame) {
  var hash = 0x811c9dc5;
  void addCodeUnit(int codeUnit) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }

  for (final codeUnit
      in 'cols=${frame.viewportCols};rows=${frame.viewportRows};start=${frame.viewportStartRow}\n'
          .codeUnits) {
    addCodeUnit(codeUnit);
  }
  for (final row in frame.rows) {
    for (final codeUnit
        in '${row.index}|${row.wrapped}|${row.text}\n'.codeUnits) {
      addCodeUnit(codeUnit);
    }
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

Map<String, Object?> terminalBenchmarkFrameTimingEvent(
  FrameTiming timing, {
  int? timestampMicros,
}) {
  final totalSpanMicros = timing.totalSpan.inMicroseconds;
  return <String, Object?>{
    'schema_version': 'ianvs-bench-flutter-frame-timing-v1',
    'timestamp_micros':
        timestampMicros ?? DateTime.now().microsecondsSinceEpoch,
    'build_duration_micros': timing.buildDuration.inMicroseconds,
    'raster_duration_micros': timing.rasterDuration.inMicroseconds,
    'total_span_micros': totalSpanMicros,
    'missed_vsync': totalSpanMicros > 16666,
  };
}
