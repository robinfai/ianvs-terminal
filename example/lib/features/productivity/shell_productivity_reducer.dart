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
      ShellCwdChangedEvent() => ShellProductivitySnapshot(
        state: snapshot.state,
        recentItems: snapshot.recentItems.addDirectory(
          ShellRecentDirectoryEntry(path: event.cwd),
        ),
        currentCwd: event.cwd,
      ),
    };
  }

  static ShellProductivitySnapshot _promptMark(
    ShellProductivitySnapshot snapshot,
    ShellPromptMarkEvent event,
  ) {
    return ShellProductivitySnapshot(
      state: ShellProductivityState(
        features: snapshot.state.features,
        promptMarks: [
          ...snapshot.state.promptMarks,
          ShellPromptMark(id: event.id, row: event.row, cwd: event.cwd),
        ],
        commandOutputRanges: snapshot.state.commandOutputRanges,
        recentCommands: snapshot.state.recentCommands,
        recentDirectories: snapshot.state.recentDirectories,
        readOnly: snapshot.state.readOnly,
      ),
      recentItems: event.cwd == null
          ? snapshot.recentItems
          : snapshot.recentItems.addDirectory(
              ShellRecentDirectoryEntry(path: event.cwd!),
            ),
      currentCwd: event.cwd ?? snapshot.currentCwd,
    );
  }

  static ShellProductivitySnapshot _commandFinished(
    ShellProductivitySnapshot snapshot,
    ShellCommandFinishedEvent event,
  ) {
    return ShellProductivitySnapshot(
      state: snapshot.state,
      recentItems: snapshot.recentItems.addCommand(
        ShellRecentCommandEntry(
          command: event.command,
          cwd: event.cwd ?? snapshot.currentCwd,
          exitCode: event.exitCode,
        ),
      ),
      currentCwd: event.cwd ?? snapshot.currentCwd,
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
