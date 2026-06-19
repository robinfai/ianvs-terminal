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
      _isToolbeltOpen = false;
      _isCommandSearchOpen = true;
      _commandSearchSessionId = sessionId;
      _commandSearchOverlayController = _commandSearchShellWiring.controllerFor(
        _commandCenterRuntime,
        sessionId: sessionId,
        globalHistory: _globalCommandHistory,
      );
    });
  }

  Future<void> _handleNativeCommandSearchMenu() async {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId == null) {
      return;
    }
    _openCommandSearch(activeSessionId);
  }

  void _closeCommandSearch({bool preferCommandInput = false}) {
    final sessionId = _commandSearchSessionId;
    _mutateState(() {
      _isCommandSearchOpen = false;
      _commandSearchSessionId = null;
      _commandSearchOverlayController = null;
    });
    if (sessionId != null &&
        preferCommandInput &&
        _commandInputVisibleForSession(sessionId)) {
      _restoreCommandInputFocus(sessionId);
      return;
    }
    _focusSession(sessionId);
  }

  void _viewCommandSearchBlock({
    required SessionController sessionController,
    required SessionState sessionState,
    required String sessionId,
    required String blockId,
  }) {
    final resolvedBlockId = _resolveCommandSearchBlockId(
      sessionId: sessionId,
      blockId: blockId,
    );
    _closeCommandSearch();
    _navigateToContextChipBlock(
      sessionController: sessionController,
      sessionState: sessionState,
      sessionId: sessionId,
      blockId: resolvedBlockId,
    );
  }

  void _askAgentAboutCommandSearchResult({
    required String sessionId,
    required CommandSearchAgentActionRequest request,
  }) {
    if (!_commandCenterFeatureFlags.agentCommandSearchActions) {
      _closeCommandSearch(preferCommandInput: true);
      return;
    }
    final prompt = _commandSearchAgentPrompt(request);
    final selectedBlockId = _commandSearchAgentBlockIdFor(
      sessionId: sessionId,
      request: request,
    );
    _mutateState(() {
      _isCommandSearchOpen = false;
      _commandSearchSessionId = null;
      _commandSearchOverlayController = null;
      _universalInputMode = UniversalInputMode.agent;
      if (selectedBlockId != null) {
        _selectedCommandBlockIdsBySession[sessionId] = selectedBlockId;
      }
      _agentPromptActionsBySession[sessionId] = ShellAgentPromptAction(
        id: ++_agentPromptActionSerial,
        prompt: prompt,
      );
    });
    _restoreCommandInputFocus(sessionId);
  }

  String? _commandSearchAgentBlockIdFor({
    required String sessionId,
    required CommandSearchAgentActionRequest request,
  }) {
    final invocationId = request.invocationId?.trim();
    if (invocationId == null || invocationId.isEmpty) {
      return null;
    }
    final requestSessionId = request.sessionId?.trim();
    if (requestSessionId != null &&
        requestSessionId.isNotEmpty &&
        requestSessionId != sessionId) {
      return null;
    }
    final resolvedBlockId = _resolveCommandSearchBlockId(
      sessionId: sessionId,
      blockId: invocationId,
    );
    final snapshot =
        _commandBlockSnapshotsBySession[sessionId] ??
        const ShellCommandBlockSnapshot();
    final compatibleBlock = _commandBlockCommandCenterAdapter
        .compatibleBlockById(
          snapshot: snapshot,
          sessionId: sessionId,
          blockId: resolvedBlockId,
        );
    return compatibleBlock?.id;
  }

  String _commandSearchAgentPrompt(CommandSearchAgentActionRequest request) {
    final cwd = request.cwd?.trim();
    final cwdSuffix = cwd == null || cwd.isEmpty ? '' : ' in $cwd';
    final exitSuffix = request.exitCode == null
        ? ''
        : ' (exit ${request.exitCode})';
    return switch (request.kind) {
      CommandSearchAgentActionKind.explain =>
        'Explain command from search history$cwdSuffix: ${request.command}',
      CommandSearchAgentActionKind.debug =>
        'Debug command from search history$exitSuffix$cwdSuffix: ${request.command}',
    };
  }

  String? _resolveCommandSearchBlockId({
    required String sessionId,
    required String blockId,
  }) {
    final snapshot =
        _commandBlockSnapshotsBySession[sessionId] ??
        const ShellCommandBlockSnapshot();
    if (_commandBlockCommandCenterAdapter.compatibleBlockById(
          snapshot: snapshot,
          sessionId: sessionId,
          blockId: blockId,
        ) !=
        null) {
      return blockId;
    }

    final entry = _commandSearchEntryForBlockId(blockId);
    if (entry == null) {
      return blockId;
    }
    for (final candidate in snapshot.blocks.reversed) {
      if (!candidate.isValid || candidate.command != entry.command) {
        continue;
      }
      if (!_nullableTrimmedEquals(candidate.cwd, entry.cwd)) {
        continue;
      }
      if (entry.exitCode != null && candidate.exitCode != entry.exitCode) {
        continue;
      }
      return candidate.id;
    }
    return blockId;
  }

  GlobalCommandHistoryEntry? _commandSearchEntryForBlockId(String blockId) {
    final controller = _commandSearchOverlayController;
    if (controller == null) {
      return null;
    }
    for (final result in controller.state.results) {
      final entry = result.entry;
      if (entry.invocationId == blockId) {
        return entry;
      }
    }
    return null;
  }

  bool _nullableTrimmedEquals(String? left, String? right) {
    final normalizedLeft = left?.trim();
    final normalizedRight = right?.trim();
    final effectiveLeft = normalizedLeft == null || normalizedLeft.isEmpty
        ? null
        : normalizedLeft;
    final effectiveRight = normalizedRight == null || normalizedRight.isEmpty
        ? null
        : normalizedRight;
    return effectiveLeft == effectiveRight;
  }

  CommandSearchOverlayController _commandSearchControllerFor(String sessionId) {
    final controller = _commandSearchOverlayController;
    if (controller != null && _commandSearchSessionId == sessionId) {
      return controller;
    }
    final nextController = _commandSearchShellWiring.controllerFor(
      _commandCenterRuntime,
      sessionId: sessionId,
      globalHistory: _globalCommandHistory,
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

  Future<void> _dispatchCommandSearchOutput(
    String sessionId,
    CommandSearchOverlayOutput output,
  ) async {
    final intent = _commandSearchShellWiring.terminalIntentFor(
      output,
      readOnly: _isSessionReadOnly(sessionId),
    );
    final text = intent.text;
    final useCommandInput = _commandInputVisibleForSession(sessionId);
    final commandInputText = text == null
        ? null
        : output.kind == CommandSearchOverlayOutputKind.explicitExecute
        ? _normalizedCommandInputTextForExecution(text)
        : text;
    switch (intent.kind) {
      case CommandSearchTerminalIntentKind.none:
        _focusSession(sessionId);
      case CommandSearchTerminalIntentKind.disabled:
        _showCommandSearchBlockedIntent(intent.reason);
        _focusSession(sessionId);
      case CommandSearchTerminalIntentKind.insertText:
      case CommandSearchTerminalIntentKind.executeText:
        final didHandle =
            text != null &&
            (useCommandInput
                ? await _routeCommandThroughCommandInput(
                    sessionId,
                    commandInputText!,
                    execute:
                        output.kind ==
                        CommandSearchOverlayOutputKind.explicitExecute,
                  )
                : _sendPlainTextToSession(sessionId, text));
        if (didHandle) {
          _closeCommandSearch(preferCommandInput: useCommandInput);
        }
      case CommandSearchTerminalIntentKind.requiresPastePolicy:
        if (text != null) {
          if (useCommandInput) {
            final didHandle = await _routeCommandThroughCommandInput(
              sessionId,
              commandInputText!,
              execute:
                  output.kind == CommandSearchOverlayOutputKind.explicitExecute,
            );
            if (didHandle) {
              _closeCommandSearch(preferCommandInput: true);
            }
            return;
          }
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
