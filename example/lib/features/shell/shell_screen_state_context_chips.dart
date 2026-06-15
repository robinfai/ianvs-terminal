part of 'shell_screen.dart';

extension _ShellScreenStateContextChips on _ShellScreenState {
  ContextChipState _contextChipsForPane({
    required SessionState sessionState,
    required TerminalPane pane,
    required TerminalProfile? profile,
  }) {
    return _commandCenterContextWiring.chipsForSession(
      _commandCenterRuntime,
      sessionId: pane.sessionId,
      shellIntegrationCwd: pane.shellIntegration.currentDirectory,
      profileId: profile?.id ?? pane.profileId,
      profileName: profile?.name,
      readOnly: _isSessionReadOnly(pane.sessionId),
      blockRangeState: _commandCenterRuntime.blockRangeState(
        rangesByInvocationId: _commandBlockRangesForSession(
          sessionState,
          pane.sessionId,
        ),
      ),
    );
  }

  void _handleContextChipIntent({
    required SessionController sessionController,
    required SessionState sessionState,
    required String sessionId,
    required ContextChipClickIntent intent,
  }) {
    switch (intent.kind) {
      case ContextChipIntentKind.none:
        return;
      case ContextChipIntentKind.revealCwd:
        _showContextChipMessage('CWD: ${intent.cwd ?? 'Unavailable'}');
      case ContextChipIntentKind.openProfile:
        unawaited(_openProfilesSheet(sessionController, sessionState));
      case ContextChipIntentKind.showShellHookDiagnostics:
        _showContextChipMessage(_shellHookDiagnosticsMessage(intent));
      case ContextChipIntentKind.navigateToBlock:
        _navigateToContextChipBlock(
          sessionState: sessionState,
          sessionId: sessionId,
          blockId: intent.blockId,
        );
      case ContextChipIntentKind.openBlockActions:
        _showContextChipMessage('Command block actions are not ready yet.');
      case ContextChipIntentKind.toggleReadOnly:
        _toggleReadOnlySession(sessionId);
    }
  }

  void _navigateToContextChipBlock({
    required SessionState sessionState,
    required String sessionId,
    required String? blockId,
  }) {
    if (blockId == null) {
      _showContextChipMessage('Command block is unavailable.');
      return;
    }
    final rangeState = _commandCenterRuntime.blockRangeState(
      rangesByInvocationId: _commandBlockRangesForSession(
        sessionState,
        sessionId,
      ),
    );
    final block = rangeState.blockByInvocationId(blockId);
    final targetRow = block?.inputRange?.startRow;
    if (targetRow == null) {
      _showContextChipMessage('Command block range is unavailable.');
      return;
    }
    ref
        .read(terminalRuntimeControllerProvider)
        .scrollViewportTo(sessionId, targetRow);
    _focusSession(sessionId);
  }

  String _shellHookDiagnosticsMessage(ContextChipClickIntent intent) {
    return switch (intent.unavailableReason) {
      null => 'Shell integration is active.',
      CommandCenterUnavailableReason.shellIntegrationDisabled =>
        'Shell integration is disabled.',
      CommandCenterUnavailableReason.unknownHook =>
        'Shell hook payload is unknown.',
      CommandCenterUnavailableReason.missingCommand =>
        'Shell hook command is missing.',
      CommandCenterUnavailableReason.missingCwd => 'CWD is unavailable.',
      CommandCenterUnavailableReason.missingLifecycle =>
        'Command lifecycle is unavailable.',
      CommandCenterUnavailableReason.missingOutputRange =>
        'Command output range is unavailable.',
      CommandCenterUnavailableReason.outOfOrderLifecycle =>
        'Command lifecycle event order is incomplete.',
    };
  }

  void _showContextChipMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
