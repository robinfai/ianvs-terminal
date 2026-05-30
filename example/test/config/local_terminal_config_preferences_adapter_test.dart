import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/local_terminal_config_preferences_adapter.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local terminal config preferences adapter', () {
    test('maps local config defaults and appearance to app preferences', () {
      const config = LocalTerminalConfigDocument(
        defaultProfileId: 'local',
        appearance: TerminalAppAppearance(
          themeMode: TerminalThemeMode.dark,
          terminalViewportPadding: 18,
        ),
        notifications: LocalTerminalNotificationsConfig(
          enabled: true,
          commandFinished: false,
          bell: true,
          activity: false,
        ),
      );

      final preferences =
          LocalTerminalConfigPreferencesAdapter.toAppPreferences(config);

      expect(preferences.defaults.defaultProfileId, 'local');
      expect(preferences.appearance.themeMode, TerminalThemeMode.dark);
      expect(preferences.appearance.terminalViewportPadding, 18);
      expect(preferences.notifications.commandFinished, isFalse);
      expect(preferences.notifications.bell, isTrue);
      expect(preferences.notifications.activity, isFalse);
    });
  });
}
