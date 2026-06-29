import 'dart:convert';
import 'dart:io';

import 'bench_config.dart';
import 'bench_policy.dart';
import 'correctness_oracle.dart';
import 'replay_terminal.dart';
import 'summary_analyzer.dart';
import 'workloads.dart';

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
  }) : _clock = clock ?? DateTime.now,
       _workloadCatalog = workloadCatalog ?? BenchWorkloadCatalog(),
       _replayEngine = replayEngine ?? const ReplayTerminalEngine();

  final DateTime Function() _clock;
  final BenchWorkloadCatalog _workloadCatalog;
  final ReplayTerminalEngine _replayEngine;

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
          );
          summaries.add(
            const SummaryAnalyzer().summarizeRunDirectory(runDirectory),
          );
          if (config.gates.requireHashMatch &&
              correctness['hash_match'] != true) {
            failures.add(
              '${workload.name}/${framePolicy.wireName}: hash mismatch',
            );
          }
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

void _writeRunDirectory({
  required Directory runDirectory,
  required String configYaml,
  required BenchRunData data,
  required Map<String, Object?> correctness,
  required BenchCollectors collectors,
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
  File(
    '${runDirectory.path}/correctness.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(correctness));
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
