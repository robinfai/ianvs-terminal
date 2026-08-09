import 'package:app/features/layout/local_terminal_layout_models.dart';
import 'package:app/features/layout/terminal_layout_action_reducer.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local layout action reducer', () {
    test('new tab action creates a local tab from fallback intent', () {
      final layout = TerminalLayoutActionReducer.reduce(
        layout: const TerminalLayout(),
        actionId: TerminalActionId.newTab,
        context: _context(tab: 'tab-1', pane: 'pane-1'),
      );

      expect(layout.activeTabId, 'tab-1');
      expect(layout.activeTab!.activeSessionIntent!.profileId, 'default');
    });

    test('split actions update active tab pane tree', () {
      final initial = TerminalLayoutActionReducer.reduce(
        layout: const TerminalLayout(),
        actionId: TerminalActionId.newTab,
        context: _context(tab: 'tab-1', pane: 'pane-1'),
      );
      final split = TerminalLayoutActionReducer.reduce(
        layout: initial,
        actionId: TerminalActionId.splitRight,
        context: _context(tab: 'unused', pane: 'pane-2', split: 'split-1'),
      );

      expect(split.activeTab!.root.containsPane('pane-1'), isTrue);
      expect(split.activeTab!.root.containsPane('pane-2'), isTrue);
      expect(split.activeTab!.root.direction, TerminalPaneSplitDirection.right);
    });

    test('split action recovers a stale active pane id', () {
      final layout = TerminalLayout(
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

      final split = TerminalLayoutActionReducer.reduce(
        layout: layout,
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
      final initial = TerminalLayoutActionReducer.reduce(
        layout: const TerminalLayout(),
        actionId: TerminalActionId.newTab,
        context: _context(tab: 'tab-1', pane: 'pane-1'),
      );
      final split = TerminalLayoutActionReducer.reduce(
        layout: initial,
        actionId: TerminalActionId.splitRight,
        context: _context(pane: 'pane-2', split: 'split-1'),
      );

      final previous = TerminalLayoutActionReducer.reduce(
        layout: split,
        actionId: TerminalActionId.focusPreviousPane,
        context: _context(),
      );
      final next = TerminalLayoutActionReducer.reduce(
        layout: previous,
        actionId: TerminalActionId.focusNextPane,
        context: _context(),
      );
      final resized = TerminalLayoutActionReducer.reduce(
        layout: next,
        actionId: TerminalActionId.resizePane,
        context: _context(),
      );

      expect(split.activeTab!.activePaneId, 'pane-2');
      expect(previous.activeTab!.activePaneId, 'pane-1');
      expect(next.activeTab!.activePaneId, 'pane-2');
      expect(resized.activeTab!.root.ratio, closeTo(0.42, 0.0001));
    });

    test('close and reopen tab actions roundtrip closed tab stack', () {
      final initial = TerminalLayoutActionReducer.reduce(
        layout: const TerminalLayout(),
        actionId: TerminalActionId.newTab,
        context: _context(tab: 'tab-1', pane: 'pane-1'),
      );
      final closed = TerminalLayoutActionReducer.reduce(
        layout: initial,
        actionId: TerminalActionId.closeActiveTab,
        context: _context(),
      );
      final reopened = TerminalLayoutActionReducer.reduce(
        layout: closed,
        actionId: TerminalActionId.reopenClosedTab,
        context: _context(),
      );

      expect(closed.isEmpty, isTrue);
      expect(reopened.activeTabId, 'tab-1');
    });

    test('unhandled action leaves layout unchanged', () {
      const layout = TerminalLayout();
      final reduced = TerminalLayoutActionReducer.reduce(
        layout: layout,
        actionId: TerminalActionId.openThemePicker,
        context: _context(),
      );

      expect(identical(reduced, layout), isTrue);
    });
  });
}

TerminalLayoutActionContext _context({
  String tab = 'tab-next',
  String pane = 'pane-next',
  String split = 'split-next',
}) {
  return TerminalLayoutActionContext(
    nextTabId: tab,
    nextPaneId: pane,
    nextSplitId: split,
    fallbackIntent: const TerminalRelaunchSpec(profileId: 'default'),
  );
}
