import 'package:app/features/policies/local_terminal_policy_action_reducer.dart';
import 'package:app/features/productivity/shell_productivity_action_reducer.dart';
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/shell/shell_action_dispatcher.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/visual/local_terminal_visual_action_reducer.dart';
import 'package:app/features/layout/terminal_layout_action_reducer.dart';
import 'package:app/features/layout/local_terminal_layout_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shell action dispatcher', () {
    test('dispatches layout actions first', () {
      final result = ShellActionDispatcher.dispatch(
        actionId: TerminalActionId.newTab,
        state: const ShellActionDispatchState(),
        context: _context(),
      );

      expect(result, isA<ShellLayoutDispatchResult>());
      expect(
        (result as ShellLayoutDispatchResult).layout.activeTabId,
        'tab-next',
      );
    });

    test('dispatches pane focus actions through layout reducer', () {
      final layout = const TerminalLayout().addTab(
        TerminalLayoutTab(
          id: 'tab-1',
          activePaneId: 'pane-2',
          root: TerminalPaneNode.split(
            id: 'split-1',
            direction: TerminalPaneSplitDirection.right,
            first: TerminalPaneNode.leaf(
              id: 'pane-1',
              sessionIntent: TerminalRelaunchSpec(profileId: 'default'),
            ),
            second: TerminalPaneNode.leaf(
              id: 'pane-2',
              sessionIntent: TerminalRelaunchSpec(profileId: 'default'),
            ),
          ),
        ),
      );

      final result = ShellActionDispatcher.dispatch(
        actionId: TerminalActionId.focusPreviousPane,
        state: ShellActionDispatchState(layout: layout),
        context: _context(),
      );

      expect(result, isA<ShellLayoutDispatchResult>());
      expect(
        (result as ShellLayoutDispatchResult).layout.activeTab!.activePaneId,
        'pane-1',
      );
    });

    test('dispatches productivity actions when layout is unchanged', () {
      final result = ShellActionDispatcher.dispatch(
        actionId: TerminalActionId.toggleReadOnly,
        state: const ShellActionDispatchState(),
        context: _context(),
      );

      expect(result, isA<ShellProductivityDispatchResult>());
      expect(
        (result as ShellProductivityDispatchResult).result,
        isA<ShellProductivityStateResult>(),
      );
    });

    test('dispatches policy actions when layout and productivity are noop', () {
      final result = ShellActionDispatcher.dispatch(
        actionId: TerminalActionId.paste,
        state: const ShellActionDispatchState(),
        context: _context(pasteText: 'hello'),
      );

      expect(result, isA<ShellPolicyDispatchResult>());
      expect(
        (result as ShellPolicyDispatchResult).result,
        isA<LocalTerminalPasteActionResult>(),
      );
    });

    test('dispatches visual actions when other reducers are noop', () {
      final result = ShellActionDispatcher.dispatch(
        actionId: TerminalActionId.openThemePicker,
        state: const ShellActionDispatchState(),
        context: _context(),
      );

      expect(result, isA<ShellVisualDispatchResult>());
      expect(
        (result as ShellVisualDispatchResult).result,
        isA<LocalTerminalOpenThemePickerResult>(),
      );
    });

    test('returns unhandled for actions without reducer mapping', () {
      final result = ShellActionDispatcher.dispatch(
        actionId: TerminalActionId.openDefaults,
        state: const ShellActionDispatchState(),
        context: _context(),
      );

      expect(result, isA<ShellUnhandledDispatchResult>());
    });
  });
}

ShellActionDispatchContext _context({String pasteText = ''}) {
  return ShellActionDispatchContext(
    layout: const TerminalLayoutActionContext(
      nextTabId: 'tab-next',
      nextPaneId: 'pane-next',
      nextSplitId: 'split-next',
      fallbackIntent: TerminalRelaunchSpec(profileId: 'default'),
    ),
    productivity: const ShellProductivityActionContext(
      currentRow: 0,
      search: ShellSearchState(),
    ),
    policy: LocalTerminalPolicyActionContext(pasteText: pasteText),
    visual: const LocalTerminalVisualActionContext(),
  );
}
