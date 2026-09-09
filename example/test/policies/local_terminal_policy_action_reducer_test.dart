import 'package:app/features/policies/local_terminal_paste_decision.dart';
import 'package:app/features/policies/local_terminal_policy_action_reducer.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local terminal policy action reducer', () {
    test('paste action returns paste decision', () {
      final result = LocalTerminalPolicyActionReducer.reduce(
        actionId: TerminalActionId.paste,
        policies: const LocalTerminalPolicyBundle(),
        context: const LocalTerminalPolicyActionContext(pasteText: 'hello'),
      );

      expect(result, isA<LocalTerminalPasteActionResult>());
      expect(
        (result as LocalTerminalPasteActionResult).decision.kind,
        LocalTerminalPasteDecisionKind.sendImmediately,
      );
    });
  });
}
