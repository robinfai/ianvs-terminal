import 'dart:io';

import 'data/repositories/data_api_installation_identity_repository.dart';
import 'data/repositories/data_api_legacy_json_migration.dart';
import 'data/services/data_api_client.dart';
import 'data/services/data_api_runtime.dart';
import 'features/config/data_api_terminal_config_repository.dart';
import 'features/config/local_terminal_config_repository.dart';
import 'features/layout/data_api_terminal_layout_repository.dart';
import 'features/layout/local_terminal_layout_repository.dart';
import 'features/preferences/app_preferences_repository.dart';
import 'features/preferences/data_api_app_preferences_repository.dart';
import 'features/profiles/data_api_profile_repository.dart';
import 'features/profiles/profile_repository.dart';
import 'features/shell/data_api_paste_history_repository.dart';
import 'features/shell/paste_history_repository.dart';

/// The only production decision point between historical JSON persistence and
/// the Data API. A configured runtime always selects API adapters; missing
/// remote credentials fail closed in [DataApiClient] and never fall back.
final class PersistenceRepositoryComposition {
  const PersistenceRepositoryComposition._({
    required this.profiles,
    required this.preferences,
    required this.terminalConfig,
    required this.terminalLayout,
    required this.pasteHistory,
    required this.usesDataApi,
    required this.persistenceUnavailable,
  });

  factory PersistenceRepositoryComposition.forRuntime(
    DataApiRuntime? runtime, {
    required DirectoryResolver profileExportDirectoryResolver,
    bool dataApiPersistenceRequired = false,
    bool dataApiPersistenceUnavailable = false,
  }) {
    if (dataApiPersistenceUnavailable || runtime == null) {
      if (dataApiPersistenceUnavailable || dataApiPersistenceRequired) {
        const client = _UnavailableDataApiResourceClient();
        return PersistenceRepositoryComposition._(
          profiles: DataApiProfileRepository(
            client: client,
            exportDirectoryResolver: profileExportDirectoryResolver,
          ),
          preferences: DataApiAppPreferencesRepository(client: client),
          terminalConfig: DataApiTerminalConfigRepository(client: client),
          terminalLayout: DataApiTerminalLayoutRepository(client: client),
          pasteHistory: DataApiPasteHistoryRepository(client: client),
          usesDataApi: true,
          persistenceUnavailable: true,
        );
      }
      return PersistenceRepositoryComposition._(
        profiles: ProfileRepository(
          directoryResolver: profileExportDirectoryResolver,
        ),
        preferences: AppPreferencesRepository(),
        terminalConfig: LocalTerminalConfigRepository(),
        terminalLayout: LocalTerminalLayoutRepository(),
        pasteHistory: PasteHistoryRepository(),
        usesDataApi: false,
        persistenceUnavailable: false,
      );
    }
    final client = DataApiClient.fromRuntime(runtime);
    return PersistenceRepositoryComposition._(
      profiles: DataApiProfileRepository(
        client: client,
        exportDirectoryResolver: profileExportDirectoryResolver,
      ),
      preferences: DataApiAppPreferencesRepository(client: client),
      terminalConfig: DataApiTerminalConfigRepository(client: client),
      terminalLayout: DataApiTerminalLayoutRepository(client: client),
      pasteHistory: DataApiPasteHistoryRepository(client: client),
      usesDataApi: true,
      persistenceUnavailable: false,
    );
  }

  final ProfileRepositoryPort profiles;
  final AppPreferencesRepositoryPort preferences;
  final TerminalConfigRepository terminalConfig;
  final TerminalLayoutRepository terminalLayout;
  final PasteHistoryRepositoryPort pasteHistory;
  final bool usesDataApi;
  final bool persistenceUnavailable;
}

final class DataApiPersistenceUnavailableException implements Exception {
  const DataApiPersistenceUnavailableException();

  @override
  String toString() {
    return 'The configured Data API is unavailable. Reconnect or disable the '
        'data service in settings; local persistence was not used as a fallback.';
  }
}

final class _UnavailableDataApiResourceClient implements DataApiResourceClient {
  const _UnavailableDataApiResourceClient();

  @override
  bool get canAccessResources => false;

  Never _unavailable() {
    throw const DataApiPersistenceUnavailableException();
  }

  @override
  Future<bool> deleteResource({
    required String kind,
    required String id,
    int? expectedRevision,
  }) async => _unavailable();

  @override
  Future<DataApiResource?> getResource({
    required String kind,
    required String id,
    bool includeSensitive = false,
  }) async => _unavailable();

  @override
  Future<DataApiResourcePage> listResourcePage({
    String? kind,
    bool includeSensitive = false,
    int limit = DataApiClient.maximumPageSize,
    String? cursor,
  }) async => _unavailable();

  @override
  Future<DataApiMigrationMergeReport> mergeResources({
    required String sourceId,
    required List<DataApiMigrationResource> resources,
  }) async => _unavailable();

  @override
  Future<DataApiResource> putResource({
    required String kind,
    required String id,
    required Object? data,
    Object? sensitive,
    bool clearSensitive = false,
    int? expectedRevision,
  }) async => _unavailable();
}

Future<DataApiLegacyJsonMigrationReport?> prepareDataApiPersistence({
  required DataApiRuntime? runtime,
  required Directory appSupportDirectory,
  DataApiResourceClient? resourceClient,
  DataApiInstallationIdentity? installationIdentity,
}) async {
  if (runtime == null) {
    return null;
  }
  final client = resourceClient ?? DataApiClient.fromRuntime(runtime);
  if (!client.canAccessResources) {
    throw const DataApiAuthenticationRequiredException();
  }
  try {
    final identity =
        installationIdentity ??
        await DataApiInstallationIdentityRepository(
          appSupportDirectory: appSupportDirectory,
        ).loadOrCreate();
    return await DataApiLegacyJsonMigration(
      appSupportDirectory: appSupportDirectory,
      client: client,
      installationIdentity: identity,
    ).run();
  } on DataApiLegacyJsonMigrationConflictException {
    rethrow;
  } on Object catch (error, stackTrace) {
    Error.throwWithStackTrace(
      DataApiPersistencePreparationException(error),
      stackTrace,
    );
  }
}

Future<void> acknowledgeDataApiMigrationKeepRemote({
  required DataApiRuntime runtime,
  required Directory appSupportDirectory,
  required DataApiLegacyJsonMigrationConflictException conflict,
  DataApiResourceClient? resourceClient,
  DataApiInstallationIdentity? installationIdentity,
}) async {
  final client = resourceClient ?? DataApiClient.fromRuntime(runtime);
  if (!client.canAccessResources) {
    throw const DataApiAuthenticationRequiredException();
  }
  final identity =
      installationIdentity ??
      await DataApiInstallationIdentityRepository(
        appSupportDirectory: appSupportDirectory,
      ).loadOrCreate();
  await DataApiLegacyJsonMigration(
    appSupportDirectory: appSupportDirectory,
    client: client,
    installationIdentity: identity,
  ).acknowledgeKeepRemote(conflict);
}

final class DataApiPersistencePreparationException implements Exception {
  const DataApiPersistencePreparationException(this.cause);

  final Object cause;

  @override
  String toString() {
    return 'Local Data API migration did not complete: $cause. Remote data '
        'was not overwritten; restart the app to retry.';
  }
}
