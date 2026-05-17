import 'package:app/features/policies/local_terminal_paste_decision.dart';
import 'package:app/features/policies/local_terminal_policy_action_reducer.dart';
import 'package:app/features/policies/local_terminal_policy_models.dart';
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

    test('bell notification action returns notification intent', () {
      final result = LocalTerminalPolicyActionReducer.reduce(
        actionId: TerminalActionId.toggleBellNotify,
        policies: const LocalTerminalPolicyBundle(),
        context: const LocalTerminalPolicyActionContext(focused: false),
      );

      expect(result, isA<LocalTerminalNotificationActionResult>());
      expect(
        (result as LocalTerminalNotificationActionResult).intent,
        isNotNull,
      );
    });

    test('hotkey window action exposes failure when disabled', () {
      final result = LocalTerminalPolicyActionReducer.reduce(
        actionId: TerminalActionId.hotkeyWindow,
        policies: const LocalTerminalPolicyBundle(),
        context: const LocalTerminalPolicyActionContext(),
      );

      expect(result, isA<LocalTerminalHotkeyActionResult>());
      expect(
        (result as LocalTerminalHotkeyActionResult).state.hasVisibleFailure,
        isTrue,
      );
    });

    test('hotkey window action toggles when enabled and sized', () {
      final result = LocalTerminalPolicyActionReducer.reduce(
        actionId: TerminalActionId.hotkeyWindow,
        policies: const LocalTerminalPolicyBundle(
          hotkeyWindow: LocalTerminalHotkeyWindowPolicy(enabled: true),
        ),
        context: const LocalTerminalPolicyActionContext(),
      );

      expect((result as LocalTerminalHotkeyActionResult).state.visible, isTrue);
    });
  });
}
