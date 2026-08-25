import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/data_api_remote_fallback.dart';
import '../services/data_api_runtime.dart';
import '../services/portable_master_key.dart';
import 'data_api_configuration.dart';
import 'data_api_configuration_repository.dart';

typedef DataApiLocalMigrationRuntimeStarter = Future<DataApiRuntime> Function();

/// Persistent API-backed configuration is available in bundled-local and
/// authenticated remote modes.
final dataApiPersistenceEnabledProvider = Provider<bool>(
  (ref) => ref.watch(dataApiRuntimeProvider)?.canAccessResources == true,
);

/// Cross-device synchronization exists only for an authenticated remote URL.
final crossDeviceConfigurationSyncEnabledProvider = Provider<bool>((ref) {
  final runtime = ref.watch(dataApiRuntimeProvider);
  return runtime?.deployment == DataApiDeployment.remote &&
      runtime?.canAccessResources == true;
});

/// Composition-root seam for the persistent Data API configuration.
///
/// The application overrides this provider with the same repository used by
/// bootstrap, so settings and startup always read a single source of truth.
final dataApiConfigurationRepositoryProvider =
    Provider<DataApiConfigurationRepository?>((ref) => null);

/// The one user-owned key repository shared by all encryption consumers.
final portableMasterKeyRepositoryProvider =
    Provider<PortableMasterKeyRepository?>((ref) => null);

/// Starts a temporary bundled local API while the active graph is remote.
/// The migration caller owns and closes the returned runtime after the copy.
final dataApiLocalMigrationRuntimeStarterProvider =
    Provider<DataApiLocalMigrationRuntimeStarter?>((ref) => null);

/// Durable checkpoint for the last remote resource set mirrored into the
/// bundled local API. Production supplies a file-backed implementation.
final dataApiRemoteFallbackSnapshotStoreProvider =
    Provider<DataApiRemoteFallbackSnapshotStore?>((ref) => null);

/// Coordinates background remote mirroring and explicit offline fallback.
final dataApiRemoteFallbackControllerProvider =
    Provider<DataApiRemoteFallbackController?>((ref) {
      final runtime = ref.watch(dataApiRuntimeProvider);
      final startLocalRuntime = ref.watch(
        dataApiLocalMigrationRuntimeStarterProvider,
      );
      final configurationRepository = ref.watch(
        dataApiConfigurationRepositoryProvider,
      );
      final snapshotStore = ref.watch(
        dataApiRemoteFallbackSnapshotStoreProvider,
      );
      if (runtime == null ||
          runtime.deployment != DataApiDeployment.remote ||
          !runtime.canAccessResources ||
          startLocalRuntime == null ||
          configurationRepository == null ||
          snapshotStore == null) {
        return null;
      }
      return DataApiRemoteFallbackController(
        remoteRuntime: runtime,
        startLocalRuntime: startLocalRuntime,
        configurationRepository: configurationRepository,
        snapshotStore: snapshotStore,
      );
    });

/// Startup may have failed before a repository could expose its own recovery
/// flag (for example, an application-support I/O error). Propagating this
/// composition-root fact keeps the explicit Disabled/save escape path enabled
/// without treating the unread configuration as Disabled implicitly.
final dataApiConfigurationRecoveryRequiredProvider = Provider<bool>(
  (ref) => false,
);
