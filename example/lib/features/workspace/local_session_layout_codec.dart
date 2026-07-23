import '../profiles/profile_models.dart';
import '../sessions/session_state.dart';
import 'local_terminal_layout_models.dart';

typedef LocalTerminalLayoutSessionRelauncher =
    TerminalPane? Function(TerminalRelaunchSpec spec);

class LocalTerminalLayoutRelaunchFailure {
  const LocalTerminalLayoutRelaunchFailure({
    required this.paneId,
    required this.intent,
    this.error,
  });

  final String paneId;
  final TerminalRelaunchSpec intent;
  final Object? error;
}

class LocalTerminalLayoutRestoreResult {
  LocalTerminalLayoutRestoreResult({
    required List<TerminalTab> tabs,
    required this.activeSessionId,
    required List<LocalTerminalLayoutRelaunchFailure> failures,
  }) : tabs = List.unmodifiable(tabs),
       failures = List.unmodifiable(failures);

  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final List<LocalTerminalLayoutRelaunchFailure> failures;
}

class LocalSessionLayoutCodec {
  const LocalSessionLayoutCodec._();

  static TerminalLayout capture(SessionState state) {
    final profilesById = <String, TerminalProfile>{
      for (final profile in state.profiles) profile.id: profile,
    };
    final tabs = <TerminalLayoutTab>[
      for (final tab in state.tabs)
        TerminalLayoutTab(
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
    return TerminalLayout(tabs: tabs, activeTabId: activeTabId);
  }

  static LocalTerminalLayoutRestoreResult restore(
    TerminalLayout workspace, {
    required LocalTerminalLayoutSessionRelauncher relaunch,
  }) {
    final failures = <LocalTerminalLayoutRelaunchFailure>[];
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
    return LocalTerminalLayoutRestoreResult(
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
      final priorSpec = pane.relaunchSpec;
      final commandProfile = profile ?? configuredProfile;
      final spec = TerminalRelaunchSpec(
        profileId: pane.profileId,
        command: commandProfile == null
            ? priorSpec?.command
            : TerminalRelaunchCommand(
                program: commandProfile.shell,
                arguments: commandProfile.args,
              ),
        cwd:
            _nonEmpty(pane.shellIntegration.currentDirectory) ??
            _nonEmpty(profile?.cwd) ??
            priorSpec?.cwd,
      );
      return TerminalPaneNode.leaf(id: pane.sessionId, relaunchSpec: spec);
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
    required LocalTerminalLayoutSessionRelauncher relaunch,
    required List<LocalTerminalLayoutRelaunchFailure> failures,
  }) {
    if (node.isLeaf) {
      final intent = node.relaunchSpec!;
      try {
        final pane = relaunch(intent);
        if (pane == null) {
          failures.add(
            LocalTerminalLayoutRelaunchFailure(paneId: node.id, intent: intent),
          );
          return null;
        }
        return _RestoredPaneNode(
          layout: TerminalPaneLayoutNode.leaf(pane),
          sessionIdByOldPaneId: {node.id: pane.sessionId},
        );
      } on Object catch (error) {
        failures.add(
          LocalTerminalLayoutRelaunchFailure(
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
