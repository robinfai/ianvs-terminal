import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/configuration/data_api_configuration_providers.dart';

/// Whether a persistent Data API (bundled local or remote) is available.
///
/// OpenSSH config discovery is intentionally independent from this capability:
/// local-only macOS sessions may still connect to hosts declared in
/// `~/.ssh/config`. This gate covers only user-managed SSH profile documents.
final customSshProfileConfigurationEnabledProvider = Provider<bool>(
  (ref) => ref.watch(dataApiPersistenceEnabledProvider),
);

final class CustomSshProfileConfigurationUnavailableException
    implements Exception {
  const CustomSshProfileConfigurationUnavailableException();

  @override
  String toString() {
    return 'Custom SSH profiles require the bundled local API or a configured '
        'remote HTTP API.';
  }
}
