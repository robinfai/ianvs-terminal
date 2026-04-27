import '../preferences/app_preferences_models.dart';
import '../profiles/profile_models.dart';

class TerminalTab {
  const TerminalTab({
    required this.sessionId,
    required this.title,
    required this.profileId,
    this.profileSnapshot,
    this.isExited = false,
    this.exitCode,
  });

  final String sessionId;
  final String title;
  final String profileId;
  final TerminalProfile? profileSnapshot;
  final bool isExited;
  final int? exitCode;

  TerminalTab copyWith({
    String? title,
    TerminalProfile? profileSnapshot,
    bool? isExited,
    int? exitCode,
  }) {
    return TerminalTab(
      sessionId: sessionId,
      title: title ?? this.title,
      profileId: profileId,
      profileSnapshot: profileSnapshot ?? this.profileSnapshot,
      isExited: isExited ?? this.isExited,
      exitCode: exitCode ?? this.exitCode,
    );
  }
}

class SessionState {
  const SessionState({
    required this.tabs,
    required this.activeSessionId,
    required this.profiles,
    required this.defaultProfileId,
    required this.configuredDefaultProfileId,
    required this.configurationWarnings,
    required this.themeMode,
    required this.isReady,
    this.lastError,
  });

  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final List<TerminalProfile> profiles;
  final String? defaultProfileId;
  final String? configuredDefaultProfileId;
  final List<TerminalProfileLoadWarning> configurationWarnings;
  final TerminalThemeMode themeMode;
  final bool isReady;
  final String? lastError;

  factory SessionState.initial() {
    return const SessionState(
      tabs: [],
      activeSessionId: null,
      profiles: [],
      defaultProfileId: null,
      configuredDefaultProfileId: null,
      configurationWarnings: [],
      themeMode: TerminalThemeMode.system,
      isReady: false,
    );
  }

  SessionState copyWith({
    List<TerminalTab>? tabs,
    Object? activeSessionId = _sessionStateNoChange,
    List<TerminalProfile>? profiles,
    Object? defaultProfileId = _sessionStateNoChange,
    Object? configuredDefaultProfileId = _sessionStateNoChange,
    List<TerminalProfileLoadWarning>? configurationWarnings,
    TerminalThemeMode? themeMode,
    bool? isReady,
    Object? lastError = _sessionStateNoChange,
  }) {
    return SessionState(
      tabs: tabs ?? this.tabs,
      activeSessionId: identical(activeSessionId, _sessionStateNoChange)
          ? this.activeSessionId
          : activeSessionId as String?,
      profiles: profiles ?? this.profiles,
      defaultProfileId: identical(defaultProfileId, _sessionStateNoChange)
          ? this.defaultProfileId
          : defaultProfileId as String?,
      configuredDefaultProfileId:
          identical(configuredDefaultProfileId, _sessionStateNoChange)
          ? this.configuredDefaultProfileId
          : configuredDefaultProfileId as String?,
      configurationWarnings:
          configurationWarnings ?? this.configurationWarnings,
      themeMode: themeMode ?? this.themeMode,
      isReady: isReady ?? this.isReady,
      lastError: identical(lastError, _sessionStateNoChange)
          ? this.lastError
          : lastError as String?,
    );
  }
}

const Object _sessionStateNoChange = Object();
