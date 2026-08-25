import 'dart:io';

import 'package:ianvs_pty/ianvs_pty.dart';

import '../data/configuration/data_api_configuration.dart';
import '../data/configuration/data_api_configuration_providers.dart';
import '../data/configuration/data_api_configuration_repository.dart';
import '../data/services/data_api_remote_session_store.dart';
import '../data/services/data_api_runtime.dart';
import '../data/services/portable_master_key.dart';
import '../features/recording/local_session_recording_repository.dart';
import '../persistence_repository_composition.dart';
import '../platform/app_shutdown_coordinator.dart';

enum AppStartupStage {
  paths,
  secureRecovery,
  configuration,
  dataBootstrap,
  platform,
  pty,
  configurationValidation,
  runtimeComposition,
  runtimeShutdown,
}

final class AppStartupPaths {
  const AppStartupPaths({
    required this.appSupportDirectory,
    this.appDocumentsDirectory,
  });

  final Directory appSupportDirectory;
  final Directory? appDocumentsDirectory;
}

final class AppStartupPlatformPreparation {
  const AppStartupPlatformPreparation({
    required this.usesIosSandboxShell,
    this.iosSandboxRoot,
  });

  final bool usesIosSandboxShell;
  final Directory? iosSandboxRoot;
}

/// Configuration handles created before the first configuration read.
///
/// Keeping these handles separate lets startup expose a working recovery
/// settings capability even when the authoritative configuration cannot be
/// loaded normally.
final class AppStartupConfigurationAccess {
  const AppStartupConfigurationAccess({
    required this.repository,
    required this.remoteSessionStore,
    required this.masterKeyRepository,
    required this.settings,
  });

  final DataApiConfigurationRepository repository;
  final DataApiRemoteSessionSlotStore remoteSessionStore;
  final PortableMasterKeyRepository masterKeyRepository;
  final AppStartupDataSettingsCapability settings;
}

/// Immutable identity of the authoritative configuration used by one startup
/// attempt. Equality on [DataApiConfiguration] deliberately ignores persisted
/// metadata, so startup carries the generation and full content digest
/// explicitly when it validates that a runtime still matches storage.
final class AppStartupConfigurationSnapshot {
  const AppStartupConfigurationSnapshot({
    required this.configuration,
    required this.generation,
    required this.digest,
  });

  final DataApiConfiguration configuration;
  final int generation;
  final String digest;
}

final class AppStartupConfigurationSnapshotConflictException
    implements Exception {
  const AppStartupConfigurationSnapshotConflictException({
    required this.expectedGeneration,
    required this.actualGeneration,
    required this.expectedDigest,
    required this.actualDigest,
  });

  final int expectedGeneration;
  final int actualGeneration;
  final String expectedDigest;
  final String actualDigest;

  @override
  String toString() {
    return 'The data service configuration changed during startup '
        '(generation $expectedGeneration -> $actualGeneration). Retry to '
        'build the runtime from the new authoritative snapshot.';
  }
}

abstract interface class AppStartupDataSettingsCapability {
  bool get localDataApiAvailable;

  Future<DataApiConfiguration> loadForRecovery();

  Future<void> saveDisabled();

  Future<void> saveLocal();

  Future<void> reconnect(DataApiRemoteLoginRequest request);
}

abstract interface class AppStartupMasterKeyCapability {
  Future<void> importPortableMasterKey(String encoded);

  Future<String> exportPortableMasterKey();
}

/// Optional startup gate implemented by hosts that require an initial Data API
/// mode decision before the runtime may be composed.
///
/// Keeping this separate from [AppStartupDataSettingsCapability] preserves the
/// recovery-settings contract for embedders that do not have first-launch
/// onboarding.
abstract interface class AppStartupInitialDataSetupCapability {
  Future<AppStartupDataSetupRequirement?> initialSetupRequirement(
    DataApiConfiguration configuration,
  );
}

enum AppStartupDataSetupRequirement { optional, required }

final class AppStartupFailure {
  AppStartupFailure({
    required this.stage,
    required this.error,
    required this.stackTrace,
    this.dataSettings,
  });

  final AppStartupStage stage;
  final Object error;
  final StackTrace stackTrace;
  final AppStartupDataSettingsCapability? dataSettings;

  bool get canRetry => true;

  bool get canOpenSettings => dataSettings != null;
}

sealed class AppStartupState {
  const AppStartupState();
}

final class AppStartupLoading extends AppStartupState {
  const AppStartupLoading({required this.attempt});

  final int attempt;
}

final class AppStartupDataSetupRequired extends AppStartupState {
  const AppStartupDataSetupRequired({
    required this.attempt,
    required this.requirement,
    required this.settings,
  });

  final int attempt;
  final AppStartupDataSetupRequirement requirement;
  final AppStartupDataSettingsCapability settings;

  bool get canSkip => requirement == AppStartupDataSetupRequirement.optional;
}

final class AppStartupReady extends AppStartupState {
  const AppStartupReady(this.graph);

  final AppRuntimeGraph graph;
}

final class AppStartupRecoverableFailure extends AppStartupState {
  const AppStartupRecoverableFailure(this.failure);

  final AppStartupFailure failure;
}

final class AppRuntimeGraphCloseException implements Exception {
  AppRuntimeGraphCloseException({required this.result});

  final AppShutdownResult result;

  @override
  String toString() {
    final details = <String>[
      if (result.timedOut) 'timed out',
      if (result.failures.isNotEmpty)
        '${result.failures.length} shutdown task(s) failed',
    ];
    return 'Runtime graph shutdown did not settle cleanly: '
        '${details.join(', ')}.';
  }
}

/// Complete, immutable dependency graph exposed only after startup succeeds.
///
/// [shutdownCoordinator] is the single owner of runtime cleanup. Both native
/// application shutdown and graph replacement call [close], whose idempotent
/// future prevents the same resources from being closed twice.
final class AppRuntimeGraph {
  AppRuntimeGraph({
    required this.generation,
    required this.paths,
    required this.dataApiConfiguration,
    required this.dataApiConfigurationRepository,
    required this.masterKeyRepository,
    required this.dataApiRuntime,
    required this.dataApiStartupWarning,
    required this.ptySessionBackend,
    required this.persistenceRepositories,
    required this.recordingRepository,
    required this.shutdownCoordinator,
    this.localMigrationRuntimeStarter,
    this.remoteFallbackSnapshotRuntimeStarter,
    this.remoteFallbackSnapshotCommitter,
    this.remoteFallbackSnapshotActivator,
  }) {
    if (dataApiRuntime case final runtime?) {
      shutdownCoordinator.registerTask(
        'data-api-runtime',
        runtime.close,
        phase: AppShutdownPhase.infrastructure,
      );
    }
  }

  final int generation;
  final AppStartupPaths paths;
  final DataApiConfiguration dataApiConfiguration;
  final DataApiConfigurationRepository dataApiConfigurationRepository;
  final PortableMasterKeyRepository masterKeyRepository;
  final DataApiRuntime? dataApiRuntime;
  final DataApiStartupWarning? dataApiStartupWarning;
  final PtySessionBackend ptySessionBackend;
  final PersistenceRepositoryComposition persistenceRepositories;
  final LocalSessionRecordingRepository recordingRepository;
  final AppShutdownCoordinator shutdownCoordinator;
  final DataApiLocalMigrationRuntimeStarter? localMigrationRuntimeStarter;
  final DataApiLocalMigrationRuntimeStarter?
  remoteFallbackSnapshotRuntimeStarter;
  final Future<void> Function()? remoteFallbackSnapshotCommitter;
  final Future<void> Function()? remoteFallbackSnapshotActivator;

  Future<void>? _boundedCloseFuture;
  Future<void>? _settledCloseFuture;

  bool get closeHasStarted => shutdownCoordinator.hasStarted;

  Future<void> close() => _boundedCloseFuture ??= _closeBounded();

  Future<void> _closeBounded() async {
    final result = await shutdownCoordinator.shutdown();
    if (result.timedOut || result.failures.isNotEmpty) {
      throw AppRuntimeGraphCloseException(result: result);
    }
  }

  /// Waits for the one already-started shutdown execution to fully settle.
  /// This never reruns tasks after [close] returned a bounded timeout.
  Future<void> settleClose() => _settledCloseFuture ??= _settleClose();

  Future<void> _settleClose() async {
    final result = await shutdownCoordinator.settle();
    if (result.failures.isNotEmpty) {
      throw AppRuntimeGraphCloseException(result: result);
    }
  }
}
