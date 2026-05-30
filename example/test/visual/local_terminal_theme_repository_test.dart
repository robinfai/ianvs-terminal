import 'dart:convert';
import 'dart:io';

import 'package:app/features/visual/local_terminal_theme_repository.dart';
import 'package:app/features/visual/local_terminal_visual_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local terminal theme repository', () {
    test('returns empty presets when themes file is absent', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-themes-missing',
      );
      final repository = LocalTerminalThemeRepository(
        directoryResolver: () async => directory,
      );

      expect(await repository.load(), isEmpty);
    });

    test('persists theme presets', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-themes-roundtrip',
      );
      final repository = LocalTerminalThemeRepository(
        directoryResolver: () async => directory,
      );

      await repository.save([_preset()]);
      final loaded = await repository.load();

      expect(loaded, hasLength(1));
      expect(loaded.single.id, 'baseline');
      expect(loaded.single.dark.background, 0x000000);
    });

    test('exports a single preset document', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-theme-export',
      );
      final repository = LocalTerminalThemeRepository(
        directoryResolver: () async => directory,
      );

      final file = await repository.exportPreset(_preset());

      expect(file.path, contains('baseline.ianvs-terminal-theme.json'));
      expect(await file.readAsString(), contains('"baseline"'));
    });

    test('quarantines corrupt theme list', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-themes-corrupt',
      );
      final file = File('${directory.path}/ianvs_themes.json');
      await file.writeAsString('{bad json');
      final repository = LocalTerminalThemeRepository(
        directoryResolver: () async => directory,
      );

      final loaded = await repository.load();

      expect(loaded, isEmpty);
      expect(
        directory.listSync().any(
          (entry) => entry.path.contains('ianvs_themes.json.corrupt'),
        ),
        isTrue,
      );
    });

    test('skips malformed theme entries without quarantine', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-themes-invalid-entries',
      );
      final file = File('${directory.path}/ianvs_themes.json');
      await file.writeAsString(
        jsonEncode([
          'not a preset',
          {
            'id': 'custom',
            'name': 'Custom',
            'dark': {'background': 'black', 'foreground': 0xeeeeee},
            'light': {'background': 0xffffff, 'foreground': false},
          },
        ]),
      );
      final repository = LocalTerminalThemeRepository(
        directoryResolver: () async => directory,
      );

      final loaded = await repository.load();

      expect(loaded, hasLength(1));
      expect(loaded.single.id, 'custom');
      expect(loaded.single.dark.background, 0x000000);
      expect(loaded.single.dark.foreground, 0xeeeeee);
      expect(loaded.single.light.background, 0xffffff);
      expect(loaded.single.light.foreground, 0xffffff);
      expect(
        directory.listSync().any(
          (entry) => entry.path.contains('ianvs_themes.json.corrupt'),
        ),
        isFalse,
      );
    });
  });
}

LocalTerminalThemePreset _preset() {
  return const LocalTerminalThemePreset(
    id: 'baseline',
    name: 'Baseline',
    dark: LocalTerminalColorScheme(
      background: 0x000000,
      foreground: 0xffffff,
      cursor: 0xffffff,
      selection: 0x333333,
      splitDivider: 0x222222,
      inactivePaneOverlay: 0x11000000,
    ),
    light: LocalTerminalColorScheme(
      background: 0xffffff,
      foreground: 0x000000,
      cursor: 0x000000,
      selection: 0xdddddd,
      splitDivider: 0xcccccc,
      inactivePaneOverlay: 0x11000000,
    ),
  );
}
