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

      await repository.save([_preset(), _preset(), _preset(id: '   ')]);
      final loaded = await repository.load();
      final raw =
          jsonDecode(
                await File(
                  '${directory.path}/ianvs_themes.json',
                ).readAsString(),
              )
              as List<dynamic>;

      expect(raw, hasLength(1));
      expect(loaded, hasLength(1));
      expect(loaded.single.id, 'baseline');
      expect(loaded.single.dark.background, 0x000000);
    });

    test('caps persisted theme presets', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-themes-capped',
      );
      final repository = LocalTerminalThemeRepository(
        directoryResolver: () async => directory,
      );

      await repository.save([
        for (
          var index = 0;
          index < maxLocalTerminalThemePresets + 2;
          index += 1
        )
          _preset(id: 'preset-$index'),
      ]);
      final loaded = await repository.load();
      final raw =
          jsonDecode(
                await File(
                  '${directory.path}/ianvs_themes.json',
                ).readAsString(),
              )
              as List<dynamic>;

      expect(raw, hasLength(maxLocalTerminalThemePresets));
      expect(loaded, hasLength(maxLocalTerminalThemePresets));
      expect(loaded.first.id, 'preset-0');
      expect(loaded.last.id, 'preset-${maxLocalTerminalThemePresets - 1}');
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

    test('exports a preset without overwriting an existing file', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-theme-export-collision',
      );
      final existing = File(
        '${directory.path}/baseline.ianvs-terminal-theme.json',
      );
      await existing.writeAsString('existing theme');
      final repository = LocalTerminalThemeRepository(
        directoryResolver: () async => directory,
      );

      final file = await repository.exportPreset(_preset());

      expect(file.path, isNot(existing.path));
      expect(file.path, contains('baseline.ianvs-terminal-theme-1.json'));
      expect(await existing.readAsString(), 'existing theme');
      expect(await file.readAsString(), contains('"baseline"'));
    });

    test('sanitizes exported preset id inside theme directory', () async {
      final root = await Directory.systemTemp.createTemp(
        'ianvs terminal-theme-export-safe-name',
      );
      final directory = Directory('${root.path}/themes');
      final repository = LocalTerminalThemeRepository(
        directoryResolver: () async => directory,
      );

      final file = await repository.exportPreset(
        _preset(id: '../escaped-theme'),
      );

      final directoryPath = await directory.resolveSymbolicLinks();
      final filePath = await file.resolveSymbolicLinks();
      expect(filePath, startsWith('$directoryPath${Platform.pathSeparator}'));
      expect(file.path, contains('..-escaped-theme.ianvs-terminal-theme.json'));
      expect(
        File(
          '${root.path}/escaped-theme.ianvs-terminal-theme.json',
        ).existsSync(),
        isFalse,
      );
    });

    test(
      'truncates long exported preset ids to a writable file name',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-theme-export-long-name',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = LocalTerminalThemeRepository(
          directoryResolver: () async => directory,
        );

        final file = await repository.exportPreset(
          _preset(id: 'theme-${List.filled(400, 'a').join()}'),
        );

        final filename = file.uri.pathSegments.last;
        expect(filename.length, lessThanOrEqualTo(146));
        expect(await file.exists(), isTrue);
        expect(await file.readAsString(), contains('"theme-'));
      },
    );

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
          {'id': '   ', 'name': 'Blank'},
          {'id': 'missing-name', 'name': '   '},
          {
            'id': ' custom ',
            'name': ' Custom ',
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
      expect(loaded.single.name, 'Custom');
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

    test('limits persisted theme preset scans without quarantine', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-themes-bounded-load',
      );
      final file = File('${directory.path}/ianvs_themes.json');
      await file.writeAsString(
        jsonEncode([
          for (
            var index = 0;
            index < maxLocalTerminalThemePresets * 4 + 1;
            index += 1
          )
            'not-a-preset-$index',
          _preset(id: 'too-late').toJson(),
        ]),
      );
      final repository = LocalTerminalThemeRepository(
        directoryResolver: () async => directory,
      );

      final loaded = await repository.load();

      expect(loaded, isEmpty);
      expect(
        directory.listSync().any(
          (entry) => entry.path.contains('ianvs_themes.json.corrupt'),
        ),
        isFalse,
      );
    });

    test('skips duplicate theme preset ids without quarantine', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-themes-duplicate-ids',
      );
      final file = File('${directory.path}/ianvs_themes.json');
      await file.writeAsString(
        jsonEncode([
          {
            'id': ' shared ',
            'name': 'First',
            'dark': {'background': 0x000000},
            'light': {'background': 0xffffff},
          },
          {
            'id': 'shared',
            'name': 'Second',
            'dark': {'background': 0x111111},
            'light': {'background': 0xeeeeee},
          },
          {
            'id': 'unique',
            'name': 'Unique',
            'dark': {'background': 0x222222},
            'light': {'background': 0xdddddd},
          },
        ]),
      );
      final repository = LocalTerminalThemeRepository(
        directoryResolver: () async => directory,
      );

      final loaded = await repository.load();

      expect(
        loaded.map((preset) => preset.name).toList(growable: false),
        const ['First', 'Unique'],
      );
      expect(
        directory.listSync().any(
          (entry) => entry.path.contains('ianvs_themes.json.corrupt'),
        ),
        isFalse,
      );
    });
  });
}

LocalTerminalThemePreset _preset({String id = 'baseline'}) {
  return LocalTerminalThemePreset(
    id: id,
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
