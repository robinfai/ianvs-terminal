import 'package:app/features/command_center/command_block_models.dart';
import 'package:app/features/command_center/command_invocation_models.dart';
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

    test('block actions are registered in the unified action registry', () {
      expect(
        ShellActionRegistry.actions[TerminalActionId.copyBlockOutput]?.label,
        'copy_block_output',
      );
      expect(
        ShellActionRegistry
            .actions[TerminalActionId.reInputBlockCommand]
            ?.requiresActiveSession,
        isTrue,
      );
      expect(
        ShellActionRegistry
            .actions[TerminalActionId.rerunBlockCommand]
            ?.terminalInputPolicy,
        TerminalInputPolicy.performableOnly,
      );
    });

    test('block copy output availability follows reducer range reasons', () {
      final available = ShellActionAvailabilityResolver.resolve(
        actionId: TerminalActionId.copyBlockOutput,
        hasActiveSession: true,
        productivity: const ShellProductivityState(),
        commandBlock: _block(),
      );
      final missingRange = ShellActionAvailabilityResolver.resolve(
        actionId: TerminalActionId.copyBlockOutput,
        hasActiveSession: true,
        productivity: const ShellProductivityState(),
        commandBlock: _block(hasOutputRange: false),
      );

      expect(available.enabled, isTrue);
      expect(missingRange.enabled, isFalse);
      expect(
        missingRange.reason,
        ShellActionDisabledReason.missingCommandOutput,
      );
    });

    test('block writing actions honor read-only and paste safety', () {
      final readOnly = ShellActionAvailabilityResolver.resolve(
        actionId: TerminalActionId.rerunBlockCommand,
        hasActiveSession: true,
        productivity: const ShellProductivityState(readOnly: true),
        commandBlock: _block(),
      );
      final pastePolicy = ShellActionAvailabilityResolver.resolve(
        actionId: TerminalActionId.rerunBlockCommand,
        hasActiveSession: true,
        productivity: const ShellProductivityState(),
        commandBlock: _block(command: 'printf one\nprintf two'),
      );

      expect(readOnly.enabled, isFalse);
      expect(readOnly.reason, ShellActionDisabledReason.readOnly);
      expect(pastePolicy.enabled, isFalse);
      expect(
        pastePolicy.reason,
        ShellActionDisabledReason.pasteRequiresConfirmation,
      );
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

const _scope = CommandBlockScope('session-a', paneId: 'pane-a');
const _inputRange = CommandBlockRowRange(startRow: 4, endRowExclusive: 5);
const _outputRange = CommandBlockRowRange(startRow: 5, endRowExclusive: 8);
final _startedAt = DateTime.utc(2026, 6, 15, 10);

CommandBlock _block({
  String command = 'flutter test',
  bool hasOutputRange = true,
}) {
  return CommandBlock(
    id: 'cmd-1',
    sessionId: _scope.sessionId,
    paneId: _scope.paneId,
    command: command,
    startedAt: _startedAt,
    status: CommandInvocationStatus.succeeded,
    inputRange: _inputRange,
    outputRange: hasOutputRange ? _outputRange : null,
  );
}
