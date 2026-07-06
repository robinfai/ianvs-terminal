import 'dart:async';

final class TerminalRefreshScheduler {
  final Set<String> _refreshingSessionIds = <String>{};
  final Set<String> _queuedRefreshSessionIds = <String>{};
  final Set<String> _scheduledRefreshSessionIds = <String>{};
  final Map<String, Timer> _cooldownTimers = <String, Timer>{};

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
    if (!_scheduledRefreshSessionIds.add(sessionId)) {
      return false;
    }
    scheduleMicrotask(() {
      _scheduledRefreshSessionIds.remove(sessionId);
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

  void remove(String sessionId) {
    clearRefreshing(sessionId);
    _queuedRefreshSessionIds.remove(sessionId);
    _scheduledRefreshSessionIds.remove(sessionId);
    cancelCooldown(sessionId);
  }

  void dispose() {
    for (final timer in _cooldownTimers.values) {
      timer.cancel();
    }
    _refreshingSessionIds.clear();
    _queuedRefreshSessionIds.clear();
    _scheduledRefreshSessionIds.clear();
    _cooldownTimers.clear();
  }
}
