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
    this.universalInput = const LocalTerminalUniversalInputConfig(),
    this.commandCenter = const LocalTerminalCommandCenterConfig(),
    this.commandBlocksHistory = const LocalTerminalCommandBlocksHistoryConfig(),
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
  final LocalTerminalUniversalInputConfig universalInput;
  final LocalTerminalCommandCenterConfig commandCenter;
  final LocalTerminalCommandBlocksHistoryConfig commandBlocksHistory;

  LocalTerminalConfigDocument copyWith({
    int? schemaVersion,
    Object? defaultProfileId = _localTerminalConfigNoChange,
    TerminalAppAppearance? appearance,
    LocalTerminalKeybindingsConfig? keybindings,
    LocalTerminalWorkspaceConfig? workspace,
    LocalTerminalClipboardConfig? clipboard,
    LocalTerminalPasteConfig? paste,
    LocalTerminalShellIntegrationConfig? shellIntegration,
    LocalTerminalNotificationsConfig? notifications,
    LocalTerminalHotkeyWindowConfig? hotkeyWindow,
    LocalTerminalUniversalInputConfig? universalInput,
    LocalTerminalCommandCenterConfig? commandCenter,
    LocalTerminalCommandBlocksHistoryConfig? commandBlocksHistory,
  }) {
    return LocalTerminalConfigDocument(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      defaultProfileId:
          identical(defaultProfileId, _localTerminalConfigNoChange)
          ? this.defaultProfileId
          : defaultProfileId as String?,
      appearance: appearance ?? this.appearance,
      keybindings: keybindings ?? this.keybindings,
      workspace: workspace ?? this.workspace,
      clipboard: clipboard ?? this.clipboard,
      paste: paste ?? this.paste,
      shellIntegration: shellIntegration ?? this.shellIntegration,
      notifications: notifications ?? this.notifications,
      hotkeyWindow: hotkeyWindow ?? this.hotkeyWindow,
      universalInput: universalInput ?? this.universalInput,
      commandCenter: commandCenter ?? this.commandCenter,
      commandBlocksHistory: commandBlocksHistory ?? this.commandBlocksHistory,
    );
  }

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
      'universalInput': universalInput.toJson(),
      'commandCenter': commandCenter.toJson(),
      'commandBlocksHistory': commandBlocksHistory.toJson(),
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
      defaultProfileId: _nonEmptyTrimmedStringOrNull(json['defaultProfileId']),
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
      universalInput: LocalTerminalUniversalInputConfig.fromJson(
        _objectMap(json['universalInput']),
      ),
      commandCenter: LocalTerminalCommandCenterConfig.fromJson(
        _objectMap(json['commandCenter']),
      ),
      commandBlocksHistory: LocalTerminalCommandBlocksHistoryConfig.fromJson(
        _objectMap(json['commandBlocksHistory']),
      ),
    );
  }

  static int _schemaVersionFromJson(Object? value, int fallback) {
    return _positiveWholeIntFromJson(value, fallback);
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

    final key = _nonEmptyTrimmedStringOrNull(json['key']);
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
      historySize: _nonNegativeIntFromJson(json?['historySize'], 50),
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

class LocalTerminalCommandCenterConfig {
  const LocalTerminalCommandCenterConfig({
    this.enabled = false,
    this.historySearch = false,
    this.commandBlocks = false,
    this.commandBar = false,
    this.contextChips = false,
    this.reviewEntrypoints = false,
    this.verificationDiagnostics = false,
    this.agentCenter = false,
    this.agentConversation = false,
    this.agentContext = false,
    this.agentCommandProposals = false,
    this.agentProviderDraft = false,
    this.agentCommandSearchActions = false,
  });

  final bool enabled;
  final bool historySearch;
  final bool commandBlocks;
  final bool commandBar;
  final bool contextChips;
  final bool reviewEntrypoints;
  final bool verificationDiagnostics;
  final bool agentCenter;
  final bool agentConversation;
  final bool agentContext;
  final bool agentCommandProposals;
  final bool agentProviderDraft;
  final bool agentCommandSearchActions;

  Map<String, Object?> toJson() {
    return {
      'enabled': enabled,
      'historySearch': historySearch,
      'commandBlocks': commandBlocks,
      'commandBar': commandBar,
      'contextChips': contextChips,
      'reviewEntrypoints': reviewEntrypoints,
      'verificationDiagnostics': verificationDiagnostics,
      'agentCenter': agentCenter,
      'agentConversation': agentConversation,
      'agentContext': agentContext,
      'agentCommandProposals': agentCommandProposals,
      'agentProviderDraft': agentProviderDraft,
      'agentCommandSearchActions': agentCommandSearchActions,
    };
  }

  static LocalTerminalCommandCenterConfig fromJson(
    Map<Object?, Object?>? json,
  ) {
    return LocalTerminalCommandCenterConfig(
      enabled: _boolFromJson(json?['enabled'], false),
      historySearch: _boolFromJson(json?['historySearch'], false),
      commandBlocks: _boolFromJson(json?['commandBlocks'], false),
      commandBar: _boolFromJson(json?['commandBar'], false),
      contextChips: _boolFromJson(json?['contextChips'], false),
      reviewEntrypoints: _boolFromJson(json?['reviewEntrypoints'], false),
      verificationDiagnostics: _boolFromJson(
        json?['verificationDiagnostics'],
        false,
      ),
      agentCenter: _boolFromJson(json?['agentCenter'], false),
      agentConversation: _boolFromJson(json?['agentConversation'], false),
      agentContext: _boolFromJson(json?['agentContext'], false),
      agentCommandProposals: _boolFromJson(
        json?['agentCommandProposals'],
        false,
      ),
      agentProviderDraft: _boolFromJson(json?['agentProviderDraft'], false),
      agentCommandSearchActions: _boolFromJson(
        json?['agentCommandSearchActions'],
        false,
      ),
    );
  }
}

class LocalTerminalUniversalInputConfig {
  const LocalTerminalUniversalInputConfig({
    this.suggestCorrectedCommands = true,
  });

  final bool suggestCorrectedCommands;

  LocalTerminalUniversalInputConfig copyWith({bool? suggestCorrectedCommands}) {
    return LocalTerminalUniversalInputConfig(
      suggestCorrectedCommands:
          suggestCorrectedCommands ?? this.suggestCorrectedCommands,
    );
  }

  Map<String, Object?> toJson() {
    return {'suggestCorrectedCommands': suggestCorrectedCommands};
  }

  static LocalTerminalUniversalInputConfig fromJson(
    Map<Object?, Object?>? json,
  ) {
    if (json == null) {
      return const LocalTerminalUniversalInputConfig();
    }
    return LocalTerminalUniversalInputConfig(
      suggestCorrectedCommands: _boolFromJson(
        json['suggestCorrectedCommands'],
        true,
      ),
    );
  }
}

class LocalTerminalCommandBlocksHistoryConfig {
  const LocalTerminalCommandBlocksHistoryConfig({
    this.enabled = false,
    this.commandBlocks = false,
    this.failureSnapshots = false,
    this.reviewWorkspaceEntrypoints = false,
    this.outputDiff = false,
  });

  final bool enabled;
  final bool commandBlocks;
  final bool failureSnapshots;
  final bool reviewWorkspaceEntrypoints;
  final bool outputDiff;

  LocalTerminalCommandBlocksHistoryConfig copyWith({
    bool? enabled,
    bool? commandBlocks,
    bool? failureSnapshots,
    bool? reviewWorkspaceEntrypoints,
    bool? outputDiff,
  }) {
    return LocalTerminalCommandBlocksHistoryConfig(
      enabled: enabled ?? this.enabled,
      commandBlocks: commandBlocks ?? this.commandBlocks,
      failureSnapshots: failureSnapshots ?? this.failureSnapshots,
      reviewWorkspaceEntrypoints:
          reviewWorkspaceEntrypoints ?? this.reviewWorkspaceEntrypoints,
      outputDiff: outputDiff ?? this.outputDiff,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'enabled': enabled,
      'commandBlocks': commandBlocks,
      'failureSnapshots': failureSnapshots,
      'reviewWorkspaceEntrypoints': reviewWorkspaceEntrypoints,
      'outputDiff': outputDiff,
    };
  }

  static LocalTerminalCommandBlocksHistoryConfig fromJson(
    Map<Object?, Object?>? json,
  ) {
    if (json == null) {
      return const LocalTerminalCommandBlocksHistoryConfig();
    }
    return LocalTerminalCommandBlocksHistoryConfig(
      enabled: _boolFromJson(json['enabled'], false),
      commandBlocks: _boolFromJson(json['commandBlocks'], false),
      failureSnapshots: _boolFromJson(json['failureSnapshots'], false),
      reviewWorkspaceEntrypoints: _boolFromJson(
        json['reviewWorkspaceEntrypoints'],
        false,
      ),
      outputDiff: _boolFromJson(json['outputDiff'], false),
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

int _positiveWholeIntFromJson(Object? value, int fallback) {
  final parsed = _wholeIntOrNull(value);
  return parsed == null || parsed <= 0 ? fallback : parsed;
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
    for (final policy in LocalTerminalOsc52Policy.values) {
      if (policy.name == normalized) {
        return policy;
      }
    }
  }
  return LocalTerminalOsc52Policy.profile;
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

const Object _localTerminalConfigNoChange = Object();
