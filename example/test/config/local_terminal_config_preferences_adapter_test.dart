import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/local_terminal_config_preferences_adapter.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local terminal config preferences adapter', () {
    test('maps local config defaults and appearance to app preferences', () {
      const config = LocalTerminalConfigDocument(
        defaultProfileId: 'local',
        appearance: TerminalAppAppearance(themeMode: TerminalThemeMode.dark),
      );

      final preferences =
          LocalTerminalConfigPreferencesAdapter.toAppPreferences(config);

      expect(preferences.defaults.defaultProfileId, 'local');
      expect(preferences.appearance.themeMode, TerminalThemeMode.dark);
    });
  });
}
