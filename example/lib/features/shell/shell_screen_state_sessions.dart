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
    _viewportResizeTimers.remove(sessionId)?.cancel();
    if (immediate) {
      _commitViewportResize(
        sessionController,
        sessionId,
        viewportSize,
        devicePixelRatio,
      );
      return;
    }

    _viewportResizeTimers[sessionId] = Timer(
      _ShellScreenState._viewportResizeDebounce,
      () {
        _viewportResizeTimers.remove(sessionId);
        _commitViewportResize(
          sessionController,
          sessionId,
          viewportSize,
          devicePixelRatio,
        );
      },
    );
  }

  void _clearViewportMetricsForSession(String sessionId) {
    _viewportResizeTimers.remove(sessionId)?.cancel();
    _scheduledViewportSizes.remove(sessionId);
    _committedViewportSizes.remove(sessionId);
    _measuredTerminalCellSizes.remove(sessionId);
    _terminalViewportKeys.removeWhere((key, _) => key.sessionId == sessionId);
    _paneDropTargetKeys.removeWhere((key, _) => key.sessionId == sessionId);
    _terminalViewportDevicePixelRatios.remove(sessionId);
  }

  void _clearPresentationStateForSession(String sessionId) {
    _sshAuthPromptPresenter.cancelSession(sessionId);
    _sshHostKeyPromptPresenter.cancelSession(sessionId);
    _invalidateZmodemPickerRequest(sessionId);
    unawaited(_cancelOsc1337AttentionRequest(sessionId));
    _osc1337FireworksTimers.remove(sessionId)?.cancel();
    _detachTabColorViewportListener(sessionId);
    _clearViewportMetricsForSession(sessionId);
    _clearInstantReplayHistory(sessionId);

    final selectionController = _selectionControllers.remove(sessionId);
    if (selectionController != null) {
      selectionController.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        selectionController.dispose();
      });
    }

    final focusNode = _terminalFocusNodes.remove(sessionId);
    if (focusNode != null) {
      focusNode.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        focusNode.dispose();
      });
    }

    _mutateState(() {
      _readOnlySessionIds.remove(sessionId);
      _mobileTerminalFontScales.remove(sessionId);
      _mobileTerminalPinchStartScales.remove(sessionId);
      _osc1337AttentionEpochs.remove(sessionId);
      _lastOsc1337FireworksAt.remove(sessionId);
      _osc1337FireworksSerials.remove(sessionId);
      _lastActivityNotificationAt.remove(sessionId);
      _activityNotificationTrailingTimers.remove(sessionId)?.cancel();
      _lastActivityFramePreviews.remove(sessionId);
      _lastNewOutputFramePreviews.remove(sessionId);
      _triggerMatchesBySession.remove(sessionId);
      _terminalFrameSequenceBySession.remove(sessionId);
      _searchRefreshFrameSignatures.remove(sessionId);
      final searchHadSession =
          _searchMatchesBySession.containsKey(sessionId) ||
          _searchHits.any((hit) => hit.session.sessionId == sessionId);
      if (searchHadSession) {
        _searchMatchesBySession =
            Map.unmodifiable(<String, List<terminal.TerminalSearchMatch>>{
              for (final entry in _searchMatchesBySession.entries)
                if (entry.key != sessionId) entry.key: entry.value,
            });
        _searchHits = List.unmodifiable(
          _searchHits.where((hit) => hit.session.sessionId != sessionId),
        );
        _activeSearchIndex = _searchHits.isEmpty
            ? 0
            : _activeSearchIndex.clamp(0, _searchHits.length - 1);
        _lastSearchScopeSessionSignature = null;
      }
      _sessionsSeenForActivityNotifications.remove(sessionId);
      _sessionsSeenForNewOutputBadges.remove(sessionId);
      _sessionsWithNewOutput.remove(sessionId);
      _coprocessInputKeysBySession.remove(sessionId);
      final zmodem = _zmodemTransfers.remove(sessionId);
      _zmodemTransportFailureSessionIds.remove(sessionId);
      _pendingZmodemTerminalMessages.remove(sessionId);
      if (zmodem != null) {
        _zmodemAuthorizedTransferIds.remove('$sessionId:${zmodem.transferId}');
      }
      _coprocesses = <String, _ShellCoprocess>{
        for (final entry in _coprocesses.entries)
          if (entry.key != sessionId) entry.key: entry.value,
      };
      _annotations = [
        for (final annotation in _annotations)
          if (annotation.sessionId != sessionId) annotation,
      ];
      _capturedOutputEntries = [
        for (final entry in _capturedOutputEntries)
          if (entry.sessionId != sessionId) entry,
      ];
      if (_zoomedPaneSessionId == sessionId) {
        _zoomedPaneSessionId = null;
      }
      if (_lastRenderableSessionId == sessionId) {
        _lastRenderableSessionId = null;
      }
      if (_hoveredTerminalLinkSessionId == sessionId) {
        _hoveredTerminalLink = null;
        _hoveredTerminalLinkSessionId = null;
      }
      if (_copyModeSessionId == sessionId) {
        _resetCopyModeState();
      }
      if (_autocompleteSessionId == sessionId) {
        _resetAutocompleteState();
      }
      if (_autoComposerSessionId == sessionId) {
        _resetAutoComposerState(clearText: true);
      }
    });
    _syncOpenAnnotationSheet();
  }

  void _clearPresentationStateForSessions(Iterable<String> sessionIds) {
    for (final sessionId in sessionIds.toList(growable: false)) {
      _clearPresentationStateForSession(sessionId);
    }
  }

  String get _emptyStateTitle {
    return _recentlyClosedLastSession
        ? 'Shell layout is idle'
        : 'Start a shell layout';
  }

  String get _emptyStateMessage {
    return _recentlyClosedLastSession
        ? 'The last session has closed. Open a new tab to keep working in the shell layout.'
        : 'Open a new tab to start working in the shell layout.';
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
    final hasFocus = focusNode.hasFocus;
    if (activeSessionId != sessionId) {
      if (!hasFocus) {
        ref
            .read(terminalRuntimeControllerProvider)
            .setSessionFocused(sessionId, focused: false);
      }
      return;
    }
    ref
        .read(terminalRuntimeControllerProvider)
        .setSessionFocused(sessionId, focused: hasFocus);

    final shouldShowCue = hasFocus && _showReturningCueOnNextFocus;
    if (_activeTerminalHasFocus == hasFocus &&
        _showLayoutCue == shouldShowCue) {
      return;
    }

    _layoutCueTimer?.cancel();
    _layoutCueTimer = null;
    _mutateState(() {
      _activeTerminalHasFocus = hasFocus;
      if (hasFocus) {
        _showLayoutCue = shouldShowCue;
        _showReturningCueOnNextFocus = false;
      } else {
        _showLayoutCue = false;
      }
    });

    if (shouldShowCue) {
      _layoutCueTimer = Timer(_ShellScreenState._layoutCueDuration, () {
        if (!mounted || !_showLayoutCue) {
          return;
        }
        _mutateState(() {
          _showLayoutCue = false;
        });
      });
    }
  }

  void _scheduleLayoutCue(String title) {
    _showReturningCueOnNextFocus = true;
    _layoutCueTitle = title;
    _recentlyClosedLastSession = false;
  }

  void _scheduleReturningCue() {
    _scheduleLayoutCue('Back in shell');
  }

  void _showScheduledLayoutCueNow() {
    if (!_showReturningCueOnNextFocus) {
      return;
    }
    _layoutCueTimer?.cancel();
    _layoutCueTimer = null;
    _mutateState(() {
      _showLayoutCue = true;
      _showReturningCueOnNextFocus = false;
    });
    _layoutCueTimer = Timer(_ShellScreenState._layoutCueDuration, () {
      if (!mounted || !_showLayoutCue) {
        return;
      }
      _mutateState(() {
        _showLayoutCue = false;
      });
    });
  }

  void _syncPresentationState(SessionState sessionState) {
    final currentTabCount = sessionState.tabs.length;
    _syncTabColorViewportListeners(sessionState);
    _seedInactiveSessionFrameBaselines(sessionState);
    _syncZoomedPaneState(sessionState);
    _syncHoveredTerminalLinkVisibility(sessionState);
    if (currentTabCount == 0 && _lastObservedTabCount > 0) {
      _recentlyClosedLastSession = true;
      _activeTerminalHasFocus = false;
      _showLayoutCue = false;
    } else if (currentTabCount > 0 && _lastObservedTabCount == 0) {
      _recentlyClosedLastSession = false;
    }
    if (sessionState.activeSessionId == null) {
      _activeTerminalHasFocus = false;
      _showLayoutCue = false;
      _isSearchOpen = false;
      _isAutocompleteOpen = false;
      _isAutoComposerOpen = false;
      _isCopyModeOpen = false;
      _isToolbeltOpen = false;
      _searchQuery = '';
      _searchErrorText = null;
      _searchMatchesBySession = const {};
      _searchHits = const [];
      _activeSearchIndex = 0;
      _lastSearchScopeSessionSignature = null;
      _autocompletePrefix = '';
      _autocompleteSessionId = null;
      _autocompleteSuggestions = const [];
      _activeAutocompleteIndex = 0;
      _autoComposerSessionId = null;
      _autoComposerController.clear();
      _autoComposerSuggestions = const [];
      _activeAutoComposerIndex = 0;
      _resetCopyModeState();
      _layoutCueTimer?.cancel();
      _layoutCueTimer = null;
    } else {
      final copyModeSessionId = _copyModeSessionId;
      if (_isCopyModeOpen &&
          (copyModeSessionId == null ||
              copyModeSessionId != sessionState.activeSessionId)) {
        if (copyModeSessionId != null) {
          _selectionControllers[copyModeSessionId]?.clear();
        }
        _resetCopyModeState();
      }
      final autocompleteSessionId = _autocompleteSessionId;
      if (_isAutocompleteOpen &&
          (autocompleteSessionId == null ||
              autocompleteSessionId != sessionState.activeSessionId)) {
        _resetAutocompleteState();
      }
      final autoComposerSessionId = _autoComposerSessionId;
      if (_isAutoComposerOpen &&
          (autoComposerSessionId == null ||
              autoComposerSessionId != sessionState.activeSessionId)) {
        _resetAutoComposerState(clearText: true);
      }
      _syncSearchResultsForSessionScope(sessionState);
    }
    _lastObservedTabCount = currentTabCount;
  }

  void _syncTabColorViewportListeners(SessionState sessionState) {
    final sessionIds = <String>{
      for (final tab in sessionState.tabs)
        for (final pane in tab.effectivePanes) pane.sessionId,
    };
    for (final staleSessionId
        in _tabColorViewportControllers.keys
            .where((sessionId) => !sessionIds.contains(sessionId))
            .toList(growable: false)) {
      _detachTabColorViewportListener(staleSessionId);
    }

    final sessionController = ref.read(sessionControllerProvider.notifier);
    for (final sessionId in sessionIds) {
      final viewport = sessionController.viewportFor(sessionId);
      if (identical(_tabColorViewportControllers[sessionId], viewport)) {
        continue;
      }
      _detachTabColorViewportListener(sessionId);
      _lastTabColors[sessionId] = viewport.frame.tabColor;
      void listener() {
        final nextColor = viewport.frame.tabColor;
        if (_lastTabColors[sessionId] == nextColor) {
          return;
        }
        _lastTabColors[sessionId] = nextColor;
        if (mounted) {
          _mutateState(() {});
        }
      }

      _tabColorViewportControllers[sessionId] = viewport;
      _tabColorViewportListeners[sessionId] = listener;
      viewport.addListener(listener);
    }
  }

  void _detachTabColorViewportListener(String sessionId) {
    final viewport = _tabColorViewportControllers.remove(sessionId);
    final listener = _tabColorViewportListeners.remove(sessionId);
    if (viewport != null && listener != null) {
      viewport.removeListener(listener);
    }
    _lastTabColors.remove(sessionId);
  }

  void _seedInactiveSessionFrameBaselines(SessionState sessionState) {
    final previousActiveSessionId = _lastObservedActiveSessionId;
    final activeSessionId = sessionState.activeSessionId;
    _lastObservedActiveSessionId = activeSessionId;
    if (previousActiveSessionId != activeSessionId) {
      unawaited(_osc72DragDropController.setActiveSession(activeSessionId));
    }
    if (previousActiveSessionId == null ||
        previousActiveSessionId == activeSessionId ||
        !sessionState.tabs.any(
          (tab) => tab.containsSession(previousActiveSessionId),
        )) {
      return;
    }

    final frame = ref
        .read(sessionControllerProvider.notifier)
        .viewportFor(previousActiveSessionId)
        .frame;
    final preview = _framePreview(frame);
    _sessionsSeenForActivityNotifications.add(previousActiveSessionId);
    _lastActivityFramePreviews[previousActiveSessionId] = preview;
    _sessionsSeenForNewOutputBadges.add(previousActiveSessionId);
    _lastNewOutputFramePreviews[previousActiveSessionId] = preview;
  }

  void _syncHoveredTerminalLinkVisibility(SessionState sessionState) {
    final sessionId = _hoveredTerminalLinkSessionId;
    if (sessionId == null) {
      return;
    }
    if (_sessionIsVisibleInLayout(sessionState, sessionId)) {
      return;
    }
    _hoveredTerminalLink = null;
    _hoveredTerminalLinkSessionId = null;
  }

  bool _sessionIsVisibleInLayout(SessionState sessionState, String sessionId) {
    final activeSessionId = sessionState.activeSessionId;
    if (activeSessionId == null) {
      return false;
    }
    final activeTab = _tabForSession(sessionState, activeSessionId);
    if (activeTab == null || !activeTab.containsSession(sessionId)) {
      return false;
    }
    final zoomedPaneSessionId = _zoomedPaneSessionId;
    if (zoomedPaneSessionId != null &&
        activeTab.containsSession(zoomedPaneSessionId)) {
      return sessionId == zoomedPaneSessionId;
    }
    return true;
  }

  void _syncZoomedPaneState(SessionState sessionState) {
    final zoomedPaneSessionId = _zoomedPaneSessionId;
    if (zoomedPaneSessionId == null) {
      return;
    }

    final zoomedTab = _tabForSession(sessionState, zoomedPaneSessionId);
    if (zoomedTab == null || zoomedTab.effectivePanes.length < 2) {
      _zoomedPaneSessionId = null;
    }
  }

  void _createSession(
    SessionController sessionController,
    TerminalProfile profile, {
    required bool returningToLayout,
  }) {
    if (returningToLayout) {
      _scheduleReturningCue();
    }
    sessionController.createSession(profile);
    _focusSession(ref.read(sessionControllerProvider).activeSessionId);
  }

  void _activateSession(
    SessionController sessionController,
    String sessionId, {
    bool requestFocus = true,
  }) {
    final sessionState = ref.read(sessionControllerProvider);
    final targetTab = _tabForSession(sessionState, sessionId);
    final activeTab = _tabForSession(
      sessionState,
      sessionState.activeSessionId,
    );
    if (targetTab != null &&
        activeTab != null &&
        targetTab.sessionId == activeTab.sessionId) {
      _clearNewOutputForSession(sessionId);
    } else {
      _clearNewOutputForTab(targetTab);
    }
    _syncZoomedPaneForActivation(targetTab, sessionId);
    sessionController.activateSession(sessionId);
    if (requestFocus) {
      _focusSession(sessionId);
    }
  }

  void _syncZoomedPaneForActivation(TerminalTab? targetTab, String sessionId) {
    final zoomedPaneSessionId = _zoomedPaneSessionId;
    if (targetTab == null ||
        zoomedPaneSessionId == null ||
        zoomedPaneSessionId == sessionId ||
        !targetTab.containsSession(zoomedPaneSessionId)) {
      return;
    }

    _mutateState(() {
      _zoomedPaneSessionId = sessionId;
    });
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

  List<TerminalPane> _tabNewOutputPanes(TerminalTab tab) {
    final panes = tab.effectivePanes
        .where((pane) => _sessionsWithNewOutput.contains(pane.sessionId))
        .toList(growable: false);
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId == null || panes.length < 2) {
      return panes;
    }
    return <TerminalPane>[
      for (final pane in panes)
        if (pane.sessionId != activeSessionId) pane,
      for (final pane in panes)
        if (pane.sessionId == activeSessionId) pane,
    ];
  }

  String _tabNewOutputTooltip(TerminalTab tab) {
    final panes = _tabNewOutputPanes(tab);
    if (panes.isEmpty || tab.effectivePanes.length < 2) {
      return 'New output';
    }
    final focusHint = panes.length == 1
        ? 'Click to focus this pane.'
        : 'Click to focus the first pane with new output.';
    return [
      if (panes.length == 1)
        'New output in a split pane.'
      else
        'New output in ${panes.length} split panes.',
      for (final pane in panes) _terminalPaneContextLine(pane.sessionId),
      focusHint,
    ].join('\n');
  }

  String _hiddenTabsNewOutputTooltip(Iterable<TerminalTab> tabs) {
    final targets = _hiddenTabsNewOutputTargets(tabs);
    if (targets.isEmpty) {
      return 'Hidden tabs have new output';
    }
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (targets.length == 1) {
      final target = targets.single;
      final needsFocus = target.pane.sessionId != activeSessionId;
      return [
        'New output in a hidden tab.',
        'Tab: ${_shellTabDisplayTitle(target.tab)} (${target.tab.sessionId})',
        _terminalPaneContextLine(target.pane.sessionId),
        if (needsFocus)
          'Click to focus this pane.'
        else
          'Pane already focused.',
      ].join('\n');
    }
    final hasFocusableTarget = targets.any(
      (target) => target.pane.sessionId != activeSessionId,
    );
    return [
      'New output in ${targets.length} hidden panes.',
      for (final target in targets)
        '${_shellTabDisplayTitle(target.tab)} (${target.tab.sessionId}) - '
            '${_terminalPaneContextLine(target.pane.sessionId)}',
      if (hasFocusableTarget)
        'Click to focus the first pane with new output.'
      else
        'Pane already focused.',
    ].join('\n');
  }

  String? _hiddenTabsNewOutputPaneSessionId(Iterable<TerminalTab> tabs) {
    final targets = _hiddenTabsNewOutputTargets(tabs);
    return targets.isEmpty ? null : targets.first.pane.sessionId;
  }

  List<_ShellHiddenNewOutputTarget> _hiddenTabsNewOutputTargets(
    Iterable<TerminalTab> tabs,
  ) {
    final targets = <_ShellHiddenNewOutputTarget>[];
    for (final tab in tabs) {
      for (final pane in _tabNewOutputPanes(tab)) {
        targets.add(_ShellHiddenNewOutputTarget(tab: tab, pane: pane));
      }
    }
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId == null || targets.length < 2) {
      return targets;
    }
    return <_ShellHiddenNewOutputTarget>[
      for (final target in targets)
        if (target.pane.sessionId != activeSessionId) target,
      for (final target in targets)
        if (target.pane.sessionId == activeSessionId) target,
    ];
  }

  String? _tabNewOutputPaneSessionId(TerminalTab tab) {
    if (tab.effectivePanes.length < 2) {
      return null;
    }
    final panes = _tabNewOutputPanes(tab);
    return panes.isEmpty ? null : panes.first.sessionId;
  }

  Color _tabTerminalBackgroundColor(
    BuildContext context,
    SessionState sessionState,
    TerminalTab tab,
  ) {
    final profile = _profileForPane(tab.activePane, sessionState.profiles);
    return _terminalColorsForProfile(context, profile).canvasBackground;
  }

  Color? _tabProfileColor(SessionState sessionState, TerminalTab tab) {
    final dynamicColor = ref
        .read(sessionControllerProvider.notifier)
        .viewportFor(tab.activePane.sessionId)
        .frame
        .tabColor;
    if (dynamicColor != null) {
      return dynamicColor;
    }
    final profile = _profileForPane(tab.activePane, sessionState.profiles);
    return terminalViewportColorFromHex(profile?.appearance.colors.tab);
  }

  void _clearNewOutputForTab(TerminalTab? tab) {
    if (tab == null) {
      return;
    }
    var changed = false;
    for (final pane in tab.effectivePanes) {
      changed =
          _clearNewOutputForSession(pane.sessionId, notify: false) || changed;
    }
    if (changed && mounted) {
      _mutateState(() {});
    }
  }

  bool _clearNewOutputForSession(String sessionId, {bool notify = true}) {
    final changed = _sessionsWithNewOutput.remove(sessionId);
    if (changed && notify && mounted) {
      _mutateState(() {});
    }
    return changed;
  }

  String? _splitAxisConflictReason(
    SessionState sessionState,
    String? sessionId,
    TerminalSplitAxis requestedAxis,
  ) {
    if (sessionId == null) {
      return 'No active pane is available.';
    }
    final tab = _tabForSession(sessionState, sessionId);
    if (tab == null || tab.paneFor(sessionId) == null) {
      return 'No active pane is available.';
    }
    final frame = ref
        .read(sessionControllerProvider.notifier)
        .viewportFor(sessionId)
        .frame;
    final primarySize = requestedAxis == TerminalSplitAxis.horizontal
        ? frame.viewportCols
        : frame.viewportRows;
    if (primarySize <= 0) {
      return null;
    }
    final minimumPrimarySize = _minimumPanePrimaryCells(requestedAxis);
    if (primarySize < minimumPrimarySize * 2) {
      return _minimumPaneSizeConflictReason(requestedAxis);
    }
    return null;
  }

  int _minimumPanePrimaryCells(TerminalSplitAxis axis) {
    return axis == TerminalSplitAxis.horizontal
        ? _ShellScreenState._minimumHorizontalPaneCols
        : _ShellScreenState._minimumVerticalPaneRows;
  }

  String _minimumPaneSizeConflictReason(TerminalSplitAxis axis) {
    return axis == TerminalSplitAxis.horizontal
        ? 'Another pane would become narrower than ${_ShellScreenState._minimumHorizontalPaneCols} columns.'
        : 'Another pane would become shorter than ${_ShellScreenState._minimumVerticalPaneRows} rows.';
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
    final panes = activeTab.effectivePanes;
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
    _scheduleLayoutCue('Pane ${normalizedIndex + 1} of ${panes.length}');
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
        return _minimumPaneSizeConflictReason(activeTab.splitAxis);
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
    return ref.read(referenceDemoModeProvider) ||
        _readOnlySessionIds.contains(sessionId);
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
        'terminal-history-${DateTime.now().millisecondsSinceEpoch}';
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

  bool _splitActiveSession(
    SessionController sessionController,
    TerminalProfile profile,
    TerminalSplitAxis axis,
  ) {
    final currentState = ref.read(sessionControllerProvider);
    final activeSessionId = currentState.activeSessionId;
    if (activeSessionId == null) {
      sessionController.createSession(profile);
      _focusSession(ref.read(sessionControllerProvider).activeSessionId);
      return true;
    }
    return _splitSession(sessionController, activeSessionId, profile, axis);
  }

  bool _splitSession(
    SessionController sessionController,
    String targetSessionId,
    TerminalProfile profile,
    TerminalSplitAxis axis,
  ) {
    final currentState = ref.read(sessionControllerProvider);
    final targetTab = _tabForSession(currentState, targetSessionId);
    final conflictReason =
        (targetTab == null
            ? null
            : _zoomedPaneManagementUnavailableReason(targetTab)) ??
        _splitAxisConflictReason(currentState, targetSessionId, axis);
    if (conflictReason != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(conflictReason)));
      return false;
    }
    sessionController.splitSession(targetSessionId, profile, axis);
    _focusSession(ref.read(sessionControllerProvider).activeSessionId);
    return true;
  }

  void _closeSession(
    SessionController sessionController,
    SessionState sessionState,
    String sessionId,
  ) {
    unawaited(
      _closeSessionAfterRecordingGate(
        sessionController,
        sessionState,
        sessionId,
      ),
    );
  }

  Future<void> _closeSessionAfterRecordingGate(
    SessionController sessionController,
    SessionState sessionState,
    String sessionId,
  ) async {
    final closesLastSession =
        sessionState.tabs.length == 1 &&
        sessionState.tabs.single.effectivePanes.length == 1;
    if (!await sessionController.closeSession(sessionId)) {
      return;
    }
    if (closesLastSession) {
      _recentlyClosedLastSession = true;
    }
    _clearPresentationStateForSession(sessionId);
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
    unawaited(
      _closeTabAfterRecordingGate(
        sessionController,
        sessionState,
        tabSessionId,
      ),
    );
  }

  Future<void> _closeTabAfterRecordingGate(
    SessionController sessionController,
    SessionState sessionState,
    String tabSessionId,
  ) async {
    final closesLastTab = sessionState.tabs.length == 1;
    final closingTab = sessionState.tabs.firstWhere(
      (tab) => tab.sessionId == tabSessionId,
      orElse: () => sessionState.tabs.first,
    );
    final closeCompleted = await sessionController.closeTab(tabSessionId);
    final currentState = ref.read(sessionControllerProvider);
    final remainingSessionIds = currentState.tabs
        .expand((tab) => tab.effectivePanes)
        .map((pane) => pane.sessionId)
        .toSet();
    final removedSessionIds = closingTab.effectivePanes
        .map((pane) => pane.sessionId)
        .where((sessionId) => !remainingSessionIds.contains(sessionId))
        .toList(growable: false);
    // Native close is per pane. A later pane can become busy after an earlier
    // pane closed, so reconcile presentation resources even when the tab-wide
    // operation returns false.
    _clearPresentationStateForSessions(removedSessionIds);
    final nextActiveSessionId = currentState.activeSessionId;
    if (removedSessionIds.isNotEmpty && nextActiveSessionId != null) {
      _scheduleReturningCue();
      _focusSession(nextActiveSessionId);
    }
    if (!closeCompleted) {
      return;
    }
    if (closesLastTab) {
      _recentlyClosedLastSession = true;
    }
    if (nextActiveSessionId != null && removedSessionIds.isEmpty) {
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
      _showScheduledLayoutCueNow();
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

class _ShellHiddenNewOutputTarget {
  const _ShellHiddenNewOutputTarget({required this.tab, required this.pane});

  final TerminalTab tab;
  final TerminalPane pane;
}
