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
              key: ValueKey(target.operationScopeId),
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
    final integration = pane?.shellIntegration;
    if (integration?.bootstrapPhase == 'checking' &&
        integration?.contextKind != 'shell')
      return null;
    final nested = integration?.sftpRoute == true;
    if (resolvedProfile == null || (!resolvedProfile.isSsh && !nested)) {
      return null;
    }
    final connection = resolvedProfile.connection;
    return SftpSessionTarget(
      sessionId: sessionId,
      profileName: resolvedProfile.name,
      contextId: integration?.hostContextId ?? integration?.contextId ?? 'root',
      host: nested
          ? (integration?.sshHost ?? connection.host)
          : connection.host,
      user: nested
          ? (integration?.sshUser ?? connection.user)
          : connection.user,
      port: nested
          ? (integration?.sshPort ?? connection.port)
          : connection.port,
    );
  }

  void _openSftpPanel(SessionState sessionState, String? sessionId) {
    final target = _sftpTargetFor(sessionState, sessionId);
    if (target == null) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    _mutateState(() {
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
    if (sessionId != null && !context.usesMobileNavigation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusSession(sessionId);
        }
      });
    }
  }
}
