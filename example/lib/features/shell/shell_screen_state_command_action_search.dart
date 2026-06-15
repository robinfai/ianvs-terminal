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
    final themePresetId = _commandActionSearchThemePresetIdFor(actionId);
    if (themePresetId != null) {
      _closeCommandActionSearch();
      await _applyCommandActionSearchThemePreset(sessionId, themePresetId);
      return;
    }

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
        if (!sessionController.canReopenClosedPane) {
          _showCommandActionSearchBlockedIntent(
            'No recently closed pane is available.',
          );
          _focusSession(sessionId);
          return;
        }
        sessionController.reopenClosedPane();
        _focusSession(ref.read(sessionControllerProvider).activeSessionId);
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
      case TerminalActionId.saveBlockOutput:
      case TerminalActionId.openInReview:
      case TerminalActionId.searchWithinBlock:
      case TerminalActionId.reInputBlockCommand:
      case TerminalActionId.rerunBlockCommand:
        await _dispatchCommandActionSearchBlockAction(
          action,
          sessionId: sessionId,
          sessionState: sessionState,
          sessionController: sessionController,
        );
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

  Future<void> _dispatchCommandActionSearchBlockAction(
    TerminalActionId actionId, {
    required String sessionId,
    required SessionState sessionState,
    required SessionController sessionController,
  }) async {
    final currentSessionId = sessionState.activeSessionId;
    if (currentSessionId == null) {
      _showCommandActionSearchBlockedIntent(
        'Command block actions require an active session.',
      );
      _focusSession(sessionId);
      return;
    }
    final action = _commandBlockActionForActionSearch(actionId);
    final block = _activeCommandActionSearchBlock(
      sessionState,
      currentSessionId,
    );
    if (action == null || block == null) {
      _showCommandActionSearchBlockedIntent('No command block is selected.');
      _focusSession(sessionId);
      return;
    }

    final result = const CommandBlockActionReducer().reduce(
      action,
      block,
      readOnly: _isSessionReadOnly(currentSessionId),
    );
    if (!result.enabled) {
      _showCommandActionSearchBlockedIntent(
        _commandActionSearchBlockDisabledMessage(result.disabledReason),
      );
      _focusSession(sessionId);
      return;
    }
    await _dispatchCommandActionSearchBlockIntent(
      currentSessionId,
      sessionController,
      result.intent,
      sessionState: sessionState,
      block: block,
    );
  }

  Future<void> _dispatchCommandActionSearchBlockIntent(
    String sessionId,
    SessionController sessionController,
    CommandBlockActionIntent intent, {
    SessionState? sessionState,
    CommandBlock? block,
  }) async {
    switch (intent.kind) {
      case CommandBlockActionIntentKind.none:
        _focusSession(sessionId);
      case CommandBlockActionIntentKind.clipboardText:
        final text = intent.text;
        if (text != null) {
          await Clipboard.setData(ClipboardData(text: text));
        }
        _focusSession(sessionId);
      case CommandBlockActionIntentKind.copyOutputRange:
        final outputRange = intent.outputRange;
        if (outputRange == null) {
          _showCommandActionSearchBlockedIntent(
            'No command block output is available.',
          );
          _focusSession(sessionId);
          return;
        }
        final selectionController = _selectionControllers.putIfAbsent(
          sessionId,
          SelectionController.new,
        );
        _selectCommandBlockOutputRange(
          sessionController,
          sessionId,
          selectionController,
          outputRange,
        );
        await _copySelection(sessionController, sessionId, selectionController);
      case CommandBlockActionIntentKind.clipboardCommandAndOutput:
        final outputRange = intent.outputRange;
        final command = intent.text;
        if (outputRange == null || command == null) {
          _showCommandActionSearchBlockedIntent(
            'No command block output is available.',
          );
          _focusSession(sessionId);
          return;
        }
        final selectionController = _selectionControllers.putIfAbsent(
          sessionId,
          SelectionController.new,
        );
        _selectCommandBlockOutputRange(
          sessionController,
          sessionId,
          selectionController,
          outputRange,
        );
        final output = _selectionTextForSession(
          sessionController,
          sessionId,
          selectionController,
        );
        await Clipboard.setData(
          ClipboardData(
            text: [command, if (output.isNotEmpty) output].join('\n'),
          ),
        );
        _focusSession(sessionId);
      case CommandBlockActionIntentKind.terminalWrite:
        final terminalIntent = intent.terminalIntent;
        if (terminalIntent == null) {
          _focusSession(sessionId);
          return;
        }
        await _dispatchCommandActionSearchTerminalIntent(
          sessionId,
          terminalIntent,
        );
      case CommandBlockActionIntentKind.scopedSearch:
        final outputRange = intent.outputRange;
        if (outputRange == null) {
          _showCommandActionSearchBlockedIntent(
            'No command block output is available.',
          );
          _focusSession(sessionId);
          return;
        }
        _openSearch(scopedOutputRange: outputRange);
      case CommandBlockActionIntentKind.saveOutput:
        final outputRange = intent.outputRange;
        if (outputRange == null) {
          _showCommandActionSearchBlockedIntent(
            'No command block output is available.',
          );
          _focusSession(sessionId);
          return;
        }
        final file = await _saveCommandBlockOutput(
          sessionController: sessionController,
          sessionId: sessionId,
          blockId: intent.blockId,
          outputRange: outputRange,
        );
        if (file == null) {
          _showCommandActionSearchBlockedIntent(
            'No command block output is available.',
          );
          _focusSession(sessionId);
          return;
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Command block output saved to ${file.path}'),
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
        _focusSession(sessionId);
      case CommandBlockActionIntentKind.reviewEntrypoint:
        if (sessionState == null || block == null) {
          _showCommandActionSearchBlockedIntent(
            'Open in review is not available for this command block.',
          );
          _focusSession(sessionId);
          return;
        }
        final opened = _openCommandBlockReviewFromActionSearch(
          sessionState: sessionState,
          block: block,
        );
        if (!opened) {
          _focusSession(sessionId);
        }
    }
  }

  CommandBlock? _activeCommandActionSearchBlock(
    SessionState sessionState,
    String sessionId,
  ) {
    final rangeState = _commandCenterRuntime.blockRangeState(
      rangesByInvocationId: _commandBlockRangesForSession(
        sessionState,
        sessionId,
      ),
    );
    final blocks = rangeState.blocksForScope(CommandBlockScope(sessionId));
    if (blocks.isEmpty) {
      return null;
    }
    final selectedBlockId = _selectedCommandBlockIdsBySession[sessionId];
    if (selectedBlockId != null) {
      final selectedBlock = rangeState.blockByInvocationId(selectedBlockId);
      if (selectedBlock?.scope == CommandBlockScope(sessionId)) {
        return selectedBlock;
      }
    }
    return blocks.last;
  }

  Map<String, CommandBlockTerminalRanges> _commandBlockRangesForSession(
    SessionState sessionState,
    String sessionId,
  ) {
    final pane = _paneForSession(sessionState, sessionId);
    final promptMarks = pane?.shellIntegration.promptMarks ?? const [];
    if (promptMarks.length < 2) {
      return const <String, CommandBlockTerminalRanges>{};
    }

    final ranges = <String, CommandBlockTerminalRanges>{};
    final sortedMarks = [...promptMarks]
      ..sort((a, b) => a.scrollbackOffset.compareTo(b.scrollbackOffset));
    var nextPromptSearchIndex = 0;
    for (final invocation
        in _commandCenterRuntime.lifecycle.invocationsForSession(sessionId)) {
      final startIndex = _promptMarkIndexForCommand(
        sortedMarks,
        invocation.command,
        startAt: nextPromptSearchIndex,
      );
      if (startIndex == -1 || startIndex + 1 >= sortedMarks.length) {
        continue;
      }
      final inputRow = sortedMarks[startIndex].scrollbackOffset;
      final outputEndRow = sortedMarks[startIndex + 1].scrollbackOffset;
      ranges[invocation.id] = CommandBlockTerminalRanges(
        inputRange: CommandBlockRowRange(
          startRow: inputRow,
          endRowExclusive: inputRow + 1,
        ),
        outputRange: CommandBlockRowRange(
          startRow: inputRow + 1,
          endRowExclusive: outputEndRow,
        ),
      );
      nextPromptSearchIndex = startIndex + 1;
    }
    return ranges;
  }

  int _promptMarkIndexForCommand(
    List<TerminalShellPromptMark> promptMarks,
    String command, {
    required int startAt,
  }) {
    final trimmedCommand = command.trim();
    for (var index = startAt; index < promptMarks.length; index += 1) {
      if (promptMarks[index].command?.trim() == trimmedCommand) {
        return index;
      }
    }
    return -1;
  }

  void _selectCommandBlockOutputRange(
    SessionController sessionController,
    String sessionId,
    SelectionController selectionController,
    CommandBlockRowRange outputRange,
  ) {
    final endRow = math.max(
      outputRange.startRow,
      outputRange.endRowExclusive - 1,
    );
    final frame = sessionController.viewportFor(sessionId).frame;
    selectionController.setSelection(
      terminal.TerminalSelection(
        startRow: outputRange.startRow,
        startCol: 0,
        endRow: endRow,
        endCol: _rowEndColumn(frame, endRow),
      ),
    );
    _focusSession(sessionId);
  }

  Future<File?> _saveCommandBlockOutput({
    required SessionController sessionController,
    required String sessionId,
    required String? blockId,
    required CommandBlockRowRange outputRange,
  }) async {
    final selectionController = _selectionControllers.putIfAbsent(
      sessionId,
      SelectionController.new,
    );
    _selectCommandBlockOutputRange(
      sessionController,
      sessionId,
      selectionController,
      outputRange,
    );
    final output = _selectionTextForSession(
      sessionController,
      sessionId,
      selectionController,
    ).trimRight();
    if (output.trim().isEmpty) {
      return null;
    }

    final capturedAt = DateTime.now();
    final supportDirectory = await getApplicationSupportDirectory();
    final exportDirectory = Directory(
      '${supportDirectory.path}/scrollback_exports',
    );
    final safeBlockId = blockId?.trim();
    final blockSegment = safeBlockId != null && safeBlockId.isNotEmpty
        ? safeBlockId
        : sessionId;
    final basename = [
      'command-block',
      blockSegment,
      capturedAt.millisecondsSinceEpoch.toString(),
    ].join('-');

    return LocalTerminalScrollbackExporter.write(
      directory: exportDirectory,
      basename: basename,
      export: LocalTerminalScrollbackExport(
        format: LocalTerminalExportFormat.plainText,
        content: output,
        metadata: <String, Object?>{
          'sessionId': sessionId,
          if (safeBlockId != null && safeBlockId.isNotEmpty)
            'blockId': safeBlockId,
          'scope': 'command-block-output',
          'capturedAt': capturedAt.toIso8601String(),
        },
      ),
      policy: const LocalTerminalScrollbackExportPolicy(),
    );
  }

  bool _openCommandBlockReviewFromActionSearch({
    required SessionState sessionState,
    required CommandBlock block,
  }) {
    final result = CommandReviewEntrypointResolver(
      store: ref.read(instantReplayStoreProvider),
    ).resolve(CommandReviewEntrypointAction.openInReview, block);
    if (!result.enabled) {
      _showCommandActionSearchBlockedIntent(
        _commandActionSearchReviewDisabledMessage(result.disabledReason),
      );
      return false;
    }

    final intent = result.intent;
    final commandLabel = block.command.trim();
    final reviewLabel = commandLabel.isEmpty ? 'command block' : commandLabel;
    _closeCommandActionSearch();
    _mutateState(() {
      _instantReplayWorkspaceSession = _InstantReplayWorkspaceSession(
        sourceSessionId: block.sessionId,
        sourceLabel:
            'Review: $reviewLabel • ${_instantReplaySourceLabelFor(sessionState, block.sessionId)}',
        frames: intent.replayFrames,
        targetFrame: intent.targetFrame,
        targetRow: intent.targetRow,
      );
    });
    return true;
  }

  CommandBlockAction? _commandBlockActionForActionSearch(
    TerminalActionId actionId,
  ) {
    return switch (actionId) {
      TerminalActionId.copyBlockOutput => CommandBlockAction.copyOutput,
      TerminalActionId.saveBlockOutput => CommandBlockAction.saveOutput,
      TerminalActionId.openInReview => CommandBlockAction.openReviewEntrypoint,
      TerminalActionId.searchWithinBlock =>
        CommandBlockAction.searchWithinBlock,
      TerminalActionId.reInputBlockCommand => CommandBlockAction.reInput,
      TerminalActionId.rerunBlockCommand => CommandBlockAction.rerun,
      _ => null,
    };
  }

  String _commandActionSearchReviewDisabledMessage(
    CommandReviewEntrypointDisabledReason? reason,
  ) {
    return switch (reason) {
      CommandReviewEntrypointDisabledReason.missingOutputRange =>
        'No command block output is available.',
      CommandReviewEntrypointDisabledReason.missingReplayFrame =>
        'No replay frame is available for this command block.',
      CommandReviewEntrypointDisabledReason.diffUnavailable =>
        'Diff review is not available for this command block.',
      null => 'Open in review is not available for this command block.',
    };
  }

  String _commandActionSearchBlockDisabledMessage(
    CommandBlockActionDisabledReason? reason,
  ) {
    return switch (reason) {
      CommandBlockActionDisabledReason.emptyCommand =>
        'No command block command is available.',
      CommandBlockActionDisabledReason.missingOutputRange =>
        'No command block output is available.',
      CommandBlockActionDisabledReason.missingTerminalFrame =>
        'No terminal frame is available.',
      CommandBlockActionDisabledReason.readOnly => 'Read-only mode is enabled.',
      CommandBlockActionDisabledReason.requiresPastePolicy =>
        'Command block paste requires confirmation.',
      null => 'Command block action is unavailable.',
    };
  }

  TerminalActionId? _terminalActionIdForName(String name) {
    for (final actionId in TerminalActionId.values) {
      if (actionId.name == name) {
        return actionId;
      }
    }
    return null;
  }

  String? _commandActionSearchThemePresetIdFor(String actionId) {
    const prefix = ShellCommandActionSearchAdapter.applyThemeActionIdPrefix;
    if (!actionId.startsWith(prefix)) {
      return null;
    }
    final themePresetId = actionId.substring(prefix.length).trim();
    return themePresetId.isEmpty ? null : themePresetId;
  }

  Future<void> _applyCommandActionSearchThemePreset(
    String sessionId,
    String themePresetId,
  ) async {
    final sessionState = ref.read(sessionControllerProvider);
    final sessionController = ref.read(sessionControllerProvider.notifier);
    final preset = _terminalThemePresetForId(themePresetId);
    if (preset == null) {
      _showCommandActionSearchBlockedIntent('Theme preset is unavailable.');
      _focusSession(sessionId);
      return;
    }
    final profile = _effectiveDefaultProfileFor(
      sessionState.profiles,
      sessionState.defaultProfileId,
    );
    if (profile == null) {
      _showCommandActionSearchBlockedIntent(
        'Apply theme requires a default profile.',
      );
      _focusSession(sessionId);
      return;
    }

    await sessionController.saveProfile(
      profile.copyWith(
        appearance: profile.appearance.copyWith(colors: preset.palette),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Applied ${preset.name} theme to ${profile.name}.'),
        ),
      );
    }
    _focusSession(sessionId);
  }

  TerminalThemePreset? _terminalThemePresetForId(String presetId) {
    for (final preset in terminalThemePresets) {
      if (preset.id == presetId) {
        return preset;
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
