part of 'shell_screen.dart';

const double _minimumMobileTerminalFontScale = 0.7;
const double _maximumMobileTerminalFontScale = 2.0;

extension _ShellScreenMobileInput on _ShellScreenState {
  Widget? _mobileControlsFor(
    SessionController sessionController,
    String? activeSessionId,
    AppThemeTokens palette, {
    required bool keyboardVisible,
    required bool visible,
  }) {
    if (!visible ||
        defaultTargetPlatform != TargetPlatform.iOS ||
        _recordingShelfOpen ||
        _isSftpPanelOpen ||
        _isSearchOpen ||
        _selectedRecording != null ||
        _instantReplayLayoutSession != null ||
        activeSessionId == null) {
      return null;
    }
    final exited =
        _paneForSession(_sessionState, activeSessionId)?.isExited == true;
    return !keyboardVisible || exited
        ? _MobileTerminalToolbar(
            onKeyboard: exited ? null : () => _focusSession(activeSessionId),
            onSearch: _openSearch,
            onReplay: () => unawaited(_openRecordingLibrary()),
            onRecording:
                _sessionState.recordingBusySessionIds.contains(
                      activeSessionId,
                    ) ||
                    (exited &&
                        !_sessionState.recordingPendingSaveSessionIds.contains(
                          activeSessionId,
                        ) &&
                        !_sessionState.recordingSessionIds.contains(
                          activeSessionId,
                        ))
                ? null
                : () => unawaited(
                    _toggleActiveSessionRecording(
                      sessionController,
                      activeSessionId,
                    ),
                  ),
            recording: _sessionState.recordingSessionIds.contains(
              activeSessionId,
            ),
            pendingSave: _sessionState.recordingPendingSaveSessionIds.contains(
              activeSessionId,
            ),
          )
        : ListenableBuilder(
            listenable:
                _composerSessions[activeSessionId]?.controller ??
                _focusNodeFor(activeSessionId),
            builder: (context, _) {
              final composer = _composerSessions[activeSessionId];
              if (composer?.enabled == true &&
                  composer!.controller.ownership ==
                      terminal.ComposerOwnership.ready) {
                return const SizedBox.shrink();
              }
              return IosTerminalInputBar(
                key: const Key('ios-terminal-input-bar'),
                palette: palette,
                keyboardVisible: keyboardVisible,
                onSendBytes: (bytes) =>
                    _sendMobileTerminalBytes(activeSessionId, bytes),
                onDismissKeyboard: () =>
                    _dismissMobileTerminalKeyboard(activeSessionId),
              );
            },
          );
  }

  double _mobileFontScaleFor(String sessionId) {
    return _mobileTerminalFontScales[sessionId] ?? 1.0;
  }

  terminal.TerminalFontConfig _mobileFontFor(
    String sessionId,
    terminal.TerminalFontConfig base,
  ) {
    return base.copyWith(size: base.size * _mobileFontScaleFor(sessionId));
  }

  void _startMobileTerminalPinch(String sessionId, ScaleStartDetails details) {
    _mobileTerminalPinchStartScales[sessionId] = _mobileFontScaleFor(sessionId);
  }

  void _updateMobileTerminalPinch(
    String sessionId,
    ScaleUpdateDetails details,
  ) {
    if (details.pointerCount < 2) {
      return;
    }
    final startScale = _mobileTerminalPinchStartScales.putIfAbsent(
      sessionId,
      () => _mobileFontScaleFor(sessionId),
    );
    _setMobileTerminalFontScale(sessionId, startScale * details.scale);
  }

  void _endMobileTerminalPinch(String sessionId, ScaleEndDetails details) {
    _mobileTerminalPinchStartScales.remove(sessionId);
  }

  void _setMobileTerminalFontScale(String sessionId, double scale) {
    final normalized = scale.clamp(
      _minimumMobileTerminalFontScale,
      _maximumMobileTerminalFontScale,
    );
    if ((_mobileFontScaleFor(sessionId) - normalized).abs() < 0.005) {
      return;
    }
    _mutateState(() {
      _mobileTerminalFontScales[sessionId] = normalized;
      _measuredTerminalCellSizes.remove(sessionId);
      _committedViewportSizes.remove(sessionId);
    });
  }

  void _sendMobileTerminalBytes(String sessionId, List<int> bytes) {
    if (bytes.isEmpty || _isSessionReadOnly(sessionId)) {
      return;
    }
    // Raw terminal shortcuts belong to the live PTY. The Block editor owns
    // ready-shell input and must never invalidate its lease through this bar.
    final composer = _composerSessions[sessionId];
    if (composer?.enabled == true &&
        composer!.controller.ownership == terminal.ComposerOwnership.ready) {
      return;
    }
    ref
        .read(terminalRuntimeControllerProvider)
        .sendInput(sessionId, Uint8List.fromList(bytes));
    _focusSession(sessionId);
  }

  void _dismissMobileTerminalKeyboard(String sessionId) {
    _composerSessions[sessionId]?.editorFocus.unfocus();
    _focusNodeFor(sessionId).unfocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
  }
}
