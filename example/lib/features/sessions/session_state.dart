import '../layout/local_terminal_relaunch_spec.dart';
import '../preferences/app_preferences_models.dart';
import '../profiles/profile_models.dart';

enum TerminalSplitAxis { horizontal, vertical }

class TerminalPane {
  const TerminalPane({
    required this.sessionId,
    required this.title,
    required this.profileId,
    this.profileSnapshot,
    this.relaunchSpec,
    this.isExited = false,
    this.exitCode,
    this.shellIntegration = TerminalShellIntegrationSnapshot.empty,
    this.oscBadge,
    this.tabStatus = const TerminalPaneTabStatusState(),
    this.progress,
    this.namedProgress = const <String, TerminalPaneProgressState>{},
    this.recentNotifications = const <TerminalPaneNotificationState>[],
  });

  final String sessionId;
  final String title;
  final String profileId;
  final TerminalProfile? profileSnapshot;
  final TerminalRelaunchSpec? relaunchSpec;
  final bool isExited;
  final int? exitCode;
  final TerminalShellIntegrationSnapshot shellIntegration;
  final String? oscBadge;
  final TerminalPaneTabStatusState tabStatus;
  final TerminalPaneProgressState? progress;
  final Map<String, TerminalPaneProgressState> namedProgress;
  final List<TerminalPaneNotificationState> recentNotifications;

  TerminalPane copyWith({
    String? title,
    String? profileId,
    Object? profileSnapshot = _terminalPaneNoChange,
    Object? relaunchSpec = _terminalPaneNoChange,
    bool? isExited,
    Object? exitCode = _terminalPaneNoChange,
    TerminalShellIntegrationSnapshot? shellIntegration,
    Object? oscBadge = _terminalPaneNoChange,
    TerminalPaneTabStatusState? tabStatus,
    Object? progress = _terminalPaneNoChange,
    Map<String, TerminalPaneProgressState>? namedProgress,
    List<TerminalPaneNotificationState>? recentNotifications,
  }) {
    return TerminalPane(
      sessionId: sessionId,
      title: title ?? this.title,
      profileId: profileId ?? this.profileId,
      profileSnapshot: identical(profileSnapshot, _terminalPaneNoChange)
          ? this.profileSnapshot
          : profileSnapshot as TerminalProfile?,
      relaunchSpec: identical(relaunchSpec, _terminalPaneNoChange)
          ? this.relaunchSpec
          : relaunchSpec as TerminalRelaunchSpec?,
      isExited: isExited ?? this.isExited,
      exitCode: identical(exitCode, _terminalPaneNoChange)
          ? this.exitCode
          : exitCode as int?,
      shellIntegration: shellIntegration ?? this.shellIntegration,
      oscBadge: identical(oscBadge, _terminalPaneNoChange)
          ? this.oscBadge
          : oscBadge as String?,
      tabStatus: tabStatus ?? this.tabStatus,
      progress: identical(progress, _terminalPaneNoChange)
          ? this.progress
          : progress as TerminalPaneProgressState?,
      namedProgress: namedProgress ?? this.namedProgress,
      recentNotifications: recentNotifications ?? this.recentNotifications,
    );
  }
}

const Object _terminalPaneNoChange = Object();

class TerminalPaneTabStatusState {
  const TerminalPaneTabStatusState({
    this.indicator,
    this.status,
    this.statusColor,
  });

  final String? indicator;
  final String? status;
  final String? statusColor;

  bool get isEmpty =>
      indicator == null && status == null && statusColor == null;

  TerminalPaneTabStatusState copyWith({
    Object? indicator = _terminalPaneNoChange,
    Object? status = _terminalPaneNoChange,
    Object? statusColor = _terminalPaneNoChange,
  }) {
    return TerminalPaneTabStatusState(
      indicator: identical(indicator, _terminalPaneNoChange)
          ? this.indicator
          : indicator as String?,
      status: identical(status, _terminalPaneNoChange)
          ? this.status
          : status as String?,
      statusColor: identical(statusColor, _terminalPaneNoChange)
          ? this.statusColor
          : statusColor as String?,
    );
  }
}

class TerminalPaneProgressState {
  const TerminalPaneProgressState({
    required this.source,
    required this.named,
    required this.action,
    this.id,
    this.state,
    this.percent,
    this.label,
  });

  final String source;
  final bool named;
  final String action;
  final String? id;
  final String? state;
  final int? percent;
  final String? label;

  bool get active => state != null && state != 'hidden' && action != 'clear';

  TerminalPaneProgressState copyWith({
    String? source,
    bool? named,
    String? action,
    Object? id = _terminalPaneNoChange,
    Object? state = _terminalPaneNoChange,
    Object? percent = _terminalPaneNoChange,
    Object? label = _terminalPaneNoChange,
  }) {
    return TerminalPaneProgressState(
      source: source ?? this.source,
      named: named ?? this.named,
      action: action ?? this.action,
      id: identical(id, _terminalPaneNoChange) ? this.id : id as String?,
      state: identical(state, _terminalPaneNoChange)
          ? this.state
          : state as String?,
      percent: identical(percent, _terminalPaneNoChange)
          ? this.percent
          : percent as int?,
      label: identical(label, _terminalPaneNoChange)
          ? this.label
          : label as String?,
    );
  }

  String get displayLabel {
    final prefix = named ? (id ?? 'PROGRESS') : 'PROGRESS';
    final value = percent?.toString();
    final stateLabel = state?.toUpperCase();
    return [
      prefix.toUpperCase(),
      if (value != null) '$value%' else ?stateLabel,
    ].join(' ');
  }
}

class TerminalPaneNotificationState {
  const TerminalPaneNotificationState({
    required this.source,
    required this.title,
    required this.message,
    this.identifier,
    this.applicationName,
    this.notificationTypes = const <String>[],
    this.expiresAfterMs,
    this.reportActivation = false,
    this.reportClose = false,
    this.buttons = const <String>[],
    this.remoteHost,
    this.remoteUser,
    this.count = 1,
  });

  final String source;
  final String title;
  final String message;
  final String? identifier;
  final String? applicationName;
  final List<String> notificationTypes;
  final int? expiresAfterMs;
  final bool reportActivation;
  final bool reportClose;
  final List<String> buttons;
  final String? remoteHost;
  final String? remoteUser;
  final int count;

  TerminalPaneNotificationState copyWith({int? count}) {
    return TerminalPaneNotificationState(
      source: source,
      title: title,
      message: message,
      identifier: identifier,
      applicationName: applicationName,
      notificationTypes: notificationTypes,
      expiresAfterMs: expiresAfterMs,
      reportActivation: reportActivation,
      reportClose: reportClose,
      buttons: buttons,
      remoteHost: remoteHost,
      remoteUser: remoteUser,
      count: count ?? this.count,
    );
  }
}

class TerminalPaneLayoutNode {
  const TerminalPaneLayoutNode._({
    required this.id,
    required this.pane,
    required this.splitAxis,
    required this.first,
    required this.second,
    required this.ratio,
  });

  factory TerminalPaneLayoutNode.leaf(TerminalPane pane) {
    return TerminalPaneLayoutNode._(
      id: pane.sessionId,
      pane: pane,
      splitAxis: null,
      first: null,
      second: null,
      ratio: 0.5,
    );
  }

  factory TerminalPaneLayoutNode.split({
    required String id,
    required TerminalSplitAxis splitAxis,
    required TerminalPaneLayoutNode first,
    required TerminalPaneLayoutNode second,
    double ratio = 0.5,
  }) {
    return TerminalPaneLayoutNode._(
      id: id,
      pane: null,
      splitAxis: splitAxis,
      first: first,
      second: second,
      ratio: _splitRatio(ratio),
    );
  }

  factory TerminalPaneLayoutNode.fromPanes(
    List<TerminalPane> panes,
    TerminalSplitAxis splitAxis,
  ) {
    if (panes.isEmpty) {
      throw ArgumentError.value(panes, 'panes', 'Must not be empty.');
    }
    var layout = TerminalPaneLayoutNode.leaf(panes.first);
    for (var index = 1; index < panes.length; index++) {
      layout = TerminalPaneLayoutNode.split(
        id: _terminalPaneSplitNodeId(
          layout.firstLeafId,
          panes[index].sessionId,
        ),
        splitAxis: splitAxis,
        first: layout,
        second: TerminalPaneLayoutNode.leaf(panes[index]),
        ratio: index / (index + 1),
      );
    }
    return layout;
  }

  final String id;
  final TerminalPane? pane;
  final TerminalSplitAxis? splitAxis;
  final TerminalPaneLayoutNode? first;
  final TerminalPaneLayoutNode? second;
  final double ratio;

  bool get isLeaf => pane != null;

  List<TerminalPane> get panes {
    if (isLeaf) {
      return [pane!];
    }
    return [...first!.panes, ...second!.panes];
  }

  String get firstLeafId {
    if (isLeaf) {
      return pane!.sessionId;
    }
    return first!.firstLeafId;
  }

  bool containsSession(String sessionId) {
    return paneFor(sessionId) != null;
  }

  TerminalPane? paneFor(String sessionId) {
    if (isLeaf) {
      return pane!.sessionId == sessionId ? pane : null;
    }
    return first!.paneFor(sessionId) ?? second!.paneFor(sessionId);
  }

  TerminalPaneLayoutNode replacePane(TerminalPane replacement) {
    if (isLeaf) {
      return pane!.sessionId == replacement.sessionId
          ? TerminalPaneLayoutNode.leaf(replacement)
          : this;
    }
    return TerminalPaneLayoutNode.split(
      id: id,
      splitAxis: splitAxis!,
      first: first!.replacePane(replacement),
      second: second!.replacePane(replacement),
      ratio: ratio,
    );
  }

  TerminalPaneLayoutNode splitPane({
    required String sessionId,
    required TerminalPane newPane,
    required TerminalSplitAxis axis,
  }) {
    if (isLeaf) {
      if (pane!.sessionId != sessionId) {
        return this;
      }
      return TerminalPaneLayoutNode.split(
        id: _terminalPaneSplitNodeId(sessionId, newPane.sessionId),
        splitAxis: axis,
        first: this,
        second: TerminalPaneLayoutNode.leaf(newPane),
      );
    }
    return TerminalPaneLayoutNode.split(
      id: id,
      splitAxis: splitAxis!,
      first: first!.splitPane(
        sessionId: sessionId,
        newPane: newPane,
        axis: axis,
      ),
      second: second!.splitPane(
        sessionId: sessionId,
        newPane: newPane,
        axis: axis,
      ),
      ratio: ratio,
    );
  }

  TerminalPaneLayoutNode insertPane({
    required String targetSessionId,
    required TerminalPane pane,
    required TerminalSplitAxis axis,
    required bool before,
  }) {
    if (isLeaf) {
      if (this.pane!.sessionId != targetSessionId) {
        return this;
      }
      final inserted = TerminalPaneLayoutNode.leaf(pane);
      return TerminalPaneLayoutNode.split(
        id: before
            ? _terminalPaneSplitNodeId(pane.sessionId, targetSessionId)
            : _terminalPaneSplitNodeId(targetSessionId, pane.sessionId),
        splitAxis: axis,
        first: before ? inserted : this,
        second: before ? this : inserted,
      );
    }
    return TerminalPaneLayoutNode.split(
      id: id,
      splitAxis: splitAxis!,
      first: first!.insertPane(
        targetSessionId: targetSessionId,
        pane: pane,
        axis: axis,
        before: before,
      ),
      second: second!.insertPane(
        targetSessionId: targetSessionId,
        pane: pane,
        axis: axis,
        before: before,
      ),
      ratio: ratio,
    );
  }

  TerminalPaneLayoutNode? removePane(String sessionId) {
    if (isLeaf) {
      return pane!.sessionId == sessionId ? null : this;
    }
    final nextFirst = first!.removePane(sessionId);
    final nextSecond = second!.removePane(sessionId);
    if (nextFirst == null) {
      return nextSecond;
    }
    if (nextSecond == null) {
      return nextFirst;
    }
    return TerminalPaneLayoutNode.split(
      id: id,
      splitAxis: splitAxis!,
      first: nextFirst,
      second: nextSecond,
      ratio: ratio,
    );
  }

  TerminalPaneLayoutNode swapPaneWithSibling(String sessionId) {
    if (isLeaf) {
      return this;
    }
    if (first!.containsSession(sessionId)) {
      if (!first!.isLeaf) {
        return TerminalPaneLayoutNode.split(
          id: id,
          splitAxis: splitAxis!,
          first: first!.swapPaneWithSibling(sessionId),
          second: second!,
          ratio: ratio,
        );
      }
      return TerminalPaneLayoutNode.split(
        id: id,
        splitAxis: splitAxis!,
        first: second!,
        second: first!,
        ratio: 1 - ratio,
      );
    }
    if (second!.containsSession(sessionId)) {
      if (!second!.isLeaf) {
        return TerminalPaneLayoutNode.split(
          id: id,
          splitAxis: splitAxis!,
          first: first!,
          second: second!.swapPaneWithSibling(sessionId),
          ratio: ratio,
        );
      }
      return TerminalPaneLayoutNode.split(
        id: id,
        splitAxis: splitAxis!,
        first: second!,
        second: first!,
        ratio: 1 - ratio,
      );
    }
    return TerminalPaneLayoutNode.split(
      id: id,
      splitAxis: splitAxis!,
      first: first!.swapPaneWithSibling(sessionId),
      second: second!.swapPaneWithSibling(sessionId),
      ratio: ratio,
    );
  }

  TerminalPaneLayoutNode resizeSplit(String splitNodeId, double nextRatio) {
    if (isLeaf) {
      return this;
    }
    if (id == splitNodeId) {
      return TerminalPaneLayoutNode.split(
        id: id,
        splitAxis: splitAxis!,
        first: first!,
        second: second!,
        ratio: nextRatio,
      );
    }
    return TerminalPaneLayoutNode.split(
      id: id,
      splitAxis: splitAxis!,
      first: first!.resizeSplit(splitNodeId, nextRatio),
      second: second!.resizeSplit(splitNodeId, nextRatio),
      ratio: ratio,
    );
  }

  TerminalPaneLayoutNode growPane(String sessionId, double delta) {
    if (isLeaf) {
      return this;
    }
    if (first!.containsSession(sessionId)) {
      if (!first!.isLeaf) {
        return TerminalPaneLayoutNode.split(
          id: id,
          splitAxis: splitAxis!,
          first: first!.growPane(sessionId, delta),
          second: second!,
          ratio: ratio,
        );
      }
      return TerminalPaneLayoutNode.split(
        id: id,
        splitAxis: splitAxis!,
        first: first!,
        second: second!,
        ratio: ratio + delta,
      );
    }
    if (second!.containsSession(sessionId)) {
      if (!second!.isLeaf) {
        return TerminalPaneLayoutNode.split(
          id: id,
          splitAxis: splitAxis!,
          first: first!,
          second: second!.growPane(sessionId, delta),
          ratio: ratio,
        );
      }
      return TerminalPaneLayoutNode.split(
        id: id,
        splitAxis: splitAxis!,
        first: first!,
        second: second!,
        ratio: ratio - delta,
      );
    }
    return this;
  }
}

double _splitRatio(double value) {
  if (!value.isFinite) {
    return 0.5;
  }
  return value.clamp(0.1, 0.9);
}

class TerminalTab {
  const TerminalTab({
    required this.sessionId,
    required this.title,
    required this.profileId,
    this.profileSnapshot,
    this.relaunchSpec,
    this.isExited = false,
    this.exitCode,
    this.panes = const [],
    this.paneLayout,
    this.activePaneSessionId,
    this.splitAxis = TerminalSplitAxis.horizontal,
    this.shellIntegration = TerminalShellIntegrationSnapshot.empty,
    this.oscBadge,
    this.tabStatus = const TerminalPaneTabStatusState(),
    this.progress,
    this.namedProgress = const <String, TerminalPaneProgressState>{},
    this.recentNotifications = const <TerminalPaneNotificationState>[],
  });

  final String sessionId;
  final String title;
  final String profileId;
  final TerminalProfile? profileSnapshot;
  final TerminalRelaunchSpec? relaunchSpec;
  final bool isExited;
  final int? exitCode;
  final List<TerminalPane> panes;
  final TerminalPaneLayoutNode? paneLayout;
  final String? activePaneSessionId;
  final TerminalSplitAxis splitAxis;
  final TerminalShellIntegrationSnapshot shellIntegration;
  final String? oscBadge;
  final TerminalPaneTabStatusState tabStatus;
  final TerminalPaneProgressState? progress;
  final Map<String, TerminalPaneProgressState> namedProgress;
  final List<TerminalPaneNotificationState> recentNotifications;

  TerminalPane get rootPane {
    return TerminalPane(
      sessionId: sessionId,
      title: title,
      profileId: profileId,
      profileSnapshot: profileSnapshot,
      relaunchSpec: relaunchSpec,
      isExited: isExited,
      exitCode: exitCode,
      shellIntegration: shellIntegration,
      oscBadge: oscBadge,
      tabStatus: tabStatus,
      progress: progress,
      namedProgress: namedProgress,
      recentNotifications: recentNotifications,
    );
  }

  TerminalPaneLayoutNode get effectivePaneLayout {
    final layout = paneLayout;
    if (layout != null) {
      return layout;
    }
    if (panes.isNotEmpty) {
      return TerminalPaneLayoutNode.fromPanes(panes, splitAxis);
    }
    return TerminalPaneLayoutNode.leaf(rootPane);
  }

  List<TerminalPane> get effectivePanes {
    return effectivePaneLayout.panes;
  }

  String get activeSessionId {
    final panes = effectivePanes;
    final activePaneId = activePaneSessionId;
    if (activePaneId != null &&
        panes.any((pane) => pane.sessionId == activePaneId)) {
      return activePaneId;
    }
    if (panes.any((pane) => pane.sessionId == sessionId)) {
      return sessionId;
    }
    return panes.first.sessionId;
  }

  TerminalPane get activePane {
    return paneFor(activeSessionId) ?? effectivePanes.first;
  }

  bool containsSession(String sessionId) {
    return effectivePanes.any((pane) => pane.sessionId == sessionId);
  }

  TerminalPane? paneFor(String sessionId) {
    return effectivePaneLayout.paneFor(sessionId);
  }

  TerminalTab replacePane(TerminalPane replacement) {
    if (paneLayout == null &&
        panes.isEmpty &&
        replacement.sessionId == sessionId) {
      return copyWith(
        title: replacement.title,
        profileId: replacement.profileId,
        profileSnapshot: replacement.profileSnapshot,
        relaunchSpec: replacement.relaunchSpec,
        isExited: replacement.isExited,
        exitCode: replacement.exitCode,
        shellIntegration: replacement.shellIntegration,
        oscBadge: replacement.oscBadge,
        tabStatus: replacement.tabStatus,
        progress: replacement.progress,
        namedProgress: replacement.namedProgress,
        recentNotifications: replacement.recentNotifications,
      );
    }
    final nextLayout = effectivePaneLayout.replacePane(replacement);
    final replacingRootPane = replacement.sessionId == sessionId;
    return copyWith(
      title: replacingRootPane ? replacement.title : title,
      profileId: replacingRootPane ? replacement.profileId : profileId,
      profileSnapshot: replacingRootPane
          ? replacement.profileSnapshot
          : profileSnapshot,
      relaunchSpec: replacingRootPane ? replacement.relaunchSpec : relaunchSpec,
      isExited: replacingRootPane ? replacement.isExited : isExited,
      exitCode: replacingRootPane ? replacement.exitCode : exitCode,
      shellIntegration: replacingRootPane
          ? replacement.shellIntegration
          : shellIntegration,
      oscBadge: replacingRootPane ? replacement.oscBadge : _terminalTabNoChange,
      tabStatus: replacingRootPane ? replacement.tabStatus : null,
      progress: replacingRootPane ? replacement.progress : _terminalTabNoChange,
      namedProgress: replacingRootPane ? replacement.namedProgress : null,
      recentNotifications: replacingRootPane
          ? replacement.recentNotifications
          : null,
      panes: nextLayout.panes,
      paneLayout: nextLayout,
    );
  }

  TerminalTab copyWith({
    String? title,
    String? profileId,
    Object? profileSnapshot = _terminalTabNoChange,
    Object? relaunchSpec = _terminalTabNoChange,
    bool? isExited,
    Object? exitCode = _terminalTabNoChange,
    List<TerminalPane>? panes,
    Object? paneLayout = _terminalTabNoChange,
    Object? activePaneSessionId = _terminalTabNoChange,
    TerminalSplitAxis? splitAxis,
    TerminalShellIntegrationSnapshot? shellIntegration,
    Object? oscBadge = _terminalTabNoChange,
    TerminalPaneTabStatusState? tabStatus,
    Object? progress = _terminalTabNoChange,
    Map<String, TerminalPaneProgressState>? namedProgress,
    List<TerminalPaneNotificationState>? recentNotifications,
  }) {
    final nextSplitAxis = splitAxis ?? this.splitAxis;
    final nextPaneLayout = identical(paneLayout, _terminalTabNoChange)
        ? panes == null
              ? this.paneLayout
              : panes.isEmpty
              ? null
              : TerminalPaneLayoutNode.fromPanes(panes, nextSplitAxis)
        : paneLayout as TerminalPaneLayoutNode?;
    return TerminalTab(
      sessionId: sessionId,
      title: title ?? this.title,
      profileId: profileId ?? this.profileId,
      profileSnapshot: identical(profileSnapshot, _terminalTabNoChange)
          ? this.profileSnapshot
          : profileSnapshot as TerminalProfile?,
      relaunchSpec: identical(relaunchSpec, _terminalTabNoChange)
          ? this.relaunchSpec
          : relaunchSpec as TerminalRelaunchSpec?,
      isExited: isExited ?? this.isExited,
      exitCode: identical(exitCode, _terminalTabNoChange)
          ? this.exitCode
          : exitCode as int?,
      panes: panes ?? this.panes,
      paneLayout: nextPaneLayout,
      activePaneSessionId: identical(activePaneSessionId, _terminalTabNoChange)
          ? this.activePaneSessionId
          : activePaneSessionId as String?,
      splitAxis: nextSplitAxis,
      shellIntegration: shellIntegration ?? this.shellIntegration,
      oscBadge: identical(oscBadge, _terminalTabNoChange)
          ? this.oscBadge
          : oscBadge as String?,
      tabStatus: tabStatus ?? this.tabStatus,
      progress: identical(progress, _terminalTabNoChange)
          ? this.progress
          : progress as TerminalPaneProgressState?,
      namedProgress: namedProgress ?? this.namedProgress,
      recentNotifications: recentNotifications ?? this.recentNotifications,
    );
  }
}

const Object _terminalTabNoChange = Object();

String _terminalPaneSplitNodeId(String firstSessionId, String secondSessionId) {
  return 'split-$firstSessionId-$secondSessionId';
}

class TerminalShellPromptMark {
  const TerminalShellPromptMark({
    required this.globalLine,
    this.zoneId,
    this.command,
    this.cwd,
    this.promptKind,
    this.aid,
    this.parentAid,
  });

  /// Stable absolute history coordinate emitted by current native frames.
  final int globalLine;
  final int? zoneId;
  final String? command;
  final String? cwd;
  final String? promptKind;
  final String? aid;
  final String? parentAid;
}

int? terminalPromptMarkScrollbackOffset(
  TerminalShellPromptMark mark, {
  required int? globalBottomRow,
  required int scrollbackMaxOffset,
}) {
  if (scrollbackMaxOffset < 0) {
    return null;
  }
  if (globalBottomRow != null && globalBottomRow >= 0 && mark.globalLine >= 0) {
    return (globalBottomRow - mark.globalLine).clamp(0, scrollbackMaxOffset);
  }
  return null;
}

int? terminalPromptGlobalLineFromScrollbackOffset({
  required int? globalBottomRow,
  required int scrollbackMaxOffset,
  required int scrollbackOffset,
}) {
  if (globalBottomRow == null ||
      globalBottomRow < 0 ||
      scrollbackMaxOffset < 0 ||
      scrollbackOffset < 0 ||
      scrollbackOffset > scrollbackMaxOffset) {
    return null;
  }
  final globalLine = globalBottomRow - scrollbackOffset;
  return globalLine < 0 ? null : globalLine;
}

class TerminalShellIntegrationSnapshot {
  const TerminalShellIntegrationSnapshot({
    this.currentDirectory,
    this.hostname,
    this.username,
    this.shell,
    this.integrationVersion,
    this.lastCommand,
    this.lastExitCode,
    this.recentCommands = const <String>[],
    this.recentDirectories = const <String>[],
    this.promptMarks = const <TerminalShellPromptMark>[],
    this.userVariables = const <String, String>{},
  });

  static const empty = TerminalShellIntegrationSnapshot();

  final String? currentDirectory;
  final String? hostname;
  final String? username;
  final String? shell;
  final String? integrationVersion;
  final String? lastCommand;
  final int? lastExitCode;
  final List<String> recentCommands;
  final List<String> recentDirectories;
  final List<TerminalShellPromptMark> promptMarks;
  final Map<String, String> userVariables;

  TerminalShellIntegrationSnapshot copyWith({
    Object? currentDirectory = _shellIntegrationNoChange,
    Object? hostname = _shellIntegrationNoChange,
    Object? username = _shellIntegrationNoChange,
    Object? shell = _shellIntegrationNoChange,
    Object? integrationVersion = _shellIntegrationNoChange,
    Object? lastCommand = _shellIntegrationNoChange,
    Object? lastExitCode = _shellIntegrationNoChange,
    List<String>? recentCommands,
    List<String>? recentDirectories,
    List<TerminalShellPromptMark>? promptMarks,
    Map<String, String>? userVariables,
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
      integrationVersion:
          identical(integrationVersion, _shellIntegrationNoChange)
          ? this.integrationVersion
          : integrationVersion as String?,
      lastCommand: identical(lastCommand, _shellIntegrationNoChange)
          ? this.lastCommand
          : lastCommand as String?,
      lastExitCode: identical(lastExitCode, _shellIntegrationNoChange)
          ? this.lastExitCode
          : lastExitCode as int?,
      recentCommands: recentCommands ?? this.recentCommands,
      recentDirectories: recentDirectories ?? this.recentDirectories,
      promptMarks: promptMarks ?? this.promptMarks,
      userVariables: userVariables ?? this.userVariables,
    );
  }
}

const Object _shellIntegrationNoChange = Object();

class SessionState {
  factory SessionState({
    required List<TerminalTab> tabs,
    required String? activeSessionId,
    required List<TerminalProfile> profiles,
    required String? defaultProfileId,
    required String? configuredDefaultProfileId,
    required List<TerminalProfileLoadWarning> configurationWarnings,
    required TerminalThemeMode themeMode,
    required TerminalLanguageMode languageMode,
    required double terminalViewportPadding,
    required bool isReady,
    Set<String> recordingSessionIds = const <String>{},
    Set<String> recordingPendingSaveSessionIds = const <String>{},
    Set<String> recordingBusySessionIds = const <String>{},
    String? lastError,
  }) {
    return SessionState._(
      tabs: List.unmodifiable(tabs),
      activeSessionId: activeSessionId,
      profiles: List.unmodifiable(profiles),
      defaultProfileId: defaultProfileId,
      configuredDefaultProfileId: configuredDefaultProfileId,
      configurationWarnings: List.unmodifiable(configurationWarnings),
      themeMode: themeMode,
      languageMode: languageMode,
      terminalViewportPadding: terminalViewportPadding,
      isReady: isReady,
      recordingSessionIds: Set.unmodifiable(recordingSessionIds),
      recordingPendingSaveSessionIds: Set.unmodifiable(
        recordingPendingSaveSessionIds,
      ),
      recordingBusySessionIds: Set.unmodifiable(recordingBusySessionIds),
      lastError: lastError,
    );
  }

  const SessionState._({
    required this.tabs,
    required this.activeSessionId,
    required this.profiles,
    required this.defaultProfileId,
    required this.configuredDefaultProfileId,
    required this.configurationWarnings,
    required this.themeMode,
    required this.languageMode,
    required this.terminalViewportPadding,
    required this.isReady,
    required this.recordingSessionIds,
    required this.recordingPendingSaveSessionIds,
    required this.recordingBusySessionIds,
    this.lastError,
  });

  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final List<TerminalProfile> profiles;
  final String? defaultProfileId;
  final String? configuredDefaultProfileId;
  final List<TerminalProfileLoadWarning> configurationWarnings;
  final TerminalThemeMode themeMode;
  final TerminalLanguageMode languageMode;
  final double terminalViewportPadding;
  final bool isReady;
  final Set<String> recordingSessionIds;
  final Set<String> recordingPendingSaveSessionIds;
  final Set<String> recordingBusySessionIds;
  final String? lastError;

  factory SessionState.initial() {
    return const SessionState._(
      tabs: <TerminalTab>[],
      activeSessionId: null,
      profiles: <TerminalProfile>[],
      defaultProfileId: null,
      configuredDefaultProfileId: null,
      configurationWarnings: <TerminalProfileLoadWarning>[],
      themeMode: TerminalThemeMode.system,
      languageMode: TerminalLanguageMode.system,
      terminalViewportPadding:
          TerminalAppAppearance.defaultTerminalViewportPadding,
      isReady: false,
      recordingSessionIds: <String>{},
      recordingPendingSaveSessionIds: <String>{},
      recordingBusySessionIds: <String>{},
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
    TerminalLanguageMode? languageMode,
    double? terminalViewportPadding,
    bool? isReady,
    Set<String>? recordingSessionIds,
    Set<String>? recordingPendingSaveSessionIds,
    Set<String>? recordingBusySessionIds,
    Object? lastError = _sessionStateNoChange,
  }) {
    return SessionState._(
      tabs: tabs == null ? this.tabs : List.unmodifiable(tabs),
      activeSessionId: identical(activeSessionId, _sessionStateNoChange)
          ? this.activeSessionId
          : activeSessionId as String?,
      profiles: profiles == null ? this.profiles : List.unmodifiable(profiles),
      defaultProfileId: identical(defaultProfileId, _sessionStateNoChange)
          ? this.defaultProfileId
          : defaultProfileId as String?,
      configuredDefaultProfileId:
          identical(configuredDefaultProfileId, _sessionStateNoChange)
          ? this.configuredDefaultProfileId
          : configuredDefaultProfileId as String?,
      configurationWarnings: configurationWarnings == null
          ? this.configurationWarnings
          : List.unmodifiable(configurationWarnings),
      themeMode: themeMode ?? this.themeMode,
      languageMode: languageMode ?? this.languageMode,
      terminalViewportPadding:
          TerminalAppAppearance.normalizeTerminalViewportPadding(
            terminalViewportPadding ?? this.terminalViewportPadding,
          ),
      isReady: isReady ?? this.isReady,
      recordingSessionIds: recordingSessionIds == null
          ? this.recordingSessionIds
          : Set.unmodifiable(recordingSessionIds),
      recordingPendingSaveSessionIds: recordingPendingSaveSessionIds == null
          ? this.recordingPendingSaveSessionIds
          : Set.unmodifiable(recordingPendingSaveSessionIds),
      recordingBusySessionIds: recordingBusySessionIds == null
          ? this.recordingBusySessionIds
          : Set.unmodifiable(recordingBusySessionIds),
      lastError: identical(lastError, _sessionStateNoChange)
          ? this.lastError
          : lastError as String?,
    );
  }
}

const Object _sessionStateNoChange = Object();
