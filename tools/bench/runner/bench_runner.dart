import 'dart:io';

import '../src/bench_config.dart';
import '../src/bench_policy.dart';
import '../src/bench_runner_core.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.write(_usage);
    return;
  }

  try {
    final parsed = _parseArgs(args);
    final configPath = parsed['config'];
    final result = configPath == null
        ? await _runSingle(parsed)
        : await BenchRunnerCore().runConfig(
            BenchConfig.fromFile(File(configPath)),
          );

    stdout.writeln('Benchmark results: ${result.outputDirectory.path}');
    for (final failure in result.failures) {
      stderr.writeln('FAIL: $failure');
    }
    exitCode = result.exitCode;
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(_usage);
    exitCode = 64;
  } on Object catch (error) {
    stderr.writeln('Benchmark runner failed: $error');
    exitCode = 1;
  }
}

Future<BenchRunnerResult> _runSingle(Map<String, String> parsed) {
  final workload = parsed['workload'];
  if (workload == null || workload.isEmpty) {
    throw const FormatException('Missing --workload or --config');
  }
  final framePolicy = BenchFramePolicy.parse(
    parsed['frame-policy'] ?? parsed['policy'] ?? 'delta_coalesced',
  );
  final renderPolicy = BenchRenderPolicy.parse(
    parsed['render-policy'] ?? 'normal_render',
  );
  final cols = int.tryParse(parsed['cols'] ?? '120') ?? 120;
  final rows = int.tryParse(parsed['rows'] ?? '40') ?? 40;
  final output =
      parsed['output'] ?? parsed['output-dir'] ?? 'build/bench-results';

  return BenchRunnerCore().runSingle(
    workloadName: workload,
    framePolicy: framePolicy,
    renderPolicy: renderPolicy,
    cols: cols,
    rows: rows,
    outputDir: output,
  );
}

Map<String, String> _parseArgs(List<String> args) {
  final parsed = <String, String>{};
  for (var index = 0; index < args.length; index += 1) {
    final arg = args[index];
    if (!arg.startsWith('--')) {
      throw FormatException('Unexpected argument: $arg');
    }
    final withoutPrefix = arg.substring(2);
    final equalsIndex = withoutPrefix.indexOf('=');
    if (equalsIndex >= 0) {
      parsed[withoutPrefix.substring(0, equalsIndex)] = withoutPrefix.substring(
        equalsIndex + 1,
      );
      continue;
    }
    if (index + 1 >= args.length || args[index + 1].startsWith('--')) {
      throw FormatException('Missing value for --$withoutPrefix');
    }
    parsed[withoutPrefix] = args[index + 1];
    index += 1;
  }
  return parsed;
}

const _usage = '''
Ianvs benchmark runner

Usage:
  dart run tools/bench/runner/bench_runner.dart --config tools/bench/configs/bench_ci_smoke.yaml

  dart run tools/bench/runner/bench_runner.dart \\
    --workload burst_stdout.seq_1000 \\
    --frame-policy delta_coalesced \\
    --render-policy headless_state_only \\
    --cols 80 \\
    --rows 24 \\
    --output build/bench-results
''';
