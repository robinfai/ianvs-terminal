import 'dart:convert';
import 'dart:io';

import '../../platform/local_file_collision.dart';
import '../terminal/terminal.dart' as terminal;

const _maxSafeBasenameLength = 120;
const _maxDiagnosticsResourceSamples = 60;
const _maxDiagnosticsEvents = 200;
const _maxDiagnosticsSummaryEntries = 32;
const _maxDiagnosticsSummaryNestedEntries = 32;
const _maxDiagnosticsSummaryListEntries = 20;
const _maxDiagnosticsSummaryScanMultiplier = 4;
const _maxDiagnosticsSummaryStringLength = 4096;
const _maxDiagnosticsSummaryListStringLength = 512;

class LocalTerminalDiagnosticsExporter {
  const LocalTerminalDiagnosticsExporter._();

  static Future<Directory> write({
    required Directory directory,
    required String basename,
    required List<terminal.TerminalDiagnosticsExport> exports,
  }) async {
    if (exports.isEmpty) {
      throw StateError('At least one diagnostics export is required.');
    }
    final boundedExports = exports.map(_boundedExport).toList(growable: false);

    await directory.create(recursive: true);
    final target = await nextAvailableDirectory(
      Directory('${directory.path}/${_safeBasename(basename)}'),
    );
    await target.create(recursive: true);

    final manifest = <String, Object?>{
      'schema_version': 'terminal-diagnostics-bundle-v1',
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'session_count': boundedExports.length,
      'privacy': const <String, Object?>{
        'content_included': false,
        'scrollback_included': false,
        'env_included': false,
        'raw_command_included': false,
        'raw_cwd_included': false,
      },
      'sessions': boundedExports.map((export) => export.manifest).toList(),
    };

    await _writeJson(File('${target.path}/manifest.json'), manifest);
    await _writeJson(
      File('${target.path}/sessions.json'),
      boundedExports
          .map(
            (export) => <String, Object?>{
              'manifest': export.manifest,
              'summary': export.summary,
            },
          )
          .toList(),
    );
    await _writeJsonLines(
      File('${target.path}/resource_samples.jsonl'),
      boundedExports.expand(
        (export) => export.resourceSamples.map(
          (sample) => _withSessionId(sample, export.manifest),
        ),
      ),
    );
    await _writeJsonLines(
      File('${target.path}/terminal_stats.jsonl'),
      boundedExports.map(
        (export) => <String, Object?>{
          'session_id': export.manifest['session_id'],
          'terminal_stats': export.terminalStats,
        },
      ),
    );
    await _writeJsonLines(
      File('${target.path}/events.jsonl'),
      boundedExports.expand(
        (export) => export.events.map(
          (event) => _withSessionId(event, export.manifest),
        ),
      ),
    );
    await File(
      '${target.path}/summary.md',
    ).writeAsString(_summaryMarkdown(boundedExports));

    return target;
  }

  static terminal.TerminalDiagnosticsExport _boundedExport(
    terminal.TerminalDiagnosticsExport export,
  ) {
    return terminal.TerminalDiagnosticsExport(
      manifest: _boundedJsonMap(export.manifest),
      resourceSamples: export.resourceSamples
          .take(_maxDiagnosticsResourceSamples)
          .map(_boundedJsonMap)
          .toList(growable: false),
      terminalStats: _boundedJsonMap(export.terminalStats),
      events: export.events
          .take(_maxDiagnosticsEvents)
          .map(_boundedJsonMap)
          .toList(growable: false),
      summary: _boundedSummary(export.summary),
    );
  }

  static Future<void> _writeJson(File file, Object? value) {
    return file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(value),
    );
  }

  static Future<void> _writeJsonLines(
    File file,
    Iterable<Map<String, Object?>> values,
  ) {
    final buffer = StringBuffer();
    for (final value in values) {
      buffer.writeln(jsonEncode(value));
    }
    return file.writeAsString(buffer.toString());
  }

  static Map<String, Object?> _withSessionId(
    Map<String, Object?> value,
    Map<String, Object?> manifest,
  ) {
    if (value.containsKey('session_id') || value.containsKey('sessionId')) {
      return value;
    }
    return <String, Object?>{'session_id': manifest['session_id'], ...value};
  }

  static String _summaryMarkdown(
    List<terminal.TerminalDiagnosticsExport> exports,
  ) {
    final buffer = StringBuffer()
      ..writeln('# Terminal Diagnostics Summary')
      ..writeln()
      ..writeln('## 结论')
      ..writeln();
    for (final export in exports) {
      buffer.writeln(
        '- session ${export.manifest['session_id'] ?? 'unknown'}: ${export.conclusion ?? 'insufficient-evidence'}',
      );
    }

    buffer
      ..writeln()
      ..writeln('## 证据摘要')
      ..writeln();
    for (final export in exports) {
      final evidence = _stringList(export.summary['evidence']);
      if (evidence.isEmpty) {
        buffer.writeln(
          '- session ${export.manifest['session_id'] ?? 'unknown'}: no evidence summary provided',
        );
        continue;
      }
      for (final item in evidence) {
        buffer.writeln(
          '- session ${export.manifest['session_id'] ?? 'unknown'}: $item',
        );
      }
    }

    buffer
      ..writeln()
      ..writeln('## 归因分数')
      ..writeln();
    for (final export in exports) {
      final scores = export.summary['attribution_scores'];
      buffer.writeln(
        '- session ${export.manifest['session_id'] ?? 'unknown'}: ${scores is Map ? jsonEncode(scores) : '{}'}',
      );
    }

    buffer
      ..writeln()
      ..writeln('## 隐私处理')
      ..writeln()
      ..writeln(
        '- 默认不导出 scrollback、env、完整 command line、原始 cwd、username、hostname。',
      )
      ..writeln('- 命令和路径只允许摘要、计数、类别或 salted hash 进入基础包。');

    buffer
      ..writeln()
      ..writeln('## 建议下一步')
      ..writeln();
    for (final export in exports) {
      final nextSteps = _stringList(export.summary['next_steps']);
      if (nextSteps.isEmpty) {
        buffer.writeln(
          '- session ${export.manifest['session_id'] ?? 'unknown'}: reproduce while active for at least two samples, then export again.',
        );
        continue;
      }
      for (final item in nextSteps) {
        buffer.writeln(
          '- session ${export.manifest['session_id'] ?? 'unknown'}: $item',
        );
      }
    }

    return buffer.toString();
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) {
      return const <String>[];
    }
    final strings = <String>[];
    for (final entry in value.take(
      _maxDiagnosticsSummaryEntriesToScan(_maxDiagnosticsSummaryListEntries),
    )) {
      if (strings.length >= _maxDiagnosticsSummaryListEntries) {
        break;
      }
      final text = _boundedNonEmptyTrimmedString(
        entry,
        maxLength: _maxDiagnosticsSummaryListStringLength,
      );
      if (text != null) {
        strings.add(text);
      }
    }
    return strings;
  }

  static Map<String, Object?> _boundedSummary(Map<String, Object?> value) {
    final result = <String, Object?>{};
    for (final entry in value.entries.take(
      _maxDiagnosticsSummaryEntriesToScan(_maxDiagnosticsSummaryEntries),
    )) {
      if (result.length >= _maxDiagnosticsSummaryEntries) {
        break;
      }
      final boundedValue = switch (entry.key) {
        'evidence' || 'next_steps' => _stringList(entry.value),
        _ => _boundedJsonValue(entry.value, depth: 2),
      };
      if (boundedValue != null) {
        result[entry.key] = boundedValue;
      }
    }
    return result;
  }

  static Map<String, Object?> _boundedJsonMap(Map<String, Object?> value) {
    final result = <String, Object?>{};
    for (final entry in value.entries.take(
      _maxDiagnosticsSummaryEntriesToScan(_maxDiagnosticsSummaryNestedEntries),
    )) {
      if (result.length >= _maxDiagnosticsSummaryNestedEntries) {
        break;
      }
      final boundedValue = _boundedJsonValue(entry.value, depth: 2);
      if (boundedValue != null) {
        result[entry.key] = boundedValue;
      }
    }
    return result;
  }

  static Object? _boundedJsonValue(Object? value, {required int depth}) {
    if (value == null || value is bool) {
      return value;
    }
    if (value is num) {
      return value.isFinite ? value : null;
    }
    final text = _boundedNonEmptyTrimmedString(
      value,
      maxLength: _maxDiagnosticsSummaryStringLength,
    );
    if (text != null) {
      return text;
    }
    if (depth <= 0) {
      return null;
    }
    if (value is List) {
      final result = <Object?>[];
      for (final entry in value.take(
        _maxDiagnosticsSummaryEntriesToScan(_maxDiagnosticsSummaryListEntries),
      )) {
        if (result.length >= _maxDiagnosticsSummaryListEntries) {
          break;
        }
        final boundedValue = _boundedJsonValue(entry, depth: depth - 1);
        if (boundedValue != null) {
          result.add(boundedValue);
        }
      }
      return result;
    }
    if (value is Map) {
      final result = <String, Object?>{};
      for (final entry in value.entries.take(
        _maxDiagnosticsSummaryEntriesToScan(
          _maxDiagnosticsSummaryNestedEntries,
        ),
      )) {
        if (result.length >= _maxDiagnosticsSummaryNestedEntries) {
          break;
        }
        final key = _boundedNonEmptyTrimmedString(
          entry.key,
          maxLength: _maxDiagnosticsSummaryListStringLength,
        );
        if (key == null) {
          continue;
        }
        final boundedValue = _boundedJsonValue(entry.value, depth: depth - 1);
        if (boundedValue != null) {
          result[key] = boundedValue;
        }
      }
      return result;
    }
    return null;
  }

  static int _maxDiagnosticsSummaryEntriesToScan(int maxEntries) {
    return maxEntries * _maxDiagnosticsSummaryScanMultiplier;
  }

  static String? _boundedNonEmptyTrimmedString(
    Object? value, {
    required int maxLength,
  }) {
    final text = value is String ? value.trim() : null;
    if (text == null || text.isEmpty) {
      return null;
    }
    if (text.length <= maxLength) {
      return text;
    }
    return text.substring(0, maxLength);
  }

  static String _safeBasename(String basename) {
    final safe = basename
        .replaceAll(RegExp('[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp('-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (safe.isEmpty || RegExp(r'^\.+$').hasMatch(safe)) {
      return _fallbackBasename();
    }
    if (safe.length <= _maxSafeBasenameLength) {
      return safe;
    }
    final truncated = safe
        .substring(0, _maxSafeBasenameLength)
        .replaceAll(RegExp(r'[._-]+$'), '');
    if (truncated.isEmpty || RegExp(r'^\.+$').hasMatch(truncated)) {
      return _fallbackBasename();
    }
    return truncated;
  }

  static String _fallbackBasename() {
    return 'diagnostics-${DateTime.now().millisecondsSinceEpoch}';
  }
}
