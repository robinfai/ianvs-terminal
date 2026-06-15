import '../command_center/command_block_action_reducer.dart';
import '../command_center/command_block_actions.dart';
import '../command_center/command_block_models.dart';
import '../productivity/shell_productivity_models.dart';
import 'shell_action_registry.dart';

enum ShellActionDisabledReason {
  missingActiveSession,
  shellIntegrationUnavailable,
  readOnly,
  missingCommandOutput,
  missingCommandBlock,
  missingTerminalFrame,
  pasteRequiresConfirmation,
  missingRecentDirectory,
}

extension ShellActionDisabledReasonText on ShellActionDisabledReason {
  String get title {
    return switch (this) {
      ShellActionDisabledReason.missingActiveSession => 'No active session',
      ShellActionDisabledReason.shellIntegrationUnavailable =>
        'Shell integration unavailable',
      ShellActionDisabledReason.readOnly => 'Read-only mode',
      ShellActionDisabledReason.missingCommandOutput =>
        'No command output available',
      ShellActionDisabledReason.missingCommandBlock => 'No command block',
      ShellActionDisabledReason.missingTerminalFrame => 'No terminal frame',
      ShellActionDisabledReason.pasteRequiresConfirmation =>
        'Paste confirmation required',
      ShellActionDisabledReason.missingRecentDirectory =>
        'No recent directory available',
    };
  }

  String get description {
    return switch (this) {
      ShellActionDisabledReason.missingActiveSession =>
        'Open a local shell session before using this action.',
      ShellActionDisabledReason.shellIntegrationUnavailable =>
        'Enable shell integration or wait until prompt metadata is available.',
      ShellActionDisabledReason.readOnly =>
        'Disable read-only mode before sending text or paste content.',
      ShellActionDisabledReason.missingCommandOutput =>
        'Run a command with captured output before using this action.',
      ShellActionDisabledReason.missingCommandBlock =>
        'Select a command block before using this action.',
      ShellActionDisabledReason.missingTerminalFrame =>
        'Wait for the terminal frame before using this action.',
      ShellActionDisabledReason.pasteRequiresConfirmation =>
        'Confirm the multiline paste before sending command text.',
      ShellActionDisabledReason.missingRecentDirectory =>
        'Visit a local directory before opening the recent directory list.',
    };
  }
}

class ShellActionAvailability {
  const ShellActionAvailability({required this.enabled, this.reason});

  final bool enabled;
  final ShellActionDisabledReason? reason;

  static const enabledAction = ShellActionAvailability(enabled: true);

  static ShellActionAvailability disabled(ShellActionDisabledReason reason) {
    return ShellActionAvailability(enabled: false, reason: reason);
  }
}

class ShellActionAvailabilityResolver {
  const ShellActionAvailabilityResolver._();

  static ShellActionAvailability resolve({
    required TerminalActionId actionId,
    required bool hasActiveSession,
    required ShellProductivityState productivity,
    CommandBlock? commandBlock,
    bool hasTerminalFrame = true,
    CommandBlockActionReducer commandBlockReducer =
        const CommandBlockActionReducer(),
  }) {
    final descriptor = ShellActionRegistry.actions[actionId];
    if (descriptor?.requiresActiveSession == true && !hasActiveSession) {
      return ShellActionAvailability.disabled(
        ShellActionDisabledReason.missingActiveSession,
      );
    }

    final blockAction = _commandBlockActionFor(actionId);
    if (blockAction != null) {
      if (commandBlock == null) {
        return ShellActionAvailability.disabled(
          ShellActionDisabledReason.missingCommandBlock,
        );
      }
      final result = commandBlockReducer.reduce(
        blockAction,
        commandBlock,
        readOnly: productivity.readOnly,
        hasTerminalFrame: hasTerminalFrame,
      );
      return result.enabled
          ? ShellActionAvailability.enabledAction
          : ShellActionAvailability.disabled(
              _shellDisabledReasonForBlockAction(result.disabledReason!),
            );
    }

    switch (actionId) {
      case TerminalActionId.previousPrompt:
      case TerminalActionId.nextPrompt:
        return productivity.canNavigatePrompts
            ? ShellActionAvailability.enabledAction
            : ShellActionAvailability.disabled(
                ShellActionDisabledReason.shellIntegrationUnavailable,
              );
      case TerminalActionId.selectCommandOutput:
      case TerminalActionId.copyCommandOutput:
        return productivity.canSelectCommandOutput
            ? ShellActionAvailability.enabledAction
            : ShellActionAvailability.disabled(
                ShellActionDisabledReason.missingCommandOutput,
              );
      case TerminalActionId.openRecentDirectory:
        return productivity.canOpenRecentDirectory
            ? ShellActionAvailability.enabledAction
            : ShellActionAvailability.disabled(
                ShellActionDisabledReason.missingRecentDirectory,
              );
      case TerminalActionId.paste:
      case TerminalActionId.advancedPaste:
      case TerminalActionId.pasteHistory:
        return productivity.canPaste
            ? ShellActionAvailability.enabledAction
            : ShellActionAvailability.disabled(
                ShellActionDisabledReason.readOnly,
              );
      default:
        return ShellActionAvailability.enabledAction;
    }
  }
}

CommandBlockAction? _commandBlockActionFor(TerminalActionId actionId) {
  return switch (actionId) {
    TerminalActionId.copyBlockOutput => CommandBlockAction.copyOutput,
    TerminalActionId.reInputBlockCommand => CommandBlockAction.reInput,
    TerminalActionId.rerunBlockCommand => CommandBlockAction.rerun,
    _ => null,
  };
}

ShellActionDisabledReason _shellDisabledReasonForBlockAction(
  CommandBlockActionDisabledReason reason,
) {
  return switch (reason) {
    CommandBlockActionDisabledReason.emptyCommand =>
      ShellActionDisabledReason.missingCommandOutput,
    CommandBlockActionDisabledReason.missingOutputRange =>
      ShellActionDisabledReason.missingCommandOutput,
    CommandBlockActionDisabledReason.missingTerminalFrame =>
      ShellActionDisabledReason.missingTerminalFrame,
    CommandBlockActionDisabledReason.readOnly =>
      ShellActionDisabledReason.readOnly,
    CommandBlockActionDisabledReason.requiresPastePolicy =>
      ShellActionDisabledReason.pasteRequiresConfirmation,
  };
}
