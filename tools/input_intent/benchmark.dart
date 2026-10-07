import 'dart:convert';
import 'dart:io';

// Repository-only tool: this package is a member of the root Dart workspace.
// ignore: depend_on_referenced_packages
import 'package:ianvs_terminal/input_intent.dart';

// Pure Dart smoke and a bounded, warmed local inference benchmark. No shell,
// model endpoint, user history or network is consulted.
void main() {
  final inputs = [
    '找出最近修改的几个文件',
    'the build failed again',
    'custom-cli --version',
    'make build',
    'make me a sandwich',
    'git status 是什么意思',
    'network details ${'connection refused ' * 100}',
  ];
  const context = InputIntentContext(commandNames: {'make', 'git'});
  for (var i = 0; i < 100; i++) {
    classifyInputIntent(inputs[i % inputs.length], context: context);
  }
  final times = <int>[];
  for (var i = 0; i < 1000; i++) {
    final watch = Stopwatch()..start();
    classifyInputIntent(inputs[i % inputs.length], context: context);
    times.add(watch.elapsedMicroseconds);
  }
  times.sort();
  stdout.writeln(
    jsonEncode({
      'samples': times.length,
      'p50Microseconds': times[500],
      'p95Microseconds': times[950],
      'p99Microseconds': times[990],
      'maxMicroseconds': times.last,
    }),
  );
}
