import 'package:app/features/policies/local_terminal_policy_action_reducer.dart';
import 'package:app/features/productivity/shell_productivity_action_reducer.dart';
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/shell/shell_action_dispatcher.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/visual/local_terminal_visual_action_reducer.dart';
import 'package:app/features/workspace/local_workspace_action_reducer.dart';
import 'package:app/features/workspace/local_workspace_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shell action dispatcher', () {
    test('dispatches workspace actions first', () {
      final result = ShellActionDispatcher.dispatch(
        actionId: TerminalActionId.newTab,
        state: const ShellActionDispatchState(),
        context: _context(),
      );

      expect(result, isA<ShellWorkspaceDispatchResult>());
      expect(
        (result as ShellWorkspaceDispatchResult).workspace.activeTabId,
        'tab-next',
      );
    });

    test('dispatches productivity actions when workspace is unchanged', () {
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

    test(
      'dispatches policy actions when workspace and productivity are noop',
      () {
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
      },
    );

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
    workspace: const LocalWorkspaceActionContext(
      nextTabId: 'tab-next',
      nextPaneId: 'pane-next',
      nextSplitId: 'split-next',
      fallbackIntent: TerminalPaneSessionIntent(profileId: 'default'),
    ),
    productivity: const ShellProductivityActionContext(
      currentRow: 0,
      search: ShellSearchState(),
    ),
    policy: LocalTerminalPolicyActionContext(pasteText: pasteText),
    visual: const LocalTerminalVisualActionContext(),
  );
}
