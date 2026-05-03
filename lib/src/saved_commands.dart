import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'platform_paths.dart';

class SavedCommandsState {
  const SavedCommandsState({
    this.version = 1,
    this.commands = const <String>[],
  });

  factory SavedCommandsState.fromJson(Object? json) {
    final map = _objectMap(json);
    if (map == null) {
      return const SavedCommandsState();
    }
    final rawCommands = map['commands'];
    if (rawCommands is! List) {
      return const SavedCommandsState();
    }
    final commands = <String>[];
    for (final value in rawCommands) {
      if (value is! String) {
        continue;
      }
      final command = value.trim();
      if (command.isEmpty || commands.contains(command)) {
        continue;
      }
      commands.add(command);
    }
    return SavedCommandsState(commands: commands);
  }

  final int version;
  final List<String> commands;

  Map<String, Object?> toJson() {
    return <String, Object?>{'version': version, 'commands': commands};
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
    : _commands = List<String>.from(store.load().commands);

  factory SavedCommandsController.memory([
    List<String> commands = const <String>[],
  ]) {
    return SavedCommandsController(
      store: SavedCommandsStore.memory(SavedCommandsState(commands: commands)),
    );
  }

  final SavedCommandsStore store;
  final List<String> _commands;

  List<String> get commands => List.unmodifiable(_commands);
  bool get hasCommands => _commands.isNotEmpty;

  bool containsCommand(String command) {
    final normalized = command.trim();
    return normalized.isNotEmpty && _commands.contains(normalized);
  }

  bool addCommand(String command) {
    final normalized = command.trim();
    if (normalized.isEmpty) {
      return false;
    }
    final previousIndex = _commands.indexOf(normalized);
    if (previousIndex == 0) {
      return false;
    }
    if (previousIndex > 0) {
      _commands.removeAt(previousIndex);
    }
    _commands.insert(0, normalized);
    _saveAndNotify();
    return true;
  }

  bool removeCommand(String command) {
    final normalized = command.trim();
    if (normalized.isEmpty) {
      return false;
    }
    final removed = _commands.remove(normalized);
    if (!removed) {
      return false;
    }
    _saveAndNotify();
    return true;
  }

  void _saveAndNotify() {
    store.save(SavedCommandsState(commands: List<String>.from(_commands)));
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
