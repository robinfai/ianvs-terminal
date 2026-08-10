import 'dart:async';

final class TerminalRefreshScheduler {
  final Set<String> _refreshingSessionIds = <String>{};
  final Set<String> _queuedRefreshSessionIds = <String>{};
  final Map<String, Object> _scheduledRefreshTokens = <String, Object>{};
  final Map<String, Timer> _cooldownTimers = <String, Timer>{};
  final Map<String, Timer> _inputProbeTimers = <String, Timer>{};

  bool isRefreshing(String sessionId) {
    return _refreshingSessionIds.contains(sessionId);
  }

  bool hasQueuedRefresh(String sessionId) {
    return _queuedRefreshSessionIds.contains(sessionId);
  }

  bool hasCooldown(String sessionId) {
    return _cooldownTimers.containsKey(sessionId);
  }

  void markRefreshing(String sessionId) {
    _refreshingSessionIds.add(sessionId);
  }

  void clearRefreshing(String sessionId) {
    _refreshingSessionIds.remove(sessionId);
  }

  void queueRefresh(String sessionId) {
    _queuedRefreshSessionIds.add(sessionId);
  }

  bool consumeQueuedRefresh(String sessionId) {
    return _queuedRefreshSessionIds.remove(sessionId);
  }

  bool scheduleDeferredRefresh(String sessionId, void Function() refresh) {
    if (_scheduledRefreshTokens.containsKey(sessionId)) {
      return false;
    }
    final token = Object();
    _scheduledRefreshTokens[sessionId] = token;
    scheduleMicrotask(() {
      if (!identical(_scheduledRefreshTokens[sessionId], token)) {
        return;
      }
      _scheduledRefreshTokens.remove(sessionId);
      refresh();
    });
    return true;
  }

  void startCooldown(
    String sessionId,
    Duration duration,
    void Function() onQueuedRefresh,
  ) {
    _cooldownTimers.remove(sessionId)?.cancel();
    _cooldownTimers[sessionId] = Timer(duration, () {
      _cooldownTimers.remove(sessionId);
      if (consumeQueuedRefresh(sessionId)) {
        onQueuedRefresh();
      }
    });
  }

  void cancelCooldown(String sessionId) {
    _cooldownTimers.remove(sessionId)?.cancel();
  }

  bool scheduleInputProbe(
    String sessionId,
    Duration delay,
    void Function() probe,
  ) {
    if (_inputProbeTimers.containsKey(sessionId)) {
      return false;
    }
    _inputProbeTimers[sessionId] = Timer(delay, () {
      _inputProbeTimers.remove(sessionId);
      probe();
    });
    return true;
  }

  void cancelInputProbe(String sessionId) {
    _inputProbeTimers.remove(sessionId)?.cancel();
  }

  void remove(String sessionId) {
    clearRefreshing(sessionId);
    _queuedRefreshSessionIds.remove(sessionId);
    _scheduledRefreshTokens.remove(sessionId);
    cancelCooldown(sessionId);
    cancelInputProbe(sessionId);
  }

  void dispose() {
    for (final timer in _cooldownTimers.values) {
      timer.cancel();
    }
    for (final timer in _inputProbeTimers.values) {
      timer.cancel();
    }
    _refreshingSessionIds.clear();
    _queuedRefreshSessionIds.clear();
    _scheduledRefreshTokens.clear();
    _cooldownTimers.clear();
    _inputProbeTimers.clear();
  }
}
