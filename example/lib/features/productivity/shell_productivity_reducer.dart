import 'shell_productivity_models.dart';

const int maxShellPromptMarks = 500;
const int maxShellCommandOutputRanges = 500;

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
        promptMarks: _appendBounded(
          snapshot.state.promptMarks,
          ShellPromptMark(id: id, row: event.row, cwd: cwd),
          maxShellPromptMarks,
        ),
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
    final commandId = _trimmedOrNull(event.commandId);
    if (commandId == null ||
        event.startRow < 0 ||
        event.endRow < event.startRow) {
      return snapshot;
    }

    return ShellProductivitySnapshot(
      state: ShellProductivityState(
        features: snapshot.state.features,
        promptMarks: snapshot.state.promptMarks,
        commandOutputRanges: _appendBounded(
          snapshot.state.commandOutputRanges,
          ShellCommandOutputRange(
            commandId: commandId,
            startRow: event.startRow,
            endRow: event.endRow,
          ),
          maxShellCommandOutputRanges,
        ),
        recentCommands: snapshot.state.recentCommands,
        recentDirectories: snapshot.state.recentDirectories,
        readOnly: snapshot.state.readOnly,
      ),
      recentItems: snapshot.recentItems,
      currentCwd: snapshot.currentCwd,
    );
  }
}

List<T> _appendBounded<T>(List<T> current, T next, int limit) {
  if (limit <= 0) {
    return <T>[];
  }
  final start = current.length >= limit ? current.length - limit + 1 : 0;
  return <T>[...current.skip(start), next];
}

String? _trimmedOrNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
