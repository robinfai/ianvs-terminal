import 'package:app/features/command_center/command_block_models.dart';
import 'package:app/features/command_center/command_invocation_models.dart';
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

    test('block action availability covers action search block actions', () {
      final availableActions = <TerminalActionId>[
        TerminalActionId.copyBlockOutput,
        TerminalActionId.saveBlockOutput,
        TerminalActionId.openInReview,
        TerminalActionId.searchWithinBlock,
        TerminalActionId.reInputBlockCommand,
        TerminalActionId.rerunBlockCommand,
      ];

      for (final actionId in availableActions) {
        final availability = ShellActionAvailabilityResolver.resolve(
          actionId: actionId,
          hasActiveSession: true,
          productivity: const ShellProductivityState(),
          commandBlock: _block(),
        );

        expect(
          availability.enabled,
          isTrue,
          reason: '$actionId should accept the active command block',
        );
      }
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

    test('history peek uses any captured command block', () {
      const flags = CommandBlocksHistoryFeatureFlags(
        enabled: true,
        commandBlocks: true,
        historyPeek: true,
        failureSnapshots: false,
        reviewWorkspaceEntrypoints: true,
        outputDiff: false,
      );

      final historyPeek = ShellActionAvailabilityResolver.resolve(
        actionId: TerminalActionId.openHistoryPeek,
        hasActiveSession: true,
        productivity: const ShellProductivityState(),
        commandBlocksHistory: flags,
        hasCommandBlocks: true,
      );
      final historyPeekWithoutBlocks = ShellActionAvailabilityResolver.resolve(
        actionId: TerminalActionId.openHistoryPeek,
        hasActiveSession: true,
        productivity: const ShellProductivityState(),
        commandBlocksHistory: flags,
        hasCommandBlocks: false,
      );
      final replay = ShellActionAvailabilityResolver.resolve(
        actionId: TerminalActionId.replayFromCommandBlock,
        hasActiveSession: true,
        productivity: const ShellProductivityState(),
        commandBlocksHistory: flags,
        hasCommandBlocks: true,
        hasHistoryPeekCommandBlocks: false,
      );

      expect(historyPeek.enabled, isTrue);
      expect(historyPeekWithoutBlocks.enabled, isFalse);
      expect(
        historyPeekWithoutBlocks.reason,
        ShellActionDisabledReason.missingCommandBlock,
      );
      expect(replay.enabled, isTrue);
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
