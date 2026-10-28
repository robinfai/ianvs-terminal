import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../platform/local_json_file.dart';
import '../../startup/app_environment.dart';

final terminalAiHistoryRepositoryProvider =
    Provider<TerminalAiHistoryRepository>(
      (_) => LocalTerminalAiHistoryRepository(),
    );

abstract interface class TerminalAiHistoryRepository {
  Future<List<Map<String, Object?>>> load();
  Future<void> save(
    String id,
    Map<String, Object?> document, {
    Map<String, Object?>? previous,
  });
}

/// Content-only local history. No model credentials, executable approvals or
/// process handles are serialized. Atomic replacement preserves the last save.
class LocalTerminalAiHistoryRepository implements TerminalAiHistoryRepository {
  LocalTerminalAiHistoryRepository({Future<Directory> Function()? directory})
    : _directory = directory ?? _defaultDirectory;
  static Future<Directory> _defaultDirectory() async => AppEnvironment.current
      .supportDirectory(await getApplicationSupportDirectory());
  final Future<Directory> Function() _directory;
  Future<List<Map<String, Object?>>>? _startupHistory;
  // Coordinate bindings and provider scopes within this application process.
  static Future<void> _writes = Future.value();
  static const int maxDocumentBytes = 16 * 1024 * 1024;
  Future<Directory> _root() async =>
      Directory('${(await _directory()).path}/ai-history');

  @override
  Future<List<Map<String, Object?>>> load() => _startupHistory ??= _load();

  Future<List<Map<String, Object?>>> _load() async {
    final root = await _root();
    if (!await root.exists()) return [];
    final files = await root
        .list()
        .where((f) => f is File && f.path.endsWith('.json'))
        .cast<File>()
        .toList();
    final modified = <String, DateTime>{};
    for (final file in files) {
      modified[file.path] = (await file.stat()).modified;
    }
    files.sort((a, b) {
      final recent = modified[b.path]!.compareTo(modified[a.path]!);
      return recent == 0 ? b.path.compareTo(a.path) : recent;
    });
    final result = <Map<String, Object?>>[];
    var bytes = 0;
    for (final file in files) {
      if (result.length == 64) break;
      final length = await file.length();
      if (length > maxDocumentBytes) continue;
      try {
        final data = decodeJsonObject(
          await file.readAsString(),
          documentName: 'AI history',
        );
        if (data['schema'] == 1 && data['id'] is String) {
          if (bytes + length > 64 * 1024 * 1024) continue;
          bytes += length;
          result.add(data);
        }
      } on FormatException {
        // Preserve corrupt/unknown documents for recovery; never overwrite them.
      }
    }
    return result;
  }

  @override
  Future<void> save(
    String id,
    Map<String, Object?> document, {
    Map<String, Object?>? previous,
  }) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,160}$').hasMatch(id)) {
      return Future.error(ArgumentError('Invalid history identity'));
    }
    final write = _writes.then((_) async {
      final file = File('${(await _root()).path}/$id.json');
      var merged = document;
      if (previous != null && await file.exists()) {
        final latest = decodeJsonObject(
          await file.readAsString(),
          documentName: 'AI history',
        );
        // A restored view owns only its changes, not another session's newer
        // anchor, draft or folds. Serialize read/merge/replace as one operation.
        merged = {
          ...latest,
          for (final entry in document.entries)
            if (jsonEncode(previous[entry.key]) != jsonEncode(entry.value))
              entry.key: entry.key == 'nativeView'
                  ? _mergeView(
                      latest[entry.key],
                      previous[entry.key],
                      entry.value,
                    )
                  : entry.key == 'expanded'
                  ? _mergeSet(
                      latest[entry.key],
                      previous[entry.key],
                      entry.value,
                    )
                  : entry.value,
        };
      }
      final data = jsonEncode(merged);
      if (utf8.encode(data).length > maxDocumentBytes) {
        throw StateError('AI history exceeds its storage budget');
      }
      await writeStringAtomically(file, data);
    });
    _writes = write.catchError((Object _, StackTrace _) {});
    return write;
  }

  static List<String> _mergeSet(
    Object? latest,
    Object? previous,
    Object? current,
  ) {
    Set<String> values(Object? value) =>
        (value is List ? value : const <Object?>[]).whereType<String>().toSet();
    final before = values(previous);
    final after = values(current);
    return (values(latest)
          ..removeAll(before.difference(after))
          ..addAll(after.difference(before)))
        .toList();
  }

  static Map<String, Object?> _mergeView(
    Object? latest,
    Object? previous,
    Object? current,
  ) {
    final old = latest is Map ? latest : const <Object?, Object?>{};
    final before = previous is Map ? previous : const <Object?, Object?>{};
    final after = current is Map ? current : const <Object?, Object?>{};
    return {
      for (final name in ['collapsed', 'expanded'])
        name: _mergeSet(old[name], before[name], after[name]),
    };
  }
}
