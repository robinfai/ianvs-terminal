import '../profiles/profile_models.dart';
import '../sessions/session_state.dart';
import 'local_workspace_models.dart';

typedef LocalWorkspaceSessionRelauncher =
    TerminalPane? Function(TerminalSessionDescriptor descriptor);

class LocalWorkspaceRelaunchFailure {
  const LocalWorkspaceRelaunchFailure({
    required this.paneId,
    required this.intent,
    this.error,
  });

  final String paneId;
  final TerminalSessionDescriptor intent;
  final Object? error;
}

class LocalWorkspaceRestoreResult {
  LocalWorkspaceRestoreResult({
    required List<TerminalTab> tabs,
    required this.activeSessionId,
    required List<LocalWorkspaceRelaunchFailure> failures,
  }) : tabs = List.unmodifiable(tabs),
       failures = List.unmodifiable(failures);

  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final List<LocalWorkspaceRelaunchFailure> failures;
}

class LocalSessionWorkspaceCodec {
  const LocalSessionWorkspaceCodec._();

  static TerminalWorkspace capture(
    SessionState state, {
    TerminalWorkspaceIdentity identity =
        TerminalWorkspaceIdentity.defaultWorkspace,
  }) {
    final profilesById = <String, TerminalProfile>{
      for (final profile in state.profiles) profile.id: profile,
    };
    final tabs = <TerminalWorkspaceTab>[
      for (final tab in state.tabs)
        TerminalWorkspaceTab(
          id: tab.sessionId,
          root: _captureNode(tab.effectivePaneLayout, profilesById),
          activePaneId: tab.activeSessionId,
        ),
    ];
    final activeTabId = state.activeSessionId == null
        ? null
        : state.tabs
              .where((tab) => tab.containsSession(state.activeSessionId!))
              .firstOrNull
              ?.sessionId;
    return TerminalWorkspace(
      identity: identity,
      tabs: tabs,
      activeTabId: activeTabId,
    );
  }

  static LocalWorkspaceRestoreResult restore(
    TerminalWorkspace workspace, {
    required LocalWorkspaceSessionRelauncher relaunch,
  }) {
    final failures = <LocalWorkspaceRelaunchFailure>[];
    final tabs = <TerminalTab>[];
    final activeSessionIdByOldTabId = <String, String>{};

    for (final sourceTab in workspace.tabs) {
      final restored = _restoreNode(
        sourceTab.root,
        relaunch: relaunch,
        failures: failures,
      );
      if (restored == null) {
        continue;
      }
      final layout = restored.layout;
      final rootPane = layout.panes.first;
      final activeSessionId =
          restored.sessionIdByOldPaneId[sourceTab.effectiveActivePaneId] ??
          rootPane.sessionId;
      tabs.add(
        TerminalTab(
          sessionId: rootPane.sessionId,
          title: rootPane.title,
          profileId: rootPane.profileId,
          profileSnapshot: rootPane.profileSnapshot,
          panes: layout.panes,
          paneLayout: layout,
          activePaneSessionId: activeSessionId == rootPane.sessionId
              ? null
              : activeSessionId,
          splitAxis: layout.isLeaf
              ? TerminalSplitAxis.horizontal
              : layout.splitAxis!,
        ),
      );
      activeSessionIdByOldTabId[sourceTab.id] = activeSessionId;
    }

    final activeSessionId =
        activeSessionIdByOldTabId[workspace.activeTabId] ??
        (tabs.isEmpty ? null : tabs.first.activeSessionId);
    return LocalWorkspaceRestoreResult(
      tabs: tabs,
      activeSessionId: activeSessionId,
      failures: failures,
    );
  }

  static TerminalPaneNode _captureNode(
    TerminalPaneLayoutNode node,
    Map<String, TerminalProfile> profilesById,
  ) {
    if (node.isLeaf) {
      final pane = node.pane!;
      final profile = pane.profileSnapshot ?? profilesById[pane.profileId];
      final configuredProfile = profilesById[pane.profileId];
      final priorDescriptor = pane.sessionDescriptor;
      final commandProfile = profile ?? configuredProfile;
      final descriptor = TerminalSessionDescriptor(
        id: _nonEmpty(priorDescriptor?.id) ?? pane.sessionId,
        profileId: pane.profileId,
        command: commandProfile == null
            ? priorDescriptor?.command
            : TerminalSessionCommand(
                program: commandProfile.shell,
                arguments: commandProfile.args,
              ),
        cwd:
            _nonEmpty(pane.shellIntegration.currentDirectory) ??
            _nonEmpty(profile?.cwd) ??
            priorDescriptor?.cwd,
        environment: commandProfile == null
            ? priorDescriptor?.environment ??
                  const TerminalSessionEnvironmentMetadata()
            : TerminalSessionEnvironmentMetadata(
                keys: (commandProfile.env.keys.toList(growable: false)..sort()),
              ),
        title: _nonEmpty(pane.title),
        createdAtUtc: priorDescriptor?.createdAtUtc,
        exitState: pane.isExited
            ? TerminalSessionExitState.exited
            : TerminalSessionExitState.running,
        exitCode: pane.isExited ? pane.exitCode : null,
        recordingPath: priorDescriptor?.recordingPath,
        restartPolicy:
            priorDescriptor?.restartPolicy ??
            TerminalSessionRestartPolicy.relaunch,
      );
      return TerminalPaneNode.leaf(
        id: pane.sessionId,
        sessionDescriptor: descriptor,
      );
    }
    return TerminalPaneNode.split(
      id: node.id,
      direction: node.splitAxis == TerminalSplitAxis.horizontal
          ? TerminalPaneSplitDirection.right
          : TerminalPaneSplitDirection.down,
      first: _captureNode(node.first!, profilesById),
      second: _captureNode(node.second!, profilesById),
      ratio: node.ratio,
    );
  }

  static _RestoredPaneNode? _restoreNode(
    TerminalPaneNode node, {
    required LocalWorkspaceSessionRelauncher relaunch,
    required List<LocalWorkspaceRelaunchFailure> failures,
  }) {
    if (node.isLeaf) {
      final intent = node.sessionDescriptor!;
      try {
        if (intent.restartPolicy == TerminalSessionRestartPolicy.never) {
          throw StateError('Session restart policy is never.');
        }
        final pane = relaunch(intent);
        if (pane == null) {
          failures.add(
            LocalWorkspaceRelaunchFailure(paneId: node.id, intent: intent),
          );
          return null;
        }
        return _RestoredPaneNode(
          layout: TerminalPaneLayoutNode.leaf(pane),
          sessionIdByOldPaneId: {node.id: pane.sessionId},
        );
      } on Object catch (error) {
        failures.add(
          LocalWorkspaceRelaunchFailure(
            paneId: node.id,
            intent: intent,
            error: error,
          ),
        );
        return null;
      }
    }

    final first = _restoreNode(
      node.children.first,
      relaunch: relaunch,
      failures: failures,
    );
    final second = _restoreNode(
      node.children[1],
      relaunch: relaunch,
      failures: failures,
    );
    if (first == null) {
      return second;
    }
    if (second == null) {
      return first;
    }
    return _RestoredPaneNode(
      layout: TerminalPaneLayoutNode.split(
        id: node.id,
        splitAxis: node.direction == TerminalPaneSplitDirection.right
            ? TerminalSplitAxis.horizontal
            : TerminalSplitAxis.vertical,
        first: first.layout,
        second: second.layout,
        ratio: node.ratio,
      ),
      sessionIdByOldPaneId: {
        ...first.sessionIdByOldPaneId,
        ...second.sessionIdByOldPaneId,
      },
    );
  }
}

class _RestoredPaneNode {
  const _RestoredPaneNode({
    required this.layout,
    required this.sessionIdByOldPaneId,
  });

  final TerminalPaneLayoutNode layout;
  final Map<String, String> sessionIdByOldPaneId;
}

String? _nonEmpty(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
