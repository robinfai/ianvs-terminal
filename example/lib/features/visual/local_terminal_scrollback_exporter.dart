import 'dart:convert';
import 'dart:io';

import '../../platform/local_file_collision.dart';
import 'local_terminal_visual_models.dart';

const _maxSafeBasenameLength = 120;
const _maxMetadataEntries = 32;
const _maxMetadataNestedEntries = 32;
const _maxMetadataListEntries = 20;
const _maxMetadataScanMultiplier = 4;
const _maxMetadataKeyLength = 128;
const _maxMetadataStringLength = 4096;
const _invalidJsonValue = Object();

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
      if (includeMetadata) 'metadata': _boundedMetadata(metadata),
      'content': content,
    });
  }

  static Map<String, Object?> _boundedMetadata(Map<String, Object?> value) {
    final result = <String, Object?>{};
    for (final entry in value.entries.take(
      _maxMetadataEntriesToScan(_maxMetadataEntries),
    )) {
      if (result.length >= _maxMetadataEntries) {
        break;
      }
      final key = _boundedNonEmptyTrimmedString(
        entry.key,
        maxLength: _maxMetadataKeyLength,
      );
      if (key == null) {
        continue;
      }
      final boundedValue = _boundedJsonValue(entry.value, depth: 2);
      if (!identical(boundedValue, _invalidJsonValue)) {
        result[key] = boundedValue;
      }
    }
    return result;
  }

  static Object? _boundedJsonValue(Object? value, {required int depth}) {
    if (value == null || value is bool) {
      return value;
    }
    if (value is num) {
      return value.isFinite ? value : _invalidJsonValue;
    }
    final text = _boundedNonEmptyTrimmedString(
      value,
      maxLength: _maxMetadataStringLength,
    );
    if (text != null) {
      return text;
    }
    if (depth <= 0) {
      return _invalidJsonValue;
    }
    if (value is List) {
      final result = <Object?>[];
      for (final entry in value.take(
        _maxMetadataEntriesToScan(_maxMetadataListEntries),
      )) {
        if (result.length >= _maxMetadataListEntries) {
          break;
        }
        final boundedValue = _boundedJsonValue(entry, depth: depth - 1);
        if (!identical(boundedValue, _invalidJsonValue)) {
          result.add(boundedValue);
        }
      }
      return result;
    }
    if (value is Map) {
      final result = <String, Object?>{};
      for (final entry in value.entries.take(
        _maxMetadataEntriesToScan(_maxMetadataNestedEntries),
      )) {
        if (result.length >= _maxMetadataNestedEntries) {
          break;
        }
        final key = _boundedNonEmptyTrimmedString(
          entry.key,
          maxLength: _maxMetadataKeyLength,
        );
        if (key == null) {
          continue;
        }
        final boundedValue = _boundedJsonValue(entry.value, depth: depth - 1);
        if (!identical(boundedValue, _invalidJsonValue)) {
          result[key] = boundedValue;
        }
      }
      return result;
    }
    return _invalidJsonValue;
  }

  static int _maxMetadataEntriesToScan(int maxEntries) {
    return maxEntries * _maxMetadataScanMultiplier;
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
    final file = await nextAvailableFile(
      File('${directory.path}/$safeBasename.${export.fileExtension()}'),
    );
    await file.writeAsString(
      export.encode(includeMetadata: policy.includeMetadata),
    );
    return file;
  }

  static String _safeBasename(String basename) {
    final safe = basename
        .replaceAll(RegExp('[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp('-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return _normalizeSafeBasename(safe);
  }

  static String _normalizeSafeBasename(String safe) {
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
    return 'scrollback-${DateTime.now().millisecondsSinceEpoch}';
  }
}
