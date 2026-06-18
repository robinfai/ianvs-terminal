import 'command_block_actions.dart';
import 'command_block_models.dart';
import 'command_search_intents.dart';
import 'command_search_overlay_controller.dart';

class CommandBlockActionReducer {
  const CommandBlockActionReducer({
    this.writePolicy = const CommandSearchInsertExecutePolicy(),
  });

  final CommandSearchInsertExecutePolicy writePolicy;

  CommandBlockActionResult reduce(
    CommandBlockAction action,
    CommandBlock block, {
    bool readOnly = false,
    bool hasTerminalFrame = true,
  }) {
    if (_requiresOutputRange(action) && !block.hasOutputRange) {
      return const CommandBlockActionResult.disabled(
        CommandBlockActionDisabledReason.missingOutputRange,
      );
    }
    if (_requiresTerminalFrame(action) && !hasTerminalFrame) {
      return const CommandBlockActionResult.disabled(
        CommandBlockActionDisabledReason.missingTerminalFrame,
      );
    }

    return switch (action) {
      CommandBlockAction.copyCommand => _copyCommand(block),
      CommandBlockAction.copyOutput => _copyOutput(block),
      CommandBlockAction.copyBoth => _copyBoth(block),
      CommandBlockAction.reInput => _terminalWrite(
        block,
        CommandSearchOverlayOutput.insert(block.command),
        readOnly: readOnly,
        explicitExecution: false,
      ),
      CommandBlockAction.rerun => _terminalWrite(
        block,
        CommandSearchOverlayOutput.explicitExecute(block.command),
        readOnly: readOnly,
        explicitExecution: true,
      ),
      CommandBlockAction.searchWithinBlock => CommandBlockActionResult.enabled(
        CommandBlockActionIntent.scopedSearch(
          scope: block.scope,
          blockId: block.id,
          outputRange: block.outputRange!,
        ),
      ),
      CommandBlockAction.saveOutput => CommandBlockActionResult.enabled(
        CommandBlockActionIntent.saveOutput(
          scope: block.scope,
          blockId: block.id,
          outputRange: block.outputRange!,
        ),
      ),
      CommandBlockAction.openReviewEntrypoint =>
        CommandBlockActionResult.enabled(
          CommandBlockActionIntent.reviewEntrypoint(
            scope: block.scope,
            blockId: block.id,
            outputRange: block.outputRange!,
          ),
        ),
    };
  }

  CommandBlockActionResult _copyCommand(CommandBlock block) {
    final command = block.command.trim();
    if (command.isEmpty) {
      return const CommandBlockActionResult.disabled(
        CommandBlockActionDisabledReason.emptyCommand,
      );
    }
    return CommandBlockActionResult.enabled(
      CommandBlockActionIntent.clipboardText(
        text: command,
        scope: block.scope,
        blockId: block.id,
      ),
    );
  }

  CommandBlockActionResult _copyOutput(CommandBlock block) {
    return CommandBlockActionResult.enabled(
      CommandBlockActionIntent.copyOutputRange(
        scope: block.scope,
        blockId: block.id,
        outputRange: block.outputRange!,
      ),
    );
  }

  CommandBlockActionResult _copyBoth(CommandBlock block) {
    final command = block.command.trim();
    if (command.isEmpty) {
      return const CommandBlockActionResult.disabled(
        CommandBlockActionDisabledReason.emptyCommand,
      );
    }
    return CommandBlockActionResult.enabled(
      CommandBlockActionIntent.clipboardCommandAndOutput(
        text: command,
        scope: block.scope,
        blockId: block.id,
        outputRange: block.outputRange!,
      ),
    );
  }

  CommandBlockActionResult _terminalWrite(
    CommandBlock block,
    CommandSearchOverlayOutput output, {
    required bool readOnly,
    required bool explicitExecution,
  }) {
    final terminalIntent = writePolicy.resolve(output, readOnly: readOnly);
    final intent = CommandBlockActionIntent.terminalWrite(
      terminalIntent: terminalIntent,
      scope: block.scope,
      blockId: block.id,
      explicitExecution: explicitExecution,
    );
    return switch (terminalIntent.kind) {
      CommandSearchTerminalIntentKind.insertText ||
      CommandSearchTerminalIntentKind.executeText =>
        CommandBlockActionResult.enabled(intent),
      CommandSearchTerminalIntentKind.requiresPastePolicy =>
        CommandBlockActionResult.enabled(intent),
      CommandSearchTerminalIntentKind.disabled =>
        CommandBlockActionResult.disabled(
          _disabledReasonForTerminalIntent(terminalIntent),
          intent: intent,
        ),
      CommandSearchTerminalIntentKind.none =>
        const CommandBlockActionResult.disabled(
          CommandBlockActionDisabledReason.emptyCommand,
        ),
    };
  }
}

bool _requiresOutputRange(CommandBlockAction action) {
  return switch (action) {
    CommandBlockAction.copyCommand ||
    CommandBlockAction.reInput ||
    CommandBlockAction.rerun => false,
    CommandBlockAction.copyOutput ||
    CommandBlockAction.copyBoth ||
    CommandBlockAction.searchWithinBlock ||
    CommandBlockAction.saveOutput ||
    CommandBlockAction.openReviewEntrypoint => true,
  };
}

bool _requiresTerminalFrame(CommandBlockAction action) {
  return switch (action) {
    CommandBlockAction.saveOutput ||
    CommandBlockAction.openReviewEntrypoint => true,
    CommandBlockAction.copyCommand ||
    CommandBlockAction.copyOutput ||
    CommandBlockAction.copyBoth ||
    CommandBlockAction.reInput ||
    CommandBlockAction.rerun ||
    CommandBlockAction.searchWithinBlock => false,
  };
}

CommandBlockActionDisabledReason _disabledReasonForTerminalIntent(
  CommandSearchTerminalIntent intent,
) {
  return switch (intent.reason) {
    CommandSearchTerminalIntentReason.readOnly =>
      CommandBlockActionDisabledReason.readOnly,
    CommandSearchTerminalIntentReason.emptySelection ||
    null => CommandBlockActionDisabledReason.emptyCommand,
    CommandSearchTerminalIntentReason.multilineRequiresPastePolicy =>
      CommandBlockActionDisabledReason.requiresPastePolicy,
  };
}
