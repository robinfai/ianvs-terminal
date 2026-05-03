import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'platform_paths.dart';

@immutable
class SavedCommandEntry {
  const SavedCommandEntry({
    required this.command,
    this.title = '',
    this.tags = const <String>[],
    this.cwdHint = '',
    this.targetKind = '',
    this.createdAt = '',
  });

  factory SavedCommandEntry.fromJson(Object? json) {
    final map = _objectMap(json);
    if (map == null) {
      return const SavedCommandEntry(command: '');
    }
    return SavedCommandEntry(
      command: _normalizedCommand(map['command']),
      title: _stringOrEmpty(map['title']),
      tags: _stringList(map['tags']),
      cwdHint: _stringOrEmpty(map['cwdHint']),
      targetKind: _stringOrEmpty(map['targetKind']),
      createdAt: _stringOrEmpty(map['createdAt']),
    );
  }

  final String command;
  final String title;
  final List<String> tags;
  final String cwdHint;
  final String targetKind;
  final String createdAt;

  bool get isValid => command.isNotEmpty;

  SavedCommandEntry copyWith({
    String? command,
    String? title,
    List<String>? tags,
    String? cwdHint,
    String? targetKind,
    String? createdAt,
  }) {
    return SavedCommandEntry(
      command: command ?? this.command,
      title: title ?? this.title,
      tags: tags ?? this.tags,
      cwdHint: cwdHint ?? this.cwdHint,
      targetKind: targetKind ?? this.targetKind,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'command': command,
      'title': title,
      'tags': tags,
      'cwdHint': cwdHint,
      'targetKind': targetKind,
      'createdAt': createdAt,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is SavedCommandEntry &&
        other.command == command &&
        other.title == title &&
        listEquals(other.tags, tags) &&
        other.cwdHint == cwdHint &&
        other.targetKind == targetKind &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(
    command,
    title,
    Object.hashAll(tags),
    cwdHint,
    targetKind,
    createdAt,
  );
}

class SavedCommandsState {
  const SavedCommandsState({
    this.version = 2,
    this.entries = const <SavedCommandEntry>[],
  });

  factory SavedCommandsState.fromJson(Object? json) {
    final map = _objectMap(json);
    if (map == null) {
      return const SavedCommandsState();
    }
    final rawEntries = map['entries'];
    if (rawEntries is List) {
      final entries = <SavedCommandEntry>[];
      final seenCommands = <String>{};
      for (final value in rawEntries) {
        final entry = SavedCommandEntry.fromJson(value);
        if (!entry.isValid || !seenCommands.add(entry.command)) {
          continue;
        }
        entries.add(entry);
      }
      if (entries.isNotEmpty) {
        return SavedCommandsState(
          version: _intOrDefault(map['version'], 2),
          entries: entries,
        );
      }
    }
    final rawCommands = map['commands'];
    if (rawCommands is! List) {
      return const SavedCommandsState();
    }
    final entries = <SavedCommandEntry>[];
    final seenCommands = <String>{};
    for (final value in rawCommands) {
      final command = _normalizedCommand(value);
      if (command.isEmpty || !seenCommands.add(command)) {
        continue;
      }
      entries.add(
        SavedCommandEntry(command: command, createdAt: _timestampForNewEntry()),
      );
    }
    return SavedCommandsState(entries: entries);
  }

  final int version;
  final List<SavedCommandEntry> entries;

  List<String> get commands =>
      entries.map((entry) => entry.command).toList(growable: false);

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'version': version,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
      'commands': commands,
    };
  }
}

class SavedCommandsStore {
  SavedCommandsStore({File? file})
    : file = file ?? defaultSavedCommandsFile(),
      _memoryState = null;

  SavedCommandsStore.memory([SavedCommandsState? initialState])
    : file = null,
      _memoryState = initialState ?? const SavedCommandsState();

  final File? file;
  SavedCommandsState? _memoryState;

  static File defaultSavedCommandsFile() {
    return File(defaultSavedCommandsFilePath());
  }

  SavedCommandsState load() {
    final memoryState = _memoryState;
    if (memoryState != null) {
      return memoryState;
    }
    final target = file;
    if (target == null || !target.existsSync()) {
      return const SavedCommandsState();
    }
    try {
      return SavedCommandsState.fromJson(jsonDecode(target.readAsStringSync()));
    } catch (_) {
      return const SavedCommandsState();
    }
  }

  void save(SavedCommandsState state) {
    if (_memoryState != null) {
      _memoryState = state;
      return;
    }
    final target = file;
    if (target == null) {
      return;
    }
    target.parent.createSync(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    target.writeAsStringSync('${encoder.convert(state.toJson())}\n');
  }
}

class SavedCommandsController extends ChangeNotifier {
  SavedCommandsController({required this.store})
    : _entries = List<SavedCommandEntry>.from(store.load().entries);

  factory SavedCommandsController.memory([
    List<String> commands = const <String>[],
  ]) {
    return SavedCommandsController(
      store: SavedCommandsStore.memory(
        SavedCommandsState(
          entries: commands
              .map((command) => SavedCommandEntry(command: command))
              .toList(growable: false),
        ),
      ),
    );
  }

  final SavedCommandsStore store;
  final List<SavedCommandEntry> _entries;

  List<SavedCommandEntry> get entries => List.unmodifiable(_entries);
  List<String> get commands =>
      entries.map((entry) => entry.command).toList(growable: false);
  bool get hasCommands => _entries.isNotEmpty;

  bool containsCommand(String command) {
    final normalized = _normalizedCommand(command);
    return normalized.isNotEmpty &&
        _entries.any((entry) => entry.command == normalized);
  }

  bool addCommand(String command) {
    final normalized = _normalizedCommand(command);
    if (normalized.isEmpty) {
      return false;
    }
    final previousIndex = _entries.indexWhere(
      (entry) => entry.command == normalized,
    );
    if (previousIndex == 0) {
      return false;
    }
    SavedCommandEntry? previousEntry;
    if (previousIndex > 0) {
      previousEntry = _entries.removeAt(previousIndex);
    }
    _entries.insert(
      0,
      (previousEntry ?? SavedCommandEntry(command: normalized)).copyWith(
        command: normalized,
        title: previousEntry?.title ?? normalized,
        createdAt: _timestampForNewEntry(),
      ),
    );
    _saveAndNotify();
    return true;
  }

  bool removeCommand(String command) {
    final normalized = _normalizedCommand(command);
    if (normalized.isEmpty) {
      return false;
    }
    final removedIndex = _entries.indexWhere(
      (entry) => entry.command == normalized,
    );
    if (removedIndex < 0) {
      return false;
    }
    _entries.removeAt(removedIndex);
    _saveAndNotify();
    return true;
  }

  void _saveAndNotify() {
    store.save(
      SavedCommandsState(entries: List<SavedCommandEntry>.from(_entries)),
    );
    notifyListeners();
  }
}

Map<String, Object?>? _objectMap(Object? value) {
  if (value is Map) {
    return value.map(
      (key, entry) => MapEntry(key.toString(), entry as Object?),
    );
  }
  return null;
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  final tags = <String>[];
  for (final entry in value) {
    final tag = _stringOrEmpty(entry);
    if (tag.isEmpty || tags.contains(tag)) {
      continue;
    }
    tags.add(tag);
  }
  return tags;
}

String _stringOrEmpty(Object? value) {
  if (value is! String) {
    return '';
  }
  return value.trim();
}

String _normalizedCommand(Object? value) {
  if (value is! String) {
    return '';
  }
  return value.trim();
}

int _intOrDefault(Object? value, int fallback) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return fallback;
}

String _timestampForNewEntry() {
  return DateTime.now().toUtc().toIso8601String();
}
