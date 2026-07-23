import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/workspace/local_workspace_action_reducer.dart';
import 'package:app/features/workspace/local_terminal_layout_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local workspace action reducer', () {
    test('new tab action creates a local tab from fallback intent', () {
      final workspace = LocalWorkspaceActionReducer.reduce(
        workspace: const TerminalLayout(),
        actionId: TerminalActionId.newTab,
        context: _context(tab: 'tab-1', pane: 'pane-1'),
      );

      expect(workspace.activeTabId, 'tab-1');
      expect(workspace.activeTab!.activeSessionIntent!.profileId, 'default');
    });

    test('split actions update active tab pane tree', () {
      final initial = LocalWorkspaceActionReducer.reduce(
        workspace: const TerminalLayout(),
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

    test('split action recovers a stale active pane id', () {
      final workspace = TerminalLayout(
        tabs: [
          TerminalLayoutTab(
            id: 'tab-1',
            activePaneId: 'missing-pane',
            root: TerminalPaneNode.leaf(
              id: 'pane-1',
              sessionIntent: const TerminalRelaunchSpec(
                profileId: 'default',
                cwd: '/project',
              ),
            ),
          ),
        ],
        activeTabId: 'tab-1',
      );

      final split = LocalWorkspaceActionReducer.reduce(
        workspace: workspace,
        actionId: TerminalActionId.splitDown,
        context: _context(pane: 'pane-2', split: 'split-1'),
      );

      expect(split.activeTab!.root.containsPane('pane-1'), isTrue);
      expect(split.activeTab!.root.containsPane('pane-2'), isTrue);
      expect(split.activeTab!.activePaneId, 'pane-2');
      expect(
        split.activeTab!.root.findPane('pane-2')!.sessionIntent!.cwd,
        '/project',
      );
    });

    test('focus and resize pane actions update active tab pane state', () {
      final initial = LocalWorkspaceActionReducer.reduce(
        workspace: const TerminalLayout(),
        actionId: TerminalActionId.newTab,
        context: _context(tab: 'tab-1', pane: 'pane-1'),
      );
      final split = LocalWorkspaceActionReducer.reduce(
        workspace: initial,
        actionId: TerminalActionId.splitRight,
        context: _context(pane: 'pane-2', split: 'split-1'),
      );

      final previous = LocalWorkspaceActionReducer.reduce(
        workspace: split,
        actionId: TerminalActionId.focusPreviousPane,
        context: _context(),
      );
      final next = LocalWorkspaceActionReducer.reduce(
        workspace: previous,
        actionId: TerminalActionId.focusNextPane,
        context: _context(),
      );
      final resized = LocalWorkspaceActionReducer.reduce(
        workspace: next,
        actionId: TerminalActionId.resizePane,
        context: _context(),
      );

      expect(split.activeTab!.activePaneId, 'pane-2');
      expect(previous.activeTab!.activePaneId, 'pane-1');
      expect(next.activeTab!.activePaneId, 'pane-2');
      expect(resized.activeTab!.root.ratio, closeTo(0.42, 0.0001));
    });

    test('close and reopen tab actions roundtrip closed tab stack', () {
      final initial = LocalWorkspaceActionReducer.reduce(
        workspace: const TerminalLayout(),
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
      const workspace = TerminalLayout();
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
    fallbackIntent: const TerminalRelaunchSpec(profileId: 'default'),
  );
}
