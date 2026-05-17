import 'package:app/features/policies/local_terminal_policy_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local terminal policy models', () {
    test('paste policy confirms large and multiline paste', () {
      const policy = LocalTerminalPastePolicy(largePasteThreshold: 5);

      expect(policy.requiresConfirmation('one\ntwo'), isTrue);
      expect(policy.requiresConfirmation('12345'), isTrue);
      expect(policy.requiresConfirmation('1234'), isFalse);
    });

    test('paste policy blocks read-only paste', () {
      const policy = LocalTerminalPastePolicy();

      expect(policy.canPaste(readOnly: true), isFalse);
      expect(policy.canPaste(readOnly: false), isTrue);
    });

    test('monitor rule respects focus and threshold', () {
      const rule = LocalTerminalMonitorRule(
        enabled: true,
        target: LocalTerminalMonitorTarget.systemNotification,
        focusPolicy: LocalTerminalMonitorFocusPolicy.unfocused,
        threshold: Duration(seconds: 5),
      );

      expect(
        rule.shouldNotify(
          focused: true,
          observedDuration: const Duration(seconds: 10),
        ),
        isFalse,
      );
      expect(
        rule.shouldNotify(
          focused: false,
          observedDuration: const Duration(seconds: 3),
        ),
        isFalse,
      );
      expect(
        rule.shouldNotify(
          focused: false,
          observedDuration: const Duration(seconds: 10),
        ),
        isTrue,
      );
    });

    test('hotkey window policy exposes usable size', () {
      const enabled = LocalTerminalHotkeyWindowPolicy(enabled: true);
      const invalid = LocalTerminalHotkeyWindowPolicy(widthFraction: 0);

      expect(enabled.hasUsableSize, isTrue);
      expect(invalid.hasUsableSize, isFalse);
    });

    test('hotkey window state exposes visible failure', () {
      final state = const LocalTerminalHotkeyWindowState().failed(
        const LocalTerminalHotkeyWindowFailure(
          kind: LocalTerminalHotkeyWindowFailureKind.permissionDenied,
          message: 'Accessibility permission is required',
        ),
      );

      expect(state.visible, isFalse);
      expect(state.hasVisibleFailure, isTrue);
      expect(state.toggled().hasVisibleFailure, isFalse);
    });

    test(
      'paste history policy gates capture and keeps newest unique entries',
      () {
        const policy = LocalTerminalPasteHistoryPolicy(maxEntries: 2);
        final state = const LocalTerminalPasteHistoryState()
            .record(text: 'one', policy: policy, largePaste: false)
            .record(text: 'two', policy: policy, largePaste: false)
            .record(text: 'one', policy: policy, largePaste: false)
            .record(text: 'large', policy: policy, largePaste: true);

        expect(state.entries, ['one', 'two']);
        expect(state.focusShouldReturnToTerminal, isTrue);
      },
    );

    test('paste history policy can reject multiline capture', () {
      const policy = LocalTerminalPasteHistoryPolicy(captureMultiline: false);
      final state = const LocalTerminalPasteHistoryState().record(
        text: 'one\ntwo',
        policy: policy,
        largePaste: false,
      );

      expect(state.entries, isEmpty);
    });
  });
}
