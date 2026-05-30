class ShellIntegrationFeatureSet {
  const ShellIntegrationFeatureSet({
    this.promptMarks = true,
    this.cwdTracking = true,
    this.commandStatus = true,
    this.recentCommands = true,
    this.recentDirectories = true,
    this.commandOutputRanges = true,
  });

  const ShellIntegrationFeatureSet.disabled()
    : promptMarks = false,
      cwdTracking = false,
      commandStatus = false,
      recentCommands = false,
      recentDirectories = false,
      commandOutputRanges = false;

  final bool promptMarks;
  final bool cwdTracking;
  final bool commandStatus;
  final bool recentCommands;
  final bool recentDirectories;
  final bool commandOutputRanges;
}

class ShellPromptMark {
  const ShellPromptMark({required this.id, required this.row, this.cwd});

  final String id;
  final int row;
  final String? cwd;

  bool get isValid => id.trim().isNotEmpty && row >= 0;
}

class ShellCommandOutputRange {
  const ShellCommandOutputRange({
    required this.commandId,
    required this.startRow,
    required this.endRow,
  });

  final String commandId;
  final int startRow;
  final int endRow;

  bool get isValid => startRow >= 0 && endRow >= startRow;
}

class ShellProductivityState {
  const ShellProductivityState({
    this.features = const ShellIntegrationFeatureSet(),
    this.promptMarks = const <ShellPromptMark>[],
    this.commandOutputRanges = const <ShellCommandOutputRange>[],
    this.recentCommands = const <String>[],
    this.recentDirectories = const <String>[],
    this.readOnly = false,
  });

  final ShellIntegrationFeatureSet features;
  final List<ShellPromptMark> promptMarks;
  final List<ShellCommandOutputRange> commandOutputRanges;
  final List<String> recentCommands;
  final List<String> recentDirectories;
  final bool readOnly;

  bool get canSendText => !readOnly;
  bool get canPaste => !readOnly;
  bool get canNavigatePrompts {
    return features.promptMarks && promptMarks.any((mark) => mark.isValid);
  }

  bool get canSelectCommandOutput {
    return features.commandOutputRanges &&
        commandOutputRanges.any((range) => range.isValid);
  }

  bool get canOpenRecentDirectory {
    return features.recentDirectories && recentDirectories.isNotEmpty;
  }

  ShellPromptMark? previousPrompt(int currentRow) {
    if (!features.promptMarks) {
      return null;
    }

    ShellPromptMark? candidate;
    for (final mark in promptMarks) {
      if (mark.isValid &&
          mark.row < currentRow &&
          (candidate == null || mark.row > candidate.row)) {
        candidate = mark;
      }
    }
    return candidate;
  }

  ShellPromptMark? nextPrompt(int currentRow) {
    if (!features.promptMarks) {
      return null;
    }

    ShellPromptMark? candidate;
    for (final mark in promptMarks) {
      if (mark.isValid &&
          mark.row > currentRow &&
          (candidate == null || mark.row < candidate.row)) {
        candidate = mark;
      }
    }
    return candidate;
  }

  ShellCommandOutputRange? lastCommandOutputRange() {
    if (!features.commandOutputRanges) {
      return null;
    }

    for (final range in commandOutputRanges.reversed) {
      if (range.isValid) {
        return range;
      }
    }
    return null;
  }

  ShellProductivityState toggleReadOnly() {
    return ShellProductivityState(
      features: features,
      promptMarks: promptMarks,
      commandOutputRanges: commandOutputRanges,
      recentCommands: recentCommands,
      recentDirectories: recentDirectories,
      readOnly: !readOnly,
    );
  }
}

class ShellRecentCommandEntry {
  const ShellRecentCommandEntry({
    required this.command,
    required this.cwd,
    required this.exitCode,
  });

  final String command;
  final String? cwd;
  final int? exitCode;

  bool get succeeded => exitCode == 0;

  Map<String, Object?> toJson() {
    return {'command': command, 'cwd': cwd, 'exitCode': exitCode};
  }

  static ShellRecentCommandEntry fromJson(Map<Object?, Object?> json) {
    return ShellRecentCommandEntry(
      command: _trimmedStringOrNull(json['command']) ?? '',
      cwd: _trimmedStringOrNull(json['cwd']),
      exitCode: _intOrNull(json['exitCode']),
    );
  }
}

class ShellRecentDirectoryEntry {
  const ShellRecentDirectoryEntry({required this.path, this.label});

  final String path;
  final String? label;

  String get displayLabel => label ?? path;

  Map<String, Object?> toJson() {
    return {'path': path, 'label': label};
  }

  static ShellRecentDirectoryEntry fromJson(Map<Object?, Object?> json) {
    return ShellRecentDirectoryEntry(
      path: _trimmedStringOrNull(json['path']) ?? '',
      label: _trimmedStringOrNull(json['label']),
    );
  }
}

class ShellRecentItemsState {
  const ShellRecentItemsState({
    this.commands = const <ShellRecentCommandEntry>[],
    this.directories = const <ShellRecentDirectoryEntry>[],
    this.limit = _defaultRecentItemsLimit,
  });

  final List<ShellRecentCommandEntry> commands;
  final List<ShellRecentDirectoryEntry> directories;
  final int limit;

  ShellRecentItemsState addCommand(ShellRecentCommandEntry entry) {
    final command = _trimmedStringOrNull(entry.command);
    if (command == null) {
      return trimmed();
    }
    final normalizedEntry = ShellRecentCommandEntry(
      command: command,
      cwd: _trimmedStringOrNull(entry.cwd),
      exitCode: entry.exitCode,
    );
    return ShellRecentItemsState(
      commands: _prependUnique(
        commands,
        normalizedEntry,
        (candidate) => '${candidate.cwd ?? ''}\n${candidate.command}',
      ),
      directories: directories,
      limit: limit,
    ).trimmed();
  }

  ShellRecentItemsState addDirectory(ShellRecentDirectoryEntry entry) {
    final path = _trimmedStringOrNull(entry.path);
    if (path == null) {
      return trimmed();
    }
    final normalizedEntry = ShellRecentDirectoryEntry(
      path: path,
      label: _trimmedStringOrNull(entry.label),
    );
    return ShellRecentItemsState(
      commands: commands,
      directories: _prependUnique(
        directories,
        normalizedEntry,
        (candidate) => candidate.path,
      ),
      limit: limit,
    ).trimmed();
  }

  ShellRecentItemsState trimmed() {
    final effectiveLimit = _effectiveLimit(limit);
    return ShellRecentItemsState(
      commands: commands.take(effectiveLimit).toList(growable: false),
      directories: directories.take(effectiveLimit).toList(growable: false),
      limit: effectiveLimit,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'limit': limit,
      'commands': commands
          .map((entry) => entry.toJson())
          .toList(growable: false),
      'directories': directories
          .map((entry) => entry.toJson())
          .toList(growable: false),
    };
  }

  static ShellRecentItemsState fromJson(Map<Object?, Object?> json) {
    return ShellRecentItemsState(
      limit: _limitFromJson(json['limit']),
      commands: _objectList(json['commands'])
          .map(ShellRecentCommandEntry.fromJson)
          .where((entry) => entry.command.isNotEmpty)
          .toList(growable: false),
      directories: _objectList(json['directories'])
          .map(ShellRecentDirectoryEntry.fromJson)
          .where((entry) => entry.path.isNotEmpty)
          .toList(growable: false),
    ).trimmed();
  }
}

const _defaultRecentItemsLimit = 50;

class ShellCommandBlock {
  const ShellCommandBlock({
    required this.id,
    required this.command,
    required this.startRow,
    required this.endRow,
  });

  final String id;
  final String command;
  final int startRow;
  final int endRow;

  bool get isValid => startRow >= 0 && endRow >= startRow;

  bool containsRow(int row) {
    return isValid && row >= startRow && row <= endRow;
  }
}

class ShellSearchMatch {
  const ShellSearchMatch({
    required this.row,
    required this.column,
    required this.length,
    this.blockId,
  });

  final int row;
  final int column;
  final int length;
  final String? blockId;

  bool get isValid => row >= 0 && column >= 0 && length > 0;
}

class ShellSearchState {
  const ShellSearchState({
    this.query = '',
    this.matches = const <ShellSearchMatch>[],
    this.activeMatchIndex = -1,
    this.scopedBlockId,
  });

  final String query;
  final List<ShellSearchMatch> matches;
  final int activeMatchIndex;
  final String? scopedBlockId;

  bool get isActive => query.isNotEmpty;
  bool get hasMatches => matches.any((match) => match.isValid);
  ShellSearchMatch? get activeMatch {
    if (activeMatchIndex < 0 || activeMatchIndex >= matches.length) {
      return null;
    }
    final match = matches[activeMatchIndex];
    return match.isValid ? match : null;
  }

  ShellSearchState nextMatch() {
    final nextIndex = _nextValidMatchIndex(matches, activeMatchIndex);
    if (nextIndex == null) {
      return this;
    }

    return ShellSearchState(
      query: query,
      matches: matches,
      activeMatchIndex: nextIndex,
      scopedBlockId: scopedBlockId,
    );
  }

  ShellSearchState previousMatch() {
    final nextIndex = _previousValidMatchIndex(matches, activeMatchIndex);
    if (nextIndex == null) {
      return this;
    }

    return ShellSearchState(
      query: query,
      matches: matches,
      activeMatchIndex: nextIndex,
      scopedBlockId: scopedBlockId,
    );
  }

  ShellSearchState clear() {
    return const ShellSearchState();
  }

  ShellSearchState scopedToBlock(String blockId) {
    final scopedMatches = matches
        .where((match) => match.isValid && match.blockId == blockId)
        .toList(growable: false);
    return ShellSearchState(
      query: query,
      matches: scopedMatches,
      activeMatchIndex: scopedMatches.isEmpty ? -1 : 0,
      scopedBlockId: blockId,
    );
  }
}

int? _nextValidMatchIndex(List<ShellSearchMatch> matches, int currentIndex) {
  if (matches.isEmpty) {
    return null;
  }

  final startIndex = currentIndex < 0 ? -1 : currentIndex;
  for (var offset = 1; offset <= matches.length; offset += 1) {
    final index = (startIndex + offset) % matches.length;
    if (matches[index].isValid) {
      return index;
    }
  }
  return null;
}

int? _previousValidMatchIndex(
  List<ShellSearchMatch> matches,
  int currentIndex,
) {
  if (matches.isEmpty) {
    return null;
  }

  final startIndex = currentIndex < 0 || currentIndex >= matches.length
      ? 0
      : currentIndex;
  for (var offset = 1; offset <= matches.length; offset += 1) {
    final index = (startIndex - offset + matches.length * 2) % matches.length;
    if (matches[index].isValid) {
      return index;
    }
  }
  return null;
}

List<T> _prependUnique<T>(
  List<T> entries,
  T entry,
  String Function(T entry) keyOf,
) {
  final key = keyOf(entry);
  return [
    entry,
    for (final candidate in entries)
      if (keyOf(candidate) != key) candidate,
  ];
}

Map<Object?, Object?>? _objectMap(Object? value) {
  if (value is Map<Object?, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.cast<Object?, Object?>();
  }
  return null;
}

String? _stringOrNull(Object? value) {
  return value is String ? value : null;
}

String? _trimmedStringOrNull(Object? value) {
  final text = _stringOrNull(value)?.trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}

int? _intOrNull(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num && value.isFinite) {
    return value.toInt();
  }
  return null;
}

int? _wholeIntOrNull(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num && value.isFinite) {
    final parsed = value.toInt();
    if (value == parsed) {
      return parsed;
    }
  }
  return null;
}

int _limitFromJson(Object? value) {
  final parsed = _wholeIntOrNull(value);
  if (parsed == null) {
    return _defaultRecentItemsLimit;
  }
  return _effectiveLimit(parsed);
}

int _effectiveLimit(int value) {
  if (value < 1) {
    return _defaultRecentItemsLimit;
  }
  return value;
}

List<Map<Object?, Object?>> _objectList(Object? value) {
  if (value is! List) {
    return const <Map<Object?, Object?>>[];
  }

  return value
      .map(_objectMap)
      .whereType<Map<Object?, Object?>>()
      .toList(growable: false);
}
