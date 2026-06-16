import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_action_side_effect_executor.dart';
import 'package:app/features/shell/shell_action_side_effect_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shell action side effect executor', () {
    test('executes matching handler with payload', () async {
      final calls = <Object?>[];
      final executor = ShellActionSideEffectExecutor(
        ShellActionSideEffectHandlers(
          sendPaste: (payload) async => calls.add(payload),
        ),
      );

      await executor.execute(
        const ShellActionSideEffectPlan(
          kind: ShellActionSideEffectKind.sendPaste,
          payload: 'hello',
        ),
      );

      expect(calls, ['hello']);
    });

    test(
      'executes command block action handler with action id payload',
      () async {
        final calls = <Object?>[];
        final executor = ShellActionSideEffectExecutor(
          ShellActionSideEffectHandlers(
            commandBlockAction: (payload) async => calls.add(payload),
          ),
        );

        await executor.execute(
          const ShellActionSideEffectPlan(
            kind: ShellActionSideEffectKind.commandBlockAction,
            payload: TerminalActionId.openHistoryPeek,
          ),
        );

        expect(calls, [TerminalActionId.openHistoryPeek]);
      },
    );

    test('ignores missing handlers and none plans', () async {
      final executor = ShellActionSideEffectExecutor(
        const ShellActionSideEffectHandlers(),
      );

      await executor.execute(
        const ShellActionSideEffectPlan(kind: ShellActionSideEffectKind.none),
      );
      await executor.execute(
        const ShellActionSideEffectPlan(
          kind: ShellActionSideEffectKind.openThemePicker,
        ),
      );

      expect(true, isTrue);
    });
  });
}
