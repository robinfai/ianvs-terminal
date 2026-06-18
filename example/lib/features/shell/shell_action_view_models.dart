import '../productivity/command_blocks_history_feature_flags.dart';
import '../productivity/shell_productivity_models.dart';
import '../command_center/command_block_models.dart';
import 'shell_action_availability.dart';
import 'shell_action_registry.dart';

class ShellActionMenuItemViewModel {
  const ShellActionMenuItemViewModel({
    required this.actionId,
    required this.label,
    required this.enabled,
    this.disabledTitle,
    this.disabledDescription,
    this.shortcutHint,
  });

  final TerminalActionId actionId;
  final String label;
  final bool enabled;
  final String? disabledTitle;
  final String? disabledDescription;
  final String? shortcutHint;
}

class ShellActionViewModelBuilder {
  const ShellActionViewModelBuilder._();

  static List<ShellActionMenuItemViewModel> commandPaletteItems({
    required bool hasActiveSession,
    required ShellProductivityState productivity,
    CommandBlocksHistoryFeatureFlags commandBlocksHistory =
        CommandBlocksHistoryFeatureFlags.disabled,
    CommandBlock? commandBlock,
    bool hasCommandBlocks = false,
  }) {
    return ShellActionRegistry.actions.values
        .where((descriptor) => descriptor.commandPaletteVisible)
        .map(
          (descriptor) => forDescriptor(
            descriptor: descriptor,
            hasActiveSession: hasActiveSession,
            productivity: productivity,
            commandBlocksHistory: commandBlocksHistory,
            commandBlock: commandBlock,
            hasCommandBlocks: hasCommandBlocks,
          ),
        )
        .toList(growable: false);
  }

  static ShellActionMenuItemViewModel forDescriptor({
    required TerminalActionDescriptor descriptor,
    required bool hasActiveSession,
    required ShellProductivityState productivity,
    CommandBlocksHistoryFeatureFlags commandBlocksHistory =
        CommandBlocksHistoryFeatureFlags.disabled,
    CommandBlock? commandBlock,
    bool hasCommandBlocks = false,
  }) {
    final availability = ShellActionAvailabilityResolver.resolve(
      actionId: descriptor.id,
      hasActiveSession: hasActiveSession,
      productivity: productivity,
      commandBlocksHistory: commandBlocksHistory,
      commandBlock: commandBlock,
      hasCommandBlocks: hasCommandBlocks,
    );
    final reason = availability.reason;

    return ShellActionMenuItemViewModel(
      actionId: descriptor.id,
      label: descriptor.label,
      enabled: availability.enabled,
      disabledTitle: reason?.title,
      disabledDescription: reason?.description,
      shortcutHint: descriptor.shortcutHint,
    );
  }
}
