import 'dart:math' as math;

final class TerminalFramePumpBackoff {
  TerminalFramePumpBackoff({
    required this.emptyRefreshesBeforeBackoff,
    required this.initialSkipTicks,
    required this.maxSkipTicks,
  }) : assert(emptyRefreshesBeforeBackoff > 0),
       assert(initialSkipTicks > 0),
       assert(maxSkipTicks >= initialSkipTicks);

  final int emptyRefreshesBeforeBackoff;
  final int initialSkipTicks;
  final int maxSkipTicks;

  final Map<String, int> _emptyRefreshCounts = <String, int>{};
  final Map<String, int> _skipTicks = <String, int>{};
  final Map<String, int> _nextSkipTicks = <String, int>{};

  bool shouldSkipPollingRefresh(String sessionId) {
    final skipTicks = _skipTicks[sessionId] ?? 0;
    if (skipTicks <= 0) {
      return false;
    }
    if (skipTicks == 1) {
      _skipTicks.remove(sessionId);
    } else {
      _skipTicks[sessionId] = skipTicks - 1;
    }
    return true;
  }

  void recordRefreshResult(String sessionId, {required bool hadActivity}) {
    if (hadActivity) {
      reset(sessionId);
      return;
    }
    final emptyRefreshCount = (_emptyRefreshCounts[sessionId] ?? 0) + 1;
    _emptyRefreshCounts[sessionId] = emptyRefreshCount;
    if (emptyRefreshCount < emptyRefreshesBeforeBackoff) {
      return;
    }

    final skipTicks = _nextSkipTicks[sessionId] ?? initialSkipTicks;
    _skipTicks[sessionId] = skipTicks;
    _nextSkipTicks[sessionId] = math.min(skipTicks * 2, maxSkipTicks);
  }

  void reset(String sessionId) {
    _emptyRefreshCounts.remove(sessionId);
    _skipTicks.remove(sessionId);
    _nextSkipTicks.remove(sessionId);
  }

  void remove(String sessionId) {
    reset(sessionId);
  }
}
