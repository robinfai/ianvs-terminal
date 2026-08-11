import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef AppShutdownTask = Future<void> Function();

/// Ordered process-shutdown boundaries.
///
/// Application state must be finalized before infrastructure such as local
/// sidecars is released. Tasks within one phase still run concurrently.
enum AppShutdownPhase { application, infrastructure }

final class _RegisteredAppShutdownTask {
  const _RegisteredAppShutdownTask({required this.phase, required this.run});

  final AppShutdownPhase phase;
  final AppShutdownTask run;
}

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
/// Application tasks settle before infrastructure cleanup starts. Tasks in the
/// same phase start concurrently, and the complete sequence shares one global
/// timeout.
final class AppShutdownCoordinator {
  AppShutdownCoordinator({this.timeout = const Duration(seconds: 8)}) {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive.');
    }
  }

  final Duration timeout;

  final Map<String, _RegisteredAppShutdownTask> _tasks =
      <String, _RegisteredAppShutdownTask>{};
  Future<AppShutdownResult>? _shutdownFuture;

  bool get hasStarted => _shutdownFuture != null;

  void registerTask(
    String name,
    AppShutdownTask task, {
    AppShutdownPhase phase = AppShutdownPhase.application,
  }) {
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
    _tasks[normalizedName] = _RegisteredAppShutdownTask(
      phase: phase,
      run: task,
    );
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
    final tasks = Map<String, _RegisteredAppShutdownTask>.unmodifiable(_tasks);
    final failures = <AppShutdownFailure>[];
    var settledTaskCount = 0;

    var timedOut = false;
    for (final phase in AppShutdownPhase.values) {
      final phaseTasks = tasks.entries
          .where((entry) => entry.value.phase == phase)
          .toList(growable: false);
      if (phaseTasks.isEmpty) {
        continue;
      }
      final remaining = timeout - stopwatch.elapsed;
      if (remaining <= Duration.zero) {
        timedOut = true;
        break;
      }
      final phaseFutures = phaseTasks
          .map((entry) async {
            try {
              await Future<void>.sync(entry.value.run);
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
      try {
        await Future.wait(phaseFutures).timeout(remaining);
      } on TimeoutException {
        timedOut = true;
        break;
      }
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
  return AppShutdownCoordinator();
});
