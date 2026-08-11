import '../preferences/app_preferences_repository.dart';
import 'local_terminal_config_bootstrap.dart';
import 'local_terminal_config_repository.dart';

class LocalTerminalConfigLoader {
  const LocalTerminalConfigLoader({
    required this.localConfigRepository,
    required this.legacyPreferencesRepository,
  });

  final TerminalConfigRepository localConfigRepository;
  final AppPreferencesRepositoryPort legacyPreferencesRepository;

  Future<LocalTerminalConfigBootstrapResult> load() async {
    final localConfig = await localConfigRepository.loadVersioned();
    if (localConfig.value != null) {
      return LocalTerminalConfigBootstrap.resolve(
        localConfig: localConfig.value,
        legacyAppPreferences: null,
        localConfigRevision: localConfig.revision,
      );
    }
    final legacyPreferences = await legacyPreferencesRepository.loadVersioned();
    return LocalTerminalConfigBootstrap.resolve(
      localConfig: null,
      legacyAppPreferences: legacyPreferences.value,
      localConfigRevision: localConfig.revision,
      legacyPreferencesRevision: legacyPreferences.revision,
    );
  }
}
