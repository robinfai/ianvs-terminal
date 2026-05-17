import '../productivity/shell_productivity_models.dart';
import 'shell_action_registry.dart';

enum ShellActionDisabledReason {
  missingActiveSession,
  shellIntegrationUnavailable,
  readOnly,
  missingCommandOutput,
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
  }) {
    final descriptor = ShellActionRegistry.actions[actionId];
    if (descriptor?.requiresActiveSession == true && !hasActiveSession) {
      return ShellActionAvailability.disabled(
        ShellActionDisabledReason.missingActiveSession,
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
