import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../src/terminal_render_phase3_gate.dart';

void main() {
  const workload = 'scrollback_heavy_profile';
  const targets = <String>['macos-darwin-arm64', 'macos-darwin-x64'];

  late Directory tempDirectory;
  late Directory beforeRoot;
  late Directory afterRoot;

  setUp(() {
    tempDirectory = Directory.systemTemp.createTempSync('phase3-gate-test-');
    beforeRoot = Directory('${tempDirectory.path}/before');
    afterRoot = Directory('${tempDirectory.path}/after');
    _writeMatrix(
      beforeRoot,
      targets: targets,
      workload: workload,
      totalSpanMicros: const [100, 110, 120],
      paintMicros: const [50, 55, 60],
      includePhase3RenderMetrics: false,
    );
    _writeMatrix(
      afterRoot,
      targets: targets,
      workload: workload,
      totalSpanMicros: const [100, 110, 115],
      paintMicros: const [49, 54, 55],
      includePhase3RenderMetrics: true,
    );
  });

  tearDown(() {
    tempDirectory.deleteSync(recursive: true);
  });

  test('passes matching targets, repeats, correctness, schema, and timing', () {
    final result = TerminalRenderPhase3Gate.evaluate(
      beforeRoot: beforeRoot,
      afterRoot: afterRoot,
      workload: workload,
      repeats: 3,
    );

    expect(result.passed, isTrue);
    expect(result.failureCodes, isEmpty);
    expect(result.targetResults, hasLength(2));
    expect(result.toJson(), containsPair('schema_version', phase3GateSchema));
  });

  test('rejects timing regression at immutable thresholds', () {
    _writeMatrix(
      afterRoot,
      targets: targets,
      workload: workload,
      totalSpanMicros: const [120, 121, 122],
      paintMicros: const [56, 57, 58],
      includePhase3RenderMetrics: true,
    );

    final result = TerminalRenderPhase3Gate.evaluate(
      beforeRoot: beforeRoot,
      afterRoot: afterRoot,
      workload: workload,
      repeats: 3,
    );

    expect(result.passed, isFalse);
    expect(
      result.failureCodes,
      containsAll(<String>[
        'p95_total_span_regression',
        'p95_paint_regression',
      ]),
    );
  });

  test('rejects missing summary and after render metrics', () {
    final summary = File('${afterRoot.path}/${targets.first}/summary.csv');
    summary.writeAsStringSync(
      summary.readAsStringSync().replaceFirst(',p95_paint_micros', ''),
    );
    final render = File(
      '${afterRoot.path}/${targets.last}/$workload/repeat_2/'
      'flutter_render.ndjson',
    );
    final event =
        jsonDecode(render.readAsLinesSync().single) as Map<String, Object?>;
    event.remove('picture_draw_count');
    render.writeAsStringSync('${jsonEncode(event)}\n');

    final result = TerminalRenderPhase3Gate.evaluate(
      beforeRoot: beforeRoot,
      afterRoot: afterRoot,
      workload: workload,
      repeats: 3,
    );

    expect(result.passed, isFalse);
    expect(
      result.failureCodes,
      containsAll(<String>[
        'summary_metric_missing',
        'after_render_metric_missing',
      ]),
    );
  });

  test('rejects after render files containing only whitespace', () {
    final render = File(
      '${afterRoot.path}/${targets.first}/$workload/repeat_2/'
      'flutter_render.ndjson',
    );
    render.writeAsStringSync('\n   \n');

    final result = TerminalRenderPhase3Gate.evaluate(
      beforeRoot: beforeRoot,
      afterRoot: afterRoot,
      workload: workload,
      repeats: 3,
    );
    final output = File('${tempDirectory.path}/empty-render-gate.json');
    final process = _runGateCli(
      beforeRoot: beforeRoot,
      afterRoot: afterRoot,
      output: output,
      workload: workload,
    );

    expect(result.passed, isFalse);
    expect(result.failureCodes, contains('after_render_empty'));
    expect(() => jsonEncode(result.toJson()), returnsNormally);
    expect(process.exitCode, 1, reason: '${process.stderr}');
    final report =
        jsonDecode(output.readAsStringSync()) as Map<String, Object?>;
    expect(report['passed'], isFalse);
    expect(report['failure_codes'], contains('after_render_empty'));
  });

  for (final nonFiniteValue in <String>['NaN', 'Infinity']) {
    test('rejects non-finite after timing metric $nonFiniteValue', () {
      _rewriteSummaryMetric(
        File('${afterRoot.path}/${targets.first}/summary.csv'),
        metric: 'p95_total_span_micros',
        value: nonFiniteValue,
      );

      final result = TerminalRenderPhase3Gate.evaluate(
        beforeRoot: beforeRoot,
        afterRoot: afterRoot,
        workload: workload,
        repeats: 3,
      );

      expect(result.passed, isFalse);
      expect(result.failureCodes, contains('summary_metric_non_finite'));
      expect(result.failureCodes, isNot(contains('p95_total_span_regression')));
      expect(() => jsonEncode(result.toJson()), returnsNormally);
    });
  }

  test('rejects any before or after correctness hash mismatch', () {
    final correctness = File(
      '${beforeRoot.path}/${targets.first}/$workload/repeat_3/'
      'correctness.json',
    );
    correctness.writeAsStringSync(
      jsonEncode(<String, Object?>{'hash_match': false}),
    );

    final result = TerminalRenderPhase3Gate.evaluate(
      beforeRoot: beforeRoot,
      afterRoot: afterRoot,
      workload: workload,
      repeats: 3,
    );

    expect(result.passed, isFalse);
    expect(result.failureCodes, contains('correctness_hash_mismatch'));
  });

  test('rejects target label set mismatch', () {
    Directory(
      '${afterRoot.path}/${targets.last}',
    ).renameSync('${afterRoot.path}/macos-darwin-unexpected');

    final result = TerminalRenderPhase3Gate.evaluate(
      beforeRoot: beforeRoot,
      afterRoot: afterRoot,
      workload: workload,
      repeats: 3,
    );

    expect(result.passed, isFalse);
    expect(result.failureCodes, contains('target_label_mismatch'));
  });

  test('rejects matrix roots with no immediate target directories', () {
    beforeRoot
      ..deleteSync(recursive: true)
      ..createSync(recursive: true);
    afterRoot
      ..deleteSync(recursive: true)
      ..createSync(recursive: true);

    final result = TerminalRenderPhase3Gate.evaluate(
      beforeRoot: beforeRoot,
      afterRoot: afterRoot,
      workload: workload,
      repeats: 3,
    );
    final output = File('${tempDirectory.path}/empty-roots-gate.json');
    final process = _runGateCli(
      beforeRoot: beforeRoot,
      afterRoot: afterRoot,
      output: output,
      workload: workload,
    );

    expect(result.passed, isFalse);
    final emptyFailures = result.failures
        .where((failure) => failure.code == 'matrix_targets_empty')
        .toList(growable: false);
    expect(emptyFailures, hasLength(2));
    expect(emptyFailures.map((failure) => failure.side).toSet(), {
      'before',
      'after',
    });
    expect(() => jsonEncode(result.toJson()), returnsNormally);
    expect(process.exitCode, 1, reason: '${process.stderr}');
    final report =
        jsonDecode(output.readAsStringSync()) as Map<String, Object?>;
    expect(report['passed'], isFalse);
    expect(report['failure_codes'], contains('matrix_targets_empty'));
  });

  test('rejects unequal or unexpected repeat counts', () {
    Directory(
      '${afterRoot.path}/${targets.first}/$workload/repeat_3',
    ).deleteSync(recursive: true);
    _rewriteSummaryWithoutRepeat(
      File('${afterRoot.path}/${targets.first}/summary.csv'),
      repeat: 3,
    );

    final result = TerminalRenderPhase3Gate.evaluate(
      beforeRoot: beforeRoot,
      afterRoot: afterRoot,
      workload: workload,
      repeats: 3,
    );

    expect(result.passed, isFalse);
    expect(result.failureCodes, contains('repeat_count_mismatch'));
  });

  test('CLI writes schema JSON and returns gate pass or failure exit code', () {
    final output = File('${tempDirectory.path}/gate.json');
    ProcessResult runCli() =>
        Process.runSync(Platform.resolvedExecutable, <String>[
          'run',
          'tools/bench/analysis/terminal_render_phase3_gate.dart',
          '--before',
          beforeRoot.path,
          '--after',
          afterRoot.path,
          '--output',
          output.path,
          '--workload',
          workload,
          '--repeats',
          '3',
        ], workingDirectory: Directory.current.path);

    final passing = runCli();
    expect(passing.exitCode, 0, reason: '${passing.stderr}');
    expect(
      jsonDecode(output.readAsStringSync()),
      containsPair('schema_version', phase3GateSchema),
    );

    final render = File(
      '${afterRoot.path}/${targets.first}/$workload/repeat_1/'
      'flutter_render.ndjson',
    );
    render.writeAsStringSync(
      '${jsonEncode(<String, Object?>{'paint_micros': 1})}\n',
    );
    final failing = runCli();
    expect(failing.exitCode, 1, reason: '${failing.stderr}');
    expect(
      jsonDecode(output.readAsStringSync()),
      containsPair('passed', isFalse),
    );
  });

  test('CLI writes valid failure JSON for a non-finite timing metric', () {
    _rewriteSummaryMetric(
      File('${afterRoot.path}/${targets.first}/summary.csv'),
      metric: 'p95_paint_micros',
      value: 'NaN',
    );
    final output = File('${tempDirectory.path}/non-finite-gate.json');

    final process = Process.runSync(Platform.resolvedExecutable, <String>[
      'run',
      'tools/bench/analysis/terminal_render_phase3_gate.dart',
      '--before',
      beforeRoot.path,
      '--after',
      afterRoot.path,
      '--output',
      output.path,
      '--workload',
      workload,
      '--repeats',
      '3',
    ], workingDirectory: Directory.current.path);

    expect(process.exitCode, 1, reason: '${process.stderr}');
    expect(output.existsSync(), isTrue);
    final report =
        jsonDecode(output.readAsStringSync()) as Map<String, Object?>;
    expect(report['passed'], isFalse);
    expect(report['failure_codes'], contains('summary_metric_non_finite'));
  });
}

void _writeMatrix(
  Directory root, {
  required List<String> targets,
  required String workload,
  required List<int> totalSpanMicros,
  required List<int> paintMicros,
  required bool includePhase3RenderMetrics,
}) {
  for (final target in targets) {
    final targetDirectory = Directory('${root.path}/$target')
      ..createSync(recursive: true);
    final summaryRows = <String>[
      'target_platform,target_device,workload,policy,repeat,hash_match,'
          'p95_total_span_micros,p95_paint_micros',
    ];
    for (var index = 0; index < totalSpanMicros.length; index += 1) {
      final repeat = index + 1;
      summaryRows.add(
        'macos,$target,$workload,real_flutter_profile,$repeat,true,'
        '${totalSpanMicros[index]},${paintMicros[index]}',
      );
      final runDirectory = Directory(
        '${targetDirectory.path}/$workload/repeat_$repeat',
      )..createSync(recursive: true);
      File('${runDirectory.path}/correctness.json').writeAsStringSync(
        '${jsonEncode(<String, Object?>{'hash_match': true})}\n',
      );
      final renderEvent = <String, Object?>{
        'schema_version': 'ianvs-bench-flutter-render-v1',
        'paint_micros': paintMicros[index],
        if (includePhase3RenderMetrics) ...<String, Object?>{
          'rows_visited': 40,
          'picture_draw_count': 40,
          'debug_collection_enabled': false,
        },
      };
      File(
        '${runDirectory.path}/flutter_render.ndjson',
      ).writeAsStringSync('${jsonEncode(renderEvent)}\n');
    }
    File(
      '${targetDirectory.path}/summary.csv',
    ).writeAsStringSync('${summaryRows.join('\n')}\n');
  }
}

void _rewriteSummaryWithoutRepeat(File summary, {required int repeat}) {
  final lines = summary.readAsLinesSync();
  final repeatIndex = lines.first.split(',').indexOf('repeat');
  summary.writeAsStringSync(
    '${lines.where((line) {
      if (identical(line, lines.first)) {
        return true;
      }
      return line.split(',')[repeatIndex] != '$repeat';
    }).join('\n')}\n',
  );
}

void _rewriteSummaryMetric(
  File summary, {
  required String metric,
  required String value,
}) {
  final lines = summary.readAsLinesSync();
  final header = lines.first.split(',');
  final metricIndex = header.indexOf(metric);
  summary.writeAsStringSync(
    '${<String>[lines.first, for (final line in lines.skip(1)) (line.split(',')..[metricIndex] = value).join(',')].join('\n')}\n',
  );
}

ProcessResult _runGateCli({
  required Directory beforeRoot,
  required Directory afterRoot,
  required File output,
  required String workload,
}) {
  return Process.runSync(Platform.resolvedExecutable, <String>[
    'run',
    'tools/bench/analysis/terminal_render_phase3_gate.dart',
    '--before',
    beforeRoot.path,
    '--after',
    afterRoot.path,
    '--output',
    output.path,
    '--workload',
    workload,
    '--repeats',
    '3',
  ], workingDirectory: Directory.current.path);
}
