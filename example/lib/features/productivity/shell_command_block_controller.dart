import 'command_blocks_history_feature_flags.dart';
import 'shell_productivity_models.dart';
import 'shell_productivity_reducer.dart';

const int shellCommandBlockSnapshotBlockLimit = 200;

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
  }) : _blocks = List<ShellCommandBlock>.unmodifiable(
         _retainedCommandBlocks(blocks),
       );

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
      ShellCommandStartedEvent() => _commandStarted(snapshot, event),
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
    final eventCwd = _trimmed(event.cwd);
    final currentCwd = eventCwd ?? snapshot.currentCwd;
    return ShellCommandBlockSnapshot.withBlocks(
      blocks: snapshot.blocks,
      lastPrompt: ShellPromptMark(id: id, row: event.row, cwd: currentCwd),
      pendingRange: snapshot.pendingRange,
      currentCwd: currentCwd,
    );
  }

  static ShellCommandBlockSnapshot _commandStarted(
    ShellCommandBlockSnapshot snapshot,
    ShellCommandStartedEvent event,
  ) {
    final commandId = event.commandId.trim();
    final command = event.command.trim();
    if (commandId.isEmpty || command.isEmpty || event.commandRow < 0) {
      return snapshot;
    }
    final eventCwd = _trimmed(event.cwd);
    final cwd = eventCwd ?? snapshot.lastPrompt?.cwd ?? snapshot.currentCwd;
    final outputRange = ShellCommandBlockRange(
      commandRow: event.commandRow,
      outputStartRow: event.commandRow + 1,
      outputEndRow: event.commandRow + 1,
    );
    final block = ShellCommandBlock(
      id: commandId,
      command: command,
      cwd: cwd,
      status: ShellCommandBlockStatus.running,
      outputRange: outputRange,
    );
    return ShellCommandBlockSnapshot.withBlocks(
      blocks: _upsertCommandBlock(snapshot.blocks, block),
      lastPrompt: snapshot.lastPrompt,
      pendingRange: null,
      currentCwd: cwd ?? snapshot.currentCwd,
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
      return ShellCommandBlockSnapshot.withBlocks(
        blocks: snapshot.blocks,
        lastPrompt: snapshot.lastPrompt,
        pendingRange: null,
        currentCwd: snapshot.currentCwd,
      );
    }
    final pendingRange = ShellCommandOutputRange(
      commandId: commandId,
      startRow: event.startRow,
      endRow: event.endRow,
    );
    return ShellCommandBlockSnapshot.withBlocks(
      blocks: _blocksWithUpdatedRunningRange(snapshot.blocks, pendingRange),
      lastPrompt: snapshot.lastPrompt,
      pendingRange: pendingRange,
      currentCwd: snapshot.currentCwd,
    );
  }

  static ShellCommandBlockSnapshot _commandFinished(
    ShellCommandBlockSnapshot snapshot,
    ShellCommandFinishedEvent event, {
    required CommandBlocksHistoryFeatureFlags flags,
  }) {
    final command = event.command.trim();
    final eventCwd = _trimmed(event.cwd);
    final currentCwd = eventCwd ?? snapshot.currentCwd;
    final runningBlock = _latestRunningBlockForCommand(snapshot, command);
    final range =
        snapshot.pendingRange ?? _outputRangeFromRunningBlock(runningBlock);
    if (range == null) {
      if (eventCwd == null) {
        return snapshot;
      }
      return ShellCommandBlockSnapshot.withBlocks(
        blocks: snapshot.blocks,
        lastPrompt: snapshot.lastPrompt,
        pendingRange: null,
        currentCwd: currentCwd,
      );
    }
    if (command.isEmpty || !range.isValid) {
      return ShellCommandBlockSnapshot.withBlocks(
        blocks: snapshot.blocks,
        lastPrompt: snapshot.lastPrompt,
        pendingRange: null,
        currentCwd: currentCwd,
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
        currentCwd: currentCwd,
      );
    }
    final cwd = eventCwd ?? snapshot.lastPrompt?.cwd ?? snapshot.currentCwd;
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
      blocks: _upsertCommandBlock(snapshot.blocks, block),
      lastPrompt: snapshot.lastPrompt,
      pendingRange: null,
      currentCwd: currentCwd,
    );
  }
}

ShellCommandBlock? _latestRunningBlockForCommand(
  ShellCommandBlockSnapshot snapshot,
  String command,
) {
  final trimmedCommand = command.trim();
  if (trimmedCommand.isEmpty) {
    return null;
  }
  for (final block in snapshot.blocks.reversed) {
    if (block.status == ShellCommandBlockStatus.running &&
        block.command == trimmedCommand &&
        block.isValid) {
      return block;
    }
  }
  return null;
}

ShellCommandOutputRange? _outputRangeFromRunningBlock(
  ShellCommandBlock? block,
) {
  if (block == null || !block.isValid) {
    return null;
  }
  return ShellCommandOutputRange(
    commandId: block.id,
    startRow: block.outputRange.outputStartRow,
    endRow: block.outputRange.outputEndRow,
  );
}

List<ShellCommandBlock> _blocksWithUpdatedRunningRange(
  List<ShellCommandBlock> blocks,
  ShellCommandOutputRange range,
) {
  final index = blocks.lastIndexWhere(
    (block) =>
        block.id == range.commandId &&
        block.status == ShellCommandBlockStatus.running &&
        block.outputRange.commandRow < range.startRow,
  );
  if (index < 0) {
    return blocks;
  }
  final existing = blocks[index];
  final updated = existing.copyWith(
    outputRange: ShellCommandBlockRange(
      commandRow: existing.outputRange.commandRow,
      outputStartRow: range.startRow,
      outputEndRow: range.endRow,
    ),
  );
  return [...blocks.take(index), updated, ...blocks.skip(index + 1)];
}

List<ShellCommandBlock> _upsertCommandBlock(
  List<ShellCommandBlock> blocks,
  ShellCommandBlock block,
) {
  final index = blocks.lastIndexWhere((candidate) => candidate.id == block.id);
  if (index < 0) {
    return _retainedCommandBlocks([...blocks, block]);
  }
  return _retainedCommandBlocks([
    ...blocks.take(index),
    block,
    ...blocks.skip(index + 1),
  ]);
}

List<ShellCommandBlock> _retainedCommandBlocks(
  Iterable<ShellCommandBlock> blocks,
) {
  final list = blocks is List<ShellCommandBlock>
      ? blocks
      : blocks.toList(growable: false);
  if (list.length <= shellCommandBlockSnapshotBlockLimit) {
    return list;
  }
  return list.sublist(list.length - shellCommandBlockSnapshotBlockLimit);
}

String? _trimmed(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}
