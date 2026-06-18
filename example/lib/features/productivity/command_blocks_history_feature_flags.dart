import '../config/local_terminal_config_models.dart';

class CommandBlocksHistoryFeatureFlags {
  const CommandBlocksHistoryFeatureFlags({
    required this.enabled,
    required this.commandBlocks,
    required this.failureSnapshots,
    required this.reviewWorkspaceEntrypoints,
    required this.outputDiff,
  });

  static const disabled = CommandBlocksHistoryFeatureFlags(
    enabled: false,
    commandBlocks: false,
    failureSnapshots: false,
    reviewWorkspaceEntrypoints: false,
    outputDiff: false,
  );

  final bool enabled;
  final bool commandBlocks;
  final bool failureSnapshots;
  final bool reviewWorkspaceEntrypoints;
  final bool outputDiff;

  factory CommandBlocksHistoryFeatureFlags.fromConfig(
    LocalTerminalCommandBlocksHistoryConfig config,
  ) {
    if (!config.enabled) {
      return disabled;
    }
    return CommandBlocksHistoryFeatureFlags(
      enabled: true,
      commandBlocks: config.commandBlocks,
      failureSnapshots: config.failureSnapshots,
      reviewWorkspaceEntrypoints: config.reviewWorkspaceEntrypoints,
      outputDiff: config.outputDiff,
    );
  }

  Map<String, Object?> toDiagnosticsJson() {
    return {
      'enabled': enabled,
      'commandBlocks': commandBlocks,
      'failureSnapshots': failureSnapshots,
      'reviewWorkspaceEntrypoints': reviewWorkspaceEntrypoints,
      'outputDiff': outputDiff,
    };
  }
}
