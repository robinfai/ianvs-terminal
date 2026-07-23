import '../shell/shell_action_registry.dart';
import 'local_terminal_layout_models.dart';

class TerminalLayoutActionContext {
  const TerminalLayoutActionContext({
    required this.nextTabId,
    required this.nextPaneId,
    required this.nextSplitId,
    required this.fallbackIntent,
    this.paneResizeDelta = 0.08,
  });

  final String nextTabId;
  final String nextPaneId;
  final String nextSplitId;
  final TerminalRelaunchSpec fallbackIntent;
  final double paneResizeDelta;
}

class TerminalLayoutActionReducer {
  const TerminalLayoutActionReducer._();

  static TerminalLayout reduce({
    required TerminalLayout layout,
    required TerminalActionId actionId,
    required TerminalLayoutActionContext context,
  }) {
    return switch (actionId) {
      TerminalActionId.newTab => layout.addTabFromActivePane(
        tabId: context.nextTabId,
        paneId: context.nextPaneId,
        fallbackIntent: context.fallbackIntent,
      ),
      TerminalActionId.duplicateCurrentCwd => layout.addTabFromActivePane(
        tabId: context.nextTabId,
        paneId: context.nextPaneId,
        fallbackIntent: context.fallbackIntent,
      ),
      TerminalActionId.splitRight => layout.splitActivePaneFromActiveCwd(
        splitNodeId: context.nextSplitId,
        newPaneId: context.nextPaneId,
        direction: TerminalPaneSplitDirection.right,
        fallbackIntent: context.fallbackIntent,
      ),
      TerminalActionId.splitDown => layout.splitActivePaneFromActiveCwd(
        splitNodeId: context.nextSplitId,
        newPaneId: context.nextPaneId,
        direction: TerminalPaneSplitDirection.down,
        fallbackIntent: context.fallbackIntent,
      ),
      TerminalActionId.closeActiveTab => layout.closeActiveTab(),
      TerminalActionId.reopenClosedTab => layout.reopenClosedTab(),
      TerminalActionId.closePane => layout.updateActiveTab(
        (tab) => tab.closeActivePane(),
      ),
      TerminalActionId.reopenClosedPane => layout.updateActiveTab(
        (tab) => tab.reopenClosedPane(splitNodeId: context.nextSplitId),
      ),
      TerminalActionId.focusNextPane => layout.updateActiveTab(
        (tab) => tab.focusRelativePane(1),
      ),
      TerminalActionId.focusPreviousPane => layout.updateActiveTab(
        (tab) => tab.focusRelativePane(-1),
      ),
      TerminalActionId.resizePane => layout.updateActiveTab(
        (tab) => tab.growActivePane(context.paneResizeDelta),
      ),
      TerminalActionId.zoomPane => layout.updateActiveTab(
        (tab) => tab.toggleZoomActivePane(),
      ),
      TerminalActionId.swapPane => layout.updateActiveTab(
        (tab) => tab.swapActivePaneWithSibling(),
      ),
      _ => layout,
    };
  }
}
