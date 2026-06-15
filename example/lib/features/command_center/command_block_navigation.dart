import 'command_block_models.dart';
import 'command_invocation_models.dart';

enum CommandBlockNavigationTarget { previous, next, lastFailed }

enum CommandBlockNavigationDisabledReason {
  shellIntegrationDisabled,
  noCommandBlocks,
  missingInputRange,
  noPreviousBlock,
  noNextBlock,
  noFailedBlock,
}

enum CommandBlockNavigationIntentKind { none, scrollToBlock }

class CommandBlockNavigationIntent {
  const CommandBlockNavigationIntent._({
    required this.kind,
    this.scope,
    this.blockId,
    this.row,
  });

  const CommandBlockNavigationIntent.none()
    : this._(kind: CommandBlockNavigationIntentKind.none);

  const CommandBlockNavigationIntent.scrollToBlock({
    required CommandBlockScope scope,
    required String blockId,
    required int row,
  }) : this._(
         kind: CommandBlockNavigationIntentKind.scrollToBlock,
         scope: scope,
         blockId: blockId,
         row: row,
       );

  final CommandBlockNavigationIntentKind kind;
  final CommandBlockScope? scope;
  final String? blockId;
  final int? row;

  bool get writesToTerminal => false;
}

class CommandBlockNavigationState {
  const CommandBlockNavigationState({
    required this.scope,
    this.selectedBlockId,
  });

  final CommandBlockScope scope;
  final String? selectedBlockId;

  CommandBlockNavigationState selectBlock(String blockId) {
    return CommandBlockNavigationState(scope: scope, selectedBlockId: blockId);
  }
}

class CommandBlockNavigationResult {
  const CommandBlockNavigationResult._({
    required this.state,
    required this.intent,
    required this.readOnly,
    this.disabledReason,
  });

  const CommandBlockNavigationResult.disabled({
    required CommandBlockNavigationState state,
    required CommandBlockNavigationDisabledReason reason,
    bool readOnly = false,
  }) : this._(
         state: state,
         intent: const CommandBlockNavigationIntent.none(),
         readOnly: readOnly,
         disabledReason: reason,
       );

  const CommandBlockNavigationResult.enabled({
    required CommandBlockNavigationState state,
    required CommandBlockNavigationIntent intent,
    bool readOnly = false,
  }) : this._(state: state, intent: intent, readOnly: readOnly);

  final CommandBlockNavigationState state;
  final CommandBlockNavigationIntent intent;
  final bool readOnly;
  final CommandBlockNavigationDisabledReason? disabledReason;

  bool get enabled => disabledReason == null;
}

class CommandBlockNavigationController {
  const CommandBlockNavigationController();

  CommandBlockNavigationResult navigate(
    CommandBlockRangeState rangeState, {
    required CommandBlockNavigationState state,
    required CommandBlockNavigationTarget target,
    bool readOnly = false,
  }) {
    if (!rangeState.shellIntegrationEnabled) {
      return CommandBlockNavigationResult.disabled(
        state: state,
        reason: CommandBlockNavigationDisabledReason.shellIntegrationDisabled,
        readOnly: readOnly,
      );
    }

    final scopedBlocks = rangeState.blocksForScope(state.scope);
    if (scopedBlocks.isEmpty) {
      return CommandBlockNavigationResult.disabled(
        state: state,
        reason: CommandBlockNavigationDisabledReason.noCommandBlocks,
        readOnly: readOnly,
      );
    }

    final navigableBlocks = scopedBlocks
        .where((block) => block.hasInputRange)
        .toList(growable: false);
    if (navigableBlocks.isEmpty) {
      return CommandBlockNavigationResult.disabled(
        state: state,
        reason: CommandBlockNavigationDisabledReason.missingInputRange,
        readOnly: readOnly,
      );
    }

    final targetBlock = switch (target) {
      CommandBlockNavigationTarget.previous => _previousBlock(
        navigableBlocks,
        state.selectedBlockId,
      ),
      CommandBlockNavigationTarget.next => _nextBlock(
        navigableBlocks,
        state.selectedBlockId,
      ),
      CommandBlockNavigationTarget.lastFailed => _lastFailedBlock(scopedBlocks),
    };

    if (targetBlock == null) {
      return CommandBlockNavigationResult.disabled(
        state: state,
        reason: _missingTargetReason(target),
        readOnly: readOnly,
      );
    }
    if (!targetBlock.hasInputRange) {
      return CommandBlockNavigationResult.disabled(
        state: state,
        reason: CommandBlockNavigationDisabledReason.missingInputRange,
        readOnly: readOnly,
      );
    }

    return CommandBlockNavigationResult.enabled(
      state: state.selectBlock(targetBlock.id),
      intent: CommandBlockNavigationIntent.scrollToBlock(
        scope: targetBlock.scope,
        blockId: targetBlock.id,
        row: targetBlock.inputRange!.startRow,
      ),
      readOnly: readOnly,
    );
  }
}

CommandBlock? _previousBlock(
  List<CommandBlock> blocks,
  String? selectedBlockId,
) {
  if (selectedBlockId == null) {
    return blocks.last;
  }
  final selectedIndex = blocks.indexWhere(
    (block) => block.id == selectedBlockId,
  );
  if (selectedIndex == -1) {
    return blocks.last;
  }
  if (selectedIndex == 0) {
    return null;
  }
  return blocks[selectedIndex - 1];
}

CommandBlock? _nextBlock(List<CommandBlock> blocks, String? selectedBlockId) {
  if (selectedBlockId == null) {
    return blocks.first;
  }
  final selectedIndex = blocks.indexWhere(
    (block) => block.id == selectedBlockId,
  );
  if (selectedIndex == -1) {
    return blocks.first;
  }
  if (selectedIndex == blocks.length - 1) {
    return null;
  }
  return blocks[selectedIndex + 1];
}

CommandBlock? _lastFailedBlock(List<CommandBlock> blocks) {
  for (final block in blocks.reversed) {
    if (block.status == CommandInvocationStatus.failed) {
      return block;
    }
  }
  return null;
}

CommandBlockNavigationDisabledReason _missingTargetReason(
  CommandBlockNavigationTarget target,
) {
  return switch (target) {
    CommandBlockNavigationTarget.previous =>
      CommandBlockNavigationDisabledReason.noPreviousBlock,
    CommandBlockNavigationTarget.next =>
      CommandBlockNavigationDisabledReason.noNextBlock,
    CommandBlockNavigationTarget.lastFailed =>
      CommandBlockNavigationDisabledReason.noFailedBlock,
  };
}
