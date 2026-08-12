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
        profiles: LocalTerminalOnlyProfileRepository(
          delegate: ProfileRepository(
            directoryResolver: profileExportDirectoryResolver,
          ),
        ),
        preferences: AppPreferencesRepository(
          directoryResolver: profileExportDirectoryResolver,
        ),
        terminalConfig: LocalTerminalConfigRepository(
          directoryResolver: profileExportDirectoryResolver,
        ),
        terminalLayout: LocalTerminalLayoutRepository(
          directoryResolver: profileExportDirectoryResolver,
        ),
        pasteHistory: PasteHistoryRepository(
          directoryResolver: profileExportDirectoryResolver,
        ),
        usesDataApi: false,
        persistenceUnavailable: false,
      );
    }
    final client = DataApiClient.fromRuntime(runtime);
    final profiles = DataApiProfileRepository(
      client: client,
      exportDirectoryResolver: profileExportDirectoryResolver,
    );
    return PersistenceRepositoryComposition._(
      profiles: profiles,
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
    DataApiMigrationConflictPolicy conflictPolicy =
        DataApiMigrationConflictPolicy.preserveDestination,
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
