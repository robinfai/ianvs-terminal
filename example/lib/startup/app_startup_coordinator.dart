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
typedef AppStartupMigration =
    Future<void> Function(
      AppStartupPaths paths,
      AppStartupConfigurationAccess access,
      AppStartupConfigurationSnapshot configurationSnapshot,
      DataApiRuntime? runtime,
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
typedef AppStartupMigrationRecoveryFactory =
    List<AppStartupMigrationRecoveryOperation> Function({
      required Object error,
      required AppStartupPaths paths,
      required AppStartupConfigurationAccess configurationAccess,
      required AppStartupConfigurationSnapshot configurationSnapshot,
    });

final class AppStartupPipeline {
  const AppStartupPipeline({
    required this.resolvePaths,
    required this.createConfigurationAccess,
    required this.loadConfiguration,
    required this.validateConfiguration,
    required this.recoverSecureConfiguration,
    required this.bootstrapData,
    required this.prepareMigration,
    required this.preparePlatform,
    required this.loadPty,
    required this.composeGraph,
    required this.migrationRecoveries,
    this.rollbackTimeout = const Duration(seconds: 8),
  });

  final AppStartupPathResolver resolvePaths;
  final AppStartupConfigurationAccessFactory createConfigurationAccess;
  final AppStartupConfigurationLoader loadConfiguration;
  final AppStartupConfigurationValidator validateConfiguration;
  final AppStartupSecureRecovery recoverSecureConfiguration;
  final AppStartupDataBootstrap bootstrapData;
  final AppStartupMigration prepareMigration;
  final AppStartupPlatformPreparer preparePlatform;
  final AppStartupPtyLoader loadPty;
  final AppStartupGraphComposer composeGraph;
  final AppStartupMigrationRecoveryFactory migrationRecoveries;
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
  Future<void>? _activeRecovery;
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

  bool get shutdownHasStarted => _closeFuture != null;

  Future<void> start() => _runSingleFlight();

  Future<void> retry() => _runSingleFlight();

  Future<void> _runSingleFlight() {
    final activeRecovery = _activeRecovery;
    if (activeRecovery != null) {
      return activeRecovery;
    }
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
        migrationRecoveries: poisonedTerminationLease.migrationRecoveries,
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
        _retainPoisonedTerminationLease(
          error,
          stackTrace,
          dataSettings: null,
          migrationRecoveries: const <AppStartupMigrationRecoveryCapability>[],
        );
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
          migrationRecoveries: pendingRuntimeRollback.migrationRecoveries,
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
          migrationRecoveries: pendingGraphRollback.migrationRecoveries,
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

      stage = AppStartupStage.migration;
      await _pipeline.prepareMigration(
        paths,
        configurationAccess,
        configurationSnapshot,
        dataApiRuntime,
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
      final recoveryOperations =
          stage == AppStartupStage.migration &&
              paths != null &&
              configurationAccess != null &&
              configurationSnapshot != null
          ? _pipeline.migrationRecoveries(
              error: error,
              paths: paths,
              configurationAccess: configurationAccess,
              configurationSnapshot: configurationSnapshot,
            )
          : const <AppStartupMigrationRecoveryOperation>[];
      final migrationRecoveries = <AppStartupMigrationRecoveryCapability>[
        if (paths != null && configurationAccess != null)
          for (final operation in recoveryOperations)
            _OwnedMigrationRecoveryCapability(
              owner: this,
              context: _MigrationRecoveryContext(
                paths: paths,
                configurationAccess: configurationAccess,
              ),
              operation: operation,
            ),
      ];
      final graph = candidateGraph;
      if (graph != null) {
        try {
          await graph.close();
        } on Object catch (rollbackError, rollbackStackTrace) {
          if (_closeNeedsRetainedLease(rollbackError)) {
            _pendingGraphRollback = _PendingGraphRollback(
              graph: graph,
              dataSettings: configurationAccess?.settings,
              migrationRecoveries: migrationRecoveries,
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
              migrationRecoveries: migrationRecoveries,
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
        migrationRecoveries: migrationRecoveries,
      );
      _setFailure(
        stage,
        failureError,
        failureStackTrace,
        dataSettings: configurationAccess?.settings,
        migrationRecoveries: migrationRecoveries,
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

  Future<void> _runMigrationRecovery(
    _MigrationRecoveryContext context,
    AppStartupMigrationRecoveryOperation operation,
  ) {
    final activeRecovery = _activeRecovery;
    if (activeRecovery != null) {
      return activeRecovery;
    }
    if (_disposed) {
      return Future<void>.error(
        StateError('Application shutdown has already started.'),
      );
    }
    final poisonedTerminationLease = _poisonedTerminationLease;
    if (poisonedTerminationLease != null) {
      return Future<void>.error(
        poisonedTerminationLease.error,
        poisonedTerminationLease.stackTrace,
      );
    }
    if (_activeAttempt != null || _ownedGraph != null) {
      return Future<void>.error(
        StateError('Startup or an active runtime already owns the pipeline.'),
      );
    }

    late final Future<void> recovery;
    recovery = _executeMigrationRecovery(context, operation).whenComplete(() {
      if (identical(_activeRecovery, recovery)) {
        _activeRecovery = null;
      }
    });
    _activeRecovery = recovery;
    return recovery;
  }

  Future<void> _executeMigrationRecovery(
    _MigrationRecoveryContext context,
    AppStartupMigrationRecoveryOperation operation,
  ) async {
    await _settlePendingRollbackBeforeRecovery();
    if (_disposed) {
      return;
    }

    final snapshot = await _pipeline.loadConfiguration(
      context.configurationAccess,
    );
    if (_disposed) {
      return;
    }
    final runtime = await _pipeline.bootstrapData(
      context.paths,
      context.configurationAccess,
      snapshot,
    );
    if (runtime == null) {
      throw StateError('The data service is disabled.');
    }

    Object? operationError;
    StackTrace? operationStackTrace;
    try {
      if (!_disposed) {
        await _pipeline.validateConfiguration(
          context.configurationAccess,
          snapshot,
        );
        if (!_disposed) {
          await operation.run(runtime);
        }
      }
    } on Object catch (error, stackTrace) {
      operationError = error;
      operationStackTrace = stackTrace;
    }

    final settlement = Future<void>.sync(runtime.close);
    try {
      await settlement.timeout(_pipeline.rollbackTimeout);
    } on Object catch (closeError, closeStackTrace) {
      if (_closeNeedsRetainedLease(closeError)) {
        _pendingRuntimeRollback = _PendingRuntimeRollback(
          runtime: runtime,
          settlement: settlement,
          dataSettings: context.configurationAccess.settings,
          migrationRecoveries: const <AppStartupMigrationRecoveryCapability>[],
        );
      }
      _retainPoisonedTerminationLease(
        closeError,
        closeStackTrace,
        dataSettings: context.configurationAccess.settings,
        migrationRecoveries: const <AppStartupMigrationRecoveryCapability>[],
      );
      if (operationError != null) {
        Error.throwWithStackTrace(
          AppStartupRollbackException(
            startupError: operationError,
            rollbackError: closeError,
          ),
          closeStackTrace,
        );
      }
      Error.throwWithStackTrace(closeError, closeStackTrace);
    }

    if (operationError != null) {
      Error.throwWithStackTrace(operationError, operationStackTrace!);
    }
  }

  Future<void> _settlePendingRollbackBeforeRecovery() async {
    final poisonedTerminationLease = _poisonedTerminationLease;
    if (poisonedTerminationLease != null) {
      Error.throwWithStackTrace(
        poisonedTerminationLease.error,
        poisonedTerminationLease.stackTrace,
      );
    }
    final pendingRuntimeRollback = _pendingRuntimeRollback;
    if (pendingRuntimeRollback != null) {
      await pendingRuntimeRollback.settlement.timeout(
        _pipeline.rollbackTimeout,
      );
      if (identical(_pendingRuntimeRollback, pendingRuntimeRollback)) {
        _pendingRuntimeRollback = null;
      }
    }

    final pendingGraphRollback = _pendingGraphRollback;
    if (pendingGraphRollback != null) {
      await pendingGraphRollback.graph.settleClose().timeout(
        _pipeline.rollbackTimeout,
      );
      if (identical(_pendingGraphRollback, pendingGraphRollback)) {
        _pendingGraphRollback = null;
      }
    }
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
    required Iterable<AppStartupMigrationRecoveryCapability>
    migrationRecoveries,
  }) {
    if (!_containsTerminationUnknown(error)) {
      return;
    }
    _poisonedTerminationLease ??= _PoisonedTerminationLease(
      error: error,
      stackTrace: stackTrace,
      dataSettings: dataSettings,
      migrationRecoveries: migrationRecoveries,
    );
  }

  void _setFailure(
    AppStartupStage stage,
    Object error,
    StackTrace stackTrace, {
    AppStartupDataSettingsCapability? dataSettings,
    Iterable<AppStartupMigrationRecoveryCapability> migrationRecoveries =
        const <AppStartupMigrationRecoveryCapability>[],
  }) {
    _setState(
      AppStartupRecoverableFailure(
        AppStartupFailure(
          stage: stage,
          error: error,
          stackTrace: stackTrace,
          dataSettings: dataSettings,
          migrationRecoveries: migrationRecoveries,
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
    unawaited(future.then(_reportCloseResult));
    unawaited(_closeCoordinator.settle().then(_reportCloseResult));
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
    await settle('active migration recovery', _activeRecovery);

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
    required Iterable<AppStartupMigrationRecoveryCapability>
    migrationRecoveries,
  }) : migrationRecoveries = List.unmodifiable(migrationRecoveries);

  final DataApiRuntime runtime;
  final Future<void> settlement;
  final AppStartupDataSettingsCapability? dataSettings;
  final List<AppStartupMigrationRecoveryCapability> migrationRecoveries;
}

final class _PendingGraphRollback {
  _PendingGraphRollback({
    required this.graph,
    required this.dataSettings,
    required Iterable<AppStartupMigrationRecoveryCapability>
    migrationRecoveries,
  }) : migrationRecoveries = List.unmodifiable(migrationRecoveries);

  final AppRuntimeGraph graph;
  final AppStartupDataSettingsCapability? dataSettings;
  final List<AppStartupMigrationRecoveryCapability> migrationRecoveries;
}

final class _PoisonedTerminationLease {
  _PoisonedTerminationLease({
    required this.error,
    required this.stackTrace,
    required this.dataSettings,
    required Iterable<AppStartupMigrationRecoveryCapability>
    migrationRecoveries,
  }) : migrationRecoveries = List.unmodifiable(migrationRecoveries);

  final Object error;
  final StackTrace stackTrace;
  final AppStartupDataSettingsCapability? dataSettings;
  final List<AppStartupMigrationRecoveryCapability> migrationRecoveries;
}

final class _MigrationRecoveryContext {
  const _MigrationRecoveryContext({
    required this.paths,
    required this.configurationAccess,
  });

  final AppStartupPaths paths;
  final AppStartupConfigurationAccess configurationAccess;
}

final class _OwnedMigrationRecoveryCapability
    implements AppStartupMigrationRecoveryCapability {
  const _OwnedMigrationRecoveryCapability({
    required this.owner,
    required this.context,
    required this.operation,
  });

  final AppStartupCoordinator owner;
  final _MigrationRecoveryContext context;
  final AppStartupMigrationRecoveryOperation operation;

  @override
  AppStartupMigrationRecoveryKind get kind => operation.kind;

  @override
  Future<void> run() => owner._runMigrationRecovery(context, operation);
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
