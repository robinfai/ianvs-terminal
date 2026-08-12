import 'dart:convert';
import 'dart:io';

import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/local_terminal_config_repository.dart';
import 'package:app/features/policies/local_terminal_policy_models.dart';
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
      final persisted =
          jsonDecode(
                await File(
                  '${directory.path}/ianvs_config.json',
                ).readAsString(),
              )
              as Map<String, Object?>;
      expect(
        persisted['schemaVersion'],
        LocalTerminalConfigDocument.currentSchemaVersion,
      );
      expect(persisted, contains('layout'));
      expect(persisted, isNot(contains('workspace')));
    });

    test('serializes concurrent partial document updates', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-config-concurrent-updates',
      );
      final repository = LocalTerminalConfigRepository(
        directoryResolver: () async => directory,
      );
      await repository.save(const LocalTerminalConfigDocument());

      await Future.wait(<Future<LocalTerminalConfigDocument>>[
        repository.update(
          (current) => current.copyWith(defaultProfileId: 'local-dev'),
        ),
        repository.update(
          (current) => current.copyWith(
            notifications: LocalTerminalNotificationsConfig(
              enabled: current.notifications.enabled,
              commandFinished: current.notifications.commandFinished,
              bell: false,
              activity: current.notifications.activity,
            ),
          ),
        ),
        repository.update(
          (current) => current.copyWith(
            layout: const LocalTerminalLayoutConfig(restoreLayout: false),
          ),
        ),
      ]);

      final loaded = await repository.load();
      expect(loaded, isNotNull);
      expect(loaded!.defaultProfileId, 'local-dev');
      expect(loaded.notifications.bell, isFalse);
      expect(loaded.layout.restoreLayout, isFalse);
    });

    test('repairs malformed current config with unknown fields', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-config-workspace-migration',
      );
      final file = File('${directory.path}/ianvs_config.json');
      await file.writeAsString(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'workspace': <String, Object?>{'restoreLayout': true},
        }),
      );
      final repository = LocalTerminalConfigRepository(
        directoryResolver: () async => directory,
      );

      final loaded = await repository.load();
      expect(loaded?.layout.restoreLayout, isFalse);
      expect(
        directory.listSync().any((entry) => entry.path.contains('.corrupt')),
        isTrue,
      );
    });

    test('rejects noncurrent config schema without mutation', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-config-invalid-schema',
      );
      final file = File('${directory.path}/ianvs_config.json');
      await file.writeAsString(
        jsonEncode({
          'schemaVersion': 2,
          'defaultProfileId': 'local-dev',
          'appearance': {'themeMode': 'dark'},
        }),
      );
      final repository = LocalTerminalConfigRepository(
        directoryResolver: () async => directory,
      );

      final original = await file.readAsString();
      await expectLater(
        repository.load(),
        throwsA(isA<UnsupportedLocalTerminalConfigSchemaVersion>()),
      );
      expect(await file.readAsString(), original);
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
            'layout': {'restoreLayout': 'yes'},
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
        expect(
          loaded.keybindings.overrides[TerminalActionId.newTab]?.binding,
          isNull,
        );
        expect(loaded.layout.restoreLayout, isFalse);
        expect(loaded.clipboard.copyOnSelect, isFalse);
        expect(loaded.clipboard.osc52, LocalTerminalOsc52Policy.allow);
        expect(
          loaded.paste.bracketedPaste,
          LocalTerminalBracketedPastePolicy.force,
        );
        expect(loaded.paste.confirmLargePaste, isTrue);
        expect(loaded.paste.confirmMultilinePaste, isFalse);
        expect(
          loaded.paste.historySize,
          defaultLocalTerminalPasteHistoryEntries,
        );
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

    test(
      'rejects non-finite schema without mutation',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-config-non-finite-integers',
        );
        final file = File('${directory.path}/ianvs_config.json');
        await file.writeAsString('''
{
  "schemaVersion": 1e999,
  "defaultProfileId": "local-dev",
  "paste": {"historySize": 1e999}
}
''');
        final repository = LocalTerminalConfigRepository(
          directoryResolver: () async => directory,
        );

        final original = await file.readAsString();
        await expectLater(
          repository.load(),
          throwsA(isA<UnsupportedLocalTerminalConfigSchemaVersion>()),
        );
        expect(await file.readAsString(), original);
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
  });
}
