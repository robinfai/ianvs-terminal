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
    final l10n = context.l10n;
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
    final isActiveSessionSsh =
        _sftpTargetFor(sessionState, activeSessionIdBeforeOpen) != null;
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
        hasDefaultProfile: _canOpenNewSessionLauncher(sessionState),
        hasActiveSession: hasActiveSession,
        isActiveSessionSsh: isActiveSessionSsh,
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
      barrierLabel: l10n.closeCommandPalette,
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
          if (!_canOpenNewSessionLauncher(currentState)) {
            return ShellActionBindingResult.skipped(
              l10n.noTerminalSessionOptionAvailable,
            );
          }
          unawaited(_openNewSessionLauncher(sessionController, currentState));
          return const ShellActionBindingResult.completed();
        },
        closeTab: (_) {
          if (currentSessionId == null) {
            return ShellActionBindingResult.skipped(
              l10n.closeTabRequiresActiveSession,
            );
          }
          final currentTab = _tabForSession(currentState, currentSessionId);
          if (currentTab == null) {
            return ShellActionBindingResult.skipped(
              l10n.closeTabRequiresActiveTab,
            );
          }
          _closeTab(sessionController, currentState, currentTab.sessionId);
          return const ShellActionBindingResult.completed();
        },
        duplicateCurrentCwd: (_) {
          if (defaultProfile == null || currentSessionId == null) {
            return ShellActionBindingResult.skipped(
              l10n.duplicateCwdRequiresProfileSession,
            );
          }
          final currentPane = _paneForSession(currentState, currentSessionId);
          final currentDirectory =
              currentPane?.shellIntegration.currentDirectory;
          if (currentDirectory == null || currentDirectory.isEmpty) {
            return ShellActionBindingResult.skipped(
              l10n.noCurrentDirectoryAvailable,
            );
          }
          if (_shellHostIsRemote(currentPane?.shellIntegration.hostname)) {
            return ShellActionBindingResult.skipped(
              l10n.remoteDirectoryCannotDuplicate,
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
            return ShellActionBindingResult.skipped(
              l10n.noDuplicatedSessionCreated,
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
            return ShellActionBindingResult.skipped(
              l10n.noRecentlyClosedTabAvailable,
            );
          }
          sessionController.reopenClosedTab();
          _focusSession(ref.read(sessionControllerProvider).activeSessionId);
          return const ShellActionBindingResult.completed();
        },
        reopenClosedPane: (_) {
          if (!sessionController.canReopenClosedPane) {
            return ShellActionBindingResult.skipped(
              l10n.noRecentlyClosedPaneForTab,
            );
          }
          final reopenedSessionId = sessionController.reopenClosedPane();
          if (reopenedSessionId == null) {
            return ShellActionBindingResult.skipped(
              l10n.noRecentlyClosedPaneReopened,
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
            return ShellActionBindingResult.skipped(
              l10n.closePaneRequiresActiveSession,
            );
          }
          _closeSession(sessionController, currentState, currentSessionId);
          return const ShellActionBindingResult.completed();
        },
        toolbelt: (_) {
          FocusManager.instance.primaryFocus?.unfocus();
          _mutateState(() {
            _isSftpPanelOpen = false;
            _sftpPanelSessionId = null;
            _isToolbeltOpen = true;
          });
          return const ShellActionBindingResult.completed();
        },
        splitRight: (_) {
          if (defaultProfile == null || currentSessionId == null) {
            return ShellActionBindingResult.skipped(
              l10n.splitRightRequiresProfileSession,
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
            return ShellActionBindingResult.skipped(l10n.splitRightUnavailable);
          }
          return const ShellActionBindingResult.completed();
        },
        splitDown: (_) {
          if (defaultProfile == null || currentSessionId == null) {
            return ShellActionBindingResult.skipped(
              l10n.splitDownRequiresProfileSession,
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
            return ShellActionBindingResult.skipped(l10n.splitDownUnavailable);
          }
          return const ShellActionBindingResult.completed();
        },
        focusNextPane: (_) {
          if (currentSessionId == null) {
            return ShellActionBindingResult.skipped(
              l10n.focusNextPaneRequiresSession,
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
            return ShellActionBindingResult.skipped(l10n.noNextPaneAvailable);
          }
          return const ShellActionBindingResult.completed();
        },
        focusPreviousPane: (_) {
          if (currentSessionId == null) {
            return ShellActionBindingResult.skipped(
              l10n.focusPreviousPaneRequiresSession,
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
            return ShellActionBindingResult.skipped(
              l10n.noPreviousPaneAvailable,
            );
          }
          return const ShellActionBindingResult.completed();
        },
        resizePaneRight: (_) {
          if (currentSessionId == null) {
            return ShellActionBindingResult.skipped(
              l10n.resizePaneRequiresSession,
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
            return ShellActionBindingResult.skipped(
              l10n.resizePaneRequiresTwoPanes,
            );
          }
          final growthBlockedReason = _growActivePaneUnavailableReason(
            currentTab,
            currentSessionId,
          );
          if (growthBlockedReason != null ||
              !_growActivePane(currentTab, currentSessionId)) {
            return ShellActionBindingResult.skipped(
              growthBlockedReason ?? l10n.resizePaneRequiresTwoPanes,
            );
          }
          _focusSession(currentSessionId);
          return const ShellActionBindingResult.completed();
        },
        swapPane: (_) {
          if (currentSessionId == null) {
            return ShellActionBindingResult.skipped(
              l10n.swapPaneRequiresSession,
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
            return ShellActionBindingResult.skipped(
              l10n.swapPaneRequiresTwoPanes,
            );
          }
          sessionController.swapActivePaneWithSibling();
          _focusSession(currentSessionId);
          return const ShellActionBindingResult.completed();
        },
        zoomPane: (_) {
          if (currentSessionId == null) {
            return ShellActionBindingResult.skipped(
              l10n.zoomPaneRequiresSession,
            );
          }
          final currentTab = _tabForSession(currentState, currentSessionId);
          if ((currentTab?.effectivePanes.length ?? 0) < 2) {
            return ShellActionBindingResult.skipped(
              l10n.zoomPaneRequiresTwoPanes,
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
            return ShellActionBindingResult.skipped(l10n.copyRequiresSession);
          }
          final selectionController = _selectionControllers[currentSessionId];
          if (selectionController == null) {
            return ShellActionBindingResult.skipped(
              l10n.copyRequiresSelectionController,
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
            return ShellActionBindingResult.skipped(
              l10n.copyCommandOutputRequiresSession,
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
            return ShellActionBindingResult.skipped(
              l10n.noCommandOutputAvailable,
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
            return ShellActionBindingResult.skipped(
              l10n.copyModeRequiresSession,
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
            return ShellActionBindingResult.skipped(l10n.pasteRequiresSession);
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
            return ShellActionBindingResult.skipped(
              l10n.advancedPasteRequiresSession,
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
            return ShellActionBindingResult.skipped(
              l10n.pasteHistoryRequiresSession,
            );
          }
          await _openPasteHistory(sessionState);
          return const ShellActionBindingResult.completed();
        },
        instantReplay: (_) async {
          if (currentSessionId == null) {
            return ShellActionBindingResult.skipped(l10n.replayRequiresSession);
          }
          await _openInstantReplay(sessionState);
          return const ShellActionBindingResult.completed();
        },
        toggleReadOnly: (_) {
          if (currentSessionId == null) {
            return ShellActionBindingResult.skipped(
              l10n.readOnlyRequiresSession,
            );
          }
          final willEnableReadOnly = !_isSessionReadOnly(currentSessionId);
          _toggleReadOnlySession(currentSessionId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  willEnableReadOnly
                      ? l10n.readOnlyEnabledNotice
                      : l10n.readOnlyDisabledNotice,
                ),
              ),
            );
          }
          return const ShellActionBindingResult.completed();
        },
        clearBuffer: (_) {
          if (currentSessionId == null) {
            return ShellActionBindingResult.skipped(
              l10n.clearBufferRequiresSession,
            );
          }
          final cleared = ref
              .read(terminalRuntimeControllerProvider)
              .clearBuffer(currentSessionId);
          if (cleared) {
            ref
                .read(sessionControllerProvider.notifier)
                .clearPromptMarks(currentSessionId);
            _showShellSnackBar(l10n.bufferClearedCommandKept);
          }
          if (!cleared && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.clearBufferRequiresNative)),
            );
          }
          return ShellActionBindingResult.completed(
            cleared ? l10n.bufferCleared : l10n.clearBufferUnsupported,
          );
        },
        globalSearch: (_) async {
          if (sessionState.tabs.isEmpty) {
            return ShellActionBindingResult.skipped(
              l10n.globalSearchRequiresTab,
            );
          }
          await _openGlobalSearch(sessionState);
          return const ShellActionBindingResult.completed();
        },
        autocomplete: (_) {
          if (currentSessionId == null) {
            return ShellActionBindingResult.skipped(
              l10n.autocompleteRequiresSession,
            );
          }
          _openAutocomplete();
          return const ShellActionBindingResult.completed();
        },
        autoComposer: (_) {
          if (currentSessionId == null) {
            return ShellActionBindingResult.skipped(
              l10n.autoComposerRequiresSession,
            );
          }
          _openAutoComposer();
          return const ShellActionBindingResult.completed();
        },
        searchScrollback: (_) {
          if (currentSessionId == null) {
            return ShellActionBindingResult.skipped(l10n.searchRequiresSession);
          }
          _openSearch();
          return const ShellActionBindingResult.completed();
        },
        previousPrompt: (_) {
          if (currentSessionId == null) {
            return ShellActionBindingResult.skipped(
              l10n.previousPromptRequiresSession,
            );
          }
          _navigateShellPrompt(currentSessionId, direction: -1);
          return const ShellActionBindingResult.completed();
        },
        nextPrompt: (_) {
          if (currentSessionId == null) {
            return ShellActionBindingResult.skipped(
              l10n.nextPromptRequiresSession,
            );
          }
          _navigateShellPrompt(currentSessionId, direction: 1);
          return const ShellActionBindingResult.completed();
        },
        selectCommandOutput: (_) {
          if (currentSessionId == null) {
            return ShellActionBindingResult.skipped(
              l10n.selectCommandOutputRequiresSession,
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
            return ShellActionBindingResult.skipped(
              l10n.shellIntegrationRequiresSession,
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
            return ShellActionBindingResult.skipped(
              l10n.openRecentDirectoryRequiresSession,
            );
          }
          final currentPane = _paneForSession(currentState, currentSessionId);
          final recentDirectories =
              currentPane?.shellIntegration.recentDirectories ?? const [];
          if (recentDirectories.isEmpty) {
            return ShellActionBindingResult.skipped(
              l10n.noRecentDirectoryAvailable,
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
            return ShellActionBindingResult.skipped(
              l10n.tmuxIntegrationRequiresSession,
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
            return ShellActionBindingResult.skipped(
              l10n.coprocessRequiresSession,
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
            return ShellActionBindingResult.skipped(
              l10n.annotationsRequireSession,
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
            return ShellActionBindingResult.skipped(
              l10n.capturedOutputRequiresSession,
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
            return ShellActionBindingResult.skipped(
              l10n.passwordManagerRequiresSession,
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
              : ShellActionBindingResult.skipped(l10n.hotkeyWindowUnavailable);
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
            return ShellActionBindingResult.skipped(
              l10n.layoutTemplateRequiresProfileSession,
            );
          }
          final currentTab = _tabForSession(currentState, currentSessionId);
          if (currentTab == null) {
            return ShellActionBindingResult.skipped(
              l10n.noActiveTabForLayoutTemplates,
            );
          }
          if (currentTab.effectivePanes.length > 1) {
            return ShellActionBindingResult.skipped(
              l10n.twoPaneLayoutAlreadySatisfied,
            );
          }
          if (!_splitActiveSession(
            sessionController,
            defaultProfile,
            TerminalSplitAxis.horizontal,
          )) {
            return ShellActionBindingResult.skipped(
              l10n.layoutTemplateUnavailable,
            );
          }
          return const ShellActionBindingResult.completed();
        },
        exportScrollback: (_) async {
          if (currentSessionId == null) {
            return ShellActionBindingResult.skipped(
              l10n.exportScrollbackRequiresSession,
            );
          }
          final file = await _exportVisibleFrame(currentSessionId);
          if (file == null) {
            return ShellActionBindingResult.skipped(
              l10n.noVisibleContentToExport,
            );
          }
          if (mounted) {
            _showShellPathSnackBar(
              message: l10n.scrollbackExported,
              path: file.path,
            );
          }
          return ShellActionBindingResult.completed(
            l10n.exportedTerminalScrollback,
          );
        },
        exportDiagnostics: (_) async {
          if (currentSessionId == null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.exportDiagnosticsRequiresSession)),
              );
            }
            return ShellActionBindingResult.skipped(
              l10n.exportDiagnosticsRequiresSession,
            );
          }
          final directory = await _exportDiagnosticsBundle(currentState);
          if (directory == null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.diagnosticsExportUnavailable)),
              );
            }
            return ShellActionBindingResult.skipped(
              l10n.diagnosticsExportUnavailable,
            );
          }
          if (mounted) {
            _showShellPathSnackBar(
              message: l10n.diagnosticsExported,
              path: directory.path,
            );
          }
          return ShellActionBindingResult.completed(
            l10n.exportedTerminalDiagnostics,
          );
        },
        toggleCommandFinishedNotify: (_) async {
          final previous = _commandFinishedNotificationsEnabled;
          _mutateState(() {
            _commandFinishedNotificationsEnabled =
                !_commandFinishedNotificationsEnabled;
          });
          try {
            await _saveNotificationPreferences();
            if (mounted) {
              final messenger = ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar();
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    l10n.commandFinishedNotificationsSaved(
                      _commandFinishedNotificationsEnabled.toString(),
                    ),
                  ),
                ),
              );
            }
            return const ShellActionBindingResult.completed();
          } on Object catch (error) {
            _mutateState(() {
              _commandFinishedNotificationsEnabled = previous;
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.unableSaveNotifications(error.toString())),
                ),
              );
            }
            return ShellActionBindingResult.failed(
              failureCode: ShellActionBindingFailureCode.platformFailure,
              message: l10n.unableSaveCommandFinishedNotifications,
            );
          }
        },
        toggleBellNotify: (_) async {
          final previous = _bellNotificationsEnabled;
          _mutateState(() {
            _bellNotificationsEnabled = !_bellNotificationsEnabled;
          });
          try {
            await _saveNotificationPreferences();
            if (mounted) {
              final messenger = ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar();
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    l10n.bellNotificationsSaved(
                      _bellNotificationsEnabled.toString(),
                    ),
                  ),
                ),
              );
            }
            return const ShellActionBindingResult.completed();
          } on Object catch (error) {
            _mutateState(() {
              _bellNotificationsEnabled = previous;
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.unableSaveNotifications(error.toString())),
                ),
              );
            }
            return ShellActionBindingResult.failed(
              failureCode: ShellActionBindingFailureCode.platformFailure,
              message: l10n.unableSaveBellNotifications,
            );
          }
        },
        toggleActivityMonitor: (_) async {
          final previous = _activityNotificationsEnabled;
          _mutateState(() {
            _activityNotificationsEnabled = !_activityNotificationsEnabled;
          });
          try {
            await _saveNotificationPreferences();
            if (mounted) {
              final messenger = ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar();
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    l10n.activityMonitorSaved(
                      _activityNotificationsEnabled.toString(),
                    ),
                  ),
                ),
              );
            }
            return const ShellActionBindingResult.completed();
          } on Object catch (error) {
            _mutateState(() {
              _activityNotificationsEnabled = previous;
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.unableSaveNotifications(error.toString())),
                ),
              );
            }
            return ShellActionBindingResult.failed(
              failureCode: ShellActionBindingFailureCode.platformFailure,
              message: l10n.unableSaveActivityMonitor,
            );
          }
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
        if (!_canOpenNewSessionLauncher(currentState)) {
          return;
        }
        await _openNewSessionLauncher(sessionController, currentState);
        return;
      case TerminalActionId.toolbelt:
        FocusManager.instance.primaryFocus?.unfocus();
        _mutateState(() {
          _isSftpPanelOpen = false;
          _sftpPanelSessionId = null;
          _isToolbeltOpen = true;
        });
        return;
      case TerminalActionId.openSftpPanel:
        _openSftpPanel(currentState, currentSessionId);
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
        ? context.l10n.noDefaultProfileAvailable
        : !hasCurrentDirectory
        ? context.l10n.noCurrentDirectoryAvailable
        : _shellHostIsRemote(targetPane?.shellIntegration.hostname)
        ? context.l10n.remoteDirectoryCannotDuplicate
        : null;
    final growPaneBlockedReason = targetPane == null
        ? context.l10n.addAnotherPaneForAction
        : paneManagementBlockedReason ??
              _growActivePaneUnavailableReason(tab, targetSessionId);
    final reopenClosedPaneBlockedReason = sessionController.canReopenClosedPane
        ? null
        : context.l10n.noRecentlyClosedPaneForTab;
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
                  context.l10n.unavailableReason(reason),
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
          title: context.l10n.duplicateCurrentDirectory,
          enabled: duplicateCwdBlockedReason == null,
          disabledReason: duplicateCwdBlockedReason,
        ),
        item(
          action: TerminalActionId.splitRight,
          icon: Icons.vertical_split_rounded,
          title: context.l10n.terminalActionName('split_right'),
          enabled: defaultProfile != null && splitRightBlockedReason == null,
          disabledReason: splitRightBlockedReason,
        ),
        item(
          action: TerminalActionId.splitDown,
          icon: Icons.horizontal_split_rounded,
          title: context.l10n.terminalActionName('split_down'),
          enabled: defaultProfile != null && splitDownBlockedReason == null,
          disabledReason: splitDownBlockedReason,
        ),
        item(
          action: TerminalActionId.reopenClosedPane,
          icon: Icons.restore_page_rounded,
          title: context.l10n.terminalActionName('reopen_closed_pane'),
          enabled: reopenClosedPaneBlockedReason == null,
          disabledReason: reopenClosedPaneBlockedReason,
        ),
        item(
          action: TerminalActionId.applyLayoutTemplate,
          icon: Icons.dashboard_customize_rounded,
          title: context.l10n.applyTwoPaneLayout,
          enabled: defaultProfile != null && !hasMultiplePanes,
          disabledReason: hasMultiplePanes
              ? context.l10n.tabAlreadyMultiplePanes
              : null,
        ),
        const PopupMenuDivider(),
        item(
          action: TerminalActionId.resizePane,
          icon: Icons.open_with_rounded,
          title: context.l10n.growActivePane,
          enabled: hasMultiplePanes && growPaneBlockedReason == null,
          disabledReason: growPaneBlockedReason,
        ),
        item(
          action: TerminalActionId.swapPane,
          icon: Icons.swap_horiz_rounded,
          title: context.l10n.swapActivePane,
          enabled: hasMultiplePanes && paneManagementBlockedReason == null,
          disabledReason: hasMultiplePanes
              ? paneManagementBlockedReason
              : context.l10n.addAnotherPaneForAction,
        ),
        const PopupMenuDivider(),
        item(
          action: TerminalActionId.closePane,
          icon: Icons.close_fullscreen_rounded,
          title: context.l10n.closeActivePane,
          enabled: true,
        ),
        item(
          action: TerminalActionId.closeActiveTab,
          icon: Icons.close_rounded,
          title: context.l10n.terminalActionName('close_active_tab'),
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
          _showShellSnackBar(context.l10n.remoteDirectoryCannotDuplicate);
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
