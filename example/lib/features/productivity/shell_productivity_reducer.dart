import 'shell_productivity_models.dart';

sealed class ShellProductivityEvent {
  const ShellProductivityEvent();
}

class ShellPromptMarkEvent extends ShellProductivityEvent {
  const ShellPromptMarkEvent({required this.id, required this.row, this.cwd});

  final String id;
  final int row;
  final String? cwd;
}

class ShellCommandFinishedEvent extends ShellProductivityEvent {
  const ShellCommandFinishedEvent({
    required this.command,
    required this.cwd,
    required this.exitCode,
  });

  final String command;
  final String? cwd;
  final int? exitCode;
}

class ShellCommandStartedEvent extends ShellProductivityEvent {
  const ShellCommandStartedEvent({
    required this.commandId,
    required this.command,
    required this.commandRow,
    this.cwd,
  });

  final String commandId;
  final String command;
  final int commandRow;
  final String? cwd;
}

class ShellCommandOutputRangeEvent extends ShellProductivityEvent {
  const ShellCommandOutputRangeEvent({
    required this.commandId,
    required this.startRow,
    required this.endRow,
  });

  final String commandId;
  final int startRow;
  final int endRow;
}

class ShellCwdChangedEvent extends ShellProductivityEvent {
  const ShellCwdChangedEvent(this.cwd);

  final String cwd;
}

class ShellProductivitySnapshot {
  const ShellProductivitySnapshot({
    this.state = const ShellProductivityState(),
    this.recentItems = const ShellRecentItemsState(),
    this.currentCwd,
  });

  final ShellProductivityState state;
  final ShellRecentItemsState recentItems;
  final String? currentCwd;
}

class ShellProductivityReducer {
  const ShellProductivityReducer._();

  static ShellProductivitySnapshot reduce(
    ShellProductivitySnapshot snapshot,
    ShellProductivityEvent event,
  ) {
    return switch (event) {
      ShellPromptMarkEvent() => _promptMark(snapshot, event),
      ShellCommandStartedEvent() => _commandStarted(snapshot, event),
      ShellCommandFinishedEvent() => _commandFinished(snapshot, event),
      ShellCommandOutputRangeEvent() => _commandOutputRange(snapshot, event),
      ShellCwdChangedEvent() => _cwdChanged(snapshot, event),
    };
  }

  static ShellProductivitySnapshot _cwdChanged(
    ShellProductivitySnapshot snapshot,
    ShellCwdChangedEvent event,
  ) {
    final cwd = _trimmedOrNull(event.cwd);
    if (cwd == null) {
      return snapshot;
    }
    return ShellProductivitySnapshot(
      state: snapshot.state,
      recentItems: snapshot.recentItems.addDirectory(
        ShellRecentDirectoryEntry(path: cwd),
      ),
      currentCwd: cwd,
    );
  }

  static ShellProductivitySnapshot _promptMark(
    ShellProductivitySnapshot snapshot,
    ShellPromptMarkEvent event,
  ) {
    final id = _trimmedOrNull(event.id);
    if (id == null || event.row < 0) {
      return snapshot;
    }

    final cwd = _trimmedOrNull(event.cwd);
    return ShellProductivitySnapshot(
      state: ShellProductivityState(
        features: snapshot.state.features,
        promptMarks: [
          ...snapshot.state.promptMarks,
          ShellPromptMark(id: id, row: event.row, cwd: cwd),
        ],
        commandOutputRanges: snapshot.state.commandOutputRanges,
        recentCommands: snapshot.state.recentCommands,
        recentDirectories: snapshot.state.recentDirectories,
        readOnly: snapshot.state.readOnly,
      ),
      recentItems: cwd == null
          ? snapshot.recentItems
          : snapshot.recentItems.addDirectory(
              ShellRecentDirectoryEntry(path: cwd),
            ),
      currentCwd: cwd ?? snapshot.currentCwd,
    );
  }

  static ShellProductivitySnapshot _commandStarted(
    ShellProductivitySnapshot snapshot,
    ShellCommandStartedEvent event,
  ) {
    final cwd = _trimmedOrNull(event.cwd);
    if (cwd == null) {
      return snapshot;
    }
    return ShellProductivitySnapshot(
      state: snapshot.state,
      recentItems: snapshot.recentItems.addDirectory(
        ShellRecentDirectoryEntry(path: cwd),
      ),
      currentCwd: cwd,
    );
  }

  static ShellProductivitySnapshot _commandFinished(
    ShellProductivitySnapshot snapshot,
    ShellCommandFinishedEvent event,
  ) {
    final command = event.command.trim();
    final eventCwd = _trimmedOrNull(event.cwd);
    final currentCwd = eventCwd ?? snapshot.currentCwd;
    return ShellProductivitySnapshot(
      state: snapshot.state,
      recentItems: command.isEmpty
          ? snapshot.recentItems
          : snapshot.recentItems.addCommand(
              ShellRecentCommandEntry(
                command: command,
                cwd: currentCwd,
                exitCode: event.exitCode,
              ),
            ),
      currentCwd: currentCwd,
    );
  }

  static ShellProductivitySnapshot _commandOutputRange(
    ShellProductivitySnapshot snapshot,
    ShellCommandOutputRangeEvent event,
  ) {
    return ShellProductivitySnapshot(
      state: ShellProductivityState(
        features: snapshot.state.features,
        promptMarks: snapshot.state.promptMarks,
        commandOutputRanges: [
          ...snapshot.state.commandOutputRanges,
          ShellCommandOutputRange(
            commandId: event.commandId,
            startRow: event.startRow,
            endRow: event.endRow,
          ),
        ],
        recentCommands: snapshot.state.recentCommands,
        recentDirectories: snapshot.state.recentDirectories,
        readOnly: snapshot.state.readOnly,
      ),
      recentItems: snapshot.recentItems,
      currentCwd: snapshot.currentCwd,
    );
  }
}

String? _trimmedOrNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
