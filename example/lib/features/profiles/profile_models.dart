import 'dart:convert';

import 'package:flutterm_terminal/flutterm_terminal.dart' as terminal_pkg;

import '../terminal/terminal_defaults.dart';

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

class TerminalProfileLoadWarning {
  const TerminalProfileLoadWarning({
    required this.profileId,
    required this.profileName,
    required this.path,
    required this.rawValueSummary,
    required this.fallbackSummary,
  });

  final String profileId;
  final String profileName;
  final String path;
  final String rawValueSummary;
  final String fallbackSummary;

  @override
  bool operator ==(Object other) {
    return other is TerminalProfileLoadWarning &&
        other.profileId == profileId &&
        other.profileName == profileName &&
        other.path == path &&
        other.rawValueSummary == rawValueSummary &&
        other.fallbackSummary == fallbackSummary;
  }

  @override
  int get hashCode => Object.hash(
    profileId,
    profileName,
    path,
    rawValueSummary,
    fallbackSummary,
  );
}

class TerminalProfileLaunch {
  const TerminalProfileLaunch({
    required this.program,
    this.args = const [],
    this.env = const {},
    this.cwd,
  });

  final String program;
  final List<String> args;
  final Map<String, String> env;
  final String? cwd;

  TerminalProfileLaunch copyWith({
    String? program,
    List<String>? args,
    Map<String, String>? env,
    Object? cwd = _profileNoChange,
  }) {
    return TerminalProfileLaunch(
      program: program ?? this.program,
      args: args ?? this.args,
      env: env ?? this.env,
      cwd: identical(cwd, _profileNoChange) ? this.cwd : cwd as String?,
    );
  }

  Map<String, Object?> toJson() {
    return {'program': program, 'args': args, 'env': env, 'cwd': cwd};
  }

  terminal_pkg.TerminalLaunchConfig toTerminalLaunchConfig() {
    return terminal_pkg.TerminalLaunchConfig(
      program: program,
      args: args,
      env: env,
      cwd: cwd,
    );
  }

  static TerminalProfileLaunch fromJson(
    Object? json, {
    Map<String, Object?>? legacy,
  }) {
    return _fromJson(json, legacy: legacy);
  }

  static TerminalProfileLaunch _fromJson(
    Object? json, {
    Map<String, Object?>? legacy,
    _TerminalProfileWarningSink? warningSink,
  }) {
    final launch = _asObjectMap(json);
    if (launch != null) {
      final rawProgram = launch['program'];
      final program = _stringOrNull(rawProgram)?.trim();
      return TerminalProfileLaunch(
        program: program == null || program.isEmpty
            ? _warnAndDefaultProgram(rawProgram, warningSink)
            : program,
        args: _stringList(
          launch['args'],
          path: 'launch.args',
          warningSink: warningSink,
        ),
        env: _stringMap(
          launch['env'],
          path: 'launch.env',
          warningSink: warningSink,
        ),
        cwd: _nullableStringField(
          launch['cwd'],
          path: 'launch.cwd',
          warningSink: warningSink,
        ),
      );
    }

    final rawProgram = legacy?['shell'];
    final program = _stringOrNull(rawProgram)?.trim();
    return TerminalProfileLaunch(
      program: program == null || program.isEmpty
          ? _warnAndDefaultProgram(rawProgram, warningSink, path: 'shell')
          : program,
      args: _stringList(
        legacy?['args'],
        path: 'args',
        warningSink: warningSink,
      ),
      env: _stringMap(legacy?['env'], path: 'env', warningSink: warningSink),
      cwd: _nullableStringField(
        legacy?['cwd'],
        path: 'cwd',
        warningSink: warningSink,
      ),
    );
  }
}

class TerminalProfileTerminal {
  const TerminalProfileTerminal({
    this.emulation = TerminalEmulation.xterm256,
    this.scrollbackLines = defaultTerminalScrollbackLines,
  });

  final TerminalEmulation emulation;
  final int scrollbackLines;

  TerminalProfileTerminal copyWith({
    TerminalEmulation? emulation,
    int? scrollbackLines,
  }) {
    return TerminalProfileTerminal(
      emulation: emulation ?? this.emulation,
      scrollbackLines: scrollbackLines ?? this.scrollbackLines,
    );
  }

  Map<String, Object?> toJson() {
    return {'emulation': emulation.name, 'scrollbackLines': scrollbackLines};
  }

  terminal_pkg.TerminalEmulation toTerminalEmulation() {
    return _toTerminalPackageEmulation(emulation);
  }

  static TerminalProfileTerminal fromJson(
    Object? json, {
    Map<String, Object?>? legacy,
  }) {
    return _fromJson(json, legacy: legacy);
  }

  static TerminalProfileTerminal _fromJson(
    Object? json, {
    Map<String, Object?>? legacy,
    _TerminalProfileWarningSink? warningSink,
  }) {
    final terminal = _asObjectMap(json);
    if (terminal != null) {
      return TerminalProfileTerminal(
        emulation: _terminalEmulationFromJson(
          terminal['emulation'],
          path: 'terminal.emulation',
          warningSink: warningSink,
        ),
        scrollbackLines: _positiveIntField(
          terminal['scrollbackLines'],
          fallback: defaultTerminalScrollbackLines,
          path: 'terminal.scrollbackLines',
          warningSink: warningSink,
        ),
      );
    }

    return TerminalProfileTerminal(
      emulation: _terminalEmulationFromJson(
        legacy?['terminalEmulation'],
        path: 'terminalEmulation',
        warningSink: warningSink,
      ),
    );
  }
}

class TerminalProfileFont {
  const TerminalProfileFont({
    this.family = terminalPrimaryFontFamily,
    this.fallback = terminalFontFamilyFallback,
    this.size = terminalFontSize,
    this.lineHeight = terminalLineHeight,
  });

  final String family;
  final List<String> fallback;
  final double size;
  final double lineHeight;

  TerminalProfileFont copyWith({
    String? family,
    List<String>? fallback,
    double? size,
    double? lineHeight,
  }) {
    return TerminalProfileFont(
      family: family ?? this.family,
      fallback: fallback ?? this.fallback,
      size: size ?? this.size,
      lineHeight: lineHeight ?? this.lineHeight,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'family': family,
      'fallback': fallback,
      'size': size,
      'lineHeight': lineHeight,
    };
  }

  terminal_pkg.TerminalFontConfig toTerminalFontConfig() {
    return terminal_pkg.TerminalFontConfig(
      family: family,
      fallback: fallback,
      size: size,
      lineHeight: lineHeight,
    );
  }

  static TerminalProfileFont fromJson(Object? json) {
    return _fromJson(json);
  }

  static TerminalProfileFont _fromJson(
    Object? json, {
    _TerminalProfileWarningSink? warningSink,
  }) {
    final font = _asObjectMap(json);
    final rawFamily = font?['family'];
    final family = _stringOrNull(rawFamily)?.trim();
    return TerminalProfileFont(
      family: family == null || family.isEmpty
          ? _warnAndDefaultString(
              rawFamily,
              warningSink: warningSink,
              path: 'appearance.font.family',
              fallback: terminalPrimaryFontFamily,
            )
          : family,
      fallback:
          _stringList(
                font?['fallback'],
                path: 'appearance.font.fallback',
                warningSink: warningSink,
              )
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList(),
      size: _positiveDoubleField(
        font?['size'],
        fallback: terminalFontSize,
        path: 'appearance.font.size',
        warningSink: warningSink,
      ),
      lineHeight: _positiveDoubleField(
        font?['lineHeight'],
        fallback: terminalLineHeight,
        path: 'appearance.font.lineHeight',
        warningSink: warningSink,
      ),
    );
  }
}

class TerminalProfileColors {
  const TerminalProfileColors({
    this.foreground,
    this.background,
    this.cursor,
    this.selection,
  });

  final String? foreground;
  final String? background;
  final String? cursor;
  final String? selection;

  TerminalProfileColors copyWith({
    Object? foreground = _profileNoChange,
    Object? background = _profileNoChange,
    Object? cursor = _profileNoChange,
    Object? selection = _profileNoChange,
  }) {
    return TerminalProfileColors(
      foreground: identical(foreground, _profileNoChange)
          ? this.foreground
          : foreground as String?,
      background: identical(background, _profileNoChange)
          ? this.background
          : background as String?,
      cursor: identical(cursor, _profileNoChange)
          ? this.cursor
          : cursor as String?,
      selection: identical(selection, _profileNoChange)
          ? this.selection
          : selection as String?,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'foreground': foreground,
      'background': background,
      'cursor': cursor,
      'selection': selection,
    };
  }

  terminal_pkg.TerminalColorPalette toTerminalColorPalette() {
    return terminal_pkg.TerminalColorPalette(
      foreground: foreground,
      background: background,
      cursor: cursor,
      selection: selection,
    );
  }

  static TerminalProfileColors fromJson(Object? json) {
    return _fromJson(json);
  }

  static TerminalProfileColors _fromJson(
    Object? json, {
    _TerminalProfileWarningSink? warningSink,
  }) {
    final colors = _asObjectMap(json);
    return TerminalProfileColors(
      foreground: _nullableHexColor(
        colors?['foreground'],
        path: 'appearance.colors.foreground',
        warningSink: warningSink,
      ),
      background: _nullableHexColor(
        colors?['background'],
        path: 'appearance.colors.background',
        warningSink: warningSink,
      ),
      cursor: _nullableHexColor(
        colors?['cursor'],
        path: 'appearance.colors.cursor',
        warningSink: warningSink,
      ),
      selection: _nullableHexColor(
        colors?['selection'],
        path: 'appearance.colors.selection',
        warningSink: warningSink,
      ),
    );
  }
}

class TerminalProfileCursor {
  const TerminalProfileCursor({
    this.shape = TerminalCursorShape.block,
    this.blink = true,
  });

  final TerminalCursorShape shape;
  final bool blink;

  TerminalProfileCursor copyWith({TerminalCursorShape? shape, bool? blink}) {
    return TerminalProfileCursor(
      shape: shape ?? this.shape,
      blink: blink ?? this.blink,
    );
  }

  Map<String, Object?> toJson() {
    return {'shape': shape.name, 'blink': blink};
  }

  terminal_pkg.TerminalCursorConfig toTerminalCursorConfig() {
    return terminal_pkg.TerminalCursorConfig(
      shape: _toTerminalPackageCursorShape(shape),
      blink: blink,
    );
  }

  static TerminalProfileCursor fromJson(Object? json) {
    return _fromJson(json);
  }

  static TerminalProfileCursor _fromJson(
    Object? json, {
    _TerminalProfileWarningSink? warningSink,
  }) {
    final cursor = _asObjectMap(json);
    return TerminalProfileCursor(
      shape: _terminalCursorShapeFromJson(
        cursor?['shape'],
        path: 'appearance.cursor.shape',
        warningSink: warningSink,
      ),
      blink: _boolField(
        cursor?['blink'],
        fallback: true,
        path: 'appearance.cursor.blink',
        warningSink: warningSink,
      ),
    );
  }
}

class TerminalProfileAppearance {
  const TerminalProfileAppearance({
    this.font = const TerminalProfileFont(),
    this.colors = const TerminalProfileColors(),
    this.cursor = const TerminalProfileCursor(),
  });

  final TerminalProfileFont font;
  final TerminalProfileColors colors;
  final TerminalProfileCursor cursor;

  TerminalProfileAppearance copyWith({
    TerminalProfileFont? font,
    TerminalProfileColors? colors,
    TerminalProfileCursor? cursor,
  }) {
    return TerminalProfileAppearance(
      font: font ?? this.font,
      colors: colors ?? this.colors,
      cursor: cursor ?? this.cursor,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'font': font.toJson(),
      'colors': colors.toJson(),
      'cursor': cursor.toJson(),
    };
  }

  terminal_pkg.TerminalDisplayConfig toTerminalDisplayConfig() {
    return terminal_pkg.TerminalDisplayConfig(
      font: font.toTerminalFontConfig(),
      colors: colors.toTerminalColorPalette(),
      cursor: cursor.toTerminalCursorConfig(),
    );
  }

  static TerminalProfileAppearance fromJson(Object? json) {
    return _fromJson(json);
  }

  static TerminalProfileAppearance _fromJson(
    Object? json, {
    _TerminalProfileWarningSink? warningSink,
  }) {
    final appearance = _asObjectMap(json);
    return TerminalProfileAppearance(
      font: TerminalProfileFont._fromJson(
        appearance?['font'],
        warningSink: warningSink,
      ),
      colors: TerminalProfileColors._fromJson(
        appearance?['colors'],
        warningSink: warningSink,
      ),
      cursor: TerminalProfileCursor._fromJson(
        appearance?['cursor'],
        warningSink: warningSink,
      ),
    );
  }
}

class TerminalProfileInteraction {
  const TerminalProfileInteraction({
    this.copyOnSelect = false,
    this.optionDragMode = TerminalOptionDragMode.blockSelection,
  });

  final bool copyOnSelect;
  final TerminalOptionDragMode optionDragMode;

  TerminalProfileInteraction copyWith({
    bool? copyOnSelect,
    TerminalOptionDragMode? optionDragMode,
  }) {
    return TerminalProfileInteraction(
      copyOnSelect: copyOnSelect ?? this.copyOnSelect,
      optionDragMode: optionDragMode ?? this.optionDragMode,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'copyOnSelect': copyOnSelect,
      'optionDragMode': optionDragMode.jsonValue,
    };
  }

  terminal_pkg.TerminalInteractionConfig toTerminalInteractionConfig() {
    return terminal_pkg.TerminalInteractionConfig(
      copyOnSelect: copyOnSelect,
      optionDragMode: _toTerminalPackageDragMode(optionDragMode),
    );
  }

  static TerminalProfileInteraction fromJson(Object? json) {
    return _fromJson(json);
  }

  static TerminalProfileInteraction _fromJson(
    Object? json, {
    _TerminalProfileWarningSink? warningSink,
  }) {
    final interaction = _asObjectMap(json);
    return TerminalProfileInteraction(
      copyOnSelect: _boolField(
        interaction?['copyOnSelect'],
        fallback: false,
        path: 'interaction.copyOnSelect',
        warningSink: warningSink,
      ),
      optionDragMode: _optionDragModeFromJson(
        interaction?['optionDragMode'],
        path: 'interaction.optionDragMode',
        warningSink: warningSink,
      ),
    );
  }
}

class TerminalProfile {
  const TerminalProfile({
    required this.id,
    required this.name,
    required this.shell,
    this.args = const [],
    this.env = const {},
    this.cwd,
    this.terminalEmulation = TerminalEmulation.xterm256,
    this.scrollbackLines = defaultTerminalScrollbackLines,
    this.appearance = const TerminalProfileAppearance(),
    this.interaction = const TerminalProfileInteraction(),
  });

  TerminalProfile.configured({
    required this.id,
    required this.name,
    required TerminalProfileLaunch launch,
    TerminalProfileTerminal terminal = const TerminalProfileTerminal(),
    this.appearance = const TerminalProfileAppearance(),
    this.interaction = const TerminalProfileInteraction(),
  }) : shell = launch.program,
       args = launch.args,
       env = launch.env,
       cwd = launch.cwd,
       terminalEmulation = terminal.emulation,
       scrollbackLines = terminal.scrollbackLines;

  final String id;
  final String name;
  final String shell;
  final List<String> args;
  final Map<String, String> env;
  final String? cwd;
  final TerminalEmulation terminalEmulation;
  final int scrollbackLines;
  final TerminalProfileAppearance appearance;
  final TerminalProfileInteraction interaction;

  TerminalProfileLaunch get launch =>
      TerminalProfileLaunch(program: shell, args: args, env: env, cwd: cwd);

  TerminalProfileTerminal get terminal => TerminalProfileTerminal(
    emulation: terminalEmulation,
    scrollbackLines: scrollbackLines,
  );

  TerminalProfile copyWith({
    String? id,
    String? name,
    String? shell,
    List<String>? args,
    Map<String, String>? env,
    Object? cwd = _profileNoChange,
    TerminalEmulation? terminalEmulation,
    int? scrollbackLines,
    TerminalProfileAppearance? appearance,
    TerminalProfileInteraction? interaction,
  }) {
    return TerminalProfile.configured(
      id: id ?? this.id,
      name: name ?? this.name,
      launch: launch.copyWith(program: shell, args: args, env: env, cwd: cwd),
      terminal: terminal.copyWith(
        emulation: terminalEmulation,
        scrollbackLines: scrollbackLines,
      ),
      appearance: appearance ?? this.appearance,
      interaction: interaction ?? this.interaction,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'launch': launch.toJson(),
      'terminal': terminal.toJson(),
      'appearance': appearance.toJson(),
      'interaction': interaction.toJson(),
    };
  }

  static TerminalProfile fromJson(
    Map<String, Object?> json, {
    required String fallbackId,
    List<TerminalProfileLoadWarning>? loadWarnings,
  }) {
    final rawId = json['id'];
    final parsedId = _stringOrNull(rawId)?.trim();
    final profileId = parsedId == null || parsedId.isEmpty
        ? fallbackId
        : parsedId;
    final rawName = json['name'];
    final parsedName = _stringOrNull(rawName)?.trim();
    final profileName = parsedName == null || parsedName.isEmpty
        ? profileId
        : parsedName;
    final warningSink = _TerminalProfileWarningSink(
      profileId: profileId,
      profileName: profileName,
      warnings: loadWarnings,
    );

    if (parsedId == null || parsedId.isEmpty) {
      warningSink.add(
        path: 'id',
        rawValue: rawId,
        fallbackSummary: 'used fallback id "$profileId"',
      );
    }
    if (parsedName == null || parsedName.isEmpty) {
      warningSink.add(
        path: 'name',
        rawValue: rawName,
        fallbackSummary: 'used profile name "$profileName"',
      );
    }

    return TerminalProfile.configured(
      id: profileId,
      name: profileName,
      launch: TerminalProfileLaunch._fromJson(
        json['launch'],
        legacy: json,
        warningSink: warningSink,
      ),
      terminal: TerminalProfileTerminal._fromJson(
        json['terminal'],
        legacy: json,
        warningSink: warningSink,
      ),
      appearance: TerminalProfileAppearance._fromJson(
        json['appearance'],
        warningSink: warningSink,
      ),
      interaction: TerminalProfileInteraction._fromJson(
        json['interaction'],
        warningSink: warningSink,
      ),
    );
  }

  terminal_pkg.TerminalSessionConfig toSessionConfig() {
    return terminal_pkg.TerminalSessionConfig(
      launch: launch.toTerminalLaunchConfig(),
      emulation: terminal.toTerminalEmulation(),
      scrollbackLines: scrollbackLines,
      display: appearance.toTerminalDisplayConfig(),
      interaction: interaction.toTerminalInteractionConfig(),
    );
  }
}

class TerminalProfilesDocument {
  const TerminalProfilesDocument({
    this.schemaVersion = currentSchemaVersion,
    required this.profiles,
    this.loadWarnings = const [],
  });

  static const int currentSchemaVersion = 2;

  final int schemaVersion;
  final List<TerminalProfile> profiles;
  final List<TerminalProfileLoadWarning> loadWarnings;

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'profiles': profiles.map((profile) => profile.toJson()).toList(),
    };
  }

  String encode() => jsonEncode(toJson());

  static TerminalProfilesDocument fromJson(Map<String, Object?> json) {
    final warnings = <TerminalProfileLoadWarning>[];
    final profiles = <TerminalProfile>[];
    final rawProfiles = json['profiles'];
    if (rawProfiles is List<dynamic>) {
      for (var index = 0; index < rawProfiles.length; index += 1) {
        final rawProfile = rawProfiles[index];
        final profileMap = _asStringMap(rawProfile);
        if (profileMap == null) {
          warnings.add(
            TerminalProfileLoadWarning(
              profileId: 'profile-$index',
              profileName: 'Profile ${index + 1}',
              path: 'profiles[$index]',
              rawValueSummary: _rawValueSummary(rawProfile),
              fallbackSummary: 'ignored invalid profile entry',
            ),
          );
          continue;
        }
        profiles.add(
          TerminalProfile.fromJson(
            profileMap,
            fallbackId: _fallbackProfileIdFor(index),
            loadWarnings: warnings,
          ),
        );
      }
    } else {
      warnings.add(
        TerminalProfileLoadWarning(
          profileId: 'document',
          profileName: 'Profiles document',
          path: 'profiles',
          rawValueSummary: _rawValueSummary(rawProfiles),
          fallbackSummary: 'loaded no profiles from invalid profile list',
        ),
      );
    }

    return TerminalProfilesDocument(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      profiles: profiles,
      loadWarnings: warnings,
    );
  }
}

TerminalProfile defaultTerminalProfile() {
  return TerminalProfile(
    id: 'default',
    name: 'Local Shell',
    shell: const String.fromEnvironment(
      'FLUTTERM_DEFAULT_SHELL',
      defaultValue: '/bin/zsh',
    ),
  );
}

TerminalProfile vt220TerminalProfile() {
  return TerminalProfile(
    id: 'vt220',
    name: 'Strict VT220',
    shell: const String.fromEnvironment(
      'FLUTTERM_DEFAULT_SHELL',
      defaultValue: '/bin/zsh',
    ),
    terminalEmulation: TerminalEmulation.vt220,
  );
}

String terminalEmulationLabel(TerminalEmulation emulation) {
  return switch (emulation) {
    TerminalEmulation.xterm256 => 'xterm-256color',
    TerminalEmulation.vt220 => 'VT220',
  };
}

String terminalCursorShapeLabel(TerminalCursorShape shape) {
  return switch (shape) {
    TerminalCursorShape.block => 'Block',
    TerminalCursorShape.underline => 'Underline',
    TerminalCursorShape.beam => 'Beam',
  };
}

String terminalOptionDragModeLabel(TerminalOptionDragMode mode) {
  return switch (mode) {
    TerminalOptionDragMode.blockSelection => 'Block selection',
    TerminalOptionDragMode.normalSelection => 'Normal selection',
  };
}

terminal_pkg.TerminalEmulation _toTerminalPackageEmulation(
  TerminalEmulation emulation,
) {
  return switch (emulation) {
    TerminalEmulation.xterm256 => terminal_pkg.TerminalEmulation.xterm256,
    TerminalEmulation.vt220 => terminal_pkg.TerminalEmulation.vt220,
  };
}

terminal_pkg.TerminalCursorShape _toTerminalPackageCursorShape(
  TerminalCursorShape shape,
) {
  return switch (shape) {
    TerminalCursorShape.block => terminal_pkg.TerminalCursorShape.block,
    TerminalCursorShape.underline => terminal_pkg.TerminalCursorShape.underline,
    TerminalCursorShape.beam => terminal_pkg.TerminalCursorShape.beam,
  };
}

terminal_pkg.TerminalOptionDragMode _toTerminalPackageDragMode(
  TerminalOptionDragMode mode,
) {
  return switch (mode) {
    TerminalOptionDragMode.normalSelection =>
      terminal_pkg.TerminalOptionDragMode.normalSelection,
    TerminalOptionDragMode.blockSelection =>
      terminal_pkg.TerminalOptionDragMode.blockSelection,
  };
}

TerminalCursorShape _terminalCursorShapeFromJson(
  Object? raw, {
  String path = 'appearance.cursor.shape',
  _TerminalProfileWarningSink? warningSink,
}) {
  return _terminalCursorShapeFromJsonWithWarning(
    raw,
    path: path,
    warningSink: warningSink,
  );
}

const Object _profileNoChange = Object();

String terminalProfileLoadWarningMessage(TerminalProfileLoadWarning warning) {
  return '${warning.profileName} (${warning.profileId}) • ${warning.path} ignored: ${warning.rawValueSummary}. ${warning.fallbackSummary}.';
}

class _TerminalProfileWarningSink {
  _TerminalProfileWarningSink({
    required this.profileId,
    required this.profileName,
    required List<TerminalProfileLoadWarning>? warnings,
  }) : _warnings = warnings;

  final String profileId;
  final String profileName;
  final List<TerminalProfileLoadWarning>? _warnings;

  void add({
    required String path,
    required Object? rawValue,
    required String fallbackSummary,
  }) {
    _warnings?.add(
      TerminalProfileLoadWarning(
        profileId: profileId,
        profileName: profileName,
        path: path,
        rawValueSummary: _rawValueSummary(rawValue),
        fallbackSummary: fallbackSummary,
      ),
    );
  }
}

Map<Object?, Object?>? _asObjectMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return value.map(
    (key, entryValue) => MapEntry(key as Object?, entryValue as Object?),
  );
}

Map<String, Object?>? _asStringMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return value.map(
    (key, entryValue) => MapEntry(key.toString(), entryValue as Object?),
  );
}

String? _stringOrNull(Object? value) {
  return value is String ? value : null;
}

String _warnAndDefaultProgram(
  Object? rawValue,
  _TerminalProfileWarningSink? warningSink, {
  String path = 'launch.program',
}) {
  final fallback = defaultTerminalProfile().shell;
  warningSink?.add(
    path: path,
    rawValue: rawValue,
    fallbackSummary: 'used default shell "$fallback"',
  );
  return fallback;
}

String _warnAndDefaultString(
  Object? rawValue, {
  required _TerminalProfileWarningSink? warningSink,
  required String path,
  required String fallback,
}) {
  if (rawValue != null) {
    warningSink?.add(
      path: path,
      rawValue: rawValue,
      fallbackSummary: 'used default value "$fallback"',
    );
  }
  return fallback;
}

String? _nullableStringField(
  Object? rawValue, {
  required String path,
  required _TerminalProfileWarningSink? warningSink,
}) {
  if (rawValue == null) {
    return null;
  }
  final value = _stringOrNull(rawValue);
  if (value != null) {
    return value;
  }
  warningSink?.add(
    path: path,
    rawValue: rawValue,
    fallbackSummary: 'used default null value',
  );
  return null;
}

List<String> _stringList(
  Object? rawValue, {
  required String path,
  required _TerminalProfileWarningSink? warningSink,
}) {
  if (rawValue == null) {
    return path == 'appearance.font.fallback'
        ? [...terminalFontFamilyFallback]
        : const [];
  }
  if (rawValue is! List<dynamic>) {
    warningSink?.add(
      path: path,
      rawValue: rawValue,
      fallbackSummary: path == 'appearance.font.fallback'
          ? 'used default fallback font list'
          : 'used empty list',
    );
    return path == 'appearance.font.fallback'
        ? [...terminalFontFamilyFallback]
        : const [];
  }
  final values = <String>[];
  for (var index = 0; index < rawValue.length; index += 1) {
    final entry = rawValue[index];
    if (entry is String) {
      final normalized = path == 'appearance.font.fallback'
          ? entry.trim()
          : entry;
      if (normalized.isEmpty) {
        warningSink?.add(
          path: '$path[$index]',
          rawValue: entry,
          fallbackSummary: 'ignored empty value',
        );
        continue;
      }
      values.add(normalized);
      continue;
    }
    warningSink?.add(
      path: '$path[$index]',
      rawValue: entry,
      fallbackSummary: 'ignored invalid non-string value',
    );
  }
  if (path == 'appearance.font.fallback' && values.isEmpty) {
    return [...terminalFontFamilyFallback];
  }
  return values;
}

Map<String, String> _stringMap(
  Object? rawValue, {
  required String path,
  required _TerminalProfileWarningSink? warningSink,
}) {
  if (rawValue == null) {
    return const {};
  }
  if (rawValue is! Map) {
    warningSink?.add(
      path: path,
      rawValue: rawValue,
      fallbackSummary: 'used empty map',
    );
    return const {};
  }
  final values = <String, String>{};
  for (final entry in rawValue.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key is! String || key.trim().isEmpty || value is! String) {
      warningSink?.add(
        path: '$path.${key ?? 'unknown'}',
        rawValue: <Object?>[key, value],
        fallbackSummary: 'ignored invalid environment entry',
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
  required _TerminalProfileWarningSink? warningSink,
}) {
  if (rawValue is num && rawValue.toInt() >= 1) {
    return rawValue.toInt();
  }
  if (rawValue != null) {
    warningSink?.add(
      path: path,
      rawValue: rawValue,
      fallbackSummary: 'used default value $fallback',
    );
  }
  return fallback;
}

double _positiveDoubleField(
  Object? rawValue, {
  required double fallback,
  required String path,
  required _TerminalProfileWarningSink? warningSink,
}) {
  if (rawValue is num && rawValue.toDouble() > 0) {
    return rawValue.toDouble();
  }
  if (rawValue != null) {
    warningSink?.add(
      path: path,
      rawValue: rawValue,
      fallbackSummary: 'used default value $fallback',
    );
  }
  return fallback;
}

bool _boolField(
  Object? rawValue, {
  required bool fallback,
  required String path,
  required _TerminalProfileWarningSink? warningSink,
}) {
  if (rawValue is bool) {
    return rawValue;
  }
  if (rawValue != null) {
    warningSink?.add(
      path: path,
      rawValue: rawValue,
      fallbackSummary: 'used default value $fallback',
    );
  }
  return fallback;
}

String? _nullableHexColor(
  Object? rawValue, {
  required String path,
  required _TerminalProfileWarningSink? warningSink,
}) {
  if (rawValue == null) {
    return null;
  }
  final value = _stringOrNull(rawValue);
  if (value != null) {
    final normalized = value.trim().toUpperCase();
    if (RegExp(r'^#[0-9A-F]{6}$').hasMatch(normalized)) {
      return normalized;
    }
  }
  warningSink?.add(
    path: path,
    rawValue: rawValue,
    fallbackSummary: 'used inherited default color',
  );
  return null;
}

TerminalEmulation _terminalEmulationFromJson(
  Object? raw, {
  required String path,
  required _TerminalProfileWarningSink? warningSink,
}) {
  return switch (raw) {
    'vt220' => TerminalEmulation.vt220,
    'xterm256' || 'xterm-256color' || null => TerminalEmulation.xterm256,
    _ => () {
      warningSink?.add(
        path: path,
        rawValue: raw,
        fallbackSummary:
            'used default emulation "${TerminalEmulation.xterm256.name}"',
      );
      return TerminalEmulation.xterm256;
    }(),
  };
}

TerminalCursorShape _terminalCursorShapeFromJsonWithWarning(
  Object? raw, {
  String path = 'appearance.cursor.shape',
  _TerminalProfileWarningSink? warningSink,
}) {
  return switch (raw) {
    'underline' => TerminalCursorShape.underline,
    'beam' => TerminalCursorShape.beam,
    'block' || null => TerminalCursorShape.block,
    _ => () {
      warningSink?.add(
        path: path,
        rawValue: raw,
        fallbackSummary:
            'used default cursor shape "${TerminalCursorShape.block.name}"',
      );
      return TerminalCursorShape.block;
    }(),
  };
}

TerminalOptionDragMode _optionDragModeFromJson(
  Object? raw, {
  required String path,
  required _TerminalProfileWarningSink? warningSink,
}) {
  return switch (raw) {
    'normal_selection' => TerminalOptionDragMode.normalSelection,
    'block_selection' || null => TerminalOptionDragMode.blockSelection,
    _ => () {
      warningSink?.add(
        path: path,
        rawValue: raw,
        fallbackSummary:
            'used default option-drag mode "${TerminalOptionDragMode.blockSelection.jsonValue}"',
      );
      return TerminalOptionDragMode.blockSelection;
    }(),
  };
}

String _rawValueSummary(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is String) {
    final trimmed = value.trim();
    final normalized = trimmed.isEmpty ? '(empty string)' : '"$trimmed"';
    return normalized.length <= 72
        ? normalized
        : '${normalized.substring(0, 69)}..."';
  }
  if (value is num || value is bool) {
    return value.toString();
  }
  try {
    final encoded = jsonEncode(value);
    return encoded.length <= 72 ? encoded : '${encoded.substring(0, 69)}...';
  } on JsonUnsupportedObjectError {
    return value.runtimeType.toString();
  }
}

String _fallbackProfileIdFor(int index) => 'profile-${index + 1}';
