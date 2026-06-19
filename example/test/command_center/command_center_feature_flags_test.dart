import 'package:app/features/command_center/command_center_feature_flags.dart';
import 'package:app/features/command_center/command_center_mode_router.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandCenterFeatureFlags', () {
    test('defaults every capability to false', () {
      const flags = CommandCenterFeatureFlags();

      expect(flags.enabled, isFalse);
      expect(flags.historySearch, isFalse);
      expect(flags.commandBlocks, isFalse);
      expect(flags.commandBar, isFalse);
      expect(flags.contextChips, isFalse);
      expect(flags.reviewEntrypoints, isFalse);
      expect(flags.verificationDiagnostics, isFalse);
      expect(flags.agentCenter, isFalse);
      expect(flags.agentConversation, isFalse);
      expect(flags.agentContext, isFalse);
      expect(flags.agentCommandProposals, isFalse);
      expect(flags.agentProviderDraft, isFalse);
      expect(flags.agentCommandSearchActions, isFalse);
      expect(flags.agentRolloutStage, AgentCenterRolloutStage.off);
    });

    test('requires the total switch before enabling sub capabilities', () {
      const config = LocalTerminalCommandCenterConfig(
        enabled: false,
        historySearch: true,
        commandBlocks: true,
        commandBar: true,
        contextChips: true,
        reviewEntrypoints: true,
        verificationDiagnostics: true,
        agentCenter: true,
        agentConversation: true,
        agentContext: true,
        agentCommandProposals: true,
        agentProviderDraft: true,
        agentCommandSearchActions: true,
      );

      final flags = CommandCenterFeatureFlags.fromConfig(config);

      expect(flags.enabled, isFalse);
      expect(flags.historySearch, isFalse);
      expect(flags.commandBlocks, isFalse);
      expect(flags.commandBar, isFalse);
      expect(flags.contextChips, isFalse);
      expect(flags.reviewEntrypoints, isFalse);
      expect(flags.verificationDiagnostics, isFalse);
      expect(flags.agentCenter, isFalse);
      expect(flags.agentConversation, isFalse);
      expect(flags.agentContext, isFalse);
      expect(flags.agentCommandProposals, isFalse);
      expect(flags.agentProviderDraft, isFalse);
      expect(flags.agentCommandSearchActions, isFalse);
    });

    test('resolves enabled sub capabilities from config', () {
      const config = LocalTerminalCommandCenterConfig(
        enabled: true,
        historySearch: true,
        commandBlocks: false,
        commandBar: true,
        contextChips: true,
        reviewEntrypoints: false,
        verificationDiagnostics: true,
        agentCenter: true,
        agentConversation: true,
        agentContext: true,
        agentCommandProposals: true,
        agentProviderDraft: false,
        agentCommandSearchActions: true,
      );

      final flags = CommandCenterFeatureFlags.fromConfig(config);

      expect(flags.enabled, isTrue);
      expect(flags.historySearch, isTrue);
      expect(flags.commandBlocks, isFalse);
      expect(flags.commandBar, isTrue);
      expect(flags.contextChips, isTrue);
      expect(flags.reviewEntrypoints, isFalse);
      expect(flags.verificationDiagnostics, isTrue);
      expect(flags.agentCenter, isTrue);
      expect(flags.agentConversation, isTrue);
      expect(flags.agentContext, isTrue);
      expect(flags.agentCommandProposals, isTrue);
      expect(flags.agentProviderDraft, isFalse);
      expect(flags.agentCommandSearchActions, isTrue);
      expect(flags.agentRolloutStage, AgentCenterRolloutStage.proposalPreview);
    });

    test('allows tests to inject an explicit snapshot', () {
      const flags = CommandCenterFeatureFlags(
        enabled: true,
        historySearch: true,
        commandBlocks: true,
        commandBar: false,
        contextChips: true,
        reviewEntrypoints: false,
        verificationDiagnostics: false,
        agentCenter: true,
        agentConversation: true,
        agentContext: true,
        agentCommandProposals: false,
        agentProviderDraft: true,
        agentCommandSearchActions: false,
      );

      expect(flags.enabled, isTrue);
      expect(flags.historySearch, isTrue);
      expect(flags.commandBlocks, isTrue);
      expect(flags.commandBar, isFalse);
      expect(flags.contextChips, isTrue);
      expect(flags.reviewEntrypoints, isFalse);
      expect(flags.verificationDiagnostics, isFalse);
      expect(flags.agentCenter, isTrue);
      expect(flags.agentConversation, isTrue);
      expect(flags.agentProviderDraft, isTrue);
      expect(flags.agentRolloutStage, AgentCenterRolloutStage.providerPreview);
    });

    test('applies development overrides before gating sub capabilities', () {
      final flags = CommandCenterFeatureFlags.fromConfig(
        const LocalTerminalCommandCenterConfig(enabled: false),
        overrides: const CommandCenterFeatureFlagOverrides(
          enabled: true,
          historySearch: true,
          agentCenter: true,
          agentConversation: true,
        ),
      );

      expect(flags.enabled, isTrue);
      expect(flags.historySearch, isTrue);
      expect(flags.commandBlocks, isFalse);
      expect(flags.agentCenter, isTrue);
      expect(flags.agentConversation, isTrue);
      expect(flags.agentContext, isFalse);
    });

    test('gates Agent sub capabilities behind Agent conversation', () {
      final flags = CommandCenterFeatureFlags.fromConfig(
        const LocalTerminalCommandCenterConfig(
          enabled: true,
          agentCenter: true,
          agentConversation: false,
          agentContext: true,
          agentCommandProposals: true,
          agentProviderDraft: true,
          agentCommandSearchActions: true,
        ),
      );

      expect(flags.agentCenter, isTrue);
      expect(flags.agentConversation, isFalse);
      expect(flags.agentContext, isFalse);
      expect(flags.agentCommandProposals, isFalse);
      expect(flags.agentProviderDraft, isFalse);
      expect(flags.agentCommandSearchActions, isFalse);
      expect(flags.agentRolloutStage, AgentCenterRolloutStage.off);
    });

    test('derives enabled router modes from rollout flags', () {
      final modes = commandCenterEnabledModesForFlags(
        CommandCenterFeatureFlags.fromConfig(
          const LocalTerminalCommandCenterConfig(
            enabled: true,
            historySearch: true,
            commandBar: true,
            agentCenter: true,
            agentConversation: true,
            agentContext: true,
            agentCommandProposals: true,
            agentCommandSearchActions: true,
          ),
        ),
      );

      expect(modes, contains(CommandCenterMode.terminal));
      expect(modes, contains(CommandCenterMode.commandSearch));
      expect(modes, contains(CommandCenterMode.actionSearch));
      expect(modes, contains(CommandCenterMode.agentConversation));
      expect(modes, contains(CommandCenterMode.agentInlineAsk));
      expect(modes, contains(CommandCenterMode.agentCommandReview));
    });

    test(
      'keeps router modes terminal-only when Command Center is disabled',
      () {
        final modes = commandCenterEnabledModesForFlags(
          const CommandCenterFeatureFlags(
            agentCenter: true,
            agentConversation: true,
          ),
        );

        expect(modes, {CommandCenterMode.terminal});
      },
    );
  });
}
