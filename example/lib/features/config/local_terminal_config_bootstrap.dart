import '../preferences/app_preferences_models.dart';
import 'local_terminal_config_models.dart';
import 'local_terminal_config_repository.dart';

class LocalTerminalConfigBootstrapResult {
  const LocalTerminalConfigBootstrapResult({
    required this.config,
    required this.source,
  });

  final LocalTerminalConfigDocument config;
  final LocalTerminalConfigBootstrapSource source;
}

enum LocalTerminalConfigBootstrapSource {
  localConfig,
  legacyAppPreferences,
  defaults,
}

class LocalTerminalConfigBootstrap {
  const LocalTerminalConfigBootstrap._();

  static LocalTerminalConfigBootstrapResult resolve({
    required LocalTerminalConfigDocument? localConfig,
    required TerminalAppPreferencesDocument? legacyAppPreferences,
  }) {
    if (localConfig != null) {
      return LocalTerminalConfigBootstrapResult(
        config: localConfig,
        source: LocalTerminalConfigBootstrapSource.localConfig,
      );
    }

    if (legacyAppPreferences != null) {
      return LocalTerminalConfigBootstrapResult(
        config: LocalTerminalConfigMigration.withRuntimeDefaults(
          LocalTerminalConfigMigration.fromLegacyAppPreferences(
            legacyAppPreferences,
          ),
        ),
        source: LocalTerminalConfigBootstrapSource.legacyAppPreferences,
      );
    }

    return const LocalTerminalConfigBootstrapResult(
      config: LocalTerminalConfigMigration.runtimeDefaults,
      source: LocalTerminalConfigBootstrapSource.defaults,
    );
  }
}
