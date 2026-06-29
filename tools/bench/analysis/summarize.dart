import 'dart:io';

import '../src/summary_analyzer.dart';

void main(List<String> args) {
  try {
    final input = _inputPath(args);
    final directory = Directory(input);
    if (!directory.existsSync()) {
      throw FormatException('Input directory does not exist: $input');
    }
    const SummaryAnalyzer().summarizeRunDirectory(directory);
    stdout.writeln('Summary written: ${directory.path}');
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(
      'Usage: dart run tools/bench/analysis/summarize.dart --input <run-dir>',
    );
    exitCode = 64;
  } on Object catch (error) {
    stderr.writeln('Summary failed: $error');
    exitCode = 1;
  }
}

String _inputPath(List<String> args) {
  if (args.isEmpty) {
    throw const FormatException('Missing --input');
  }
  for (var index = 0; index < args.length; index += 1) {
    final arg = args[index];
    if (arg == '--input') {
      if (index + 1 >= args.length) {
        throw const FormatException('Missing value for --input');
      }
      return args[index + 1];
    }
    if (arg.startsWith('--input=')) {
      return arg.substring('--input='.length);
    }
  }
  if (args.length == 1 && !args.single.startsWith('--')) {
    return args.single;
  }
  throw const FormatException('Missing --input');
}
