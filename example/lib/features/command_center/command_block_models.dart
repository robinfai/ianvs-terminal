import 'command_invocation_models.dart';
import 'command_lifecycle_degraded_state.dart';

class CommandBlockScope {
  const CommandBlockScope(this.sessionId, {this.paneId});

  final String sessionId;
  final String? paneId;

  bool matches({required String sessionId, String? paneId}) {
    return this.sessionId == sessionId && this.paneId == paneId;
  }

  @override
  bool operator ==(Object other) {
    return other is CommandBlockScope &&
        other.sessionId == sessionId &&
        other.paneId == paneId;
  }

  @override
  int get hashCode => Object.hash(sessionId, paneId);
}

class CommandBlockRowRange {
  const CommandBlockRowRange({
    required this.startRow,
    required this.endRowExclusive,
  }) : assert(startRow >= 0),
       assert(endRowExclusive >= startRow);

  final int startRow;
  final int endRowExclusive;

  bool get isEmpty => startRow == endRowExclusive;
  int get rowCount => endRowExclusive - startRow;

  bool containsRow(int row) {
    return row >= startRow && row < endRowExclusive;
  }

  CommandBlockRowRange? truncateBeforeRow(int row) {
    if (endRowExclusive <= row) {
      return this;
    }
    if (row <= startRow) {
      return null;
    }
    return CommandBlockRowRange(startRow: startRow, endRowExclusive: row);
  }

  @override
  bool operator ==(Object other) {
    return other is CommandBlockRowRange &&
        other.startRow == startRow &&
        other.endRowExclusive == endRowExclusive;
  }

  @override
  int get hashCode => Object.hash(startRow, endRowExclusive);

  @override
  String toString() {
    return 'CommandBlockRowRange($startRow, $endRowExclusive)';
  }
}

class CommandBlockTerminalRanges {
  const CommandBlockTerminalRanges({this.inputRange, this.outputRange});

  final CommandBlockRowRange? inputRange;
  final CommandBlockRowRange? outputRange;

  bool get hasInputRange => inputRange != null && !inputRange!.isEmpty;
  bool get hasOutputRange => outputRange != null && !outputRange!.isEmpty;
  bool get hasCompleteRanges => hasInputRange && hasOutputRange;
}

class CommandBlock {
  const CommandBlock({
    required this.id,
    required this.sessionId,
    required this.command,
    required this.startedAt,
    required this.status,
    this.cwd,
    this.paneId,
    this.profileId,
    this.finishedAt,
    this.exitCode,
    this.inputRange,
    this.outputRange,
  });

  factory CommandBlock.fromInvocation(
    CommandInvocation invocation, {
    CommandBlockTerminalRanges ranges = const CommandBlockTerminalRanges(),
  }) {
    return CommandBlock(
      id: invocation.id,
      sessionId: invocation.sessionId,
      command: invocation.command,
      cwd: invocation.cwd,
      paneId: invocation.paneId,
      profileId: invocation.profileId,
      startedAt: invocation.startedAt,
      finishedAt: invocation.finishedAt,
      exitCode: invocation.exitCode,
      status: invocation.status,
      inputRange: ranges.inputRange,
      outputRange: ranges.outputRange,
    );
  }

  final String id;
  final String sessionId;
  final String command;
  final String? cwd;
  final String? paneId;
  final String? profileId;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final int? exitCode;
  final CommandInvocationStatus status;
  final CommandBlockRowRange? inputRange;
  final CommandBlockRowRange? outputRange;

  CommandBlockScope get scope => CommandBlockScope(sessionId, paneId: paneId);
  bool get hasInputRange => inputRange != null && !inputRange!.isEmpty;
  bool get hasOutputRange => outputRange != null && !outputRange!.isEmpty;
  bool get hasCompleteRanges => hasInputRange && hasOutputRange;

  CommandCenterActionAvailability outputRangeAvailability({
    bool shellIntegrationEnabled = true,
  }) {
    if (!shellIntegrationEnabled) {
      return CommandCenterActionAvailability.disabled(
        CommandCenterDisabledActionReason.shellIntegrationDisabled,
      );
    }
    if (!hasOutputRange) {
      return CommandCenterActionAvailability.disabled(
        CommandCenterDisabledActionReason.missingOutputRange,
      );
    }
    return CommandCenterActionAvailability.enabledAction;
  }

  CommandBlock copyWith({
    CommandBlockRowRange? inputRange,
    CommandBlockRowRange? outputRange,
    bool clearOutputRange = false,
  }) {
    return CommandBlock(
      id: id,
      sessionId: sessionId,
      command: command,
      cwd: cwd,
      paneId: paneId,
      profileId: profileId,
      startedAt: startedAt,
      finishedAt: finishedAt,
      exitCode: exitCode,
      status: status,
      inputRange: inputRange ?? this.inputRange,
      outputRange: clearOutputRange ? null : outputRange ?? this.outputRange,
    );
  }
}

class CommandBlockRangeState {
  const CommandBlockRangeState._({
    required this.blocks,
    required this.shellIntegrationEnabled,
  });

  factory CommandBlockRangeState.fromBlocks(
    Iterable<CommandBlock> blocks, {
    bool shellIntegrationEnabled = true,
  }) {
    return CommandBlockRangeState._(
      blocks: List<CommandBlock>.unmodifiable(
        _clipOutputRanges(blocks.toList(growable: false)),
      ),
      shellIntegrationEnabled: shellIntegrationEnabled,
    );
  }

  factory CommandBlockRangeState.fromInvocations(
    Iterable<CommandInvocation> invocations, {
    required Map<String, CommandBlockTerminalRanges> rangesByInvocationId,
    bool shellIntegrationEnabled = true,
  }) {
    final blocks = invocations
        .map(
          (invocation) => CommandBlock.fromInvocation(
            invocation,
            ranges:
                rangesByInvocationId[invocation.id] ??
                const CommandBlockTerminalRanges(),
          ),
        )
        .toList(growable: false);

    return CommandBlockRangeState._(
      blocks: List<CommandBlock>.unmodifiable(_clipOutputRanges(blocks)),
      shellIntegrationEnabled: shellIntegrationEnabled,
    );
  }

  final List<CommandBlock> blocks;
  final bool shellIntegrationEnabled;

  CommandBlock? blockByInvocationId(String invocationId) {
    for (final block in blocks) {
      if (block.id == invocationId) {
        return block;
      }
    }
    return null;
  }

  List<CommandBlock> blocksForScope(CommandBlockScope scope) {
    final scopedBlocks = blocks.where((block) => block.scope == scope).toList();
    scopedBlocks.sort(_compareBlocksForRows);
    return List<CommandBlock>.unmodifiable(scopedBlocks);
  }

  CommandLifecycleDegradedState degradedStateForScope(CommandBlockScope scope) {
    final scopedBlocks = blocksForScope(scope);
    return CommandLifecycleDegradedState(
      shellIntegrationEnabled: shellIntegrationEnabled,
      lifecycleAvailable: scopedBlocks.isNotEmpty,
      hasOutputRange: scopedBlocks.any((block) => block.hasOutputRange),
    );
  }
}

List<CommandBlock> _clipOutputRanges(List<CommandBlock> blocks) {
  final resultById = <String, CommandBlock>{
    for (final block in blocks) block.id: block,
  };
  final blocksByScope = <CommandBlockScope, List<CommandBlock>>{};

  for (final block in blocks) {
    blocksByScope.putIfAbsent(block.scope, () => <CommandBlock>[]).add(block);
  }

  for (final scopeBlocks in blocksByScope.values) {
    scopeBlocks.sort(_compareBlocksForRows);
    for (var index = 0; index < scopeBlocks.length - 1; index += 1) {
      final current = resultById[scopeBlocks[index].id]!;
      final outputRange = current.outputRange;
      final nextInputRange = scopeBlocks[index + 1].inputRange;
      if (outputRange == null || nextInputRange == null) {
        continue;
      }
      final clippedRange = outputRange.truncateBeforeRow(
        nextInputRange.startRow,
      );
      resultById[current.id] = current.copyWith(
        outputRange: clippedRange,
        clearOutputRange: clippedRange == null,
      );
    }
  }

  return blocks.map((block) => resultById[block.id]!).toList(growable: false);
}

int _compareBlocksForRows(CommandBlock a, CommandBlock b) {
  final aStart = a.inputRange?.startRow;
  final bStart = b.inputRange?.startRow;
  if (aStart != null && bStart != null && aStart != bStart) {
    return aStart.compareTo(bStart);
  }
  if (aStart != null && bStart == null) {
    return -1;
  }
  if (aStart == null && bStart != null) {
    return 1;
  }

  final startedAtComparison = a.startedAt.compareTo(b.startedAt);
  if (startedAtComparison != 0) {
    return startedAtComparison;
  }
  return a.id.compareTo(b.id);
}
