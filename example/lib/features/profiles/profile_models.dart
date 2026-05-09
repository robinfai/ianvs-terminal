import 'dart:convert';

import 'package:flutterm_terminal/flutterm_terminal.dart' as terminal_pkg;

typedef TerminalEmulation = terminal_pkg.TerminalEmulation;
typedef TerminalCursorShape = terminal_pkg.TerminalCursorShape;
typedef TerminalOptionDragMode = terminal_pkg.TerminalOptionDragMode;

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

class TerminalProfile {
  TerminalProfile({
    required this.id,
    required this.name,
    required String shell,
    List<String> args = const [],
    Map<String, String> env = const {},
    String? cwd,
    TerminalEmulation terminalEmulation = TerminalEmulation.xterm256,
    int scrollbackLines = terminal_pkg.defaultTerminalScrollbackLines,
    terminal_pkg.TerminalDisplayConfig appearance =
        const terminal_pkg.TerminalDisplayConfig(),
    terminal_pkg.TerminalInteractionConfig interaction =
        const terminal_pkg.TerminalInteractionConfig(),
  }) : sessionConfig = terminal_pkg.TerminalSessionConfig(
         launch: terminal_pkg.TerminalLaunchConfig(
           program: shell,
           args: args,
           env: env,
           cwd: cwd,
         ),
         emulation: terminalEmulation,
         scrollbackLines: scrollbackLines,
         display: appearance,
         interaction: interaction,
       );

  const TerminalProfile.configured({
    required this.id,
    required this.name,
    required this.sessionConfig,
  });

  final String id;
  final String name;
  final terminal_pkg.TerminalSessionConfig sessionConfig;

  String get shell => sessionConfig.launch.program;
  List<String> get args => sessionConfig.launch.args;
  Map<String, String> get env => sessionConfig.launch.env;
  String? get cwd => sessionConfig.launch.cwd;
  TerminalEmulation get terminalEmulation => sessionConfig.emulation;
  int get scrollbackLines => sessionConfig.scrollbackLines;
  terminal_pkg.TerminalLaunchConfig get launch => sessionConfig.launch;
  terminal_pkg.TerminalDisplayConfig get appearance => sessionConfig.display;
  terminal_pkg.TerminalInteractionConfig get interaction =>
      sessionConfig.interaction;

  TerminalProfile copyWith({
    String? id,
    String? name,
    String? shell,
    List<String>? args,
    Map<String, String>? env,
    Object? cwd = _profileNoChange,
    TerminalEmulation? terminalEmulation,
    int? scrollbackLines,
    terminal_pkg.TerminalDisplayConfig? appearance,
    terminal_pkg.TerminalInteractionConfig? interaction,
    terminal_pkg.TerminalSessionConfig? sessionConfig,
  }) {
    final baseConfig = sessionConfig ?? this.sessionConfig;
    final nextLaunch = baseConfig.launch.copyWith(
      program: shell,
      args: args,
      env: env,
      cwd: cwd,
    );
    return TerminalProfile.configured(
      id: id ?? this.id,
      name: name ?? this.name,
      sessionConfig: baseConfig.copyWith(
        launch: nextLaunch,
        emulation: terminalEmulation,
        scrollbackLines: scrollbackLines,
        display: appearance,
        interaction: interaction,
      ),
    );
  }

  Map<String, Object?> toJson() {
    final configJson = sessionConfig.toJson();
    return {'id': id, 'name': name, ...configJson};
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

    final sessionConfig = terminal_pkg.TerminalSessionConfig.fromProfileJson(
      json,
      defaultProgram: defaultTerminalProfile().shell,
      onWarning: (warning) {
        warningSink.add(
          path: warning.path,
          rawValue: warning.rawValue,
          fallbackSummary: warning.fallbackSummary,
        );
      },
    );

    return TerminalProfile.configured(
      id: profileId,
      name: profileName,
      sessionConfig: sessionConfig,
    );
  }

  terminal_pkg.TerminalSessionConfig toSessionConfig() {
    return sessionConfig;
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
