import 'dart:convert';

enum TerminalThemeMode {
  system,
  light,
  dark;

  static TerminalThemeMode fromJsonValue(Object? value) {
    final normalized = value is String ? value.trim().toLowerCase() : null;
    return switch (normalized) {
      'light' => TerminalThemeMode.light,
      'dark' => TerminalThemeMode.dark,
      _ => TerminalThemeMode.system,
    };
  }
}

class TerminalAppDefaults {
  const TerminalAppDefaults({this.defaultProfileId});

  final String? defaultProfileId;

  TerminalAppDefaults copyWith({
    Object? defaultProfileId = _appPreferencesNoChange,
  }) {
    return TerminalAppDefaults(
      defaultProfileId: identical(defaultProfileId, _appPreferencesNoChange)
          ? this.defaultProfileId
          : _nonEmptyTrimmedStringOrNull(defaultProfileId as String?),
    );
  }

  Map<String, Object?> toJson() {
    return {'defaultProfileId': _nonEmptyTrimmedStringOrNull(defaultProfileId)};
  }

  static TerminalAppDefaults fromJson(Map<Object?, Object?>? json) {
    return TerminalAppDefaults(
      defaultProfileId: _nonEmptyTrimmedStringOrNull(json?['defaultProfileId']),
    );
  }
}

class TerminalAppAppearance {
  const TerminalAppAppearance({
    this.themeMode = TerminalThemeMode.system,
    this.terminalViewportPadding = defaultTerminalViewportPadding,
  });

  static const double defaultTerminalViewportPadding = 8;
  static const double minTerminalViewportPadding = 0;
  static const double maxTerminalViewportPadding = 48;

  final TerminalThemeMode themeMode;
  final double terminalViewportPadding;

  TerminalAppAppearance copyWith({
    TerminalThemeMode? themeMode,
    double? terminalViewportPadding,
  }) {
    return TerminalAppAppearance(
      themeMode: themeMode ?? this.themeMode,
      terminalViewportPadding: normalizeTerminalViewportPadding(
        terminalViewportPadding ?? this.terminalViewportPadding,
      ),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'themeMode': themeMode.name,
      'terminalViewportPadding': normalizeTerminalViewportPadding(
        terminalViewportPadding,
      ),
    };
  }

  static TerminalAppAppearance fromJson(Map<Object?, Object?>? json) {
    return TerminalAppAppearance(
      themeMode: TerminalThemeMode.fromJsonValue(json?['themeMode']),
      terminalViewportPadding: normalizeTerminalViewportPadding(
        json?['terminalViewportPadding'],
      ),
    );
  }

  static double normalizeTerminalViewportPadding(Object? value) {
    final parsed = switch (value) {
      num() => value.toDouble(),
      String() => double.tryParse(value),
      _ => null,
    };
    if (parsed == null || !parsed.isFinite) {
      return defaultTerminalViewportPadding;
    }
    return parsed
        .clamp(minTerminalViewportPadding, maxTerminalViewportPadding)
        .toDouble();
  }
}

class TerminalAppNotifications {
  const TerminalAppNotifications({
    this.commandFinished = true,
    this.bell = true,
    this.activity = true,
  });

  final bool commandFinished;
  final bool bell;
  final bool activity;

  TerminalAppNotifications copyWith({
    bool? commandFinished,
    bool? bell,
    bool? activity,
  }) {
    return TerminalAppNotifications(
      commandFinished: commandFinished ?? this.commandFinished,
      bell: bell ?? this.bell,
      activity: activity ?? this.activity,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'commandFinished': commandFinished,
      'bell': bell,
      'activity': activity,
    };
  }

  static TerminalAppNotifications fromJson(Map<Object?, Object?>? json) {
    return TerminalAppNotifications(
      commandFinished: _boolFromJson(json?['commandFinished'], true),
      bell: _boolFromJson(json?['bell'], true),
      activity: _boolFromJson(json?['activity'], true),
    );
  }
}

class TerminalAppPreferencesDocument {
  const TerminalAppPreferencesDocument({
    this.schemaVersion = currentSchemaVersion,
    this.defaults = const TerminalAppDefaults(),
    this.appearance = const TerminalAppAppearance(),
    this.notifications = const TerminalAppNotifications(),
  });

  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final TerminalAppDefaults defaults;
  final TerminalAppAppearance appearance;
  final TerminalAppNotifications notifications;

  TerminalAppPreferencesDocument copyWith({
    int? schemaVersion,
    TerminalAppDefaults? defaults,
    TerminalAppAppearance? appearance,
    TerminalAppNotifications? notifications,
  }) {
    return TerminalAppPreferencesDocument(
      schemaVersion: _schemaVersionFromJson(
        schemaVersion ?? this.schemaVersion,
        currentSchemaVersion,
      ),
      defaults: defaults ?? this.defaults,
      appearance: appearance ?? this.appearance,
      notifications: notifications ?? this.notifications,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': _schemaVersionFromJson(
        schemaVersion,
        currentSchemaVersion,
      ),
      'defaults': defaults.toJson(),
      'appearance': appearance.toJson(),
      'notifications': notifications.toJson(),
    };
  }

  String encode() => jsonEncode(toJson());

  static TerminalAppPreferencesDocument fromJson(Map<String, Object?> json) {
    return TerminalAppPreferencesDocument(
      schemaVersion: _schemaVersionFromJson(
        json['schemaVersion'],
        currentSchemaVersion,
      ),
      defaults: TerminalAppDefaults.fromJson(_objectMap(json['defaults'])),
      appearance: TerminalAppAppearance.fromJson(
        _objectMap(json['appearance']),
      ),
      notifications: TerminalAppNotifications.fromJson(
        _objectMap(json['notifications']),
      ),
    );
  }
}

int _schemaVersionFromJson(Object? value, int fallback) {
  if (value is int) {
    return value > 0 ? value : fallback;
  }
  if (value is num && value.isFinite) {
    final parsed = value.toInt();
    return parsed > 0 && value == parsed ? parsed : fallback;
  }
  return fallback;
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

const Object _appPreferencesNoChange = Object();
