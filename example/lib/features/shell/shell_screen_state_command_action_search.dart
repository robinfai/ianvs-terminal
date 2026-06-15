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
      case TerminalActionId.search:
        _openSearch();
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
      case TerminalActionId.pasteHistory:
        if (currentSessionId != null) {
          await _openPasteHistory(sessionState);
        }
      case TerminalActionId.advancedPaste:
        if (currentSessionId != null) {
          await _openAdvancedPaste(currentSessionId);
        }
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
      case TerminalActionId.hotkeyWindow:
        await _toggleHotkeyWindowWithFeedback();
      case TerminalActionId.defaults:
      case TerminalActionId.openDefaults:
        await _openDefaultsAndAppearance(sessionController, sessionState);
      case TerminalActionId.profiles:
        await _openProfilesSheet(sessionController, sessionState);
      case TerminalActionId.dynamicProfiles:
        await _openDynamicProfiles(sessionController);
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
