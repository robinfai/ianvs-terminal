import 'agent_mode.dart';

enum InputOwnershipRequestKind {
  textInput,
  openMode,
  escape,
  ctrlR,
  commandK,
  askAgent,
  enter,
  explicitExecute,
  insertProposal,
  executeProposal,
}

enum InputOwnershipRequestSource {
  activeSurface,
  hiddenTerminalFocus,
  keyboardShortcut,
  explicitAction,
}

enum InputOwnershipDisposition { passThrough, consumed, blocked }

class InputOwnershipRequest {
  const InputOwnershipRequest._({
    required this.kind,
    required this.source,
    this.mode,
    this.text,
  });

  const InputOwnershipRequest.textInput(
    String text, {
    InputOwnershipRequestSource source =
        InputOwnershipRequestSource.activeSurface,
  }) : this._(
         kind: InputOwnershipRequestKind.textInput,
         source: source,
         text: text,
       );

  const InputOwnershipRequest.openMode(AppInputMode mode)
    : this._(
        kind: InputOwnershipRequestKind.openMode,
        source: InputOwnershipRequestSource.explicitAction,
        mode: mode,
      );

  const InputOwnershipRequest.escape()
    : this._(
        kind: InputOwnershipRequestKind.escape,
        source: InputOwnershipRequestSource.keyboardShortcut,
      );

  const InputOwnershipRequest.ctrlR()
    : this._(
        kind: InputOwnershipRequestKind.ctrlR,
        source: InputOwnershipRequestSource.keyboardShortcut,
      );

  const InputOwnershipRequest.commandK()
    : this._(
        kind: InputOwnershipRequestKind.commandK,
        source: InputOwnershipRequestSource.keyboardShortcut,
      );

  const InputOwnershipRequest.askAgent()
    : this._(
        kind: InputOwnershipRequestKind.askAgent,
        source: InputOwnershipRequestSource.explicitAction,
      );

  const InputOwnershipRequest.enter()
    : this._(
        kind: InputOwnershipRequestKind.enter,
        source: InputOwnershipRequestSource.activeSurface,
      );

  const InputOwnershipRequest.explicitExecute()
    : this._(
        kind: InputOwnershipRequestKind.explicitExecute,
        source: InputOwnershipRequestSource.explicitAction,
      );

  const InputOwnershipRequest.insertProposal()
    : this._(
        kind: InputOwnershipRequestKind.insertProposal,
        source: InputOwnershipRequestSource.explicitAction,
      );

  const InputOwnershipRequest.executeProposal()
    : this._(
        kind: InputOwnershipRequestKind.executeProposal,
        source: InputOwnershipRequestSource.explicitAction,
      );

  final InputOwnershipRequestKind kind;
  final InputOwnershipRequestSource source;
  final AppInputMode? mode;
  final String? text;
}

class InputOwnershipDecision {
  const InputOwnershipDecision({
    required this.disposition,
    required this.previousState,
    required this.nextState,
    required this.owner,
    required this.writesToPty,
    required this.mayExecute,
    required this.reason,
    this.routesToSafetyPipeline = false,
    this.insertsCommandDraft = false,
  });

  final InputOwnershipDisposition disposition;
  final InputRoutingState previousState;
  final InputRoutingState nextState;
  final InputOwner owner;
  final bool writesToPty;
  final bool mayExecute;
  final String reason;
  final bool routesToSafetyPipeline;
  final bool insertsCommandDraft;

  bool get consumed => disposition != InputOwnershipDisposition.passThrough;
  bool get blocked => disposition == InputOwnershipDisposition.blocked;
}

class InputOwnershipRouter {
  const InputOwnershipRouter();

  InputOwnershipDecision route(
    InputRoutingState state,
    InputOwnershipRequest request, {
    bool readOnly = false,
  }) {
    if (_isHiddenTerminalTextForActiveSurface(state, request)) {
      return _decision(
        state,
        disposition: InputOwnershipDisposition.blocked,
        reason: 'hidden-terminal-focus-blocked',
      );
    }

    return switch (request.kind) {
      InputOwnershipRequestKind.textInput => _routeText(state, readOnly),
      InputOwnershipRequestKind.openMode => _openMode(state, request.mode!),
      InputOwnershipRequestKind.escape => _escape(state),
      InputOwnershipRequestKind.ctrlR => _openMode(
        state,
        AppInputMode.commandSearch,
      ),
      InputOwnershipRequestKind.commandK => _openMode(
        state,
        AppInputMode.actionSearch,
      ),
      InputOwnershipRequestKind.askAgent => _openMode(
        state,
        AppInputMode.agentConversation,
      ),
      InputOwnershipRequestKind.enter => _enter(state, readOnly),
      InputOwnershipRequestKind.explicitExecute => _explicitExecute(
        state,
        readOnly,
      ),
      InputOwnershipRequestKind.insertProposal => _insertProposal(state),
      InputOwnershipRequestKind.executeProposal => _executeProposal(
        state,
        readOnly,
      ),
    };
  }

  bool _isHiddenTerminalTextForActiveSurface(
    InputRoutingState state,
    InputOwnershipRequest request,
  ) {
    return request.kind == InputOwnershipRequestKind.textInput &&
        request.source == InputOwnershipRequestSource.hiddenTerminalFocus &&
        !state.terminalOwnsInput;
  }

  InputOwnershipDecision _routeText(InputRoutingState state, bool readOnly) {
    if (state.terminalOwnsInput) {
      if (readOnly) {
        return _decision(
          state,
          disposition: InputOwnershipDisposition.blocked,
          writesToPty: false,
          mayExecute: false,
          reason: 'read-only-blocks-terminal-text',
        );
      }
      return _decision(
        state,
        disposition: InputOwnershipDisposition.passThrough,
        writesToPty: true,
        mayExecute: true,
        reason: 'terminal-text-to-pty',
      );
    }

    return _decision(
      state,
      disposition: InputOwnershipDisposition.consumed,
      writesToPty: false,
      mayExecute: false,
      reason: 'active-surface-owns-text',
    );
  }

  InputOwnershipDecision _openMode(InputRoutingState state, AppInputMode mode) {
    final nextState = state.copyWith(mode: mode);
    return _decision(
      state,
      nextState: nextState,
      disposition: InputOwnershipDisposition.consumed,
      reason: 'opened-${mode.name}',
    );
  }

  InputOwnershipDecision _escape(InputRoutingState state) {
    final mode = state.mode == AppInputMode.agentCommandReview
        ? AppInputMode.agentConversation
        : AppInputMode.terminal;
    return _decision(
      state,
      nextState: state.copyWith(mode: mode),
      disposition: InputOwnershipDisposition.consumed,
      reason: mode == AppInputMode.agentConversation
          ? 'review-cancelled-to-agent'
          : 'cancelled-to-terminal',
    );
  }

  InputOwnershipDecision _enter(InputRoutingState state, bool readOnly) {
    return switch (state.mode) {
      AppInputMode.terminal => _routeText(state, readOnly),
      AppInputMode.terminalCommandBar => _explicitExecute(state, readOnly),
      AppInputMode.commandSearch => _decision(
        state,
        disposition: InputOwnershipDisposition.consumed,
        writesToPty: false,
        mayExecute: false,
        insertsCommandDraft: true,
        reason: 'command-search-enter-inserts-draft',
      ),
      AppInputMode.agentConversation ||
      AppInputMode.agentInlineAsk => _decision(
        state,
        disposition: InputOwnershipDisposition.consumed,
        writesToPty: false,
        mayExecute: false,
        reason: 'agent-enter-sends-message',
      ),
      AppInputMode.agentCommandReview => _decision(
        state,
        disposition: InputOwnershipDisposition.consumed,
        writesToPty: false,
        mayExecute: false,
        reason: 'review-enter-edits-proposal',
      ),
      AppInputMode.actionSearch || AppInputMode.savedCommandSearch => _decision(
        state,
        disposition: InputOwnershipDisposition.consumed,
        writesToPty: false,
        mayExecute: false,
        reason: 'active-surface-handles-enter',
      ),
    };
  }

  InputOwnershipDecision _explicitExecute(
    InputRoutingState state,
    bool readOnly,
  ) {
    if (readOnly) {
      return _decision(
        state,
        disposition: InputOwnershipDisposition.blocked,
        writesToPty: false,
        mayExecute: false,
        routesToSafetyPipeline: true,
        reason: 'read-only-blocks-execution',
      );
    }
    return _decision(
      state,
      disposition: InputOwnershipDisposition.consumed,
      writesToPty: false,
      mayExecute: true,
      routesToSafetyPipeline: true,
      reason: 'explicit-execute-through-safety',
    );
  }

  InputOwnershipDecision _insertProposal(InputRoutingState state) {
    return _decision(
      state,
      nextState: state.copyWith(mode: AppInputMode.terminalCommandBar),
      disposition: InputOwnershipDisposition.consumed,
      writesToPty: false,
      mayExecute: false,
      insertsCommandDraft: true,
      reason: 'proposal-inserted-as-draft',
    );
  }

  InputOwnershipDecision _executeProposal(
    InputRoutingState state,
    bool readOnly,
  ) {
    return _explicitExecute(state, readOnly);
  }

  InputOwnershipDecision _decision(
    InputRoutingState state, {
    InputRoutingState? nextState,
    required InputOwnershipDisposition disposition,
    bool writesToPty = false,
    bool mayExecute = false,
    bool routesToSafetyPipeline = false,
    bool insertsCommandDraft = false,
    required String reason,
  }) {
    final resolvedState = nextState ?? state;
    return InputOwnershipDecision(
      disposition: disposition,
      previousState: state,
      nextState: resolvedState,
      owner: resolvedState.owner,
      writesToPty: writesToPty,
      mayExecute: mayExecute,
      routesToSafetyPipeline: routesToSafetyPipeline,
      insertsCommandDraft: insertsCommandDraft,
      reason: reason,
    );
  }
}
