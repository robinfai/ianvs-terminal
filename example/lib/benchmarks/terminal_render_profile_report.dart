import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
  required String expectedViewportHash,
  required String actualViewportHash,
  DateTime? startedAt,
  DateTime? completedAt,
}) {
  outputDir.createSync(recursive: true);
  final started = startedAt ?? DateTime.now().toUtc();
  final completed = completedAt ?? DateTime.now().toUtc();
  final hashMatch = expectedViewportHash == actualViewportHash;

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
      '| ${summary['target_device']} | ${summary['workload']} | '
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
      '| ${summary['target_device']} | ${summary['workload']} | '
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
}) {
  final frameCount = flutterRenderEvents.length;
  final cacheHits = _sumInt(flutterRenderEvents, 'row_cache_hits');
  final cacheMisses = _sumInt(flutterRenderEvents, 'row_cache_misses');
  return <String, Object?>{
    'workload': workload,
    'policy': policy,
    'repeat': repeatIndex,
    'target_platform': targetPlatform,
    'target_device': targetDevice,
    'hash_match': hashMatch,
    'semantic_generations': semanticGenerations,
    'frame_diffs_generated': frameCount,
    'frames_presented': frameCount,
    'coalescing_ratio': frameCount == 0
        ? 'N/A'
        : semanticGenerations / frameCount,
    'snapshot_count': flutterRenderEvents
        .where((event) => event['frame_kind'] == 'snapshot')
        .length,
    'delta_count': flutterRenderEvents
        .where((event) => event['frame_kind'] == 'delta')
        .length,
    'avg_rows_emitted': 'N/A',
    'p95_frame_build_micros': 'N/A',
    'p95_apply_frame_micros': 'N/A',
    'p95_build_duration_micros': _percentile(
      _intValues(flutterFrameTimingEvents, 'build_duration_micros'),
      95,
    ),
    'p50_raster_duration_micros': _percentile(
      _intValues(flutterFrameTimingEvents, 'raster_duration_micros'),
      50,
    ),
    'p95_raster_duration_micros': _percentile(
      _intValues(flutterFrameTimingEvents, 'raster_duration_micros'),
      95,
    ),
    'p99_raster_duration_micros': _percentile(
      _intValues(flutterFrameTimingEvents, 'raster_duration_micros'),
      99,
    ),
    'p95_total_span_micros': _percentile(
      _intValues(flutterFrameTimingEvents, 'total_span_micros'),
      95,
    ),
    'p95_paint_micros': _percentile(
      _intValues(flutterRenderEvents, 'paint_micros'),
      95,
    ),
    'missed_vsync_count': flutterFrameTimingEvents
        .where((event) => event['missed_vsync'] == true)
        .length,
    'row_cache_hit_rate': cacheHits + cacheMisses == 0
        ? 'N/A'
        : cacheHits / (cacheHits + cacheMisses),
  };
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
    '- hash_match: `${summary['hash_match']}`\n'
    '- frames_presented: `${summary['frames_presented']}`\n'
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
      .map((value) => value.toInt())
      .toList(growable: false);
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
  'p95_build_duration_micros',
  'p95_raster_duration_micros',
  'p95_total_span_micros',
  'p95_paint_micros',
  'missed_vsync_count',
  'row_cache_hit_rate',
];

const _groupedSummaryCsvHeader = <String>[
  'target_platform',
  'target_device',
  'workload',
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
    _csv(summary['p95_build_duration_micros']),
    _csv(summary['p95_raster_duration_micros']),
    _csv(summary['p95_total_span_micros']),
    _csv(summary['p95_paint_micros']),
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
        '${summary['target_platform']}\u0000${summary['target_device']}\u0000${summary['workload']}';
    grouped.putIfAbsent(key, () => <Map<String, Object?>>[]).add(summary);
  }

  final results = <Map<String, Object?>>[];
  for (final entries in grouped.values) {
    final first = entries.first;
    results.add(<String, Object?>{
      'target_platform': first['target_platform'],
      'target_device': first['target_device'],
      'workload': first['workload'],
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
