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
  Future<AppShutdownResult>? _settlementFuture;

  late Stopwatch _stopwatch;
  late Map<String, _RegisteredAppShutdownTask> _shutdownTasks;
  final List<AppShutdownFailure> _failures = <AppShutdownFailure>[];
  var _settledTaskCount = 0;

  bool get hasStarted => _settlementFuture != null;

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

  Future<AppShutdownResult> shutdown({bool bounded = true}) {
    final settlement = _startShutdown();
    if (!bounded) {
      return settlement;
    }
    return _shutdownFuture ??= _boundedResult(settlement);
  }

  Future<AppShutdownResult> _startShutdown() {
    final existing = _settlementFuture;
    if (existing != null) {
      return existing;
    }
    final settlement = Completer<AppShutdownResult>();
    _settlementFuture = settlement.future;
    _stopwatch = Stopwatch()..start();
    _shutdownTasks = Map<String, _RegisteredAppShutdownTask>.unmodifiable(
      _tasks,
    );
    unawaited(
      _runToSettlement().then(
        settlement.complete,
        onError: settlement.completeError,
      ),
    );
    return settlement.future;
  }

  /// The eventual result after every registered task has actually settled.
  ///
  /// Calling this starts shutdown when needed. Unlike [shutdown], this future
  /// is not shortened by [timeout]; it is used before a replacement runtime is
  /// allowed to start after a bounded shutdown response timed out.
  Future<AppShutdownResult> settle() {
    return shutdown(bounded: false);
  }

  Future<AppShutdownResult> _runToSettlement() {
    // Start application tasks synchronously with [shutdown]. Flutter disposes
    // descendants before their parent State, so deferring this first phase to
    // an async body would let ProviderScope disposal race recording/layout
    // capture. Later phases still begin only after the preceding phase settles.
    var phases = _startPhase(AppShutdownPhase.application);
    phases = phases.then((_) => _startPhase(AppShutdownPhase.infrastructure));
    return phases.then((_) {
      _stopwatch.stop();
      return AppShutdownResult(
        timedOut: false,
        totalTaskCount: _shutdownTasks.length,
        settledTaskCount: _settledTaskCount,
        elapsed: _stopwatch.elapsed,
        failures: List<AppShutdownFailure>.unmodifiable(_failures),
      );
    });
  }

  Future<void> _startPhase(AppShutdownPhase phase) {
    final phaseTasks = _shutdownTasks.entries.where(
      (entry) => entry.value.phase == phase,
    );
    final phaseFutures = <Future<void>>[];
    for (final entry in phaseTasks) {
      Future<void> task;
      try {
        // Invoke the callback directly so pre-await capture begins before
        // shutdown() returns. Normalize synchronous exceptions below.
        task = entry.value.run();
      } on Object catch (error, stackTrace) {
        task = Future<void>.error(error, stackTrace);
      }
      phaseFutures.add(
        task
            .catchError((Object error, StackTrace stackTrace) {
              _failures.add(
                AppShutdownFailure(
                  taskName: entry.key,
                  error: error,
                  stackTrace: stackTrace,
                ),
              );
            })
            .whenComplete(() {
              _settledTaskCount += 1;
            }),
      );
    }
    return Future.wait(phaseFutures);
  }

  Future<AppShutdownResult> _boundedResult(
    Future<AppShutdownResult> settlement,
  ) async {
    try {
      return await settlement.timeout(timeout);
    } on TimeoutException {
      return AppShutdownResult(
        timedOut: true,
        totalTaskCount: _shutdownTasks.length,
        settledTaskCount: _settledTaskCount,
        elapsed: _stopwatch.elapsed,
        failures: List<AppShutdownFailure>.unmodifiable(_failures),
      );
    }
  }
}

final appShutdownCoordinatorProvider = Provider<AppShutdownCoordinator>((ref) {
  return AppShutdownCoordinator();
});
