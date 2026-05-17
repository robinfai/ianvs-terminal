import '../shell/shell_action_registry.dart';
import 'local_workspace_models.dart';

class LocalWorkspaceActionContext {
  const LocalWorkspaceActionContext({
    required this.nextTabId,
    required this.nextPaneId,
    required this.nextSplitId,
    required this.fallbackIntent,
  });

  final String nextTabId;
  final String nextPaneId;
  final String nextSplitId;
  final TerminalPaneSessionIntent fallbackIntent;
}

class LocalWorkspaceActionReducer {
  const LocalWorkspaceActionReducer._();

  static TerminalWorkspace reduce({
    required TerminalWorkspace workspace,
    required TerminalActionId actionId,
    required LocalWorkspaceActionContext context,
  }) {
    return switch (actionId) {
      TerminalActionId.newTab => workspace.addTabFromActivePane(
        tabId: context.nextTabId,
        paneId: context.nextPaneId,
        fallbackIntent: context.fallbackIntent,
      ),
      TerminalActionId.duplicateCurrentCwd => workspace.addTabFromActivePane(
        tabId: context.nextTabId,
        paneId: context.nextPaneId,
        fallbackIntent: context.fallbackIntent,
      ),
      TerminalActionId.splitRight => workspace.splitActivePaneFromActiveCwd(
        splitNodeId: context.nextSplitId,
        newPaneId: context.nextPaneId,
        direction: TerminalPaneSplitDirection.right,
        fallbackIntent: context.fallbackIntent,
      ),
      TerminalActionId.splitDown => workspace.splitActivePaneFromActiveCwd(
        splitNodeId: context.nextSplitId,
        newPaneId: context.nextPaneId,
        direction: TerminalPaneSplitDirection.down,
        fallbackIntent: context.fallbackIntent,
      ),
      TerminalActionId.closeActiveTab => workspace.closeActiveTab(),
      TerminalActionId.reopenClosedTab => workspace.reopenClosedTab(),
      TerminalActionId.closePane => workspace.updateActiveTab(
        (tab) => tab.closeActivePane(),
      ),
      TerminalActionId.reopenClosedPane => workspace.updateActiveTab(
        (tab) => tab.reopenClosedPane(splitNodeId: context.nextSplitId),
      ),
      TerminalActionId.zoomPane => workspace.updateActiveTab(
        (tab) => tab.toggleZoomActivePane(),
      ),
      TerminalActionId.swapPane => workspace.updateActiveTab(
        (tab) => tab.swapActivePaneWithSibling(),
      ),
      _ => workspace,
    };
  }
}
