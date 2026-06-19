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

  static const runtimeDefaultCommandCenter = LocalTerminalCommandCenterConfig(
    enabled: true,
    historySearch: true,
    commandBlocks: true,
    commandBar: true,
    contextChips: true,
    reviewEntrypoints: true,
    verificationDiagnostics: true,
  );

  static const runtimeDefaultCommandBlocksHistory =
      LocalTerminalCommandBlocksHistoryConfig(
        enabled: true,
        commandBlocks: true,
        failureSnapshots: true,
        reviewWorkspaceEntrypoints: true,
        outputDiff: true,
      );

  static const runtimeDefaults = LocalTerminalConfigDocument(
    commandCenter: runtimeDefaultCommandCenter,
    commandBlocksHistory: runtimeDefaultCommandBlocksHistory,
  );

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
        config: _withRuntimeDefaults(
          LocalTerminalConfigMigration.fromLegacyAppPreferences(
            legacyAppPreferences,
          ),
        ),
        source: LocalTerminalConfigBootstrapSource.legacyAppPreferences,
      );
    }

    return const LocalTerminalConfigBootstrapResult(
      config: runtimeDefaults,
      source: LocalTerminalConfigBootstrapSource.defaults,
    );
  }

  static LocalTerminalConfigDocument _withRuntimeDefaults(
    LocalTerminalConfigDocument config,
  ) {
    return config.copyWith(
      commandCenter: runtimeDefaultCommandCenter,
      commandBlocksHistory: runtimeDefaultCommandBlocksHistory,
    );
  }
}
