import 'dart:convert';
import 'dart:io';

const String phase3GateSchema = 'ianvs-terminal-render-phase3-gate-v1';
const double phase3TotalSpanLimitRatio = 1.05;
const double phase3PaintLimitRatio = 1.00;

final class TerminalRenderPhase3Gate {
  const TerminalRenderPhase3Gate._();

  static TerminalRenderPhase3GateResult evaluate({
    required Directory beforeRoot,
    required Directory afterRoot,
    required String workload,
    required int repeats,
  }) {
    if (workload.isEmpty) {
      throw ArgumentError.value(workload, 'workload', 'must not be empty');
    }
    if (repeats <= 0) {
      throw ArgumentError.value(repeats, 'repeats', 'must be positive');
    }

    final failures = <TerminalRenderPhase3GateFailure>[];
    final beforeTargets = _targetDirectories(
      beforeRoot,
      side: 'before',
      failures: failures,
    );
    final afterTargets = _targetDirectories(
      afterRoot,
      side: 'after',
      failures: failures,
    );
    final beforeLabels = beforeTargets.keys.toSet();
    final afterLabels = afterTargets.keys.toSet();
    if (!_sameStringSet(beforeLabels, afterLabels)) {
      failures.add(
        TerminalRenderPhase3GateFailure(
          code: 'target_label_mismatch',
          message:
              'before targets ${_sorted(beforeLabels)} do not match '
              'after targets ${_sorted(afterLabels)}',
        ),
      );
    }

    final targetResults = <TerminalRenderPhase3TargetResult>[];
    final commonLabels = beforeLabels.intersection(afterLabels).toList()
      ..sort();
    for (final targetLabel in commonLabels) {
      final targetFailuresBefore = failures.length;
      final beforeDirectory = beforeTargets[targetLabel]!;
      final afterDirectory = afterTargets[targetLabel]!;
      final beforeRows = _readWorkloadSummaryRows(
        beforeDirectory,
        workload: workload,
        side: 'before',
        targetLabel: targetLabel,
        failures: failures,
      );
      final afterRows = _readWorkloadSummaryRows(
        afterDirectory,
        workload: workload,
        side: 'after',
        targetLabel: targetLabel,
        failures: failures,
      );
      final beforeRepeats = _repeatNumbers(beforeRows);
      final afterRepeats = _repeatNumbers(afterRows);
      final expectedRepeats = <int>{
        for (var repeat = 1; repeat <= repeats; repeat += 1) repeat,
      };
      if (beforeRows.length != repeats ||
          afterRows.length != repeats ||
          !_sameIntSet(beforeRepeats, afterRepeats) ||
          !_sameIntSet(beforeRepeats, expectedRepeats)) {
        failures.add(
          TerminalRenderPhase3GateFailure(
            code: 'repeat_count_mismatch',
            message:
                '$targetLabel/$workload expected repeats '
                '${_sortedInts(expectedRepeats)}, found before '
                '${_sortedInts(beforeRepeats)} (${beforeRows.length} rows) '
                'and after ${_sortedInts(afterRepeats)} '
                '(${afterRows.length} rows)',
            targetLabel: targetLabel,
          ),
        );
      }

      _validateSummaryHashes(
        beforeRows,
        side: 'before',
        targetLabel: targetLabel,
        failures: failures,
      );
      _validateSummaryHashes(
        afterRows,
        side: 'after',
        targetLabel: targetLabel,
        failures: failures,
      );
      _validateRunArtifacts(
        beforeDirectory,
        side: 'before',
        targetLabel: targetLabel,
        workload: workload,
        repeatNumbers: beforeRepeats,
        requirePhase3RenderMetrics: false,
        failures: failures,
      );
      _validateRunArtifacts(
        afterDirectory,
        side: 'after',
        targetLabel: targetLabel,
        workload: workload,
        repeatNumbers: afterRepeats,
        requirePhase3RenderMetrics: true,
        failures: failures,
      );

      final beforeTotalMedian = _metricMedian(
        beforeRows,
        metric: 'p95_total_span_micros',
        side: 'before',
        targetLabel: targetLabel,
        failures: failures,
      );
      final afterTotalMedian = _metricMedian(
        afterRows,
        metric: 'p95_total_span_micros',
        side: 'after',
        targetLabel: targetLabel,
        failures: failures,
      );
      final beforePaintMedian = _metricMedian(
        beforeRows,
        metric: 'p95_paint_micros',
        side: 'before',
        targetLabel: targetLabel,
        failures: failures,
      );
      final afterPaintMedian = _metricMedian(
        afterRows,
        metric: 'p95_paint_micros',
        side: 'after',
        targetLabel: targetLabel,
        failures: failures,
      );
      final totalLimit = beforeTotalMedian == null
          ? null
          : beforeTotalMedian * phase3TotalSpanLimitRatio;
      final paintLimit = beforePaintMedian == null
          ? null
          : beforePaintMedian * phase3PaintLimitRatio;
      if (afterTotalMedian != null &&
          totalLimit != null &&
          afterTotalMedian > totalLimit) {
        failures.add(
          TerminalRenderPhase3GateFailure(
            code: 'p95_total_span_regression',
            message:
                '$targetLabel median p95_total_span_micros '
                '$afterTotalMedian exceeds immutable limit $totalLimit',
            targetLabel: targetLabel,
            metric: 'p95_total_span_micros',
          ),
        );
      }
      if (afterPaintMedian != null &&
          paintLimit != null &&
          afterPaintMedian > paintLimit) {
        failures.add(
          TerminalRenderPhase3GateFailure(
            code: 'p95_paint_regression',
            message:
                '$targetLabel median p95_paint_micros '
                '$afterPaintMedian exceeds immutable limit $paintLimit',
            targetLabel: targetLabel,
            metric: 'p95_paint_micros',
          ),
        );
      }

      targetResults.add(
        TerminalRenderPhase3TargetResult(
          targetLabel: targetLabel,
          beforeRepeatCount: beforeRows.length,
          afterRepeatCount: afterRows.length,
          beforeP95TotalSpanMedian: beforeTotalMedian,
          afterP95TotalSpanMedian: afterTotalMedian,
          p95TotalSpanLimit: totalLimit,
          beforeP95PaintMedian: beforePaintMedian,
          afterP95PaintMedian: afterPaintMedian,
          p95PaintLimit: paintLimit,
          passed: failures.length == targetFailuresBefore,
        ),
      );
    }

    return TerminalRenderPhase3GateResult(
      passed: failures.isEmpty,
      beforeRoot: beforeRoot.path,
      afterRoot: afterRoot.path,
      workload: workload,
      repeats: repeats,
      beforeTargetLabels: _sorted(beforeLabels),
      afterTargetLabels: _sorted(afterLabels),
      targetResults: List<TerminalRenderPhase3TargetResult>.unmodifiable(
        targetResults,
      ),
      failures: List<TerminalRenderPhase3GateFailure>.unmodifiable(failures),
    );
  }
}

final class TerminalRenderPhase3GateResult {
  const TerminalRenderPhase3GateResult({
    required this.passed,
    required this.beforeRoot,
    required this.afterRoot,
    required this.workload,
    required this.repeats,
    required this.beforeTargetLabels,
    required this.afterTargetLabels,
    required this.targetResults,
    required this.failures,
  });

  final bool passed;
  final String beforeRoot;
  final String afterRoot;
  final String workload;
  final int repeats;
  final List<String> beforeTargetLabels;
  final List<String> afterTargetLabels;
  final List<TerminalRenderPhase3TargetResult> targetResults;
  final List<TerminalRenderPhase3GateFailure> failures;

  List<String> get failureCodes => List<String>.unmodifiable(
    failures.map((failure) => failure.code).toSet(),
  );

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema_version': phase3GateSchema,
      'passed': passed,
      'before_root': beforeRoot,
      'after_root': afterRoot,
      'workload': workload,
      'required_repeats': repeats,
      'thresholds': const <String, Object?>{
        'p95_total_span_median_max_ratio': phase3TotalSpanLimitRatio,
        'p95_paint_median_max_ratio': phase3PaintLimitRatio,
      },
      'target_labels': <String, Object?>{
        'before': beforeTargetLabels,
        'after': afterTargetLabels,
      },
      'targets': targetResults.map((target) => target.toJson()).toList(),
      'failure_codes': failureCodes,
      'failures': failures.map((failure) => failure.toJson()).toList(),
    };
  }
}

final class TerminalRenderPhase3TargetResult {
  const TerminalRenderPhase3TargetResult({
    required this.targetLabel,
    required this.beforeRepeatCount,
    required this.afterRepeatCount,
    required this.beforeP95TotalSpanMedian,
    required this.afterP95TotalSpanMedian,
    required this.p95TotalSpanLimit,
    required this.beforeP95PaintMedian,
    required this.afterP95PaintMedian,
    required this.p95PaintLimit,
    required this.passed,
  });

  final String targetLabel;
  final int beforeRepeatCount;
  final int afterRepeatCount;
  final double? beforeP95TotalSpanMedian;
  final double? afterP95TotalSpanMedian;
  final double? p95TotalSpanLimit;
  final double? beforeP95PaintMedian;
  final double? afterP95PaintMedian;
  final double? p95PaintLimit;
  final bool passed;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'target_label': targetLabel,
      'passed': passed,
      'before_repeat_count': beforeRepeatCount,
      'after_repeat_count': afterRepeatCount,
      'p95_total_span_micros': <String, Object?>{
        'before_median': beforeP95TotalSpanMedian,
        'after_median': afterP95TotalSpanMedian,
        'limit': p95TotalSpanLimit,
      },
      'p95_paint_micros': <String, Object?>{
        'before_median': beforeP95PaintMedian,
        'after_median': afterP95PaintMedian,
        'limit': p95PaintLimit,
      },
    };
  }
}

final class TerminalRenderPhase3GateFailure {
  const TerminalRenderPhase3GateFailure({
    required this.code,
    required this.message,
    this.targetLabel,
    this.metric,
    this.side,
    this.repeat,
  });

  final String code;
  final String message;
  final String? targetLabel;
  final String? metric;
  final String? side;
  final int? repeat;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'code': code,
      'message': message,
      if (targetLabel != null) 'target_label': targetLabel,
      if (metric != null) 'metric': metric,
      if (side != null) 'side': side,
      if (repeat != null) 'repeat': repeat,
    };
  }
}

Map<String, Directory> _targetDirectories(
  Directory root, {
  required String side,
  required List<TerminalRenderPhase3GateFailure> failures,
}) {
  if (!root.existsSync()) {
    failures.add(
      TerminalRenderPhase3GateFailure(
        code: 'matrix_root_missing',
        message: '$side matrix root does not exist: ${root.path}',
        side: side,
      ),
    );
    return const <String, Directory>{};
  }
  final targets = <String, Directory>{};
  for (final entry in root.listSync(followLinks: false)) {
    if (entry is! Directory) {
      continue;
    }
    final label = entry.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .last;
    targets[label] = entry;
  }
  if (targets.isEmpty) {
    failures.add(
      TerminalRenderPhase3GateFailure(
        code: 'matrix_targets_empty',
        message:
            '$side matrix root has no immediate target directories: '
            '${root.path}',
        side: side,
      ),
    );
  }
  return targets;
}

List<Map<String, String>> _readWorkloadSummaryRows(
  Directory targetDirectory, {
  required String workload,
  required String side,
  required String targetLabel,
  required List<TerminalRenderPhase3GateFailure> failures,
}) {
  final summary = File('${targetDirectory.path}/summary.csv');
  if (!summary.existsSync()) {
    failures.add(
      TerminalRenderPhase3GateFailure(
        code: 'summary_missing',
        message: '$side summary.csv is missing: ${summary.path}',
        targetLabel: targetLabel,
        side: side,
      ),
    );
    return const <Map<String, String>>[];
  }
  final lines = summary
      .readAsLinesSync()
      .where((line) => line.trim().isNotEmpty)
      .toList(growable: false);
  if (lines.length < 2) {
    failures.add(
      TerminalRenderPhase3GateFailure(
        code: 'summary_empty',
        message: '$side summary.csv has no data rows: ${summary.path}',
        targetLabel: targetLabel,
        side: side,
      ),
    );
    return const <Map<String, String>>[];
  }
  final header = _parseCsvLine(lines.first);
  final rows = <Map<String, String>>[];
  for (final line in lines.skip(1)) {
    final values = _parseCsvLine(line);
    final row = <String, String>{
      for (var index = 0; index < header.length; index += 1)
        header[index]: index < values.length ? values[index] : '',
    };
    if (row['workload'] == workload) {
      rows.add(row);
    }
  }
  return rows;
}

Set<int> _repeatNumbers(List<Map<String, String>> rows) {
  return rows
      .map((row) => int.tryParse(row['repeat'] ?? ''))
      .whereType<int>()
      .toSet();
}

void _validateSummaryHashes(
  List<Map<String, String>> rows, {
  required String side,
  required String targetLabel,
  required List<TerminalRenderPhase3GateFailure> failures,
}) {
  for (final row in rows) {
    if (row['hash_match'] == 'true') {
      continue;
    }
    failures.add(
      TerminalRenderPhase3GateFailure(
        code: 'correctness_hash_mismatch',
        message:
            '$side $targetLabel repeat ${row['repeat']} has '
            'summary hash_match=${row['hash_match']}',
        targetLabel: targetLabel,
        side: side,
        repeat: int.tryParse(row['repeat'] ?? ''),
      ),
    );
  }
}

void _validateRunArtifacts(
  Directory targetDirectory, {
  required String side,
  required String targetLabel,
  required String workload,
  required Set<int> repeatNumbers,
  required bool requirePhase3RenderMetrics,
  required List<TerminalRenderPhase3GateFailure> failures,
}) {
  for (final repeat in repeatNumbers) {
    final runDirectory = Directory(
      '${targetDirectory.path}/$workload/repeat_$repeat',
    );
    final correctness = File('${runDirectory.path}/correctness.json');
    if (!correctness.existsSync()) {
      failures.add(
        TerminalRenderPhase3GateFailure(
          code: 'correctness_missing',
          message: '$side correctness.json is missing: ${correctness.path}',
          targetLabel: targetLabel,
          side: side,
          repeat: repeat,
        ),
      );
    } else {
      try {
        final decoded = jsonDecode(correctness.readAsStringSync());
        if (decoded is! Map || decoded['hash_match'] != true) {
          failures.add(
            TerminalRenderPhase3GateFailure(
              code: 'correctness_hash_mismatch',
              message:
                  '$side $targetLabel/$workload/repeat_$repeat '
                  'correctness hash_match is not true',
              targetLabel: targetLabel,
              side: side,
              repeat: repeat,
            ),
          );
        }
      } on FormatException {
        failures.add(
          TerminalRenderPhase3GateFailure(
            code: 'correctness_invalid',
            message: '$side correctness.json is invalid: ${correctness.path}',
            targetLabel: targetLabel,
            side: side,
            repeat: repeat,
          ),
        );
      }
    }

    if (requirePhase3RenderMetrics) {
      _validateAfterRenderMetrics(
        File('${runDirectory.path}/flutter_render.ndjson'),
        targetLabel: targetLabel,
        repeat: repeat,
        failures: failures,
      );
    }
  }
}

void _validateAfterRenderMetrics(
  File renderFile, {
  required String targetLabel,
  required int repeat,
  required List<TerminalRenderPhase3GateFailure> failures,
}) {
  if (!renderFile.existsSync() || renderFile.lengthSync() == 0) {
    failures.add(
      TerminalRenderPhase3GateFailure(
        code: 'after_render_missing',
        message:
            'after flutter_render.ndjson is missing or empty: '
            '${renderFile.path}',
        targetLabel: targetLabel,
        side: 'after',
        repeat: repeat,
      ),
    );
    return;
  }
  const requiredMetrics = <String>{
    'rows_visited',
    'picture_draw_count',
    'debug_collection_enabled',
  };
  var eventIndex = 0;
  for (final line in renderFile.readAsLinesSync()) {
    if (line.trim().isEmpty) {
      continue;
    }
    eventIndex += 1;
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      decoded = null;
    }
    final event = decoded is Map ? decoded : null;
    final missing = event == null
        ? requiredMetrics.toList()
        : requiredMetrics
              .where((metric) => !event.containsKey(metric))
              .toList();
    if (missing.isEmpty) {
      continue;
    }
    failures.add(
      TerminalRenderPhase3GateFailure(
        code: 'after_render_metric_missing',
        message:
            '$targetLabel repeat $repeat render event $eventIndex '
            'is missing ${missing.join(', ')}',
        targetLabel: targetLabel,
        side: 'after',
        repeat: repeat,
      ),
    );
  }
  if (eventIndex == 0) {
    failures.add(
      TerminalRenderPhase3GateFailure(
        code: 'after_render_empty',
        message:
            'after flutter_render.ndjson has no events: '
            '${renderFile.path}',
        targetLabel: targetLabel,
        side: 'after',
        repeat: repeat,
      ),
    );
  }
}

double? _metricMedian(
  List<Map<String, String>> rows, {
  required String metric,
  required String side,
  required String targetLabel,
  required List<TerminalRenderPhase3GateFailure> failures,
}) {
  final values = <double>[];
  var hasMissingValue = false;
  var hasNonFiniteValue = false;
  for (final row in rows) {
    final value = double.tryParse(row[metric] ?? '');
    if (value == null) {
      hasMissingValue = true;
    } else if (!value.isFinite) {
      hasNonFiniteValue = true;
    } else {
      values.add(value);
    }
  }
  if (hasMissingValue || rows.isEmpty) {
    failures.add(
      TerminalRenderPhase3GateFailure(
        code: 'summary_metric_missing',
        message: '$side $targetLabel requires numeric $metric for every repeat',
        targetLabel: targetLabel,
        metric: metric,
        side: side,
      ),
    );
  }
  if (hasNonFiniteValue) {
    failures.add(
      TerminalRenderPhase3GateFailure(
        code: 'summary_metric_non_finite',
        message: '$side $targetLabel requires finite $metric for every repeat',
        targetLabel: targetLabel,
        metric: metric,
        side: side,
      ),
    );
  }
  if (hasMissingValue || hasNonFiniteValue || rows.isEmpty) {
    return null;
  }
  values.sort();
  final middle = values.length ~/ 2;
  if (values.length.isOdd) {
    return values[middle];
  }
  return (values[middle - 1] + values[middle]) / 2;
}

bool _sameStringSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

bool _sameIntSet(Set<int> left, Set<int> right) =>
    left.length == right.length && left.containsAll(right);

List<String> _sorted(Set<String> values) => values.toList()..sort();

List<int> _sortedInts(Set<int> values) => values.toList()..sort();

List<String> _parseCsvLine(String line) {
  final values = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;
  for (var index = 0; index < line.length; index += 1) {
    final character = line[index];
    if (character == '"') {
      if (inQuotes && index + 1 < line.length && line[index + 1] == '"') {
        buffer.write('"');
        index += 1;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (character == ',' && !inQuotes) {
      values.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(character);
    }
  }
  values.add(buffer.toString());
  return values;
}
