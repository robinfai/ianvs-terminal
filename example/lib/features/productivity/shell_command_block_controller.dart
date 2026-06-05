import 'command_blocks_history_feature_flags.dart';
import 'shell_productivity_models.dart';
import 'shell_productivity_reducer.dart';

class ShellCommandBlockSnapshot {
  const ShellCommandBlockSnapshot({
    this.blocks = const <ShellCommandBlock>[],
    this.lastPrompt,
    this.pendingRange,
  });

  final List<ShellCommandBlock> blocks;
  final ShellPromptMark? lastPrompt;
  final ShellCommandOutputRange? pendingRange;

  ShellCommandBlock? previousRunFor(ShellCommandBlock block) {
    for (final candidate in blocks.reversed) {
      if (candidate.id == block.id) {
        continue;
      }
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
      ShellCwdChangedEvent() => snapshot,
    };
  }

  static ShellCommandBlockSnapshot _promptMark(
    ShellCommandBlockSnapshot snapshot,
    ShellPromptMarkEvent event,
  ) {
    final id = event.id.trim();
    if (id.isEmpty || event.row < 0) {
      return snapshot;
    }
    return ShellCommandBlockSnapshot(
      blocks: snapshot.blocks,
      lastPrompt: ShellPromptMark(
        id: id,
        row: event.row,
        cwd: _trimmed(event.cwd),
      ),
      pendingRange: snapshot.pendingRange,
    );
  }

  static ShellCommandBlockSnapshot _outputRange(
    ShellCommandBlockSnapshot snapshot,
    ShellCommandOutputRangeEvent event,
  ) {
    if (event.startRow < 0 || event.endRow < event.startRow) {
      return snapshot;
    }
    return ShellCommandBlockSnapshot(
      blocks: snapshot.blocks,
      lastPrompt: snapshot.lastPrompt,
      pendingRange: ShellCommandOutputRange(
        commandId: event.commandId,
        startRow: event.startRow,
        endRow: event.endRow,
      ),
    );
  }

  static ShellCommandBlockSnapshot _commandFinished(
    ShellCommandBlockSnapshot snapshot,
    ShellCommandFinishedEvent event, {
    required CommandBlocksHistoryFeatureFlags flags,
  }) {
    final command = event.command.trim();
    final range = snapshot.pendingRange;
    if (command.isEmpty || range == null || !range.isValid) {
      return snapshot;
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
    final cwd = _trimmed(event.cwd) ?? snapshot.lastPrompt?.cwd;
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
    return ShellCommandBlockSnapshot(
      blocks: [...snapshot.blocks, block],
      lastPrompt: snapshot.lastPrompt,
      pendingRange: null,
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
