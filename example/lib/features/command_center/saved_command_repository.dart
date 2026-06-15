import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'command_history_privacy_filter.dart';

typedef SavedCommandDirectoryResolver = Future<Directory> Function();

class SavedCommandRepository {
  SavedCommandRepository({
    SavedCommandDirectoryResolver? directoryResolver,
    CommandHistoryPrivacyFilter privacyFilter =
        const CommandHistoryPrivacyFilter(),
  }) : _directoryResolver = directoryResolver ?? getApplicationSupportDirectory,
       _privacyFilter = privacyFilter;

  final SavedCommandDirectoryResolver _directoryResolver;
  final CommandHistoryPrivacyFilter _privacyFilter;

  Future<SavedCommandDocument> load() async {
    final file = await _savedCommandsFile();
    if (!await file.exists()) {
      return const SavedCommandDocument();
    }

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        throw const FormatException('Root value was not an object.');
      }
      return SavedCommandDocument.fromJson(
        decoded.map((key, value) => MapEntry(key, value as Object?)),
        privacyFilter: _privacyFilter,
      );
    } on Object {
      await _quarantineCorruptFile(file);
      const repaired = SavedCommandDocument();
      await save(repaired);
      return repaired;
    }
  }

  Future<void> save(SavedCommandDocument document) async {
    final file = await _savedCommandsFile();
    await file.parent.create(recursive: true);
    final filteredDocument = document.trimmed(privacyFilter: _privacyFilter);
    await file.writeAsString(jsonEncode(filteredDocument.toJson()));
  }

  Future<void> clear() async {
    final file = await _savedCommandsFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<File> _savedCommandsFile() async {
    final directory = await _directoryResolver();
    return File('${directory.path}/ianvs_saved_commands.json');
  }

  Future<void> _quarantineCorruptFile(File file) async {
    final quarantinedPath =
        '${file.path}.corrupt.${DateTime.now().millisecondsSinceEpoch}';
    await file.rename(quarantinedPath);
  }
}

class SavedCommandDocument {
  const SavedCommandDocument({
    this.limit = _defaultSavedCommandLimit,
    this.entries = const <SavedCommandEntry>[],
  });

  static const schemaVersion = 1;

  final int limit;
  final List<SavedCommandEntry> entries;

  static SavedCommandDocument fromJson(
    Map<Object?, Object?> json, {
    CommandHistoryPrivacyFilter privacyFilter =
        const CommandHistoryPrivacyFilter(),
  }) {
    final entries = _objectList(
      json['entries'],
    ).map(SavedCommandEntry.fromJson).nonNulls.toList(growable: false);
    return SavedCommandDocument(
      limit: _limitFromJson(json['limit']),
      entries: entries,
    ).trimmed(privacyFilter: privacyFilter);
  }

  SavedCommandDocument trimmed({
    CommandHistoryPrivacyFilter privacyFilter =
        const CommandHistoryPrivacyFilter(),
  }) {
    final normalized =
        entries
            .map(_normalizedEntry)
            .nonNulls
            .where(
              (entry) => privacyFilter.evaluateCommand(entry.command).allowed,
            )
            .toList(growable: false)
          ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    final seenIds = <String>{};
    final nextEntries = <SavedCommandEntry>[];
    for (final entry in normalized) {
      if (!seenIds.add(entry.id)) {
        continue;
      }
      nextEntries.add(entry);
      if (nextEntries.length >= _effectiveLimit(limit)) {
        break;
      }
    }
    return SavedCommandDocument(limit: limit, entries: nextEntries);
  }

  SavedCommandDocument markUsed(String id, DateTime usedAt) {
    final normalizedId = _trimmedStringOrNull(id);
    if (normalizedId == null) {
      return this;
    }
    var changed = false;
    final nextEntries = <SavedCommandEntry>[];
    for (final entry in entries) {
      if (entry.id == normalizedId) {
        changed = true;
        nextEntries.add(_entryMarkedUsed(entry, usedAt));
      } else {
        nextEntries.add(entry);
      }
    }
    return changed
        ? SavedCommandDocument(limit: limit, entries: nextEntries)
        : this;
  }

  Map<String, Object?> toJson() {
    final document = trimmed();
    return {
      'schemaVersion': schemaVersion,
      'limit': _effectiveLimit(document.limit),
      'entries': document.entries.map((entry) => entry.toJson()).toList(),
    };
  }
}

class SavedCommandEntry {
  const SavedCommandEntry({
    required this.id,
    required this.title,
    required this.command,
    required this.createdAt,
    required this.updatedAt,
    this.cwd,
    this.tags = const <String>[],
    this.useCount = 0,
    this.lastUsedAt,
  });

  final String id;
  final String title;
  final String command;
  final String? cwd;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int useCount;
  final DateTime? lastUsedAt;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'title': title,
      'command': command,
      'cwd': cwd,
      'tags': tags,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'useCount': useCount,
      'lastUsedAt': lastUsedAt?.toIso8601String(),
    };
  }

  static SavedCommandEntry? fromJson(Map<Object?, Object?> json) {
    final id = _trimmedStringOrNull(json['id']);
    final command = _trimmedStringOrNull(json['command']);
    final createdAt = _dateTimeOrNull(json['createdAt']);
    final updatedAt = _dateTimeOrNull(json['updatedAt']);
    if (id == null ||
        command == null ||
        createdAt == null ||
        updatedAt == null) {
      return null;
    }
    return SavedCommandEntry(
      id: id,
      title: _trimmedStringOrNull(json['title']) ?? command,
      command: command,
      cwd: _trimmedStringOrNull(json['cwd']),
      tags: _stringList(json['tags']),
      createdAt: createdAt,
      updatedAt: updatedAt,
      useCount: _nonNegativeIntOrZero(json['useCount']),
      lastUsedAt: _dateTimeOrNull(json['lastUsedAt']),
    );
  }
}

SavedCommandEntry _entryMarkedUsed(SavedCommandEntry entry, DateTime usedAt) {
  return SavedCommandEntry(
    id: entry.id,
    title: entry.title,
    command: entry.command,
    cwd: entry.cwd,
    tags: entry.tags,
    createdAt: entry.createdAt,
    updatedAt: entry.updatedAt,
    useCount: entry.useCount < 0 ? 1 : entry.useCount + 1,
    lastUsedAt: usedAt,
  );
}

const _defaultSavedCommandLimit = 200;

SavedCommandEntry? _normalizedEntry(SavedCommandEntry entry) {
  final id = _trimmedStringOrNull(entry.id);
  final command = _trimmedStringOrNull(entry.command);
  if (id == null || command == null) {
    return null;
  }
  return SavedCommandEntry(
    id: id,
    title: _trimmedStringOrNull(entry.title) ?? command,
    command: command,
    cwd: _trimmedStringOrNull(entry.cwd),
    tags: _normalizedTags(entry.tags),
    createdAt: entry.createdAt,
    updatedAt: entry.updatedAt,
    useCount: entry.useCount < 0 ? 0 : entry.useCount,
    lastUsedAt: entry.lastUsedAt,
  );
}

int _effectiveLimit(int limit) {
  return limit > 0 ? limit : _defaultSavedCommandLimit;
}

int _limitFromJson(Object? value) {
  final limit = _wholeIntOrNull(value);
  return limit == null || limit <= 0 ? _defaultSavedCommandLimit : limit;
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

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return _normalizedTags([
    for (final item in value)
      if (item is String) item,
  ]);
}

List<String> _normalizedTags(Iterable<String> tags) {
  final seen = <String>{};
  final normalized = <String>[];
  for (final tag in tags) {
    final trimmed = tag.trim();
    if (trimmed.isEmpty || !seen.add(trimmed)) {
      continue;
    }
    normalized.add(trimmed);
  }
  return List<String>.unmodifiable(normalized);
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

int _nonNegativeIntOrZero(Object? value) {
  final parsed = _wholeIntOrNull(value);
  if (parsed == null || parsed < 0) {
    return 0;
  }
  return parsed;
}

DateTime? _dateTimeOrNull(Object? value) {
  if (value is! String) {
    return null;
  }
  return DateTime.tryParse(value);
}
