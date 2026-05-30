import '../preferences/app_preferences_models.dart';
import 'local_terminal_config_models.dart';

class LocalTerminalConfigPreferencesAdapter {
  const LocalTerminalConfigPreferencesAdapter._();

  static TerminalAppPreferencesDocument toAppPreferences(
    LocalTerminalConfigDocument config,
  ) {
    return TerminalAppPreferencesDocument(
      defaults: TerminalAppDefaults(defaultProfileId: config.defaultProfileId),
      appearance: config.appearance,
      notifications: TerminalAppNotifications(
        commandFinished: config.notifications.enabled,
        bell: config.notifications.enabled,
        activity: config.notifications.enabled,
      ),
    );
  }
}
