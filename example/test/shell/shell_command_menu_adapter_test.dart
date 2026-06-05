import 'package:app/features/policies/local_terminal_policy_action_reducer.dart';
import 'package:app/features/productivity/command_blocks_history_feature_flags.dart';
import 'package:app/features/productivity/shell_productivity_action_reducer.dart';
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/shell/shell_action_dispatcher.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_command_menu_adapter.dart';
import 'package:app/features/shell/shell_action_runtime_controller.dart';
import 'package:app/features/visual/local_terminal_visual_action_reducer.dart';
import 'package:app/features/workspace/local_workspace_action_reducer.dart';
import 'package:app/features/workspace/local_workspace_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shell command menu adapter', () {
    test('builds command menu items from action view models', () {
      final adapter = ShellCommandMenuAdapter(
        runtimeController: ShellActionRuntimeController(),
      );

      final items = adapter.items(hasActiveSession: true);

      expect(
        items.any((item) => item.actionId == TerminalActionId.newTab),
        isTrue,
      );
      expect(
        items.any((item) => item.actionId == TerminalActionId.openThemePicker),
        isTrue,
      );
    });

    test('passes command block gate inputs into menu items', () {
      final adapter = ShellCommandMenuAdapter(
        runtimeController: ShellActionRuntimeController(),
      );

      final items = adapter.items(
        hasActiveSession: true,
        commandBlocksHistory: _commandBlocksHistoryFlags,
        hasCommandBlocks: true,
      );

      final historyPeek = items.singleWhere(
        (item) => item.actionId == TerminalActionId.openHistoryPeek,
      );

      expect(historyPeek.enabled, isTrue);
    });

    test('select runs action through runtime controller', () async {
      final adapter = ShellCommandMenuAdapter(
        runtimeController: ShellActionRuntimeController(),
      );

      final state = await adapter.select(
        actionId: TerminalActionId.newTab,
        context: _context(),
      );

      expect(state.workspace.activeTabId, 'tab-next');
    });
  });
}

ShellActionDispatchContext _context() {
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
    policy: const LocalTerminalPolicyActionContext(),
    visual: const LocalTerminalVisualActionContext(),
  );
}

const _commandBlocksHistoryFlags = CommandBlocksHistoryFeatureFlags(
  enabled: true,
  commandBlocks: true,
  historyPeek: true,
  failureSnapshots: true,
  reviewWorkspaceEntrypoints: true,
  outputDiff: true,
);
