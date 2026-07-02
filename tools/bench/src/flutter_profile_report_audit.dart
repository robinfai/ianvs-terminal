import 'dart:convert';
import 'dart:io';

final class FlutterProfileReportAudit {
  const FlutterProfileReportAudit({
    required this.requiredTargetCount,
    required this.requiredWorkloads,
    required this.requiredRepeats,
    this.readinessReportPath,
    this.runbookReportPath,
  });

  final int requiredTargetCount;
  final List<String> requiredWorkloads;
  final int requiredRepeats;
  final String? readinessReportPath;
  final String? runbookReportPath;

  FlutterProfileReportAuditResult audit({
    required List<Directory> inputDirectories,
    required Directory outputDirectory,
  }) {
    final rows = <Map<String, String>>[];
    final failures = <String>[];
    for (final directory in inputDirectories) {
      rows.addAll(_readSummaryRows(directory, failures));
    }

    final targetDevices = rows
        .map((row) => row['target_device'] ?? '')
        .where((target) => target.isNotEmpty)
        .toSet();
    if (targetDevices.length < requiredTargetCount) {
      failures.add(
        'requires at least $requiredTargetCount target devices, found ${targetDevices.length}',
      );
    }

    for (final target in targetDevices) {
      for (final workload in requiredWorkloads) {
        final matchingRows = rows
            .where((row) {
              return row['target_device'] == target &&
                  row['workload'] == workload;
            })
            .toList(growable: false);
        if (matchingRows.length < requiredRepeats) {
          failures.add(
            '$target/$workload requires $requiredRepeats repeats, found ${matchingRows.length}',
          );
        }
      }
    }

    for (final row in rows) {
      if (row['hash_match'] != 'true') {
        failures.add(
          '${row['target_device']}/${row['workload']}/repeat_${row['repeat']} has hash_match=${row['hash_match']}',
        );
      }
    }

    for (final directory in inputDirectories) {
      _validateRunArtifacts(directory, rows, failures);
    }

    final result = FlutterProfileReportAuditResult(
      passed: failures.isEmpty,
      targetCount: targetDevices.length,
      runCount: rows.length,
      failures: List<String>.unmodifiable(failures),
      rows: List<Map<String, String>>.unmodifiable(rows),
      inputDirectories: List<String>.unmodifiable(
        inputDirectories.map((directory) => directory.path),
      ),
      requiredTargetCount: requiredTargetCount,
      requiredWorkloads: List<String>.unmodifiable(requiredWorkloads),
      requiredRepeats: requiredRepeats,
      readinessReportPath: readinessReportPath,
      runbookReportPath: runbookReportPath,
    );
    _writeOutputs(outputDirectory, result);
    return result;
  }

  List<Map<String, String>> _readSummaryRows(
    Directory directory,
    List<String> failures,
  ) {
    final file = File('${directory.path}/summary.csv');
    if (!file.existsSync()) {
      failures.add('missing summary.csv: ${directory.path}');
      return const <Map<String, String>>[];
    }
    final lines = file
        .readAsLinesSync()
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
    if (lines.length < 2) {
      failures.add('summary.csv has no rows: ${directory.path}');
      return const <Map<String, String>>[];
    }
    final header = _parseCsvLine(lines.first);
    return lines
        .skip(1)
        .map((line) {
          final values = _parseCsvLine(line);
          return <String, String>{
            for (var index = 0; index < header.length; index += 1)
              header[index]: index < values.length ? values[index] : '',
            '_matrix_root': directory.path,
          };
        })
        .toList(growable: false);
  }

  void _validateRunArtifacts(
    Directory matrixRoot,
    List<Map<String, String>> rows,
    List<String> failures,
  ) {
    final rootRows = rows.where(
      (row) => row['_matrix_root'] == matrixRoot.path,
    );
    for (final row in rootRows) {
      final workload = row['workload'] ?? '';
      final repeat = row['repeat'] ?? '';
      final runDir = Directory('${matrixRoot.path}/$workload/repeat_$repeat');
      if (!runDir.existsSync()) {
        failures.add('missing run directory: ${runDir.path}');
        continue;
      }
      _requireFile(runDir, 'correctness.json', failures);
      _requireNonEmptyFile(runDir, 'flutter_frame_timing.ndjson', failures);
      _requireNonEmptyFile(runDir, 'flutter_render.ndjson', failures);
      final correctnessFile = File('${runDir.path}/correctness.json');
      if (correctnessFile.existsSync()) {
        final decoded = jsonDecode(correctnessFile.readAsStringSync());
        if (decoded is Map && decoded['hash_match'] != true) {
          failures.add('correctness hash mismatch: ${correctnessFile.path}');
        }
      }
    }
  }

  void _writeOutputs(
    Directory outputDirectory,
    FlutterProfileReportAuditResult result,
  ) {
    outputDirectory.createSync(recursive: true);
    _writeFormalSummary(outputDirectory, result.rows);
    File('${outputDirectory.path}/formal_profile_audit.json').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(result.toJson())}\n',
    );
    File(
      '${outputDirectory.path}/formal_profile_report.md',
    ).writeAsStringSync(_formalMarkdown(result));
    _writeManifest(outputDirectory, result);
  }
}

final class FlutterProfileReportAuditResult {
  const FlutterProfileReportAuditResult({
    required this.passed,
    required this.targetCount,
    required this.runCount,
    required this.failures,
    required this.rows,
    required this.inputDirectories,
    required this.requiredTargetCount,
    required this.requiredWorkloads,
    required this.requiredRepeats,
    required this.readinessReportPath,
    required this.runbookReportPath,
  });

  final bool passed;
  final int targetCount;
  final int runCount;
  final List<String> failures;
  final List<Map<String, String>> rows;
  final List<String> inputDirectories;
  final int requiredTargetCount;
  final List<String> requiredWorkloads;
  final int requiredRepeats;
  final String? readinessReportPath;
  final String? runbookReportPath;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema_version': 'ianvs-bench-formal-profile-audit-v1',
      'passed': passed,
      'target_count': targetCount,
      'run_count': runCount,
      'failures': failures,
    };
  }

  Map<String, Object?> toManifestJson(Directory outputDirectory) {
    return <String, Object?>{
      'schema_version': 'ianvs-bench-formal-profile-manifest-v1',
      'input_directories': inputDirectories,
      'required_target_count': requiredTargetCount,
      'required_workloads': requiredWorkloads,
      'required_repeats': requiredRepeats,
      if (readinessReportPath != null)
        'readiness_report': _fileReferenceJson(readinessReportPath!),
      if (runbookReportPath != null)
        'runbook_report': _fileReferenceJson(runbookReportPath!),
      'artifacts': const <String>[
        'formal_profile_summary.csv',
        'formal_profile_audit.json',
        'formal_profile_manifest.json',
        'formal_profile_report.md',
      ],
      'artifact_files': const <String>[
        'formal_profile_summary.csv',
        'formal_profile_audit.json',
        'formal_profile_manifest.json',
        'formal_profile_report.md',
      ].map((name) => _artifactFileJson(outputDirectory, name)).toList(),
    };
  }
}

void _writeManifest(
  Directory outputDirectory,
  FlutterProfileReportAuditResult result,
) {
  final file = File('${outputDirectory.path}/formal_profile_manifest.json');
  const encoder = JsonEncoder.withIndent('  ');
  var previousContent = '';
  for (var attempt = 0; attempt < 5; attempt += 1) {
    final content =
        '${encoder.convert(result.toManifestJson(outputDirectory))}\n';
    if (content == previousContent) {
      return;
    }
    file.writeAsStringSync(content);
    previousContent = content;
  }
}

Map<String, Object?> _artifactFileJson(Directory outputDirectory, String name) {
  final path = '${outputDirectory.path}/$name';
  return <String, Object?>{'name': name, ..._fileReferenceJson(path)};
}

Map<String, Object?> _fileReferenceJson(String path) {
  final file = File(path);
  return <String, Object?>{
    'path': path,
    'present': file.existsSync(),
    if (file.existsSync()) 'byte_size': file.lengthSync(),
  };
}

void _requireFile(Directory directory, String name, List<String> failures) {
  final file = File('${directory.path}/$name');
  if (!file.existsSync()) {
    failures.add('missing $name: ${directory.path}');
  }
}

void _requireNonEmptyFile(
  Directory directory,
  String name,
  List<String> failures,
) {
  final file = File('${directory.path}/$name');
  if (!file.existsSync()) {
    failures.add('missing $name: ${directory.path}');
    return;
  }
  if (file.lengthSync() == 0) {
    failures.add('empty $name: ${directory.path}');
  }
}

void _writeFormalSummary(
  Directory outputDirectory,
  List<Map<String, String>> rows,
) {
  if (rows.isEmpty) {
    File(
      '${outputDirectory.path}/formal_profile_summary.csv',
    ).writeAsStringSync('');
    return;
  }
  final header = rows.first.keys.where((key) => key != '_matrix_root').toList();
  final buffer = StringBuffer()..writeln(header.join(','));
  for (final row in rows) {
    buffer.writeln(header.map((key) => _csv(row[key] ?? '')).join(','));
  }
  File(
    '${outputDirectory.path}/formal_profile_summary.csv',
  ).writeAsStringSync(buffer.toString());
}

String _formalMarkdown(FlutterProfileReportAuditResult result) {
  final buffer = StringBuffer()
    ..writeln('# Formal Flutter Profile Report')
    ..writeln()
    ..writeln('- passed: `${result.passed}`')
    ..writeln('- target_count: `${result.targetCount}`')
    ..writeln('- run_count: `${result.runCount}`');
  if (result.rows.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Performance Summary')
      ..writeln()
      ..writeln(
        '| target | workload | repeats | hash matches | avg p95 total span | max p95 total span | missed vsync | row cache hit rate |',
      )
      ..writeln('|---|---|---:|---:|---:|---:|---:|---:|');
    for (final row in _performanceSummaryRows(result.rows)) {
      buffer.writeln(
        '| ${_markdownCell(row.target)} | ${_markdownCell(row.workload)} (${_markdownCell(row.wireFormat)}) | '
        '${row.repeatCount} | ${row.hashMatchCount} | '
        '${_formatDouble(row.p95TotalSpanAverage)} | '
        '${_formatDouble(row.p95TotalSpanMax)} | '
        '${row.missedVsyncCount} | ${_formatDouble(row.rowCacheHitRateAverage)} |',
      );
    }
  }
  if (result.failures.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Failures');
    for (final failure in result.failures) {
      buffer.writeln('- $failure');
    }
  }
  return buffer.toString();
}

List<_PerformanceSummaryRow> _performanceSummaryRows(
  List<Map<String, String>> rows,
) {
  final grouped = <String, List<Map<String, String>>>{};
  for (final row in rows) {
    final key =
        '${row['target_device'] ?? ''}\n${row['workload'] ?? ''}\n${row['wire_format'] ?? ''}';
    grouped.putIfAbsent(key, () => <Map<String, String>>[]).add(row);
  }
  final summaries = grouped.entries
      .map((entry) {
        final groupRows = entry.value;
        final p95TotalSpans = groupRows
            .map((row) => _doubleValue(row['p95_total_span_micros']))
            .nonNulls
            .toList(growable: false);
        final rowCacheHitRates = groupRows
            .map((row) => _doubleValue(row['row_cache_hit_rate']))
            .nonNulls
            .toList(growable: false);
        return _PerformanceSummaryRow(
          target: groupRows.first['target_device'] ?? '',
          workload: groupRows.first['workload'] ?? '',
          wireFormat: groupRows.first['wire_format'] ?? '',
          repeatCount: groupRows.length,
          hashMatchCount: groupRows
              .where((row) => row['hash_match'] == 'true')
              .length,
          p95TotalSpanAverage: _average(p95TotalSpans),
          p95TotalSpanMax: _max(p95TotalSpans),
          missedVsyncCount: groupRows.fold<int>(
            0,
            (sum, row) => sum + (_intValue(row['missed_vsync_count']) ?? 0),
          ),
          rowCacheHitRateAverage: _average(rowCacheHitRates),
        );
      })
      .toList(growable: false);
  return summaries..sort((left, right) {
    final targetCompare = left.target.compareTo(right.target);
    if (targetCompare != 0) {
      return targetCompare;
    }
    return left.workload.compareTo(right.workload);
  });
}

final class _PerformanceSummaryRow {
  const _PerformanceSummaryRow({
    required this.target,
    required this.workload,
    required this.wireFormat,
    required this.repeatCount,
    required this.hashMatchCount,
    required this.p95TotalSpanAverage,
    required this.p95TotalSpanMax,
    required this.missedVsyncCount,
    required this.rowCacheHitRateAverage,
  });

  final String target;
  final String workload;
  final String wireFormat;
  final int repeatCount;
  final int hashMatchCount;
  final double? p95TotalSpanAverage;
  final double? p95TotalSpanMax;
  final int missedVsyncCount;
  final double? rowCacheHitRateAverage;
}

double? _average(List<double> values) {
  if (values.isEmpty) {
    return null;
  }
  return values.reduce((left, right) => left + right) / values.length;
}

double? _max(List<double> values) {
  if (values.isEmpty) {
    return null;
  }
  return values.reduce((left, right) => left > right ? left : right);
}

double? _doubleValue(String? value) {
  final source = value?.trim() ?? '';
  if (source.isEmpty || source == 'N/A') {
    return null;
  }
  return double.tryParse(source);
}

int? _intValue(String? value) {
  final source = value?.trim() ?? '';
  if (source.isEmpty || source == 'N/A') {
    return null;
  }
  return int.tryParse(source);
}

String _formatDouble(double? value) {
  if (value == null) {
    return 'N/A';
  }
  return value.toStringAsFixed(4);
}

String _markdownCell(String value) => value.replaceAll('|', r'\|');

List<String> _parseCsvLine(String line) {
  final values = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;
  for (var index = 0; index < line.length; index += 1) {
    final char = line[index];
    if (char == '"') {
      if (inQuotes && index + 1 < line.length && line[index + 1] == '"') {
        buffer.write('"');
        index += 1;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }
    if (char == ',' && !inQuotes) {
      values.add(buffer.toString());
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  values.add(buffer.toString());
  return values;
}

String _csv(String value) {
  if (!value.contains(',') && !value.contains('"') && !value.contains('\n')) {
    return value;
  }
  return '"${value.replaceAll('"', '""')}"';
}
