import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/workspace/local_workspace_action_reducer.dart';
import 'package:app/features/workspace/local_workspace_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local workspace action reducer', () {
    test('new tab action creates a local tab from fallback intent', () {
      final workspace = LocalWorkspaceActionReducer.reduce(
        workspace: const TerminalWorkspace(),
        actionId: TerminalActionId.newTab,
        context: _context(tab: 'tab-1', pane: 'pane-1'),
      );

      expect(workspace.activeTabId, 'tab-1');
      expect(workspace.activeTab!.activeSessionIntent!.profileId, 'default');
    });

    test('split actions update active tab pane tree', () {
      final initial = LocalWorkspaceActionReducer.reduce(
        workspace: const TerminalWorkspace(),
        actionId: TerminalActionId.newTab,
        context: _context(tab: 'tab-1', pane: 'pane-1'),
      );
      final split = LocalWorkspaceActionReducer.reduce(
        workspace: initial,
        actionId: TerminalActionId.splitRight,
        context: _context(tab: 'unused', pane: 'pane-2', split: 'split-1'),
      );

      expect(split.activeTab!.root.containsPane('pane-1'), isTrue);
      expect(split.activeTab!.root.containsPane('pane-2'), isTrue);
      expect(split.activeTab!.root.direction, TerminalPaneSplitDirection.right);
    });

    test('close and reopen tab actions roundtrip closed tab stack', () {
      final initial = LocalWorkspaceActionReducer.reduce(
        workspace: const TerminalWorkspace(),
        actionId: TerminalActionId.newTab,
        context: _context(tab: 'tab-1', pane: 'pane-1'),
      );
      final closed = LocalWorkspaceActionReducer.reduce(
        workspace: initial,
        actionId: TerminalActionId.closeActiveTab,
        context: _context(),
      );
      final reopened = LocalWorkspaceActionReducer.reduce(
        workspace: closed,
        actionId: TerminalActionId.reopenClosedTab,
        context: _context(),
      );

      expect(closed.isEmpty, isTrue);
      expect(reopened.activeTabId, 'tab-1');
    });

    test('unhandled action leaves workspace unchanged', () {
      const workspace = TerminalWorkspace();
      final reduced = LocalWorkspaceActionReducer.reduce(
        workspace: workspace,
        actionId: TerminalActionId.openThemePicker,
        context: _context(),
      );

      expect(identical(reduced, workspace), isTrue);
    });
  });
}

LocalWorkspaceActionContext _context({
  String tab = 'tab-next',
  String pane = 'pane-next',
  String split = 'split-next',
}) {
  return LocalWorkspaceActionContext(
    nextTabId: tab,
    nextPaneId: pane,
    nextSplitId: split,
    fallbackIntent: const TerminalPaneSessionIntent(profileId: 'default'),
  );
}
