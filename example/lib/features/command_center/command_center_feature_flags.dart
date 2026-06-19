import '../config/local_terminal_config_models.dart';
import 'command_center_mode_router.dart';

enum AgentCenterRolloutStage {
  off,
  conversationPreview,
  contextPreview,
  proposalPreview,
  providerPreview,
}

class CommandCenterFeatureFlags {
  const CommandCenterFeatureFlags({
    this.enabled = false,
    this.historySearch = false,
    this.commandBlocks = false,
    this.commandBar = false,
    this.contextChips = false,
    this.reviewEntrypoints = false,
    this.verificationDiagnostics = false,
    this.agentCenter = false,
    this.agentConversation = false,
    this.agentContext = false,
    this.agentCommandProposals = false,
    this.agentProviderDraft = false,
    this.agentCommandSearchActions = false,
  });

  factory CommandCenterFeatureFlags.fromConfig(
    LocalTerminalCommandCenterConfig config, {
    CommandCenterFeatureFlagOverrides overrides =
        const CommandCenterFeatureFlagOverrides(),
  }) {
    final enabled = overrides.enabled ?? config.enabled;
    final agentCenter =
        enabled && (overrides.agentCenter ?? config.agentCenter);
    final agentConversation =
        agentCenter &&
        (overrides.agentConversation ?? config.agentConversation);
    return CommandCenterFeatureFlags(
      enabled: enabled,
      historySearch:
          enabled && (overrides.historySearch ?? config.historySearch),
      commandBlocks:
          enabled && (overrides.commandBlocks ?? config.commandBlocks),
      commandBar: enabled && (overrides.commandBar ?? config.commandBar),
      contextChips: enabled && (overrides.contextChips ?? config.contextChips),
      reviewEntrypoints:
          enabled && (overrides.reviewEntrypoints ?? config.reviewEntrypoints),
      verificationDiagnostics:
          enabled &&
          (overrides.verificationDiagnostics ?? config.verificationDiagnostics),
      agentCenter: agentCenter,
      agentConversation: agentConversation,
      agentContext:
          agentConversation && (overrides.agentContext ?? config.agentContext),
      agentCommandProposals:
          agentConversation &&
          (overrides.agentCommandProposals ?? config.agentCommandProposals),
      agentProviderDraft:
          agentConversation &&
          (overrides.agentProviderDraft ?? config.agentProviderDraft),
      agentCommandSearchActions:
          agentConversation &&
          (overrides.agentCommandSearchActions ??
              config.agentCommandSearchActions),
    );
  }

  final bool enabled;
  final bool historySearch;
  final bool commandBlocks;
  final bool commandBar;
  final bool contextChips;
  final bool reviewEntrypoints;
  final bool verificationDiagnostics;
  final bool agentCenter;
  final bool agentConversation;
  final bool agentContext;
  final bool agentCommandProposals;
  final bool agentProviderDraft;
  final bool agentCommandSearchActions;

  AgentCenterRolloutStage get agentRolloutStage {
    if (!agentCenter || !agentConversation) {
      return AgentCenterRolloutStage.off;
    }
    if (agentProviderDraft) {
      return AgentCenterRolloutStage.providerPreview;
    }
    if (agentCommandProposals || agentCommandSearchActions) {
      return AgentCenterRolloutStage.proposalPreview;
    }
    if (agentContext) {
      return AgentCenterRolloutStage.contextPreview;
    }
    return AgentCenterRolloutStage.conversationPreview;
  }
}

class CommandCenterFeatureFlagOverrides {
  const CommandCenterFeatureFlagOverrides({
    this.enabled,
    this.historySearch,
    this.commandBlocks,
    this.commandBar,
    this.contextChips,
    this.reviewEntrypoints,
    this.verificationDiagnostics,
    this.agentCenter,
    this.agentConversation,
    this.agentContext,
    this.agentCommandProposals,
    this.agentProviderDraft,
    this.agentCommandSearchActions,
  });

  final bool? enabled;
  final bool? historySearch;
  final bool? commandBlocks;
  final bool? commandBar;
  final bool? contextChips;
  final bool? reviewEntrypoints;
  final bool? verificationDiagnostics;
  final bool? agentCenter;
  final bool? agentConversation;
  final bool? agentContext;
  final bool? agentCommandProposals;
  final bool? agentProviderDraft;
  final bool? agentCommandSearchActions;
}

Set<CommandCenterMode> commandCenterEnabledModesForFlags(
  CommandCenterFeatureFlags flags,
) {
  final modes = <CommandCenterMode>{CommandCenterMode.terminal};
  if (!flags.enabled) {
    return modes;
  }
  if (flags.commandBar) {
    modes.add(CommandCenterMode.commandBar);
    modes.add(CommandCenterMode.actionSearch);
    modes.add(CommandCenterMode.savedCommand);
  }
  if (flags.historySearch) {
    modes.add(CommandCenterMode.commandSearch);
  }
  if (flags.agentConversation) {
    modes.add(CommandCenterMode.agentConversation);
  }
  if (flags.agentContext) {
    modes.add(CommandCenterMode.agentInlineAsk);
  }
  if (flags.agentCommandProposals) {
    modes.add(CommandCenterMode.agentCommandReview);
  }
  return Set<CommandCenterMode>.unmodifiable(modes);
}
