import '../terminal/terminal_models.dart';
import 'terminal_frame_pump.dart';

enum TerminalRefreshClass { interactive, streaming, background, idle }

final class TerminalRefreshDecision {
  const TerminalRefreshDecision({
    required this.shouldRequestFullPoll,
    required this.requestReason,
    required this.snapshot,
  });

  final bool shouldRequestFullPoll;
  final String? requestReason;
  final TerminalRefreshSnapshot snapshot;
}

final class TerminalRefreshResult {
  const TerminalRefreshResult({
    required this.receivedFrame,
    required this.eventCount,
    required this.snapshot,
  });

  final bool receivedFrame;
  final int eventCount;
  final TerminalRefreshSnapshot snapshot;
}

final class TerminalRefreshSnapshot {
  const TerminalRefreshSnapshot({
    required this.refreshClass,
    required this.pumpMetrics,
    required this.hintPollCount,
    required this.fullPollCount,
  });

  final TerminalRefreshClass refreshClass;
  final TerminalFramePumpMetrics pumpMetrics;
  final int hintPollCount;
  final int fullPollCount;
}

final class TerminalRefreshPolicy {
  TerminalRefreshPolicy({
    required this.pollInterval,
    required this.interactiveGrace,
    required this.streamingGap,
    required this.streamingGrace,
    required this.fallbackPolicy,
  }) : assert(pollInterval > Duration.zero),
       assert(interactiveGrace > Duration.zero),
       assert(streamingGap > Duration.zero),
       assert(streamingGrace > Duration.zero);

  factory TerminalRefreshPolicy.standard() {
    const pollInterval = Duration(milliseconds: 33);
    return TerminalRefreshPolicy(
      pollInterval: pollInterval,
      interactiveGrace: const Duration(milliseconds: 500),
      streamingGap: const Duration(milliseconds: 100),
      streamingGrace: const Duration(milliseconds: 250),
      fallbackPolicy: TerminalFramePumpPolicy(
        activeInterval: pollInterval,
        emptyRefreshesBeforeBackoff: 2,
        idleIntervals: <Duration>[
          Duration(milliseconds: 132),
          Duration(milliseconds: 264),
          Duration(milliseconds: 396),
        ],
      ),
    );
  }

  final Duration pollInterval;
  final Duration interactiveGrace;
  final Duration streamingGap;
  final Duration streamingGrace;
  final TerminalFramePumpPolicy fallbackPolicy;

  final Map<String, _TerminalRefreshState> _states =
      <String, _TerminalRefreshState>{};

  TerminalRefreshDecision decisionForTick(
    String sessionId, {
    required Duration now,
    required bool? hintReady,
  }) {
    final state = _stateFor(sessionId);
    if (hintReady != null) {
      state.hintPollCount += 1;
    }

    final refreshClass = _refreshClassFor(state, now);
    final deadlineDue = switch (refreshClass) {
      TerminalRefreshClass.interactive ||
      TerminalRefreshClass.streaming => now >= state.nextDirectPollDue,
      TerminalRefreshClass.background || TerminalRefreshClass.idle =>
        !fallbackPolicy.shouldSkipPollingRefresh(sessionId, now: now),
    };
    final shouldRequestFullPoll = hintReady == true || deadlineDue;
    final requestReason = switch ((hintReady, deadlineDue, refreshClass)) {
      (true, _, _) => 'native_hint',
      (_, true, TerminalRefreshClass.idle) => 'idle_deadline',
      (_, true, _) => 'deadline',
      _ => null,
    };

    if (shouldRequestFullPoll) {
      if (refreshClass == TerminalRefreshClass.interactive ||
          refreshClass == TerminalRefreshClass.streaming) {
        state.nextDirectPollDue = now + pollInterval;
      }
    }

    return TerminalRefreshDecision(
      shouldRequestFullPoll: shouldRequestFullPoll,
      requestReason: requestReason,
      snapshot: _snapshotFor(sessionId, state, now),
    );
  }

  void recordFullPollRequest(String sessionId) {
    _stateFor(sessionId).fullPollCount += 1;
  }

  void recordInput(String sessionId, {required Duration now}) {
    _recordInteractiveSignal(sessionId, now: now);
  }

  void recordFocus(
    String sessionId, {
    required Duration now,
    required bool focused,
  }) {
    final state = _stateFor(sessionId)..focused = focused;
    if (focused) {
      _resetForInteractiveSignal(sessionId, state, now);
    }
  }

  void recordResize(String sessionId, {required Duration now}) {
    _recordInteractiveSignal(sessionId, now: now);
  }

  void recordActivation(
    String sessionId, {
    required Duration now,
    required bool active,
  }) {
    final state = _stateFor(sessionId)
      ..active = active
      ..lastFrameAt = null
      ..consecutiveFrames = 0
      ..streamingUntil = Duration.zero;
    _resetForInteractiveSignal(sessionId, state, now);
  }

  TerminalRefreshResult recordRefreshResult(
    String sessionId, {
    required Duration now,
    required bool receivedFrame,
    required int eventCount,
    required TerminalFrameModes modes,
  }) {
    final state = _stateFor(sessionId)
      ..alternateScreen = modes.alternateScreen
      ..mouseTracking = modes.mouseMode != 'off';

    if (receivedFrame) {
      final previousFrameAt = state.lastFrameAt;
      if (previousFrameAt != null && now - previousFrameAt <= streamingGap) {
        state.consecutiveFrames += 1;
      } else {
        state.consecutiveFrames = 1;
        state.streamingUntil = Duration.zero;
      }
      state.lastFrameAt = now;
      if (state.consecutiveFrames >= 2) {
        state.streamingUntil = now + streamingGrace;
      }
    }

    final refreshClass = _refreshClassFor(state, now);
    if (refreshClass == TerminalRefreshClass.interactive ||
        refreshClass == TerminalRefreshClass.streaming) {
      fallbackPolicy.reset(sessionId, now: now);
      state.nextDirectPollDue = now + pollInterval;
    } else {
      fallbackPolicy.recordRefreshResult(
        sessionId,
        now: now,
        hadActivity: receivedFrame || eventCount > 0,
      );
    }

    return TerminalRefreshResult(
      receivedFrame: receivedFrame,
      eventCount: eventCount,
      snapshot: _snapshotFor(sessionId, state, now),
    );
  }

  TerminalRefreshSnapshot snapshot(String sessionId, {required Duration now}) {
    final state = _states[sessionId];
    if (state == null) {
      return const TerminalRefreshSnapshot(
        refreshClass: TerminalRefreshClass.idle,
        pumpMetrics: TerminalFramePumpMetrics(
          emptyRefreshCount: 0,
          backoffSkipTicks: 0,
          currentDelay: Duration.zero,
        ),
        hintPollCount: 0,
        fullPollCount: 0,
      );
    }
    return _snapshotFor(sessionId, state, now);
  }

  void remove(String sessionId) {
    _states.remove(sessionId);
    fallbackPolicy.remove(sessionId);
  }

  void _recordInteractiveSignal(String sessionId, {required Duration now}) {
    final state = _stateFor(sessionId);
    _resetForInteractiveSignal(sessionId, state, now);
  }

  void _resetForInteractiveSignal(
    String sessionId,
    _TerminalRefreshState state,
    Duration now,
  ) {
    state
      ..interactiveUntil = now + interactiveGrace
      ..nextDirectPollDue = now + pollInterval;
    fallbackPolicy.reset(sessionId, now: now);
  }

  _TerminalRefreshState _stateFor(String sessionId) {
    return _states.putIfAbsent(sessionId, _TerminalRefreshState.new);
  }

  TerminalRefreshClass _refreshClassFor(
    _TerminalRefreshState state,
    Duration now,
  ) {
    if (state.active &&
        (state.focused ||
            state.alternateScreen ||
            state.mouseTracking ||
            now < state.interactiveUntil)) {
      return TerminalRefreshClass.interactive;
    }
    if (now < state.streamingUntil) {
      return TerminalRefreshClass.streaming;
    }
    if (!state.active) {
      return TerminalRefreshClass.background;
    }
    return TerminalRefreshClass.idle;
  }

  TerminalRefreshSnapshot _snapshotFor(
    String sessionId,
    _TerminalRefreshState state,
    Duration now,
  ) {
    final refreshClass = _refreshClassFor(state, now);
    final pumpMetrics =
        refreshClass == TerminalRefreshClass.interactive ||
            refreshClass == TerminalRefreshClass.streaming
        ? TerminalFramePumpMetrics(
            emptyRefreshCount: 0,
            backoffSkipTicks: 0,
            currentDelay: pollInterval,
          )
        : fallbackPolicy.metricsFor(sessionId);
    return TerminalRefreshSnapshot(
      refreshClass: refreshClass,
      pumpMetrics: pumpMetrics,
      hintPollCount: state.hintPollCount,
      fullPollCount: state.fullPollCount,
    );
  }
}

final class _TerminalRefreshState {
  bool active = true;
  bool focused = false;
  bool alternateScreen = false;
  bool mouseTracking = false;
  int consecutiveFrames = 0;
  Duration? lastFrameAt;
  Duration interactiveUntil = Duration.zero;
  Duration streamingUntil = Duration.zero;
  Duration nextDirectPollDue = Duration.zero;
  int hintPollCount = 0;
  int fullPollCount = 0;
}
