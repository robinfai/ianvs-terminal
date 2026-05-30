import 'dart:convert';

import '../preferences/app_preferences_models.dart';
import '../shell/shell_action_registry.dart';

class LocalTerminalConfigDocument {
  const LocalTerminalConfigDocument({
    this.schemaVersion = currentSchemaVersion,
    this.defaultProfileId,
    this.appearance = const TerminalAppAppearance(),
    this.keybindings = const LocalTerminalKeybindingsConfig(),
    this.workspace = const LocalTerminalWorkspaceConfig(),
    this.clipboard = const LocalTerminalClipboardConfig(),
    this.paste = const LocalTerminalPasteConfig(),
    this.shellIntegration = const LocalTerminalShellIntegrationConfig(),
    this.notifications = const LocalTerminalNotificationsConfig(),
    this.hotkeyWindow = const LocalTerminalHotkeyWindowConfig(),
  });

  static const int currentSchemaVersion = 1;

  static const Set<String> forbiddenTopLevelKeys = {
    'ssh',
    'sshProfiles',
    'sshConfig',
    'remote',
    'remoteDomain',
    'remoteDomains',
    'sftp',
    'serial',
    'telnet',
  };

  final int schemaVersion;
  final String? defaultProfileId;
  final TerminalAppAppearance appearance;
  final LocalTerminalKeybindingsConfig keybindings;
  final LocalTerminalWorkspaceConfig workspace;
  final LocalTerminalClipboardConfig clipboard;
  final LocalTerminalPasteConfig paste;
  final LocalTerminalShellIntegrationConfig shellIntegration;
  final LocalTerminalNotificationsConfig notifications;
  final LocalTerminalHotkeyWindowConfig hotkeyWindow;

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'defaultProfileId': defaultProfileId,
      'appearance': appearance.toJson(),
      'keybindings': keybindings.toJson(),
      'workspace': workspace.toJson(),
      'clipboard': clipboard.toJson(),
      'paste': paste.toJson(),
      'shellIntegration': shellIntegration.toJson(),
      'notifications': notifications.toJson(),
      'hotkeyWindow': hotkeyWindow.toJson(),
    };
  }

  String encode() => jsonEncode(toJson());

  static LocalTerminalConfigDocument decode(String raw) {
    final decoded = jsonDecode(raw);
    final json = _objectMap(decoded);
    if (json == null) {
      throw const FormatException('Local config JSON must be an object.');
    }
    return fromJson(json.cast<String, Object?>());
  }

  static LocalTerminalConfigDocument fromJson(Map<String, Object?> json) {
    _rejectForbiddenTopLevelKeys(json);

    return LocalTerminalConfigDocument(
      schemaVersion: _schemaVersionFromJson(
        json['schemaVersion'],
        currentSchemaVersion,
      ),
      defaultProfileId: _stringOrNull(json['defaultProfileId']),
      appearance: TerminalAppAppearance.fromJson(
        _objectMap(json['appearance']),
      ),
      keybindings: LocalTerminalKeybindingsConfig.fromJson(
        _objectMap(json['keybindings']),
      ),
      workspace: LocalTerminalWorkspaceConfig.fromJson(
        _objectMap(json['workspace']),
      ),
      clipboard: LocalTerminalClipboardConfig.fromJson(
        _objectMap(json['clipboard']),
      ),
      paste: LocalTerminalPasteConfig.fromJson(_objectMap(json['paste'])),
      shellIntegration: LocalTerminalShellIntegrationConfig.fromJson(
        _objectMap(json['shellIntegration']),
      ),
      notifications: LocalTerminalNotificationsConfig.fromJson(
        _objectMap(json['notifications']),
      ),
      hotkeyWindow: LocalTerminalHotkeyWindowConfig.fromJson(
        _objectMap(json['hotkeyWindow']),
      ),
    );
  }

  static int _schemaVersionFromJson(Object? value, int fallback) {
    return _intFromJson(value, fallback);
  }

  static void _rejectForbiddenTopLevelKeys(Map<String, Object?> json) {
    final forbidden = json.keys.where(forbiddenTopLevelKeys.contains).toList();
    if (forbidden.isEmpty) {
      return;
    }

    throw FormatException(
      'LocalTerminalConfig does not accept remote-only fields: '
      '${forbidden.join(', ')}',
    );
  }
}

class LocalTerminalKeybindingsConfig {
  const LocalTerminalKeybindingsConfig({
    this.disabledDefaultActions = const <TerminalActionId>{},
    this.overrides =
        const <TerminalActionId, LocalTerminalKeyBindingOverride>{},
  });

  final Set<TerminalActionId> disabledDefaultActions;
  final Map<TerminalActionId, LocalTerminalKeyBindingOverride> overrides;

  Map<String, Object?> toJson() {
    return {
      'disabledDefaultActions': disabledDefaultActions
          .map((actionId) => actionId.name)
          .toList(growable: false),
      'overrides': {
        for (final entry in overrides.entries)
          entry.key.name: entry.value.toJson(),
      },
    };
  }

  static LocalTerminalKeybindingsConfig fromJson(Map<Object?, Object?>? json) {
    if (json == null) {
      return const LocalTerminalKeybindingsConfig();
    }

    return LocalTerminalKeybindingsConfig(
      disabledDefaultActions: _actionIdSet(json['disabledDefaultActions']),
      overrides: _actionBindingOverrides(json['overrides']),
    );
  }
}

class LocalTerminalKeyBindingOverride {
  const LocalTerminalKeyBindingOverride({this.enabled = true, this.binding});

  final bool enabled;
  final LocalTerminalKeyBinding? binding;

  Map<String, Object?> toJson() {
    return {'enabled': enabled, 'binding': binding?.toJson()};
  }

  static LocalTerminalKeyBindingOverride fromJson(Map<Object?, Object?>? json) {
    if (json == null) {
      return const LocalTerminalKeyBindingOverride();
    }

    return LocalTerminalKeyBindingOverride(
      enabled: _boolFromJson(json['enabled'], true),
      binding: LocalTerminalKeyBinding.fromJson(_objectMap(json['binding'])),
    );
  }
}

class LocalTerminalKeyBinding {
  const LocalTerminalKeyBinding({
    required this.scope,
    required this.key,
    this.meta = false,
    this.control = false,
    this.shift = false,
    this.alt = false,
  });

  final TerminalKeyBindingScope scope;
  final String key;
  final bool meta;
  final bool control;
  final bool shift;
  final bool alt;

  String get signature {
    final parts = <String>[
      scope.name,
      if (meta) 'meta',
      if (control) 'control',
      if (shift) 'shift',
      if (alt) 'alt',
      _normalizeKeySignatureLabel(key),
    ];
    return parts.join('+');
  }

  Map<String, Object?> toJson() {
    return {
      'scope': scope.name,
      'key': key,
      'meta': meta,
      'control': control,
      'shift': shift,
      'alt': alt,
    };
  }

  static LocalTerminalKeyBinding? fromJson(Map<Object?, Object?>? json) {
    if (json == null) {
      return null;
    }

    return LocalTerminalKeyBinding(
      scope: _keyBindingScope(json['scope']),
      key: _stringOrNull(json['key']) ?? '',
      meta: _boolFromJson(json['meta'], false),
      control: _boolFromJson(json['control'], false),
      shift: _boolFromJson(json['shift'], false),
      alt: _boolFromJson(json['alt'], false),
    );
  }
}

class LocalTerminalWorkspaceConfig {
  const LocalTerminalWorkspaceConfig({this.restoreLayout = false});

  final bool restoreLayout;

  Map<String, Object?> toJson() {
    return {'restoreLayout': restoreLayout};
  }

  static LocalTerminalWorkspaceConfig fromJson(Map<Object?, Object?>? json) {
    return LocalTerminalWorkspaceConfig(
      restoreLayout: _boolFromJson(json?['restoreLayout'], false),
    );
  }
}

class LocalTerminalClipboardConfig {
  const LocalTerminalClipboardConfig({
    this.copyOnSelect = false,
    this.osc52 = LocalTerminalOsc52Policy.profile,
  });

  final bool copyOnSelect;
  final LocalTerminalOsc52Policy osc52;

  Map<String, Object?> toJson() {
    return {'copyOnSelect': copyOnSelect, 'osc52': osc52.name};
  }

  static LocalTerminalClipboardConfig fromJson(Map<Object?, Object?>? json) {
    return LocalTerminalClipboardConfig(
      copyOnSelect: _boolFromJson(json?['copyOnSelect'], false),
      osc52: _osc52Policy(json?['osc52']),
    );
  }
}

enum LocalTerminalOsc52Policy { disabled, profile, allow }

class LocalTerminalPasteConfig {
  const LocalTerminalPasteConfig({
    this.bracketedPaste = LocalTerminalBracketedPastePolicy.auto,
    this.confirmLargePaste = true,
    this.confirmMultilinePaste = true,
    this.historySize = 50,
  });

  final LocalTerminalBracketedPastePolicy bracketedPaste;
  final bool confirmLargePaste;
  final bool confirmMultilinePaste;
  final int historySize;

  Map<String, Object?> toJson() {
    return {
      'bracketedPaste': bracketedPaste.name,
      'confirmLargePaste': confirmLargePaste,
      'confirmMultilinePaste': confirmMultilinePaste,
      'historySize': historySize,
    };
  }

  static LocalTerminalPasteConfig fromJson(Map<Object?, Object?>? json) {
    return LocalTerminalPasteConfig(
      bracketedPaste: _bracketedPastePolicy(json?['bracketedPaste']),
      confirmLargePaste: _boolFromJson(json?['confirmLargePaste'], true),
      confirmMultilinePaste: _boolFromJson(
        json?['confirmMultilinePaste'],
        true,
      ),
      historySize: _intFromJson(json?['historySize'], 50),
    );
  }
}

enum LocalTerminalBracketedPastePolicy { auto, force, plain }

class LocalTerminalShellIntegrationConfig {
  const LocalTerminalShellIntegrationConfig({this.enabled = true});

  final bool enabled;

  Map<String, Object?> toJson() {
    return {'enabled': enabled};
  }

  static LocalTerminalShellIntegrationConfig fromJson(
    Map<Object?, Object?>? json,
  ) {
    return LocalTerminalShellIntegrationConfig(
      enabled: _boolFromJson(json?['enabled'], true),
    );
  }
}

class LocalTerminalNotificationsConfig {
  const LocalTerminalNotificationsConfig({this.enabled = true});

  final bool enabled;

  Map<String, Object?> toJson() {
    return {'enabled': enabled};
  }

  static LocalTerminalNotificationsConfig fromJson(
    Map<Object?, Object?>? json,
  ) {
    return LocalTerminalNotificationsConfig(
      enabled: _boolFromJson(json?['enabled'], true),
    );
  }
}

class LocalTerminalHotkeyWindowConfig {
  const LocalTerminalHotkeyWindowConfig({this.enabled = false});

  final bool enabled;

  Map<String, Object?> toJson() {
    return {'enabled': enabled};
  }

  static LocalTerminalHotkeyWindowConfig fromJson(Map<Object?, Object?>? json) {
    return LocalTerminalHotkeyWindowConfig(
      enabled: _boolFromJson(json?['enabled'], false),
    );
  }
}

Map<Object?, Object?>? _objectMap(Object? value) {
  if (value is Map<Object?, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.cast<Object?, Object?>();
  }
  return null;
}

String? _stringOrNull(Object? value) {
  return value is String ? value : null;
}

bool _boolFromJson(Object? value, bool fallback) {
  return value is bool ? value : fallback;
}

int _intFromJson(Object? value, int fallback) {
  if (value is int) {
    return value;
  }
  if (value is num && value.isFinite) {
    return value.toInt();
  }
  return fallback;
}

Set<TerminalActionId> _actionIdSet(Object? value) {
  if (value is! List) {
    return const <TerminalActionId>{};
  }

  return value.map(_actionId).whereType<TerminalActionId>().toSet();
}

Map<TerminalActionId, LocalTerminalKeyBindingOverride> _actionBindingOverrides(
  Object? value,
) {
  final json = _objectMap(value);
  if (json == null) {
    return const <TerminalActionId, LocalTerminalKeyBindingOverride>{};
  }

  final overrides = <TerminalActionId, LocalTerminalKeyBindingOverride>{};
  for (final entry in json.entries) {
    final actionId = _actionId(entry.key);
    if (actionId == null) {
      continue;
    }
    overrides[actionId] = LocalTerminalKeyBindingOverride.fromJson(
      _objectMap(entry.value),
    );
  }
  return overrides;
}

TerminalActionId? _actionId(Object? value) {
  if (value is! String) {
    return null;
  }

  for (final actionId in TerminalActionId.values) {
    if (actionId.name == value) {
      return actionId;
    }
  }
  return null;
}

TerminalKeyBindingScope _keyBindingScope(Object? value) {
  if (value is String) {
    for (final scope in TerminalKeyBindingScope.values) {
      if (scope.name == value) {
        return scope;
      }
    }
  }
  return TerminalKeyBindingScope.terminalFocused;
}

LocalTerminalOsc52Policy _osc52Policy(Object? value) {
  if (value is String) {
    for (final policy in LocalTerminalOsc52Policy.values) {
      if (policy.name == value) {
        return policy;
      }
    }
  }
  return LocalTerminalOsc52Policy.profile;
}

LocalTerminalBracketedPastePolicy _bracketedPastePolicy(Object? value) {
  if (value is String) {
    for (final policy in LocalTerminalBracketedPastePolicy.values) {
      if (policy.name == value) {
        return policy;
      }
    }
  }
  return LocalTerminalBracketedPastePolicy.auto;
}

String _normalizeKeySignatureLabel(String value) {
  if (value.length == 4 && value.startsWith('Key')) {
    return 'Key ${value.substring(3)}';
  }
  return value;
}
