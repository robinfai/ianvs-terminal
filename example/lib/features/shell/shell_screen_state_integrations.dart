part of 'shell_screen.dart';

extension _ShellScreenStateIntegrations on _ShellScreenState {
  Future<void> _openShellIntegrationUtilities(
    SessionState sessionState,
    String sessionId,
  ) async {
    final pane = _paneForSession(sessionState, sessionId);
    if (pane == null) {
      return;
    }
    final frame = ref
        .read(sessionControllerProvider.notifier)
        .viewportFor(sessionId)
        .frame;
    final integration = _integrationWithEffectivePromptMarks(
      sessionId,
      pane.shellIntegration,
    );
    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: animationsEnabled
          ? null
          : AnimationStyle.noAnimation,
      builder: (sheetContext) {
        return _ShellIntegrationUtilitiesSheet(
          integration: integration,
          globalBottomRow: frame.globalBottomRow,
          scrollbackMaxOffset: frame.scrollbackMaxOffset,
          onInsertCommand: (command) {
            _sendPlainTextToSession(sessionId, command);
          },
          onChangeDirectory: (directory) {
            _sendPlainTextToSession(
              sessionId,
              'cd ${_shellQuotedPath(directory)}',
            );
          },
          onJumpToMark: (mark) {
            final currentFrame = ref
                .read(sessionControllerProvider.notifier)
                .viewportFor(sessionId)
                .frame;
            final offset = terminalPromptMarkScrollbackOffset(
              mark,
              globalBottomRow: currentFrame.globalBottomRow,
              scrollbackMaxOffset: currentFrame.scrollbackMaxOffset,
            );
            if (offset == null) {
              return;
            }
            ref
                .read(terminalRuntimeControllerProvider)
                .scrollViewportTo(sessionId, offset);
            _focusSession(sessionId);
          },
        );
      },
    );
  }

  bool _tmuxControlModeActive(String sessionId) {
    final frame = ref
        .read(sessionControllerProvider.notifier)
        .viewportFor(sessionId)
        .frame;
    return _frameLooksLikeTmuxControlMode(frame);
  }

  bool _frameLooksLikeTmuxControlMode(terminal.TerminalFrameDiff frame) {
    var sawModeBanner = false;
    var sawCommandMenu = false;
    for (final row in frame.rows) {
      final text = row.text.trim();
      if (text.contains('tmux mode started') ||
          text.startsWith('%window-add') ||
          text.startsWith('%session-changed')) {
        sawModeBanner = true;
      }
      if (text.contains('Detach cleanly') ||
          text.contains('Force-quit tmux mode') ||
          text == 'Command Menu') {
        sawCommandMenu = true;
      }
    }
    return sawModeBanner && sawCommandMenu;
  }

  Future<void> _openTmuxIntegration(String sessionId) async {
    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: animationsEnabled
          ? null
          : AnimationStyle.noAnimation,
      builder: (sheetContext) {
        return _TmuxIntegrationSheet(
          controlModeDetected: _tmuxControlModeActive(sessionId),
          onSendCommand: (command) {
            _sendPlainTextToSession(sessionId, command);
          },
        );
      },
    );
  }

  Future<void> _openCoprocess(String sessionId) async {
    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: animationsEnabled
          ? null
          : AnimationStyle.noAnimation,
      builder: (sheetContext) {
        return _CoprocessSheet(
          activeCoprocess: _coprocesses[sessionId],
          onStart: (request) => _startCoprocess(sessionId, request),
          onStop: () => _stopCoprocess(sessionId),
        );
      },
    );
  }

  Future<void> _openAdvancedPaste(String sessionId) async {
    final clipboardText = await ClipboardBridge.paste();
    if (!mounted) {
      return;
    }

    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    final result = await showModalBottomSheet<_AdvancedPasteSheetResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: animationsEnabled
          ? null
          : AnimationStyle.noAnimation,
      builder: (sheetContext) {
        return _AdvancedPasteSheet(initialText: clipboardText);
      },
    );

    if (!mounted || !_sessionExists(sessionId)) {
      return;
    }

    switch (result) {
      case _AdvancedPasteSendResult(:final text):
        if (text.isEmpty) {
          return;
        }
        await _pasteTextToSession(sessionId, text);
        await _recordPasteHistory(text, PasteHistoryKind.paste);
        return;
      case null:
        return;
    }
  }

  Future<void> _openPasteHistory(SessionState sessionState) async {
    final activeSessionIdBeforeOpen = sessionState.activeSessionId;
    if (activeSessionIdBeforeOpen == null) {
      return;
    }
    if (!_pasteHistoryLoaded) {
      await _loadPasteHistory();
    }
    if (!mounted) {
      return;
    }

    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    final result = await showModalBottomSheet<_PasteHistorySheetResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: animationsEnabled
          ? null
          : AnimationStyle.noAnimation,
      builder: (sheetContext) {
        return _PasteHistorySheet(
          entries: _pasteHistoryEntries,
          persistToDisk: _pasteHistoryPersistToDisk,
          onPersistChanged: (enabled) =>
              unawaited(_setPasteHistoryPersistence(enabled)),
          onClear: () => unawaited(_clearPasteHistory()),
        );
      },
    );

    if (!mounted) {
      return;
    }

    switch (result) {
      case _PasteHistoryPickResult(:final entry):
        final currentActiveSessionId = ref
            .read(sessionControllerProvider)
            .activeSessionId;
        if (currentActiveSessionId == null) {
          return;
        }
        final decision = LocalTerminalPasteDecisionResolver.resolve(
          text: entry.text,
          readOnly: _isSessionReadOnly(currentActiveSessionId),
          pastePolicy: _pastePolicy,
          historyPolicy: _pasteHistoryPolicy,
        );
        switch (decision.kind) {
          case LocalTerminalPasteDecisionKind.blockedReadOnly:
            _restoreSessionFocus(
              activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
              activeSessionIdAfterClose: currentActiveSessionId,
            );
            return;
          case LocalTerminalPasteDecisionKind.requireConfirmation:
            final confirmed = await _confirmPaste(decision);
            if (!confirmed) {
              _restoreSessionFocus(
                activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
                activeSessionIdAfterClose: currentActiveSessionId,
              );
              return;
            }
          case LocalTerminalPasteDecisionKind.sendImmediately:
            break;
        }
        await _pasteTextToSession(currentActiveSessionId, decision.text);
        if (decision.captureHistory) {
          await _recordPasteHistory(decision.text, PasteHistoryKind.paste);
        }
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentActiveSessionId,
        );
        return;
      case null:
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: ref
              .read(sessionControllerProvider)
              .activeSessionId,
        );
        return;
    }
  }

  Future<void> _openPasswordManager(
    SessionController sessionController,
    String sessionId,
  ) async {
    final store = ref.read(passwordManagerStoreProvider);
    final frame = sessionController.viewportFor(sessionId).frame;
    final promptDetected = _frameHasPasswordPrompt(frame);
    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    final result = await showModalBottomSheet<_PasswordManagerSheetResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: animationsEnabled
          ? null
          : AnimationStyle.noAnimation,
      builder: (sheetContext) {
        return _PasswordManagerSheet(
          entries: store.entries,
          promptDetected: promptDetected,
          onAdd: store.add,
          onRemove: store.remove,
        );
      },
    );

    if (!mounted) {
      return;
    }
    switch (result) {
      case _PasswordManagerSendResult(:final entry):
        final latestFrame = sessionController.viewportFor(sessionId).frame;
        if (!_frameHasPasswordPrompt(latestFrame)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Password send blocked: no password prompt is active.',
              ),
            ),
          );
          return;
        }
        _sendPasswordToSession(sessionId, entry);
        return;
      case null:
        return;
    }
  }

  void _sendPasswordToSession(String sessionId, PasswordManagerEntry entry) {
    if (_isSessionReadOnly(sessionId)) {
      return;
    }
    ref
        .read(terminalRuntimeControllerProvider)
        .sendInput(
          sessionId,
          Uint8List.fromList(utf8.encode('${entry.password}\n')),
        );
  }

  bool _frameHasPasswordPrompt(terminal.TerminalFrameDiff frame) {
    for (final logicalRow in _logicalRows(frame.rows).reversed) {
      final text = logicalRow.text.trimRight();
      if (text.isEmpty) {
        continue;
      }
      if (_passwordPromptPattern.hasMatch(text)) {
        return true;
      }
      return false;
    }
    return false;
  }
}
