import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

List<Map<String, Object?>> terminalRuntimeFrameEvents(
  Iterable<Map<String, Object?>> events,
) {
  return events
      .where(
        (event) => event['schema_version'] == 'ianvs-bench-dart-runtime-v1',
      )
      .toList(growable: false);
}

Map<String, Object?> writeTerminalRenderProfileReport({
  required Directory outputDir,
  required String workload,
  required String policy,
  required int repeatIndex,
  required String targetPlatform,
  required String targetDevice,
  required int semanticGenerations,
  required List<Map<String, Object?>> flutterRenderEvents,
  required List<Map<String, Object?>> flutterFrameTimingEvents,
  List<Map<String, Object?>> dartRuntimeEvents = const <Map<String, Object?>>[],
  required String expectedViewportHash,
  required String actualViewportHash,
  DateTime? startedAt,
  DateTime? completedAt,
}) {
  outputDir.createSync(recursive: true);
  final started = startedAt ?? DateTime.now().toUtc();
  final completed = completedAt ?? DateTime.now().toUtc();
  final hashMatch = expectedViewportHash == actualViewportHash;
  final runtimeFrameEvents = terminalRuntimeFrameEvents(dartRuntimeEvents);

  _writeJson(File('${outputDir.path}/metadata.json'), <String, Object?>{
    'schema_version': 'ianvs-bench-metadata-v1',
    'workload': workload,
    'repeat_index': repeatIndex,
    'started_at': started.toIso8601String(),
    'completed_at': completed.toIso8601String(),
    'runner': 'flutter_drive_profile',
    'target': <String, Object?>{
      'platform': targetPlatform,
      'device': targetDevice,
      'flutter_mode': 'profile',
    },
    'mode': <String, Object?>{
      'frame_policy': policy,
      'renderer': 'flutter',
      'engine': 'real',
      'wire_format': _wireFormatFor(runtimeFrameEvents),
    },
  });
  _writeJson(File('${outputDir.path}/correctness.json'), <String, Object?>{
    'schema_version': 'ianvs-bench-correctness-v1',
    'workload': workload,
    'reference_policy': policy,
    'tested_policy': policy,
    'reference_hash': expectedViewportHash,
    'tested_hash': actualViewportHash,
    'hash_match': hashMatch,
  });
  _writeNdjson(
    File('${outputDir.path}/flutter_render.ndjson'),
    flutterRenderEvents,
  );
  _writeNdjson(
    File('${outputDir.path}/flutter_frame_timing.ndjson'),
    flutterFrameTimingEvents,
  );
  _writeNdjson(
    File('${outputDir.path}/dart_runtime.ndjson'),
    runtimeFrameEvents,
  );

  final summary = _summarize(
    workload: workload,
    policy: policy,
    repeatIndex: repeatIndex,
    targetPlatform: targetPlatform,
    targetDevice: targetDevice,
    semanticGenerations: semanticGenerations,
    hashMatch: hashMatch,
    flutterRenderEvents: flutterRenderEvents,
    flutterFrameTimingEvents: flutterFrameTimingEvents,
    dartRuntimeEvents: runtimeFrameEvents,
  );
  _writeSummary(outputDir, summary);
  return summary;
}

void writeTerminalRenderProfileAggregateSummary(
  Directory outputDir,
  List<Map<String, Object?>> summaries,
) {
  outputDir.createSync(recursive: true);
  final csv = StringBuffer()..writeln(_summaryCsvHeader.join(','));
  for (final summary in summaries) {
    csv.writeln(_summaryCsvRow(summary).join(','));
  }
  File('${outputDir.path}/summary.csv').writeAsStringSync(csv.toString());

  final groupedSummaries = _groupSummariesByWorkload(summaries);
  final groupedCsv = StringBuffer()
    ..writeln(_groupedSummaryCsvHeader.join(','));
  for (final summary in groupedSummaries) {
    groupedCsv.writeln(_groupedSummaryCsvRow(summary).join(','));
  }
  File(
    '${outputDir.path}/summary_by_workload.csv',
  ).writeAsStringSync(groupedCsv.toString());

  final md = StringBuffer()
    ..writeln('# Flutter Render Profile Matrix Summary')
    ..writeln()
    ..writeln(
      '| target | workload | repeat | hash match | frames | p95 total span |',
    )
    ..writeln('|---|---|---:|---:|---:|---:|');
  for (final summary in summaries) {
    md.writeln(
      '| ${summary['target_device']} | ${summary['workload']} (${summary['wire_format']}) | '
      '${summary['repeat']} | ${summary['hash_match']} | '
      '${summary['frames_presented']} | '
      '${_display(summary['p95_total_span_micros'])} |',
    );
  }
  md
    ..writeln()
    ..writeln('## By Workload')
    ..writeln()
    ..writeln(
      '| target | workload | repeats | hash matches | avg p95 total span | missed vsync |',
    )
    ..writeln('|---|---|---:|---:|---:|---:|');
  for (final summary in groupedSummaries) {
    md.writeln(
      '| ${summary['target_device']} | ${summary['workload']} (${summary['wire_format']}) | '
      '${summary['repeat_count']} | ${summary['hash_match_count']} | '
      '${_display(summary['p95_total_span_micros_avg'])} | '
      '${summary['missed_vsync_count_total']} |',
    );
  }
  File('${outputDir.path}/summary.md').writeAsStringSync(md.toString());
}

Map<String, Object?> _summarize({
  required String workload,
  required String policy,
  required int repeatIndex,
  required String targetPlatform,
  required String targetDevice,
  required int semanticGenerations,
  required bool hashMatch,
  required List<Map<String, Object?>> flutterRenderEvents,
  required List<Map<String, Object?>> flutterFrameTimingEvents,
  required List<Map<String, Object?>> dartRuntimeEvents,
}) {
  final surfacePaintEvents = flutterRenderEvents
      .where(
        (event) => event['schema_version'] == 'ianvs-bench-flutter-render-v1',
      )
      .toList(growable: false);
  final cursorPaintEvents = flutterRenderEvents
      .where(
        (event) => event['schema_version'] == 'ianvs-bench-flutter-cursor-v1',
      )
      .toList(growable: false);
  final surfaceNonFramePaintEvents = surfacePaintEvents
      .where((event) => event['paint_kind'] == 'non_frame')
      .toList(growable: false);
  final frameCount = surfacePaintEvents.length;
  final cacheHits = _sumInt(surfacePaintEvents, 'row_cache_hits');
  final cacheMisses = _sumInt(surfacePaintEvents, 'row_cache_misses');
  final runtimeFrameCount = dartRuntimeEvents.length;
  final frameBuildDurations = _completeNonNegativeIntValues(
    flutterFrameTimingEvents,
    'build_duration_micros',
  );
  final frameRasterDurations = _completeNonNegativeIntValues(
    flutterFrameTimingEvents,
    'raster_duration_micros',
  );
  final frameTotalSpans = _completeNonNegativeIntValues(
    flutterFrameTimingEvents,
    'total_span_micros',
  );
  final surfacePaintDurations = _completeNonNegativeIntValues(
    surfacePaintEvents,
    'paint_micros',
  );
  final surfaceNonFramePaintDurations = _completeNonNegativeIntValues(
    surfaceNonFramePaintEvents,
    'paint_micros',
  );
  final cursorPaintDurations = _completeNonNegativeIntValues(
    cursorPaintEvents,
    'paint_micros',
  );
  final overlayLayerEvents = cursorPaintEvents.isNotEmpty
      ? cursorPaintEvents
      : surfacePaintEvents;
  final missedVsyncMetricValid =
      flutterFrameTimingEvents.isNotEmpty &&
      flutterFrameTimingEvents.every((event) => event['missed_vsync'] is bool);
  final surfaceWorkloadHasNoOverlay =
      cursorPaintEvents.isEmpty &&
      (workload == 'cursor_blink_idle_profile' ||
          workload == 'cursor_blink_idle_surface_profile');
  final overlayLayerCountMetricValid =
      surfaceWorkloadHasNoOverlay ||
      _allFiniteNumbers(
        overlayLayerEvents,
        'overlay_layer_count',
        nonNegative: true,
        integer: true,
      );
  final cursorPaintBoundsMetricValid = _allFiniteNumbers(
    cursorPaintEvents,
    'paint_bounds_area',
    nonNegative: true,
  );
  final cursorCellWidthMetricValid = _allFiniteNumbers(
    cursorPaintEvents,
    'cell_width_px',
    positive: true,
  );
  final cursorCellHeightMetricValid = _allFiniteNumbers(
    cursorPaintEvents,
    'cell_height_px',
    positive: true,
  );
  final cursorDevicePixelRatioMetricValid = _allFiniteNumbers(
    cursorPaintEvents,
    'device_pixel_ratio',
    positive: true,
  );
  final cursorPictureLiveCountMetricValid = _allFiniteNumbers(
    cursorPaintEvents,
    'cursor_picture_live_count',
    nonNegative: true,
    integer: true,
  );
  final cursorPictureEstimatedBytesMetricValid = _allFiniteNumbers(
    cursorPaintEvents,
    'cursor_picture_estimated_bytes',
    nonNegative: true,
  );
  final sampledBlinkTransitions =
      workload == 'cursor_blink_idle_overlay_profile'
      ? cursorPaintEvents.length
      : workload == 'cursor_blink_idle_profile' ||
            workload == 'cursor_blink_idle_surface_profile'
      ? surfaceNonFramePaintEvents.length
      : 0;
  return <String, Object?>{
    'workload': workload,
    'policy': policy,
    'repeat': repeatIndex,
    'target_platform': targetPlatform,
    'target_device': targetDevice,
    'wire_format': _wireFormatFor(dartRuntimeEvents),
    'hash_match': hashMatch,
    'semantic_generations': semanticGenerations,
    'frame_diffs_generated': runtimeFrameCount == 0
        ? frameCount
        : runtimeFrameCount,
    'frames_presented': frameCount,
    'coalescing_ratio': frameCount == 0
        ? 'N/A'
        : semanticGenerations / frameCount,
    'snapshot_count': surfacePaintEvents
        .where((event) => event['frame_kind'] == 'snapshot')
        .length,
    'delta_count': surfacePaintEvents
        .where((event) => event['frame_kind'] == 'delta')
        .length,
    'avg_rows_emitted': _averageIntValues(
      dartRuntimeEvents,
      'native_rows_emitted',
    ),
    'p95_frame_build_micros': _percentile(
      _intValues(dartRuntimeEvents, 'native_frame_build_micros'),
      95,
    ),
    'p95_apply_frame_micros': _percentile(
      _intValues(dartRuntimeEvents, 'apply_frame_micros'),
      95,
    ),
    'runtime_frame_count': runtimeFrameCount,
    'runtime_raw_frame_bytes_total': _sumInt(
      dartRuntimeEvents,
      'raw_frame_bytes',
    ),
    'p95_json_decode_micros': _percentile(
      _intValues(dartRuntimeEvents, 'json_decode_micros'),
      95,
    ),
    'p95_protobuf_decode_micros': _percentile(
      _intValues(dartRuntimeEvents, 'protobuf_decode_micros'),
      95,
    ),
    'p95_native_json_encode_micros': _percentile(
      _intValues(dartRuntimeEvents, 'native_json_encode_micros'),
      95,
    ),
    'p95_native_protobuf_encode_micros': _percentile(
      _intValues(dartRuntimeEvents, 'native_protobuf_encode_micros'),
      95,
    ),
    'p50_build_duration_micros': _percentile(frameBuildDurations, 50),
    'p95_build_duration_micros': _percentile(frameBuildDurations, 95),
    'p50_raster_duration_micros': _percentile(frameRasterDurations, 50),
    'p95_raster_duration_micros': _percentile(frameRasterDurations, 95),
    'p99_raster_duration_micros': _percentile(frameRasterDurations, 99),
    'p50_total_span_micros': _percentile(frameTotalSpans, 50),
    'p95_total_span_micros': _percentile(frameTotalSpans, 95),
    'p95_paint_micros': _percentile(surfacePaintDurations, 95),
    'p50_surface_paint_micros': _percentile(surfaceNonFramePaintDurations, 50),
    'p95_surface_paint_micros': _percentile(surfaceNonFramePaintDurations, 95),
    'p50_cursor_paint_micros': _percentile(cursorPaintDurations, 50),
    'p95_cursor_paint_micros': _percentile(cursorPaintDurations, 95),
    'sampled_blink_transitions': sampledBlinkTransitions,
    'surface_non_frame_paint_count': surfaceNonFramePaintEvents.length,
    'cursor_paint_count': cursorPaintEvents.length,
    'max_cursor_paint_bounds_area': _maxNumOrZero(
      cursorPaintEvents,
      'paint_bounds_area',
    ),
    'max_cursor_cell_width_px': _maxNumOrZero(
      cursorPaintEvents,
      'cell_width_px',
    ),
    'max_cursor_cell_height_px': _maxNumOrZero(
      cursorPaintEvents,
      'cell_height_px',
    ),
    'max_cursor_device_pixel_ratio': _maxNumOrZero(
      cursorPaintEvents,
      'device_pixel_ratio',
    ),
    'max_cursor_picture_live_count': _maxNumOrZero(
      cursorPaintEvents,
      'cursor_picture_live_count',
    ),
    'max_cursor_picture_estimated_bytes': _maxNumOrZero(
      cursorPaintEvents,
      'cursor_picture_estimated_bytes',
    ),
    'max_overlay_layer_count': _maxNumOrZero(
      flutterRenderEvents,
      'overlay_layer_count',
    ),
    'missed_vsync_metric_valid': missedVsyncMetricValid,
    'overlay_layer_count_metric_valid': overlayLayerCountMetricValid,
    'cursor_paint_bounds_metric_valid': cursorPaintBoundsMetricValid,
    'cursor_cell_width_metric_valid': cursorCellWidthMetricValid,
    'cursor_cell_height_metric_valid': cursorCellHeightMetricValid,
    'cursor_device_pixel_ratio_metric_valid': cursorDevicePixelRatioMetricValid,
    'cursor_picture_live_count_metric_valid': cursorPictureLiveCountMetricValid,
    'cursor_picture_estimated_bytes_metric_valid':
        cursorPictureEstimatedBytesMetricValid,
    'cursor_paint_bounds_violation_count': cursorPaintEvents
        .where(_cursorPaintBoundsExceeded)
        .length,
    'cursor_picture_estimated_bytes_violation_count': cursorPaintEvents
        .where(_cursorPictureEstimatedBytesExceeded)
        .length,
    'missed_vsync_count': flutterFrameTimingEvents
        .where((event) => event['missed_vsync'] == true)
        .length,
    'row_cache_hit_rate': cacheHits + cacheMisses == 0
        ? 'N/A'
        : cacheHits / (cacheHits + cacheMisses),
  };
}

num _maxNumOrZero(List<Map<String, Object?>> events, String key) {
  num maximum = 0;
  for (final event in events) {
    final value = event[key];
    if (value is num && value.isFinite && value > maximum) {
      maximum = value;
    }
  }
  return maximum;
}

bool _allFiniteNumbers(
  List<Map<String, Object?>> events,
  String key, {
  bool positive = false,
  bool nonNegative = false,
  bool integer = false,
}) {
  if (events.isEmpty) {
    return false;
  }
  return events.every((event) {
    final value = event[key];
    if (value is! num || !value.isFinite) {
      return false;
    }
    final number = value.toDouble();
    if (positive && number <= 0) {
      return false;
    }
    if (nonNegative && number < 0) {
      return false;
    }
    return !integer || number == number.truncateToDouble();
  });
}

double? _finiteEventNumber(Map<String, Object?> event, String key) {
  final value = event[key];
  return value is num && value.isFinite ? value.toDouble() : null;
}

bool _cursorPaintBoundsExceeded(Map<String, Object?> event) {
  final bounds = _finiteEventNumber(event, 'paint_bounds_area');
  final width = _finiteEventNumber(event, 'cell_width_px');
  final height = _finiteEventNumber(event, 'cell_height_px');
  if (bounds == null ||
      bounds < 0 ||
      width == null ||
      width <= 0 ||
      height == null ||
      height <= 0) {
    return false;
  }
  final limit = 2 * width * height;
  return !limit.isFinite || bounds > limit;
}

bool _cursorPictureEstimatedBytesExceeded(Map<String, Object?> event) {
  final bytes = _finiteEventNumber(event, 'cursor_picture_estimated_bytes');
  final width = _finiteEventNumber(event, 'cell_width_px');
  final height = _finiteEventNumber(event, 'cell_height_px');
  final dpr = _finiteEventNumber(event, 'device_pixel_ratio');
  if (bytes == null ||
      bytes < 0 ||
      width == null ||
      width <= 0 ||
      height == null ||
      height <= 0 ||
      dpr == null ||
      dpr <= 0) {
    return false;
  }
  final physicalWidth = 2 * width * dpr;
  final physicalHeight = height * dpr;
  if (!physicalWidth.isFinite || !physicalHeight.isFinite) {
    return true;
  }
  final limit = physicalWidth.ceil() * physicalHeight.ceil() * 4;
  return bytes > limit;
}

void _writeJson(File file, Map<String, Object?> value) {
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
  );
}

void _writeNdjson(File file, List<Map<String, Object?>> events) {
  final buffer = StringBuffer();
  for (final event in events) {
    buffer.writeln(jsonEncode(event));
  }
  file.writeAsStringSync(buffer.toString());
}

void _writeSummary(Directory outputDir, Map<String, Object?> summary) {
  File('${outputDir.path}/summary.csv').writeAsStringSync(
    '${_summaryCsvHeader.join(',')}\n${_summaryCsvRow(summary).join(',')}\n',
  );
  File('${outputDir.path}/summary.md').writeAsStringSync(
    '# Flutter Render Profile Summary\n\n'
    '- target_platform: `${summary['target_platform']}`\n'
    '- target_device: `${summary['target_device']}`\n'
    '- workload: `${summary['workload']}`\n'
    '- policy: `${summary['policy']}`\n'
    '- wire_format: `${summary['wire_format']}`\n'
    '- hash_match: `${summary['hash_match']}`\n'
    '- frames_presented: `${summary['frames_presented']}`\n'
    '- runtime_frame_count: `${summary['runtime_frame_count']}`\n'
    '- runtime_raw_frame_bytes_total: `${summary['runtime_raw_frame_bytes_total']}`\n'
    '- p95_frame_build_micros: `${summary['p95_frame_build_micros']}`\n'
    '- p95_apply_frame_micros: `${summary['p95_apply_frame_micros']}`\n'
    '- p95_json_decode_micros: `${summary['p95_json_decode_micros']}`\n'
    '- p95_protobuf_decode_micros: `${summary['p95_protobuf_decode_micros']}`\n'
    '- p95_native_json_encode_micros: `${summary['p95_native_json_encode_micros']}`\n'
    '- p95_native_protobuf_encode_micros: `${summary['p95_native_protobuf_encode_micros']}`\n'
    '- p95_build_duration_micros: `${summary['p95_build_duration_micros']}`\n'
    '- p95_raster_duration_micros: `${summary['p95_raster_duration_micros']}`\n'
    '- p95_total_span_micros: `${summary['p95_total_span_micros']}`\n'
    '- p95_paint_micros: `${summary['p95_paint_micros']}`\n'
    '- missed_vsync_count: `${summary['missed_vsync_count']}`\n'
    '- row_cache_hit_rate: `${_display(summary['row_cache_hit_rate'])}`\n',
  );
}

int _sumInt(List<Map<String, Object?>> events, String key) {
  var total = 0;
  for (final event in events) {
    final value = event[key];
    if (value is num) {
      total += value.toInt();
    }
  }
  return total;
}

List<int> _intValues(List<Map<String, Object?>> events, String key) {
  return events
      .map((event) => event[key])
      .whereType<num>()
      .where((value) => value.isFinite)
      .map((value) => value.toInt())
      .toList(growable: false);
}

List<int> _completeNonNegativeIntValues(
  List<Map<String, Object?>> events,
  String key,
) {
  final values = <int>[];
  for (final event in events) {
    final value = event[key];
    if (value is! num ||
        !value.isFinite ||
        value < 0 ||
        value.toDouble() != value.truncateToDouble()) {
      return const <int>[];
    }
    values.add(value.toInt());
  }
  return values;
}

Object _averageIntValues(List<Map<String, Object?>> events, String key) {
  final values = _intValues(events, key);
  if (values.isEmpty) {
    return 'N/A';
  }
  return values.reduce((a, b) => a + b) / values.length;
}

String _wireFormatFor(List<Map<String, Object?>> events) {
  final formats = events
      .map((event) => event['wire_format'])
      .whereType<String>()
      .where((value) => value.isNotEmpty && value != 'unknown')
      .toSet();
  if (formats.length == 1) {
    return formats.single;
  }
  if (formats.isEmpty) {
    return 'render_only';
  }
  return 'mixed';
}

Object _percentile(List<int> values, int percentile) {
  if (values.isEmpty) {
    return 'N/A';
  }
  final sorted = values.toList(growable: false)..sort();
  final rank = (percentile / 100) * sorted.length;
  final index = math.max(0, math.min(sorted.length - 1, rank.ceil() - 1));
  return sorted[index];
}

const _summaryCsvHeader = <String>[
  'target_platform',
  'target_device',
  'workload',
  'policy',
  'repeat',
  'wire_format',
  'hash_match',
  'semantic_generations',
  'frame_diffs_generated',
  'frames_presented',
  'coalescing_ratio',
  'snapshot_count',
  'delta_count',
  'avg_rows_emitted',
  'p95_frame_build_micros',
  'p95_apply_frame_micros',
  'runtime_frame_count',
  'runtime_raw_frame_bytes_total',
  'p95_json_decode_micros',
  'p95_protobuf_decode_micros',
  'p95_native_json_encode_micros',
  'p95_native_protobuf_encode_micros',
  'p50_build_duration_micros',
  'p95_build_duration_micros',
  'p50_raster_duration_micros',
  'p95_raster_duration_micros',
  'p50_total_span_micros',
  'p95_total_span_micros',
  'p95_paint_micros',
  'p50_surface_paint_micros',
  'p95_surface_paint_micros',
  'p50_cursor_paint_micros',
  'p95_cursor_paint_micros',
  'sampled_blink_transitions',
  'surface_non_frame_paint_count',
  'cursor_paint_count',
  'max_cursor_paint_bounds_area',
  'max_cursor_cell_width_px',
  'max_cursor_cell_height_px',
  'max_cursor_device_pixel_ratio',
  'max_cursor_picture_live_count',
  'max_cursor_picture_estimated_bytes',
  'max_overlay_layer_count',
  'missed_vsync_metric_valid',
  'overlay_layer_count_metric_valid',
  'cursor_paint_bounds_metric_valid',
  'cursor_cell_width_metric_valid',
  'cursor_cell_height_metric_valid',
  'cursor_device_pixel_ratio_metric_valid',
  'cursor_picture_live_count_metric_valid',
  'cursor_picture_estimated_bytes_metric_valid',
  'cursor_paint_bounds_violation_count',
  'cursor_picture_estimated_bytes_violation_count',
  'missed_vsync_count',
  'row_cache_hit_rate',
];

const _groupedSummaryCsvHeader = <String>[
  'target_platform',
  'target_device',
  'workload',
  'wire_format',
  'repeat_count',
  'hash_match_count',
  'frames_presented_avg',
  'p95_total_span_micros_avg',
  'p95_total_span_micros_max',
  'missed_vsync_count_total',
  'row_cache_hit_rate_avg',
];

List<String> _summaryCsvRow(Map<String, Object?> summary) {
  return <String>[
    _csv(summary['target_platform']),
    _csv(summary['target_device']),
    _csv(summary['workload']),
    _csv(summary['policy']),
    _csv(summary['repeat']),
    _csv(summary['wire_format']),
    _csv(summary['hash_match']),
    _csv(summary['semantic_generations']),
    _csv(summary['frame_diffs_generated']),
    _csv(summary['frames_presented']),
    _csv(_display(summary['coalescing_ratio'])),
    _csv(summary['snapshot_count']),
    _csv(summary['delta_count']),
    _csv(_display(summary['avg_rows_emitted'])),
    _csv(summary['p95_frame_build_micros']),
    _csv(summary['p95_apply_frame_micros']),
    _csv(summary['runtime_frame_count']),
    _csv(summary['runtime_raw_frame_bytes_total']),
    _csv(summary['p95_json_decode_micros']),
    _csv(summary['p95_protobuf_decode_micros']),
    _csv(summary['p95_native_json_encode_micros']),
    _csv(summary['p95_native_protobuf_encode_micros']),
    _csv(summary['p50_build_duration_micros']),
    _csv(summary['p95_build_duration_micros']),
    _csv(summary['p50_raster_duration_micros']),
    _csv(summary['p95_raster_duration_micros']),
    _csv(summary['p50_total_span_micros']),
    _csv(summary['p95_total_span_micros']),
    _csv(summary['p95_paint_micros']),
    _csv(summary['p50_surface_paint_micros']),
    _csv(summary['p95_surface_paint_micros']),
    _csv(summary['p50_cursor_paint_micros']),
    _csv(summary['p95_cursor_paint_micros']),
    _csv(summary['sampled_blink_transitions']),
    _csv(summary['surface_non_frame_paint_count']),
    _csv(summary['cursor_paint_count']),
    _csv(summary['max_cursor_paint_bounds_area']),
    _csv(summary['max_cursor_cell_width_px']),
    _csv(summary['max_cursor_cell_height_px']),
    _csv(summary['max_cursor_device_pixel_ratio']),
    _csv(summary['max_cursor_picture_live_count']),
    _csv(summary['max_cursor_picture_estimated_bytes']),
    _csv(summary['max_overlay_layer_count']),
    _csv(summary['missed_vsync_metric_valid']),
    _csv(summary['overlay_layer_count_metric_valid']),
    _csv(summary['cursor_paint_bounds_metric_valid']),
    _csv(summary['cursor_cell_width_metric_valid']),
    _csv(summary['cursor_cell_height_metric_valid']),
    _csv(summary['cursor_device_pixel_ratio_metric_valid']),
    _csv(summary['cursor_picture_live_count_metric_valid']),
    _csv(summary['cursor_picture_estimated_bytes_metric_valid']),
    _csv(summary['cursor_paint_bounds_violation_count']),
    _csv(summary['cursor_picture_estimated_bytes_violation_count']),
    _csv(summary['missed_vsync_count']),
    _csv(_display(summary['row_cache_hit_rate'])),
  ];
}

List<Map<String, Object?>> _groupSummariesByWorkload(
  List<Map<String, Object?>> summaries,
) {
  final grouped = <String, List<Map<String, Object?>>>{};
  for (final summary in summaries) {
    final key =
        '${summary['target_platform']}\u0000${summary['target_device']}\u0000${summary['workload']}\u0000${summary['wire_format']}';
    grouped.putIfAbsent(key, () => <Map<String, Object?>>[]).add(summary);
  }

  final results = <Map<String, Object?>>[];
  for (final entries in grouped.values) {
    final first = entries.first;
    results.add(<String, Object?>{
      'target_platform': first['target_platform'],
      'target_device': first['target_device'],
      'workload': first['workload'],
      'wire_format': first['wire_format'],
      'repeat_count': entries.length,
      'hash_match_count': entries
          .where((entry) => entry['hash_match'] == true)
          .length,
      'frames_presented_avg': _averageSummaryValue(entries, 'frames_presented'),
      'p95_total_span_micros_avg': _averageSummaryValue(
        entries,
        'p95_total_span_micros',
      ),
      'p95_total_span_micros_max': _maxSummaryValue(
        entries,
        'p95_total_span_micros',
      ),
      'missed_vsync_count_total': _sumSummaryValue(
        entries,
        'missed_vsync_count',
      ),
      'row_cache_hit_rate_avg': _averageSummaryValue(
        entries,
        'row_cache_hit_rate',
      ),
    });
  }
  results.sort((a, b) {
    final targetCompare = '${a['target_device']}'.compareTo(
      '${b['target_device']}',
    );
    if (targetCompare != 0) {
      return targetCompare;
    }
    return '${a['workload']}'.compareTo('${b['workload']}');
  });
  return results;
}

List<String> _groupedSummaryCsvRow(Map<String, Object?> summary) {
  return <String>[
    _csv(summary['target_platform']),
    _csv(summary['target_device']),
    _csv(summary['workload']),
    _csv(summary['wire_format']),
    _csv(summary['repeat_count']),
    _csv(summary['hash_match_count']),
    _csv(_display(summary['frames_presented_avg'])),
    _csv(_display(summary['p95_total_span_micros_avg'])),
    _csv(_display(summary['p95_total_span_micros_max'])),
    _csv(summary['missed_vsync_count_total']),
    _csv(_display(summary['row_cache_hit_rate_avg'])),
  ];
}

Object _averageSummaryValue(List<Map<String, Object?>> entries, String key) {
  final values = _summaryNumbers(entries, key);
  if (values.isEmpty) {
    return 'N/A';
  }
  return values.reduce((a, b) => a + b) / values.length;
}

Object _maxSummaryValue(List<Map<String, Object?>> entries, String key) {
  final values = _summaryNumbers(entries, key);
  if (values.isEmpty) {
    return 'N/A';
  }
  return values.reduce(math.max);
}

int _sumSummaryValue(List<Map<String, Object?>> entries, String key) {
  return _summaryNumbers(
    entries,
    key,
  ).fold<int>(0, (total, value) => total + value.toInt());
}

List<double> _summaryNumbers(List<Map<String, Object?>> entries, String key) {
  return entries
      .map((entry) => entry[key])
      .whereType<num>()
      .map((value) => value.toDouble())
      .toList(growable: false);
}

String _csv(Object? value) {
  final text = value?.toString() ?? 'N/A';
  if (!text.contains(',') && !text.contains('"') && !text.contains('\n')) {
    return text;
  }
  return '"${text.replaceAll('"', '""')}"';
}

String _display(Object? value) {
  if (value is double) {
    return value.toStringAsFixed(4);
  }
  return value?.toString() ?? 'N/A';
}
