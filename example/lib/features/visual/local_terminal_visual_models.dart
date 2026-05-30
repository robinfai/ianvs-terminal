import 'dart:convert';

class LocalTerminalColorScheme {
  const LocalTerminalColorScheme({
    required this.background,
    required this.foreground,
    required this.cursor,
    required this.selection,
    required this.splitDivider,
    required this.inactivePaneOverlay,
  });

  final int background;
  final int foreground;
  final int cursor;
  final int selection;
  final int splitDivider;
  final int inactivePaneOverlay;

  Map<String, Object?> toJson() {
    return {
      'background': background,
      'foreground': foreground,
      'cursor': cursor,
      'selection': selection,
      'splitDivider': splitDivider,
      'inactivePaneOverlay': inactivePaneOverlay,
    };
  }

  static LocalTerminalColorScheme fromJson(Map<Object?, Object?> json) {
    return LocalTerminalColorScheme(
      background: _colorIntFromJson(json['background'], 0x000000),
      foreground: _colorIntFromJson(json['foreground'], 0xffffff),
      cursor: _colorIntFromJson(json['cursor'], 0xffffff),
      selection: _colorIntFromJson(json['selection'], 0x333333),
      splitDivider: _colorIntFromJson(json['splitDivider'], 0x222222),
      inactivePaneOverlay: _colorIntFromJson(
        json['inactivePaneOverlay'],
        0x11000000,
      ),
    );
  }
}

class LocalTerminalThemePreset {
  const LocalTerminalThemePreset({
    required this.id,
    required this.name,
    required this.dark,
    required this.light,
  });

  final String id;
  final String name;
  final LocalTerminalColorScheme dark;
  final LocalTerminalColorScheme light;

  LocalTerminalColorScheme schemeForBrightness({required bool darkMode}) {
    return darkMode ? dark : light;
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'dark': dark.toJson(),
      'light': light.toJson(),
    };
  }

  String encode() => jsonEncode(toJson());

  static LocalTerminalThemePreset decode(String raw) {
    final decoded = jsonDecode(raw);
    final json = _objectMap(decoded);
    if (json == null) {
      throw const FormatException('Theme preset JSON must be an object.');
    }
    return fromJson(json);
  }

  static LocalTerminalThemePreset fromJson(Map<Object?, Object?> json) {
    return LocalTerminalThemePreset(
      id: _stringOrNull(json['id']) ?? '',
      name: _stringOrNull(json['name']) ?? '',
      dark: LocalTerminalColorScheme.fromJson(
        _objectMap(json['dark']) ?? const {},
      ),
      light: LocalTerminalColorScheme.fromJson(
        _objectMap(json['light']) ?? const {},
      ),
    );
  }
}

class LocalTerminalProfileThemeOverride {
  const LocalTerminalProfileThemeOverride({
    required this.profileId,
    required this.themePresetId,
  });

  final String profileId;
  final String themePresetId;

  bool appliesTo(String candidateProfileId) {
    return profileId == candidateProfileId;
  }
}

class LocalTerminalPaneVisualPolicy {
  const LocalTerminalPaneVisualPolicy({
    this.showActivePaneBorder = true,
    this.dimInactivePanes = true,
    this.dividerThickness = 1.0,
  });

  final bool showActivePaneBorder;
  final bool dimInactivePanes;
  final double dividerThickness;

  bool get hasVisibleDivider => dividerThickness > 0;
}

class LocalTerminalLayoutTemplate {
  const LocalTerminalLayoutTemplate({
    required this.id,
    required this.name,
    required this.paneCount,
    required this.localOnly,
  });

  final String id;
  final String name;
  final int paneCount;
  final bool localOnly;

  bool get canApply => localOnly && paneCount > 0;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'paneCount': paneCount,
      'localOnly': localOnly,
    };
  }

  static LocalTerminalLayoutTemplate fromJson(Map<Object?, Object?> json) {
    return LocalTerminalLayoutTemplate(
      id: _stringOrNull(json['id']) ?? '',
      name: _stringOrNull(json['name']) ?? '',
      paneCount: _nonNegativeIntFromJson(json['paneCount'], 0),
      localOnly: _boolFromJson(json['localOnly'], false),
    );
  }
}

class LocalTerminalAdvancedVisualPolicy {
  const LocalTerminalAdvancedVisualPolicy({
    this.backgroundImageEnabled = false,
    this.blurEnabled = false,
    this.opacity = 1.0,
  });

  final bool backgroundImageEnabled;
  final bool blurEnabled;
  final double opacity;

  bool get touchesRendererRisk {
    return backgroundImageEnabled || blurEnabled || opacity < 1.0;
  }
}

class LocalTerminalCommandTimestampPolicy {
  const LocalTerminalCommandTimestampPolicy({
    this.enabled = false,
    this.showDuration = true,
  });

  final bool enabled;
  final bool showDuration;
}

class LocalTerminalCommandPanePolicy {
  const LocalTerminalCommandPanePolicy({
    this.enabled = false,
    this.defaultVisible = false,
  });

  final bool enabled;
  final bool defaultVisible;

  bool get canShow => enabled && defaultVisible;
}

enum LocalTerminalExportFormat { plainText, ansiText, json }

class LocalTerminalScrollbackExportPolicy {
  const LocalTerminalScrollbackExportPolicy({
    this.enabled = true,
    this.defaultFormat = LocalTerminalExportFormat.plainText,
    this.includeMetadata = true,
  });

  final bool enabled;
  final LocalTerminalExportFormat defaultFormat;
  final bool includeMetadata;

  bool canExport(LocalTerminalExportFormat format) {
    return enabled && LocalTerminalExportFormat.values.contains(format);
  }
}

class LocalTerminalGraphicsStoragePolicy {
  const LocalTerminalGraphicsStoragePolicy({
    this.enabled = false,
    this.maxBytes = 50 * 1024 * 1024,
    this.evictWhenExceeded = true,
  });

  final bool enabled;
  final int maxBytes;
  final bool evictWhenExceeded;

  bool acceptsImage({required int bytes}) {
    return enabled && bytes > 0 && bytes <= maxBytes;
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

int _colorIntFromJson(Object? value, int fallback) {
  final parsed = _intFromJson(value, fallback);
  return parsed < 0 || parsed > 0xffffffff ? fallback : parsed;
}

int _nonNegativeIntFromJson(Object? value, int fallback) {
  final parsed = _intFromJson(value, fallback);
  return parsed < 0 ? fallback : parsed;
}
