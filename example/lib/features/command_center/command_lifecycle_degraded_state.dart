import 'shell_hook_lifecycle_adapter.dart';

enum CommandCenterCapability {
  historySearch,
  commandBlocks,
  stickyHeader,
  reviewEntrypoints,
  copyOutput,
}

enum CommandCenterAction {
  openHistorySearch,
  showCommandBlocks,
  showStickyHeader,
  openReviewEntrypoints,
  copyOutput,
}

enum CommandCenterUnavailableReason {
  shellIntegrationDisabled,
  unknownHook,
  missingCommand,
  missingCwd,
  missingLifecycle,
  missingOutputRange,
  outOfOrderLifecycle,
}

enum CommandCenterDisabledActionReason {
  shellIntegrationDisabled,
  unknownHook,
  missingCommand,
  missingCwd,
  missingLifecycle,
  missingOutputRange,
  outOfOrderLifecycle,
}

class CommandCenterCapabilityState {
  const CommandCenterCapabilityState._({
    required this.enabled,
    required this.limited,
    required this.unavailable,
    this.reason,
  });

  const CommandCenterCapabilityState.enabled()
    : this._(enabled: true, limited: false, unavailable: false);

  const CommandCenterCapabilityState.limited(
    CommandCenterUnavailableReason reason,
  ) : this._(enabled: true, limited: true, unavailable: false, reason: reason);

  const CommandCenterCapabilityState.unavailable(
    CommandCenterUnavailableReason reason,
  ) : this._(enabled: false, limited: false, unavailable: true, reason: reason);

  final bool enabled;
  final bool limited;
  final bool unavailable;
  final CommandCenterUnavailableReason? reason;
}

class CommandCenterActionAvailability {
  const CommandCenterActionAvailability._({
    required this.enabled,
    this.disabledReason,
  });

  static const enabledAction = CommandCenterActionAvailability._(enabled: true);

  static CommandCenterActionAvailability disabled(
    CommandCenterDisabledActionReason reason,
  ) {
    return CommandCenterActionAvailability._(
      enabled: false,
      disabledReason: reason,
    );
  }

  final bool enabled;
  final CommandCenterDisabledActionReason? disabledReason;
}

class CommandLifecycleDegradedState {
  const CommandLifecycleDegradedState({
    required this.shellIntegrationEnabled,
    this.hasHistory = false,
    this.lifecycleAvailable = true,
    this.hasOutputRange = false,
    this.sessionReasons = const <String, CommandCenterUnavailableReason>{},
    this.globalReason,
  });

  final bool shellIntegrationEnabled;
  final bool hasHistory;
  final bool lifecycleAvailable;
  final bool hasOutputRange;
  final Map<String, CommandCenterUnavailableReason> sessionReasons;
  final CommandCenterUnavailableReason? globalReason;

  CommandCenterCapabilityState capability(
    CommandCenterCapability capability, {
    String? sessionId,
  }) {
    final reason = _unavailableReasonFor(capability, sessionId: sessionId);
    if (reason == null) {
      return const CommandCenterCapabilityState.enabled();
    }
    if (capability == CommandCenterCapability.historySearch && hasHistory) {
      return CommandCenterCapabilityState.limited(reason);
    }
    return CommandCenterCapabilityState.unavailable(reason);
  }

  CommandCenterActionAvailability action(
    CommandCenterAction action, {
    String? sessionId,
  }) {
    final capabilityState = capability(
      _capabilityForAction(action),
      sessionId: sessionId,
    );
    if (capabilityState.enabled) {
      return CommandCenterActionAvailability.enabledAction;
    }
    return CommandCenterActionAvailability.disabled(
      _disabledActionReasonFor(capabilityState.reason!),
    );
  }

  CommandCenterUnavailableReason? _unavailableReasonFor(
    CommandCenterCapability capability, {
    String? sessionId,
  }) {
    if (!shellIntegrationEnabled) {
      return CommandCenterUnavailableReason.shellIntegrationDisabled;
    }
    final sessionReason = sessionId == null ? null : sessionReasons[sessionId];
    if (sessionReason != null) {
      return sessionReason;
    }
    if (globalReason != null) {
      return globalReason;
    }
    if (_requiresOutputRange(capability) && !hasOutputRange) {
      return CommandCenterUnavailableReason.missingOutputRange;
    }
    if (_requiresLifecycle(capability) && !lifecycleAvailable) {
      return CommandCenterUnavailableReason.missingLifecycle;
    }
    return null;
  }
}

CommandCenterUnavailableReason commandCenterUnavailableReasonForIgnoredHook(
  ShellHookLifecycleIgnoredReason reason,
) {
  return switch (reason) {
    ShellHookLifecycleIgnoredReason.unknownHook =>
      CommandCenterUnavailableReason.unknownHook,
    ShellHookLifecycleIgnoredReason.missingCommand =>
      CommandCenterUnavailableReason.missingCommand,
    ShellHookLifecycleIgnoredReason.missingCwd =>
      CommandCenterUnavailableReason.missingCwd,
  };
}

CommandCenterCapability _capabilityForAction(CommandCenterAction action) {
  return switch (action) {
    CommandCenterAction.openHistorySearch =>
      CommandCenterCapability.historySearch,
    CommandCenterAction.showCommandBlocks =>
      CommandCenterCapability.commandBlocks,
    CommandCenterAction.showStickyHeader =>
      CommandCenterCapability.stickyHeader,
    CommandCenterAction.openReviewEntrypoints =>
      CommandCenterCapability.reviewEntrypoints,
    CommandCenterAction.copyOutput => CommandCenterCapability.copyOutput,
  };
}

bool _requiresLifecycle(CommandCenterCapability capability) {
  return switch (capability) {
    CommandCenterCapability.historySearch => false,
    CommandCenterCapability.commandBlocks ||
    CommandCenterCapability.stickyHeader ||
    CommandCenterCapability.reviewEntrypoints ||
    CommandCenterCapability.copyOutput => true,
  };
}

bool _requiresOutputRange(CommandCenterCapability capability) {
  return switch (capability) {
    CommandCenterCapability.historySearch => false,
    CommandCenterCapability.commandBlocks ||
    CommandCenterCapability.stickyHeader ||
    CommandCenterCapability.reviewEntrypoints ||
    CommandCenterCapability.copyOutput => true,
  };
}

CommandCenterDisabledActionReason _disabledActionReasonFor(
  CommandCenterUnavailableReason reason,
) {
  return switch (reason) {
    CommandCenterUnavailableReason.shellIntegrationDisabled =>
      CommandCenterDisabledActionReason.shellIntegrationDisabled,
    CommandCenterUnavailableReason.unknownHook =>
      CommandCenterDisabledActionReason.unknownHook,
    CommandCenterUnavailableReason.missingCommand =>
      CommandCenterDisabledActionReason.missingCommand,
    CommandCenterUnavailableReason.missingCwd =>
      CommandCenterDisabledActionReason.missingCwd,
    CommandCenterUnavailableReason.missingLifecycle =>
      CommandCenterDisabledActionReason.missingLifecycle,
    CommandCenterUnavailableReason.missingOutputRange =>
      CommandCenterDisabledActionReason.missingOutputRange,
    CommandCenterUnavailableReason.outOfOrderLifecycle =>
      CommandCenterDisabledActionReason.outOfOrderLifecycle,
  };
}
