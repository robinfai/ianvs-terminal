import 'data/services/data_api_client.dart';
import 'data/services/data_api_runtime.dart';
import 'data/services/portable_master_key.dart';
import 'data/sync/local_first_sync.dart';
import 'data/sync/sync_repositories.dart';
import 'features/config/local_terminal_config_repository.dart';
import 'features/layout/local_terminal_layout_repository.dart';
import 'features/preferences/app_preferences_repository.dart';
import 'features/profiles/profile_repository.dart';
import 'features/profiles/profile_secret_cipher.dart';
import 'features/shell/paste_history_repository.dart';

/// Every mode uses the same encrypted local profile store. An API is an
/// optional synchronization destination; a transport failure never swaps or
/// locks the application's repository graph.
final class PersistenceRepositoryComposition {
  const PersistenceRepositoryComposition._({
    required this.profiles,
    required this.preferences,
    required this.terminalConfig,
    required this.terminalLayout,
    required this.pasteHistory,
    required this.sync,
    required this.configureSyncRuntime,
  });

  factory PersistenceRepositoryComposition.forRuntime(
    DataApiRuntime? runtime, {
    required DirectoryResolver profileExportDirectoryResolver,
    PortableMasterKeyRepository? masterKeyRepository,
    bool dataApiPersistenceRequired = false,
    bool dataApiPersistenceUnavailable = false,
  }) {
    const legacyProfileKeyStore = FlutterSecureProfileSecretKeyStore();
    ProfileSecretCipher localCipher() => ProfileSecretCipher(
      keyStore: PortableMasterProfileSecretKeyStore(
        masterKeyRepository: masterKeyRepository,
        legacyStore: legacyProfileKeyStore,
      ),
      legacyKeyStore: masterKeyRepository?.allowLegacyMigration == false
          ? null
          : legacyProfileKeyStore,
    );
    final localProfiles = ProfileRepository(
      directoryResolver: profileExportDirectoryResolver,
      secretCipher: localCipher(),
    );
    final bindings = SyncRepositoryBindings(
      profiles: localProfiles,
      preferences: AppPreferencesRepository(
        directoryResolver: profileExportDirectoryResolver,
      ),
      terminalConfig: LocalTerminalConfigRepository(
        directoryResolver: profileExportDirectoryResolver,
      ),
      pasteHistory: PasteHistoryRepository(
        directoryResolver: profileExportDirectoryResolver,
      ),
    );
    final enabled =
        runtime != null &&
        runtime.canAccessResources &&
        !dataApiPersistenceUnavailable;
    final sync = LocalFirstSyncCoordinator(
      documents: bindings.bindings,
      closeTransport: runtime?.close,
      enabledButUnavailable:
          !enabled &&
          (dataApiPersistenceRequired ||
              dataApiPersistenceUnavailable ||
              runtime != null),
      client: enabled
          ? DataApiClient(
              baseUri: runtime.baseUri,
              accessToken: runtime.resourceAccessToken,
              encryptionKey: runtime.encryptionKey,
              connectionTimeout: const Duration(seconds: 2),
              requestTimeout: const Duration(seconds: 4),
            )
          : null,
      checkpoints: enabled
          ? FileSyncCheckpointStore(
              directory: profileExportDirectoryResolver,
              destination: runtime.syncIdentity,
              cipher: localCipher(),
            )
          : null,
    );
    final repositories = bindings.wrap(sync);
    return PersistenceRepositoryComposition._(
      profiles: repositories.profiles,
      preferences: repositories.preferences,
      terminalConfig: repositories.terminalConfig,
      terminalLayout: LocalTerminalLayoutRepository(
        directoryResolver: profileExportDirectoryResolver,
      ),
      pasteHistory: repositories.pasteHistory,
      sync: sync,
      configureSyncRuntime: (nextRuntime) async {
        final active = nextRuntime != null && nextRuntime.canAccessResources;
        await sync.setTransport(
          nextClient: active
              ? DataApiClient(
                  baseUri: nextRuntime.baseUri,
                  accessToken: nextRuntime.resourceAccessToken,
                  encryptionKey: nextRuntime.encryptionKey,
                  connectionTimeout: const Duration(seconds: 2),
                  requestTimeout: const Duration(seconds: 4),
                )
              : null,
          nextCheckpoints: active
              ? FileSyncCheckpointStore(
                  directory: profileExportDirectoryResolver,
                  destination: nextRuntime.syncIdentity,
                  cipher: localCipher(),
                )
              : null,
          nextClose: nextRuntime?.close,
        );
      },
    );
  }

  final ProfileRepositoryPort profiles;
  final AppPreferencesRepositoryPort preferences;
  final TerminalConfigRepository terminalConfig;
  final TerminalLayoutRepository terminalLayout;
  final PasteHistoryRepositoryPort pasteHistory;
  final LocalFirstSyncCoordinator sync;
  bool get usesDataApi =>
      sync.client != null && sync.phase != LocalFirstSyncPhase.disabled;
  final Future<void> Function(DataApiRuntime?) configureSyncRuntime;
  bool get persistenceUnavailable => false;
}

/// Retained for callers decoding historical startup failures.
final class DataApiPersistenceUnavailableException implements Exception {
  const DataApiPersistenceUnavailableException();
  @override
  String toString() =>
      'API synchronization is unavailable; local data is still available.';
}
