final class TerminalFocusReportDecision {
  const TerminalFocusReportDecision({required this.focused});

  final bool focused;
}

final class TerminalFocusReporter {
  bool? _lastReportedFocus;

  TerminalFocusReportDecision? synchronize({
    required bool focusTrackingEnabled,
    required bool hasFocus,
  }) {
    if (!focusTrackingEnabled) {
      _lastReportedFocus = null;
      return null;
    }
    if (_lastReportedFocus == hasFocus) {
      return null;
    }
    _lastReportedFocus = hasFocus;
    return TerminalFocusReportDecision(focused: hasFocus);
  }

  TerminalFocusReportDecision? detach({
    required bool focusTrackingEnabled,
    required bool focusNodeHasFocus,
  }) {
    if (!focusTrackingEnabled) {
      _lastReportedFocus = null;
      return null;
    }
    if (_lastReportedFocus != true && !focusNodeHasFocus) {
      return null;
    }
    _lastReportedFocus = false;
    return const TerminalFocusReportDecision(focused: false);
  }

  void reset() {
    _lastReportedFocus = null;
  }
}
