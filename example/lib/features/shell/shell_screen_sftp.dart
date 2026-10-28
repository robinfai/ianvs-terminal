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
              target != null &&
              (_sftpPanelPinnedTarget == null ||
                  _sftpPanelPinnedTarget == target)
          ? SftpSidePanel(
              key: ValueKey(target.operationScopeId),
              target: target,
              dataSource: ref.watch(sftpDirectoryDataSourceProvider),
              fileActions: ref.watch(sftpFileActionsProvider),
              onClose: _closeSftpPanel,
              initialPath: _sftpPanelInitialPath,
              highlightedName: _sftpPanelHighlightedName,
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
    if (pane == null || pane.isExited) return null;
    final scope = ref
        .read(terminalRuntimeControllerProvider)
        .commandOccurrenceScopeFor(sessionId);
    if (scope == null ||
        scope.transport.kind == terminal.CommandTransportKind.replay) {
      return null;
    }
    final integration = pane.shellIntegration;
    if (integration.bootstrapPhase == 'checking' &&
        integration.contextKind != 'shell') {
      return null;
    }
    final route = integration.hostContextId ?? integration.contextId ?? 'root';
    if (route != 'root' && !integration.sftpRoute) return null;
    final nested = integration.sftpRoute && route != 'root';
    final routeLease = integration.sftpContextId;
    if (nested &&
        (routeLease == null || routeLease == route || routeLease == 'root')) {
      return null;
    }
    final remote = scope.transport.kind == terminal.CommandTransportKind.ssh;
    if (resolvedProfile == null || (!remote && !nested)) return null;
    final transport = scope.transport;
    return SftpSessionTarget(
      sessionId: sessionId,
      profileName: resolvedProfile.name,
      contextId: nested ? routeLease! : 'root',
      sessionEpoch: scope.sessionEpoch,
      host: nested ? (integration.sshHost ?? '') : (transport.host ?? ''),
      user: nested ? (integration.sshUser ?? '') : (transport.user ?? ''),
      port: nested ? (integration.sshPort ?? 22) : (transport.port ?? 22),
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
      _sftpPanelPinnedTarget = null;
      _sftpPanelInitialPath = '/';
      _sftpPanelHighlightedName = null;
    });
  }

  void _openSftpFileLocation(
    SftpSessionTarget target,
    TerminalFileLocation location,
  ) {
    final current = _sftpTargetFor(
      ref.read(sessionControllerProvider),
      target.sessionId,
    );
    if (!mounted || current != target) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _mutateState(() {
      _isSftpPanelOpen = true;
      _sftpPanelSessionId = target.sessionId;
      _sftpPanelPinnedTarget = target;
      _sftpPanelInitialPath = location.parent;
      _sftpPanelHighlightedName = location.name;
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
      _sftpPanelPinnedTarget = null;
      _sftpPanelInitialPath = '/';
      _sftpPanelHighlightedName = null;
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
