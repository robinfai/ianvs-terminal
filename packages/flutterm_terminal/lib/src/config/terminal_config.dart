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
      program: _stringOrNull(map?['program']) ?? '',
      args: _stringList(map?['args']),
      env: _stringMap(map?['env']),
      cwd: _stringOrNull(map?['cwd']),
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
      family: _stringOrNull(map?['family']) ?? terminalPrimaryFontFamily,
      fallback: _stringList(map?['fallback'], fallback: terminalFontFamilyFallback),
      size: _doubleOr(map?['size'], terminalFontSize),
      lineHeight: _doubleOr(map?['lineHeight'], terminalLineHeight),
    );
  }
}

class TerminalColorPalette {
  const TerminalColorPalette({
    this.foreground,
    this.background,
    this.cursor,
    this.selection,
  });

  final String? foreground;
  final String? background;
  final String? cursor;
  final String? selection;

  TerminalColorPalette copyWith({
    Object? foreground = _terminalConfigNoChange,
    Object? background = _terminalConfigNoChange,
    Object? cursor = _terminalConfigNoChange,
    Object? selection = _terminalConfigNoChange,
  }) {
    return TerminalColorPalette(
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

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'foreground': foreground,
      'background': background,
      'cursor': cursor,
      'selection': selection,
    };
  }

  factory TerminalColorPalette.fromJson(Object? json) {
    final map = _asObjectMap(json);
    return TerminalColorPalette(
      foreground: _stringOrNull(map?['foreground']),
      background: _stringOrNull(map?['background']),
      cursor: _stringOrNull(map?['cursor']),
      selection: _stringOrNull(map?['selection']),
    );
  }
}

class TerminalCursorConfig {
  const TerminalCursorConfig({
    this.shape = TerminalCursorShape.block,
    this.blink = true,
  });

  final TerminalCursorShape shape;
  final bool blink;

  TerminalCursorConfig copyWith({
    TerminalCursorShape? shape,
    bool? blink,
  }) {
    return TerminalCursorConfig(
      shape: shape ?? this.shape,
      blink: blink ?? this.blink,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'shape': shape.name,
      'blink': blink,
    };
  }

  factory TerminalCursorConfig.fromJson(Object? json) {
    final map = _asObjectMap(json);
    return TerminalCursorConfig(
      shape: _cursorShapeFromJson(map?['shape']),
      blink: map?['blink'] as bool? ?? true,
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
      copyOnSelect: map?['copyOnSelect'] as bool? ?? false,
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
    this.display = const TerminalDisplayConfig(),
    this.interaction = const TerminalInteractionConfig(),
  });

  final TerminalLaunchConfig launch;
  final TerminalEmulation emulation;
  final int scrollbackLines;
  final TerminalDisplayConfig display;
  final TerminalInteractionConfig interaction;

  TerminalSessionConfig copyWith({
    TerminalLaunchConfig? launch,
    TerminalEmulation? emulation,
    int? scrollbackLines,
    TerminalDisplayConfig? display,
    TerminalInteractionConfig? interaction,
  }) {
    return TerminalSessionConfig(
      launch: launch ?? this.launch,
      emulation: emulation ?? this.emulation,
      scrollbackLines: scrollbackLines ?? this.scrollbackLines,
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
      'appearance': display.toJson(),
      'interaction': interaction.toJson(),
    };
  }

  factory TerminalSessionConfig.fromJson(Map<String, Object?> json) {
    final terminal = _asObjectMap(json['terminal']);
    return TerminalSessionConfig(
      launch: TerminalLaunchConfig.fromJson(json['launch']),
      emulation: _emulationFromJson(terminal?['emulation']),
      scrollbackLines: _intOr(
        terminal?['scrollbackLines'],
        defaultTerminalScrollbackLines,
      ),
      display: TerminalDisplayConfig.fromJson(json['appearance']),
      interaction: TerminalInteractionConfig.fromJson(json['interaction']),
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

List<String> _stringList(Object? value, {List<String> fallback = const <String>[]}) {
  if (value is List) {
    return value.whereType<String>().toList();
  }
  return fallback;
}

Map<String, String> _stringMap(Object? value) {
  if (value is Map) {
    return value.map(
      (key, entry) => MapEntry(key.toString(), entry?.toString() ?? ''),
    );
  }
  return const <String, String>{};
}

double _doubleOr(Object? value, double fallback) {
  if (value is num) {
    return value.toDouble();
  }
  return fallback;
}

int _intOr(Object? value, int fallback) {
  if (value is num) {
    return value.toInt();
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

const Object _terminalConfigNoChange = Object();
