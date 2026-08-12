import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ianvs_pty/ianvs_pty.dart';

import '../data/services/data_api_runtime.dart';
import '../platform/app_shutdown_coordinator.dart';
import 'app_startup_models.dart';

typedef AppStartupPathResolver = Future<AppStartupPaths> Function();
typedef AppStartupConfigurationAccessFactory =
    Future<AppStartupConfigurationAccess> Function(AppStartupPaths paths);
typedef AppStartupConfigurationLoader =
    Future<AppStartupConfigurationSnapshot> Function(
      AppStartupConfigurationAccess access,
    );
typedef AppStartupConfigurationValidator =
    Future<void> Function(
      AppStartupConfigurationAccess access,
      AppStartupConfigurationSnapshot snapshot,
    );
typedef AppStartupSecureRecovery =
    Future<DataApiStartupWarning?> Function(
      AppStartupConfigurationAccess access,
    );
typedef AppStartupDataBootstrap =
    Future<DataApiRuntime?> Function(
      AppStartupPaths paths,
      AppStartupConfigurationAccess access,
      AppStartupConfigurationSnapshot configurationSnapshot,
    );
typedef AppStartupPlatformPreparer =
    Future<AppStartupPlatformPreparation> Function(AppStartupPaths paths);
typedef AppStartupPtyLoader =
    Future<PtySessionBackend> Function(AppStartupPlatformPreparation platform);
typedef AppStartupGraphComposer =
    Future<AppRuntimeGraph> Function({
      required int generation,
      required AppStartupPaths paths,
      required AppStartupConfigurationAccess configurationAccess,
      required AppStartupConfigurationSnapshot configurationSnapshot,
      required DataApiRuntime? dataApiRuntime,
      required DataApiStartupWarning? dataApiStartupWarning,
      required PtySessionBackend ptySessionBackend,
    });

final class AppStartupPipeline {
  const AppStartupPipeline({
    required this.resolvePaths,
    required this.createConfigurationAccess,
    required this.loadConfiguration,
    required this.validateConfiguration,
    required this.recoverSecureConfiguration,
    required this.bootstrapData,
    required this.preparePlatform,
    required this.loadPty,
    required this.composeGraph,
    this.rollbackTimeout = const Duration(seconds: 8),
  });

  final AppStartupPathResolver resolvePaths;
  final AppStartupConfigurationAccessFactory createConfigurationAccess;
  final AppStartupConfigurationLoader loadConfiguration;
  final AppStartupConfigurationValidator validateConfiguration;
  final AppStartupSecureRecovery recoverSecureConfiguration;
  final AppStartupDataBootstrap bootstrapData;
  final AppStartupPlatformPreparer preparePlatform;
  final AppStartupPtyLoader loadPty;
  final AppStartupGraphComposer composeGraph;
  final Duration rollbackTimeout;
}

final class AppStartupCoordinator extends ChangeNotifier {
  AppStartupCoordinator({required AppStartupPipeline pipeline})
    : _pipeline = pipeline,
      _closeCoordinator = AppShutdownCoordinator(
        timeout: pipeline.rollbackTimeout,
      ) {
    _closeCoordinator.registerTask('startup-runtime', _settleClose);
  }

  final AppStartupPipeline _pipeline;
  final AppShutdownCoordinator _closeCoordinator;

  AppStartupState _state = const AppStartupLoading(attempt: 0);
  AppStartupState get state => _state;

  Future<void>? _activeAttempt;
  AppRuntimeGraph? _ownedGraph;
  _PendingRuntimeRollback? _pendingRuntimeRollback;
  _PendingGraphRollback? _pendingGraphRollback;
  _PoisonedTerminationLease? _poisonedTerminationLease;
  var _attempt = 0;
  var _nextGeneration = 1;
  var _disposed = false;
  Future<AppShutdownResult>? _closeFuture;
  final Set<AppShutdownFailure> _reportedCloseFailures =
      Set<AppShutdownFailure>.identity();
  var _didReportCloseTimeout = false;
  var _isObservingCloseSettlement = false;

  bool get shutdownHasStarted => _closeCoordinator.hasStarted;

  Future<void> start() => _runSingleFlight();

  Future<void> retry() => _runSingleFlight();

  Future<void> _runSingleFlight() {
    final activeAttempt = _activeAttempt;
    if (activeAttempt != null) {
      return activeAttempt;
    }
    late final Future<void> attempt;
    attempt = _runAttempt().whenComplete(() {
      if (identical(_activeAttempt, attempt)) {
        _activeAttempt = null;
      }
    });
    _activeAttempt = attempt;
    return attempt;
  }

  Future<void> _runAttempt() async {
    if (_disposed) {
      return;
    }
    _attempt += 1;

    final poisonedTerminationLease = _poisonedTerminationLease;
    if (poisonedTerminationLease != null) {
      _setFailure(
        AppStartupStage.runtimeShutdown,
        poisonedTerminationLease.error,
        poisonedTerminationLease.stackTrace,
        dataSettings: poisonedTerminationLease.dataSettings,
      );
      return;
    }

    final priorGraph = _ownedGraph;
    if (priorGraph != null) {
      try {
        if (priorGraph.closeHasStarted) {
          await priorGraph.settleClose().timeout(_pipeline.rollbackTimeout);
        } else {
          await priorGraph.close();
        }
      } on Object catch (error, stackTrace) {
        if (_closeIsStillSettling(error)) {
          return;
        }
        _retainPoisonedTerminationLease(error, stackTrace, dataSettings: null);
        _setFailure(AppStartupStage.runtimeShutdown, error, stackTrace);
        if (_disposed) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        return;
      }
      if (identical(_ownedGraph, priorGraph)) {
        _ownedGraph = null;
      }
      if (_disposed) {
        return;
      }
    }

    final pendingRuntimeRollback = _pendingRuntimeRollback;
    if (pendingRuntimeRollback != null) {
      try {
        await pendingRuntimeRollback.settlement.timeout(
          _pipeline.rollbackTimeout,
        );
        if (identical(_pendingRuntimeRollback, pendingRuntimeRollback)) {
          _pendingRuntimeRollback = null;
        }
      } on Object catch (error, stackTrace) {
        _setFailure(
          AppStartupStage.runtimeShutdown,
          error,
          stackTrace,
          dataSettings: pendingRuntimeRollback.dataSettings,
        );
        return;
      }
    }

    final pendingGraphRollback = _pendingGraphRollback;
    if (pendingGraphRollback != null) {
      try {
        await pendingGraphRollback.graph.settleClose().timeout(
          _pipeline.rollbackTimeout,
        );
        if (identical(_pendingGraphRollback, pendingGraphRollback)) {
          _pendingGraphRollback = null;
        }
      } on Object catch (error, stackTrace) {
        _setFailure(
          AppStartupStage.runtimeShutdown,
          error,
          stackTrace,
          dataSettings: pendingGraphRollback.dataSettings,
        );
        return;
      }
    }

    if (_disposed) {
      return;
    }
    _setState(AppStartupLoading(attempt: _attempt));

    AppStartupStage stage = AppStartupStage.paths;
    AppStartupPaths? paths;
    AppStartupConfigurationAccess? configurationAccess;
    AppStartupConfigurationSnapshot? configurationSnapshot;
    DataApiRuntime? dataApiRuntime;
    AppRuntimeGraph? candidateGraph;
    try {
      paths = await _pipeline.resolvePaths();
      if (await _stopAttemptIfShutdownRequested()) {
        return;
      }

      stage = AppStartupStage.configuration;
      configurationAccess = await _pipeline.createConfigurationAccess(paths);
      if (await _stopAttemptIfShutdownRequested()) {
        return;
      }

      stage = AppStartupStage.secureRecovery;
      final warning = await _pipeline.recoverSecureConfiguration(
        configurationAccess,
      );
      if (await _stopAttemptIfShutdownRequested()) {
        return;
      }

      stage = AppStartupStage.configuration;
      configurationSnapshot = await _pipeline.loadConfiguration(
        configurationAccess,
      );
      if (await _stopAttemptIfShutdownRequested()) {
        return;
      }

      final settings = configurationAccess.settings;
      if (settings case final AppStartupInitialDataSetupCapability setup) {
        final requirement = await setup.initialSetupRequirement(
          configurationSnapshot.configuration,
        );
        if (await _stopAttemptIfShutdownRequested()) {
          return;
        }
        if (requirement != null) {
          _setState(
            AppStartupDataSetupRequired(
              attempt: _attempt,
              requirement: requirement,
              settings: settings,
            ),
          );
          return;
        }
      }

      stage = AppStartupStage.dataBootstrap;
      dataApiRuntime = await _pipeline.bootstrapData(
        paths,
        configurationAccess,
        configurationSnapshot,
      );
      if (await _stopAttemptIfShutdownRequested(runtime: dataApiRuntime)) {
        dataApiRuntime = null;
        return;
      }

      stage = AppStartupStage.platform;
      final platform = await _pipeline.preparePlatform(paths);
      if (await _stopAttemptIfShutdownRequested(runtime: dataApiRuntime)) {
        dataApiRuntime = null;
        return;
      }

      stage = AppStartupStage.pty;
      final ptySessionBackend = await _pipeline.loadPty(platform);
      if (await _stopAttemptIfShutdownRequested(runtime: dataApiRuntime)) {
        dataApiRuntime = null;
        return;
      }

      stage = AppStartupStage.runtimeComposition;
      candidateGraph = await _pipeline.composeGraph(
        generation: _nextGeneration,
        paths: paths,
        configurationAccess: configurationAccess,
        configurationSnapshot: configurationSnapshot,
        dataApiRuntime: dataApiRuntime,
        dataApiStartupWarning: warning,
        ptySessionBackend: ptySessionBackend,
      );
      dataApiRuntime = null;
      if (await _stopAttemptIfShutdownRequested(graph: candidateGraph)) {
        candidateGraph = null;
        return;
      }

      stage = AppStartupStage.configurationValidation;
      await _pipeline.validateConfiguration(
        configurationAccess,
        configurationSnapshot,
      );
      // Keep validation and publication in one synchronous turn. Introducing
      // another await here would reopen a configuration TOCTOU window.
      if (_disposed) {
        await candidateGraph.settleClose();
        candidateGraph = null;
        return;
      }

      final graph = candidateGraph;
      candidateGraph = null;
      _nextGeneration += 1;
      _ownedGraph = graph;
      _setState(AppStartupReady(graph));
    } on Object catch (error, stackTrace) {
      Object failureError = error;
      StackTrace failureStackTrace = stackTrace;
      final graph = candidateGraph;
      if (graph != null) {
        try {
          await graph.close();
        } on Object catch (rollbackError, rollbackStackTrace) {
          if (_closeNeedsRetainedLease(rollbackError)) {
            _pendingGraphRollback = _PendingGraphRollback(
              graph: graph,
              dataSettings: configurationAccess?.settings,
            );
          }
          failureError = AppStartupRollbackException(
            startupError: error,
            rollbackError: rollbackError,
          );
          failureStackTrace = rollbackStackTrace;
        }
      } else if (dataApiRuntime case final runtime?) {
        final settlement = Future<void>.sync(runtime.close);
        try {
          await settlement.timeout(_pipeline.rollbackTimeout);
        } on Object catch (rollbackError, rollbackStackTrace) {
          if (_closeNeedsRetainedLease(rollbackError)) {
            _pendingRuntimeRollback = _PendingRuntimeRollback(
              runtime: runtime,
              settlement: settlement,
              dataSettings: configurationAccess?.settings,
            );
          }
          failureError = AppStartupRollbackException(
            startupError: error,
            rollbackError: rollbackError,
          );
          failureStackTrace = rollbackStackTrace;
        }
      }
      _retainPoisonedTerminationLease(
        failureError,
        failureStackTrace,
        dataSettings: configurationAccess?.settings,
      );
      _setFailure(
        stage,
        failureError,
        failureStackTrace,
        dataSettings: configurationAccess?.settings,
      );
      if (_disposed) {
        Error.throwWithStackTrace(failureError, failureStackTrace);
      }
    }
  }

  Future<bool> _stopAttemptIfShutdownRequested({
    DataApiRuntime? runtime,
    AppRuntimeGraph? graph,
  }) async {
    if (!_disposed) {
      return false;
    }
    if (graph != null) {
      await graph.settleClose();
    } else {
      await runtime?.close();
    }
    return true;
  }

  bool _closeIsStillSettling(Object error) {
    return error is TimeoutException ||
        error is AppRuntimeGraphCloseException && error.result.timedOut;
  }

  bool _closeNeedsRetainedLease(Object error) {
    return _closeIsStillSettling(error) || _containsTerminationUnknown(error);
  }

  bool _containsTerminationUnknown(Object error) {
    return switch (error) {
      DataApiRuntimeTerminationUnknownFailure() => true,
      DataApiRuntimeTerminationFailureCarrier(:final terminationFailure) =>
        terminationFailure != null,
      AppRuntimeGraphCloseException(:final result) => result.failures.any(
        (failure) => _containsTerminationUnknown(failure.error),
      ),
      AppStartupRollbackException(:final rollbackError) =>
        _containsTerminationUnknown(rollbackError),
      AppStartupSettlementException(:final failures) => failures.any(
        (failure) => _containsTerminationUnknown(failure.error),
      ),
      _ => false,
    };
  }

  void _retainPoisonedTerminationLease(
    Object error,
    StackTrace stackTrace, {
    required AppStartupDataSettingsCapability? dataSettings,
  }) {
    if (!_containsTerminationUnknown(error)) {
      return;
    }
    _poisonedTerminationLease ??= _PoisonedTerminationLease(
      error: error,
      stackTrace: stackTrace,
      dataSettings: dataSettings,
    );
  }

  void _setFailure(
    AppStartupStage stage,
    Object error,
    StackTrace stackTrace, {
    AppStartupDataSettingsCapability? dataSettings,
  }) {
    _setState(
      AppStartupRecoverableFailure(
        AppStartupFailure(
          stage: stage,
          error: error,
          stackTrace: stackTrace,
          dataSettings: dataSettings,
        ),
      ),
    );
  }

  void _setState(AppStartupState state) {
    if (_disposed) {
      return;
    }
    _state = state;
    notifyListeners();
  }

  Future<AppShutdownResult> close() {
    final existing = _closeFuture;
    if (existing != null) {
      return existing;
    }
    final future = _closeCoordinator.shutdown();
    _closeFuture = future;
    unawaited(
      future.then((result) {
        _reportCloseResult(result);
        if (result.timedOut && identical(_closeFuture, future)) {
          // Preserve the one underlying settlement, but let a future native
          // Quit request observe it through a new bounded window.
          _closeFuture = null;
        }
      }),
    );
    if (!_isObservingCloseSettlement) {
      _isObservingCloseSettlement = true;
      unawaited(_closeCoordinator.settle().then(_reportCloseResult));
    }
    return future;
  }

  Future<AppShutdownResult> settleClose() {
    return _closeCoordinator.settle();
  }

  Future<void> _settleClose() async {
    _disposed = true;
    // Start the graph coordinator before this method's first await so its
    // application phase captures recording/layout state before Riverpod tears
    // providers down. The graph owns idempotency for every concurrent close
    // requester, including provider-first and native lifecycle shutdown.
    final ownedGraph = _ownedGraph;
    final ownedGraphSettlement = ownedGraph?.settleClose();
    final failures = <AppStartupSettlementFailure>[];

    Future<void> settle(String resource, Future<void>? future) async {
      if (future == null) {
        return;
      }
      try {
        await future;
      } on Object catch (error, stackTrace) {
        failures.add(
          AppStartupSettlementFailure(
            resource: resource,
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
    }

    final attempt = _activeAttempt;
    await settle('active startup attempt', attempt);
    await settle('owned runtime graph', ownedGraphSettlement);
    _ownedGraph = null;

    final pendingGraphRollback = _pendingGraphRollback;
    await settle(
      'pending candidate graph rollback',
      pendingGraphRollback?.graph.settleClose(),
    );
    if (identical(_pendingGraphRollback, pendingGraphRollback)) {
      _pendingGraphRollback = null;
    }

    final pendingRuntimeRollback = _pendingRuntimeRollback;
    if (pendingRuntimeRollback != null) {
      await settle(
        'pending data runtime rollback',
        pendingRuntimeRollback.settlement,
      );
      if (identical(_pendingRuntimeRollback, pendingRuntimeRollback)) {
        _pendingRuntimeRollback = null;
      }
    }

    final poisonedTerminationLease = _poisonedTerminationLease;
    if (poisonedTerminationLease != null &&
        !failures.any(
          (failure) => _containsTerminationUnknown(failure.error),
        )) {
      failures.add(
        AppStartupSettlementFailure(
          resource: 'unconfirmed data runtime termination',
          error: poisonedTerminationLease.error,
          stackTrace: poisonedTerminationLease.stackTrace,
        ),
      );
    }

    if (failures.isNotEmpty) {
      throw AppStartupSettlementException(failures);
    }
  }

  void _reportCloseResult(AppShutdownResult result) {
    for (final failure in result.failures) {
      if (!_reportedCloseFailures.add(failure)) {
        continue;
      }
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: failure.error,
          stack: failure.stackTrace,
          library: 'Ianvs Terminal startup shutdown',
          context: ErrorDescription(
            'while closing the typed application runtime',
          ),
        ),
      );
    }
    if (result.timedOut && !_didReportCloseTimeout) {
      _didReportCloseTimeout = true;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: TimeoutException(
            'Typed application runtime shutdown exceeded its bounded timeout.',
            _closeCoordinator.timeout,
          ),
          library: 'Ianvs Terminal startup shutdown',
        ),
      );
    }
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}

final class _PendingRuntimeRollback {
  _PendingRuntimeRollback({
    required this.runtime,
    required this.settlement,
    required this.dataSettings,
  });

  final DataApiRuntime runtime;
  final Future<void> settlement;
  final AppStartupDataSettingsCapability? dataSettings;
}

final class _PendingGraphRollback {
  _PendingGraphRollback({required this.graph, required this.dataSettings});

  final AppRuntimeGraph graph;
  final AppStartupDataSettingsCapability? dataSettings;
}

final class _PoisonedTerminationLease {
  _PoisonedTerminationLease({
    required this.error,
    required this.stackTrace,
    required this.dataSettings,
  });

  final Object error;
  final StackTrace stackTrace;
  final AppStartupDataSettingsCapability? dataSettings;
}

final class AppStartupSettlementFailure {
  const AppStartupSettlementFailure({
    required this.resource,
    required this.error,
    required this.stackTrace,
  });

  final String resource;
  final Object error;
  final StackTrace stackTrace;
}

final class AppStartupSettlementException implements Exception {
  AppStartupSettlementException(Iterable<AppStartupSettlementFailure> failures)
    : failures = List.unmodifiable(failures);

  final List<AppStartupSettlementFailure> failures;

  @override
  String toString() {
    return 'Application startup shutdown settled with '
        '${failures.length} resource failure(s): '
        '${failures.map((failure) => failure.resource).join(', ')}.';
  }
}

final class AppStartupRollbackException implements Exception {
  const AppStartupRollbackException({
    required this.startupError,
    required this.rollbackError,
  });

  final Object startupError;
  final Object rollbackError;

  @override
  String toString() {
    return 'Startup failed ($startupError), and bounded rollback also failed '
        '($rollbackError).';
  }
}
