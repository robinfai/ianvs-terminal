import '../preferences/app_preferences_repository.dart';
import 'local_terminal_config_bootstrap.dart';
import 'local_terminal_config_repository.dart';

class LocalTerminalConfigLoader {
  const LocalTerminalConfigLoader({
    required this.localConfigRepository,
    required this.legacyPreferencesRepository,
  });

  final LocalTerminalConfigRepository localConfigRepository;
  final AppPreferencesRepository legacyPreferencesRepository;

  Future<LocalTerminalConfigBootstrapResult> load() async {
    final localConfig = await localConfigRepository.load();
    final legacyPreferences = await legacyPreferencesRepository.load();
    return LocalTerminalConfigBootstrap.resolve(
      localConfig: localConfig,
      legacyAppPreferences: legacyPreferences,
    );
  }
}
