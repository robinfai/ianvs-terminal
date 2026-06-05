import 'package:app/features/policies/local_terminal_paste_decision.dart';
import 'package:app/features/policies/local_terminal_policy_action_reducer.dart';
import 'package:app/features/productivity/shell_productivity_action_reducer.dart';
import 'package:app/features/shell/shell_action_dispatcher.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_action_side_effect_plan.dart';
import 'package:app/features/visual/local_terminal_visual_action_reducer.dart';
import 'package:app/features/workspace/local_workspace_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shell action side effect planner', () {
    test('maps workspace dispatch to update workspace plan', () {
      final plan = ShellActionSideEffectPlanner.plan(
        const ShellWorkspaceDispatchResult(TerminalWorkspace()),
      );

      expect(plan.kind, ShellActionSideEffectKind.updateWorkspace);
    });

    test('maps paste decision to paste side effect kinds', () {
      final send = ShellActionSideEffectPlanner.plan(
        const ShellPolicyDispatchResult(
          LocalTerminalPasteActionResult(
            LocalTerminalPasteDecision(
              kind: LocalTerminalPasteDecisionKind.sendImmediately,
              captureHistory: true,
            ),
          ),
        ),
      );
      final blocked = ShellActionSideEffectPlanner.plan(
        const ShellPolicyDispatchResult(
          LocalTerminalPasteActionResult(
            LocalTerminalPasteDecision(
              kind: LocalTerminalPasteDecisionKind.blockedReadOnly,
              captureHistory: false,
            ),
          ),
        ),
      );

      expect(send.kind, ShellActionSideEffectKind.sendPaste);
      expect(blocked.kind, ShellActionSideEffectKind.blockPaste);
    });

    test('maps visual result to visual side effect', () {
      final plan = ShellActionSideEffectPlanner.plan(
        const ShellVisualDispatchResult(LocalTerminalOpenThemePickerResult()),
      );

      expect(plan.kind, ShellActionSideEffectKind.openThemePicker);
    });

    test(
      'maps command block productivity result to command block side effect',
      () {
        final plan = ShellActionSideEffectPlanner.plan(
          const ShellProductivityDispatchResult(
            ShellProductivityCommandBlockActionResult(
              TerminalActionId.compareLastCommandRun,
            ),
          ),
        );

        expect(plan.kind, ShellActionSideEffectKind.commandBlockAction);
        expect(plan.payload, TerminalActionId.compareLastCommandRun);
      },
    );

    test('maps unhandled dispatch to none', () {
      final plan = ShellActionSideEffectPlanner.plan(
        const ShellUnhandledDispatchResult(),
      );

      expect(plan.kind, ShellActionSideEffectKind.none);
    });
  });
}
