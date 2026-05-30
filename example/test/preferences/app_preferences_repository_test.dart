import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/preferences/app_preferences_repository.dart';

void main() {
  test(
    'app preferences repository returns null when preferences file is absent',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-preferences-missing',
      );
      final repository = AppPreferencesRepository(
        directoryResolver: () async => directory,
      );

      final loaded = await repository.load();

      expect(loaded, isNull);
    },
  );

  test('app preferences repository persists app defaults to disk', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ianvs terminal-preferences-roundtrip',
    );
    final repository = AppPreferencesRepository(
      directoryResolver: () async => directory,
    );

    const document = TerminalAppPreferencesDocument(
      defaults: TerminalAppDefaults(defaultProfileId: 'ssh'),
      appearance: TerminalAppAppearance(
        themeMode: TerminalThemeMode.dark,
        terminalViewportPadding: 14,
      ),
    );

    await repository.save(document);
    final loaded = await repository.load();

    expect(loaded, isNotNull);
    expect(
      loaded!.schemaVersion,
      TerminalAppPreferencesDocument.currentSchemaVersion,
    );
    expect(loaded.defaults.defaultProfileId, 'ssh');
    expect(loaded.appearance.themeMode, TerminalThemeMode.dark);
    expect(loaded.appearance.terminalViewportPadding, 14);
  });

  test(
    'app preferences repository fills missing fields with schema defaults',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-preferences-defaults',
      );
      final repository = AppPreferencesRepository(
        directoryResolver: () async => directory,
      );
      final file = File('${directory.path}/ianvs_preferences.json');

      await file.writeAsString('{"schemaVersion":1}');

      final loaded = await repository.load();

      expect(loaded, isNotNull);
      expect(loaded!.defaults.defaultProfileId, isNull);
      expect(loaded.appearance.themeMode, TerminalThemeMode.system);
      expect(
        loaded.appearance.terminalViewportPadding,
        TerminalAppAppearance.defaultTerminalViewportPadding,
      );
    },
  );

  test('app preferences defaults trim profile ids and reject blanks', () {
    final trimmed = TerminalAppPreferencesDocument.fromJson(const {
      'defaults': {'defaultProfileId': ' ssh '},
    });
    final blank = TerminalAppPreferencesDocument.fromJson(const {
      'defaults': {'defaultProfileId': '   '},
    });

    expect(trimmed.defaults.defaultProfileId, 'ssh');
    expect(blank.defaults.defaultProfileId, isNull);
  });

  test(
    'app preferences repository keeps values when only schema version is invalid',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-preferences-invalid-schema',
      );
      final repository = AppPreferencesRepository(
        directoryResolver: () async => directory,
      );
      final file = File('${directory.path}/ianvs_preferences.json');

      await file.writeAsString(
        jsonEncode({
          'schemaVersion': 'latest',
          'defaults': {'defaultProfileId': 'ssh'},
          'appearance': {'themeMode': 'dark', 'terminalViewportPadding': 16},
        }),
      );

      final loaded = await repository.load();

      expect(loaded, isNotNull);
      expect(
        loaded!.schemaVersion,
        TerminalAppPreferencesDocument.currentSchemaVersion,
      );
      expect(loaded.defaults.defaultProfileId, 'ssh');
      expect(loaded.appearance.themeMode, TerminalThemeMode.dark);
      expect(loaded.appearance.terminalViewportPadding, 16);
      expect(
        directory
            .listSync()
            .whereType<File>()
            .where(
              (entry) => entry.path.contains('ianvs_preferences.json.corrupt'),
            )
            .length,
        0,
      );
    },
  );

  test(
    'app preferences repository keeps values when schema version is non-finite',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-preferences-non-finite-schema',
      );
      final repository = AppPreferencesRepository(
        directoryResolver: () async => directory,
      );
      final file = File('${directory.path}/ianvs_preferences.json');

      await file.writeAsString('''
{
  "schemaVersion": 1e999,
  "defaults": {"defaultProfileId": "ssh"},
  "appearance": {"themeMode": "dark", "terminalViewportPadding": 16}
}
''');

      final loaded = await repository.load();

      expect(loaded, isNotNull);
      expect(
        loaded!.schemaVersion,
        TerminalAppPreferencesDocument.currentSchemaVersion,
      );
      expect(loaded.defaults.defaultProfileId, 'ssh');
      expect(loaded.appearance.themeMode, TerminalThemeMode.dark);
      expect(loaded.appearance.terminalViewportPadding, 16);
      expect(
        directory
            .listSync()
            .whereType<File>()
            .where(
              (entry) => entry.path.contains('ianvs_preferences.json.corrupt'),
            )
            .length,
        0,
      );
    },
  );

  test(
    'app preferences repository keeps values when schema version is non-positive',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-preferences-non-positive-schema',
      );
      final repository = AppPreferencesRepository(
        directoryResolver: () async => directory,
      );
      final file = File('${directory.path}/ianvs_preferences.json');

      await file.writeAsString(
        jsonEncode({
          'schemaVersion': -2,
          'defaults': {'defaultProfileId': 'ssh'},
          'appearance': {'themeMode': 'dark', 'terminalViewportPadding': 16},
        }),
      );

      final loaded = await repository.load();

      expect(loaded, isNotNull);
      expect(
        loaded!.schemaVersion,
        TerminalAppPreferencesDocument.currentSchemaVersion,
      );
      expect(loaded.defaults.defaultProfileId, 'ssh');
      expect(loaded.appearance.themeMode, TerminalThemeMode.dark);
      expect(loaded.appearance.terminalViewportPadding, 16);
      expect(
        directory
            .listSync()
            .whereType<File>()
            .where(
              (entry) => entry.path.contains('ianvs_preferences.json.corrupt'),
            )
            .length,
        0,
      );
    },
  );

  test(
    'app preferences repository defaults invalid sections without quarantine',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-preferences-invalid-sections',
      );
      final repository = AppPreferencesRepository(
        directoryResolver: () async => directory,
      );
      final file = File('${directory.path}/ianvs_preferences.json');

      await file.writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'defaults': {'defaultProfileId': 42},
          'appearance': 'dark',
          'notifications': {
            'commandFinished': 'yes',
            'bell': false,
            'activity': 1,
          },
        }),
      );

      final loaded = await repository.load();

      expect(loaded, isNotNull);
      expect(loaded!.defaults.defaultProfileId, isNull);
      expect(loaded.appearance.themeMode, TerminalThemeMode.system);
      expect(
        loaded.appearance.terminalViewportPadding,
        TerminalAppAppearance.defaultTerminalViewportPadding,
      );
      expect(loaded.notifications.commandFinished, isTrue);
      expect(loaded.notifications.bell, isFalse);
      expect(loaded.notifications.activity, isTrue);
      expect(
        directory
            .listSync()
            .whereType<File>()
            .where(
              (entry) => entry.path.contains('ianvs_preferences.json.corrupt'),
            )
            .length,
        0,
      );
    },
  );

  test(
    'app preferences repository quarantines corrupt files and repairs defaults',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-preferences-corrupt',
      );
      final repository = AppPreferencesRepository(
        directoryResolver: () async => directory,
      );
      final file = File('${directory.path}/ianvs_preferences.json');

      await file.writeAsString('{not-json');

      final loaded = await repository.load();

      expect(loaded, isNotNull);
      expect(loaded!.defaults.defaultProfileId, isNull);
      expect(loaded.appearance.themeMode, TerminalThemeMode.system);
      expect(
        loaded.appearance.terminalViewportPadding,
        TerminalAppAppearance.defaultTerminalViewportPadding,
      );
      expect(await file.exists(), isTrue);
      expect(
        directory
            .listSync()
            .whereType<File>()
            .where(
              (entry) => entry.path.contains('ianvs_preferences.json.corrupt'),
            )
            .length,
        1,
      );
    },
  );

  test(
    'app preferences repository defaults non-finite viewport padding',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-preferences-non-finite-padding',
      );
      final repository = AppPreferencesRepository(
        directoryResolver: () async => directory,
      );
      final file = File('${directory.path}/ianvs_preferences.json');

      await file.writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'appearance': {'themeMode': 'dark', 'terminalViewportPadding': 'NaN'},
        }),
      );

      final loaded = await repository.load();

      expect(loaded, isNotNull);
      expect(loaded!.appearance.themeMode, TerminalThemeMode.dark);
      expect(
        loaded.appearance.terminalViewportPadding,
        TerminalAppAppearance.defaultTerminalViewportPadding,
      );
      expect(
        directory
            .listSync()
            .whereType<File>()
            .where(
              (entry) => entry.path.contains('ianvs_preferences.json.corrupt'),
            )
            .length,
        0,
      );
    },
  );
}
