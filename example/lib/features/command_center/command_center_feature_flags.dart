import '../config/local_terminal_config_models.dart';

class CommandCenterFeatureFlags {
  const CommandCenterFeatureFlags({
    this.enabled = false,
    this.historySearch = false,
    this.commandBlocks = false,
    this.commandBar = false,
    this.contextChips = false,
    this.reviewEntrypoints = false,
    this.verificationDiagnostics = false,
  });

  factory CommandCenterFeatureFlags.fromConfig(
    LocalTerminalCommandCenterConfig config, {
    CommandCenterFeatureFlagOverrides overrides =
        const CommandCenterFeatureFlagOverrides(),
  }) {
    final enabled = overrides.enabled ?? config.enabled;
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
    );
  }

  final bool enabled;
  final bool historySearch;
  final bool commandBlocks;
  final bool commandBar;
  final bool contextChips;
  final bool reviewEntrypoints;
  final bool verificationDiagnostics;
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
  });

  final bool? enabled;
  final bool? historySearch;
  final bool? commandBlocks;
  final bool? commandBar;
  final bool? contextChips;
  final bool? reviewEntrypoints;
  final bool? verificationDiagnostics;
}
