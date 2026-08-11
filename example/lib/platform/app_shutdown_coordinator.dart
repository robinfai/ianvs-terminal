import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef AppShutdownTask = Future<void> Function();

final class AppShutdownFailure {
  const AppShutdownFailure({
    required this.taskName,
    required this.error,
    required this.stackTrace,
  });

  final String taskName;
  final Object error;
  final StackTrace stackTrace;
}

final class AppShutdownResult {
  const AppShutdownResult({
    required this.timedOut,
    required this.totalTaskCount,
    required this.settledTaskCount,
    required this.elapsed,
    required this.failures,
  });

  final bool timedOut;
  final int totalTaskCount;
  final int settledTaskCount;
  final Duration elapsed;
  final List<AppShutdownFailure> failures;

  bool get completedWithinTimeout => !timedOut;

  Map<String, Object> toPlatformMessage() => <String, Object>{
    'completed': completedWithinTimeout,
    'timedOut': timedOut,
    'totalTaskCount': totalTaskCount,
    'settledTaskCount': settledTaskCount,
    'failureCount': failures.length,
    'failedTaskNames': failures
        .map((failure) => failure.taskName)
        .toList(growable: false),
    'elapsedMilliseconds': elapsed.inMilliseconds,
  };
}

/// Runs all process-level cleanup through one bounded, idempotent boundary.
///
/// Tasks start concurrently so one slow cleanup cannot prevent the remaining
/// tasks from getting a chance to run before the global timeout expires.
final class AppShutdownCoordinator {
  AppShutdownCoordinator({this.timeout = const Duration(seconds: 8)}) {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive.');
    }
  }

  final Duration timeout;

  final Map<String, AppShutdownTask> _tasks = <String, AppShutdownTask>{};
  Future<AppShutdownResult>? _shutdownFuture;

  bool get hasStarted => _shutdownFuture != null;

  void registerTask(String name, AppShutdownTask task) {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Must not be empty.');
    }
    if (hasStarted) {
      throw StateError('Shutdown has already started.');
    }
    if (_tasks.containsKey(normalizedName)) {
      throw ArgumentError.value(
        normalizedName,
        'name',
        'A shutdown task with this name is already registered.',
      );
    }
    _tasks[normalizedName] = task;
  }

  bool unregisterTask(String name) {
    if (hasStarted) {
      throw StateError('Shutdown has already started.');
    }
    return _tasks.remove(name.trim()) != null;
  }

  Future<AppShutdownResult> shutdown() {
    return _shutdownFuture ??= _runShutdown();
  }

  Future<AppShutdownResult> _runShutdown() async {
    final stopwatch = Stopwatch()..start();
    final tasks = Map<String, AppShutdownTask>.unmodifiable(_tasks);
    final failures = <AppShutdownFailure>[];
    var settledTaskCount = 0;

    final taskFutures = tasks.entries
        .map((entry) async {
          try {
            await Future<void>.sync(entry.value);
          } on Object catch (error, stackTrace) {
            failures.add(
              AppShutdownFailure(
                taskName: entry.key,
                error: error,
                stackTrace: stackTrace,
              ),
            );
          } finally {
            settledTaskCount += 1;
          }
        })
        .toList(growable: false);

    var timedOut = false;
    try {
      await Future.wait(taskFutures).timeout(timeout);
    } on TimeoutException {
      timedOut = true;
    }
    stopwatch.stop();

    return AppShutdownResult(
      timedOut: timedOut,
      totalTaskCount: tasks.length,
      settledTaskCount: settledTaskCount,
      elapsed: stopwatch.elapsed,
      failures: List<AppShutdownFailure>.unmodifiable(failures),
    );
  }
}

final appShutdownCoordinatorProvider = Provider<AppShutdownCoordinator>((ref) {
  final coordinator = AppShutdownCoordinator();
  ref.onDispose(() => unawaited(coordinator.shutdown()));
  return coordinator;
});
