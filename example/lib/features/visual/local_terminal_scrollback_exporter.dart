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
    final file = File('${directory.path}/$basename.${export.fileExtension()}');
    await file.writeAsString(
      export.encode(includeMetadata: policy.includeMetadata),
    );
    return file;
  }
}
