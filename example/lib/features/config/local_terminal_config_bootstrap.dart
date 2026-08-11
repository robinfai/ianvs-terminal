import '../preferences/app_preferences_models.dart';
import 'local_terminal_config_models.dart';
import 'local_terminal_config_repository.dart';

class LocalTerminalConfigBootstrapResult {
  const LocalTerminalConfigBootstrapResult({
    required this.config,
    required this.source,
    this.localConfigRevision,
    this.legacyPreferencesRevision,
  });

  final LocalTerminalConfigDocument config;
  final LocalTerminalConfigBootstrapSource source;
  final int? localConfigRevision;
  final int? legacyPreferencesRevision;
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
    int? localConfigRevision,
    int? legacyPreferencesRevision,
  }) {
    if (localConfig != null) {
      return LocalTerminalConfigBootstrapResult(
        config: localConfig,
        source: LocalTerminalConfigBootstrapSource.localConfig,
        localConfigRevision: localConfigRevision,
      );
    }

    if (legacyAppPreferences != null) {
      return LocalTerminalConfigBootstrapResult(
        config: LocalTerminalConfigMigration.fromLegacyAppPreferences(
          legacyAppPreferences,
        ),
        source: LocalTerminalConfigBootstrapSource.legacyAppPreferences,
        legacyPreferencesRevision: legacyPreferencesRevision,
      );
    }

    return LocalTerminalConfigBootstrapResult(
      config: const LocalTerminalConfigDocument(
        layout: LocalTerminalLayoutConfig(restoreLayout: true),
      ),
      source: LocalTerminalConfigBootstrapSource.defaults,
      localConfigRevision: localConfigRevision,
      legacyPreferencesRevision: legacyPreferencesRevision,
    );
  }
}
