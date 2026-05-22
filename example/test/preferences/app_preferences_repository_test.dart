import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/preferences/app_preferences_repository.dart';

void main() {
  test(
    'app preferences repository returns null when preferences file is absent',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'flutterm-preferences-missing',
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
      'flutterm-preferences-roundtrip',
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
        'flutterm-preferences-defaults',
      );
      final repository = AppPreferencesRepository(
        directoryResolver: () async => directory,
      );
      final file = File('${directory.path}/flutterm_preferences.json');

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

  test(
    'app preferences repository quarantines corrupt files and repairs defaults',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'flutterm-preferences-corrupt',
      );
      final repository = AppPreferencesRepository(
        directoryResolver: () async => directory,
      );
      final file = File('${directory.path}/flutterm_preferences.json');

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
              (entry) =>
                  entry.path.contains('flutterm_preferences.json.corrupt'),
            )
            .length,
        1,
      );
    },
  );
}
