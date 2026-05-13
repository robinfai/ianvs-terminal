import '../preferences/app_preferences_models.dart';
import '../profiles/profile_models.dart';

enum TerminalSplitAxis { horizontal, vertical }

class TerminalPane {
  const TerminalPane({
    required this.sessionId,
    required this.title,
    required this.profileId,
    this.profileSnapshot,
    this.isExited = false,
    this.exitCode,
    this.shellIntegration = TerminalShellIntegrationSnapshot.empty,
  });

  final String sessionId;
  final String title;
  final String profileId;
  final TerminalProfile? profileSnapshot;
  final bool isExited;
  final int? exitCode;
  final TerminalShellIntegrationSnapshot shellIntegration;

  TerminalPane copyWith({
    String? title,
    String? profileId,
    TerminalProfile? profileSnapshot,
    bool? isExited,
    int? exitCode,
    TerminalShellIntegrationSnapshot? shellIntegration,
  }) {
    return TerminalPane(
      sessionId: sessionId,
      title: title ?? this.title,
      profileId: profileId ?? this.profileId,
      profileSnapshot: profileSnapshot ?? this.profileSnapshot,
      isExited: isExited ?? this.isExited,
      exitCode: exitCode ?? this.exitCode,
      shellIntegration: shellIntegration ?? this.shellIntegration,
    );
  }
}

class TerminalTab {
  const TerminalTab({
    required this.sessionId,
    required this.title,
    required this.profileId,
    this.profileSnapshot,
    this.isExited = false,
    this.exitCode,
    this.panes = const [],
    this.activePaneSessionId,
    this.splitAxis = TerminalSplitAxis.horizontal,
    this.shellIntegration = TerminalShellIntegrationSnapshot.empty,
  });

  final String sessionId;
  final String title;
  final String profileId;
  final TerminalProfile? profileSnapshot;
  final bool isExited;
  final int? exitCode;
  final List<TerminalPane> panes;
  final String? activePaneSessionId;
  final TerminalSplitAxis splitAxis;
  final TerminalShellIntegrationSnapshot shellIntegration;

  List<TerminalPane> get effectivePanes {
    if (panes.isNotEmpty) {
      return panes;
    }
    return [
      TerminalPane(
        sessionId: sessionId,
        title: title,
        profileId: profileId,
        profileSnapshot: profileSnapshot,
        isExited: isExited,
        exitCode: exitCode,
        shellIntegration: shellIntegration,
      ),
    ];
  }

  String get activeSessionId => activePaneSessionId ?? sessionId;

  TerminalPane get activePane {
    return paneFor(activeSessionId) ?? effectivePanes.first;
  }

  bool containsSession(String sessionId) {
    return effectivePanes.any((pane) => pane.sessionId == sessionId);
  }

  TerminalPane? paneFor(String sessionId) {
    for (final pane in effectivePanes) {
      if (pane.sessionId == sessionId) {
        return pane;
      }
    }
    return null;
  }

  TerminalTab copyWith({
    String? title,
    String? profileId,
    TerminalProfile? profileSnapshot,
    bool? isExited,
    int? exitCode,
    List<TerminalPane>? panes,
    Object? activePaneSessionId = _terminalTabNoChange,
    TerminalSplitAxis? splitAxis,
    TerminalShellIntegrationSnapshot? shellIntegration,
  }) {
    return TerminalTab(
      sessionId: sessionId,
      title: title ?? this.title,
      profileId: profileId ?? this.profileId,
      profileSnapshot: profileSnapshot ?? this.profileSnapshot,
      isExited: isExited ?? this.isExited,
      exitCode: exitCode ?? this.exitCode,
      panes: panes ?? this.panes,
      activePaneSessionId: identical(activePaneSessionId, _terminalTabNoChange)
          ? this.activePaneSessionId
          : activePaneSessionId as String?,
      splitAxis: splitAxis ?? this.splitAxis,
      shellIntegration: shellIntegration ?? this.shellIntegration,
    );
  }
}

const Object _terminalTabNoChange = Object();

class TerminalShellPromptMark {
  const TerminalShellPromptMark({
    required this.scrollbackOffset,
    this.command,
    this.cwd,
  });

  final int scrollbackOffset;
  final String? command;
  final String? cwd;
}

class TerminalShellIntegrationSnapshot {
  const TerminalShellIntegrationSnapshot({
    this.currentDirectory,
    this.hostname,
    this.username,
    this.shell,
    this.lastCommand,
    this.lastExitCode,
    this.recentCommands = const <String>[],
    this.recentDirectories = const <String>[],
    this.promptMarks = const <TerminalShellPromptMark>[],
  });

  static const empty = TerminalShellIntegrationSnapshot();

  final String? currentDirectory;
  final String? hostname;
  final String? username;
  final String? shell;
  final String? lastCommand;
  final int? lastExitCode;
  final List<String> recentCommands;
  final List<String> recentDirectories;
  final List<TerminalShellPromptMark> promptMarks;

  TerminalShellIntegrationSnapshot copyWith({
    Object? currentDirectory = _shellIntegrationNoChange,
    Object? hostname = _shellIntegrationNoChange,
    Object? username = _shellIntegrationNoChange,
    Object? shell = _shellIntegrationNoChange,
    Object? lastCommand = _shellIntegrationNoChange,
    Object? lastExitCode = _shellIntegrationNoChange,
    List<String>? recentCommands,
    List<String>? recentDirectories,
    List<TerminalShellPromptMark>? promptMarks,
  }) {
    return TerminalShellIntegrationSnapshot(
      currentDirectory: identical(currentDirectory, _shellIntegrationNoChange)
          ? this.currentDirectory
          : currentDirectory as String?,
      hostname: identical(hostname, _shellIntegrationNoChange)
          ? this.hostname
          : hostname as String?,
      username: identical(username, _shellIntegrationNoChange)
          ? this.username
          : username as String?,
      shell: identical(shell, _shellIntegrationNoChange)
          ? this.shell
          : shell as String?,
      lastCommand: identical(lastCommand, _shellIntegrationNoChange)
          ? this.lastCommand
          : lastCommand as String?,
      lastExitCode: identical(lastExitCode, _shellIntegrationNoChange)
          ? this.lastExitCode
          : lastExitCode as int?,
      recentCommands: recentCommands ?? this.recentCommands,
      recentDirectories: recentDirectories ?? this.recentDirectories,
      promptMarks: promptMarks ?? this.promptMarks,
    );
  }
}

const Object _shellIntegrationNoChange = Object();

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
