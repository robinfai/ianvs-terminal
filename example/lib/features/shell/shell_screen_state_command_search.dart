part of 'shell_screen.dart';

extension _ShellScreenStateCommandSearch on _ShellScreenState {
  KeyEventResult? _handleCommandSearchKey(
    KeyEvent event,
    String? activeSessionId,
  ) {
    if (!_isCommandSearchShortcut(event)) {
      return null;
    }
    if (_isCommandMenuOpen || _isDefaultsOpen || _isProfilesOpen) {
      return KeyEventResult.handled;
    }
    if (activeSessionId == null) {
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) {
      return KeyEventResult.handled;
    }
    _openCommandSearch(activeSessionId);
    return KeyEventResult.handled;
  }

  bool _isCommandSearchShortcut(KeyEvent event) {
    return event.logicalKey == LogicalKeyboardKey.keyR &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed);
  }

  void _openCommandSearch(String sessionId) {
    _mutateState(() {
      _isCommandSearchOpen = true;
      _commandSearchSessionId = sessionId;
      _commandSearchOverlayController = _commandSearchShellWiring.controllerFor(
        _commandCenterRuntime,
        sessionId: sessionId,
      );
    });
  }

  void _closeCommandSearch() {
    final sessionId = _commandSearchSessionId;
    _mutateState(() {
      _isCommandSearchOpen = false;
      _commandSearchSessionId = null;
      _commandSearchOverlayController = null;
    });
    _focusSession(sessionId);
  }

  CommandSearchOverlayController _commandSearchControllerFor(String sessionId) {
    final controller = _commandSearchOverlayController;
    if (controller != null && _commandSearchSessionId == sessionId) {
      return controller;
    }
    final nextController = _commandSearchShellWiring.controllerFor(
      _commandCenterRuntime,
      sessionId: sessionId,
    );
    _commandSearchOverlayController = nextController;
    _commandSearchSessionId = sessionId;
    return nextController;
  }

  Future<void> _insertCommandSearchSelection(String sessionId, String command) {
    return _dispatchCommandSearchOutput(
      sessionId,
      CommandSearchOverlayOutput.insert(command),
    );
  }

  Future<void> _executeCommandSearchSelection(
    String sessionId,
    String command,
  ) {
    return _dispatchCommandSearchOutput(
      sessionId,
      CommandSearchOverlayOutput.explicitExecute(command),
    );
  }

  Future<void> _dispatchCommandSearchOutput(
    String sessionId,
    CommandSearchOverlayOutput output,
  ) async {
    final intent = _commandSearchShellWiring.terminalIntentFor(
      output,
      readOnly: _isSessionReadOnly(sessionId),
    );
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
          _closeCommandSearch();
        }
      case CommandSearchTerminalIntentKind.requiresPastePolicy:
        if (text != null) {
          await _pasteTextToSessionWithPolicy(sessionId, text);
          _closeCommandSearch();
        }
    }
  }

  void _showCommandSearchBlockedIntent(
    CommandSearchTerminalIntentReason? reason,
  ) {
    if (!mounted) {
      return;
    }
    final message = switch (reason) {
      CommandSearchTerminalIntentReason.readOnly =>
        'Read-only mode is enabled.',
      CommandSearchTerminalIntentReason.emptySelection =>
        'No command is selected.',
      CommandSearchTerminalIntentReason.multilineRequiresPastePolicy =>
        'This command requires paste confirmation.',
      null => 'Command search action is unavailable.',
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
