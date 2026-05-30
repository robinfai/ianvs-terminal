import 'terminal_defaults.dart';

enum TerminalEmulation { xterm256, vt220 }

enum TerminalCursorShape { block, underline, beam }

enum TerminalOptionDragMode {
  normalSelection,
  blockSelection;

  String get jsonValue => switch (this) {
    TerminalOptionDragMode.normalSelection => 'normal_selection',
    TerminalOptionDragMode.blockSelection => 'block_selection',
  };

  static TerminalOptionDragMode fromJsonValue(Object? value) {
    return switch (value) {
      'normal_selection' => TerminalOptionDragMode.normalSelection,
      _ => TerminalOptionDragMode.blockSelection,
    };
  }
}

class TerminalLaunchConfig {
  const TerminalLaunchConfig({
    required this.program,
    this.args = const <String>[],
    this.env = const <String, String>{},
    this.cwd,
  });

  final String program;
  final List<String> args;
  final Map<String, String> env;
  final String? cwd;

  TerminalLaunchConfig copyWith({
    String? program,
    List<String>? args,
    Map<String, String>? env,
    Object? cwd = _terminalConfigNoChange,
  }) {
    return TerminalLaunchConfig(
      program: program ?? this.program,
      args: args ?? this.args,
      env: env ?? this.env,
      cwd: identical(cwd, _terminalConfigNoChange) ? this.cwd : cwd as String?,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'program': program,
      'args': args,
      'env': env,
      'cwd': cwd,
    };
  }

  factory TerminalLaunchConfig.fromJson(Object? json) {
    final map = _asObjectMap(json);
    return TerminalLaunchConfig(
      program: _trimmedStringOrNull(map?['program']) ?? '',
      args: _stringList(map?['args']),
      env: _stringMap(map?['env']),
      cwd: _trimmedStringOrNull(map?['cwd']),
    );
  }
}

class TerminalShellIntegrationConfig {
  const TerminalShellIntegrationConfig({this.enabled = true});

  final bool enabled;

  TerminalShellIntegrationConfig copyWith({bool? enabled}) {
    return TerminalShellIntegrationConfig(enabled: enabled ?? this.enabled);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{'enabled': enabled};
  }

  factory TerminalShellIntegrationConfig.fromJson(Object? json) {
    final map = _asObjectMap(json);
    return TerminalShellIntegrationConfig(
      enabled: _boolOr(map?['enabled'], true),
    );
  }
}

class TerminalFontConfig {
  const TerminalFontConfig({
    this.family = terminalPrimaryFontFamily,
    this.fallback = terminalFontFamilyFallback,
    this.size = terminalFontSize,
    this.lineHeight = terminalLineHeight,
  });

  final String family;
  final List<String> fallback;
  final double size;
  final double lineHeight;

  TerminalFontConfig copyWith({
    String? family,
    List<String>? fallback,
    double? size,
    double? lineHeight,
  }) {
    return TerminalFontConfig(
      family: family ?? this.family,
      fallback: fallback ?? this.fallback,
      size: size ?? this.size,
      lineHeight: lineHeight ?? this.lineHeight,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'family': family,
      'fallback': fallback,
      'size': size,
      'lineHeight': lineHeight,
    };
  }

  factory TerminalFontConfig.fromJson(Object? json) {
    final map = _asObjectMap(json);
    return TerminalFontConfig(
      family: _trimmedStringOrNull(map?['family']) ?? terminalPrimaryFontFamily,
      fallback: _trimmedStringList(
        map?['fallback'],
        fallback: terminalFontFamilyFallback,
      ),
      size: _positiveFiniteDoubleOr(map?['size'], terminalFontSize),
      lineHeight: _positiveFiniteDoubleOr(
        map?['lineHeight'],
        terminalLineHeight,
      ),
    );
  }
}

class TerminalSpecialColors {
  const TerminalSpecialColors({
    this.foreground,
    this.background,
    this.cursor,
    this.selection,
  });

  final String? foreground;
  final String? background;
  final String? cursor;
  final String? selection;

  TerminalSpecialColors copyWith({
    Object? foreground = _terminalConfigNoChange,
    Object? background = _terminalConfigNoChange,
    Object? cursor = _terminalConfigNoChange,
    Object? selection = _terminalConfigNoChange,
  }) {
    return TerminalSpecialColors(
      foreground: identical(foreground, _terminalConfigNoChange)
          ? this.foreground
          : foreground as String?,
      background: identical(background, _terminalConfigNoChange)
          ? this.background
          : background as String?,
      cursor: identical(cursor, _terminalConfigNoChange)
          ? this.cursor
          : cursor as String?,
      selection: identical(selection, _terminalConfigNoChange)
          ? this.selection
          : selection as String?,
    );
  }

  TerminalSpecialColors resolveWith(TerminalSpecialColors defaults) {
    return TerminalSpecialColors(
      foreground: foreground ?? defaults.foreground,
      background: background ?? defaults.background,
      cursor: cursor ?? defaults.cursor,
      selection: selection ?? defaults.selection,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'foreground': foreground,
      'background': background,
      'cursor': cursor,
      'selection': selection,
    };
  }

  factory TerminalSpecialColors.fromJson(Object? json) {
    final map = _asObjectMap(json);
    return TerminalSpecialColors(
      foreground: _hexColorOrNull(map?['foreground']),
      background: _hexColorOrNull(map?['background']),
      cursor: _hexColorOrNull(map?['cursor']),
      selection: _hexColorOrNull(map?['selection']),
    );
  }
}

class TerminalAnsiColors {
  const TerminalAnsiColors({
    this.black,
    this.red,
    this.green,
    this.yellow,
    this.blue,
    this.magenta,
    this.cyan,
    this.white,
  });

  final String? black;
  final String? red;
  final String? green;
  final String? yellow;
  final String? blue;
  final String? magenta;
  final String? cyan;
  final String? white;

  TerminalAnsiColors copyWith({
    Object? black = _terminalConfigNoChange,
    Object? red = _terminalConfigNoChange,
    Object? green = _terminalConfigNoChange,
    Object? yellow = _terminalConfigNoChange,
    Object? blue = _terminalConfigNoChange,
    Object? magenta = _terminalConfigNoChange,
    Object? cyan = _terminalConfigNoChange,
    Object? white = _terminalConfigNoChange,
  }) {
    return TerminalAnsiColors(
      black: identical(black, _terminalConfigNoChange)
          ? this.black
          : black as String?,
      red: identical(red, _terminalConfigNoChange) ? this.red : red as String?,
      green: identical(green, _terminalConfigNoChange)
          ? this.green
          : green as String?,
      yellow: identical(yellow, _terminalConfigNoChange)
          ? this.yellow
          : yellow as String?,
      blue: identical(blue, _terminalConfigNoChange)
          ? this.blue
          : blue as String?,
      magenta: identical(magenta, _terminalConfigNoChange)
          ? this.magenta
          : magenta as String?,
      cyan: identical(cyan, _terminalConfigNoChange)
          ? this.cyan
          : cyan as String?,
      white: identical(white, _terminalConfigNoChange)
          ? this.white
          : white as String?,
    );
  }

  TerminalAnsiColors resolveWith(TerminalAnsiColors defaults) {
    return TerminalAnsiColors(
      black: black ?? defaults.black,
      red: red ?? defaults.red,
      green: green ?? defaults.green,
      yellow: yellow ?? defaults.yellow,
      blue: blue ?? defaults.blue,
      magenta: magenta ?? defaults.magenta,
      cyan: cyan ?? defaults.cyan,
      white: white ?? defaults.white,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'black': black,
      'red': red,
      'green': green,
      'yellow': yellow,
      'blue': blue,
      'magenta': magenta,
      'cyan': cyan,
      'white': white,
    };
  }

  factory TerminalAnsiColors.fromJson(Object? json) {
    final map = _asObjectMap(json);
    return TerminalAnsiColors(
      black: _hexColorOrNull(map?['black']),
      red: _hexColorOrNull(map?['red']),
      green: _hexColorOrNull(map?['green']),
      yellow: _hexColorOrNull(map?['yellow']),
      blue: _hexColorOrNull(map?['blue']),
      magenta: _hexColorOrNull(map?['magenta']),
      cyan: _hexColorOrNull(map?['cyan']),
      white: _hexColorOrNull(map?['white']),
    );
  }
}

const TerminalSpecialColors defaultTerminalSpecialColors = TerminalSpecialColors(
  foreground: '#C0C0C0',
  background: '#000000',
  cursor: '#C0C0C0',
  selection: '#B5D5FF',
);

const TerminalAnsiColors defaultTerminalAnsiColors = TerminalAnsiColors(
  black: '#14191E',
  red: '#B43C2A',
  green: '#00815B',
  yellow: '#CFA518',
  blue: '#3065B8',
  magenta: '#8818A3',
  cyan: '#009399',
  white: '#E5E5E5',
);

const TerminalAnsiColors defaultTerminalBrightAnsiColors = TerminalAnsiColors(
  black: '#687378',
  red: '#FF6148',
  green: '#00C984',
  yellow: '#FFC531',
  blue: '#4F9CFE',
  magenta: '#C54FFF',
  cyan: '#00CCCC',
  white: '#FFFFFF',
);

class TerminalColorPalette {
  const TerminalColorPalette({
    this.special = const TerminalSpecialColors(),
    this.normal = const TerminalAnsiColors(),
    this.bright = const TerminalAnsiColors(),
  });

  final TerminalSpecialColors special;
  final TerminalAnsiColors normal;
  final TerminalAnsiColors bright;

  String? get foreground => special.foreground;
  String? get background => special.background;
  String? get cursor => special.cursor;
  String? get selection => special.selection;

  TerminalColorPalette copyWith({
    TerminalSpecialColors? special,
    TerminalAnsiColors? normal,
    TerminalAnsiColors? bright,
  }) {
    return TerminalColorPalette(
      special: special ?? this.special,
      normal: normal ?? this.normal,
      bright: bright ?? this.bright,
    );
  }

  TerminalColorPalette resolveWith([TerminalColorPalette defaults = defaultTerminalColorPalette]) {
    return TerminalColorPalette(
      special: special.resolveWith(defaults.special),
      normal: normal.resolveWith(defaults.normal),
      bright: bright.resolveWith(defaults.bright),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'special': special.toJson(),
      'normal': normal.toJson(),
      'bright': bright.toJson(),
    };
  }

  factory TerminalColorPalette.fromJson(Object? json) {
    final map = _asObjectMap(json);
    return TerminalColorPalette(
      special: TerminalSpecialColors.fromJson(map?['special']),
      normal: TerminalAnsiColors.fromJson(map?['normal']),
      bright: TerminalAnsiColors.fromJson(map?['bright']),
    );
  }
}

const TerminalColorPalette defaultTerminalColorPalette = TerminalColorPalette(
  special: defaultTerminalSpecialColors,
  normal: defaultTerminalAnsiColors,
  bright: defaultTerminalBrightAnsiColors,
);

class TerminalCursorConfig {
  const TerminalCursorConfig({
    this.shape = TerminalCursorShape.block,
    this.blink = true,
  });

  final TerminalCursorShape shape;
  final bool blink;

  TerminalCursorConfig copyWith({TerminalCursorShape? shape, bool? blink}) {
    return TerminalCursorConfig(
      shape: shape ?? this.shape,
      blink: blink ?? this.blink,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{'shape': shape.name, 'blink': blink};
  }

  factory TerminalCursorConfig.fromJson(Object? json) {
    final map = _asObjectMap(json);
    return TerminalCursorConfig(
      shape: _cursorShapeFromJson(map?['shape']),
      blink: _boolOr(map?['blink'], true),
    );
  }
}

class TerminalDisplayConfig {
  const TerminalDisplayConfig({
    this.font = const TerminalFontConfig(),
    this.colors = const TerminalColorPalette(),
    this.cursor = const TerminalCursorConfig(),
  });

  final TerminalFontConfig font;
  final TerminalColorPalette colors;
  final TerminalCursorConfig cursor;

  TerminalDisplayConfig copyWith({
    TerminalFontConfig? font,
    TerminalColorPalette? colors,
    TerminalCursorConfig? cursor,
  }) {
    return TerminalDisplayConfig(
      font: font ?? this.font,
      colors: colors ?? this.colors,
      cursor: cursor ?? this.cursor,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'font': font.toJson(),
      'colors': colors.toJson(),
      'cursor': cursor.toJson(),
    };
  }

  factory TerminalDisplayConfig.fromJson(Object? json) {
    final map = _asObjectMap(json);
    return TerminalDisplayConfig(
      font: TerminalFontConfig.fromJson(map?['font']),
      colors: TerminalColorPalette.fromJson(map?['colors']),
      cursor: TerminalCursorConfig.fromJson(map?['cursor']),
    );
  }
}

class TerminalInteractionConfig {
  const TerminalInteractionConfig({
    this.copyOnSelect = false,
    this.optionDragMode = TerminalOptionDragMode.blockSelection,
  });

  final bool copyOnSelect;
  final TerminalOptionDragMode optionDragMode;

  TerminalInteractionConfig copyWith({
    bool? copyOnSelect,
    TerminalOptionDragMode? optionDragMode,
  }) {
    return TerminalInteractionConfig(
      copyOnSelect: copyOnSelect ?? this.copyOnSelect,
      optionDragMode: optionDragMode ?? this.optionDragMode,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'copyOnSelect': copyOnSelect,
      'optionDragMode': optionDragMode.jsonValue,
    };
  }

  factory TerminalInteractionConfig.fromJson(Object? json) {
    final map = _asObjectMap(json);
    return TerminalInteractionConfig(
      copyOnSelect: _boolOr(map?['copyOnSelect'], false),
      optionDragMode: TerminalOptionDragMode.fromJsonValue(
        map?['optionDragMode'],
      ),
    );
  }
}

class TerminalSessionConfig {
  const TerminalSessionConfig({
    required this.launch,
    this.emulation = TerminalEmulation.xterm256,
    this.scrollbackLines = defaultTerminalScrollbackLines,
    this.shellIntegration = const TerminalShellIntegrationConfig(),
    this.display = const TerminalDisplayConfig(),
    this.interaction = const TerminalInteractionConfig(),
  });

  final TerminalLaunchConfig launch;
  final TerminalEmulation emulation;
  final int scrollbackLines;
  final TerminalShellIntegrationConfig shellIntegration;
  final TerminalDisplayConfig display;
  final TerminalInteractionConfig interaction;

  TerminalSessionConfig copyWith({
    TerminalLaunchConfig? launch,
    TerminalEmulation? emulation,
    int? scrollbackLines,
    TerminalShellIntegrationConfig? shellIntegration,
    TerminalDisplayConfig? display,
    TerminalInteractionConfig? interaction,
  }) {
    return TerminalSessionConfig(
      launch: launch ?? this.launch,
      emulation: emulation ?? this.emulation,
      scrollbackLines: scrollbackLines ?? this.scrollbackLines,
      shellIntegration: shellIntegration ?? this.shellIntegration,
      display: display ?? this.display,
      interaction: interaction ?? this.interaction,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'launch': launch.toJson(),
      'terminal': <String, Object?>{
        'emulation': emulation.name,
        'scrollbackLines': scrollbackLines,
      },
      'shellIntegration': shellIntegration.toJson(),
      'appearance': display.toJson(),
      'interaction': interaction.toJson(),
    };
  }

  factory TerminalSessionConfig.fromJson(Map<String, Object?> json) {
    final terminal = _asObjectMap(json['terminal']);
    return TerminalSessionConfig(
      launch: TerminalLaunchConfig.fromJson(json['launch']),
      emulation: _emulationFromJson(terminal?['emulation']),
      scrollbackLines: _positiveIntOr(
        terminal?['scrollbackLines'],
        defaultTerminalScrollbackLines,
      ),
      display: TerminalDisplayConfig.fromJson(json['appearance']),
      interaction: TerminalInteractionConfig.fromJson(json['interaction']),
      shellIntegration: TerminalShellIntegrationConfig.fromJson(
        json['shellIntegration'],
      ),
    );
  }

  factory TerminalSessionConfig.fromProfileJson(
    Map<String, Object?> json, {
    required String defaultProgram,
    TerminalConfigWarningCallback? onWarning,
  }) {
    final terminal = _asObjectMap(json['terminal']);
    return TerminalSessionConfig(
      launch: _launchConfigFromProfileJson(
        json['launch'],
        legacy: json,
        defaultProgram: defaultProgram,
        onWarning: onWarning,
      ),
      emulation: _emulationFromProfileJson(
        terminal?['emulation'] ?? json['terminalEmulation'],
        path: terminal == null ? 'terminalEmulation' : 'terminal.emulation',
        onWarning: onWarning,
      ),
      scrollbackLines: _positiveIntField(
        terminal?['scrollbackLines'],
        fallback: defaultTerminalScrollbackLines,
        path: 'terminal.scrollbackLines',
        onWarning: onWarning,
      ),
      display: _displayConfigFromProfileJson(
        json['appearance'],
        onWarning: onWarning,
      ),
      interaction: _interactionConfigFromProfileJson(
        json['interaction'],
        onWarning: onWarning,
      ),
      shellIntegration: _shellIntegrationConfigFromProfileJson(
        json['shellIntegration'],
        onWarning: onWarning,
      ),
    );
  }
}

class TerminalConfigWarning {
  const TerminalConfigWarning({
    required this.path,
    required this.rawValue,
    required this.fallbackSummary,
  });

  final String path;
  final Object? rawValue;
  final String fallbackSummary;
}

typedef TerminalConfigWarningCallback =
    void Function(TerminalConfigWarning warning);

TerminalLaunchConfig _launchConfigFromProfileJson(
  Object? json, {
  required Map<String, Object?> legacy,
  required String defaultProgram,
  required TerminalConfigWarningCallback? onWarning,
}) {
  final launch = _asObjectMap(json);
  if (launch != null) {
    final rawProgram = launch['program'];
    final program = _stringOrNull(rawProgram)?.trim();
    return TerminalLaunchConfig(
      program: program == null || program.isEmpty
          ? _warnAndDefaultProgram(rawProgram, defaultProgram, onWarning)
          : program,
      args: _stringListField(
        launch['args'],
        path: 'launch.args',
        onWarning: onWarning,
      ),
      env: _stringMapField(
        launch['env'],
        path: 'launch.env',
        onWarning: onWarning,
      ),
      cwd: _nullableStringField(
        launch['cwd'],
        path: 'launch.cwd',
        onWarning: onWarning,
      ),
    );
  }

  final rawProgram = legacy['shell'];
  final program = _stringOrNull(rawProgram)?.trim();
  return TerminalLaunchConfig(
    program: program == null || program.isEmpty
        ? _warnAndDefaultProgram(
            rawProgram,
            defaultProgram,
            onWarning,
            path: 'shell',
          )
        : program,
    args: _stringListField(legacy['args'], path: 'args', onWarning: onWarning),
    env: _stringMapField(legacy['env'], path: 'env', onWarning: onWarning),
    cwd: _nullableStringField(legacy['cwd'], path: 'cwd', onWarning: onWarning),
  );
}

TerminalDisplayConfig _displayConfigFromProfileJson(
  Object? json, {
  required TerminalConfigWarningCallback? onWarning,
}) {
  final appearance = _asObjectMap(json);
  final font = _asObjectMap(appearance?['font']);
  final rawFamily = font?['family'];
  final family = _stringOrNull(rawFamily)?.trim();
  final colors = _asObjectMap(appearance?['colors']);
  final specialColors = _asObjectMap(colors?['special']);
  final normalColors = _asObjectMap(colors?['normal']);
  final brightColors = _asObjectMap(colors?['bright']);
  final cursor = _asObjectMap(appearance?['cursor']);
  _warnLegacyFlatColorFields(colors, onWarning: onWarning);
  return TerminalDisplayConfig(
    font: TerminalFontConfig(
      family: family == null || family.isEmpty
          ? _warnAndDefaultString(
              rawFamily,
              path: 'appearance.font.family',
              fallback: terminalPrimaryFontFamily,
              onWarning: onWarning,
            )
          : family,
      fallback: _fontFallbackList(font?['fallback'], onWarning: onWarning),
      size: _positiveDoubleField(
        font?['size'],
        fallback: terminalFontSize,
        path: 'appearance.font.size',
        onWarning: onWarning,
      ),
      lineHeight: _positiveDoubleField(
        font?['lineHeight'],
        fallback: terminalLineHeight,
        path: 'appearance.font.lineHeight',
        onWarning: onWarning,
      ),
    ),
    colors: TerminalColorPalette(
      special: TerminalSpecialColors(
        foreground: _nullableHexColor(
          specialColors?['foreground'],
          path: 'appearance.colors.special.foreground',
          onWarning: onWarning,
        ),
        background: _nullableHexColor(
          specialColors?['background'],
          path: 'appearance.colors.special.background',
          onWarning: onWarning,
        ),
        cursor: _nullableHexColor(
          specialColors?['cursor'],
          path: 'appearance.colors.special.cursor',
          onWarning: onWarning,
        ),
        selection: _nullableHexColor(
          specialColors?['selection'],
          path: 'appearance.colors.special.selection',
          onWarning: onWarning,
        ),
      ),
      normal: _ansiColorsFromProfileJson(
        normalColors,
        path: 'appearance.colors.normal',
        onWarning: onWarning,
      ),
      bright: _ansiColorsFromProfileJson(
        brightColors,
        path: 'appearance.colors.bright',
        onWarning: onWarning,
      ),
    ),
    cursor: TerminalCursorConfig(
      shape: _cursorShapeFromProfileJson(
        cursor?['shape'],
        path: 'appearance.cursor.shape',
        onWarning: onWarning,
      ),
      blink: _boolField(
        cursor?['blink'],
        fallback: true,
        path: 'appearance.cursor.blink',
        onWarning: onWarning,
      ),
    ),
  );
}

TerminalInteractionConfig _interactionConfigFromProfileJson(
  Object? json, {
  required TerminalConfigWarningCallback? onWarning,
}) {
  final interaction = _asObjectMap(json);
  return TerminalInteractionConfig(
    copyOnSelect: _boolField(
      interaction?['copyOnSelect'],
      fallback: false,
      path: 'interaction.copyOnSelect',
      onWarning: onWarning,
    ),
    optionDragMode: _optionDragModeFromProfileJson(
      interaction?['optionDragMode'],
      path: 'interaction.optionDragMode',
      onWarning: onWarning,
    ),
  );
}

TerminalShellIntegrationConfig _shellIntegrationConfigFromProfileJson(
  Object? json, {
  required TerminalConfigWarningCallback? onWarning,
}) {
  final shellIntegration = _asObjectMap(json);
  return TerminalShellIntegrationConfig(
    enabled: _boolField(
      shellIntegration?['enabled'],
      fallback: true,
      path: 'shellIntegration.enabled',
      onWarning: onWarning,
    ),
  );
}

void _warnLegacyFlatColorFields(
  Map<String, Object?>? colors, {
  required TerminalConfigWarningCallback? onWarning,
}) {
  if (colors == null) {
    return;
  }
  for (final field in const <String>[
    'foreground',
    'background',
    'cursor',
    'selection',
  ]) {
    if (!colors.containsKey(field)) {
      continue;
    }
    onWarning?.call(
      TerminalConfigWarning(
        path: 'appearance.colors.$field',
        rawValue: colors[field],
        fallbackSummary:
            'ignored legacy flat color field; use appearance.colors.special.$field',
      ),
    );
  }
}

Map<String, Object?>? _asObjectMap(Object? value) {
  if (value is Map) {
    return value.map(
      (key, entry) => MapEntry(key.toString(), entry as Object?),
    );
  }
  return null;
}

String? _stringOrNull(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}

String? _trimmedStringOrNull(Object? value) {
  final text = _stringOrNull(value)?.trim();
  return text == null || text.isEmpty ? null : text;
}

String? _hexColorOrNull(Object? rawValue) {
  final value = _stringOrNull(rawValue);
  if (value == null) {
    return null;
  }
  final normalized = value.trim().toUpperCase();
  return RegExp(r'^#[0-9A-F]{6}$').hasMatch(normalized) ? normalized : null;
}

List<String> _stringList(
  Object? value, {
  List<String> fallback = const <String>[],
}) {
  if (value is List) {
    return value.whereType<String>().toList();
  }
  return fallback;
}

List<String> _trimmedStringList(
  Object? value, {
  required List<String> fallback,
}) {
  if (value is! List) {
    return fallback;
  }
  final values = <String>[];
  for (final entry in value) {
    final text = _trimmedStringOrNull(entry);
    if (text != null) {
      values.add(text);
    }
  }
  return values.isEmpty ? fallback : values;
}

Map<String, String> _stringMap(Object? value) {
  if (value is Map) {
    final values = <String, String>{};
    for (final entry in value.entries) {
      final key = entry.key;
      final entryValue = entry.value;
      if (key is String && key.trim().isNotEmpty && entryValue is String) {
        values[key.trim()] = entryValue;
      }
    }
    return values;
  }
  return const <String, String>{};
}

double _positiveFiniteDoubleOr(Object? value, double fallback) {
  if (value is num) {
    final parsed = value.toDouble();
    if (parsed.isFinite && parsed > 0) {
      return parsed;
    }
  }
  return fallback;
}

int _positiveIntOr(Object? value, int fallback) {
  return _positiveWholeIntOrNull(value) ?? fallback;
}

bool _boolOr(Object? value, bool fallback) {
  if (value is bool) {
    return value;
  }
  return fallback;
}

TerminalCursorShape _cursorShapeFromJson(Object? value) {
  return switch (value) {
    'underline' => TerminalCursorShape.underline,
    'beam' => TerminalCursorShape.beam,
    _ => TerminalCursorShape.block,
  };
}

TerminalEmulation _emulationFromJson(Object? value) {
  return switch (value) {
    'vt220' => TerminalEmulation.vt220,
    _ => TerminalEmulation.xterm256,
  };
}

String _warnAndDefaultProgram(
  Object? rawValue,
  String fallback,
  TerminalConfigWarningCallback? onWarning, {
  String path = 'launch.program',
}) {
  onWarning?.call(
    TerminalConfigWarning(
      path: path,
      rawValue: rawValue,
      fallbackSummary: 'used default shell "$fallback"',
    ),
  );
  return fallback;
}

String _warnAndDefaultString(
  Object? rawValue, {
  required String path,
  required String fallback,
  required TerminalConfigWarningCallback? onWarning,
}) {
  if (rawValue != null) {
    onWarning?.call(
      TerminalConfigWarning(
        path: path,
        rawValue: rawValue,
        fallbackSummary: 'used default value "$fallback"',
      ),
    );
  }
  return fallback;
}

String? _nullableStringField(
  Object? rawValue, {
  required String path,
  required TerminalConfigWarningCallback? onWarning,
}) {
  if (rawValue == null) {
    return null;
  }
  final value = _stringOrNull(rawValue)?.trim();
  if (value != null && value.isNotEmpty) {
    return value;
  }
  onWarning?.call(
    TerminalConfigWarning(
      path: path,
      rawValue: rawValue,
      fallbackSummary: 'used default null value',
    ),
  );
  return null;
}

List<String> _stringListField(
  Object? rawValue, {
  required String path,
  required TerminalConfigWarningCallback? onWarning,
}) {
  if (rawValue == null) {
    return const <String>[];
  }
  if (rawValue is! List<dynamic>) {
    onWarning?.call(
      TerminalConfigWarning(
        path: path,
        rawValue: rawValue,
        fallbackSummary: 'used empty list',
      ),
    );
    return const <String>[];
  }
  final values = <String>[];
  for (var index = 0; index < rawValue.length; index += 1) {
    final entry = rawValue[index];
    if (entry is String) {
      if (entry.isEmpty) {
        onWarning?.call(
          TerminalConfigWarning(
            path: '$path[$index]',
            rawValue: entry,
            fallbackSummary: 'ignored empty value',
          ),
        );
        continue;
      }
      values.add(entry);
      continue;
    }
    onWarning?.call(
      TerminalConfigWarning(
        path: '$path[$index]',
        rawValue: entry,
        fallbackSummary: 'ignored invalid non-string value',
      ),
    );
  }
  return values;
}

List<String> _fontFallbackList(
  Object? rawValue, {
  required TerminalConfigWarningCallback? onWarning,
}) {
  if (rawValue == null) {
    return <String>[...terminalFontFamilyFallback];
  }
  if (rawValue is! List<dynamic>) {
    onWarning?.call(
      TerminalConfigWarning(
        path: 'appearance.font.fallback',
        rawValue: rawValue,
        fallbackSummary: 'used default fallback font list',
      ),
    );
    return <String>[...terminalFontFamilyFallback];
  }
  final values = <String>[];
  for (var index = 0; index < rawValue.length; index += 1) {
    final entry = rawValue[index];
    if (entry is String) {
      final normalized = entry.trim();
      if (normalized.isEmpty) {
        onWarning?.call(
          TerminalConfigWarning(
            path: 'appearance.font.fallback[$index]',
            rawValue: entry,
            fallbackSummary: 'ignored empty value',
          ),
        );
        continue;
      }
      values.add(normalized);
      continue;
    }
    onWarning?.call(
      TerminalConfigWarning(
        path: 'appearance.font.fallback[$index]',
        rawValue: entry,
        fallbackSummary: 'ignored invalid non-string value',
      ),
    );
  }
  return values.isEmpty ? <String>[...terminalFontFamilyFallback] : values;
}

Map<String, String> _stringMapField(
  Object? rawValue, {
  required String path,
  required TerminalConfigWarningCallback? onWarning,
}) {
  if (rawValue == null) {
    return const <String, String>{};
  }
  if (rawValue is! Map) {
    onWarning?.call(
      TerminalConfigWarning(
        path: path,
        rawValue: rawValue,
        fallbackSummary: 'used empty map',
      ),
    );
    return const <String, String>{};
  }
  final values = <String, String>{};
  for (final entry in rawValue.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key is! String || key.trim().isEmpty || value is! String) {
      onWarning?.call(
        TerminalConfigWarning(
          path: '$path.${key ?? 'unknown'}',
          rawValue: <Object?>[key, value],
          fallbackSummary: 'ignored invalid environment entry',
        ),
      );
      continue;
    }
    values[key.trim()] = value;
  }
  return values;
}

int _positiveIntField(
  Object? rawValue, {
  required int fallback,
  required String path,
  required TerminalConfigWarningCallback? onWarning,
}) {
  final value = _positiveWholeIntOrNull(rawValue);
  if (value != null) {
    return value;
  }
  if (rawValue != null) {
    onWarning?.call(
      TerminalConfigWarning(
        path: path,
        rawValue: rawValue,
        fallbackSummary: 'used default value $fallback',
      ),
    );
  }
  return fallback;
}

int? _positiveWholeIntOrNull(Object? rawValue) {
  if (rawValue is int) {
    return rawValue >= 1 ? rawValue : null;
  }
  if (rawValue is num && rawValue.isFinite) {
    final parsed = rawValue.toInt();
    if (parsed >= 1 && rawValue == parsed) {
      return parsed;
    }
  }
  return null;
}

double _positiveDoubleField(
  Object? rawValue, {
  required double fallback,
  required String path,
  required TerminalConfigWarningCallback? onWarning,
}) {
  if (rawValue is num) {
    final value = rawValue.toDouble();
    if (value.isFinite && value > 0) {
      return value;
    }
  }
  if (rawValue != null) {
    onWarning?.call(
      TerminalConfigWarning(
        path: path,
        rawValue: rawValue,
        fallbackSummary: 'used default value $fallback',
      ),
    );
  }
  return fallback;
}

bool _boolField(
  Object? rawValue, {
  required bool fallback,
  required String path,
  required TerminalConfigWarningCallback? onWarning,
}) {
  if (rawValue is bool) {
    return rawValue;
  }
  if (rawValue != null) {
    onWarning?.call(
      TerminalConfigWarning(
        path: path,
        rawValue: rawValue,
        fallbackSummary: 'used default value $fallback',
      ),
    );
  }
  return fallback;
}

String? _nullableHexColor(
  Object? rawValue, {
  required String path,
  required TerminalConfigWarningCallback? onWarning,
}) {
  if (rawValue == null) {
    return null;
  }
  final value = _hexColorOrNull(rawValue);
  if (value != null) {
    return value;
  }
  onWarning?.call(
    TerminalConfigWarning(
      path: path,
      rawValue: rawValue,
      fallbackSummary: 'used inherited default color',
    ),
  );
  return null;
}

TerminalAnsiColors _ansiColorsFromProfileJson(
  Object? rawValue, {
  required String path,
  required TerminalConfigWarningCallback? onWarning,
}) {
  if (rawValue == null) {
    return const TerminalAnsiColors();
  }
  final colors = _asObjectMap(rawValue);
  if (colors == null) {
    onWarning?.call(
      TerminalConfigWarning(
        path: path,
        rawValue: rawValue,
        fallbackSummary: 'used inherited default ansi colors',
      ),
    );
    return const TerminalAnsiColors();
  }
  return TerminalAnsiColors(
    black: _nullableHexColor(
      colors['black'],
      path: '$path.black',
      onWarning: onWarning,
    ),
    red: _nullableHexColor(colors['red'], path: '$path.red', onWarning: onWarning),
    green: _nullableHexColor(
      colors['green'],
      path: '$path.green',
      onWarning: onWarning,
    ),
    yellow: _nullableHexColor(
      colors['yellow'],
      path: '$path.yellow',
      onWarning: onWarning,
    ),
    blue: _nullableHexColor(
      colors['blue'],
      path: '$path.blue',
      onWarning: onWarning,
    ),
    magenta: _nullableHexColor(
      colors['magenta'],
      path: '$path.magenta',
      onWarning: onWarning,
    ),
    cyan: _nullableHexColor(
      colors['cyan'],
      path: '$path.cyan',
      onWarning: onWarning,
    ),
    white: _nullableHexColor(
      colors['white'],
      path: '$path.white',
      onWarning: onWarning,
    ),
  );
}

TerminalEmulation _emulationFromProfileJson(
  Object? raw, {
  required String path,
  required TerminalConfigWarningCallback? onWarning,
}) {
  return switch (raw) {
    'vt220' => TerminalEmulation.vt220,
    'xterm256' || 'xterm-256color' || null => TerminalEmulation.xterm256,
    _ => () {
      onWarning?.call(
        TerminalConfigWarning(
          path: path,
          rawValue: raw,
          fallbackSummary:
              'used default emulation "${TerminalEmulation.xterm256.name}"',
        ),
      );
      return TerminalEmulation.xterm256;
    }(),
  };
}

TerminalCursorShape _cursorShapeFromProfileJson(
  Object? raw, {
  required String path,
  required TerminalConfigWarningCallback? onWarning,
}) {
  return switch (raw) {
    'underline' => TerminalCursorShape.underline,
    'beam' => TerminalCursorShape.beam,
    'block' || null => TerminalCursorShape.block,
    _ => () {
      onWarning?.call(
        TerminalConfigWarning(
          path: path,
          rawValue: raw,
          fallbackSummary:
              'used default cursor shape "${TerminalCursorShape.block.name}"',
        ),
      );
      return TerminalCursorShape.block;
    }(),
  };
}

TerminalOptionDragMode _optionDragModeFromProfileJson(
  Object? raw, {
  required String path,
  required TerminalConfigWarningCallback? onWarning,
}) {
  return switch (raw) {
    'normal_selection' => TerminalOptionDragMode.normalSelection,
    'block_selection' || null => TerminalOptionDragMode.blockSelection,
    _ => () {
      onWarning?.call(
        TerminalConfigWarning(
          path: path,
          rawValue: raw,
          fallbackSummary:
              'used default option-drag mode "${TerminalOptionDragMode.blockSelection.jsonValue}"',
        ),
      );
      return TerminalOptionDragMode.blockSelection;
    }(),
  };
}

const Object _terminalConfigNoChange = Object();
