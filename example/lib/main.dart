import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'app_bootstrap.dart';
import 'data/configuration/data_api_configuration.dart';
import 'data/configuration/data_api_configuration_repository.dart';
import 'data/repositories/data_api_installation_identity_repository.dart';
import 'data/repositories/data_api_legacy_json_migration.dart';
import 'data/services/data_api_bootstrap.dart';
import 'data/services/data_api_client.dart';
import 'data/services/data_api_remote_session_store.dart';
import 'data/services/data_api_runtime.dart';
import 'data/services/data_api_startup_recovery.dart';
import 'features/pty/pty.dart';
import 'persistence_repository_composition.dart';

bool usesIosSandboxShell(TargetPlatform platform) {
  return platform == TargetPlatform.iOS;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appSupportDirectory = await getApplicationSupportDirectory();
  final fileDataApiConfigurationRepository = FileDataApiConfigurationRepository(
    appSupportDirectory: appSupportDirectory,
  );
  final remoteSessionStore = FlutterSecureDataApiRemoteSessionStore();
  final dataApiConfigurationRepository =
      AuthenticatedDataApiConfigurationRepository(
        delegate: fileDataApiConfigurationRepository,
        remoteSessionStore: remoteSessionStore,
      );
  DataApiStartupWarning? dataApiStartupWarning;
  late DataApiConfiguration dataApiConfiguration;
  var dataApiConfigurationRecoveryRequired = false;
  try {
    dataApiConfiguration = await loadDataApiConfigurationForStartup(
      dataApiConfigurationRepository,
    );
  } on DataApiConfigurationRecoveryRequiredException catch (error, stackTrace) {
    dataApiConfiguration = const DataApiConfiguration.disabled();
    dataApiConfigurationRecoveryRequired = true;
    dataApiStartupWarning = DataApiStartupWarning(error.toString());
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'data API configuration',
      ),
    );
  } on DataApiStartupDependencyException catch (error, stackTrace) {
    dataApiConfiguration = const DataApiConfiguration.disabled();
    dataApiConfigurationRecoveryRequired = true;
    dataApiStartupWarning = DataApiStartupWarning(error.toString());
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'data API configuration',
      ),
    );
  }
  DataApiRuntime? dataApiRuntime;
  DataApiLegacyJsonMigrationConflictException? dataApiMigrationConflict;
  DataApiLegacyJsonMigrationJournalRecoveryRequiredException?
  dataApiMigrationJournalRecovery;
  var dataApiPersistenceUnavailable =
      dataApiConfigurationRecoveryRequired ||
      dataApiConfiguration.deployment != DataApiDeployment.disabled;
  if (!dataApiConfigurationRecoveryRequired) {
    try {
      await dataApiConfigurationRepository.recoverForStartup();
      try {
        await dataApiConfigurationRepository.retryPendingRevocations();
      } on DataApiRemoteRevocationPendingWarning catch (warning) {
        dataApiStartupWarning = DataApiStartupWarning(warning.toString());
      }
      dataApiRuntime = await DataApiBootstrap(
        configurationRepository: dataApiConfigurationRepository,
        remoteSessionStore: dataApiConfigurationRepository,
      ).start(appSupportDirectory: appSupportDirectory);
    } on Object catch (error, stackTrace) {
      dataApiStartupWarning = DataApiStartupWarning(error.toString());
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'data API bootstrap',
        ),
      );
    }
    try {
      await prepareDataApiPersistence(
        runtime: dataApiRuntime,
        appSupportDirectory: appSupportDirectory,
      );
      if (dataApiRuntime != null) {
        dataApiPersistenceUnavailable = false;
      }
    } on Object catch (error, stackTrace) {
      if (error is DataApiLegacyJsonMigrationConflictException) {
        dataApiMigrationConflict = error;
      }
      final migrationCause = error is DataApiPersistencePreparationException
          ? error.cause
          : error;
      if (migrationCause
          is DataApiLegacyJsonMigrationJournalRecoveryRequiredException) {
        dataApiMigrationJournalRecovery = migrationCause;
      }
      dataApiStartupWarning = DataApiStartupWarning(error.toString());
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'data API persistence',
        ),
      );
    }
  }
  final useSandboxShell = usesIosSandboxShell(defaultTargetPlatform);
  IosSandboxShellBackend? sandboxBackend;
  if (useSandboxShell) {
    final documents = await getApplicationDocumentsDirectory();
    sandboxBackend = IosSandboxShellBackend(
      rootDirectory: Directory('${documents.path}/IanvsShell'),
      terminalBackend: NativePtyBackend.load(
        emitRuntimeEventGapDiagnostics: true,
      ),
    );
  }
  final freshRuntimeRunner = DataApiFreshRuntimeRunner(
    initialRuntime: dataApiRuntime,
    bootstrap: () => DataApiBootstrap(
      configurationRepository: dataApiConfigurationRepository,
      remoteSessionStore: dataApiConfigurationRepository,
    ).start(appSupportDirectory: appSupportDirectory),
  );

  Future<DataApiStartupRetryResult> retryDataApiStartup() async {
    try {
      if (dataApiConfigurationRepository.recoveryRequired) {
        throw const DataApiConfigurationRecoveryRequiredException();
      }
      return await freshRuntimeRunner.run((retryRuntime) async {
        if (retryRuntime == null) {
          return const DataApiStartupRetryResult(
            succeeded: true,
            message:
                'The data service is disabled. Restart the app to unlock local persistence.',
          );
        }
        await prepareDataApiPersistence(
          runtime: retryRuntime,
          appSupportDirectory: appSupportDirectory,
        );
        return const DataApiStartupRetryResult(
          succeeded: true,
          message:
              'Data service preparation completed. Restart the app to unlock persistence.',
        );
      });
    } on Object catch (error) {
      return DataApiStartupRetryResult(
        succeeded: false,
        message: 'Data service preparation is still blocked: $error',
      );
    }
  }

  Future<DataApiStartupRetryResult> keepRemoteDataAfterConflict() async {
    final conflict = dataApiMigrationConflict;
    if (conflict == null) {
      return const DataApiStartupRetryResult(
        succeeded: false,
        message: 'No migration conflict is available to acknowledge.',
      );
    }
    try {
      return await freshRuntimeRunner.run((runtime) async {
        if (runtime == null) {
          throw StateError('The data service is disabled. Restart the app.');
        }
        await acknowledgeDataApiMigrationKeepRemote(
          runtime: runtime,
          appSupportDirectory: appSupportDirectory,
          conflict: conflict,
        );
        return const DataApiStartupRetryResult(
          succeeded: true,
          message:
              'Remote data was kept and local JSON was left unchanged. Restart the app to unlock persistence.',
        );
      });
    } on Object catch (error) {
      return DataApiStartupRetryResult(
        succeeded: false,
        message: 'The migration decision could not be saved: $error',
      );
    }
  }

  var migrationJournalResetAcknowledged = false;
  Future<DataApiStartupRetryResult> resetMigrationJournalAndRetry() async {
    final recovery = dataApiMigrationJournalRecovery;
    if (recovery == null) {
      return const DataApiStartupRetryResult(
        succeeded: false,
        message: 'No corrupt migration journal is available to reset.',
      );
    }
    try {
      return await freshRuntimeRunner.run((runtime) async {
        if (runtime == null) {
          throw StateError('The data service is disabled. Restart the app.');
        }
        final identity = await DataApiInstallationIdentityRepository(
          appSupportDirectory: appSupportDirectory,
        ).loadOrCreate();
        final migration = DataApiLegacyJsonMigration(
          appSupportDirectory: appSupportDirectory,
          client: DataApiClient.fromRuntime(runtime),
          installationIdentity: identity,
        );
        if (!migrationJournalResetAcknowledged) {
          await migration.acknowledgeResetRevisionJournal(recovery);
          migrationJournalResetAcknowledged = true;
        }
        await migration.run();
        return const DataApiStartupRetryResult(
          succeeded: true,
          message:
              'The migration journal was reset and local migration completed. Restart the app to unlock persistence.',
        );
      });
    } on Object catch (error) {
      return DataApiStartupRetryResult(
        succeeded: false,
        message:
            'The journal reset or migration retry did not complete; persistence remains locked: $error',
      );
    }
  }

  runIanvsTerminalApp(
    enableSessionPolling: true,
    enableReferenceDemoMode: false,
    ptySessionBackend: sandboxBackend,
    dataApiRuntime: dataApiRuntime,
    dataApiPersistenceRequired:
        dataApiConfigurationRecoveryRequired ||
        dataApiConfiguration.deployment != DataApiDeployment.disabled,
    dataApiPersistenceUnavailable: dataApiPersistenceUnavailable,
    dataApiStartupWarning: dataApiStartupWarning,
    dataApiStartupRetry:
        !dataApiConfigurationRecoveryRequired &&
            dataApiConfiguration.deployment == DataApiDeployment.disabled
        ? null
        : retryDataApiStartup,
    dataApiMigrationKeepRemote: dataApiMigrationConflict == null
        ? null
        : keepRemoteDataAfterConflict,
    dataApiMigrationResetJournal: dataApiMigrationJournalRecovery == null
        ? null
        : resetMigrationJournalAndRetry,
    dataApiConfigurationRepository: dataApiConfigurationRepository,
    dataApiConfigurationRecoveryRequired: dataApiConfigurationRecoveryRequired,
    profileExportDirectoryResolver: () async => appSupportDirectory,
  );
}
