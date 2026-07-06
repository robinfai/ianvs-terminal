import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

final class SummaryAnalyzer {
  const SummaryAnalyzer();

  Map<String, Object?> summarizeRunDirectory(Directory directory) {
    final metadata = _readJsonObject(File('${directory.path}/metadata.json'));
    final correctness = _readJsonObject(
      File('${directory.path}/correctness.json'),
    );
    final rustFrames = _readNdjson(File('${directory.path}/rust_frame.ndjson'));
    final dartEvents = _readNdjson(
      File('${directory.path}/dart_runtime.ndjson'),
    );
    final flutterEvents = _readNdjson(
      File('${directory.path}/flutter_render.ndjson'),
    );
    final timingEvents = _readNdjson(
      File('${directory.path}/flutter_frame_timing.ndjson'),
    );
    final resourceEvents = _readNdjson(
      File('${directory.path}/os_resource.ndjson'),
    );

    final workload =
        _stringValue(metadata['workload']) ??
        _stringValue(correctness['workload']) ??
        directory.uri.pathSegments.where((segment) => segment.isNotEmpty).last;
    final mode = _mapValue(metadata['mode']);
    final policy =
        _stringValue(mode['frame_policy']) ??
        _stringValue(correctness['tested_policy']) ??
        'unknown';
    final repeat = _intValue(metadata['repeat_index']) ?? 1;
    final semanticGenerations = _maxInt(rustFrames, 'semantic_generation');
    final frameCount = rustFrames.length;
    final snapshotCount = rustFrames
        .where((event) => event['frame_kind'] == 'snapshot')
        .length;
    final deltaCount = rustFrames
        .where((event) => event['frame_kind'] == 'delta')
        .length;
    final rowsEmitted = _intValues(rustFrames, 'rows_emitted');
    final viewportRows = _intValues(rustFrames, 'viewport_rows');
    final cacheHits = _sumInt(flutterEvents, 'row_cache_hits');
    final cacheMisses = _sumInt(flutterEvents, 'row_cache_misses');
    final summary = <String, Object?>{
      'workload': workload,
      'policy': policy,
      'repeat': repeat,
      'hash_match': correctness['hash_match'],
      'semantic_generations': semanticGenerations,
      'frame_diffs_generated': frameCount,
      'frames_presented': frameCount,
      'coalescing_ratio': frameCount == 0
          ? 'N/A'
          : semanticGenerations / frameCount,
      'snapshot_count': snapshotCount,
      'delta_count': deltaCount,
      'snapshot_fallback_distribution': _fallbackDistribution(rustFrames),
      'avg_rows_emitted': rowsEmitted.isEmpty ? 'N/A' : _average(rowsEmitted),
      'rows_emitted_per_viewport_row':
          rowsEmitted.isEmpty || viewportRows.isEmpty
          ? 'N/A'
          : _average(rowsEmitted) / math.max(1, _average(viewportRows)),
      'p50_frame_build_micros': _percentile(
        _intValues(rustFrames, 'frame_build_micros'),
        50,
      ),
      'p95_frame_build_micros': _percentile(
        _intValues(rustFrames, 'frame_build_micros'),
        95,
      ),
      'p99_frame_build_micros': _percentile(
        _intValues(rustFrames, 'frame_build_micros'),
        99,
      ),
      'p50_json_decode_micros': _percentile(
        _intValues(dartEvents, 'json_decode_micros'),
        50,
      ),
      'p95_json_decode_micros': _percentile(
        _intValues(dartEvents, 'json_decode_micros'),
        95,
      ),
      'p99_json_decode_micros': _percentile(
        _intValues(dartEvents, 'json_decode_micros'),
        99,
      ),
      'p50_apply_frame_micros': _percentile(
        _intValues(dartEvents, 'apply_frame_micros'),
        50,
      ),
      'p95_apply_frame_micros': _percentile(
        _intValues(dartEvents, 'apply_frame_micros'),
        95,
      ),
      'p99_apply_frame_micros': _percentile(
        _intValues(dartEvents, 'apply_frame_micros'),
        99,
      ),
      'p50_raster_duration_micros': _percentile(
        _intValues(timingEvents, 'raster_duration_micros'),
        50,
      ),
      'p95_raster_duration_micros': _percentile(
        _intValues(timingEvents, 'raster_duration_micros'),
        95,
      ),
      'p99_raster_duration_micros': _percentile(
        _intValues(timingEvents, 'raster_duration_micros'),
        99,
      ),
      'os_resource_sample_count': resourceEvents.length,
      'p95_process_cpu_percent': _percentileNum(
        _numValues(resourceEvents, 'process_cpu_percent'),
        95,
      ),
      'peak_process_rss_bytes': _maxNullableInt(
        resourceEvents,
        'process_rss_bytes',
      ),
      'row_cache_hit_rate': cacheHits + cacheMisses == 0
          ? 'N/A'
          : cacheHits / (cacheHits + cacheMisses),
    };

    _writeRunSummary(directory, summary);
    return summary;
  }

  void writeAggregateSummary(
    Directory directory,
    List<Map<String, Object?>> summaries,
  ) {
    directory.createSync(recursive: true);
    final csv = StringBuffer()..writeln(_summaryCsvHeader.join(','));
    for (final summary in summaries) {
      csv.writeln(_summaryCsvRow(summary).join(','));
    }
    File('${directory.path}/summary.csv').writeAsStringSync(csv.toString());

    final md = StringBuffer()
      ..writeln('# Ianvs Benchmark Summary')
      ..writeln()
      ..writeln(
        '| workload | policy | repeat | hash match | coalescing ratio |',
      )
      ..writeln('|---|---|---:|---:|---:|');
    for (final summary in summaries) {
      md.writeln(
        '| ${summary['workload']} | ${summary['policy']} | '
        '${summary['repeat']} | ${summary['hash_match']} | '
        '${_display(summary['coalescing_ratio'])} |',
      );
    }
    File('${directory.path}/summary.md').writeAsStringSync(md.toString());
  }
}

void _writeRunSummary(Directory directory, Map<String, Object?> summary) {
  final csv = StringBuffer()
    ..writeln(_summaryCsvHeader.join(','))
    ..writeln(_summaryCsvRow(summary).join(','));
  File('${directory.path}/summary.csv').writeAsStringSync(csv.toString());
  final md = StringBuffer()
    ..writeln('# Benchmark Run Summary')
    ..writeln()
    ..writeln('- workload: `${summary['workload']}`')
    ..writeln('- policy: `${summary['policy']}`')
    ..writeln('- hash_match: `${summary['hash_match']}`')
    ..writeln('- semantic_generations: `${summary['semantic_generations']}`')
    ..writeln('- frames_presented: `${summary['frames_presented']}`')
    ..writeln('- coalescing_ratio: `${_display(summary['coalescing_ratio'])}`');
  File('${directory.path}/summary.md').writeAsStringSync(md.toString());
}

const _summaryCsvHeader = <String>[
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
  'p95_json_decode_micros',
  'p95_apply_frame_micros',
  'p95_raster_duration_micros',
  'os_resource_sample_count',
  'p95_process_cpu_percent',
  'peak_process_rss_bytes',
  'row_cache_hit_rate',
];

List<String> _summaryCsvRow(Map<String, Object?> summary) {
  return <String>[
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
    _csv(summary['p95_json_decode_micros']),
    _csv(summary['p95_apply_frame_micros']),
    _csv(summary['p95_raster_duration_micros']),
    _csv(summary['os_resource_sample_count']),
    _csv(summary['p95_process_cpu_percent']),
    _csv(summary['peak_process_rss_bytes']),
    _csv(_display(summary['row_cache_hit_rate'])),
  ];
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

Map<String, Object?> _readJsonObject(File file) {
  if (!file.existsSync()) {
    return const <String, Object?>{};
  }
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is Map) {
    return decoded.cast<String, Object?>();
  }
  return const <String, Object?>{};
}

List<Map<String, Object?>> _readNdjson(File file) {
  if (!file.existsSync()) {
    return const <Map<String, Object?>>[];
  }
  final events = <Map<String, Object?>>[];
  for (final line in file.readAsLinesSync()) {
    if (line.trim().isEmpty) {
      continue;
    }
    final decoded = jsonDecode(line);
    if (decoded is Map) {
      events.add(decoded.cast<String, Object?>());
    }
  }
  return events;
}

Map<String, Object?> _mapValue(Object? value) {
  if (value is Map) {
    return value.cast<String, Object?>();
  }
  return const <String, Object?>{};
}

String? _stringValue(Object? value) => value is String ? value : null;

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}

int _maxInt(List<Map<String, Object?>> events, String key) {
  var max = 0;
  for (final event in events) {
    max = math.max(max, _intValue(event[key]) ?? 0);
  }
  return max;
}

Object _maxNullableInt(List<Map<String, Object?>> events, String key) {
  final values = _intValues(events, key);
  if (values.isEmpty) {
    return 'N/A';
  }
  return values.reduce(math.max);
}

int _sumInt(List<Map<String, Object?>> events, String key) {
  var sum = 0;
  for (final event in events) {
    sum += _intValue(event[key]) ?? 0;
  }
  return sum;
}

List<int> _intValues(List<Map<String, Object?>> events, String key) {
  return events
      .map((event) => _intValue(event[key]))
      .whereType<int>()
      .toList(growable: false);
}

List<num> _numValues(List<Map<String, Object?>> events, String key) {
  return events
      .map((event) => event[key])
      .whereType<num>()
      .where((value) => value.isFinite)
      .toList(growable: false);
}

double _average(List<int> values) {
  if (values.isEmpty) {
    return 0;
  }
  return values.fold<int>(0, (sum, value) => sum + value) / values.length;
}

Object _percentile(List<int> values, int percentile) {
  if (values.isEmpty) {
    return 'N/A';
  }
  final sorted = values.toList()..sort();
  final rank = ((percentile / 100) * sorted.length).ceil() - 1;
  return sorted[rank.clamp(0, sorted.length - 1)];
}

Object _percentileNum(List<num> values, int percentile) {
  if (values.isEmpty) {
    return 'N/A';
  }
  final sorted = values.toList()..sort();
  final rank = ((percentile / 100) * sorted.length).ceil() - 1;
  return sorted[rank.clamp(0, sorted.length - 1)];
}

Map<String, int> _fallbackDistribution(List<Map<String, Object?>> events) {
  final distribution = <String, int>{};
  for (final event in events) {
    final reason = event['snapshot_fallback_reason'];
    if (reason is String && reason.isNotEmpty) {
      distribution[reason] = (distribution[reason] ?? 0) + 1;
    }
  }
  return distribution;
}
