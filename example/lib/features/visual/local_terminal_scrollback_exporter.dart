import 'dart:convert';
import 'dart:io';

import 'local_terminal_visual_models.dart';

class LocalTerminalScrollbackExport {
  const LocalTerminalScrollbackExport({
    required this.format,
    required this.content,
    this.metadata = const <String, Object?>{},
  });

  final LocalTerminalExportFormat format;
  final String content;
  final Map<String, Object?> metadata;

  String fileExtension() {
    return switch (format) {
      LocalTerminalExportFormat.plainText => 'txt',
      LocalTerminalExportFormat.ansiText => 'ansi',
      LocalTerminalExportFormat.json => 'json',
    };
  }

  String encode({required bool includeMetadata}) {
    if (format != LocalTerminalExportFormat.json) {
      return content;
    }

    return jsonEncode({
      if (includeMetadata) 'metadata': metadata,
      'content': content,
    });
  }
}

class LocalTerminalScrollbackExporter {
  const LocalTerminalScrollbackExporter._();

  static Future<File> write({
    required Directory directory,
    required String basename,
    required LocalTerminalScrollbackExport export,
    required LocalTerminalScrollbackExportPolicy policy,
  }) async {
    if (!policy.canExport(export.format)) {
      throw StateError(
        'Scrollback export is disabled for ${export.format.name}',
      );
    }

    await directory.create(recursive: true);
    final safeBasename = _safeBasename(basename);
    final file = File(
      '${directory.path}/$safeBasename.${export.fileExtension()}',
    );
    await file.writeAsString(
      export.encode(includeMetadata: policy.includeMetadata),
    );
    return file;
  }

  static String _safeBasename(String basename) {
    final safe = basename
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp('-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (safe.isEmpty) {
      return 'scrollback-${DateTime.now().millisecondsSinceEpoch}';
    }
    return safe;
  }
}
