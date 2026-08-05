part of 'shell_screen.dart';

extension _ShellScreenStateCommandActions on _ShellScreenState {
  Future<bool> _executeProductionActionIfBound({
    required ShellActionProductionRuntimeAdapter adapter,
    required TerminalActionId action,
  }) async {
    if (!adapter.isReady) {
      return false;
    }
    if (!adapter.executor.wiringState.bindings.contains(action)) {
      return false;
    }
    final result = await adapter.executor.execute(action);
    return result.completed;
  }

  bool _dispatchProductionShortcutIfBound({
    required ShellActionProductionRuntimeAdapter adapter,
    required TerminalActionId action,
  }) {
    if (!adapter.isReady) {
      return false;
    }
    if (!adapter.executor.wiringState.bindings.contains(action)) {
      return false;
    }
    unawaited(adapter.executor.execute(action));
    return true;
  }

  Future<void> _openCommandMenu(
    SessionController sessionController,
    SessionState sessionState,
  ) async {
    final defaultProfile = _effectiveDefaultProfileFor(
      sessionState.profiles,
      sessionState.defaultProfileId,
    );
    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    if (_isCommandMenuOpen) {
      return;
    }

    _mutateState(() {
      _isCommandMenuOpen = true;
    });
    _publishAcceptanceSnapshot(sessionState);

    final activeSessionIdBeforeOpen = sessionState.activeSessionId;
    final hasActiveSession = activeSessionIdBeforeOpen != null;
    final isActiveSessionReadOnly =
        activeSessionIdBeforeOpen != null &&
        _isSessionReadOnly(activeSessionIdBeforeOpen);
    final isActiveSessionRecording =
        activeSessionIdBeforeOpen != null &&
        sessionState.recordingSessionIds.contains(activeSessionIdBeforeOpen);
    final isActiveRecordingPendingSave =
        activeSessionIdBeforeOpen != null &&
        sessionState.recordingPendingSaveSessionIds.contains(
          activeSessionIdBeforeOpen,
        );
    final isActiveRecordingBusy =
        activeSessionIdBeforeOpen != null &&
        sessionState.recordingBusySessionIds.contains(
          activeSessionIdBeforeOpen,
        );
    Widget commandMenu() {
      return _ShellCommandMenu(
        launcherShortcutLabel: _launcherShortcutLabel(),
        newTabShortcutLabel: _newTabShortcutLabel(),
        instantReplayShortcutLabel: _instantReplayShortcutLabel(),
        searchShortcutLabel: _searchShortcutLabel(),
        clearBufferShortcutLabel: _clearBufferShortcutLabel(),
        hasDefaultProfile: defaultProfile != null,
        hasActiveSession: hasActiveSession,
        canReopenClosedTab: sessionController.canReopenClosedTab,
        isActiveSessionReadOnly: isActiveSessionReadOnly,
        isActiveSessionRecording: isActiveSessionRecording,
        isActiveRecordingPendingSave: isActiveRecordingPendingSave,
        isActiveRecordingBusy: isActiveRecordingBusy,
        notificationsBlockedBySystem: _notificationsBlockedBySystem,
        commandFinishedNotificationsEnabled:
            _commandFinishedNotificationsEnabled,
        activityMonitorEnabled: _activityNotificationsEnabled,
      );
    }

    final commandMenuRoute = RawDialogRoute<TerminalActionId>(
      barrierDismissible: true,
      barrierLabel: 'Close command palette',
      barrierColor: Colors.black.withValues(alpha: 0.42),
      transitionDuration: animationsEnabled
          ? const Duration(milliseconds: 160)
          : Duration.zero,
      pageBuilder: (_, _, _) {
        return SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 10, right: 14),
              child: commandMenu(),
            ),
          ),
        );
      },
      transitionBuilder: (dialogContext, animation, _, child) {
        if (!animationsEnabled) {
          return child;
        }
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.03),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
    final action = await Navigator.of(
      context,
      rootNavigator: true,
    ).push<TerminalActionId>(commandMenuRoute);
    await commandMenuRoute.completed;

    if (!mounted) {
      return;
    }

    _mutateState(() {
      _isCommandMenuOpen = false;
    });
    _publishAcceptanceSnapshot();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return;
    }

    final currentState = ref.read(sessionControllerProvider);
    final currentSessionId = currentState.activeSessionId;
    final productionMenuAdapter = _buildScopedProductionActionAdapter(
      requiredActionNames: const {
        'newTab',
        'closeTab',
        'reopenClosedTab',
        'reopenClosedPane',
        'duplicateCurrentCwd',
        'toolbelt',
        'splitRight',
        'splitDown',
        'closePane',
        'focusNextPane',
        'focusPreviousPane',
        'resizePane',
        'swapPane',
        'zoomPane',
        'copy',
        'copyCommandOutput',
        'copyMode',
        'paste',
        'advancedPaste',
        'pasteHistory',
        'instantReplay',
        'toggleReadOnly',
        'clearBuffer',
        'globalSearch',
        'autocomplete',
        'autoComposer',
        'searchScrollback',
        'previousPrompt',
        'nextPrompt',
        'selectCommandOutput',
        'shellIntegrationUtilities',
        'openRecentDirectory',
        'tmuxIntegration',
        'coprocess',
        'annotations',
        'capturedOutput',
        'passwordManager',
        'toggleHotkeyWindow',
        'openDefaults',
        'defaults',
        'profiles',
        'dynamicProfiles',
        'openThemePicker',
        'applyLayoutTemplate',
        'exportScrollback',
        'exportDiagnostics',
        'toggleCommandFinishedNotify',
        'toggleBellNotify',
        'toggleActivityMonitor',
      },
      callbacks: ShellActionProductionCallbacks(
        newTab: (_) {
          if (defaultProfile == null) {
            return const ShellActionBindingResult.skipped(
              'No default profile is available.',
            );
          }
          _createSession(
            sessionController,
            defaultProfile,
            returningToLayout: activeSessionIdBeforeOpen == null,
          );
          return const ShellActionBindingResult.completed();
        },
        closeTab: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Close tab requires an active session.',
            );
          }
          final currentTab = _tabForSession(currentState, currentSessionId);
          if (currentTab == null) {
            return const ShellActionBindingResult.skipped(
              'Close tab requires an active tab.',
            );
          }
          _closeTab(sessionController, currentState, currentTab.sessionId);
          return const ShellActionBindingResult.completed();
        },
        duplicateCurrentCwd: (_) {
          if (defaultProfile == null || currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Duplicate current directory requires a default profile and active session.',
            );
          }
          final currentPane = _paneForSession(currentState, currentSessionId);
          final currentDirectory =
              currentPane?.shellIntegration.currentDirectory;
          if (currentDirectory == null || currentDirectory.isEmpty) {
            return const ShellActionBindingResult.skipped(
              'No current directory is available to duplicate.',
            );
          }
          if (_shellHostIsRemote(currentPane?.shellIntegration.hostname)) {
            return const ShellActionBindingResult.skipped(
              'Remote-reported current directories cannot be duplicated as local sessions.',
            );
          }
          _createSession(
            sessionController,
            defaultProfile,
            returningToLayout: activeSessionIdBeforeOpen == null,
          );
          final duplicateSessionId = ref
              .read(sessionControllerProvider)
              .activeSessionId;
          if (duplicateSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'No duplicated session was created.',
            );
          }
          _sendPlainTextToSession(
            duplicateSessionId,
            'cd ${_shellQuotedPath(currentDirectory)}',
          );
          return const ShellActionBindingResult.completed();
        },
        reopenClosedTab: (_) {
          if (!sessionController.canReopenClosedTab) {
            return const ShellActionBindingResult.skipped(
              'No recently closed tab is available.',
            );
          }
          sessionController.reopenClosedTab();
          _focusSession(ref.read(sessionControllerProvider).activeSessionId);
          return const ShellActionBindingResult.completed();
        },
        reopenClosedPane: (_) {
          if (!sessionController.canReopenClosedPane) {
            return const ShellActionBindingResult.skipped(
              'No recently closed pane is available for this tab.',
            );
          }
          final reopenedSessionId = sessionController.reopenClosedPane();
          if (reopenedSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'No recently closed pane could be reopened.',
            );
          }
          _syncZoomedPaneForActivation(
            _tabForSession(
              ref.read(sessionControllerProvider),
              reopenedSessionId,
            ),
            reopenedSessionId,
          );
          _focusSession(reopenedSessionId);
          return const ShellActionBindingResult.completed();
        },
        closePane: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Close pane requires an active session.',
            );
          }
          _closeSession(sessionController, currentState, currentSessionId);
          return const ShellActionBindingResult.completed();
        },
        toolbelt: (_) {
          _mutateState(() {
            _isToolbeltOpen = true;
          });
          return const ShellActionBindingResult.completed();
        },
        splitRight: (_) {
          if (defaultProfile == null || currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Split right requires a default profile and active session.',
            );
          }
          final currentTab = _tabForSession(currentState, currentSessionId);
          final paneManagementBlockedReason = currentTab == null
              ? null
              : _zoomedPaneManagementUnavailableReason(currentTab);
          if (paneManagementBlockedReason != null) {
            return ShellActionBindingResult.skipped(
              paneManagementBlockedReason,
            );
          }
          final conflictReason = _splitAxisConflictReason(
            currentState,
            currentSessionId,
            TerminalSplitAxis.horizontal,
          );
          if (conflictReason != null) {
            return ShellActionBindingResult.skipped(conflictReason);
          }
          if (!_splitActiveSession(
            sessionController,
            defaultProfile,
            TerminalSplitAxis.horizontal,
          )) {
            return const ShellActionBindingResult.skipped(
              'Split right is unavailable.',
            );
          }
          return const ShellActionBindingResult.completed();
        },
        splitDown: (_) {
          if (defaultProfile == null || currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Split down requires a default profile and active session.',
            );
          }
          final currentTab = _tabForSession(currentState, currentSessionId);
          final paneManagementBlockedReason = currentTab == null
              ? null
              : _zoomedPaneManagementUnavailableReason(currentTab);
          if (paneManagementBlockedReason != null) {
            return ShellActionBindingResult.skipped(
              paneManagementBlockedReason,
            );
          }
          final conflictReason = _splitAxisConflictReason(
            currentState,
            currentSessionId,
            TerminalSplitAxis.vertical,
          );
          if (conflictReason != null) {
            return ShellActionBindingResult.skipped(conflictReason);
          }
          if (!_splitActiveSession(
            sessionController,
            defaultProfile,
            TerminalSplitAxis.vertical,
          )) {
            return const ShellActionBindingResult.skipped(
              'Split down is unavailable.',
            );
          }
          return const ShellActionBindingResult.completed();
        },
        focusNextPane: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Focus next pane requires an active session.',
            );
          }
          final currentTab = _tabForSession(currentState, currentSessionId);
          if (currentTab == null ||
              !_focusRelativePane(
                sessionController,
                currentTab,
                currentSessionId,
                delta: 1,
              )) {
            return const ShellActionBindingResult.skipped(
              'No next pane is available.',
            );
          }
          return const ShellActionBindingResult.completed();
        },
        focusPreviousPane: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Focus previous pane requires an active session.',
            );
          }
          final currentTab = _tabForSession(currentState, currentSessionId);
          if (currentTab == null ||
              !_focusRelativePane(
                sessionController,
                currentTab,
                currentSessionId,
                delta: -1,
              )) {
            return const ShellActionBindingResult.skipped(
              'No previous pane is available.',
            );
          }
          return const ShellActionBindingResult.completed();
        },
        resizePaneRight: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Resize pane requires an active session.',
            );
          }
          final currentTab = _tabForSession(currentState, currentSessionId);
          final blockedReason = currentTab == null
              ? null
              : _zoomedPaneManagementUnavailableReason(currentTab);
          if (blockedReason != null) {
            return ShellActionBindingResult.skipped(blockedReason);
          }
          if (currentTab == null) {
            return const ShellActionBindingResult.skipped(
              'Resize pane requires at least two panes.',
            );
          }
          final growthBlockedReason = _growActivePaneUnavailableReason(
            currentTab,
            currentSessionId,
          );
          if (growthBlockedReason != null ||
              !_growActivePane(currentTab, currentSessionId)) {
            return ShellActionBindingResult.skipped(
              growthBlockedReason ?? 'Resize pane requires at least two panes.',
            );
          }
          _focusSession(currentSessionId);
          return const ShellActionBindingResult.completed();
        },
        swapPane: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Swap pane requires an active session.',
            );
          }
          final currentTab = _tabForSession(currentState, currentSessionId);
          final blockedReason = currentTab == null
              ? null
              : _zoomedPaneManagementUnavailableReason(currentTab);
          if (blockedReason != null) {
            return ShellActionBindingResult.skipped(blockedReason);
          }
          if ((currentTab?.effectivePanes.length ?? 0) < 2) {
            return const ShellActionBindingResult.skipped(
              'Swap pane requires at least two panes.',
            );
          }
          sessionController.swapActivePaneWithSibling();
          _focusSession(currentSessionId);
          return const ShellActionBindingResult.completed();
        },
        zoomPane: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Zoom pane requires an active session.',
            );
          }
          final currentTab = _tabForSession(currentState, currentSessionId);
          if ((currentTab?.effectivePanes.length ?? 0) < 2) {
            return const ShellActionBindingResult.skipped(
              'Zoom pane requires at least two panes.',
            );
          }
          _mutateState(() {
            _zoomedPaneSessionId = _zoomedPaneSessionId == currentSessionId
                ? null
                : currentSessionId;
          });
          _focusSession(currentSessionId);
          return const ShellActionBindingResult.completed();
        },
        copy: (_) async {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Copy requires an active session.',
            );
          }
          final selectionController = _selectionControllers[currentSessionId];
          if (selectionController == null) {
            return const ShellActionBindingResult.skipped(
              'Copy requires an active selection controller.',
            );
          }
          await _copySelection(
            sessionController,
            currentSessionId,
            selectionController,
          );
          _restoreSessionFocus(
            activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
            activeSessionIdAfterClose: currentSessionId,
          );
          return const ShellActionBindingResult.completed();
        },
        copyCommandOutput: (_) async {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Copy command output requires an active session.',
            );
          }
          final selectionController = _selectionControllers.putIfAbsent(
            currentSessionId,
            SelectionController.new,
          );
          final selected = _selectLastCommandOutput(
            sessionController,
            currentSessionId,
            selectionController,
          );
          if (!selected) {
            _restoreSessionFocus(
              activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
              activeSessionIdAfterClose: currentSessionId,
            );
            return const ShellActionBindingResult.skipped(
              'No command output is available to copy.',
            );
          }
          await _copySelection(
            sessionController,
            currentSessionId,
            selectionController,
          );
          _restoreSessionFocus(
            activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
            activeSessionIdAfterClose: currentSessionId,
          );
          return const ShellActionBindingResult.completed();
        },
        copyMode: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Copy mode requires an active session.',
            );
          }
          final selectionController = _selectionControllers.putIfAbsent(
            currentSessionId,
            SelectionController.new,
          );
          _enterCopyMode(
            sessionController,
            currentSessionId,
            selectionController,
          );
          return const ShellActionBindingResult.completed();
        },
        paste: (_) async {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Paste requires an active session.',
            );
          }
          await _pasteToSession(currentSessionId);
          _restoreSessionFocus(
            activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
            activeSessionIdAfterClose: currentSessionId,
          );
          return const ShellActionBindingResult.completed();
        },
        advancedPaste: (_) async {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Advanced paste requires an active session.',
            );
          }
          await _openAdvancedPaste(currentSessionId);
          _restoreSessionFocus(
            activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
            activeSessionIdAfterClose: currentSessionId,
          );
          return const ShellActionBindingResult.completed();
        },
        pasteHistory: (_) async {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Paste history requires an active session.',
            );
          }
          await _openPasteHistory(sessionState);
          return const ShellActionBindingResult.completed();
        },
        instantReplay: (_) async {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Replay recent activity requires an active session.',
            );
          }
          await _openInstantReplay(sessionState);
          return const ShellActionBindingResult.completed();
        },
        toggleReadOnly: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Read-only mode requires an active session.',
            );
          }
          final willEnableReadOnly = !_isSessionReadOnly(currentSessionId);
          _toggleReadOnlySession(currentSessionId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  willEnableReadOnly
                      ? 'Read-only mode enabled. Input is blocked for this pane.'
                      : 'Read-only mode disabled. Input is active for this pane.',
                ),
              ),
            );
          }
          return const ShellActionBindingResult.completed();
        },
        clearBuffer: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Clear buffer requires an active session.',
            );
          }
          final cleared = ref
              .read(terminalRuntimeControllerProvider)
              .clearBuffer(currentSessionId);
          if (cleared) {
            ref
                .read(sessionControllerProvider.notifier)
                .clearPromptMarks(currentSessionId);
            _showShellSnackBar(
              'Buffer cleared. The current command line was kept.',
            );
          }
          if (!cleared && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Clear buffer requires native runtime support.'),
              ),
            );
          }
          return ShellActionBindingResult.completed(
            cleared
                ? 'Cleared buffer.'
                : 'Clear buffer is not supported by this runtime.',
          );
        },
        globalSearch: (_) async {
          if (sessionState.tabs.isEmpty) {
            return const ShellActionBindingResult.skipped(
              'Global search requires at least one tab.',
            );
          }
          await _openGlobalSearch(sessionState);
          return const ShellActionBindingResult.completed();
        },
        autocomplete: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Autocomplete requires an active session.',
            );
          }
          _openAutocomplete();
          return const ShellActionBindingResult.completed();
        },
        autoComposer: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Auto composer requires an active session.',
            );
          }
          _openAutoComposer();
          return const ShellActionBindingResult.completed();
        },
        searchScrollback: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Search requires an active session.',
            );
          }
          _openSearch();
          return const ShellActionBindingResult.completed();
        },
        previousPrompt: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Previous prompt requires an active session.',
            );
          }
          _navigateShellPrompt(currentSessionId, direction: -1);
          return const ShellActionBindingResult.completed();
        },
        nextPrompt: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Next prompt requires an active session.',
            );
          }
          _navigateShellPrompt(currentSessionId, direction: 1);
          return const ShellActionBindingResult.completed();
        },
        selectCommandOutput: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Select command output requires an active session.',
            );
          }
          final selectionController = _selectionControllers.putIfAbsent(
            currentSessionId,
            SelectionController.new,
          );
          final selected = _selectLastCommandOutput(
            sessionController,
            currentSessionId,
            selectionController,
          );
          if (!selected) {
            _restoreSessionFocus(
              activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
              activeSessionIdAfterClose: currentSessionId,
            );
          }
          return const ShellActionBindingResult.completed();
        },
        shellIntegrationUtilities: (_) async {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Shell integration utilities require an active session.',
            );
          }
          await _openShellIntegrationUtilities(currentState, currentSessionId);
          _restoreSessionFocus(
            activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
            activeSessionIdAfterClose: currentSessionId,
          );
          return const ShellActionBindingResult.completed();
        },
        openRecentDirectory: (_) {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Open recent directory requires an active session.',
            );
          }
          final currentPane = _paneForSession(currentState, currentSessionId);
          final recentDirectories =
              currentPane?.shellIntegration.recentDirectories ?? const [];
          if (recentDirectories.isEmpty) {
            return const ShellActionBindingResult.skipped(
              'No recent directory is available.',
            );
          }
          _sendPlainTextToSession(
            currentSessionId,
            'cd ${_shellQuotedPath(recentDirectories.first)}',
          );
          _restoreSessionFocus(
            activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
            activeSessionIdAfterClose: currentSessionId,
          );
          return const ShellActionBindingResult.completed();
        },
        tmuxIntegration: (_) async {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'tmux integration requires an active session.',
            );
          }
          await _openTmuxIntegration(currentSessionId);
          _restoreSessionFocus(
            activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
            activeSessionIdAfterClose: currentSessionId,
          );
          return const ShellActionBindingResult.completed();
        },
        coprocess: (_) async {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Coprocess requires an active session.',
            );
          }
          await _openCoprocess(currentSessionId);
          _restoreSessionFocus(
            activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
            activeSessionIdAfterClose: currentSessionId,
          );
          return const ShellActionBindingResult.completed();
        },
        annotations: (_) async {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Annotations require an active session.',
            );
          }
          final selectionController = _selectionControllers.putIfAbsent(
            currentSessionId,
            SelectionController.new,
          );
          await _openAnnotations(
            sessionController,
            currentSessionId,
            selectionController,
          );
          _restoreSessionFocus(
            activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
            activeSessionIdAfterClose: currentSessionId,
          );
          return const ShellActionBindingResult.completed();
        },
        capturedOutput: (_) async {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Captured output requires an active session.',
            );
          }
          await _openCapturedOutput(currentSessionId);
          _restoreSessionFocus(
            activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
            activeSessionIdAfterClose: currentSessionId,
          );
          return const ShellActionBindingResult.completed();
        },
        passwordManager: (_) async {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Password manager requires an active session.',
            );
          }
          await _openPasswordManager(sessionController, currentSessionId);
          _restoreSessionFocus(
            activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
            activeSessionIdAfterClose: currentSessionId,
          );
          return const ShellActionBindingResult.completed();
        },
        toggleHotkeyWindow: (_) async {
          final toggled = await _toggleHotkeyWindowWithFeedback();
          return toggled
              ? const ShellActionBindingResult.completed()
              : const ShellActionBindingResult.skipped(
                  'Hotkey window is unavailable.',
                );
        },
        openDefaults: (_) async {
          await _openDefaultsAndAppearance(sessionController, sessionState);
          return const ShellActionBindingResult.completed();
        },
        defaults: (_) async {
          await _openDefaultsAndAppearance(sessionController, sessionState);
          return const ShellActionBindingResult.completed();
        },
        profiles: (_) async {
          await _openProfilesSheet(sessionController, sessionState);
          return const ShellActionBindingResult.completed();
        },
        dynamicProfiles: (_) async {
          await _openDynamicProfiles(sessionController);
          return const ShellActionBindingResult.completed();
        },
        openThemePicker: (_) async {
          await _openDefaultsAndAppearance(sessionController, sessionState);
          return const ShellActionBindingResult.completed();
        },
        applyLayoutTemplate: (_) {
          if (defaultProfile == null || currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Apply layout template requires a default profile and active session.',
            );
          }
          final currentTab = _tabForSession(currentState, currentSessionId);
          if (currentTab == null) {
            return const ShellActionBindingResult.skipped(
              'No active tab is available for layout templates.',
            );
          }
          if (currentTab.effectivePanes.length > 1) {
            return const ShellActionBindingResult.skipped(
              'Two-pane layout template is already satisfied.',
            );
          }
          if (!_splitActiveSession(
            sessionController,
            defaultProfile,
            TerminalSplitAxis.horizontal,
          )) {
            return const ShellActionBindingResult.skipped(
              'Apply layout template is unavailable.',
            );
          }
          return const ShellActionBindingResult.completed();
        },
        exportScrollback: (_) async {
          if (currentSessionId == null) {
            return const ShellActionBindingResult.skipped(
              'Export scrollback requires an active session.',
            );
          }
          final file = await _exportVisibleFrame(currentSessionId);
          if (file == null) {
            return const ShellActionBindingResult.skipped(
              'No visible terminal content is available to export.',
            );
          }
          if (mounted) {
            _showShellPathSnackBar(
              message: 'Scrollback exported',
              path: file.path,
            );
          }
          return const ShellActionBindingResult.completed(
            'Exported terminal scrollback.',
          );
        },
        exportDiagnostics: (_) async {
          if (currentSessionId == null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Export diagnostics requires an active session.',
                  ),
                ),
              );
            }
            return const ShellActionBindingResult.skipped(
              'Export diagnostics requires an active session.',
            );
          }
          final directory = await _exportDiagnosticsBundle(currentState);
          if (directory == null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Diagnostics export is unavailable for the active sessions.',
                  ),
                ),
              );
            }
            return const ShellActionBindingResult.skipped(
              'Diagnostics export is unavailable for the active sessions.',
            );
          }
          if (mounted) {
            _showShellPathSnackBar(
              message: 'Diagnostics exported',
              path: directory.path,
            );
          }
          return const ShellActionBindingResult.completed(
            'Exported terminal diagnostics.',
          );
        },
        toggleCommandFinishedNotify: (_) {
          _mutateState(() {
            _commandFinishedNotificationsEnabled =
                !_commandFinishedNotificationsEnabled;
          });
          unawaited(_saveNotificationPreferences());
          final messenger = ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Command-finished notifications ${_commandFinishedNotificationsEnabled ? 'enabled' : 'disabled'} and saved.',
              ),
            ),
          );
          return const ShellActionBindingResult.completed();
        },
        toggleBellNotify: (_) {
          _mutateState(() {
            _bellNotificationsEnabled = !_bellNotificationsEnabled;
          });
          unawaited(_saveNotificationPreferences());
          final messenger = ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Bell notifications ${_bellNotificationsEnabled ? 'enabled' : 'disabled'} and saved.',
              ),
            ),
          );
          return const ShellActionBindingResult.completed();
        },
        toggleActivityMonitor: (_) {
          _mutateState(() {
            _activityNotificationsEnabled = !_activityNotificationsEnabled;
          });
          unawaited(_saveNotificationPreferences());
          final messenger = ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Activity monitor ${_activityNotificationsEnabled ? 'enabled' : 'disabled'} and saved.',
              ),
            ),
          );
          return const ShellActionBindingResult.completed();
        },
      ),
    );
    if (action != null &&
        await _executeProductionActionIfBound(
          adapter: productionMenuAdapter,
          action: action,
        )) {
      return;
    }
    switch (action) {
      case TerminalActionId.openRecording:
        await _openRecordingFromPicker();
        return;
      case TerminalActionId.openTerminalAtFolder:
        await _openTerminalAtFolderFromPicker();
        return;
      case TerminalActionId.newTab:
        if (defaultProfile == null) {
          return;
        }
        _createSession(
          sessionController,
          defaultProfile,
          returningToLayout: activeSessionIdBeforeOpen == null,
        );
        return;
      case TerminalActionId.toolbelt:
        _mutateState(() {
          _isToolbeltOpen = true;
        });
        return;
      case TerminalActionId.splitRight:
        if (defaultProfile == null || currentSessionId == null) {
          return;
        }
        _splitActiveSession(
          sessionController,
          defaultProfile,
          TerminalSplitAxis.horizontal,
        );
        return;
      case TerminalActionId.splitDown:
        if (defaultProfile == null || currentSessionId == null) {
          return;
        }
        _splitActiveSession(
          sessionController,
          defaultProfile,
          TerminalSplitAxis.vertical,
        );
        return;
      case TerminalActionId.copy:
        if (currentSessionId == null) {
          return;
        }
        final selectionController = _selectionControllers[currentSessionId];
        if (selectionController == null) {
          return;
        }
        await _copySelection(
          sessionController,
          currentSessionId,
          selectionController,
        );
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentSessionId,
        );
        return;
      case TerminalActionId.copyMode:
        if (currentSessionId == null) {
          return;
        }
        final selectionController = _selectionControllers.putIfAbsent(
          currentSessionId,
          SelectionController.new,
        );
        _enterCopyMode(
          sessionController,
          currentSessionId,
          selectionController,
        );
        return;
      case TerminalActionId.paste:
        if (currentSessionId == null) {
          return;
        }
        await _pasteToSession(currentSessionId);
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentSessionId,
        );
        return;
      case TerminalActionId.advancedPaste:
        if (currentSessionId == null) {
          return;
        }
        await _openAdvancedPaste(currentSessionId);
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentSessionId,
        );
        return;
      case TerminalActionId.pasteHistory:
        if (currentSessionId == null) {
          return;
        }
        await _openPasteHistory(sessionState);
        return;
      case TerminalActionId.shellIntegrationUtilities:
        if (currentSessionId == null) {
          return;
        }
        await _openShellIntegrationUtilities(currentState, currentSessionId);
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentSessionId,
        );
        return;
      case TerminalActionId.selectCommandOutput:
        if (currentSessionId == null) {
          return;
        }
        final selectionController = _selectionControllers.putIfAbsent(
          currentSessionId,
          SelectionController.new,
        );
        if (_selectLastCommandOutput(
          sessionController,
          currentSessionId,
          selectionController,
        )) {
          return;
        }
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentSessionId,
        );
        return;
      case TerminalActionId.tmuxIntegration:
        if (currentSessionId == null) {
          return;
        }
        await _openTmuxIntegration(currentSessionId);
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentSessionId,
        );
        return;
      case TerminalActionId.coprocess:
        if (currentSessionId == null) {
          return;
        }
        await _openCoprocess(currentSessionId);
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentSessionId,
        );
        return;
      case TerminalActionId.annotations:
        if (currentSessionId == null) {
          return;
        }
        final selectionController = _selectionControllers.putIfAbsent(
          currentSessionId,
          SelectionController.new,
        );
        await _openAnnotations(
          sessionController,
          currentSessionId,
          selectionController,
        );
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentSessionId,
        );
        return;
      case TerminalActionId.capturedOutput:
        if (currentSessionId == null) {
          return;
        }
        await _openCapturedOutput(currentSessionId);
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentSessionId,
        );
        return;
      case TerminalActionId.passwordManager:
        if (currentSessionId == null) {
          return;
        }
        await _openPasswordManager(sessionController, currentSessionId);
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentSessionId,
        );
        return;
      case TerminalActionId.instantReplay:
        if (currentSessionId == null) {
          return;
        }
        await _openInstantReplay(sessionState);
        return;
      case TerminalActionId.toggleSessionRecording:
        await _toggleActiveSessionRecording(
          sessionController,
          currentSessionId,
        );
        return;
      case TerminalActionId.search:
        if (currentSessionId == null) {
          return;
        }
        _openSearch();
        return;
      case TerminalActionId.globalSearch:
        if (sessionState.tabs.isEmpty) {
          return;
        }
        await _openGlobalSearch(sessionState);
        return;
      case TerminalActionId.autocomplete:
        if (currentSessionId == null) {
          return;
        }
        _openAutocomplete();
        return;
      case TerminalActionId.autoComposer:
        if (currentSessionId == null) {
          return;
        }
        _openAutoComposer();
        return;
      case TerminalActionId.hotkeyWindow:
        await _toggleHotkeyWindowWithFeedback();
        return;
      case TerminalActionId.defaults:
        await _openDefaultsAndAppearance(sessionController, sessionState);
        return;
      case TerminalActionId.profiles:
        await _openProfilesSheet(sessionController, sessionState);
        return;
      case TerminalActionId.dynamicProfiles:
        await _openDynamicProfiles(sessionController);
        return;
      case TerminalActionId.openDefaults:
        await _openDefaultsAndAppearance(sessionController, sessionState);
        return;
      case TerminalActionId.activateTab:
        return;
      case TerminalActionId.openLauncher:
      case TerminalActionId.openCommandMenu:
      case TerminalActionId.closeActiveTab:
        return;
      case null:
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentSessionId,
        );
        return;
      default:
        return;
    }
  }

  Future<void> _openTabContextMenu(
    SessionController sessionController,
    SessionState sessionState,
    TerminalTab tab,
    Offset position,
  ) async {
    final defaultProfile = _effectiveDefaultProfileFor(
      sessionState.profiles,
      sessionState.defaultProfileId,
    );
    final targetSessionId = tab.activeSessionId;
    final hasMultiplePanes = tab.effectivePanes.length > 1;
    final paneManagementBlockedReason = _zoomedPaneManagementUnavailableReason(
      tab,
    );
    final splitRightBlockedReason =
        paneManagementBlockedReason ??
        _splitAxisConflictReason(
          sessionState,
          targetSessionId,
          TerminalSplitAxis.horizontal,
        );
    final splitDownBlockedReason =
        paneManagementBlockedReason ??
        _splitAxisConflictReason(
          sessionState,
          targetSessionId,
          TerminalSplitAxis.vertical,
        );
    final targetPane = tab.paneFor(targetSessionId);
    final hasCurrentDirectory =
        (targetPane?.shellIntegration.currentDirectory ?? '').isNotEmpty;
    final duplicateCwdBlockedReason = defaultProfile == null
        ? 'No default profile is available.'
        : !hasCurrentDirectory
        ? 'No current directory is available.'
        : _shellHostIsRemote(targetPane?.shellIntegration.hostname)
        ? 'Remote-reported current directories cannot be duplicated as local sessions.'
        : null;
    final growPaneBlockedReason = targetPane == null
        ? 'Add another pane to use this action.'
        : paneManagementBlockedReason ??
              _growActivePaneUnavailableReason(tab, targetSessionId);
    final reopenClosedPaneBlockedReason = sessionController.canReopenClosedPane
        ? null
        : 'No recently closed pane is available for this tab.';
    final overlay = Overlay.of(context).context.findRenderObject();
    final overlaySize = overlay is RenderBox
        ? overlay.size
        : MediaQuery.sizeOf(context);

    PopupMenuItem<TerminalActionId> item({
      required TerminalActionId action,
      required IconData icon,
      required String title,
      required bool enabled,
      String? disabledReason,
    }) {
      final reason = enabled ? null : disabledReason;
      return PopupMenuItem<TerminalActionId>(
        value: action,
        enabled: enabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(title)),
              ],
            ),
            if (reason != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Text(
                  'Unavailable: $reason',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).disabledColor,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    final action = await showMenu<TerminalActionId>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlaySize,
      ),
      items: [
        item(
          action: TerminalActionId.duplicateCurrentCwd,
          icon: Icons.create_new_folder_rounded,
          title: 'Duplicate current directory',
          enabled: duplicateCwdBlockedReason == null,
          disabledReason: duplicateCwdBlockedReason,
        ),
        item(
          action: TerminalActionId.splitRight,
          icon: Icons.vertical_split_rounded,
          title: 'Split right',
          enabled: defaultProfile != null && splitRightBlockedReason == null,
          disabledReason: splitRightBlockedReason,
        ),
        item(
          action: TerminalActionId.splitDown,
          icon: Icons.horizontal_split_rounded,
          title: 'Split down',
          enabled: defaultProfile != null && splitDownBlockedReason == null,
          disabledReason: splitDownBlockedReason,
        ),
        item(
          action: TerminalActionId.reopenClosedPane,
          icon: Icons.restore_page_rounded,
          title: 'Reopen closed pane',
          enabled: reopenClosedPaneBlockedReason == null,
          disabledReason: reopenClosedPaneBlockedReason,
        ),
        item(
          action: TerminalActionId.applyLayoutTemplate,
          icon: Icons.dashboard_customize_rounded,
          title: 'Apply two-pane layout',
          enabled: defaultProfile != null && !hasMultiplePanes,
          disabledReason: hasMultiplePanes
              ? 'This tab already has multiple panes.'
              : null,
        ),
        const PopupMenuDivider(),
        item(
          action: TerminalActionId.resizePane,
          icon: Icons.open_with_rounded,
          title: 'Grow active pane',
          enabled: hasMultiplePanes && growPaneBlockedReason == null,
          disabledReason: growPaneBlockedReason,
        ),
        item(
          action: TerminalActionId.swapPane,
          icon: Icons.swap_horiz_rounded,
          title: 'Swap active pane',
          enabled: hasMultiplePanes && paneManagementBlockedReason == null,
          disabledReason: hasMultiplePanes
              ? paneManagementBlockedReason
              : 'Add another pane to use this action.',
        ),
        const PopupMenuDivider(),
        item(
          action: TerminalActionId.closePane,
          icon: Icons.close_fullscreen_rounded,
          title: 'Close active pane',
          enabled: true,
        ),
        item(
          action: TerminalActionId.closeActiveTab,
          icon: Icons.close_rounded,
          title: 'Close tab',
          enabled: true,
        ),
      ],
    );

    if (!mounted || action == null) {
      return;
    }
    await _runTabContextAction(
      sessionController,
      action,
      targetTabSessionId: tab.sessionId,
    );
  }

  Future<void> _runTabContextAction(
    SessionController sessionController,
    TerminalActionId action, {
    required String targetTabSessionId,
  }) async {
    final defaultProfile = _effectiveDefaultProfileFor(
      ref.read(sessionControllerProvider).profiles,
      ref.read(sessionControllerProvider).defaultProfileId,
    );
    final initialState = ref.read(sessionControllerProvider);
    TerminalTab? targetTab;
    for (final candidate in initialState.tabs) {
      if (candidate.sessionId == targetTabSessionId) {
        targetTab = candidate;
        break;
      }
    }
    if (targetTab == null) {
      return;
    }
    final targetSessionId = targetTab.activeSessionId;

    if (action == TerminalActionId.closeActiveTab) {
      _closeTab(sessionController, initialState, targetTab.sessionId);
      return;
    }

    _activateSession(sessionController, targetSessionId);
    final currentState = ref.read(sessionControllerProvider);
    final currentSessionId = currentState.activeSessionId;
    if (currentSessionId == null) {
      return;
    }

    switch (action) {
      case TerminalActionId.duplicateCurrentCwd:
        if (defaultProfile == null) {
          return;
        }
        final currentPane = _paneForSession(currentState, currentSessionId);
        final currentDirectory = currentPane?.shellIntegration.currentDirectory;
        if (currentDirectory == null || currentDirectory.isEmpty) {
          return;
        }
        if (_shellHostIsRemote(currentPane?.shellIntegration.hostname)) {
          _showShellSnackBar(
            'Remote-reported current directories cannot be duplicated as local sessions.',
          );
          return;
        }
        _createSession(
          sessionController,
          defaultProfile,
          returningToLayout: false,
        );
        final duplicateSessionId = ref
            .read(sessionControllerProvider)
            .activeSessionId;
        if (duplicateSessionId != null) {
          _sendPlainTextToSession(
            duplicateSessionId,
            'cd ${_shellQuotedPath(currentDirectory)}',
          );
        }
        return;
      case TerminalActionId.splitRight:
        if (defaultProfile == null) {
          return;
        }
        _splitActiveSession(
          sessionController,
          defaultProfile,
          TerminalSplitAxis.horizontal,
        );
        return;
      case TerminalActionId.splitDown:
        if (defaultProfile == null) {
          return;
        }
        _splitActiveSession(
          sessionController,
          defaultProfile,
          TerminalSplitAxis.vertical,
        );
        return;
      case TerminalActionId.reopenClosedPane:
        if (!sessionController.canReopenClosedPane) {
          return;
        }
        final reopenedSessionId = sessionController.reopenClosedPane();
        if (reopenedSessionId != null) {
          _syncZoomedPaneForActivation(
            _tabForSession(
              ref.read(sessionControllerProvider),
              reopenedSessionId,
            ),
            reopenedSessionId,
          );
          _focusSession(reopenedSessionId);
        }
        return;
      case TerminalActionId.applyLayoutTemplate:
        if (defaultProfile == null) {
          return;
        }
        final currentTab = _tabForSession(currentState, currentSessionId);
        if (currentTab == null || currentTab.effectivePanes.length > 1) {
          return;
        }
        _splitActiveSession(
          sessionController,
          defaultProfile,
          TerminalSplitAxis.horizontal,
        );
        return;
      case TerminalActionId.focusNextPane:
        final currentTab = _tabForSession(currentState, currentSessionId);
        if (currentTab != null) {
          _focusRelativePane(
            sessionController,
            currentTab,
            currentSessionId,
            delta: 1,
          );
        }
        return;
      case TerminalActionId.focusPreviousPane:
        final currentTab = _tabForSession(currentState, currentSessionId);
        if (currentTab != null) {
          _focusRelativePane(
            sessionController,
            currentTab,
            currentSessionId,
            delta: -1,
          );
        }
        return;
      case TerminalActionId.resizePane:
        final currentTab = _tabForSession(currentState, currentSessionId);
        if (currentTab == null) {
          return;
        }
        final blockedReason = _growActivePaneUnavailableReason(
          currentTab,
          currentSessionId,
        );
        if (_growActivePane(currentTab, currentSessionId)) {
          _focusSession(currentSessionId);
        } else if (blockedReason != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(blockedReason)));
        }
        return;
      case TerminalActionId.swapPane:
        final currentTab = _tabForSession(currentState, currentSessionId);
        final blockedReason = currentTab == null
            ? null
            : _zoomedPaneManagementUnavailableReason(currentTab);
        if (blockedReason != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(blockedReason)));
          return;
        }
        if ((currentTab?.effectivePanes.length ?? 0) < 2) {
          return;
        }
        sessionController.swapActivePaneWithSibling();
        _focusSession(currentSessionId);
        return;
      case TerminalActionId.zoomPane:
        final currentTab = _tabForSession(currentState, currentSessionId);
        if ((currentTab?.effectivePanes.length ?? 0) < 2) {
          return;
        }
        _mutateState(() {
          _zoomedPaneSessionId = _zoomedPaneSessionId == currentSessionId
              ? null
              : currentSessionId;
        });
        _focusSession(currentSessionId);
        return;
      case TerminalActionId.closePane:
        _closeSession(sessionController, currentState, currentSessionId);
        return;
      default:
        return;
    }
  }
}
