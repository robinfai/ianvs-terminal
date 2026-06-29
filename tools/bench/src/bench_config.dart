import 'dart:io';

import 'bench_policy.dart';
import 'simple_yaml.dart';

final class BenchCollectors {
  const BenchCollectors({
    this.rustFrame = true,
    this.dartRuntime = true,
    this.flutterRender = true,
    this.flutterFrameTiming = true,
    this.osResource = false,
  });

  final bool rustFrame;
  final bool dartRuntime;
  final bool flutterRender;
  final bool flutterFrameTiming;
  final bool osResource;

  Map<String, Object?> toYamlMap() {
    return <String, Object?>{
      'rust_frame': rustFrame,
      'dart_runtime': dartRuntime,
      'flutter_render': flutterRender,
      'flutter_frame_timing': flutterFrameTiming,
      'os_resource': osResource,
    };
  }
}

final class BenchGates {
  const BenchGates({
    this.requireHashMatch = false,
    this.requireSchemaValid = false,
  });

  final bool requireHashMatch;
  final bool requireSchemaValid;
}

final class BenchConfig {
  const BenchConfig({
    required this.suite,
    required this.version,
    required this.framePolicies,
    required this.renderPolicies,
    required this.workloads,
    required this.viewportCols,
    required this.viewportRows,
    required this.repeat,
    required this.warmupRuns,
    required this.outputDir,
    required this.collectors,
    required this.gates,
  });

  factory BenchConfig.fromFile(File file) {
    return BenchConfig.fromYaml(file.readAsStringSync());
  }

  factory BenchConfig.fromYaml(String source) {
    final yaml = SimpleYaml.parseMap(source);
    final policies = _stringKeyedMap(yaml['policies']);
    final viewport = _stringKeyedMap(yaml['viewport']);
    final collectors = _stringKeyedMap(yaml['collectors']);
    final gates = _stringKeyedMap(yaml['gates']);

    return BenchConfig(
      suite: _stringValue(yaml['suite']) ?? 'ianvs_terminal_bench',
      version: _intValue(yaml['version']) ?? 1,
      framePolicies: _stringList(
        policies['frame'],
      ).map(BenchFramePolicy.parse).toList(growable: false),
      renderPolicies: _stringList(
        policies['render'],
        fallback: const ['normal_render'],
      ).map(BenchRenderPolicy.parse).toList(growable: false),
      workloads: _stringList(yaml['workloads']),
      viewportCols: _intValue(viewport['cols']) ?? 120,
      viewportRows: _intValue(viewport['rows']) ?? 40,
      repeat: _intValue(yaml['repeat']) ?? 1,
      warmupRuns: _intValue(yaml['warmup_runs']) ?? 0,
      outputDir: _stringValue(yaml['output_dir']) ?? 'build/bench-results',
      collectors: BenchCollectors(
        rustFrame: _boolValue(collectors['rust_frame'], fallback: true),
        dartRuntime: _boolValue(collectors['dart_runtime'], fallback: true),
        flutterRender: _boolValue(collectors['flutter_render'], fallback: true),
        flutterFrameTiming: _boolValue(
          collectors['flutter_frame_timing'],
          fallback: true,
        ),
        osResource: _boolValue(collectors['os_resource'], fallback: false),
      ),
      gates: BenchGates(
        requireHashMatch: _boolValue(
          gates['require_hash_match'],
          fallback: false,
        ),
        requireSchemaValid: _boolValue(
          gates['require_schema_valid'],
          fallback: false,
        ),
      ),
    );
  }

  final String suite;
  final int version;
  final List<BenchFramePolicy> framePolicies;
  final List<BenchRenderPolicy> renderPolicies;
  final List<String> workloads;
  final int viewportCols;
  final int viewportRows;
  final int repeat;
  final int warmupRuns;
  final String outputDir;
  final BenchCollectors collectors;
  final BenchGates gates;

  String toYaml() {
    return SimpleYaml.encodeMap(<String, Object?>{
      'suite': suite,
      'version': version,
      'policies': <String, Object?>{
        'frame': framePolicies.map((policy) => policy.wireName).toList(),
        'render': renderPolicies.map((policy) => policy.wireName).toList(),
      },
      'workloads': workloads,
      'viewport': <String, Object?>{'cols': viewportCols, 'rows': viewportRows},
      'repeat': repeat,
      'warmup_runs': warmupRuns,
      'output_dir': outputDir,
      'collectors': collectors.toYamlMap(),
      'gates': <String, Object?>{
        'require_hash_match': gates.requireHashMatch,
        'require_schema_valid': gates.requireSchemaValid,
      },
    });
  }
}

Map<String, Object?> _stringKeyedMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  return const <String, Object?>{};
}

List<String> _stringList(Object? value, {List<String> fallback = const []}) {
  if (value is! List) {
    return fallback;
  }
  return value
      .whereType<Object>()
      .map((entry) => entry.toString())
      .toList(growable: false);
}

String? _stringValue(Object? value) => value is String ? value : null;

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

bool _boolValue(Object? value, {required bool fallback}) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    return switch (value) {
      'true' => true,
      'false' => false,
      _ => fallback,
    };
  }
  return fallback;
}
