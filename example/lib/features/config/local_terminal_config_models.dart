import 'dart:convert';

import '../policies/local_terminal_policy_models.dart';
import '../preferences/app_preferences_models.dart';
import '../shell/shell_action_registry.dart';

const int maxLocalTerminalKeyBindingKeyLength = 64;
const int maxLocalTerminalReportVariableDecisions = 64;
final int _maxLocalTerminalKeyBindingEntriesToScan =
    TerminalActionId.values.length * 4;

class LocalTerminalConfigDocument {
  const LocalTerminalConfigDocument({
    this.schemaVersion = currentSchemaVersion,
    this.defaultProfileId,
    this.appearance = const TerminalAppAppearance(),
    this.keybindings = const LocalTerminalKeybindingsConfig(),
    this.layout = const LocalTerminalLayoutConfig(),
    this.clipboard = const LocalTerminalClipboardConfig(),
    this.hostActions = const LocalTerminalHostActionsConfig(),
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
  static const Set<String> _currentTopLevelKeys = {
    'schemaVersion',
    'defaultProfileId',
    'appearance',
    'keybindings',
    'layout',
    'clipboard',
    'hostActions',
    'paste',
    'shellIntegration',
    'notifications',
    'hotkeyWindow',
  };

  final int schemaVersion;
  final String? defaultProfileId;
  final TerminalAppAppearance appearance;
  final LocalTerminalKeybindingsConfig keybindings;
  final LocalTerminalLayoutConfig layout;
  final LocalTerminalClipboardConfig clipboard;
  final LocalTerminalHostActionsConfig hostActions;
  final LocalTerminalPasteConfig paste;
  final LocalTerminalShellIntegrationConfig shellIntegration;
  final LocalTerminalNotificationsConfig notifications;
  final LocalTerminalHotkeyWindowConfig hotkeyWindow;

  LocalTerminalConfigDocument copyWith({
    int? schemaVersion,
    Object? defaultProfileId = _localTerminalConfigNoChange,
    TerminalAppAppearance? appearance,
    LocalTerminalKeybindingsConfig? keybindings,
    LocalTerminalLayoutConfig? layout,
    LocalTerminalClipboardConfig? clipboard,
    LocalTerminalHostActionsConfig? hostActions,
    LocalTerminalPasteConfig? paste,
    LocalTerminalShellIntegrationConfig? shellIntegration,
    LocalTerminalNotificationsConfig? notifications,
    LocalTerminalHotkeyWindowConfig? hotkeyWindow,
  }) {
    return LocalTerminalConfigDocument(
      schemaVersion: currentSchemaVersion,
      defaultProfileId:
          identical(defaultProfileId, _localTerminalConfigNoChange)
          ? this.defaultProfileId
          : _nonEmptyTrimmedStringOrNull(defaultProfileId as String?),
      appearance: appearance ?? this.appearance,
      keybindings: keybindings ?? this.keybindings,
      layout: layout ?? this.layout,
      clipboard: clipboard ?? this.clipboard,
      hostActions: hostActions ?? this.hostActions,
      paste: paste ?? this.paste,
      shellIntegration: shellIntegration ?? this.shellIntegration,
      notifications: notifications ?? this.notifications,
      hotkeyWindow: hotkeyWindow ?? this.hotkeyWindow,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': currentSchemaVersion,
      'defaultProfileId': _nonEmptyTrimmedStringOrNull(defaultProfileId),
      'appearance': appearance.toJson(),
      'keybindings': keybindings.toJson(),
      'layout': layout.toJson(),
      'clipboard': clipboard.toJson(),
      'hostActions': hostActions.toJson(),
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
    _validateCurrentSchema(json['schemaVersion']);
    _rejectForbiddenTopLevelKeys(json);
    final unknown = json.keys.where(
      (key) => !_currentTopLevelKeys.contains(key),
    );
    if (unknown.isNotEmpty) {
      throw FormatException(
        'LocalTerminalConfig contains unknown fields: ${unknown.join(', ')}',
      );
    }

    return LocalTerminalConfigDocument(
      schemaVersion: currentSchemaVersion,
      defaultProfileId: _nonEmptyTrimmedStringOrNull(json['defaultProfileId']),
      appearance: TerminalAppAppearance.fromJson(
        _objectMap(json['appearance']),
      ),
      keybindings: LocalTerminalKeybindingsConfig.fromJson(
        _objectMap(json['keybindings']),
      ),
      layout: LocalTerminalLayoutConfig.fromJson(_objectMap(json['layout'])),
      clipboard: LocalTerminalClipboardConfig.fromJson(
        _objectMap(json['clipboard']),
      ),
      hostActions: LocalTerminalHostActionsConfig.fromJson(
        _objectMap(json['hostActions']),
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

  static void _validateCurrentSchema(Object? value) {
    if (value == null) {
      throw const UnsupportedLocalTerminalConfigSchemaVersion(null);
    }
    if (value is! int) {
      throw const FormatException(
        'LocalTerminalConfig schemaVersion must be an integer.',
      );
    }
    if (value != currentSchemaVersion) {
      throw UnsupportedLocalTerminalConfigSchemaVersion(value);
    }
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

final class UnsupportedLocalTerminalConfigSchemaVersion implements Exception {
  const UnsupportedLocalTerminalConfigSchemaVersion(this.version);

  final Object? version;

  @override
  String toString() =>
      'Unsupported local terminal config schema version: $version '
      '(current: ${LocalTerminalConfigDocument.currentSchemaVersion})';
}

class LocalTerminalKeybindingsConfig {
  const LocalTerminalKeybindingsConfig({
    this.disabledDefaultActions = const <TerminalActionId>{},
    this.overrides =
        const <TerminalActionId, LocalTerminalKeyBindingOverride>{},
  });

  final Set<TerminalActionId> disabledDefaultActions;
  final Map<TerminalActionId, LocalTerminalKeyBindingOverride> overrides;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is LocalTerminalKeybindingsConfig &&
        _setsEqual(disabledDefaultActions, other.disabledDefaultActions) &&
        _mapsEqual(overrides, other.overrides);
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(disabledDefaultActions),
    Object.hashAllUnordered(
      overrides.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );

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

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LocalTerminalKeyBindingOverride &&
            enabled == other.enabled &&
            binding == other.binding;
  }

  @override
  int get hashCode => Object.hash(enabled, binding);

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

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LocalTerminalKeyBinding &&
            scope == other.scope &&
            key == other.key &&
            meta == other.meta &&
            control == other.control &&
            shift == other.shift &&
            alt == other.alt;
  }

  @override
  int get hashCode => Object.hash(scope, key, meta, control, shift, alt);

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

    final key = _boundedNonEmptyTrimmedStringOrNull(
      json['key'],
      maxLength: maxLocalTerminalKeyBindingKeyLength,
    );
    if (key == null) {
      return null;
    }

    return LocalTerminalKeyBinding(
      scope: _keyBindingScope(json['scope']),
      key: key,
      meta: _boolFromJson(json['meta'], false),
      control: _boolFromJson(json['control'], false),
      shift: _boolFromJson(json['shift'], false),
      alt: _boolFromJson(json['alt'], false),
    );
  }
}

class LocalTerminalLayoutConfig {
  const LocalTerminalLayoutConfig({this.restoreLayout = false});

  final bool restoreLayout;

  Map<String, Object?> toJson() {
    return {'restoreLayout': restoreLayout};
  }

  static LocalTerminalLayoutConfig fromJson(Map<Object?, Object?>? json) {
    return LocalTerminalLayoutConfig(
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

  LocalTerminalClipboardConfig copyWith({
    bool? copyOnSelect,
    LocalTerminalOsc52Policy? osc52,
  }) {
    return LocalTerminalClipboardConfig(
      copyOnSelect: copyOnSelect ?? this.copyOnSelect,
      osc52: osc52 ?? this.osc52,
    );
  }

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

enum LocalTerminalOsc52Policy { disabled, profile, allow, ask }

/// Persistent policy for terminal escape sequences that request host effects.
class LocalTerminalHostActionsConfig {
  const LocalTerminalHostActionsConfig({
    this.osc1337OpenUrl = LocalTerminalOpenUrlPolicy.ask,
    this.osc1337RequestAttention = LocalTerminalRequestAttentionPolicy.disabled,
    this.osc1337ReportVariables =
        const <String, LocalTerminalReportVariablePolicy>{},
  });

  final LocalTerminalOpenUrlPolicy osc1337OpenUrl;
  final LocalTerminalRequestAttentionPolicy osc1337RequestAttention;
  final Map<String, LocalTerminalReportVariablePolicy> osc1337ReportVariables;

  LocalTerminalHostActionsConfig copyWith({
    LocalTerminalOpenUrlPolicy? osc1337OpenUrl,
    LocalTerminalRequestAttentionPolicy? osc1337RequestAttention,
    Map<String, LocalTerminalReportVariablePolicy>? osc1337ReportVariables,
  }) {
    return LocalTerminalHostActionsConfig(
      osc1337OpenUrl: osc1337OpenUrl ?? this.osc1337OpenUrl,
      osc1337RequestAttention:
          osc1337RequestAttention ?? this.osc1337RequestAttention,
      osc1337ReportVariables: osc1337ReportVariables == null
          ? this.osc1337ReportVariables
          : Map.unmodifiable(osc1337ReportVariables),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'osc1337OpenUrl': osc1337OpenUrl.name,
      'osc1337RequestAttention': osc1337RequestAttention.name,
      'osc1337ReportVariables': {
        for (final entry
            in osc1337ReportVariables.entries
                .where(
                  (entry) =>
                      isLocalTerminalReportVariableNameSupported(entry.key),
                )
                .take(maxLocalTerminalReportVariableDecisions))
          entry.key: entry.value.name,
      },
    };
  }

  static LocalTerminalHostActionsConfig fromJson(Map<Object?, Object?>? json) {
    return LocalTerminalHostActionsConfig(
      osc1337OpenUrl: _openUrlPolicy(json?['osc1337OpenUrl']),
      osc1337RequestAttention: _requestAttentionPolicy(
        json?['osc1337RequestAttention'],
      ),
      osc1337ReportVariables: _reportVariablePolicies(
        json?['osc1337ReportVariables'],
      ),
    );
  }
}

enum LocalTerminalOpenUrlPolicy { disabled, ask }

enum LocalTerminalRequestAttentionPolicy { disabled, allow }

enum LocalTerminalReportVariablePolicy { deny, allow }

bool isLocalTerminalReportVariableNameSupported(String name) {
  const sessionVariables = <String>{
    'session.name',
    'session.terminalIconName',
    'session.terminalWindowName',
    'session.columns',
    'session.rows',
    'session.hostname',
    'session.lastCommand',
    'session.username',
    'session.path',
    'session.shell',
    'session.badge',
    'session.profileName',
  };
  if (name.isEmpty ||
      utf8.encode(name).length > 256 ||
      name.runes.any((rune) => rune < 0x20 || (rune >= 0x7f && rune <= 0x9f))) {
    return false;
  }
  if (sessionVariables.contains(name)) {
    return true;
  }
  final userName = name.startsWith('user.') ? name.substring(5) : null;
  return userName != null && userName.isNotEmpty && userName.runes.length <= 80;
}

class LocalTerminalPasteConfig {
  const LocalTerminalPasteConfig({
    this.bracketedPaste = LocalTerminalBracketedPastePolicy.auto,
    this.confirmLargePaste = true,
    this.confirmMultilinePaste = true,
    this.historySize = defaultLocalTerminalPasteHistoryEntries,
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
      historySize: _pasteHistorySizeFromJson(json?['historySize']),
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
  const LocalTerminalNotificationsConfig({
    bool enabled = true,
    bool? commandFinished,
    bool? bell,
    bool? activity,
  }) : enabled = enabled,
       commandFinished = commandFinished ?? enabled,
       bell = bell ?? enabled,
       activity = activity ?? enabled;

  final bool enabled;
  final bool commandFinished;
  final bool bell;
  final bool activity;

  Map<String, Object?> toJson() {
    return {
      'enabled': enabled,
      'commandFinished': commandFinished,
      'bell': bell,
      'activity': activity,
    };
  }

  static LocalTerminalNotificationsConfig fromJson(
    Map<Object?, Object?>? json,
  ) {
    final enabled = _boolFromJson(json?['enabled'], true);
    return LocalTerminalNotificationsConfig(
      enabled: enabled,
      commandFinished: _boolOrNull(json?['commandFinished']) ?? enabled,
      bell: _boolOrNull(json?['bell']) ?? enabled,
      activity: _boolOrNull(json?['activity']) ?? enabled,
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

String? _nonEmptyTrimmedStringOrNull(Object? value) {
  final text = _stringOrNull(value)?.trim();
  return text == null || text.isEmpty ? null : text;
}

String? _boundedNonEmptyTrimmedStringOrNull(
  Object? value, {
  required int maxLength,
}) {
  final text = _nonEmptyTrimmedStringOrNull(value);
  if (text == null || text.length > maxLength) {
    return null;
  }
  return text;
}

bool _boolFromJson(Object? value, bool fallback) {
  return value is bool ? value : fallback;
}

bool? _boolOrNull(Object? value) {
  return value is bool ? value : null;
}

int? _wholeIntOrNull(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num && value.isFinite) {
    final parsed = value.toInt();
    if (value == parsed) {
      return parsed;
    }
  }
  return null;
}

int _nonNegativeIntFromJson(Object? value, int fallback) {
  final parsed = _wholeIntOrNull(value);
  return parsed == null || parsed < 0 ? fallback : parsed;
}

int _pasteHistorySizeFromJson(Object? value) {
  final parsed = _nonNegativeIntFromJson(
    value,
    defaultLocalTerminalPasteHistoryEntries,
  );
  return parsed > defaultLocalTerminalPasteHistoryEntries
      ? defaultLocalTerminalPasteHistoryEntries
      : parsed;
}

Set<TerminalActionId> _actionIdSet(Object? value) {
  if (value is! List) {
    return const <TerminalActionId>{};
  }

  return value
      .take(_maxLocalTerminalKeyBindingEntriesToScan)
      .map(_actionId)
      .whereType<TerminalActionId>()
      .toSet();
}

Map<TerminalActionId, LocalTerminalKeyBindingOverride> _actionBindingOverrides(
  Object? value,
) {
  final json = _objectMap(value);
  if (json == null) {
    return const <TerminalActionId, LocalTerminalKeyBindingOverride>{};
  }

  final overrides = <TerminalActionId, LocalTerminalKeyBindingOverride>{};
  for (final entry in json.entries.take(
    _maxLocalTerminalKeyBindingEntriesToScan,
  )) {
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

  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    return null;
  }
  for (final actionId in TerminalActionId.values) {
    if (actionId.name.toLowerCase() == normalized) {
      return actionId;
    }
  }
  return null;
}

TerminalKeyBindingScope _keyBindingScope(Object? value) {
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    for (final scope in TerminalKeyBindingScope.values) {
      if (scope.name.toLowerCase() == normalized) {
        return scope;
      }
    }
  }
  return TerminalKeyBindingScope.terminalFocused;
}

LocalTerminalOsc52Policy _osc52Policy(Object? value) {
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'deny') {
      return LocalTerminalOsc52Policy.disabled;
    }
    for (final policy in LocalTerminalOsc52Policy.values) {
      if (policy.name == normalized) {
        return policy;
      }
    }
  }
  return LocalTerminalOsc52Policy.profile;
}

LocalTerminalOpenUrlPolicy _openUrlPolicy(Object? value) {
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'deny') {
      return LocalTerminalOpenUrlPolicy.disabled;
    }
    for (final policy in LocalTerminalOpenUrlPolicy.values) {
      if (policy.name == normalized) {
        return policy;
      }
    }
  }
  return LocalTerminalOpenUrlPolicy.ask;
}

LocalTerminalRequestAttentionPolicy _requestAttentionPolicy(Object? value) {
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'deny') {
      return LocalTerminalRequestAttentionPolicy.disabled;
    }
    for (final policy in LocalTerminalRequestAttentionPolicy.values) {
      if (policy.name == normalized) {
        return policy;
      }
    }
  }
  return LocalTerminalRequestAttentionPolicy.disabled;
}

Map<String, LocalTerminalReportVariablePolicy> _reportVariablePolicies(
  Object? value,
) {
  if (value is! Map) {
    return const <String, LocalTerminalReportVariablePolicy>{};
  }
  final result = <String, LocalTerminalReportVariablePolicy>{};
  for (final entry in value.entries) {
    if (result.length >= maxLocalTerminalReportVariableDecisions) {
      break;
    }
    final name = entry.key;
    final rawPolicy = entry.value;
    if (name is! String ||
        !isLocalTerminalReportVariableNameSupported(name) ||
        rawPolicy is! String) {
      continue;
    }
    final normalized = rawPolicy.trim().toLowerCase();
    final policy = switch (normalized) {
      'allow' => LocalTerminalReportVariablePolicy.allow,
      'deny' || 'disabled' => LocalTerminalReportVariablePolicy.deny,
      _ => null,
    };
    if (policy != null) {
      result[name] = policy;
    }
  }
  return Map.unmodifiable(result);
}

LocalTerminalBracketedPastePolicy _bracketedPastePolicy(Object? value) {
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    for (final policy in LocalTerminalBracketedPastePolicy.values) {
      if (policy.name == normalized) {
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

bool _setsEqual<T>(Set<T> left, Set<T> right) {
  return left.length == right.length && left.containsAll(right);
}

bool _mapsEqual<K, V>(Map<K, V> left, Map<K, V> right) {
  if (left.length != right.length) {
    return false;
  }
  for (final entry in left.entries) {
    if (!right.containsKey(entry.key) || right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

const Object _localTerminalConfigNoChange = Object();
