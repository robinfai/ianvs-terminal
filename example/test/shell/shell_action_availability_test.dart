import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/shell/shell_action_availability.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shell action availability', () {
    test('requires active session when descriptor says so', () {
      final availability = ShellActionAvailabilityResolver.resolve(
        actionId: TerminalActionId.splitRight,
        hasActiveSession: false,
        productivity: const ShellProductivityState(),
      );

      expect(availability.enabled, isFalse);
      expect(
        availability.reason,
        ShellActionDisabledReason.missingActiveSession,
      );
    });

    test('prompt actions are disabled without prompt marks', () {
      final availability = ShellActionAvailabilityResolver.resolve(
        actionId: TerminalActionId.previousPrompt,
        hasActiveSession: true,
        productivity: const ShellProductivityState(),
      );

      expect(availability.enabled, isFalse);
      expect(
        availability.reason,
        ShellActionDisabledReason.shellIntegrationUnavailable,
      );
    });

    test('paste actions are disabled in read-only mode', () {
      final availability = ShellActionAvailabilityResolver.resolve(
        actionId: TerminalActionId.paste,
        hasActiveSession: true,
        productivity: const ShellProductivityState(readOnly: true),
      );

      expect(availability.enabled, isFalse);
      expect(availability.reason, ShellActionDisabledReason.readOnly);
    });

    test('command output actions require a valid output range', () {
      final availability = ShellActionAvailabilityResolver.resolve(
        actionId: TerminalActionId.copyCommandOutput,
        hasActiveSession: true,
        productivity: const ShellProductivityState(
          commandOutputRanges: [
            ShellCommandOutputRange(commandId: 'cmd', startRow: 1, endRow: 2),
          ],
        ),
      );

      expect(availability.enabled, isTrue);
    });

    test('disabled reasons expose stable user-visible diagnostics', () {
      expect(ShellActionDisabledReason.readOnly.title, 'Read-only mode');
      expect(
        ShellActionDisabledReason.missingRecentDirectory.description,
        contains('local directory'),
      );
    });
  });
}
