import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/configuration/data_api_configuration.dart';
import '../data/configuration/data_api_configuration_repository.dart';
import '../data/repositories/data_api_installation_identity_repository.dart';
import '../data/repositories/data_api_legacy_json_migration.dart';
import '../data/services/data_api_bootstrap.dart';
import '../data/services/data_api_client.dart';
import '../data/services/data_api_remote_session_store.dart';
import '../data/services/data_api_runtime.dart';
import '../features/pty/pty.dart';
import '../features/recording/local_session_recording_repository.dart';
import '../persistence_repository_composition.dart';
import '../platform/app_shutdown_coordinator.dart';
import 'app_startup_coordinator.dart';
import 'app_startup_models.dart';

typedef AppStartupDirectoryResolver = Future<Directory> Function();
typedef AppStartupNativePtyLoader = Future<PtySessionBackend> Function();

AppStartupCoordinator createProductionAppStartupCoordinator({
  TargetPlatform? platform,
  AppStartupDirectoryResolver appSupportDirectoryResolver =
      getApplicationSupportDirectory,
  AppStartupDirectoryResolver appDocumentsDirectoryResolver =
      getApplicationDocumentsDirectory,
  AppStartupNativePtyLoader? nativePtyLoader,
  AppStartupConfigurationAccessFactory? configurationAccessFactory,
  AppStartupSecureRecovery? secureRecovery,
}) {
  final targetPlatform = platform ?? defaultTargetPlatform;
  final loadNativePty =
      nativePtyLoader ??
      () => Future<NativePtyBackend>.sync(
        () => NativePtyBackend.load(emitRuntimeEventGapDiagnostics: true),
      );
  return AppStartupCoordinator(
    pipeline: AppStartupPipeline(
      resolvePaths: () async {
        return AppStartupPaths(
          appSupportDirectory: await appSupportDirectoryResolver(),
        );
      },
      createConfigurationAccess:
          configurationAccessFactory ??
          (paths) async {
            final fileRepository = FileDataApiConfigurationRepository(
              appSupportDirectory: paths.appSupportDirectory,
            );
            final remoteSessionStore = FlutterSecureDataApiRemoteSessionStore();
            final repository = AuthenticatedDataApiConfigurationRepository(
              delegate: fileRepository,
              remoteSessionStore: remoteSessionStore,
            );
            return AppStartupConfigurationAccess(
              repository: repository,
              remoteSessionStore: repository,
              settings: _ProductionDataSettingsCapability(
                repository: repository,
                localDataApiAvailable: targetPlatform == TargetPlatform.macOS,
              ),
            );
          },
      loadConfiguration: _loadConfigurationSnapshot,
      validateConfiguration: _validateConfigurationSnapshot,
      recoverSecureConfiguration:
          secureRecovery ?? _recoverProductionSecureConfiguration,
      bootstrapData: (paths, access, configurationSnapshot) {
        return _bootstrapRuntime(
          paths: paths,
          access: access,
          configuration: configurationSnapshot.configuration,
          isMacOS: targetPlatform == TargetPlatform.macOS,
        );
      },
      prepareMigration: (paths, access, configurationSnapshot, runtime) async {
        await prepareDataApiPersistence(
          runtime: runtime,
          appSupportDirectory: paths.appSupportDirectory,
        );
      },
      preparePlatform: (paths) async {
        if (targetPlatform != TargetPlatform.iOS) {
          return const AppStartupPlatformPreparation(
            usesIosSandboxShell: false,
          );
        }
        final documents = await appDocumentsDirectoryResolver();
        return AppStartupPlatformPreparation(
          usesIosSandboxShell: true,
          iosSandboxRoot: Directory(
            '${documents.path}${Platform.pathSeparator}IanvsShell',
          ),
        );
      },
      loadPty: (platform) async {
        final nativeBackend = await loadNativePty();
        if (!platform.usesIosSandboxShell) {
          return nativeBackend;
        }
        final sandboxRoot = platform.iosSandboxRoot;
        if (sandboxRoot == null) {
          throw StateError('iOS sandbox startup did not provide its root.');
        }
        return IosSandboxShellBackend(
          rootDirectory: sandboxRoot,
          terminalBackend: nativeBackend,
        );
      },
      composeGraph:
          ({
            required generation,
            required paths,
            required configurationAccess,
            required configurationSnapshot,
            required dataApiRuntime,
            required dataApiStartupWarning,
            required ptySessionBackend,
          }) async {
            final persistence = PersistenceRepositoryComposition.forRuntime(
              dataApiRuntime,
              profileExportDirectoryResolver: () async =>
                  paths.appSupportDirectory,
              dataApiPersistenceRequired:
                  configurationSnapshot.configuration.deployment !=
                  DataApiDeployment.disabled,
            );
            return AppRuntimeGraph(
              generation: generation,
              paths: paths,
              dataApiConfiguration: configurationSnapshot.configuration,
              dataApiConfigurationRepository: configurationAccess.repository,
              dataApiRuntime: dataApiRuntime,
              dataApiStartupWarning: dataApiStartupWarning,
              ptySessionBackend: ptySessionBackend,
              persistenceRepositories: persistence,
              recordingRepository: LocalSessionRecordingRepository(
                directoryResolver: () async => paths.appSupportDirectory,
              ),
              shutdownCoordinator: AppShutdownCoordinator(),
            );
          },
      migrationRecoveries:
          ({
            required error,
            required paths,
            required configurationAccess,
            required configurationSnapshot,
          }) => buildProductionMigrationRecoveryCapabilities(
            error: error,
            paths: paths,
          ),
    ),
  );
}

Future<DataApiStartupWarning?> _recoverProductionSecureConfiguration(
  AppStartupConfigurationAccess access,
) async {
  final repository =
      access.repository as AuthenticatedDataApiConfigurationRepository;
  await repository.recoverForStartup();
  try {
    await repository.retryPendingRevocations();
    return null;
  } on DataApiRemoteRevocationPendingWarning catch (warning) {
    return DataApiStartupWarning(warning.toString());
  }
}

Future<AppStartupConfigurationSnapshot> _loadConfigurationSnapshot(
  AppStartupConfigurationAccess access,
) async {
  final configuration = await loadDataApiConfigurationForStartup(
    access.repository,
  );
  return AppStartupConfigurationSnapshot(
    configuration: configuration,
    generation: configuration.generation,
    digest: await _configurationDigest(configuration),
  );
}

Future<void> _validateConfigurationSnapshot(
  AppStartupConfigurationAccess access,
  AppStartupConfigurationSnapshot expected,
) async {
  final actual = await _loadConfigurationSnapshot(access);
  if (expected.generation != actual.generation ||
      expected.digest != actual.digest) {
    throw AppStartupConfigurationSnapshotConflictException(
      expectedGeneration: expected.generation,
      actualGeneration: actual.generation,
      expectedDigest: expected.digest,
      actualDigest: actual.digest,
    );
  }
}

Future<String> _configurationDigest(DataApiConfiguration configuration) async {
  final sink = Sha256().toSync().newHashSink();
  sink.add(utf8.encode(jsonEncode(configuration.toJson())));
  sink.close();
  final hash = await sink.hash();
  return hash.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

List<AppStartupMigrationRecoveryOperation>
buildProductionMigrationRecoveryCapabilities({
  required Object error,
  required AppStartupPaths paths,
}) {
  final cause = error is DataApiPersistencePreparationException
      ? error.cause
      : error;
  return switch (cause) {
    final DataApiLegacyJsonMigrationConflictException conflict =>
      <AppStartupMigrationRecoveryOperation>[
        AppStartupMigrationRecoveryOperation(
          kind: AppStartupMigrationRecoveryKind.keepRemote,
          run: (runtime) => acknowledgeDataApiMigrationKeepRemote(
            runtime: runtime,
            appSupportDirectory: paths.appSupportDirectory,
            conflict: conflict,
          ),
        ),
      ],
    final DataApiLegacyJsonMigrationJournalRecoveryRequiredException recovery =>
      <AppStartupMigrationRecoveryOperation>[
        AppStartupMigrationRecoveryOperation(
          kind: AppStartupMigrationRecoveryKind.resetJournal,
          run: (runtime) async {
            final identity = await DataApiInstallationIdentityRepository(
              appSupportDirectory: paths.appSupportDirectory,
            ).loadOrCreate();
            final migration = DataApiLegacyJsonMigration(
              appSupportDirectory: paths.appSupportDirectory,
              client: DataApiClient.fromRuntime(runtime),
              installationIdentity: identity,
            );
            await migration.acknowledgeResetRevisionJournal(recovery);
            await migration.run();
          },
        ),
      ],
    _ => const <AppStartupMigrationRecoveryOperation>[],
  };
}

Future<DataApiRuntime?> _bootstrapRuntime({
  required AppStartupPaths paths,
  required AppStartupConfigurationAccess access,
  required DataApiConfiguration configuration,
  required bool isMacOS,
}) {
  return DataApiBootstrap(
    configurationRepository: access.repository,
    remoteSessionStore: access.remoteSessionStore,
    isMacOS: isMacOS,
  ).start(
    appSupportDirectory: paths.appSupportDirectory,
    configuration: configuration,
  );
}

final class _ProductionDataSettingsCapability
    implements AppStartupDataSettingsCapability {
  const _ProductionDataSettingsCapability({
    required AuthenticatedDataApiConfigurationRepository repository,
    required this.localDataApiAvailable,
  }) : _repository = repository;

  final AuthenticatedDataApiConfigurationRepository _repository;

  @override
  final bool localDataApiAvailable;

  @override
  Future<DataApiConfiguration> loadForRecovery() {
    return _repository.loadForRecovery();
  }

  @override
  Future<void> reconnect(DataApiRemoteLoginRequest request) {
    return _acceptSavedConfigurationWarning(
      () => _repository.connectAndSaveRemote(request),
    );
  }

  @override
  Future<void> saveDisabled() {
    return _acceptSavedConfigurationWarning(
      () => _repository.save(const DataApiConfiguration.disabled()),
    );
  }

  Future<void> _acceptSavedConfigurationWarning(
    Future<void> Function() operation,
  ) async {
    try {
      await operation();
    } on DataApiRemoteRevocationPendingWarning {
      // The selected configuration is already authoritative. Full startup
      // retries the bounded cleanup stage and surfaces any remaining warning.
    } on DataApiSecureSessionMutationException catch (warning) {
      if (!warning.configurationSaved) {
        rethrow;
      }
    } on DataApiConfigurationRecoverySentinelException catch (warning) {
      if (!warning.configurationSaved) {
        rethrow;
      }
    }
  }
}
