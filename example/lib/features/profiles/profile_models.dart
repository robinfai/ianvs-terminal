import 'dart:convert';

import '../terminal/terminal.dart' as terminal_pkg;

typedef TerminalEmulation = terminal_pkg.TerminalEmulation;
typedef TerminalCursorShape = terminal_pkg.TerminalCursorShape;
typedef TerminalOptionDragMode = terminal_pkg.TerminalOptionDragMode;
typedef TerminalColorPalette = terminal_pkg.TerminalColorPalette;
typedef TerminalProfileColors = terminal_pkg.TerminalColorPalette;
typedef TerminalSpecialColors = terminal_pkg.TerminalSpecialColors;
typedef TerminalAnsiColors = terminal_pkg.TerminalAnsiColors;
typedef TerminalProfileCursor = terminal_pkg.TerminalCursorConfig;
typedef TerminalProfileAppearance = terminal_pkg.TerminalDisplayConfig;
typedef TerminalProfileInteraction = terminal_pkg.TerminalInteractionConfig;

enum TerminalProfileTriggerAction { notify, sendText }

enum TerminalProfileSwitchRuleKind { hostname, username, directory }

class TerminalProfileSwitchRule {
  const TerminalProfileSwitchRule({
    required this.kind,
    required this.pattern,
    this.caseSensitive = false,
  });

  final TerminalProfileSwitchRuleKind kind;
  final String pattern;
  final bool caseSensitive;

  Map<String, Object?> toJson() {
    return {
      'kind': _switchRuleKindToJson(kind),
      'pattern': pattern,
      if (caseSensitive) 'caseSensitive': caseSensitive,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is TerminalProfileSwitchRule &&
        other.kind == kind &&
        other.pattern == pattern &&
        other.caseSensitive == caseSensitive;
  }

  @override
  int get hashCode => Object.hash(kind, pattern, caseSensitive);
}

class TerminalProfileTrigger {
  const TerminalProfileTrigger({
    required this.pattern,
    this.action = TerminalProfileTriggerAction.notify,
    this.value,
    this.caseSensitive = true,
  });

  final String pattern;
  final TerminalProfileTriggerAction action;
  final String? value;
  final bool caseSensitive;

  Map<String, Object?> toJson() {
    return {
      'pattern': pattern,
      'action': _triggerActionToJson(action),
      if (value != null && value!.isNotEmpty) 'value': value,
      if (!caseSensitive) 'caseSensitive': caseSensitive,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is TerminalProfileTrigger &&
        other.pattern == pattern &&
        other.action == action &&
        other.value == value &&
        other.caseSensitive == caseSensitive;
  }

  @override
  int get hashCode => Object.hash(pattern, action, value, caseSensitive);
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
    this.tags = const [],
    this.triggers = const [],
    this.switchRules = const [],
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
    this.tags = const [],
    this.triggers = const [],
    this.switchRules = const [],
  });

  final String id;
  final String name;
  final List<String> tags;
  final List<TerminalProfileTrigger> triggers;
  final List<TerminalProfileSwitchRule> switchRules;
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
    List<String>? tags,
    List<TerminalProfileTrigger>? triggers,
    List<TerminalProfileSwitchRule>? switchRules,
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
      tags: tags ?? this.tags,
      triggers: triggers ?? this.triggers,
      switchRules: switchRules ?? this.switchRules,
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
    return {
      'id': id,
      'name': name,
      if (tags.isNotEmpty) 'tags': tags,
      if (triggers.isNotEmpty)
        'triggers': triggers.map((trigger) => trigger.toJson()).toList(),
      if (switchRules.isNotEmpty)
        'automaticProfileSwitching': switchRules
            .map((rule) => rule.toJson())
            .toList(),
      ...configJson,
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
    final tags = _profileTagsFromJson(json['tags'], warningSink);
    final triggers = _profileTriggersFromJson(json['triggers'], warningSink);
    final switchRules = _profileSwitchRulesFromJson(
      json['automaticProfileSwitching'] ?? json['switchRules'],
      warningSink,
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
      tags: tags,
      triggers: triggers,
      switchRules: switchRules,
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

  static const int currentSchemaVersion = 4;

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
    final dynamicProfilesFormat =
        json['profiles'] == null && json['Profiles'] != null;
    final rawProfiles = dynamicProfilesFormat
        ? json['Profiles']
        : json['profiles'];
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
          _normalizeBuiltInShellProfile(
            TerminalProfile.fromJson(
              dynamicProfilesFormat
                  ? _dynamicProfileToProfileJson(profileMap)
                  : profileMap,
              fallbackId: _fallbackProfileIdFor(index),
              loadWarnings: warnings,
            ),
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
      schemaVersion: _schemaVersionFromJson(json['schemaVersion'], warnings),
      profiles: profiles,
      loadWarnings: warnings,
    );
  }
}

int _schemaVersionFromJson(
  Object? rawValue,
  List<TerminalProfileLoadWarning> warnings,
) {
  if (rawValue == null) {
    return 1;
  }
  if (rawValue is num && rawValue.isFinite && rawValue > 0) {
    return rawValue.toInt();
  }
  warnings.add(
    TerminalProfileLoadWarning(
      profileId: 'document',
      profileName: 'Profiles document',
      path: 'schemaVersion',
      rawValueSummary: _rawValueSummary(rawValue),
      fallbackSummary: 'used schema version 1',
    ),
  );
  return 1;
}

Map<String, Object?> _dynamicProfileToProfileJson(
  Map<String, Object?> dynamicProfile,
) {
  final guid = _stringOrNull(dynamicProfile['Guid'])?.trim();
  final name = _stringOrNull(dynamicProfile['Name'])?.trim();
  final command = _stringOrNull(dynamicProfile['Command'])?.trim();
  final customCommand = _stringOrNull(
    dynamicProfile['Custom Command'],
  )?.trim().toLowerCase();
  final cwd = _stringOrNull(dynamicProfile['Working Directory'])?.trim();
  final rawTags = dynamicProfile['Tags'] ?? dynamicProfile['tags'];
  final tags = <String>[];
  if (rawTags is List) {
    for (final rawTag in rawTags) {
      final tag = _stringOrNull(rawTag)?.trim();
      if (tag != null && tag.isNotEmpty) {
        tags.add(tag);
      }
    }
  }
  tags.add('Dynamic');
  final launch = <String, Object?>{};
  if (customCommand == 'yes' ||
      customCommand == 'true' ||
      customCommand == '1') {
    if (command != null && command.isNotEmpty) {
      launch['program'] = '/bin/sh';
      launch['args'] = <String>['-lc', command];
    }
  }
  if (cwd != null && cwd.isNotEmpty) {
    launch['cwd'] = cwd;
  }
  return <String, Object?>{
    if (guid != null && guid.isNotEmpty) 'id': guid,
    if (name != null && name.isNotEmpty) 'name': name,
    'tags': tags.toSet().toList(growable: false),
    if (launch.isNotEmpty) 'launch': launch,
  };
}

TerminalProfile defaultTerminalProfile() {
  return TerminalProfile(
    id: 'default',
    name: 'Local Shell',
    shell: const String.fromEnvironment(
      'IANVS_DEFAULT_SHELL',
      defaultValue: '/bin/zsh',
    ),
    args: const ['-l'],
  );
}

TerminalProfile vt220TerminalProfile() {
  return TerminalProfile(
    id: 'vt220',
    name: 'Strict VT220',
    shell: const String.fromEnvironment(
      'IANVS_DEFAULT_SHELL',
      defaultValue: '/bin/zsh',
    ),
    args: const ['-l'],
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

List<String> _profileTagsFromJson(
  Object? rawValue,
  _TerminalProfileWarningSink warningSink,
) {
  if (rawValue == null) {
    return const [];
  }
  if (rawValue is String) {
    return _normalizeProfileTags(rawValue.split(','));
  }
  if (rawValue is List) {
    final tags = <String>[];
    for (var index = 0; index < rawValue.length; index += 1) {
      final entry = rawValue[index];
      if (entry is String) {
        tags.add(entry);
        continue;
      }
      warningSink.add(
        path: 'tags[$index]',
        rawValue: entry,
        fallbackSummary: 'ignored invalid tag entry',
      );
    }
    return _normalizeProfileTags(tags);
  }

  warningSink.add(
    path: 'tags',
    rawValue: rawValue,
    fallbackSummary: 'used no tags',
  );
  return const [];
}

List<String> _normalizeProfileTags(Iterable<String> tags) {
  final normalized = <String>[];
  final seen = <String>{};
  for (final tag in tags) {
    final trimmed = tag.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final lookup = trimmed.toLowerCase();
    if (!seen.add(lookup)) {
      continue;
    }
    normalized.add(trimmed);
  }
  return List.unmodifiable(normalized);
}

List<TerminalProfileTrigger> _profileTriggersFromJson(
  Object? rawValue,
  _TerminalProfileWarningSink warningSink,
) {
  if (rawValue == null) {
    return const [];
  }
  if (rawValue is! List) {
    warningSink.add(
      path: 'triggers',
      rawValue: rawValue,
      fallbackSummary: 'used no triggers',
    );
    return const [];
  }

  final triggers = <TerminalProfileTrigger>[];
  for (var index = 0; index < rawValue.length; index += 1) {
    final rawEntry = rawValue[index];
    if (rawEntry is! Map) {
      warningSink.add(
        path: 'triggers[$index]',
        rawValue: rawEntry,
        fallbackSummary: 'ignored invalid trigger entry',
      );
      continue;
    }
    final map = _asStringMap(rawEntry)!;
    final pattern = _stringOrNull(map['pattern'])?.trim();
    if (pattern == null || pattern.isEmpty) {
      warningSink.add(
        path: 'triggers[$index].pattern',
        rawValue: map['pattern'],
        fallbackSummary: 'ignored trigger without a pattern',
      );
      continue;
    }
    if (!_validRegex(pattern)) {
      warningSink.add(
        path: 'triggers[$index].pattern',
        rawValue: pattern,
        fallbackSummary: 'ignored invalid trigger regex',
      );
      continue;
    }
    final action = _triggerActionFromJson(map['action']);
    if (action == null) {
      warningSink.add(
        path: 'triggers[$index].action',
        rawValue: map['action'],
        fallbackSummary: 'used notify action',
      );
    }
    final rawTriggerValue = map['value'] ?? map['text'];
    final value = _stringOrNull(rawTriggerValue);
    if ((action ?? TerminalProfileTriggerAction.notify) ==
            TerminalProfileTriggerAction.sendText &&
        (value == null || value.isEmpty)) {
      warningSink.add(
        path: 'triggers[$index].value',
        rawValue: rawTriggerValue,
        fallbackSummary: 'ignored send-text trigger without a value',
      );
      continue;
    }
    final rawCaseSensitive = map['caseSensitive'];
    final caseSensitive = rawCaseSensitive is bool ? rawCaseSensitive : true;
    if (rawCaseSensitive != null && rawCaseSensitive is! bool) {
      warningSink.add(
        path: 'triggers[$index].caseSensitive',
        rawValue: rawCaseSensitive,
        fallbackSummary: 'used case-sensitive matching',
      );
    }
    triggers.add(
      TerminalProfileTrigger(
        pattern: pattern,
        action: action ?? TerminalProfileTriggerAction.notify,
        value: value,
        caseSensitive: caseSensitive,
      ),
    );
  }
  return List.unmodifiable(triggers);
}

List<TerminalProfileSwitchRule> _profileSwitchRulesFromJson(
  Object? rawValue,
  _TerminalProfileWarningSink warningSink,
) {
  if (rawValue == null) {
    return const [];
  }
  if (rawValue is! List) {
    warningSink.add(
      path: 'automaticProfileSwitching',
      rawValue: rawValue,
      fallbackSummary: 'used no automatic profile switching rules',
    );
    return const [];
  }

  final rules = <TerminalProfileSwitchRule>[];
  for (var index = 0; index < rawValue.length; index += 1) {
    final rawEntry = rawValue[index];
    if (rawEntry is! Map) {
      warningSink.add(
        path: 'automaticProfileSwitching[$index]',
        rawValue: rawEntry,
        fallbackSummary: 'ignored invalid switching rule entry',
      );
      continue;
    }
    final map = _asStringMap(rawEntry)!;
    final kind = _switchRuleKindFromJson(map['kind'] ?? map['type']);
    if (kind == null) {
      warningSink.add(
        path: 'automaticProfileSwitching[$index].kind',
        rawValue: map['kind'] ?? map['type'],
        fallbackSummary: 'ignored switching rule with invalid kind',
      );
      continue;
    }
    final pattern = _stringOrNull(map['pattern'] ?? map['value'])?.trim();
    if (pattern == null || pattern.isEmpty) {
      warningSink.add(
        path: 'automaticProfileSwitching[$index].pattern',
        rawValue: map['pattern'] ?? map['value'],
        fallbackSummary: 'ignored switching rule without a pattern',
      );
      continue;
    }
    final rawCaseSensitive = map['caseSensitive'];
    final caseSensitive = rawCaseSensitive is bool ? rawCaseSensitive : false;
    if (rawCaseSensitive != null && rawCaseSensitive is! bool) {
      warningSink.add(
        path: 'automaticProfileSwitching[$index].caseSensitive',
        rawValue: rawCaseSensitive,
        fallbackSummary: 'used case-insensitive matching',
      );
    }
    rules.add(
      TerminalProfileSwitchRule(
        kind: kind,
        pattern: pattern,
        caseSensitive: caseSensitive,
      ),
    );
  }
  return List.unmodifiable(rules);
}

TerminalProfileTriggerAction? _triggerActionFromJson(Object? rawValue) {
  if (rawValue == null) {
    return TerminalProfileTriggerAction.notify;
  }
  final normalized = _stringOrNull(rawValue)?.trim().toLowerCase();
  return switch (normalized) {
    '' || 'notify' || 'notification' => TerminalProfileTriggerAction.notify,
    'send' ||
    'send_text' ||
    'sendtext' ||
    'respond' => TerminalProfileTriggerAction.sendText,
    _ => null,
  };
}

String _triggerActionToJson(TerminalProfileTriggerAction action) {
  return switch (action) {
    TerminalProfileTriggerAction.notify => 'notify',
    TerminalProfileTriggerAction.sendText => 'send_text',
  };
}

TerminalProfileSwitchRuleKind? _switchRuleKindFromJson(Object? rawValue) {
  final normalized = _stringOrNull(rawValue)?.trim().toLowerCase();
  return switch (normalized) {
    'host' || 'hostname' => TerminalProfileSwitchRuleKind.hostname,
    'user' || 'username' => TerminalProfileSwitchRuleKind.username,
    'dir' ||
    'directory' ||
    'cwd' ||
    'path' => TerminalProfileSwitchRuleKind.directory,
    _ => null,
  };
}

String _switchRuleKindToJson(TerminalProfileSwitchRuleKind kind) {
  return switch (kind) {
    TerminalProfileSwitchRuleKind.hostname => 'hostname',
    TerminalProfileSwitchRuleKind.username => 'username',
    TerminalProfileSwitchRuleKind.directory => 'directory',
  };
}

bool _validRegex(String pattern) {
  try {
    RegExp(pattern);
    return true;
  } on FormatException {
    return false;
  }
}

TerminalProfile _normalizeBuiltInShellProfile(TerminalProfile profile) {
  if (profile.args.isNotEmpty) {
    return profile;
  }

  final defaultProfile = defaultTerminalProfile();
  if (profile.id == defaultProfile.id &&
      profile.shell == defaultProfile.shell) {
    return profile.copyWith(args: defaultProfile.args);
  }

  final vt220Profile = vt220TerminalProfile();
  if (profile.id == vt220Profile.id &&
      profile.shell == vt220Profile.shell &&
      profile.terminalEmulation == vt220Profile.terminalEmulation) {
    return profile.copyWith(args: vt220Profile.args);
  }

  return profile;
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
