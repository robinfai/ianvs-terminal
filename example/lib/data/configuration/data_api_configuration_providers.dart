import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data_api_configuration_repository.dart';

/// Composition-root seam for the persistent Data API configuration.
///
/// The application overrides this provider with the same repository used by
/// bootstrap, so settings and startup always read a single source of truth.
final dataApiConfigurationRepositoryProvider =
    Provider<DataApiConfigurationRepository?>((ref) => null);
