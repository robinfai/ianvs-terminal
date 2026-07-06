import 'dart:convert';
import 'dart:io';

import 'bench_config.dart';
import 'bench_policy.dart';
import 'correctness_oracle.dart';
import 'replay_terminal.dart';
import 'summary_analyzer.dart';
import 'workloads.dart';

typedef BenchOsResourceSampler =
    List<Map<String, Object?>> Function({required BenchRunData data});

final class BenchRunnerResult {
  const BenchRunnerResult({
    required this.exitCode,
    required this.outputDirectory,
    this.failures = const <String>[],
  });

  final int exitCode;
  final Directory outputDirectory;
  final List<String> failures;
}

final class BenchRunnerCore {
  BenchRunnerCore({
    DateTime Function()? clock,
    BenchWorkloadCatalog? workloadCatalog,
    ReplayTerminalEngine? replayEngine,
    BenchOsResourceSampler? osResourceSampler,
  }) : _clock = clock ?? DateTime.now,
       _workloadCatalog = workloadCatalog ?? BenchWorkloadCatalog(),
       _replayEngine = replayEngine ?? const ReplayTerminalEngine(),
       _osResourceSampler = osResourceSampler ?? _defaultOsResourceSampler;

  final DateTime Function() _clock;
  final BenchWorkloadCatalog _workloadCatalog;
  final ReplayTerminalEngine _replayEngine;
  final BenchOsResourceSampler _osResourceSampler;

  Future<BenchRunnerResult> runConfig(BenchConfig config) async {
    final suiteDirectory = Directory(
      '${config.outputDir}/${_timestampForPath(_clock())}',
    )..createSync(recursive: true);
    File(
      '${suiteDirectory.path}/config.yaml',
    ).writeAsStringSync(config.toYaml());
    final summaries = <Map<String, Object?>>[];
    final failures = <String>[];

    for (final workloadName in config.workloads) {
      final workload = _workloadCatalog.resolve(workloadName);
      for (var repeat = 1; repeat <= config.repeat; repeat += 1) {
        final renderPolicy = config.renderPolicies.first;
        final reference = _replayEngine.run(
          workload: workload,
          framePolicy: BenchFramePolicy.snapshotOnly,
          renderPolicy: renderPolicy,
          cols: config.viewportCols,
          rows: config.viewportRows,
          repeatIndex: repeat,
        );

        for (final framePolicy in config.framePolicies) {
          final data = framePolicy == BenchFramePolicy.snapshotOnly
              ? reference
              : _replayEngine.run(
                  workload: workload,
                  framePolicy: framePolicy,
                  renderPolicy: renderPolicy,
                  cols: config.viewportCols,
                  rows: config.viewportRows,
                  repeatIndex: repeat,
                );
          final correctness = CorrectnessOracle.compare(
            reference: reference,
            tested: data,
          );
          final runDirectory = Directory(
            '${suiteDirectory.path}/${workload.name}/${framePolicy.wireName}/repeat_$repeat',
          );
          _writeRunDirectory(
            runDirectory: runDirectory,
            configYaml: config.toYaml(),
            data: data,
            correctness: correctness,
            collectors: config.collectors,
            resourceSamples: config.collectors.osResource
                ? _osResourceSampler(data: data)
                : const <Map<String, Object?>>[],
          );
          final summary = const SummaryAnalyzer().summarizeRunDirectory(
            runDirectory,
          );
          summaries.add(summary);
          if (config.gates.requireHashMatch &&
              correctness['hash_match'] != true) {
            failures.add(
              '${workload.name}/${framePolicy.wireName}: hash mismatch',
            );
          }
          if (config.gates.requireSchemaValid) {
            failures.addAll(
              _schemaGateFailures(
                workloadName: workload.name,
                framePolicy: framePolicy,
                runDirectory: runDirectory,
                collectors: config.collectors,
              ),
            );
          }
          failures.addAll(
            _performanceGateFailures(
              workloadName: workload.name,
              framePolicy: framePolicy,
              gates: config.gates,
              summary: summary,
            ),
          );
        }
      }
    }

    const SummaryAnalyzer().writeAggregateSummary(suiteDirectory, summaries);
    return BenchRunnerResult(
      exitCode: failures.isEmpty ? 0 : 1,
      outputDirectory: suiteDirectory,
      failures: List<String>.unmodifiable(failures),
    );
  }

  Future<BenchRunnerResult> runSingle({
    required String workloadName,
    required BenchFramePolicy framePolicy,
    required BenchRenderPolicy renderPolicy,
    required int cols,
    required int rows,
    required String outputDir,
  }) async {
    final workload = _workloadCatalog.resolve(workloadName);
    final directory = Directory('$outputDir/${_timestampForPath(_clock())}')
      ..createSync(recursive: true);
    final reference = _replayEngine.run(
      workload: workload,
      framePolicy: BenchFramePolicy.snapshotOnly,
      renderPolicy: renderPolicy,
      cols: cols,
      rows: rows,
      repeatIndex: 1,
    );
    final tested = framePolicy == BenchFramePolicy.snapshotOnly
        ? reference
        : _replayEngine.run(
            workload: workload,
            framePolicy: framePolicy,
            renderPolicy: renderPolicy,
            cols: cols,
            rows: rows,
            repeatIndex: 1,
          );
    final correctness = CorrectnessOracle.compare(
      reference: reference,
      tested: tested,
    );
    _writeRunDirectory(
      runDirectory: directory,
      configYaml: '',
      data: tested,
      correctness: correctness,
      collectors: const BenchCollectors(),
      resourceSamples: const <Map<String, Object?>>[],
    );
    const SummaryAnalyzer().summarizeRunDirectory(directory);
    return BenchRunnerResult(
      exitCode: correctness['hash_match'] == false ? 1 : 0,
      outputDirectory: directory,
      failures: correctness['hash_match'] == false
          ? <String>['$workloadName/${framePolicy.wireName}: hash mismatch']
          : const <String>[],
    );
  }
}

List<String> _schemaGateFailures({
  required String workloadName,
  required BenchFramePolicy framePolicy,
  required Directory runDirectory,
  required BenchCollectors collectors,
}) {
  final failures = <String>[
    ..._validateJsonArtifact(
      file: File('${runDirectory.path}/correctness.json'),
      schema: _loadSchema('correctness.schema.json'),
    ),
  ];
  if (collectors.rustFrame) {
    failures.addAll(
      _validateNdjsonArtifact(
        file: File('${runDirectory.path}/rust_frame.ndjson'),
        schema: _loadSchema('rust_frame.schema.json'),
      ),
    );
  }
  if (collectors.osResource) {
    failures.addAll(
      _validateNdjsonArtifact(
        file: File('${runDirectory.path}/os_resource.ndjson'),
        schema: _loadSchema('os_resource.schema.json'),
      ),
    );
  }
  return failures
      .map((failure) => '$workloadName/${framePolicy.wireName}: $failure')
      .toList(growable: false);
}

Map<String, Object?> _loadSchema(String name) {
  return _jsonObject(File('tools/bench/schemas/$name'));
}

List<String> _validateJsonArtifact({
  required File file,
  required Map<String, Object?> schema,
}) {
  if (!file.existsSync()) {
    return <String>['${_artifactName(file)} missing'];
  }
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) {
      return <String>['${_artifactName(file)} is not a JSON object'];
    }
    return _validateSchemaObject(
      artifact: _artifactName(file),
      object: decoded.cast<String, Object?>(),
      schema: schema,
    );
  } on FormatException catch (error) {
    return <String>['${_artifactName(file)} invalid JSON: ${error.message}'];
  }
}

List<String> _validateNdjsonArtifact({
  required File file,
  required Map<String, Object?> schema,
}) {
  if (!file.existsSync()) {
    return <String>['${_artifactName(file)} missing'];
  }
  final failures = <String>[];
  final lines = file.readAsLinesSync();
  for (var index = 0; index < lines.length; index += 1) {
    final line = lines[index].trim();
    if (line.isEmpty) {
      continue;
    }
    final artifact = '${_artifactName(file)} line ${index + 1}';
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        failures.add('$artifact is not a JSON object');
        continue;
      }
      failures.addAll(
        _validateSchemaObject(
          artifact: artifact,
          object: decoded.cast<String, Object?>(),
          schema: schema,
        ),
      );
    } on FormatException catch (error) {
      failures.add('$artifact invalid JSON: ${error.message}');
    }
  }
  return failures;
}

List<String> _validateSchemaObject({
  required String artifact,
  required Map<String, Object?> object,
  required Map<String, Object?> schema,
}) {
  final failures = <String>[];
  for (final key in _stringList(schema['required'])) {
    if (!object.containsKey(key)) {
      failures.add('$artifact missing required field $key');
    }
  }
  final properties = _mapValue(schema['properties']);
  for (final entry in properties.entries) {
    if (!object.containsKey(entry.key)) {
      continue;
    }
    final property = _mapValue(entry.value);
    final value = object[entry.key];
    if (property.containsKey('const') && value != property['const']) {
      failures.add(
        '$artifact field ${entry.key} expected ${property['const']} but got $value',
      );
    }
    final enumValues = _listValue(property['enum']);
    if (enumValues.isNotEmpty && !enumValues.contains(value)) {
      failures.add(
        '$artifact field ${entry.key} expected one of ${enumValues.join(', ')} but got $value',
      );
    }
    final types = _schemaTypes(property['type']);
    if (types.isNotEmpty &&
        !types.any((type) => _matchesJsonType(value, type))) {
      failures.add(
        '$artifact field ${entry.key} expected type ${types.join('|')} but got ${_jsonTypeName(value)}',
      );
    }
  }
  return failures;
}

String _artifactName(File file) {
  return file.uri.pathSegments.where((segment) => segment.isNotEmpty).last;
}

Map<String, Object?> _jsonObject(File file) {
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is Map) {
    return decoded.cast<String, Object?>();
  }
  return const <String, Object?>{};
}

Map<String, Object?> _mapValue(Object? value) {
  if (value is Map) {
    return value.cast<String, Object?>();
  }
  return const <String, Object?>{};
}

List<Object?> _listValue(Object? value) {
  return value is List ? value : const <Object?>[];
}

List<String> _stringList(Object? value) {
  return value is List
      ? value.whereType<String>().toList(growable: false)
      : const <String>[];
}

List<String> _schemaTypes(Object? value) {
  if (value is String) {
    return <String>[value];
  }
  return _stringList(value);
}

bool _matchesJsonType(Object? value, String type) {
  return switch (type) {
    'integer' => value is int,
    'number' => value is num,
    'string' => value is String,
    'boolean' => value is bool,
    'object' => value is Map,
    'array' => value is List,
    'null' => value == null,
    _ => true,
  };
}

String _jsonTypeName(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is bool) {
    return 'boolean';
  }
  if (value is int) {
    return 'integer';
  }
  if (value is num) {
    return 'number';
  }
  if (value is String) {
    return 'string';
  }
  if (value is List) {
    return 'array';
  }
  if (value is Map) {
    return 'object';
  }
  return value.runtimeType.toString();
}

List<String> _performanceGateFailures({
  required String workloadName,
  required BenchFramePolicy framePolicy,
  required BenchGates gates,
  required Map<String, Object?> summary,
}) {
  return <String>[
    ..._maxMicrosGateFailure(
      workloadName: workloadName,
      framePolicy: framePolicy,
      metricName: 'p95_frame_build_micros',
      gateName: 'max_p95_frame_build_micros',
      maxValue: gates.maxP95FrameBuildMicros,
      summary: summary,
    ),
    ..._maxMicrosGateFailure(
      workloadName: workloadName,
      framePolicy: framePolicy,
      metricName: 'p95_json_decode_micros',
      gateName: 'max_p95_json_decode_micros',
      maxValue: gates.maxP95JsonDecodeMicros,
      summary: summary,
    ),
    ..._maxMicrosGateFailure(
      workloadName: workloadName,
      framePolicy: framePolicy,
      metricName: 'p95_apply_frame_micros',
      gateName: 'max_p95_apply_frame_micros',
      maxValue: gates.maxP95ApplyFrameMicros,
      summary: summary,
    ),
    ..._maxMetricGateFailure(
      workloadName: workloadName,
      framePolicy: framePolicy,
      metricName: 'p95_process_cpu_percent',
      gateName: 'max_p95_process_cpu_percent',
      maxValue: gates.maxP95ProcessCpuPercent,
      summary: summary,
    ),
    ..._maxMetricGateFailure(
      workloadName: workloadName,
      framePolicy: framePolicy,
      metricName: 'peak_process_rss_bytes',
      gateName: 'max_peak_process_rss_bytes',
      maxValue: gates.maxPeakProcessRssBytes,
      summary: summary,
    ),
  ];
}

List<String> _maxMicrosGateFailure({
  required String workloadName,
  required BenchFramePolicy framePolicy,
  required String metricName,
  required String gateName,
  required int? maxValue,
  required Map<String, Object?> summary,
}) {
  return _maxMetricGateFailure(
    workloadName: workloadName,
    framePolicy: framePolicy,
    metricName: metricName,
    gateName: gateName,
    maxValue: maxValue,
    summary: summary,
  );
}

List<String> _maxMetricGateFailure({
  required String workloadName,
  required BenchFramePolicy framePolicy,
  required String metricName,
  required String gateName,
  required num? maxValue,
  required Map<String, Object?> summary,
}) {
  if (maxValue == null) {
    return const <String>[];
  }
  final value = _numValue(summary[metricName]);
  if (value == null) {
    return <String>[
      '$workloadName/${framePolicy.wireName}: $metricName missing for $gateName',
    ];
  }
  if (value <= maxValue) {
    return const <String>[];
  }
  return <String>[
    '$workloadName/${framePolicy.wireName}: $metricName exceeds $gateName ($value > $maxValue)',
  ];
}

num? _numValue(Object? value) {
  if (value is num && value.isFinite) {
    return value;
  }
  return null;
}

void _writeRunDirectory({
  required Directory runDirectory,
  required String configYaml,
  required BenchRunData data,
  required Map<String, Object?> correctness,
  required BenchCollectors collectors,
  required List<Map<String, Object?>> resourceSamples,
}) {
  runDirectory.createSync(recursive: true);
  File('${runDirectory.path}/metadata.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'schema_version': 'ianvs-bench-metadata-v1',
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'git_sha': _gitSha(),
      'mode': <String, Object?>{
        'frame_policy': data.framePolicy.wireName,
        'render_policy': data.renderPolicy.wireName,
      },
      'workload': data.workload,
      'viewport': <String, Object?>{
        'cols': data.viewportCols,
        'rows': data.viewportRows,
        'device_pixel_ratio': 1.0,
      },
      'repeat_index': data.repeatIndex,
      'trace_bytes_total': data.traceBytes.length,
      'trace_bytes_processed': data.traceBytes.length,
      'semantic_generations': data.semanticGenerations,
      'final_viewport_hash': data.finalViewportHash,
      'final_scrollback_hash': data.finalScrollbackHash,
    }),
  );
  if (configYaml.isNotEmpty) {
    File('${runDirectory.path}/config.yaml').writeAsStringSync(configYaml);
  }
  File(
    '${runDirectory.path}/trace.stdout.bin',
  ).writeAsBytesSync(data.traceBytes);
  if (collectors.rustFrame) {
    _writeNdjson(
      File('${runDirectory.path}/rust_frame.ndjson'),
      data.rustFrameEvents,
    );
  }
  if (collectors.dartRuntime) {
    _writeNdjson(
      File('${runDirectory.path}/dart_runtime.ndjson'),
      data.dartRuntimeEvents,
    );
  }
  if (collectors.flutterRender && data.flutterRenderEvents.isNotEmpty) {
    _writeNdjson(
      File('${runDirectory.path}/flutter_render.ndjson'),
      data.flutterRenderEvents,
    );
  }
  if (collectors.flutterFrameTiming &&
      data.flutterFrameTimingEvents.isNotEmpty) {
    _writeNdjson(
      File('${runDirectory.path}/flutter_frame_timing.ndjson'),
      data.flutterFrameTimingEvents,
    );
  }
  if (collectors.osResource) {
    _writeNdjson(
      File('${runDirectory.path}/os_resource.ndjson'),
      resourceSamples,
    );
  }
  File(
    '${runDirectory.path}/correctness.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(correctness));
}

List<Map<String, Object?>> _defaultOsResourceSampler({
  required BenchRunData data,
}) {
  return <Map<String, Object?>>[
    <String, Object?>{
      'schema_version': 'ianvs-bench-os-resource-v1',
      'timestamp_micros': DateTime.now().toUtc().microsecondsSinceEpoch,
      'session_id':
          '${data.workload}#${data.framePolicy.wireName}#${data.repeatIndex}',
      'sample_id': 1,
      'source': 'dart_process',
      'process_id': pid,
      'process_cpu_percent': _currentProcessCpuPercent(),
      'process_rss_bytes': ProcessInfo.currentRss,
    },
  ];
}

double? _currentProcessCpuPercent() {
  if (!Platform.isMacOS && !Platform.isLinux) {
    return null;
  }
  try {
    final result = Process.runSync('ps', <String>['-o', '%cpu=', '-p', '$pid']);
    if (result.exitCode != 0) {
      return null;
    }
    final fields = result.stdout.toString().trim().split(RegExp(r'\s+'));
    if (fields.isEmpty || fields.first.isEmpty) {
      return null;
    }
    return double.tryParse(fields.first);
  } on Object {
    return null;
  }
}

void _writeNdjson(File file, List<Map<String, Object?>> events) {
  file.writeAsStringSync(events.map(jsonEncode).join('\n'));
  if (events.isNotEmpty) {
    file.writeAsStringSync('\n', mode: FileMode.append);
  }
}

String _timestampForPath(DateTime value) {
  final utc = value.toUtc();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${utc.year}${two(utc.month)}${two(utc.day)}T'
      '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
}

String _gitSha() {
  try {
    final result = Process.runSync('git', ['rev-parse', '--short', 'HEAD']);
    if (result.exitCode == 0) {
      return result.stdout.toString().trim();
    }
  } on Object {
    return 'unknown';
  }
  return 'unknown';
}
