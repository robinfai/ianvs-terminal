import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart' as terminal;

enum TerminalThemePreset {
  dark,
  graphite,
  light;

  String get label => switch (this) {
    TerminalThemePreset.dark => 'Dark',
    TerminalThemePreset.graphite => 'Graphite',
    TerminalThemePreset.light => 'Light',
  };

  terminal.TerminalViewportColors get viewportColors => switch (this) {
    TerminalThemePreset.dark => terminal.TerminalViewportColors.dark,
    TerminalThemePreset.graphite => const terminal.TerminalViewportColors(
      canvasBackground: Color(0xFF101418),
      foreground: Color(0xFFE5E7EB),
      cursor: Color(0xFFA7F3D0),
      selection: Color(0x66475569),
      scrollbarTrack: Color(0x26334155),
      scrollbarThumb: Color(0x998494A6),
    ),
    TerminalThemePreset.light => terminal.TerminalViewportColors.light,
  };

  terminal.TerminalColorPalette get colorPalette {
    final colors = viewportColors;
    return terminal.TerminalColorPalette(
      foreground: terminal.terminalViewportHexFromColor(colors.foreground),
      background: terminal.terminalViewportHexFromColor(
        colors.canvasBackground,
      ),
      cursor: terminal.terminalViewportHexFromColor(colors.cursor),
      selection: terminal.terminalViewportHexFromColor(colors.selection),
    );
  }

  static TerminalThemePreset fromJson(Object? value) {
    if (value is String) {
      for (final preset in TerminalThemePreset.values) {
        if (preset.name == value.toLowerCase() || preset.label == value) {
          return preset;
        }
      }
    }
    return TerminalThemePreset.dark;
  }
}

class TerminalSettings {
  const TerminalSettings({
    required this.fontFamily,
    required this.fontSize,
    required this.themePreset,
    required this.defaultShell,
  });

  factory TerminalSettings.defaults({String? defaultShell}) {
    return TerminalSettings(
      fontFamily: '',
      fontSize: 14,
      themePreset: TerminalThemePreset.dark,
      defaultShell: _effectiveShell(defaultShell),
    );
  }

  factory TerminalSettings.fromJson(Object? json, {String? defaultShell}) {
    final map = _objectMap(json);
    if (map == null) {
      return TerminalSettings.defaults(defaultShell: defaultShell);
    }
    final shell = _stringOrNull(map['defaultShell']) ?? defaultShell;
    return TerminalSettings(
      fontFamily: _stringOrNull(map['fontFamily']) ?? '',
      fontSize: _fontSizeFromJson(map['fontSize']),
      themePreset: TerminalThemePreset.fromJson(map['themePreset']),
      defaultShell: _effectiveShell(shell),
    );
  }

  final String fontFamily;
  final double fontSize;
  final TerminalThemePreset themePreset;
  final String defaultShell;

  terminal.TerminalFontConfig get fontConfig {
    final trimmedFamily = fontFamily.trim();
    return terminal.TerminalFontConfig(
      family: trimmedFamily.isEmpty
          ? terminal.terminalPrimaryFontFamily
          : trimmedFamily,
      size: fontSize,
      lineHeight: terminal.terminalLineHeight,
    );
  }

  terminal.TerminalDisplayConfig get displayConfig {
    return terminal.TerminalDisplayConfig(
      font: fontConfig,
      colors: themePreset.colorPalette,
    );
  }

  terminal.TerminalSessionConfig toSessionConfig() {
    return terminal.TerminalSessionConfig(
      launch: terminal.TerminalLaunchConfig(
        program: defaultShell,
        cwd: Platform.environment['HOME'],
        env: const <String, String>{'TERM': 'xterm-256color'},
      ),
      display: displayConfig,
    );
  }

  TerminalSettings copyWith({
    String? fontFamily,
    double? fontSize,
    TerminalThemePreset? themePreset,
    String? defaultShell,
  }) {
    return TerminalSettings(
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: _clampFontSize(fontSize ?? this.fontSize),
      themePreset: themePreset ?? this.themePreset,
      defaultShell: _effectiveShell(defaultShell ?? this.defaultShell),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'fontFamily': fontFamily,
      'fontSize': fontSize,
      'themePreset': themePreset.name,
      'defaultShell': defaultShell,
    };
  }
}

class TerminalSettingsStore {
  TerminalSettingsStore({File? file, String? defaultShell})
    : file = file ?? defaultSettingsFile(),
      defaultShell = _effectiveShell(defaultShell);

  final File file;
  final String defaultShell;

  static File defaultSettingsFile() {
    final home = Platform.environment['HOME'] ?? Directory.current.path;
    return File(
      '$home/Library/Application Support/Ianvs/ianvs-terminal/settings.json',
    );
  }

  TerminalSettings load() {
    if (!file.existsSync()) {
      return TerminalSettings.defaults(defaultShell: defaultShell);
    }
    try {
      return TerminalSettings.fromJson(
        jsonDecode(file.readAsStringSync()),
        defaultShell: defaultShell,
      );
    } catch (_) {
      return TerminalSettings.defaults(defaultShell: defaultShell);
    }
  }

  void save(TerminalSettings settings) {
    file.parent.createSync(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    file.writeAsStringSync('${encoder.convert(settings.toJson())}\n');
  }
}

class TerminalSettingsController extends ChangeNotifier {
  TerminalSettingsController({required this.store}) : _settings = store.load();

  final TerminalSettingsStore store;
  TerminalSettings _settings;

  TerminalSettings get settings => _settings;

  void updateFontFamily(String value) {
    _save(_settings.copyWith(fontFamily: value.trim()));
  }

  void updateFontSize(double value) {
    _save(_settings.copyWith(fontSize: value));
  }

  void updateThemePreset(TerminalThemePreset value) {
    _save(_settings.copyWith(themePreset: value));
  }

  bool updateDefaultShell(String value) {
    final shell = value.trim();
    if (shell.isEmpty) {
      return false;
    }
    _save(_settings.copyWith(defaultShell: shell));
    return true;
  }

  void _save(TerminalSettings next) {
    if (_sameSettings(_settings, next)) {
      return;
    }
    _settings = next;
    store.save(next);
    notifyListeners();
  }
}

bool _sameSettings(TerminalSettings left, TerminalSettings right) {
  return left.fontFamily == right.fontFamily &&
      left.fontSize == right.fontSize &&
      left.themePreset == right.themePreset &&
      left.defaultShell == right.defaultShell;
}

Map<String, Object?>? _objectMap(Object? value) {
  if (value is Map) {
    return value.map(
      (key, entry) => MapEntry(key.toString(), entry as Object?),
    );
  }
  return null;
}

String? _stringOrNull(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

String _effectiveShell(String? shell) {
  final candidate = shell?.trim();
  if (candidate != null && candidate.isNotEmpty) {
    return candidate;
  }
  final userShell = Platform.environment['SHELL']?.trim();
  if (userShell != null && userShell.isNotEmpty) {
    return userShell;
  }
  return '/bin/zsh';
}

double _fontSizeFromJson(Object? value) {
  if (value is num) {
    return _clampFontSize(value.toDouble());
  }
  return 14;
}

double _clampFontSize(double value) => value.clamp(10, 28).toDouble();
