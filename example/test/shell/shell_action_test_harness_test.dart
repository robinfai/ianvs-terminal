import 'package:app/features/shell/shell_action_side_effect_plan.dart';
import 'package:app/features/shell/shell_action_test_harness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shell action test harness', () {
    test('records side-effect executor calls', () async {
      final harness = ShellActionTestHarness();
      final executor = harness.executor();

      await executor.execute(
        const ShellActionSideEffectPlan(
          kind: ShellActionSideEffectKind.sendPaste,
          payload: 'hello',
        ),
      );

      expect(harness.calls, hasLength(1));
      expect(harness.calls.single.kind, ShellActionSideEffectKind.sendPaste);
      expect(harness.calls.single.payload, 'hello');
    });
  });
}
