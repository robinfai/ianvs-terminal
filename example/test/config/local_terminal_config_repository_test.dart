import 'dart:convert';
import 'dart:io';

import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/local_terminal_config_repository.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local terminal config repository', () {
    test('returns null when config file is absent', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-config-missing',
      );
      final repository = LocalTerminalConfigRepository(
        directoryResolver: () async => directory,
      );

      expect(await repository.load(), isNull);
    });

    test('persists local config to disk', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-config-roundtrip',
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

    test('keeps config values when only schema version is invalid', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-config-invalid-schema',
      );
      final file = File('${directory.path}/ianvs_config.json');
      await file.writeAsString(
        jsonEncode({
          'schemaVersion': 'latest',
          'defaultProfileId': 'local-dev',
          'appearance': {'themeMode': 'dark'},
        }),
      );
      final repository = LocalTerminalConfigRepository(
        directoryResolver: () async => directory,
      );

      final loaded = await repository.load();

      expect(loaded, isNotNull);
      expect(
        loaded!.schemaVersion,
        LocalTerminalConfigDocument.currentSchemaVersion,
      );
      expect(loaded.defaultProfileId, 'local-dev');
      expect(loaded.appearance.themeMode, TerminalThemeMode.dark);
      expect(
        directory.listSync().any(
          (entry) => entry.path.contains('ianvs_config.json.corrupt'),
        ),
        isFalse,
      );
    });

    test(
      'defaults invalid primitive config fields without quarantine',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-config-invalid-primitives',
        );
        final file = File('${directory.path}/ianvs_config.json');
        await file.writeAsString(
          jsonEncode({
            'schemaVersion': 1,
            'defaultProfileId': 42,
            'keybindings': {
              'overrides': {
                'newTab': {
                  'enabled': 'yes',
                  'binding': {
                    'scope': 'global',
                    'key': 7,
                    'meta': 'true',
                    'control': true,
                    'shift': 1,
                    'alt': false,
                  },
                },
              },
            },
            'workspace': {'restoreLayout': 'yes'},
            'clipboard': {'copyOnSelect': 'no', 'osc52': 'allow'},
            'paste': {
              'bracketedPaste': 'force',
              'confirmLargePaste': 'yes',
              'confirmMultilinePaste': false,
              'historySize': 'many',
            },
            'shellIntegration': {'enabled': 'true'},
            'notifications': {'enabled': false},
            'hotkeyWindow': {'enabled': 'false'},
          }),
        );
        final repository = LocalTerminalConfigRepository(
          directoryResolver: () async => directory,
        );

        final loaded = await repository.load();

        expect(loaded, isNotNull);
        expect(loaded!.defaultProfileId, isNull);
        expect(
          loaded.keybindings.overrides[TerminalActionId.newTab]?.enabled,
          isTrue,
        );
        final binding =
            loaded.keybindings.overrides[TerminalActionId.newTab]?.binding;
        expect(binding?.scope, TerminalKeyBindingScope.global);
        expect(binding?.key, '');
        expect(binding?.meta, isFalse);
        expect(binding?.control, isTrue);
        expect(binding?.shift, isFalse);
        expect(binding?.alt, isFalse);
        expect(loaded.workspace.restoreLayout, isFalse);
        expect(loaded.clipboard.copyOnSelect, isFalse);
        expect(loaded.clipboard.osc52, LocalTerminalOsc52Policy.allow);
        expect(
          loaded.paste.bracketedPaste,
          LocalTerminalBracketedPastePolicy.force,
        );
        expect(loaded.paste.confirmLargePaste, isTrue);
        expect(loaded.paste.confirmMultilinePaste, isFalse);
        expect(loaded.paste.historySize, 50);
        expect(loaded.shellIntegration.enabled, isTrue);
        expect(loaded.notifications.enabled, isFalse);
        expect(loaded.hotkeyWindow.enabled, isFalse);
        expect(
          directory.listSync().any(
            (entry) => entry.path.contains('ianvs_config.json.corrupt'),
          ),
          isFalse,
        );
      },
    );

    test('quarantines corrupt config and writes repaired defaults', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-config-corrupt',
      );
      final file = File('${directory.path}/ianvs_config.json');
      await file.writeAsString('{bad json');
      final repository = LocalTerminalConfigRepository(
        directoryResolver: () async => directory,
      );

      final loaded = await repository.load();

      expect(loaded, isNotNull);
      expect(loaded!.defaultProfileId, isNull);
      expect(
        directory.listSync().any(
          (entry) => entry.path.contains('ianvs_config.json.corrupt'),
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
