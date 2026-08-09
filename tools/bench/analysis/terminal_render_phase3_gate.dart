import 'dart:convert';
import 'dart:io';

import '../src/terminal_render_phase3_gate.dart';

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.write(_usage);
    return;
  }

  try {
    final options = _Phase3GateOptions.parse(args);
    final result = TerminalRenderPhase3Gate.evaluate(
      beforeRoot: Directory(options.beforeRoot),
      afterRoot: Directory(options.afterRoot),
      workload: options.workload,
      repeats: options.repeats,
    );
    final output = File(options.outputPath);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(result.toJson())}\n',
    );

    stdout.writeln(
      'Terminal render Phase 3 gate: '
      '${result.passed ? 'passed' : 'failed'}',
    );
    stdout.writeln('Report: ${output.path}');
    for (final failure in result.failures) {
      stderr.writeln('FAIL [${failure.code}]: ${failure.message}');
    }
    exitCode = result.passed ? 0 : 1;
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(_usage);
    exitCode = 64;
  } on Object catch (error) {
    stderr.writeln('Terminal render Phase 3 gate failed: $error');
    exitCode = 1;
  }
}

final class _Phase3GateOptions {
  const _Phase3GateOptions({
    required this.beforeRoot,
    required this.afterRoot,
    required this.outputPath,
    required this.workload,
    required this.repeats,
  });

  final String beforeRoot;
  final String afterRoot;
  final String outputPath;
  final String workload;
  final int repeats;

  static _Phase3GateOptions parse(List<String> args) {
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 1) {
      final argument = args[index];
      if (!argument.startsWith('--')) {
        throw FormatException('Unexpected argument: $argument');
      }
      final equalsIndex = argument.indexOf('=');
      if (equalsIndex > 2) {
        values[argument.substring(2, equalsIndex)] = argument.substring(
          equalsIndex + 1,
        );
        continue;
      }
      if (index + 1 >= args.length) {
        throw FormatException('Missing value for $argument');
      }
      values[argument.substring(2)] = args[index + 1];
      index += 1;
    }

    const requiredNames = <String>[
      'before',
      'after',
      'output',
      'workload',
      'repeats',
    ];
    for (final name in requiredNames) {
      if (values[name]?.isNotEmpty != true) {
        throw FormatException('Missing --$name');
      }
    }
    final unexpected = values.keys
        .where((name) => !requiredNames.contains(name))
        .toList();
    if (unexpected.isNotEmpty) {
      throw FormatException('Unknown option --${unexpected.first}');
    }
    final repeats = int.tryParse(values['repeats']!);
    if (repeats == null || repeats <= 0) {
      throw const FormatException('--repeats must be a positive integer');
    }
    return _Phase3GateOptions(
      beforeRoot: values['before']!,
      afterRoot: values['after']!,
      outputPath: values['output']!,
      workload: values['workload']!,
      repeats: repeats,
    );
  }
}

const String _usage = r'''
Ianvs terminal render Phase 3 profile gate

Usage:
  dart run tools/bench/analysis/terminal_render_phase3_gate.dart \
    --before <matrix-root> \
    --after <matrix-root> \
    --output <report.json> \
    --workload <name> \
    --repeats <count>

The gate scans every immediate child directory of each matrix root as a target
label. Timing limits are immutable: total-span median <= 1.05x before and paint
median <= 1.00x before.
''';
