part of 'shell_screen.dart';

extension _ShellScreenStateContextChips on _ShellScreenState {
  ContextChipState _contextChipsForPane({
    required SessionState sessionState,
    required TerminalPane pane,
    required TerminalProfile? profile,
  }) {
    return _commandCenterContextWiring.chipsForSession(
      _commandCenterRuntime,
      sessionId: pane.sessionId,
      shellIntegrationCwd: pane.shellIntegration.currentDirectory,
      profileId: profile?.id ?? pane.profileId,
      profileName: profile?.name,
      readOnly: _isSessionReadOnly(pane.sessionId),
      blockRangeState: _commandCenterRuntime.blockRangeState(
        rangesByInvocationId: _commandBlockRangesForSession(
          sessionState,
          pane.sessionId,
        ),
      ),
      selectedBlockId: _selectedCommandBlockIdsBySession[pane.sessionId],
    );
  }

  void _handleContextChipIntent({
    required SessionController sessionController,
    required SessionState sessionState,
    required String sessionId,
    required ContextChipClickIntent intent,
  }) {
    switch (intent.kind) {
      case ContextChipIntentKind.none:
        return;
      case ContextChipIntentKind.revealCwd:
        _showContextChipMessage('CWD: ${intent.cwd ?? 'Unavailable'}');
      case ContextChipIntentKind.openProfile:
        unawaited(_openProfilesSheet(sessionController, sessionState));
      case ContextChipIntentKind.showShellHookDiagnostics:
        _showContextChipMessage(_shellHookDiagnosticsMessage(intent));
      case ContextChipIntentKind.navigateToBlock:
        _navigateToContextChipBlock(
          sessionController: sessionController,
          sessionState: sessionState,
          sessionId: sessionId,
          blockId: intent.blockId,
        );
      case ContextChipIntentKind.openBlockActions:
        unawaited(
          _openContextChipBlockActions(
            sessionController: sessionController,
            sessionState: sessionState,
            sessionId: sessionId,
            blockId: intent.blockId,
          ),
        );
      case ContextChipIntentKind.toggleReadOnly:
        _toggleReadOnlySession(sessionId);
    }
  }

  void _navigateToContextChipBlock({
    required SessionController sessionController,
    required SessionState sessionState,
    required String sessionId,
    required String? blockId,
  }) {
    if (blockId == null) {
      _showContextChipMessage('Command block is unavailable.');
      return;
    }
    final rangeState = _commandCenterRuntime.blockRangeState(
      rangesByInvocationId: _commandBlockRangesForSession(
        sessionState,
        sessionId,
      ),
    );
    final block = rangeState.blockByInvocationId(blockId);
    final inputRange = block?.inputRange;
    if (block == null || inputRange == null) {
      _showContextChipMessage('Command block range is unavailable.');
      return;
    }
    _mutateState(() {
      _selectedCommandBlockIdsBySession[sessionId] = block.id;
    });
    ref
        .read(terminalRuntimeControllerProvider)
        .scrollViewportTo(sessionId, inputRange.startRow);
    _focusSession(sessionId);
  }

  Future<void> _openContextChipBlockActions({
    required SessionController sessionController,
    required SessionState sessionState,
    required String sessionId,
    required String? blockId,
  }) async {
    final block = _contextChipBlockFor(
      sessionState: sessionState,
      sessionId: sessionId,
      blockId: blockId,
    );
    if (block == null) {
      _showContextChipMessage('Command block is unavailable.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  key: const Key('context-block-action-copy-command'),
                  leading: const Icon(Icons.content_copy),
                  title: const Text('Copy block command'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(
                      _runContextChipBlockAction(
                        sessionController: sessionController,
                        sessionId: sessionId,
                        block: block,
                        action: CommandBlockAction.copyCommand,
                      ),
                    );
                  },
                ),
                ListTile(
                  key: const Key('context-block-action-copy-output'),
                  leading: const Icon(Icons.copy_all),
                  title: const Text('Copy block output'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(
                      _runContextChipBlockAction(
                        sessionController: sessionController,
                        sessionId: sessionId,
                        block: block,
                        action: CommandBlockAction.copyOutput,
                      ),
                    );
                  },
                ),
                ListTile(
                  key: const Key('context-block-action-copy-both'),
                  leading: const Icon(Icons.library_books),
                  title: const Text('Copy command and output'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(
                      _runContextChipBlockAction(
                        sessionController: sessionController,
                        sessionId: sessionId,
                        block: block,
                        action: CommandBlockAction.copyBoth,
                      ),
                    );
                  },
                ),
                ListTile(
                  key: const Key('context-block-action-reinput'),
                  leading: const Icon(Icons.keyboard_return),
                  title: const Text('Reinput block command'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(
                      _runContextChipBlockAction(
                        sessionController: sessionController,
                        sessionId: sessionId,
                        block: block,
                        action: CommandBlockAction.reInput,
                      ),
                    );
                  },
                ),
                ListTile(
                  key: const Key('context-block-action-rerun'),
                  leading: const Icon(Icons.replay),
                  title: const Text('Rerun block command'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(
                      _runContextChipBlockAction(
                        sessionController: sessionController,
                        sessionId: sessionId,
                        block: block,
                        action: CommandBlockAction.rerun,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  CommandBlock? _contextChipBlockFor({
    required SessionState sessionState,
    required String sessionId,
    required String? blockId,
  }) {
    if (blockId == null) {
      return null;
    }
    final rangeState = _commandCenterRuntime.blockRangeState(
      rangesByInvocationId: _commandBlockRangesForSession(
        sessionState,
        sessionId,
      ),
    );
    final block = rangeState.blockByInvocationId(blockId);
    return block?.scope == CommandBlockScope(sessionId) ? block : null;
  }

  Future<void> _runContextChipBlockAction({
    required SessionController sessionController,
    required String sessionId,
    required CommandBlock block,
    required CommandBlockAction action,
  }) async {
    final result = const CommandBlockActionReducer().reduce(
      action,
      block,
      readOnly: _isSessionReadOnly(sessionId),
    );
    if (!result.enabled) {
      _showContextChipMessage(
        _contextChipBlockDisabledMessage(result.disabledReason),
      );
      _focusSession(sessionId);
      return;
    }
    await _dispatchCommandActionSearchBlockIntent(
      sessionId,
      sessionController,
      result.intent,
    );
  }

  String _contextChipBlockDisabledMessage(
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

  String _shellHookDiagnosticsMessage(ContextChipClickIntent intent) {
    return switch (intent.unavailableReason) {
      null => 'Shell integration is active.',
      CommandCenterUnavailableReason.shellIntegrationDisabled =>
        'Shell integration is disabled.',
      CommandCenterUnavailableReason.unknownHook =>
        'Shell hook payload is unknown.',
      CommandCenterUnavailableReason.missingCommand =>
        'Shell hook command is missing.',
      CommandCenterUnavailableReason.missingCwd => 'CWD is unavailable.',
      CommandCenterUnavailableReason.missingLifecycle =>
        'Command lifecycle is unavailable.',
      CommandCenterUnavailableReason.missingOutputRange =>
        'Command output range is unavailable.',
      CommandCenterUnavailableReason.outOfOrderLifecycle =>
        'Command lifecycle event order is incomplete.',
    };
  }

  void _showContextChipMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
