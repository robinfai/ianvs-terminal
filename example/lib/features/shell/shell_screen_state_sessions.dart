part of 'shell_screen.dart';

extension _ShellScreenStateSessions on _ShellScreenState {
  void _commitViewportResize(
    SessionController sessionController,
    String sessionId,
    Size viewportSize,
    double devicePixelRatio,
  ) {
    if (!mounted || !_sessionExists(sessionId)) {
      return;
    }
    sessionController.resizeSession(sessionId, viewportSize, devicePixelRatio);
    _committedViewportSizes[sessionId] = viewportSize;
    _refreshSearchMatchesAfterResize(sessionId);
  }

  bool _sessionExists(String sessionId) {
    return ref
        .read(sessionControllerProvider)
        .tabs
        .any((tab) => tab.containsSession(sessionId));
  }

  void _scheduleViewportResize(
    SessionController sessionController,
    String sessionId,
    Size viewportSize,
    double devicePixelRatio, {
    required bool immediate,
  }) {
    _scheduledViewportSizes[sessionId] = viewportSize;
    _terminalViewportDevicePixelRatios[sessionId] = devicePixelRatio;
    _viewportResizeTimer?.cancel();
    _viewportResizeTimer = null;
    if (immediate) {
      _commitViewportResize(
        sessionController,
        sessionId,
        viewportSize,
        devicePixelRatio,
      );
      return;
    }

    _viewportResizeTimer = Timer(_ShellScreenState._viewportResizeDebounce, () {
      _commitViewportResize(
        sessionController,
        sessionId,
        viewportSize,
        devicePixelRatio,
      );
    });
  }

  String get _emptyStateTitle {
    return _recentlyClosedLastSession
        ? 'Shell workspace is idle'
        : 'Start a shell workspace';
  }

  String get _emptyStateMessage {
    return _recentlyClosedLastSession
        ? 'The last session has closed. Open a new tab to keep working in the shell workspace.'
        : 'Open a new tab to start working in the shell workspace.';
  }

  FocusNode _focusNodeFor(String sessionId) {
    return _terminalFocusNodes.putIfAbsent(sessionId, () {
      final focusNode = FocusNode(debugLabel: 'shell-terminal-$sessionId');
      focusNode.addListener(
        () => _handleTerminalFocusChanged(sessionId, focusNode),
      );
      return focusNode;
    });
  }

  void _handleTerminalFocusChanged(String sessionId, FocusNode focusNode) {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId != sessionId) {
      return;
    }

    final hasFocus = focusNode.hasFocus;
    final shouldShowCue = hasFocus && _showReturningCueOnNextFocus;
    if (_activeTerminalHasFocus == hasFocus &&
        _showWorkspaceCue == shouldShowCue) {
      return;
    }

    _workspaceCueTimer?.cancel();
    _workspaceCueTimer = null;
    _mutateState(() {
      _activeTerminalHasFocus = hasFocus;
      if (hasFocus) {
        _showWorkspaceCue = shouldShowCue;
        _showReturningCueOnNextFocus = false;
      } else {
        _showWorkspaceCue = false;
      }
    });

    if (shouldShowCue) {
      _workspaceCueTimer = Timer(_ShellScreenState._workspaceCueDuration, () {
        if (!mounted || !_showWorkspaceCue) {
          return;
        }
        _mutateState(() {
          _showWorkspaceCue = false;
        });
      });
    }
  }

  void _scheduleWorkspaceCue(String title) {
    _showReturningCueOnNextFocus = true;
    _workspaceCueTitle = title;
    _recentlyClosedLastSession = false;
  }

  void _scheduleReturningCue() {
    _scheduleWorkspaceCue('Back in shell');
  }

  void _showScheduledWorkspaceCueNow() {
    if (!_showReturningCueOnNextFocus) {
      return;
    }
    _workspaceCueTimer?.cancel();
    _workspaceCueTimer = null;
    _mutateState(() {
      _showWorkspaceCue = true;
      _showReturningCueOnNextFocus = false;
    });
    _workspaceCueTimer = Timer(_ShellScreenState._workspaceCueDuration, () {
      if (!mounted || !_showWorkspaceCue) {
        return;
      }
      _mutateState(() {
        _showWorkspaceCue = false;
      });
    });
  }

  void _syncPresentationState(SessionState sessionState) {
    final currentTabCount = sessionState.tabs.length;
    if (currentTabCount == 0 && _lastObservedTabCount > 0) {
      _recentlyClosedLastSession = true;
      _activeTerminalHasFocus = false;
      _showWorkspaceCue = false;
    } else if (currentTabCount > 0 && _lastObservedTabCount == 0) {
      _recentlyClosedLastSession = false;
    }
    if (sessionState.activeSessionId == null) {
      _activeTerminalHasFocus = false;
      _showWorkspaceCue = false;
      _isSearchOpen = false;
      _isAutocompleteOpen = false;
      _isAutoComposerOpen = false;
      _isCopyModeOpen = false;
      _isToolbeltOpen = false;
      _searchQuery = '';
      _searchErrorText = null;
      _searchMatches = const [];
      _activeSearchIndex = 0;
      _autocompletePrefix = '';
      _autocompleteSuggestions = const [];
      _activeAutocompleteIndex = 0;
      _autoComposerController.clear();
      _autoComposerSuggestions = const [];
      _autoComposerCommandDrafts = const [];
      _autoComposerCommandDraftText = '';
      _autoComposerCommandDraftsLoading = false;
      _commandInputDraftsBySession.clear();
      _commandInputDraftTextBySession.clear();
      _commandInputDraftLoadingSessionIds.clear();
      _activeAutoComposerIndex = 0;
      _activeCommandCorrection = null;
      _activeCommandCorrectionSessionId = null;
      _universalInputPinnedContextChips = const [];
      _universalInputModelLabel = 'Local heuristic';
      _universalInputMode = UniversalInputMode.auto;
      _autoComposerClassification = const UniversalInputClassification.empty(
        mode: UniversalInputMode.auto,
      );
      _copyModeAnchorRow = null;
      _copyModeAnchorCol = null;
      _copyModeExtentRow = null;
      _copyModeExtentCol = null;
      _workspaceCueTimer?.cancel();
      _workspaceCueTimer = null;
    }
    _lastObservedTabCount = currentTabCount;
  }

  void _createSession(
    SessionController sessionController,
    TerminalProfile profile, {
    required bool returningToWorkspace,
  }) {
    _scheduleWorkspaceCue('New tab: ${profile.name}');
    sessionController.createSession(profile);
    _focusSession(ref.read(sessionControllerProvider).activeSessionId);
  }

  void _activateSession(SessionController sessionController, String sessionId) {
    _clearNewOutputForTab(
      _tabForSession(ref.read(sessionControllerProvider), sessionId),
    );
    if (_activeCommandCorrectionSessionId != null &&
        _activeCommandCorrectionSessionId != sessionId) {
      _activeCommandCorrection = null;
      _activeCommandCorrectionSessionId = null;
    }
    sessionController.activateSession(sessionId);
    _focusSession(sessionId);
  }

  TerminalTab? _tabForSession(SessionState sessionState, String? sessionId) {
    if (sessionId == null) {
      return null;
    }
    for (final tab in sessionState.tabs) {
      if (tab.containsSession(sessionId)) {
        return tab;
      }
    }
    return null;
  }

  bool _tabHasNewOutput(TerminalTab tab) {
    return tab.effectivePanes.any(
      (pane) => _sessionsWithNewOutput.contains(pane.sessionId),
    );
  }

  Color _tabTerminalBackgroundColor(
    BuildContext context,
    SessionState sessionState,
    TerminalTab tab,
  ) {
    final profile = _profileForPane(tab.activePane, sessionState.profiles);
    return _terminalColorsForProfile(context, profile).canvasBackground;
  }

  void _clearNewOutputForTab(TerminalTab? tab) {
    if (tab == null) {
      return;
    }
    var changed = false;
    for (final pane in tab.effectivePanes) {
      changed = _sessionsWithNewOutput.remove(pane.sessionId) || changed;
    }
    if (changed && mounted) {
      _mutateState(() {});
    }
  }

  void _clearNewOutputForSessions(Iterable<String> sessionIds) {
    for (final sessionId in sessionIds) {
      _sessionsWithNewOutput.remove(sessionId);
      _sessionsSeenForNewOutputBadges.remove(sessionId);
      _lastNewOutputFramePreviews.remove(sessionId);
    }
  }

  String? _splitAxisConflictReason(
    SessionState sessionState,
    String? sessionId,
    TerminalSplitAxis requestedAxis,
  ) {
    return null;
  }

  bool _sessionHasRenderableContent(
    SessionController sessionController,
    String sessionId,
  ) {
    final viewport = sessionController.viewportFor(sessionId);
    if (viewport.frameVersion <= 0) {
      return false;
    }
    final frame = viewport.frame;
    if (frame.inlineImages.isNotEmpty) {
      return true;
    }
    for (final row in frame.rows) {
      if (row.text.trim().isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  String? _displayedSessionIdFor(
    SessionController sessionController,
    SessionState sessionState,
    String? activeSessionId,
  ) {
    if (activeSessionId == null) {
      _lastRenderableSessionId = null;
      return null;
    }
    final activeTab = _tabForSession(sessionState, activeSessionId);
    final retainedSessionId = _lastRenderableSessionId;
    final retainedTab = _tabForSession(sessionState, retainedSessionId);
    if (activeTab != null &&
        retainedTab != null &&
        activeTab.sessionId == retainedTab.sessionId) {
      _lastRenderableSessionId = activeSessionId;
      return activeSessionId;
    }
    if (_sessionHasRenderableContent(sessionController, activeSessionId)) {
      _lastRenderableSessionId = activeSessionId;
      return activeSessionId;
    }
    if (retainedSessionId != null &&
        retainedTab != null &&
        _sessionHasRenderableContent(sessionController, retainedSessionId)) {
      return retainedSessionId;
    }
    return null;
  }

  void _scheduleRenderableSessionSwap(String sessionId) {
    if (!mounted) {
      return;
    }
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId == sessionId && _lastRenderableSessionId != sessionId) {
      _mutateState(() {});
    }
  }

  bool _focusRelativePane(
    SessionController sessionController,
    TerminalTab activeTab,
    String activeSessionId, {
    required int delta,
  }) {
    final zoomedPaneSessionId = _zoomedPaneSessionId;
    final zoomedPane = zoomedPaneSessionId == null
        ? null
        : activeTab.paneFor(zoomedPaneSessionId);
    final panes = zoomedPane == null ? activeTab.effectivePanes : [zoomedPane];
    if (panes.length < 2) {
      return false;
    }
    final activeIndex = panes.indexWhere(
      (pane) => pane.sessionId == activeSessionId,
    );
    if (activeIndex < 0) {
      return false;
    }
    final nextIndex = (activeIndex + delta) % panes.length;
    final normalizedIndex = nextIndex < 0
        ? nextIndex + panes.length
        : nextIndex;
    _scheduleWorkspaceCue('Pane ${normalizedIndex + 1} of ${panes.length}');
    _activateSession(sessionController, panes[normalizedIndex].sessionId);
    return true;
  }

  bool _growActivePane(TerminalTab activeTab, String activeSessionId) {
    if (_growActivePaneUnavailableReason(activeTab, activeSessionId) != null) {
      return false;
    }
    ref.read(sessionControllerProvider.notifier).growPane(activeSessionId);
    return true;
  }

  String? _growActivePaneUnavailableReason(
    TerminalTab activeTab,
    String activeSessionId,
  ) {
    final panes = activeTab.effectivePanes;
    if (panes.length < 2 || !activeTab.containsSession(activeSessionId)) {
      return 'Add another pane to use this action.';
    }

    if (_paneGrowthWouldShrinkSiblingTooFar(
      activeTab.effectivePaneLayout,
      activeSessionId,
    )) {
      return activeTab.splitAxis == TerminalSplitAxis.horizontal
          ? 'Another pane would become narrower than ${_ShellScreenState._minimumHorizontalPaneCols} columns.'
          : 'Another pane would become shorter than ${_ShellScreenState._minimumVerticalPaneRows} rows.';
    }

    final sessionController = ref.read(sessionControllerProvider.notifier);
    for (final pane in panes) {
      if (pane.sessionId == activeSessionId) {
        continue;
      }
      final frame = sessionController.viewportFor(pane.sessionId).frame;
      final primarySize = activeTab.splitAxis == TerminalSplitAxis.horizontal
          ? frame.viewportCols
          : frame.viewportRows;
      final minimumPrimarySize =
          activeTab.splitAxis == TerminalSplitAxis.horizontal
          ? _ShellScreenState._minimumHorizontalPaneCols
          : _ShellScreenState._minimumVerticalPaneRows;
      if (primarySize <= minimumPrimarySize) {
        return activeTab.splitAxis == TerminalSplitAxis.horizontal
            ? 'Another pane would become narrower than ${_ShellScreenState._minimumHorizontalPaneCols} columns.'
            : 'Another pane would become shorter than ${_ShellScreenState._minimumVerticalPaneRows} rows.';
      }
    }
    return null;
  }

  bool _paneGrowthWouldShrinkSiblingTooFar(
    TerminalPaneLayoutNode node,
    String activeSessionId,
  ) {
    if (node.isLeaf) {
      return false;
    }
    final first = node.first!;
    final second = node.second!;
    if (first.containsSession(activeSessionId)) {
      if (!first.isLeaf) {
        return _paneGrowthWouldShrinkSiblingTooFar(first, activeSessionId);
      }
      return 1 - (node.ratio + _ShellScreenState._paneGrowRatioStep) <
          _ShellScreenState._minimumSiblingPaneRatio;
    }
    if (second.containsSession(activeSessionId)) {
      if (!second.isLeaf) {
        return _paneGrowthWouldShrinkSiblingTooFar(second, activeSessionId);
      }
      return node.ratio - _ShellScreenState._paneGrowRatioStep <
          _ShellScreenState._minimumSiblingPaneRatio;
    }
    return false;
  }

  String? _zoomedPaneManagementUnavailableReason(TerminalTab tab) {
    final zoomedPaneSessionId = _zoomedPaneSessionId;
    if (zoomedPaneSessionId == null ||
        !tab.containsSession(zoomedPaneSessionId)) {
      return null;
    }
    return 'Unzoom the active pane to manage other panes.';
  }

  bool _isSessionReadOnly(String sessionId) {
    return _readOnlySessionIds.contains(sessionId);
  }

  String _visibleFrameText(String sessionId) {
    final frame = ref
        .read(sessionControllerProvider.notifier)
        .viewportFor(sessionId)
        .frame;
    final lines = <String>[
      for (final row in _logicalRows(frame.rows)) row.text.trimRight(),
    ];
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    return lines.join('\n');
  }

  Future<File?> _exportVisibleFrame(String sessionId) async {
    final historicalContent = ref
        .read(terminalRuntimeControllerProvider)
        .exportScrollbackText(sessionId);
    final hasHistoricalContent =
        historicalContent != null && historicalContent.trim().isNotEmpty;
    final content = hasHistoricalContent
        ? historicalContent
        : _visibleFrameText(sessionId);
    if (content.trim().isEmpty) {
      return null;
    }
    final supportDirectory = await getApplicationSupportDirectory();
    final exportDirectory = Directory(
      '${supportDirectory.path}/scrollback_exports',
    );
    final basename =
        'visible-scrollback-${DateTime.now().millisecondsSinceEpoch}';
    return LocalTerminalScrollbackExporter.write(
      directory: exportDirectory,
      basename: basename,
      export: LocalTerminalScrollbackExport(
        format: LocalTerminalExportFormat.plainText,
        content: content,
        metadata: <String, Object?>{
          'sessionId': sessionId,
          'scope': hasHistoricalContent
              ? 'historical-scrollback'
              : 'visible-frame',
          'capturedAt': DateTime.now().toIso8601String(),
        },
      ),
      policy: const LocalTerminalScrollbackExportPolicy(),
    );
  }

  Future<Directory?> _exportDiagnosticsBundle(SessionState state) async {
    final runtime = ref.read(terminalRuntimeControllerProvider);
    final seenSessionIds = <String>{};
    final exports = <terminal.TerminalDiagnosticsExport>[];
    for (final tab in state.tabs) {
      for (final pane in tab.effectivePanes) {
        final sessionId = pane.sessionId;
        if (!seenSessionIds.add(sessionId) || !runtime.hasSession(sessionId)) {
          continue;
        }
        final export = runtime.exportSessionDiagnostics(sessionId);
        if (export != null) {
          exports.add(export);
        }
      }
    }
    if (exports.isEmpty) {
      return null;
    }

    final supportDirectory = await getApplicationSupportDirectory();
    final exportDirectory = Directory(
      '${supportDirectory.path}/diagnostic_exports',
    );
    final basename = 'diagnostics-${DateTime.now().millisecondsSinceEpoch}';
    return LocalTerminalDiagnosticsExporter.write(
      directory: exportDirectory,
      basename: basename,
      exports: exports,
    );
  }

  void _toggleReadOnlySession(String sessionId) {
    _mutateState(() {
      if (!_readOnlySessionIds.add(sessionId)) {
        _readOnlySessionIds.remove(sessionId);
      }
    });
  }

  void _splitActiveSession(
    SessionController sessionController,
    TerminalProfile profile,
    TerminalSplitAxis axis,
  ) {
    final currentState = ref.read(sessionControllerProvider);
    final activeSessionId = currentState.activeSessionId;
    final conflictReason = _splitAxisConflictReason(
      currentState,
      activeSessionId,
      axis,
    );
    if (conflictReason != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(conflictReason)));
      return;
    }
    sessionController.splitActiveSession(profile, axis);
    _focusSession(ref.read(sessionControllerProvider).activeSessionId);
  }

  void _closeSession(
    SessionController sessionController,
    SessionState sessionState,
    String sessionId,
  ) {
    final closesLastSession =
        sessionState.tabs.length == 1 &&
        sessionState.tabs.single.effectivePanes.length == 1;
    if (closesLastSession) {
      _recentlyClosedLastSession = true;
    }
    _scheduledViewportSizes.remove(sessionId);
    _committedViewportSizes.remove(sessionId);
    _terminalViewportDevicePixelRatios.remove(sessionId);
    _clearNewOutputForSessions([sessionId]);
    sessionController.closeSession(sessionId);
    final nextActiveSessionId = ref
        .read(sessionControllerProvider)
        .activeSessionId;
    if (nextActiveSessionId != null) {
      _scheduleReturningCue();
      _focusSession(nextActiveSessionId);
    }
  }

  void _closeTab(
    SessionController sessionController,
    SessionState sessionState,
    String tabSessionId,
  ) {
    final closesLastTab = sessionState.tabs.length == 1;
    final closingTab = sessionState.tabs.firstWhere(
      (tab) => tab.sessionId == tabSessionId,
      orElse: () => sessionState.tabs.first,
    );
    if (closesLastTab) {
      _recentlyClosedLastSession = true;
    }
    for (final pane in closingTab.effectivePanes) {
      _scheduledViewportSizes.remove(pane.sessionId);
      _committedViewportSizes.remove(pane.sessionId);
      _terminalViewportDevicePixelRatios.remove(pane.sessionId);
    }
    _clearNewOutputForSessions(
      closingTab.effectivePanes.map((pane) => pane.sessionId),
    );
    sessionController.closeTab(tabSessionId);
    final nextActiveSessionId = ref
        .read(sessionControllerProvider)
        .activeSessionId;
    if (nextActiveSessionId != null) {
      _scheduleReturningCue();
      _focusSession(nextActiveSessionId);
    }
  }

  void _focusSession(String? sessionId) {
    if (sessionId == null) {
      return;
    }
    final focusNode = _focusNodeFor(sessionId);
    if (!focusNode.canRequestFocus) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !focusNode.canRequestFocus) {
        return;
      }
      focusNode.requestFocus();
    });
  }

  void _restoreSessionFocus({
    required String? activeSessionIdBeforeOpen,
    required String? activeSessionIdAfterClose,
  }) {
    if (activeSessionIdBeforeOpen == null ||
        activeSessionIdAfterClose != activeSessionIdBeforeOpen) {
      return;
    }
    _scheduleReturningCue();
    final focusNode = _focusNodeFor(activeSessionIdBeforeOpen);
    if (focusNode.hasFocus) {
      _showScheduledWorkspaceCueNow();
      return;
    }
    _focusSession(activeSessionIdBeforeOpen);
  }

  TerminalProfile? _profileForId(
    List<TerminalProfile> profiles,
    String? profileId,
  ) {
    if (profiles.isEmpty || profileId == null) {
      return null;
    }
    for (final profile in profiles) {
      if (profile.id == profileId) {
        return profile;
      }
    }
    return null;
  }

  TerminalProfile? _effectiveDefaultProfileFor(
    List<TerminalProfile> profiles,
    String? effectiveDefaultProfileId,
  ) {
    return _profileForId(profiles, effectiveDefaultProfileId) ??
        (profiles.isEmpty ? null : profiles.first);
  }

  TerminalProfile? _profileForPane(
    TerminalPane pane,
    List<TerminalProfile> profiles,
  ) {
    return pane.profileSnapshot ?? _profileForId(profiles, pane.profileId);
  }

  terminal.TerminalViewportColors _terminalColorsForProfile(
    BuildContext context,
    TerminalProfile? profile,
  ) {
    return resolveTerminalColors(
      context,
      profileAppearance: profile?.appearance,
    ).viewport;
  }

  String _defaultSummary(
    List<TerminalProfile> profiles,
    String? configuredDefaultProfileId,
    String? effectiveDefaultProfileId,
  ) {
    final effectiveProfile = _effectiveDefaultProfileFor(
      profiles,
      effectiveDefaultProfileId,
    );
    if (configuredDefaultProfileId == null) {
      return 'Current new-tab profile • ${effectiveProfile?.name ?? 'No profile available'}';
    }
    final configuredProfile = _profileForId(
      profiles,
      configuredDefaultProfileId,
    );
    return 'Configured default • ${configuredProfile?.name ?? effectiveProfile?.name ?? 'No profile available'}';
  }
}
