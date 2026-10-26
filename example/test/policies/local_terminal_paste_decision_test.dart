import 'package:app/features/policies/local_terminal_paste_decision.dart';
import 'package:app/features/policies/local_terminal_policy_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local terminal paste decision', () {
    for (final running in [false, true]) {
      for (final bracketed in [false, true]) {
        test('multiline running=$running bracketed=$bracketed', () {
          final decision = LocalTerminalPasteDecisionResolver.resolve(
            text: 'one\ntwo',
            readOnly: false,
            commandRunning: running,
            bracketedPaste: bracketed,
            pastePolicy: const LocalTerminalPastePolicy(),
            historyPolicy: const LocalTerminalPasteHistoryPolicy(
              enabled: false,
            ),
          );
          expect(
            decision.kind,
            running && bracketed
                ? LocalTerminalPasteDecisionKind.sendImmediately
                : LocalTerminalPasteDecisionKind.requireConfirmation,
          );
          expect(decision.text, 'one\ntwo');
          expect(decision.captureHistory, isFalse);
        });
      }
    }

    test(
      'application framing does not bypass size confirmation or read-only',
      () {
        for (final readOnly in [false, true]) {
          final decision = LocalTerminalPasteDecisionResolver.resolve(
            text: '字\n' * 4096,
            readOnly: readOnly,
            commandRunning: true,
            bracketedPaste: true,
            pastePolicy: const LocalTerminalPastePolicy(),
            historyPolicy: const LocalTerminalPasteHistoryPolicy(
              enabled: false,
            ),
          );
          expect(
            decision.kind,
            readOnly
                ? LocalTerminalPasteDecisionKind.blockedReadOnly
                : LocalTerminalPasteDecisionKind.requireConfirmation,
          );
        }
      },
    );

    test('blocks paste in read-only mode without history capture', () {
      final decision = LocalTerminalPasteDecisionResolver.resolve(
        text: 'hello',
        readOnly: true,
        pastePolicy: const LocalTerminalPastePolicy(),
        historyPolicy: const LocalTerminalPasteHistoryPolicy(),
      );

      expect(decision.kind, LocalTerminalPasteDecisionKind.blockedReadOnly);
      expect(decision.captureHistory, isFalse);
      expect(decision.text, 'hello');
    });

    test('requires confirmation for multiline paste', () {
      final decision = LocalTerminalPasteDecisionResolver.resolve(
        text: 'one\ntwo',
        readOnly: false,
        pastePolicy: const LocalTerminalPastePolicy(),
        historyPolicy: const LocalTerminalPasteHistoryPolicy(),
      );

      expect(decision.kind, LocalTerminalPasteDecisionKind.requireConfirmation);
      expect(decision.captureHistory, isTrue);
      expect(decision.text, 'one\ntwo');
    });

    test('sends simple paste immediately and captures history', () {
      final decision = LocalTerminalPasteDecisionResolver.resolve(
        text: 'hello',
        readOnly: false,
        pastePolicy: const LocalTerminalPastePolicy(),
        historyPolicy: const LocalTerminalPasteHistoryPolicy(),
      );

      expect(decision.kind, LocalTerminalPasteDecisionKind.sendImmediately);
      expect(decision.captureHistory, isTrue);
      expect(decision.text, 'hello');
    });

    test('ignores non-positive large paste thresholds for history capture', () {
      final decision = LocalTerminalPasteDecisionResolver.resolve(
        text: 'hello',
        readOnly: false,
        pastePolicy: const LocalTerminalPastePolicy(largePasteThreshold: 0),
        historyPolicy: const LocalTerminalPasteHistoryPolicy(),
      );

      expect(decision.kind, LocalTerminalPasteDecisionKind.sendImmediately);
      expect(decision.captureHistory, isTrue);
    });
  });
}
