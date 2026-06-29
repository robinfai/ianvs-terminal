import 'dart:io';

import '../src/flutter_profile_matrix.dart';
import '../src/flutter_profile_report_audit.dart';

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.write(_usage);
    return;
  }

  try {
    final options = FlutterProfileMatrixOptions.parse(args);
    final inputs = _inputDirectories(args);
    final output = Directory(options.outputRoot);
    final result = FlutterProfileReportAudit(
      requiredTargetCount: options.requiredTargetCount,
      requiredWorkloads: options.workloads,
      requiredRepeats: options.repeats,
      readinessReportPath: options.readinessOutput,
      runbookReportPath: options.runbookOutput,
    ).audit(inputDirectories: inputs, outputDirectory: output);

    stdout.writeln(
      'Formal profile audit: ${result.passed ? 'passed' : 'failed'}',
    );
    stdout.writeln('Formal profile report: ${output.path}');
    for (final failure in result.failures) {
      stderr.writeln('FAIL: $failure');
    }
    exitCode = result.passed ? 0 : 1;
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(_usage);
    exitCode = 64;
  } on Object catch (error) {
    stderr.writeln('Formal profile audit failed: $error');
    exitCode = 1;
  }
}

List<Directory> _inputDirectories(List<String> args) {
  final inputs = <Directory>[];
  for (var index = 0; index < args.length; index += 1) {
    final arg = args[index];
    if (arg == '--input') {
      if (index + 1 >= args.length) {
        throw const FormatException('Missing value for --input');
      }
      inputs.add(Directory(args[index + 1]));
      index += 1;
      continue;
    }
    if (arg.startsWith('--input=')) {
      inputs.add(Directory(arg.substring('--input='.length)));
    }
  }
  if (inputs.isEmpty) {
    throw const FormatException('Missing --input');
  }
  for (final input in inputs) {
    if (!input.existsSync()) {
      throw FormatException('Input directory does not exist: ${input.path}');
    }
  }
  return inputs;
}

const _usage = '''
Ianvs formal Flutter profile audit

Usage:
  dart run tools/bench/analysis/flutter_profile_audit.dart \\
    --input build/bench-results-profile/<target-run> \\
    --output build/bench-results-profile/formal-report \\
    --require-target-count 2

Options:
  --input <dir>                  Matrix result directory; may be repeated.
  --output <dir>                 Formal report output directory.
  --readiness-output <file>      Readiness JSON from the matrix runner.
  --runbook-output <file>        Target setup/runbook markdown from the runner.
  --workloads <a,b,c>            Required workloads.
  --repeats <n>                  Required repeats per target/workload.
  --require-target-count <n>     Minimum target device count.
''';
