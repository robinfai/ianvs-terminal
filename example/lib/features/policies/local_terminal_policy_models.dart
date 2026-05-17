enum LocalTerminalCopyOnSelectMode { off, clipboard }

enum LocalTerminalPointerPasteMode { disabled, paste }

enum LocalTerminalRightClickMode { contextMenu, paste, copySelection }

class LocalTerminalClipboardPolicy {
  const LocalTerminalClipboardPolicy({
    this.copyOnSelect = LocalTerminalCopyOnSelectMode.off,
    this.rightClick = LocalTerminalRightClickMode.contextMenu,
    this.middleClick = LocalTerminalPointerPasteMode.disabled,
  });

  final LocalTerminalCopyOnSelectMode copyOnSelect;
  final LocalTerminalRightClickMode rightClick;
  final LocalTerminalPointerPasteMode middleClick;
}

class LocalTerminalPastePolicy {
  const LocalTerminalPastePolicy({
    this.confirmLargePaste = true,
    this.confirmMultilinePaste = true,
    this.largePasteThreshold = 4096,
    this.historySize = 50,
  });

  final bool confirmLargePaste;
  final bool confirmMultilinePaste;
  final int largePasteThreshold;
  final int historySize;

  bool requiresConfirmation(String text) {
    if (confirmMultilinePaste && text.contains('\n')) {
      return true;
    }
    return confirmLargePaste && text.length >= largePasteThreshold;
  }

  bool canPaste({required bool readOnly}) {
    return !readOnly;
  }
}

class LocalTerminalPasteHistoryPolicy {
  const LocalTerminalPasteHistoryPolicy({
    this.enabled = true,
    this.maxEntries = 50,
    this.persist = true,
    this.captureMultiline = true,
    this.captureLargePaste = false,
  });

  final bool enabled;
  final int maxEntries;
  final bool persist;
  final bool captureMultiline;
  final bool captureLargePaste;

  bool shouldCapture({required String text, required bool largePaste}) {
    if (!enabled || maxEntries <= 0) {
      return false;
    }
    if (!captureMultiline && text.contains('\n')) {
      return false;
    }
    if (!captureLargePaste && largePaste) {
      return false;
    }
    return text.isNotEmpty;
  }
}

class LocalTerminalPasteHistoryState {
  const LocalTerminalPasteHistoryState({
    this.entries = const <String>[],
    this.focusShouldReturnToTerminal = true,
  });

  final List<String> entries;
  final bool focusShouldReturnToTerminal;

  LocalTerminalPasteHistoryState record({
    required String text,
    required LocalTerminalPasteHistoryPolicy policy,
    required bool largePaste,
  }) {
    if (!policy.shouldCapture(text: text, largePaste: largePaste)) {
      return this;
    }

    return LocalTerminalPasteHistoryState(
      entries: [
        text,
        for (final entry in entries)
          if (entry != text) entry,
      ].take(policy.maxEntries).toList(growable: false),
      focusShouldReturnToTerminal: focusShouldReturnToTerminal,
    );
  }
}

enum LocalTerminalMonitorTarget { badge, inAppToast, systemNotification }

enum LocalTerminalMonitorFocusPolicy { always, unfocused, never }

class LocalTerminalMonitorRule {
  const LocalTerminalMonitorRule({
    required this.enabled,
    required this.target,
    required this.focusPolicy,
    this.threshold,
  });

  final bool enabled;
  final LocalTerminalMonitorTarget target;
  final LocalTerminalMonitorFocusPolicy focusPolicy;
  final Duration? threshold;

  bool shouldNotify({required bool focused, Duration? observedDuration}) {
    if (!enabled || focusPolicy == LocalTerminalMonitorFocusPolicy.never) {
      return false;
    }
    if (focusPolicy == LocalTerminalMonitorFocusPolicy.unfocused && focused) {
      return false;
    }
    final requiredThreshold = threshold;
    if (requiredThreshold != null &&
        (observedDuration == null || observedDuration < requiredThreshold)) {
      return false;
    }
    return true;
  }
}

class LocalTerminalNotificationPolicy {
  const LocalTerminalNotificationPolicy({
    this.bell = const LocalTerminalMonitorRule(
      enabled: true,
      target: LocalTerminalMonitorTarget.badge,
      focusPolicy: LocalTerminalMonitorFocusPolicy.unfocused,
    ),
    this.commandFinished = const LocalTerminalMonitorRule(
      enabled: true,
      target: LocalTerminalMonitorTarget.badge,
      focusPolicy: LocalTerminalMonitorFocusPolicy.unfocused,
    ),
    this.longRunningCommandFinished = const LocalTerminalMonitorRule(
      enabled: true,
      target: LocalTerminalMonitorTarget.systemNotification,
      focusPolicy: LocalTerminalMonitorFocusPolicy.unfocused,
      threshold: Duration(seconds: 30),
    ),
    this.activity = const LocalTerminalMonitorRule(
      enabled: true,
      target: LocalTerminalMonitorTarget.badge,
      focusPolicy: LocalTerminalMonitorFocusPolicy.unfocused,
    ),
    this.silence = const LocalTerminalMonitorRule(
      enabled: false,
      target: LocalTerminalMonitorTarget.badge,
      focusPolicy: LocalTerminalMonitorFocusPolicy.unfocused,
      threshold: Duration(minutes: 5),
    ),
  });

  final LocalTerminalMonitorRule bell;
  final LocalTerminalMonitorRule commandFinished;
  final LocalTerminalMonitorRule longRunningCommandFinished;
  final LocalTerminalMonitorRule activity;
  final LocalTerminalMonitorRule silence;
}

class LocalTerminalHotkeyWindowPolicy {
  const LocalTerminalHotkeyWindowPolicy({
    this.enabled = false,
    this.widthFraction = 0.8,
    this.heightFraction = 0.5,
    this.autohide = true,
  });

  final bool enabled;
  final double widthFraction;
  final double heightFraction;
  final bool autohide;

  bool get hasUsableSize {
    return widthFraction > 0 && heightFraction > 0;
  }
}

enum LocalTerminalHotkeyWindowFailureKind {
  permissionDenied,
  platformUnavailable,
  bridgeError,
}

class LocalTerminalHotkeyWindowState {
  const LocalTerminalHotkeyWindowState({
    this.visible = false,
    this.lastFailure,
  });

  final bool visible;
  final LocalTerminalHotkeyWindowFailure? lastFailure;

  bool get hasVisibleFailure => lastFailure != null;

  LocalTerminalHotkeyWindowState toggled() {
    return LocalTerminalHotkeyWindowState(visible: !visible, lastFailure: null);
  }

  LocalTerminalHotkeyWindowState failed(
    LocalTerminalHotkeyWindowFailure failure,
  ) {
    return LocalTerminalHotkeyWindowState(
      visible: visible,
      lastFailure: failure,
    );
  }
}

class LocalTerminalHotkeyWindowFailure {
  const LocalTerminalHotkeyWindowFailure({
    required this.kind,
    required this.message,
  });

  final LocalTerminalHotkeyWindowFailureKind kind;
  final String message;
}
