part of 'shell_screen.dart';

extension _ShellScreenStateSftp on _ShellScreenState {
  Widget _buildSftpSupportingPane({
    required SessionState sessionState,
    required String activeSessionId,
    required Widget primary,
  }) {
    final target = _sftpTargetFor(sessionState, activeSessionId);
    return SftpSupportingPaneLayout(
      onDismissSupportingPane: _closeSftpPanel,
      supportingPane:
          _isSftpPanelOpen &&
              _sftpPanelSessionId == activeSessionId &&
              target != null
          ? SftpSidePanel(
              target: target,
              dataSource: ref.watch(sftpDirectoryDataSourceProvider),
              fileActions: ref.watch(sftpFileActionsProvider),
              onClose: _closeSftpPanel,
            )
          : null,
      primary: primary,
    );
  }

  SftpSessionTarget? _sftpTargetFor(
    SessionState sessionState,
    String? sessionId, {
    TerminalProfile? profile,
  }) {
    if (sessionId == null) {
      return null;
    }
    if (!ref
        .read(terminalRuntimeControllerProvider)
        .supportsRuntimeFeature(pty.ptyRuntimeFeatureSftpDirectoryListingV1)) {
      return null;
    }
    if (!ref
        .read(terminalRuntimeControllerProvider)
        .supportsRuntimeFeature(pty.ptyRuntimeFeatureSftpFileOperationsV1)) {
      return null;
    }
    final pane = _paneForSession(sessionState, sessionId);
    final resolvedProfile =
        profile ??
        pane?.profileSnapshot ??
        (pane == null ? null : _profileForPane(pane, sessionState.profiles));
    if (resolvedProfile == null || !resolvedProfile.isSsh) {
      return null;
    }
    final connection = resolvedProfile.connection;
    return SftpSessionTarget(
      sessionId: sessionId,
      profileName: resolvedProfile.name,
      host: connection.host,
      user: connection.user,
      port: connection.port,
    );
  }

  void _openSftpPanel(SessionState sessionState, String? sessionId) {
    final target = _sftpTargetFor(sessionState, sessionId);
    if (target == null) {
      return;
    }
    _mutateState(() {
      _isToolbeltOpen = false;
      _isSftpPanelOpen = true;
      _sftpPanelSessionId = target.sessionId;
    });
  }

  void _closeSftpPanel() {
    if (!_isSftpPanelOpen && _sftpPanelSessionId == null) {
      return;
    }
    final sessionId = ref.read(sessionControllerProvider).activeSessionId;
    _mutateState(() {
      _isSftpPanelOpen = false;
      _sftpPanelSessionId = null;
    });
    if (sessionId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusSession(sessionId);
        }
      });
    }
  }
}
