import 'command_blocks_history_feature_flags.dart';
import 'shell_productivity_models.dart';
import 'shell_productivity_reducer.dart';

class ShellCommandBlockSnapshot {
  const ShellCommandBlockSnapshot({
    this.lastPrompt,
    this.pendingRange,
    this.currentCwd,
  }) : _blocks = const <ShellCommandBlock>[];

  ShellCommandBlockSnapshot.withBlocks({
    List<ShellCommandBlock> blocks = const <ShellCommandBlock>[],
    this.lastPrompt,
    this.pendingRange,
    this.currentCwd,
  }) : _blocks = List<ShellCommandBlock>.unmodifiable(blocks);

  final ShellPromptMark? lastPrompt;
  final ShellCommandOutputRange? pendingRange;
  final String? currentCwd;
  final List<ShellCommandBlock> _blocks;

  List<ShellCommandBlock> get blocks => _blocks;

  ShellCommandBlock? previousRunFor(ShellCommandBlock block) {
    final targetIndex = blocks.indexWhere(
      (candidate) => candidate.id == block.id,
    );
    final endIndex = targetIndex < 0 ? blocks.length : targetIndex;
    for (var index = endIndex - 1; index >= 0; index -= 1) {
      final candidate = blocks[index];
      if (candidate.command == block.command && candidate.cwd == block.cwd) {
        return candidate;
      }
    }
    return null;
  }
}

class ShellCommandBlockController {
  const ShellCommandBlockController._();

  static ShellCommandBlockSnapshot reduce(
    ShellCommandBlockSnapshot snapshot,
    ShellProductivityEvent event, {
    required CommandBlocksHistoryFeatureFlags flags,
  }) {
    if (!flags.enabled || !flags.commandBlocks) {
      return snapshot;
    }
    return switch (event) {
      ShellPromptMarkEvent() => _promptMark(snapshot, event),
      ShellCommandOutputRangeEvent() => _outputRange(snapshot, event),
      ShellCommandFinishedEvent() => _commandFinished(
        snapshot,
        event,
        flags: flags,
      ),
      ShellCwdChangedEvent() => _cwdChanged(snapshot, event),
    };
  }

  static ShellCommandBlockSnapshot _cwdChanged(
    ShellCommandBlockSnapshot snapshot,
    ShellCwdChangedEvent event,
  ) {
    final cwd = _trimmed(event.cwd);
    if (cwd == null) {
      return snapshot;
    }
    return ShellCommandBlockSnapshot.withBlocks(
      blocks: snapshot.blocks,
      lastPrompt: snapshot.lastPrompt,
      pendingRange: snapshot.pendingRange,
      currentCwd: cwd,
    );
  }

  static ShellCommandBlockSnapshot _promptMark(
    ShellCommandBlockSnapshot snapshot,
    ShellPromptMarkEvent event,
  ) {
    final id = event.id.trim();
    if (id.isEmpty || event.row < 0) {
      return snapshot;
    }
    return ShellCommandBlockSnapshot.withBlocks(
      blocks: snapshot.blocks,
      lastPrompt: ShellPromptMark(
        id: id,
        row: event.row,
        cwd: _trimmed(event.cwd) ?? snapshot.currentCwd,
      ),
      pendingRange: snapshot.pendingRange,
      currentCwd: snapshot.currentCwd,
    );
  }

  static ShellCommandBlockSnapshot _outputRange(
    ShellCommandBlockSnapshot snapshot,
    ShellCommandOutputRangeEvent event,
  ) {
    final commandId = event.commandId.trim();
    if (commandId.isEmpty ||
        event.startRow < 0 ||
        event.endRow < event.startRow) {
      return snapshot;
    }
    return ShellCommandBlockSnapshot.withBlocks(
      blocks: snapshot.blocks,
      lastPrompt: snapshot.lastPrompt,
      pendingRange: ShellCommandOutputRange(
        commandId: commandId,
        startRow: event.startRow,
        endRow: event.endRow,
      ),
      currentCwd: snapshot.currentCwd,
    );
  }

  static ShellCommandBlockSnapshot _commandFinished(
    ShellCommandBlockSnapshot snapshot,
    ShellCommandFinishedEvent event, {
    required CommandBlocksHistoryFeatureFlags flags,
  }) {
    final command = event.command.trim();
    final range = snapshot.pendingRange;
    if (range == null) {
      return snapshot;
    }
    if (command.isEmpty || !range.isValid) {
      return ShellCommandBlockSnapshot.withBlocks(
        blocks: snapshot.blocks,
        lastPrompt: snapshot.lastPrompt,
        pendingRange: null,
        currentCwd: snapshot.currentCwd,
      );
    }
    final status = switch (event.exitCode) {
      0 => ShellCommandBlockStatus.succeeded,
      null => ShellCommandBlockStatus.unknown,
      _ => ShellCommandBlockStatus.failed,
    };
    final outputRange = ShellCommandBlockRange(
      commandRow: snapshot.lastPrompt?.row ?? range.startRow,
      outputStartRow: range.startRow,
      outputEndRow: range.endRow,
    );
    if (!outputRange.isValid) {
      return ShellCommandBlockSnapshot.withBlocks(
        blocks: snapshot.blocks,
        lastPrompt: snapshot.lastPrompt,
        pendingRange: null,
        currentCwd: snapshot.currentCwd,
      );
    }
    final cwd =
        _trimmed(event.cwd) ?? snapshot.lastPrompt?.cwd ?? snapshot.currentCwd;
    final block = ShellCommandBlock(
      id: range.commandId,
      command: command,
      cwd: cwd,
      exitCode: event.exitCode,
      status: status,
      outputRange: outputRange,
      failureSnapshot:
          status == ShellCommandBlockStatus.failed && flags.failureSnapshots
          ? ShellFailureSnapshot(
              commandBlockId: range.commandId,
              command: command,
              cwd: cwd,
              exitCode: event.exitCode,
              outputRange: outputRange,
            )
          : null,
    );
    return ShellCommandBlockSnapshot.withBlocks(
      blocks: [...snapshot.blocks, block],
      lastPrompt: snapshot.lastPrompt,
      pendingRange: null,
      currentCwd: snapshot.currentCwd,
    );
  }
}

String? _trimmed(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}
