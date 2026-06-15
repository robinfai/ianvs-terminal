import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'session_command_history_buffer.dart';

typedef GlobalCommandHistoryDirectoryResolver = Future<Directory> Function();

class GlobalCommandHistoryRepository {
  GlobalCommandHistoryRepository({
    GlobalCommandHistoryDirectoryResolver? directoryResolver,
  }) : _directoryResolver = directoryResolver ?? getApplicationSupportDirectory;

  final GlobalCommandHistoryDirectoryResolver _directoryResolver;

  Future<GlobalCommandHistoryDocument> load() async {
    final file = await _historyFile();
    if (!await file.exists()) {
      return const GlobalCommandHistoryDocument();
    }

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        throw const FormatException('Root value was not an object.');
      }
      return GlobalCommandHistoryDocument.fromJson(
        decoded.map((key, value) => MapEntry(key, value as Object?)),
      );
    } on Object {
      await _quarantineCorruptFile(file);
      const repaired = GlobalCommandHistoryDocument();
      await save(repaired);
      return repaired;
    }
  }

  Future<void> save(GlobalCommandHistoryDocument document) async {
    final file = await _historyFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(document.trimmed().toJson()));
  }

  Future<File> _historyFile() async {
    final directory = await _directoryResolver();
    return File('${directory.path}/ianvs_command_history.json');
  }

  Future<void> _quarantineCorruptFile(File file) async {
    final quarantinedPath =
        '${file.path}.corrupt.${DateTime.now().millisecondsSinceEpoch}';
    await file.rename(quarantinedPath);
  }
}

class GlobalCommandHistoryDocument {
  const GlobalCommandHistoryDocument({
    this.limit = _defaultGlobalCommandHistoryLimit,
    this.entries = const <GlobalCommandHistoryEntry>[],
  });

  static const schemaVersion = 1;

  final int limit;
  final List<GlobalCommandHistoryEntry> entries;

  static GlobalCommandHistoryDocument fromJson(Map<Object?, Object?> json) {
    final entries = _objectList(
      json['entries'],
    ).map(GlobalCommandHistoryEntry.fromJson).nonNulls.toList(growable: false);
    return GlobalCommandHistoryDocument(
      limit: _limitFromJson(json['limit']),
      entries: entries,
    ).trimmed();
  }

  Map<String, Object?> toJson() {
    final trimmedDocument = trimmed();
    return {
      'schemaVersion': schemaVersion,
      'limit': _effectiveLimit(trimmedDocument.limit),
      'entries': trimmedDocument.entries
          .map((entry) => entry.toJson())
          .toList(growable: false),
    };
  }

  GlobalCommandHistoryDocument trimmed() {
    final normalized =
        entries.map(_normalizedEntry).nonNulls.toList(growable: false)
          ..sort((left, right) => right.finishedAt.compareTo(left.finishedAt));
    final seenKeys = <String>{};
    final nextEntries = <GlobalCommandHistoryEntry>[];
    for (final entry in normalized) {
      if (!seenKeys.add(_historyKey(entry.command, entry.cwd))) {
        continue;
      }
      nextEntries.add(entry);
      if (nextEntries.length >= _effectiveLimit(limit)) {
        break;
      }
    }
    return GlobalCommandHistoryDocument(limit: limit, entries: nextEntries);
  }

  GlobalCommandHistoryDocument mergeSessionEntries(
    Iterable<SessionCommandHistoryEntry> sessionEntries, {
    int? limit,
  }) {
    final mergedEntries = <GlobalCommandHistoryEntry>[
      ...sessionEntries.map(GlobalCommandHistoryEntry.fromSessionEntry),
      ...entries,
    ];
    return GlobalCommandHistoryDocument(
      limit: limit ?? this.limit,
      entries: mergedEntries,
    ).trimmed();
  }
}

class GlobalCommandHistoryEntry {
  const GlobalCommandHistoryEntry({
    required this.command,
    required this.finishedAt,
    this.cwd,
    this.exitCode,
  });

  factory GlobalCommandHistoryEntry.fromSessionEntry(
    SessionCommandHistoryEntry entry,
  ) {
    return GlobalCommandHistoryEntry(
      command: entry.command,
      cwd: entry.cwd,
      exitCode: entry.exitCode,
      finishedAt: entry.finishedAt,
    );
  }

  final String command;
  final String? cwd;
  final int? exitCode;
  final DateTime finishedAt;

  bool get succeeded => exitCode == 0;

  Map<String, Object?> toJson() {
    return {
      'command': command,
      'cwd': cwd,
      'exitCode': exitCode,
      'finishedAt': finishedAt.toIso8601String(),
    };
  }

  static GlobalCommandHistoryEntry? fromJson(Map<Object?, Object?> json) {
    final command = _trimmedStringOrNull(json['command']);
    final finishedAt = _dateTimeOrNull(json['finishedAt']);
    if (command == null || finishedAt == null) {
      return null;
    }
    return GlobalCommandHistoryEntry(
      command: command,
      cwd: _trimmedStringOrNull(json['cwd']),
      exitCode: _wholeIntOrNull(json['exitCode']),
      finishedAt: finishedAt,
    );
  }
}

const _defaultGlobalCommandHistoryLimit = 1000;

GlobalCommandHistoryEntry? _normalizedEntry(GlobalCommandHistoryEntry entry) {
  final command = _trimmedStringOrNull(entry.command);
  if (command == null) {
    return null;
  }
  return GlobalCommandHistoryEntry(
    command: command,
    cwd: _trimmedStringOrNull(entry.cwd),
    exitCode: entry.exitCode,
    finishedAt: entry.finishedAt,
  );
}

int _effectiveLimit(int limit) {
  return limit > 0 ? limit : _defaultGlobalCommandHistoryLimit;
}

int _limitFromJson(Object? value) {
  final limit = _wholeIntOrNull(value);
  return limit == null || limit <= 0
      ? _defaultGlobalCommandHistoryLimit
      : limit;
}

String _historyKey(String command, String? cwd) {
  return '$command\n${cwd ?? ''}';
}

List<Map<Object?, Object?>> _objectList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return [
    for (final item in value)
      if (item is Map) item.cast<Object?, Object?>(),
  ];
}

String? _trimmedStringOrNull(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _wholeIntOrNull(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is double && value.isFinite && value == value.truncateToDouble()) {
    return value.toInt();
  }
  return null;
}

DateTime? _dateTimeOrNull(Object? value) {
  if (value is! String) {
    return null;
  }
  return DateTime.tryParse(value);
}
