import 'package:app/features/command_center/command_lifecycle_degraded_state.dart';
import 'package:app/features/command_center/shell_hook_lifecycle_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandLifecycleDegradedState', () {
    test('keeps history search limited when shell integration is disabled', () {
      final state = const CommandLifecycleDegradedState(
        shellIntegrationEnabled: false,
        hasHistory: true,
      );

      final search = state.capability(CommandCenterCapability.historySearch);
      final blocks = state.action(CommandCenterAction.showCommandBlocks);

      expect(search.enabled, isTrue);
      expect(search.limited, isTrue);
      expect(
        search.reason,
        CommandCenterUnavailableReason.shellIntegrationDisabled,
      );
      expect(blocks.enabled, isFalse);
      expect(
        blocks.disabledReason,
        CommandCenterDisabledActionReason.shellIntegrationDisabled,
      );
    });

    test('disables lifecycle-backed actions when lifecycle is unavailable', () {
      final state = const CommandLifecycleDegradedState(
        shellIntegrationEnabled: true,
        lifecycleAvailable: false,
        hasOutputRange: true,
      );

      expect(
        state.action(CommandCenterAction.showCommandBlocks).disabledReason,
        CommandCenterDisabledActionReason.missingLifecycle,
      );
      expect(
        state.action(CommandCenterAction.showStickyHeader).disabledReason,
        CommandCenterDisabledActionReason.missingLifecycle,
      );
      expect(
        state.action(CommandCenterAction.openReviewEntrypoints).disabledReason,
        CommandCenterDisabledActionReason.missingLifecycle,
      );
    });

    test('disables copy output when output range is missing', () {
      final state = const CommandLifecycleDegradedState(
        shellIntegrationEnabled: true,
        lifecycleAvailable: true,
        hasOutputRange: false,
      );

      final availability = state.action(CommandCenterAction.copyOutput);

      expect(availability.enabled, isFalse);
      expect(
        availability.disabledReason,
        CommandCenterDisabledActionReason.missingOutputRange,
      );
    });

    test('disables command surfaces when output range is missing', () {
      final state = const CommandLifecycleDegradedState(
        shellIntegrationEnabled: true,
        lifecycleAvailable: true,
        hasOutputRange: false,
      );

      expect(
        state.action(CommandCenterAction.showCommandBlocks).disabledReason,
        CommandCenterDisabledActionReason.missingOutputRange,
      );
      expect(
        state.action(CommandCenterAction.showStickyHeader).disabledReason,
        CommandCenterDisabledActionReason.missingOutputRange,
      );
      expect(
        state.action(CommandCenterAction.openReviewEntrypoints).disabledReason,
        CommandCenterDisabledActionReason.missingOutputRange,
      );
    });

    test('keeps out-of-order lifecycle scoped to the affected session', () {
      final state = const CommandLifecycleDegradedState(
        shellIntegrationEnabled: true,
        lifecycleAvailable: true,
        hasOutputRange: true,
        sessionReasons: {
          'session-a': CommandCenterUnavailableReason.outOfOrderLifecycle,
        },
      );

      final affected = state.action(
        CommandCenterAction.showCommandBlocks,
        sessionId: 'session-a',
      );
      final unaffected = state.action(
        CommandCenterAction.showCommandBlocks,
        sessionId: 'session-b',
      );

      expect(affected.enabled, isFalse);
      expect(
        affected.disabledReason,
        CommandCenterDisabledActionReason.outOfOrderLifecycle,
      );
      expect(unaffected.enabled, isTrue);
      expect(unaffected.disabledReason, isNull);
    });

    test('maps ignored shell hook reasons into unavailable reasons', () {
      expect(
        commandCenterUnavailableReasonForIgnoredHook(
          ShellHookLifecycleIgnoredReason.unknownHook,
        ),
        CommandCenterUnavailableReason.unknownHook,
      );
      expect(
        commandCenterUnavailableReasonForIgnoredHook(
          ShellHookLifecycleIgnoredReason.missingCommand,
        ),
        CommandCenterUnavailableReason.missingCommand,
      );
      expect(
        commandCenterUnavailableReasonForIgnoredHook(
          ShellHookLifecycleIgnoredReason.missingCwd,
        ),
        CommandCenterUnavailableReason.missingCwd,
      );
    });
  });
}
