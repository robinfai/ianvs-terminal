import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/src/terminal_settings.dart';

void main() {
  late Directory tempDir;
  late File settingsFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ianvs_terminal_settings_');
    settingsFile = File('${tempDir.path}/settings.json');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('settings store returns defaults when file is missing', () {
    final store = TerminalSettingsStore(
      file: settingsFile,
      defaultShell: '/bin/zsh',
    );

    final settings = store.load();

    expect(settings.defaultShell, '/bin/zsh');
    expect(settings.fontFamily, '');
    expect(settings.fontSize, 14);
    expect(settings.themePreset, TerminalThemePreset.dark);
  });

  test('settings store saves and reloads local settings', () {
    final store = TerminalSettingsStore(
      file: settingsFile,
      defaultShell: '/bin/zsh',
    );
    const settings = TerminalSettings(
      fontFamily: 'JetBrains Mono',
      fontSize: 16,
      themePreset: TerminalThemePreset.graphite,
      defaultShell: '/bin/bash',
    );

    store.save(settings);
    final reloaded = store.load();

    expect(reloaded.fontFamily, 'JetBrains Mono');
    expect(reloaded.fontSize, 16);
    expect(reloaded.themePreset, TerminalThemePreset.graphite);
    expect(reloaded.defaultShell, '/bin/bash');
  });

  test('settings store falls back to defaults for malformed JSON', () {
    settingsFile.parent.createSync(recursive: true);
    settingsFile.writeAsStringSync('{ bad json');
    final store = TerminalSettingsStore(
      file: settingsFile,
      defaultShell: '/bin/zsh',
    );

    final settings = store.load();

    expect(settings.defaultShell, '/bin/zsh');
    expect(settings.fontSize, 14);
    expect(settings.themePreset, TerminalThemePreset.dark);
  });
}
