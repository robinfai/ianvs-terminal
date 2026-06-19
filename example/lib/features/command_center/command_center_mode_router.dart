import '../agent_center/agent_mode.dart';

export '../agent_center/agent_mode.dart'
    show AppInputMode, InputOwner, InputRoutingState;

const defaultCommandCenterEnabledModes = <CommandCenterMode>{
  CommandCenterMode.terminal,
  CommandCenterMode.commandBar,
  CommandCenterMode.commandSearch,
  CommandCenterMode.actionSearch,
  CommandCenterMode.savedCommand,
  CommandCenterMode.agentConversation,
  CommandCenterMode.agentInlineAsk,
  CommandCenterMode.agentCommandReview,
};

enum CommandCenterMode {
  terminal,
  commandBar,
  commandSearch,
  actionSearch,
  savedCommand,
  agentConversation,
  agentInlineAsk,
  agentCommandReview,
}

enum CommandCenterModeRequestKind { textInput, open, shortcut, cancel }

enum CommandCenterModeRequestSource {
  ordinaryText,
  keyboardShortcut,
  explicitEntry,
}

enum CommandCenterModeShortcut {
  commandBar,
  commandSearch,
  actionSearch,
  savedCommand,
  agentConversation,
  agentInlineAsk,
  cancel,
  unknown,
}

enum CommandCenterRouteDisposition { passThrough, consumed, disabled }

enum CommandCenterRouteReason {
  terminalFirst,
  openedExplicitMode,
  cancelledToTerminal,
  activeModeOwnsInput,
  disabledMode,
  noActiveModeToCancel,
  commandReviewCancelledToAgent,
}

enum CommandCenterModeDisabledReason { disabled }

class CommandCenterModeState {
  const CommandCenterModeState({
    this.mode = CommandCenterMode.terminal,
    this.enabledModes = defaultCommandCenterEnabledModes,
    this.activeTerminalSessionId,
    this.activeAgentConversationId,
    this.autoDetectionEnabled = false,
  });

  final CommandCenterMode mode;
  final Set<CommandCenterMode> enabledModes;
  final String? activeTerminalSessionId;
  final String? activeAgentConversationId;
  final bool autoDetectionEnabled;

  AppInputMode get appInputMode => _appInputModeForCommandCenterMode(mode);

  InputOwner get inputOwner => inputOwnerForMode(appInputMode);

  bool get terminalOwnsInput => inputOwner == InputOwner.terminalPty;

  InputRoutingState get inputRoutingState {
    return InputRoutingState(
      mode: appInputMode,
      activeTerminalSessionId: activeTerminalSessionId,
      activeAgentConversationId: activeAgentConversationId,
      autoDetectionEnabled: autoDetectionEnabled,
    );
  }

  bool isEnabled(CommandCenterMode mode) {
    return enabledModes.contains(mode);
  }

  CommandCenterModeState copyWith({
    CommandCenterMode? mode,
    Set<CommandCenterMode>? enabledModes,
    String? activeTerminalSessionId,
    String? activeAgentConversationId,
    bool? autoDetectionEnabled,
  }) {
    return CommandCenterModeState(
      mode: mode ?? this.mode,
      enabledModes: enabledModes ?? this.enabledModes,
      activeTerminalSessionId:
          activeTerminalSessionId ?? this.activeTerminalSessionId,
      activeAgentConversationId:
          activeAgentConversationId ?? this.activeAgentConversationId,
      autoDetectionEnabled: autoDetectionEnabled ?? this.autoDetectionEnabled,
    );
  }
}

class CommandCenterModeRequest {
  const CommandCenterModeRequest._({
    required this.kind,
    required this.source,
    this.text,
    this.mode,
    this.shortcut,
  });

  const CommandCenterModeRequest.textInput(String text)
    : this._(
        kind: CommandCenterModeRequestKind.textInput,
        source: CommandCenterModeRequestSource.ordinaryText,
        text: text,
      );

  const CommandCenterModeRequest.open(
    CommandCenterMode mode, {
    required CommandCenterModeRequestSource source,
  }) : this._(
         kind: CommandCenterModeRequestKind.open,
         source: source,
         mode: mode,
       );

  const CommandCenterModeRequest.shortcut(CommandCenterModeShortcut shortcut)
    : this._(
        kind: CommandCenterModeRequestKind.shortcut,
        source: CommandCenterModeRequestSource.keyboardShortcut,
        shortcut: shortcut,
      );

  const CommandCenterModeRequest.cancel()
    : this._(
        kind: CommandCenterModeRequestKind.cancel,
        source: CommandCenterModeRequestSource.keyboardShortcut,
      );

  final CommandCenterModeRequestKind kind;
  final CommandCenterModeRequestSource source;
  final String? text;
  final CommandCenterMode? mode;
  final CommandCenterModeShortcut? shortcut;
}

class CommandCenterRouteDecision {
  const CommandCenterRouteDecision({
    required this.disposition,
    required this.previousMode,
    required this.mode,
    required this.inputOwner,
    required this.reason,
    required this.source,
    this.disabledReason,
  });

  final CommandCenterRouteDisposition disposition;
  final CommandCenterMode previousMode;
  final CommandCenterMode mode;
  final InputOwner inputOwner;
  final CommandCenterRouteReason reason;
  final CommandCenterModeRequestSource source;
  final CommandCenterModeDisabledReason? disabledReason;

  bool get consumedByCommandCenter {
    return disposition != CommandCenterRouteDisposition.passThrough;
  }

  bool get passesThroughToTerminal {
    return disposition == CommandCenterRouteDisposition.passThrough &&
        inputOwner == InputOwner.terminalPty;
  }

  bool get transitioned => previousMode != mode;
}

class CommandCenterModeRouter {
  CommandCenterModeRouter({
    CommandCenterModeState state = const CommandCenterModeState(),
  }) : state = state.isEnabled(state.mode)
           ? state
           : const CommandCenterModeState();

  CommandCenterModeState state;

  CommandCenterRouteDecision route(CommandCenterModeRequest request) {
    return switch (request.kind) {
      CommandCenterModeRequestKind.textInput => _routeTextInput(request),
      CommandCenterModeRequestKind.open => _openMode(request.mode!, request),
      CommandCenterModeRequestKind.shortcut => _routeShortcut(request),
      CommandCenterModeRequestKind.cancel => _cancel(request),
    };
  }

  CommandCenterRouteDecision _routeTextInput(CommandCenterModeRequest request) {
    if (state.terminalOwnsInput) {
      return _decision(
        disposition: CommandCenterRouteDisposition.passThrough,
        reason: CommandCenterRouteReason.terminalFirst,
        source: request.source,
      );
    }
    return _decision(
      disposition: CommandCenterRouteDisposition.consumed,
      reason: CommandCenterRouteReason.activeModeOwnsInput,
      source: request.source,
    );
  }

  CommandCenterRouteDecision _routeShortcut(CommandCenterModeRequest request) {
    final shortcut = request.shortcut;
    if (shortcut == CommandCenterModeShortcut.cancel) {
      return _cancel(request);
    }

    final mode = _modeForShortcut(shortcut);
    if (mode == null) {
      if (state.terminalOwnsInput) {
        return _decision(
          disposition: CommandCenterRouteDisposition.passThrough,
          reason: CommandCenterRouteReason.terminalFirst,
          source: request.source,
        );
      }
      return _decision(
        disposition: CommandCenterRouteDisposition.consumed,
        reason: CommandCenterRouteReason.activeModeOwnsInput,
        source: request.source,
      );
    }

    return _openMode(mode, request);
  }

  CommandCenterRouteDecision _openMode(
    CommandCenterMode mode,
    CommandCenterModeRequest request,
  ) {
    if (!state.isEnabled(mode)) {
      return _decision(
        disposition: CommandCenterRouteDisposition.disabled,
        reason: CommandCenterRouteReason.disabledMode,
        source: request.source,
        disabledReason: CommandCenterModeDisabledReason.disabled,
      );
    }

    final previousMode = state.mode;
    state = state.copyWith(mode: mode);
    return CommandCenterRouteDecision(
      disposition: CommandCenterRouteDisposition.consumed,
      previousMode: previousMode,
      mode: state.mode,
      inputOwner: state.inputOwner,
      reason: CommandCenterRouteReason.openedExplicitMode,
      source: request.source,
    );
  }

  CommandCenterRouteDecision _cancel(CommandCenterModeRequest request) {
    if (state.terminalOwnsInput) {
      return _decision(
        disposition: CommandCenterRouteDisposition.passThrough,
        reason: CommandCenterRouteReason.noActiveModeToCancel,
        source: request.source,
      );
    }

    if (state.mode == CommandCenterMode.agentCommandReview) {
      final previousMode = state.mode;
      state = state.copyWith(mode: CommandCenterMode.agentConversation);
      return CommandCenterRouteDecision(
        disposition: CommandCenterRouteDisposition.consumed,
        previousMode: previousMode,
        mode: state.mode,
        inputOwner: state.inputOwner,
        reason: CommandCenterRouteReason.commandReviewCancelledToAgent,
        source: request.source,
      );
    }

    final previousMode = state.mode;
    state = state.copyWith(mode: CommandCenterMode.terminal);
    return CommandCenterRouteDecision(
      disposition: CommandCenterRouteDisposition.consumed,
      previousMode: previousMode,
      mode: state.mode,
      inputOwner: state.inputOwner,
      reason: CommandCenterRouteReason.cancelledToTerminal,
      source: request.source,
    );
  }

  CommandCenterRouteDecision _decision({
    required CommandCenterRouteDisposition disposition,
    required CommandCenterRouteReason reason,
    required CommandCenterModeRequestSource source,
    CommandCenterModeDisabledReason? disabledReason,
  }) {
    return CommandCenterRouteDecision(
      disposition: disposition,
      previousMode: state.mode,
      mode: state.mode,
      inputOwner: state.inputOwner,
      reason: reason,
      source: source,
      disabledReason: disabledReason,
    );
  }
}

CommandCenterMode? _modeForShortcut(CommandCenterModeShortcut? shortcut) {
  return switch (shortcut) {
    CommandCenterModeShortcut.commandBar => CommandCenterMode.commandBar,
    CommandCenterModeShortcut.commandSearch => CommandCenterMode.commandSearch,
    CommandCenterModeShortcut.actionSearch => CommandCenterMode.actionSearch,
    CommandCenterModeShortcut.savedCommand => CommandCenterMode.savedCommand,
    CommandCenterModeShortcut.agentConversation =>
      CommandCenterMode.agentConversation,
    CommandCenterModeShortcut.agentInlineAsk =>
      CommandCenterMode.agentInlineAsk,
    CommandCenterModeShortcut.cancel ||
    CommandCenterModeShortcut.unknown ||
    null => null,
  };
}

AppInputMode _appInputModeForCommandCenterMode(CommandCenterMode mode) {
  return switch (mode) {
    CommandCenterMode.terminal => AppInputMode.terminal,
    CommandCenterMode.commandBar => AppInputMode.terminalCommandBar,
    CommandCenterMode.commandSearch => AppInputMode.commandSearch,
    CommandCenterMode.actionSearch => AppInputMode.actionSearch,
    CommandCenterMode.savedCommand => AppInputMode.savedCommandSearch,
    CommandCenterMode.agentConversation => AppInputMode.agentConversation,
    CommandCenterMode.agentInlineAsk => AppInputMode.agentInlineAsk,
    CommandCenterMode.agentCommandReview => AppInputMode.agentCommandReview,
  };
}
