import 'package:app/features/policies/local_terminal_policy_action_reducer.dart';
import 'package:app/features/productivity/shell_productivity_action_reducer.dart';
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/shell/shell_action_dispatcher.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_command_menu_adapter.dart';
import 'package:app/features/shell/shell_action_runtime_controller.dart';
import 'package:app/features/visual/local_terminal_visual_action_reducer.dart';
import 'package:app/features/layout/terminal_layout_action_reducer.dart';
import 'package:app/features/layout/local_terminal_layout_models.dart';
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
        isFalse,
      );
      expect(
        items.any((item) => item.actionId == TerminalActionId.openRecording),
        isTrue,
      );
    });

    test('select runs action through runtime controller', () async {
      final adapter = ShellCommandMenuAdapter(
        runtimeController: ShellActionRuntimeController(),
      );

      final state = await adapter.select(
        actionId: TerminalActionId.newTab,
        context: _context(),
      );

      expect(state.layout.activeTabId, 'tab-next');
    });
  });
}

ShellActionDispatchContext _context() {
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
    policy: const LocalTerminalPolicyActionContext(),
    visual: const LocalTerminalVisualActionContext(),
  );
}
