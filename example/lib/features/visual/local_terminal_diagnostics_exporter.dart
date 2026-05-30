import 'dart:convert';
import 'dart:io';

import '../terminal/terminal.dart' as terminal;

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

    await directory.create(recursive: true);
    final target = Directory('${directory.path}/${_safeBasename(basename)}');
    await target.create(recursive: true);

    final manifest = <String, Object?>{
      'schema_version': 'terminal-diagnostics-bundle-v1',
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'session_count': exports.length,
      'privacy': const <String, Object?>{
        'content_included': false,
        'scrollback_included': false,
        'env_included': false,
        'raw_command_included': false,
        'raw_cwd_included': false,
      },
      'sessions': exports.map((export) => export.manifest).toList(),
    };

    await _writeJson(File('${target.path}/manifest.json'), manifest);
    await _writeJson(
      File('${target.path}/sessions.json'),
      exports
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
      exports.expand(
        (export) => export.resourceSamples.map(
          (sample) => _withSessionId(sample, export.manifest),
        ),
      ),
    );
    await _writeJsonLines(
      File('${target.path}/terminal_stats.jsonl'),
      exports.map(
        (export) => <String, Object?>{
          'session_id': export.manifest['session_id'],
          'terminal_stats': export.terminalStats,
        },
      ),
    );
    await _writeJsonLines(
      File('${target.path}/events.jsonl'),
      exports.expand(
        (export) => export.events.map(
          (event) => _withSessionId(event, export.manifest),
        ),
      ),
    );
    await File(
      '${target.path}/summary.md',
    ).writeAsString(_summaryMarkdown(exports));

    return target;
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
    for (final entry in value) {
      if (entry is! String) {
        continue;
      }
      final text = entry.trim();
      if (text.isNotEmpty) {
        strings.add(text);
      }
    }
    return strings;
  }

  static String _safeBasename(String basename) {
    final safe = basename
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp('-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (safe.isEmpty || RegExp(r'^\.+$').hasMatch(safe)) {
      return 'diagnostics-${DateTime.now().millisecondsSinceEpoch}';
    }
    return safe;
  }
}
