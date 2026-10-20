part of 'shell_screen.dart';

extension _ShellScreenMobileSessions on _ShellScreenState {
  String? _bufferClearUnavailableReason(String sessionId) {
    if (_sessionSourceInUse(sessionId)) {
      return context.l10n.mobileSessionReferencedByAi;
    }
    if (_paneForSession(
          ref.read(sessionControllerProvider),
          sessionId,
        )?.isExited ==
        true) {
      return context.l10n.mobileSessionDisconnectedDetail;
    }
    return null;
  }

  Map<String, String> _liveMobileReconnections(SessionState state) => {
    for (final source in state.reconnectionTargets.keys)
      if (state.liveReconnectionFor(source) case final String target)
        source: target,
  };

  bool _sessionSourceInUse(
    String sessionId, {
    Set<String> closingSessions = const {},
  }) =>
      _terminalReconnects.containsKey(sessionId) ||
      _aiSessions.entries.any(
        (entry) =>
            entry.key != sessionId &&
            !closingSessions.contains(entry.key) &&
            entry.value.retainsSource(sessionId),
      );

  Set<String> _protectedMobileSessionIds(SessionState state) => {
    for (final tab in state.tabs)
      for (final pane in tab.effectivePanes)
        if (_sessionSourceInUse(pane.sessionId)) pane.sessionId,
  };

  Future<String?> _reconnectMobileSession(String sessionId) async {
    final next = await _reconnectTerminalSession(sessionId);
    if (!mounted) return null;
    if (next != null && _sessionExists(next)) {
      _activateSession(ref.read(sessionControllerProvider.notifier), next);
    } else if (_sessionExists(sessionId)) {
      _showShellSnackBar(context.l10n.mobileSessionReconnectFailed);
    }
    return next;
  }

  Future<void> _closeMobileSession(String sessionId) async {
    final state = ref.read(sessionControllerProvider);
    if (_paneForSession(state, sessionId) == null) return;
    await _closeSessionAfterRecordingGate(
      ref.read(sessionControllerProvider.notifier),
      state,
      sessionId,
    );
  }

  Future<void> _clearDisconnectedMobileSessions() async {
    if (_clearingDisconnectedSessions) return;
    _clearingDisconnectedSessions = true;
    try {
      // Newer AI owners are closed before the old output they reference. An
      // owner that is still running is never included in this operation.
      final state = ref.read(sessionControllerProvider);
      final candidates = state.sessionIdsInCloseOrder(
        state.tabs
            .expand((tab) => tab.effectivePanes)
            .where((pane) => pane.isExited)
            .map((pane) => pane.sessionId)
            .toList()
            .reversed,
      );
      for (final id in candidates) {
        if (!mounted) return;
        final pane = _paneForSession(ref.read(sessionControllerProvider), id);
        if (pane?.isExited != true || _sessionSourceInUse(id)) continue;
        await _closeMobileSession(id);
      }
      if (!mounted) return;
      if (ref
          .read(sessionControllerProvider)
          .tabs
          .expand((tab) => tab.effectivePanes)
          .any((pane) => pane.isExited)) {
        _showShellSnackBar(context.l10n.mobileSessionsClearPartial);
      }
    } finally {
      _clearingDisconnectedSessions = false;
    }
  }
}
