import 'dart:io';

import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/local_terminal_config_repository.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local terminal config repository', () {
    test('returns null when config file is absent', () async {
      final directory = await Directory.systemTemp.createTemp(
        'flutterm-config-missing',
      );
      final repository = LocalTerminalConfigRepository(
        directoryResolver: () async => directory,
      );

      expect(await repository.load(), isNull);
    });

    test('persists local config to disk', () async {
      final directory = await Directory.systemTemp.createTemp(
        'flutterm-config-roundtrip',
      );
      final repository = LocalTerminalConfigRepository(
        directoryResolver: () async => directory,
      );
      const document = LocalTerminalConfigDocument(
        defaultProfileId: 'local-dev',
        appearance: TerminalAppAppearance(themeMode: TerminalThemeMode.dark),
        hotkeyWindow: LocalTerminalHotkeyWindowConfig(enabled: true),
      );

      await repository.save(document);
      final loaded = await repository.load();

      expect(loaded, isNotNull);
      expect(loaded!.defaultProfileId, 'local-dev');
      expect(loaded.appearance.themeMode, TerminalThemeMode.dark);
      expect(loaded.hotkeyWindow.enabled, isTrue);
    });

    test('quarantines corrupt config and writes repaired defaults', () async {
      final directory = await Directory.systemTemp.createTemp(
        'flutterm-config-corrupt',
      );
      final file = File('${directory.path}/flutterm_config.json');
      await file.writeAsString('{bad json');
      final repository = LocalTerminalConfigRepository(
        directoryResolver: () async => directory,
      );

      final loaded = await repository.load();

      expect(loaded, isNotNull);
      expect(loaded!.defaultProfileId, isNull);
      expect(
        directory.listSync().any(
          (entry) => entry.path.contains('flutterm_config.json.corrupt'),
        ),
        isTrue,
      );
    });

    test('migrates legacy app preferences into local config defaults', () {
      const preferences = TerminalAppPreferencesDocument(
        defaults: TerminalAppDefaults(defaultProfileId: 'local-dev'),
        appearance: TerminalAppAppearance(themeMode: TerminalThemeMode.dark),
      );

      final migrated = LocalTerminalConfigMigration.fromLegacyAppPreferences(
        preferences,
      );

      expect(migrated.defaultProfileId, 'local-dev');
      expect(migrated.appearance.themeMode, TerminalThemeMode.dark);
      expect(migrated.keybindings.disabledDefaultActions, isEmpty);
    });
  });
}
