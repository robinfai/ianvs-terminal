import 'package:app/features/productivity/command_blocks_history_feature_flags.dart';
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
        ShellActionDisabledReason.commandBlocksHistoryDisabled.title,
        'Command Blocks history unavailable',
      );
      expect(
        ShellActionDisabledReason.missingRecentDirectory.description,
        contains('local directory'),
      );
    });

    test('command block actions are disabled when feature flags are off', () {
      final availability = ShellActionAvailabilityResolver.resolve(
        actionId: TerminalActionId.openHistoryPeek,
        hasActiveSession: true,
        productivity: const ShellProductivityState(),
        commandBlocksHistory: CommandBlocksHistoryFeatureFlags.disabled,
        hasCommandBlocks: true,
      );

      expect(availability.enabled, isFalse);
      expect(
        availability.reason,
        ShellActionDisabledReason.commandBlocksHistoryDisabled,
      );
    });

    test('history peek is enabled only when flag and command blocks exist', () {
      const flags = CommandBlocksHistoryFeatureFlags(
        enabled: true,
        commandBlocks: true,
        historyPeek: true,
        failureSnapshots: false,
        reviewWorkspaceEntrypoints: false,
        outputDiff: false,
      );

      final availability = ShellActionAvailabilityResolver.resolve(
        actionId: TerminalActionId.openHistoryPeek,
        hasActiveSession: true,
        productivity: const ShellProductivityState(),
        commandBlocksHistory: flags,
        hasCommandBlocks: true,
      );

      expect(availability.enabled, isTrue);
    });

    test('history peek requires the base command blocks flag', () {
      const flags = CommandBlocksHistoryFeatureFlags(
        enabled: true,
        commandBlocks: false,
        historyPeek: true,
        failureSnapshots: false,
        reviewWorkspaceEntrypoints: false,
        outputDiff: false,
      );

      final availability = ShellActionAvailabilityResolver.resolve(
        actionId: TerminalActionId.openHistoryPeek,
        hasActiveSession: true,
        productivity: const ShellProductivityState(),
        commandBlocksHistory: flags,
        hasCommandBlocks: true,
      );

      expect(availability.enabled, isFalse);
      expect(
        availability.reason,
        ShellActionDisabledReason.commandBlocksHistoryDisabled,
      );
    });

    test('history peek requires its sub-flag', () {
      const flags = CommandBlocksHistoryFeatureFlags(
        enabled: true,
        commandBlocks: true,
        historyPeek: false,
        failureSnapshots: false,
        reviewWorkspaceEntrypoints: false,
        outputDiff: false,
      );

      final availability = ShellActionAvailabilityResolver.resolve(
        actionId: TerminalActionId.openHistoryPeek,
        hasActiveSession: true,
        productivity: const ShellProductivityState(),
        commandBlocksHistory: flags,
        hasCommandBlocks: true,
      );

      expect(availability.enabled, isFalse);
      expect(
        availability.reason,
        ShellActionDisabledReason.commandBlocksHistoryDisabled,
      );
    });

    test('active session gate runs before command block gates', () {
      final availability = ShellActionAvailabilityResolver.resolve(
        actionId: TerminalActionId.openHistoryPeek,
        hasActiveSession: false,
        productivity: const ShellProductivityState(),
        commandBlocksHistory: CommandBlocksHistoryFeatureFlags.disabled,
        hasCommandBlocks: true,
      );

      expect(availability.enabled, isFalse);
      expect(
        availability.reason,
        ShellActionDisabledReason.missingActiveSession,
      );
    });

    test('command block actions require captured command blocks', () {
      const flags = CommandBlocksHistoryFeatureFlags(
        enabled: true,
        commandBlocks: true,
        historyPeek: true,
        failureSnapshots: true,
        reviewWorkspaceEntrypoints: true,
        outputDiff: true,
      );

      final availability = ShellActionAvailabilityResolver.resolve(
        actionId: TerminalActionId.compareLastCommandRun,
        hasActiveSession: true,
        productivity: const ShellProductivityState(),
        commandBlocksHistory: flags,
        hasCommandBlocks: false,
      );

      expect(availability.enabled, isFalse);
      expect(
        availability.reason,
        ShellActionDisabledReason.missingCommandBlock,
      );
    });

    test('command block actions are gated by their matching sub-flags', () {
      const flags = CommandBlocksHistoryFeatureFlags(
        enabled: true,
        commandBlocks: true,
        historyPeek: false,
        failureSnapshots: false,
        reviewWorkspaceEntrypoints: false,
        outputDiff: false,
      );

      final cases = <TerminalActionId>[
        TerminalActionId.replayFromCommandBlock,
        TerminalActionId.saveCommandSnapshot,
        TerminalActionId.compareLastCommandRun,
      ];

      for (final actionId in cases) {
        final availability = ShellActionAvailabilityResolver.resolve(
          actionId: actionId,
          hasActiveSession: true,
          productivity: const ShellProductivityState(),
          commandBlocksHistory: flags,
          hasCommandBlocks: true,
        );

        expect(
          availability.reason,
          ShellActionDisabledReason.commandBlocksHistoryDisabled,
          reason: '$actionId should be disabled by its sub-flag',
        );
      }
    });

    test('mark command block is gated by the command blocks flag', () {
      const flags = CommandBlocksHistoryFeatureFlags(
        enabled: true,
        commandBlocks: false,
        historyPeek: true,
        failureSnapshots: true,
        reviewWorkspaceEntrypoints: true,
        outputDiff: true,
      );

      final availability = ShellActionAvailabilityResolver.resolve(
        actionId: TerminalActionId.markCommandBlock,
        hasActiveSession: true,
        productivity: const ShellProductivityState(),
        commandBlocksHistory: flags,
        hasCommandBlocks: true,
      );

      expect(availability.enabled, isFalse);
      expect(
        availability.reason,
        ShellActionDisabledReason.commandBlocksHistoryDisabled,
      );
    });
  });
}
