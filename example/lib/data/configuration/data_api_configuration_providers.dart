import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/data_api_runtime.dart';
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

/// Starts a temporary bundled local API while the active graph is remote.
/// The migration caller owns and closes the returned runtime after the copy.
final dataApiLocalMigrationRuntimeStarterProvider =
    Provider<DataApiLocalMigrationRuntimeStarter?>((ref) => null);

/// Startup may have failed before a repository could expose its own recovery
/// flag (for example, an application-support I/O error). Propagating this
/// composition-root fact keeps the explicit Disabled/save escape path enabled
/// without treating the unread configuration as Disabled implicitly.
final dataApiConfigurationRecoveryRequiredProvider = Provider<bool>(
  (ref) => false,
);
