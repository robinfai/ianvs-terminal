import 'agent_intent_router.dart';

enum AppInputMode {
  terminal,
  terminalCommandBar,
  commandSearch,
  actionSearch,
  savedCommandSearch,
  agentConversation,
  agentInlineAsk,
  agentCommandReview,
}

enum InputOwner {
  terminalPty,
  terminalCommandBar,
  commandSearchOverlay,
  actionSearchOverlay,
  savedCommandSearchOverlay,
  agentConversationComposer,
  agentCommandReview,
}

class InputRoutingState {
  const InputRoutingState({
    this.mode = AppInputMode.terminal,
    InputOwner? owner,
    this.activeTerminalSessionId,
    this.activeAgentConversationId,
    this.autoDetectionEnabled = false,
    this.lastIntentDecision,
  }) : _owner = owner;

  final AppInputMode mode;
  final InputOwner? _owner;
  final String? activeTerminalSessionId;
  final String? activeAgentConversationId;
  final bool autoDetectionEnabled;
  final InputIntentDecision? lastIntentDecision;

  InputOwner get owner => _owner ?? inputOwnerForMode(mode);

  bool get terminalOwnsInput => owner == InputOwner.terminalPty;
  bool get agentOwnsInput =>
      owner == InputOwner.agentConversationComposer ||
      owner == InputOwner.agentCommandReview;

  InputRoutingState copyWith({
    AppInputMode? mode,
    InputOwner? owner,
    String? activeTerminalSessionId,
    String? activeAgentConversationId,
    bool? autoDetectionEnabled,
    InputIntentDecision? lastIntentDecision,
  }) {
    final nextMode = mode ?? this.mode;
    return InputRoutingState(
      mode: nextMode,
      owner: owner ?? inputOwnerForMode(nextMode),
      activeTerminalSessionId:
          activeTerminalSessionId ?? this.activeTerminalSessionId,
      activeAgentConversationId:
          activeAgentConversationId ?? this.activeAgentConversationId,
      autoDetectionEnabled: autoDetectionEnabled ?? this.autoDetectionEnabled,
      lastIntentDecision: lastIntentDecision ?? this.lastIntentDecision,
    );
  }
}

InputOwner inputOwnerForMode(AppInputMode mode) {
  return switch (mode) {
    AppInputMode.terminal => InputOwner.terminalPty,
    AppInputMode.terminalCommandBar => InputOwner.terminalCommandBar,
    AppInputMode.commandSearch => InputOwner.commandSearchOverlay,
    AppInputMode.actionSearch => InputOwner.actionSearchOverlay,
    AppInputMode.savedCommandSearch => InputOwner.savedCommandSearchOverlay,
    AppInputMode.agentConversation ||
    AppInputMode.agentInlineAsk => InputOwner.agentConversationComposer,
    AppInputMode.agentCommandReview => InputOwner.agentCommandReview,
  };
}
