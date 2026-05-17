import '../workspace/local_workspace_models.dart';
import 'local_terminal_visual_models.dart';

class LocalTerminalLayoutTemplateApplyContext {
  const LocalTerminalLayoutTemplateApplyContext({
    required this.tabId,
    required this.firstPaneId,
    required this.secondPaneId,
    required this.splitNodeId,
    required this.sessionIntent,
  });

  final String tabId;
  final String firstPaneId;
  final String secondPaneId;
  final String splitNodeId;
  final TerminalPaneSessionIntent sessionIntent;
}

class LocalTerminalLayoutTemplateApplier {
  const LocalTerminalLayoutTemplateApplier._();

  static TerminalWorkspace? apply({
    required LocalTerminalLayoutTemplate template,
    required LocalTerminalLayoutTemplateApplyContext context,
  }) {
    if (!template.canApply) {
      return null;
    }

    final root = template.paneCount <= 1
        ? TerminalPaneNode.leaf(
            id: context.firstPaneId,
            sessionIntent: context.sessionIntent,
          )
        : TerminalPaneNode.split(
            id: context.splitNodeId,
            direction: TerminalPaneSplitDirection.right,
            first: TerminalPaneNode.leaf(
              id: context.firstPaneId,
              sessionIntent: context.sessionIntent,
            ),
            second: TerminalPaneNode.leaf(
              id: context.secondPaneId,
              sessionIntent: context.sessionIntent,
            ),
          );

    return TerminalWorkspace().addTab(
      TerminalWorkspaceTab(
        id: context.tabId,
        root: root,
        activePaneId: context.firstPaneId,
      ),
    );
  }
}
