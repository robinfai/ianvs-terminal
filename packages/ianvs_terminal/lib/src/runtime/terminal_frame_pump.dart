final class TerminalFramePumpPolicy {
  TerminalFramePumpPolicy({
    required this.activeInterval,
    required this.emptyRefreshesBeforeBackoff,
    required List<Duration> idleIntervals,
  }) : assert(activeInterval > Duration.zero),
       assert(emptyRefreshesBeforeBackoff > 0),
       assert(idleIntervals.isNotEmpty),
       assert(idleIntervals.every((interval) => interval > Duration.zero)),
       idleIntervals = List<Duration>.unmodifiable(idleIntervals);

  final Duration activeInterval;
  final int emptyRefreshesBeforeBackoff;
  final List<Duration> idleIntervals;

  final Map<String, _TerminalFramePumpState> _states =
      <String, _TerminalFramePumpState>{};

  bool shouldSkipPollingRefresh(String sessionId, {required Duration now}) {
    final state = _states[sessionId];
    return state != null && now < state.nextRefreshDue;
  }

  void recordRefreshResult(
    String sessionId, {
    required Duration now,
    required bool hadActivity,
  }) {
    if (hadActivity) {
      reset(sessionId, now: now);
      return;
    }

    final previous = _states[sessionId];
    final emptyRefreshCount = (previous?.emptyRefreshCount ?? 0) + 1;
    final idleIntervalIndex = emptyRefreshCount < emptyRefreshesBeforeBackoff
        ? -1
        : (emptyRefreshCount - emptyRefreshesBeforeBackoff).clamp(
            0,
            idleIntervals.length - 1,
          );
    final currentDelay = idleIntervalIndex < 0
        ? activeInterval
        : idleIntervals[idleIntervalIndex];
    _states[sessionId] = _TerminalFramePumpState(
      emptyRefreshCount: emptyRefreshCount,
      currentDelay: currentDelay,
      nextRefreshDue: now + currentDelay,
    );
  }

  void reset(String sessionId, {required Duration now}) {
    _states[sessionId] = _TerminalFramePumpState(
      emptyRefreshCount: 0,
      currentDelay: activeInterval,
      nextRefreshDue: now + activeInterval,
    );
  }

  void remove(String sessionId) {
    _states.remove(sessionId);
  }

  TerminalFramePumpMetrics metricsFor(String sessionId) {
    final state = _states[sessionId];
    if (state == null) {
      return const TerminalFramePumpMetrics(
        emptyRefreshCount: 0,
        backoffSkipTicks: 0,
        currentDelay: Duration.zero,
      );
    }
    return TerminalFramePumpMetrics(
      emptyRefreshCount: state.emptyRefreshCount,
      backoffSkipTicks: state.currentDelay <= activeInterval
          ? 0
          : state.currentDelay.inMicroseconds ~/ activeInterval.inMicroseconds -
                1,
      currentDelay: state.currentDelay,
    );
  }
}

final class TerminalFramePumpMetrics {
  const TerminalFramePumpMetrics({
    required this.emptyRefreshCount,
    required this.backoffSkipTicks,
    required this.currentDelay,
  });

  final int emptyRefreshCount;
  final int backoffSkipTicks;
  final Duration currentDelay;
}

final class _TerminalFramePumpState {
  const _TerminalFramePumpState({
    required this.emptyRefreshCount,
    required this.currentDelay,
    required this.nextRefreshDue,
  });

  final int emptyRefreshCount;
  final Duration currentDelay;
  final Duration nextRefreshDue;
}
