import 'dart:convert';

enum TerminalThemeMode {
  system,
  light,
  dark;

  static TerminalThemeMode fromJsonValue(Object? value) {
    return switch (value) {
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
          : defaultProfileId as String?,
    );
  }

  Map<String, Object?> toJson() {
    return {'defaultProfileId': defaultProfileId};
  }

  static TerminalAppDefaults fromJson(Map<Object?, Object?>? json) {
    return TerminalAppDefaults(
      defaultProfileId: json?['defaultProfileId'] as String?,
    );
  }
}

class TerminalAppAppearance {
  const TerminalAppAppearance({this.themeMode = TerminalThemeMode.system});

  final TerminalThemeMode themeMode;

  TerminalAppAppearance copyWith({TerminalThemeMode? themeMode}) {
    return TerminalAppAppearance(themeMode: themeMode ?? this.themeMode);
  }

  Map<String, Object?> toJson() {
    return {'themeMode': themeMode.name};
  }

  static TerminalAppAppearance fromJson(Map<Object?, Object?>? json) {
    return TerminalAppAppearance(
      themeMode: TerminalThemeMode.fromJsonValue(json?['themeMode']),
    );
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
      commandFinished: json?['commandFinished'] as bool? ?? true,
      bell: json?['bell'] as bool? ?? true,
      activity: json?['activity'] as bool? ?? true,
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
      schemaVersion: schemaVersion ?? this.schemaVersion,
      defaults: defaults ?? this.defaults,
      appearance: appearance ?? this.appearance,
      notifications: notifications ?? this.notifications,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'defaults': defaults.toJson(),
      'appearance': appearance.toJson(),
      'notifications': notifications.toJson(),
    };
  }

  String encode() => jsonEncode(toJson());

  static TerminalAppPreferencesDocument fromJson(Map<String, Object?> json) {
    return TerminalAppPreferencesDocument(
      schemaVersion: (json['schemaVersion'] as int?) ?? currentSchemaVersion,
      defaults: TerminalAppDefaults.fromJson(
        json['defaults'] as Map<Object?, Object?>?,
      ),
      appearance: TerminalAppAppearance.fromJson(
        json['appearance'] as Map<Object?, Object?>?,
      ),
      notifications: TerminalAppNotifications.fromJson(
        json['notifications'] as Map<Object?, Object?>?,
      ),
    );
  }
}

const Object _appPreferencesNoChange = Object();
