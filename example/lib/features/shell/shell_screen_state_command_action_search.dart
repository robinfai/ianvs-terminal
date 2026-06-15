part of 'shell_screen.dart';

extension _ShellScreenStateCommandActionSearch on _ShellScreenState {
  Future<void> _loadSavedCommands() async {
    final loaded = await _savedCommandRepository.load();
    if (!mounted) {
      return;
    }
    _mutateState(() {
      _savedCommands = loaded;
      _commandActionSearchController = null;
    });
  }

  void _openCommandActionSearch(String sessionId) {
    _mutateState(() {
      _isCommandActionSearchOpen = true;
      _commandActionSearchSessionId = sessionId;
      _isCommandSearchOpen = false;
      _commandSearchSessionId = null;
      _commandSearchOverlayController = null;
      _isAutocompleteOpen = false;
      _isAutoComposerOpen = false;
      _commandActionSearchController = _buildCommandActionSearchController(
        sessionId,
      );
    });
  }

  void _closeCommandActionSearch() {
    final sessionId = _commandActionSearchSessionId;
    _mutateState(() {
      _isCommandActionSearchOpen = false;
      _commandActionSearchSessionId = null;
      _commandActionSearchController = null;
    });
    _focusSession(sessionId);
  }

  CommandActionSearchController _commandActionSearchControllerFor(
    String sessionId,
  ) {
    final controller = _commandActionSearchController;
    if (controller != null && _commandActionSearchSessionId == sessionId) {
      return controller;
    }
    final nextController = _buildCommandActionSearchController(sessionId);
    _commandActionSearchController = nextController;
    _commandActionSearchSessionId = sessionId;
    return nextController;
  }

  CommandActionSearchController _buildCommandActionSearchController(
    String sessionId,
  ) {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    return _commandActionSearchShellWiring.controllerFor(
      actions: _commandActionSearchAdapter.itemsFor(
        hasActiveSession: activeSessionId != null,
        productivity: ShellProductivityState(
          readOnly: _isSessionReadOnly(sessionId),
        ),
      ),
      savedCommands: _savedCommands,
    );
  }

  Future<void> _openCommandActionSearchAction(
    String sessionId,
    String actionId,
  ) async {
    final action = _terminalActionIdForName(actionId);
    if (action == null) {
      _showCommandActionSearchBlockedIntent('Action is unavailable.');
      _focusSession(sessionId);
      return;
    }
    if (action == TerminalActionId.openActionSearch) {
      _focusSession(sessionId);
      return;
    }

    _closeCommandActionSearch();
    final sessionState = ref.read(sessionControllerProvider);
    final sessionController = ref.read(sessionControllerProvider.notifier);
    final currentSessionId = sessionState.activeSessionId;
    switch (action) {
      case TerminalActionId.openLauncher:
      case TerminalActionId.openCommandMenu:
        await _openCommandMenu(sessionController, sessionState);
      case TerminalActionId.toolbelt:
        if (currentSessionId != null) {
          _openToolbelt();
        }
      case TerminalActionId.newTab:
        final defaultProfile = _effectiveDefaultProfileFor(
          sessionState.profiles,
          sessionState.defaultProfileId,
        );
        if (defaultProfile == null) {
          return;
        }
        _createSession(
          sessionController,
          defaultProfile,
          returningToWorkspace: false,
        );
      case TerminalActionId.duplicateCurrentCwd:
        final defaultProfile = _effectiveDefaultProfileFor(
          sessionState.profiles,
          sessionState.defaultProfileId,
        );
        if (defaultProfile == null || currentSessionId == null) {
          _showCommandActionSearchBlockedIntent(
            'Duplicate current directory requires a default profile and active session.',
          );
          _focusSession(sessionId);
          return;
        }
        final currentPane = _paneForSession(sessionState, currentSessionId);
        final currentDirectory = currentPane?.shellIntegration.currentDirectory;
        if (currentDirectory == null || currentDirectory.isEmpty) {
          _showCommandActionSearchBlockedIntent(
            'No current directory is available to duplicate.',
          );
          _focusSession(sessionId);
          return;
        }
        _createSession(
          sessionController,
          defaultProfile,
          returningToWorkspace: false,
        );
        final duplicateSessionId = ref
            .read(sessionControllerProvider)
            .activeSessionId;
        if (duplicateSessionId == null) {
          _showCommandActionSearchBlockedIntent(
            'No duplicated session was created.',
          );
          _focusSession(sessionId);
          return;
        }
        _sendPlainTextToSession(
          duplicateSessionId,
          'cd ${_shellQuotedPath(currentDirectory)}',
        );
      case TerminalActionId.closeActiveTab:
        if (currentSessionId == null) {
          _showCommandActionSearchBlockedIntent(
            'Close tab requires an active session.',
          );
          _focusSession(sessionId);
          return;
        }
        _closeSession(sessionController, sessionState, currentSessionId);
      case TerminalActionId.reopenClosedTab:
        if (!sessionController.canReopenClosedTab) {
          _showCommandActionSearchBlockedIntent(
            'No recently closed tab is available.',
          );
          _focusSession(sessionId);
          return;
        }
        sessionController.reopenClosedTab();
        _focusSession(ref.read(sessionControllerProvider).activeSessionId);
      case TerminalActionId.reopenClosedPane:
        _showCommandActionSearchBlockedIntent(
          'Reopen closed pane is not available yet.',
        );
        _focusSession(sessionId);
      case TerminalActionId.splitRight:
        if (currentSessionId != null) {
          final defaultProfile = _effectiveDefaultProfileFor(
            sessionState.profiles,
            sessionState.defaultProfileId,
          );
          if (defaultProfile == null) {
            return;
          }
          final conflictReason = _splitAxisConflictReason(
            sessionState,
            currentSessionId,
            TerminalSplitAxis.horizontal,
          );
          if (conflictReason != null) {
            _showCommandActionSearchBlockedIntent(conflictReason);
            _focusSession(sessionId);
            return;
          }
          _splitActiveSession(
            sessionController,
            defaultProfile,
            TerminalSplitAxis.horizontal,
          );
        }
      case TerminalActionId.splitDown:
        if (currentSessionId != null) {
          final defaultProfile = _effectiveDefaultProfileFor(
            sessionState.profiles,
            sessionState.defaultProfileId,
          );
          if (defaultProfile == null) {
            return;
          }
          final conflictReason = _splitAxisConflictReason(
            sessionState,
            currentSessionId,
            TerminalSplitAxis.vertical,
          );
          if (conflictReason != null) {
            _showCommandActionSearchBlockedIntent(conflictReason);
            _focusSession(sessionId);
            return;
          }
          _splitActiveSession(
            sessionController,
            defaultProfile,
            TerminalSplitAxis.vertical,
          );
        }
      case TerminalActionId.applyLayoutTemplate:
        if (currentSessionId != null) {
          final defaultProfile = _effectiveDefaultProfileFor(
            sessionState.profiles,
            sessionState.defaultProfileId,
          );
          if (defaultProfile == null) {
            return;
          }
          final currentTab = _tabForSession(sessionState, currentSessionId);
          if (currentTab == null) {
            return;
          }
          if (currentTab.effectivePanes.length > 1) {
            _showCommandActionSearchBlockedIntent(
              'Two-pane layout template is already satisfied.',
            );
            _focusSession(sessionId);
            return;
          }
          _splitActiveSession(
            sessionController,
            defaultProfile,
            TerminalSplitAxis.horizontal,
          );
        }
      case TerminalActionId.zoomPane:
        if (currentSessionId != null) {
          final currentTab = _tabForSession(sessionState, currentSessionId);
          if ((currentTab?.effectivePanes.length ?? 0) < 2) {
            _showCommandActionSearchBlockedIntent(
              'Zoom pane requires at least two panes.',
            );
            _focusSession(sessionId);
            return;
          }
          _mutateState(() {
            _zoomedPaneSessionId = _zoomedPaneSessionId == currentSessionId
                ? null
                : currentSessionId;
          });
          _focusSession(currentSessionId);
        }
      case TerminalActionId.focusNextPane:
        if (currentSessionId == null) {
          _showCommandActionSearchBlockedIntent(
            'Focus next pane requires an active session.',
          );
          _focusSession(sessionId);
          return;
        }
        final currentTab = _tabForSession(sessionState, currentSessionId);
        final blockedReason = currentTab == null
            ? null
            : _zoomedPaneManagementUnavailableReason(currentTab);
        if (blockedReason != null) {
          _showCommandActionSearchBlockedIntent(blockedReason);
          _focusSession(sessionId);
          return;
        }
        if (currentTab == null ||
            !_focusRelativePane(
              sessionController,
              currentTab,
              currentSessionId,
              delta: 1,
            )) {
          _showCommandActionSearchBlockedIntent('No next pane is available.');
          _focusSession(sessionId);
          return;
        }
      case TerminalActionId.focusPreviousPane:
        if (currentSessionId == null) {
          _showCommandActionSearchBlockedIntent(
            'Focus previous pane requires an active session.',
          );
          _focusSession(sessionId);
          return;
        }
        final previousTab = _tabForSession(sessionState, currentSessionId);
        final previousBlockedReason = previousTab == null
            ? null
            : _zoomedPaneManagementUnavailableReason(previousTab);
        if (previousBlockedReason != null) {
          _showCommandActionSearchBlockedIntent(previousBlockedReason);
          _focusSession(sessionId);
          return;
        }
        if (previousTab == null ||
            !_focusRelativePane(
              sessionController,
              previousTab,
              currentSessionId,
              delta: -1,
            )) {
          _showCommandActionSearchBlockedIntent(
            'No previous pane is available.',
          );
          _focusSession(sessionId);
          return;
        }
      case TerminalActionId.swapPane:
        if (currentSessionId == null) {
          _showCommandActionSearchBlockedIntent(
            'Swap pane requires an active session.',
          );
          _focusSession(sessionId);
          return;
        }
        final swapTab = _tabForSession(sessionState, currentSessionId);
        final swapBlockedReason = swapTab == null
            ? null
            : _zoomedPaneManagementUnavailableReason(swapTab);
        if (swapBlockedReason != null) {
          _showCommandActionSearchBlockedIntent(swapBlockedReason);
          _focusSession(sessionId);
          return;
        }
        if ((swapTab?.effectivePanes.length ?? 0) < 2) {
          _showCommandActionSearchBlockedIntent(
            'Swap pane requires at least two panes.',
          );
          _focusSession(sessionId);
          return;
        }
        sessionController.swapActivePaneWithSibling();
        _focusSession(currentSessionId);
      case TerminalActionId.resizePane:
        if (currentSessionId == null) {
          _showCommandActionSearchBlockedIntent(
            'Resize pane requires an active session.',
          );
          _focusSession(sessionId);
          return;
        }
        final resizeTab = _tabForSession(sessionState, currentSessionId);
        final resizeBlockedReason = resizeTab == null
            ? null
            : _zoomedPaneManagementUnavailableReason(resizeTab);
        if (resizeBlockedReason != null) {
          _showCommandActionSearchBlockedIntent(resizeBlockedReason);
          _focusSession(sessionId);
          return;
        }
        if (resizeTab == null) {
          _showCommandActionSearchBlockedIntent(
            'Resize pane requires at least two panes.',
          );
          _focusSession(sessionId);
          return;
        }
        final growthBlockedReason = _growActivePaneUnavailableReason(
          resizeTab,
          currentSessionId,
        );
        if (growthBlockedReason != null ||
            !_growActivePane(resizeTab, currentSessionId)) {
          _showCommandActionSearchBlockedIntent(
            growthBlockedReason ?? 'Resize pane requires at least two panes.',
          );
          _focusSession(sessionId);
          return;
        }
        _focusSession(currentSessionId);
      case TerminalActionId.closePane:
        if (currentSessionId == null) {
          _showCommandActionSearchBlockedIntent(
            'Close pane requires an active session.',
          );
          _focusSession(sessionId);
          return;
        }
        _closeSession(sessionController, sessionState, currentSessionId);
      case TerminalActionId.search:
        _openSearch();
      case TerminalActionId.nextSearchMatch:
        _moveSearchMatch(-1);
      case TerminalActionId.previousSearchMatch:
        _moveSearchMatch(1);
      case TerminalActionId.clearSearch:
        _clearSearch();
      case TerminalActionId.globalSearch:
        if (sessionState.tabs.isNotEmpty) {
          await _openGlobalSearch(sessionState);
        }
      case TerminalActionId.autocomplete:
        if (currentSessionId != null) {
          _openAutocomplete();
        }
      case TerminalActionId.autoComposer:
        if (currentSessionId != null) {
          _openAutoComposer();
        }
      case TerminalActionId.toggleReadOnly:
        if (currentSessionId != null) {
          _toggleReadOnlySessionWithFeedback(currentSessionId);
        }
      case TerminalActionId.clearScrollback:
        if (currentSessionId == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Clear scrollback requires an active session.'),
              ),
            );
          }
          return;
        }
        final cleared = ref
            .read(terminalRuntimeControllerProvider)
            .clearScrollback(currentSessionId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                cleared
                    ? 'Cleared scrollback.'
                    : 'Clear scrollback requires native runtime support.',
              ),
            ),
          );
        }
      case TerminalActionId.paste:
        if (currentSessionId == null) {
          _showCommandActionSearchBlockedIntent(
            'Paste requires an active session.',
          );
          _focusSession(sessionId);
          return;
        }
        await _pasteToSession(currentSessionId);
        _focusSession(currentSessionId);
      case TerminalActionId.pasteHistory:
        if (currentSessionId != null) {
          await _openPasteHistory(sessionState);
        }
      case TerminalActionId.advancedPaste:
        if (currentSessionId != null) {
          await _openAdvancedPaste(currentSessionId);
        }
      case TerminalActionId.copy:
        if (currentSessionId != null) {
          final selectionController = _selectionControllers[currentSessionId];
          if (selectionController != null) {
            await _copySelection(
              sessionController,
              currentSessionId,
              selectionController,
            );
          }
        }
      case TerminalActionId.copyCommandOutput:
        if (currentSessionId != null) {
          final selectionController = _selectionControllers.putIfAbsent(
            currentSessionId,
            SelectionController.new,
          );
          if (_selectLastCommandOutput(
            sessionController,
            currentSessionId,
            selectionController,
          )) {
            await _copySelection(
              sessionController,
              currentSessionId,
              selectionController,
            );
          } else {
            _focusSession(sessionId);
          }
        }
      case TerminalActionId.copyBlockOutput:
      case TerminalActionId.reInputBlockCommand:
      case TerminalActionId.rerunBlockCommand:
        _showCommandActionSearchBlockedIntent('No command block is selected.');
        _focusSession(sessionId);
      case TerminalActionId.copyMode:
        if (currentSessionId != null) {
          final selectionController = _selectionControllers.putIfAbsent(
            currentSessionId,
            SelectionController.new,
          );
          _enterCopyMode(
            sessionController,
            currentSessionId,
            selectionController,
          );
        }
      case TerminalActionId.capturedOutput:
        if (currentSessionId != null) {
          await _openCapturedOutput(currentSessionId);
        }
      case TerminalActionId.annotations:
        if (currentSessionId != null) {
          final selectionController = _selectionControllers.putIfAbsent(
            currentSessionId,
            SelectionController.new,
          );
          await _openAnnotations(
            sessionController,
            currentSessionId,
            selectionController,
          );
        }
      case TerminalActionId.shellIntegrationUtilities:
        if (currentSessionId != null) {
          await _openShellIntegrationUtilities(sessionState, currentSessionId);
        }
      case TerminalActionId.openRecentDirectory:
        if (currentSessionId == null) {
          _showCommandActionSearchBlockedIntent(
            'Open recent directory requires an active session.',
          );
          _focusSession(sessionId);
          return;
        }
        final currentPane = _paneForSession(sessionState, currentSessionId);
        final recentDirectories =
            currentPane?.shellIntegration.recentDirectories ?? const [];
        if (recentDirectories.isEmpty) {
          _showCommandActionSearchBlockedIntent(
            'No recent directory is available.',
          );
          _focusSession(sessionId);
          return;
        }
        _sendPlainTextToSession(
          currentSessionId,
          'cd ${_shellQuotedPath(recentDirectories.first)}',
        );
        _focusSession(currentSessionId);
      case TerminalActionId.selectCommandOutput:
        if (currentSessionId != null) {
          final selectionController = _selectionControllers.putIfAbsent(
            currentSessionId,
            SelectionController.new,
          );
          if (!_selectLastCommandOutput(
            sessionController,
            currentSessionId,
            selectionController,
          )) {
            _focusSession(sessionId);
          }
        }
      case TerminalActionId.tmuxIntegration:
        if (currentSessionId != null) {
          await _openTmuxIntegration(currentSessionId);
        }
      case TerminalActionId.coprocess:
        if (currentSessionId != null) {
          await _openCoprocess(currentSessionId);
        }
      case TerminalActionId.passwordManager:
        if (currentSessionId != null) {
          await _openPasswordManager(sessionController, currentSessionId);
        }
      case TerminalActionId.instantReplay:
        if (currentSessionId != null) {
          await _openInstantReplay(sessionState);
        }
      case TerminalActionId.hotkeyWindow:
        await _toggleHotkeyWindowWithFeedback();
      case TerminalActionId.defaults:
      case TerminalActionId.openDefaults:
        await _openDefaultsAndAppearance(sessionController, sessionState);
      case TerminalActionId.profiles:
        await _openProfilesSheet(sessionController, sessionState);
      case TerminalActionId.dynamicProfiles:
        await _openDynamicProfiles(sessionController);
      case TerminalActionId.openThemePicker:
        await _openDefaultsAndAppearance(sessionController, sessionState);
      case TerminalActionId.applyTheme:
        _showCommandActionSearchBlockedIntent(
          'Apply theme requires choosing a theme preset.',
        );
        _focusSession(sessionId);
      case TerminalActionId.exportScrollback:
        if (currentSessionId == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Export scrollback requires an active session.'),
              ),
            );
          }
          return;
        }
        final file = await _exportVisibleFrame(currentSessionId);
        if (file == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'No visible terminal content is available to export.',
                ),
              ),
            );
          }
          return;
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Scrollback exported to ${file.path}'),
              duration: const Duration(seconds: 8),
              action: SnackBarAction(
                label: 'Copy path',
                onPressed: () {
                  unawaited(Clipboard.setData(ClipboardData(text: file.path)));
                },
              ),
            ),
          );
        }
      case TerminalActionId.exportDiagnostics:
        if (currentSessionId == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Export diagnostics requires an active session.'),
              ),
            );
          }
          return;
        }
        final directory = await _exportDiagnosticsBundle(sessionState);
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
          return;
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Diagnostics exported to ${directory.path}'),
              duration: const Duration(seconds: 8),
              action: SnackBarAction(
                label: 'Copy path',
                onPressed: () {
                  unawaited(
                    Clipboard.setData(ClipboardData(text: directory.path)),
                  );
                },
              ),
            ),
          );
        }
      case TerminalActionId.toggleCommandFinishedNotify:
        _mutateState(() {
          _commandFinishedNotificationsEnabled =
              !_commandFinishedNotificationsEnabled;
        });
        unawaited(_saveNotificationPreferences());
        final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Command-finished notifications ${_commandFinishedNotificationsEnabled ? 'enabled' : 'disabled'} and saved.',
            ),
          ),
        );
      case TerminalActionId.toggleBellNotify:
        _mutateState(() {
          _bellNotificationsEnabled = !_bellNotificationsEnabled;
        });
        unawaited(_saveNotificationPreferences());
        final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Bell notifications ${_bellNotificationsEnabled ? 'enabled' : 'disabled'} and saved.',
            ),
          ),
        );
      case TerminalActionId.toggleActivityMonitor:
        _mutateState(() {
          _activityNotificationsEnabled = !_activityNotificationsEnabled;
        });
        unawaited(_saveNotificationPreferences());
        final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Activity monitor ${_activityNotificationsEnabled ? 'enabled' : 'disabled'} and saved.',
            ),
          ),
        );
      default:
        _showCommandActionSearchBlockedIntent(
          'This action still opens from the command menu.',
        );
        _focusSession(sessionId);
    }
  }

  Future<void> _insertCommandActionSearchSavedCommand(
    String sessionId,
    String command,
  ) async {
    final intent = _commandActionSearchShellWiring
        .terminalIntentForSavedCommand(
          command,
          readOnly: _isSessionReadOnly(sessionId),
        );
    await _dispatchCommandActionSearchTerminalIntent(sessionId, intent);
  }

  Future<void> _dispatchCommandActionSearchTerminalIntent(
    String sessionId,
    CommandSearchTerminalIntent intent,
  ) async {
    final text = intent.text;
    switch (intent.kind) {
      case CommandSearchTerminalIntentKind.none:
        _focusSession(sessionId);
      case CommandSearchTerminalIntentKind.disabled:
        _showCommandSearchBlockedIntent(intent.reason);
        _focusSession(sessionId);
      case CommandSearchTerminalIntentKind.insertText:
      case CommandSearchTerminalIntentKind.executeText:
        if (text != null && _sendPlainTextToSession(sessionId, text)) {
          _closeCommandActionSearch();
        }
      case CommandSearchTerminalIntentKind.requiresPastePolicy:
        if (text != null) {
          await _pasteTextToSessionWithPolicy(sessionId, text);
          _closeCommandActionSearch();
        }
    }
  }

  TerminalActionId? _terminalActionIdForName(String name) {
    for (final actionId in TerminalActionId.values) {
      if (actionId.name == name) {
        return actionId;
      }
    }
    return null;
  }

  void _showCommandActionSearchBlockedIntent(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
