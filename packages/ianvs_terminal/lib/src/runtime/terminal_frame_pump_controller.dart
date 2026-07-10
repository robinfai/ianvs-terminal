import '../terminal/terminal_models.dart';
import 'terminal_refresh_policy.dart';

enum TerminalFramePumpResetReason { input, activation, focusGain, resize }

final class TerminalFramePumpController {
  TerminalFramePumpController._(this._refreshPolicy);

  factory TerminalFramePumpController.standard() {
    return TerminalFramePumpController._(TerminalRefreshPolicy.standard());
  }

  final TerminalRefreshPolicy _refreshPolicy;

  TerminalRefreshDecision decisionForTick(
    String sessionId, {
    required Duration now,
    required bool? hintReady,
  }) {
    return _refreshPolicy.decisionForTick(
      sessionId,
      now: now,
      hintReady: hintReady,
    );
  }

  void reset(
    String sessionId, {
    required Duration now,
    required TerminalFramePumpResetReason reason,
    bool? active,
  }) {
    if (reason == TerminalFramePumpResetReason.activation && active == null) {
      throw ArgumentError.notNull('active');
    }
    if (reason != TerminalFramePumpResetReason.activation && active != null) {
      throw ArgumentError.value(
        active,
        'active',
        'is only valid for activation resets',
      );
    }

    switch (reason) {
      case TerminalFramePumpResetReason.input:
        _refreshPolicy.recordInput(sessionId, now: now);
      case TerminalFramePumpResetReason.activation:
        _refreshPolicy.recordActivation(sessionId, now: now, active: active!);
      case TerminalFramePumpResetReason.focusGain:
        _refreshPolicy.recordFocus(sessionId, now: now, focused: true);
      case TerminalFramePumpResetReason.resize:
        _refreshPolicy.recordResize(sessionId, now: now);
    }
  }

  void recordFocusLoss(String sessionId, {required Duration now}) {
    _refreshPolicy.recordFocus(sessionId, now: now, focused: false);
  }

  TerminalRefreshResult recordRefreshResult(
    String sessionId, {
    required Duration now,
    required bool receivedFrame,
    required int eventCount,
    required TerminalFrameModes modes,
  }) {
    return _refreshPolicy.recordRefreshResult(
      sessionId,
      now: now,
      receivedFrame: receivedFrame,
      eventCount: eventCount,
      modes: modes,
    );
  }

  void recordFullPollRequest(String sessionId) {
    _refreshPolicy.recordFullPollRequest(sessionId);
  }

  TerminalRefreshSnapshot snapshot(String sessionId, {required Duration now}) {
    return _refreshPolicy.snapshot(sessionId, now: now);
  }

  void remove(String sessionId) {
    _refreshPolicy.remove(sessionId);
  }
}
