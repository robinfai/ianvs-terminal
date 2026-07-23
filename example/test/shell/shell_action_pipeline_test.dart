import 'package:app/features/policies/local_terminal_policy_action_reducer.dart';
import 'package:app/features/productivity/shell_productivity_action_reducer.dart';
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/shell/shell_action_dispatcher.dart';
import 'package:app/features/shell/shell_action_pipeline.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_action_side_effect_executor.dart';
import 'package:app/features/shell/shell_action_side_effect_plan.dart';
import 'package:app/features/visual/local_terminal_visual_action_reducer.dart';
import 'package:app/features/layout/terminal_layout_action_reducer.dart';
import 'package:app/features/layout/local_terminal_layout_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shell action pipeline', () {
    test('dispatches, plans, and executes layout action', () async {
      final calls = <ShellActionSideEffectKind>[];
      final pipeline = ShellActionPipeline(
        executor: ShellActionSideEffectExecutor(
          ShellActionSideEffectHandlers(
            updateLayout: (_) async {
              calls.add(ShellActionSideEffectKind.updateLayout);
            },
          ),
        ),
      );

      final result = await pipeline.run(
        actionId: TerminalActionId.newTab,
        state: const ShellActionDispatchState(),
        context: _context(),
      );

      expect(result.dispatch, isA<ShellLayoutDispatchResult>());
      expect(result.plan.kind, ShellActionSideEffectKind.updateLayout);
      expect(calls, [ShellActionSideEffectKind.updateLayout]);
    });

    test('dispatches productivity action through executor', () async {
      final calls = <ShellActionSideEffectKind>[];
      final pipeline = ShellActionPipeline(
        executor: ShellActionSideEffectExecutor(
          ShellActionSideEffectHandlers(
            updateProductivityState: (_) async {
              calls.add(ShellActionSideEffectKind.updateProductivityState);
            },
          ),
        ),
      );

      final result = await pipeline.run(
        actionId: TerminalActionId.toggleReadOnly,
        state: const ShellActionDispatchState(),
        context: _context(),
      );

      expect(result.dispatch, isA<ShellProductivityDispatchResult>());
      expect(
        (result.dispatch as ShellProductivityDispatchResult).result,
        isA<ShellProductivityStateResult>(),
      );
      expect(calls, [ShellActionSideEffectKind.updateProductivityState]);
    });

    test('dispatches policy action through executor', () async {
      final calls = <ShellActionSideEffectKind>[];
      final pipeline = ShellActionPipeline(
        executor: ShellActionSideEffectExecutor(
          ShellActionSideEffectHandlers(
            sendPaste: (_) async {
              calls.add(ShellActionSideEffectKind.sendPaste);
            },
          ),
        ),
      );

      final result = await pipeline.run(
        actionId: TerminalActionId.paste,
        state: const ShellActionDispatchState(),
        context: _context(pasteText: 'hello'),
      );

      expect(result.dispatch, isA<ShellPolicyDispatchResult>());
      expect(
        (result.dispatch as ShellPolicyDispatchResult).result,
        isA<LocalTerminalPasteActionResult>(),
      );
      expect(calls, [ShellActionSideEffectKind.sendPaste]);
    });

    test('dispatches visual action through executor', () async {
      final calls = <ShellActionSideEffectKind>[];
      final pipeline = ShellActionPipeline(
        executor: ShellActionSideEffectExecutor(
          ShellActionSideEffectHandlers(
            openThemePicker: (_) async {
              calls.add(ShellActionSideEffectKind.openThemePicker);
            },
          ),
        ),
      );

      final result = await pipeline.run(
        actionId: TerminalActionId.openThemePicker,
        state: const ShellActionDispatchState(),
        context: _context(),
      );

      expect(result.dispatch, isA<ShellVisualDispatchResult>());
      expect(
        (result.dispatch as ShellVisualDispatchResult).result,
        isA<LocalTerminalOpenThemePickerResult>(),
      );
      expect(calls, [ShellActionSideEffectKind.openThemePicker]);
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
