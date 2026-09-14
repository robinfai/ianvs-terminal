part of 'shell_screen.dart';

const double _minimumMobileTerminalFontScale = 0.7;
const double _maximumMobileTerminalFontScale = 2.0;

extension _ShellScreenMobileInput on _ShellScreenState {
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
    ref
        .read(terminalRuntimeControllerProvider)
        .sendInput(sessionId, Uint8List.fromList(bytes));
    _focusSession(sessionId);
  }

  void _dismissMobileTerminalKeyboard(String sessionId) {
    _focusNodeFor(sessionId).unfocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
  }
}
