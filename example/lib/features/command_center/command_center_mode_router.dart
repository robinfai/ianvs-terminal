const defaultCommandCenterEnabledModes = <CommandCenterMode>{
  CommandCenterMode.terminal,
  CommandCenterMode.commandBar,
  CommandCenterMode.commandSearch,
  CommandCenterMode.actionSearch,
  CommandCenterMode.savedCommand,
};

enum CommandCenterMode {
  terminal,
  commandBar,
  commandSearch,
  actionSearch,
  savedCommand,
  futureAgent,
}

enum CommandCenterInputOwner {
  terminal,
  commandBar,
  commandSearch,
  actionSearch,
  savedCommand,
  futureAgent,
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
  futureAgent,
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
}

enum CommandCenterModeDisabledReason { disabled }

class CommandCenterModeState {
  const CommandCenterModeState({
    this.mode = CommandCenterMode.terminal,
    this.enabledModes = defaultCommandCenterEnabledModes,
  });

  final CommandCenterMode mode;
  final Set<CommandCenterMode> enabledModes;

  CommandCenterInputOwner get inputOwner {
    return switch (mode) {
      CommandCenterMode.terminal => CommandCenterInputOwner.terminal,
      CommandCenterMode.commandBar => CommandCenterInputOwner.commandBar,
      CommandCenterMode.commandSearch => CommandCenterInputOwner.commandSearch,
      CommandCenterMode.actionSearch => CommandCenterInputOwner.actionSearch,
      CommandCenterMode.savedCommand => CommandCenterInputOwner.savedCommand,
      CommandCenterMode.futureAgent => CommandCenterInputOwner.futureAgent,
    };
  }

  bool get terminalOwnsInput => inputOwner == CommandCenterInputOwner.terminal;

  bool isEnabled(CommandCenterMode mode) {
    return enabledModes.contains(mode);
  }

  CommandCenterModeState copyWith({
    CommandCenterMode? mode,
    Set<CommandCenterMode>? enabledModes,
  }) {
    return CommandCenterModeState(
      mode: mode ?? this.mode,
      enabledModes: enabledModes ?? this.enabledModes,
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
  final CommandCenterInputOwner inputOwner;
  final CommandCenterRouteReason reason;
  final CommandCenterModeRequestSource source;
  final CommandCenterModeDisabledReason? disabledReason;

  bool get consumedByCommandCenter {
    return disposition != CommandCenterRouteDisposition.passThrough;
  }

  bool get passesThroughToTerminal {
    return disposition == CommandCenterRouteDisposition.passThrough &&
        inputOwner == CommandCenterInputOwner.terminal;
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
    CommandCenterModeShortcut.futureAgent => CommandCenterMode.futureAgent,
    CommandCenterModeShortcut.cancel ||
    CommandCenterModeShortcut.unknown ||
    null => null,
  };
}
