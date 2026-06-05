import '../productivity/command_blocks_history_feature_flags.dart';
import '../productivity/shell_productivity_models.dart';
import 'shell_action_dispatcher.dart';
import 'shell_action_registry.dart';
import 'shell_action_runtime_controller.dart';
import 'shell_action_view_models.dart';

class ShellCommandMenuAdapter {
  const ShellCommandMenuAdapter({required this.runtimeController});

  final ShellActionRuntimeController runtimeController;

  List<ShellActionMenuItemViewModel> items({
    required bool hasActiveSession,
    ShellProductivityState? productivity,
    CommandBlocksHistoryFeatureFlags commandBlocksHistory =
        CommandBlocksHistoryFeatureFlags.disabled,
    bool hasCommandBlocks = false,
    bool? hasHistoryPeekCommandBlocks,
  }) {
    return ShellActionViewModelBuilder.commandPaletteItems(
      hasActiveSession: hasActiveSession,
      productivity: productivity ?? runtimeController.state.productivity,
      commandBlocksHistory: commandBlocksHistory,
      hasCommandBlocks: hasCommandBlocks,
      hasHistoryPeekCommandBlocks: hasHistoryPeekCommandBlocks,
    );
  }

  Future<ShellActionRuntimeState> select({
    required TerminalActionId actionId,
    required ShellActionDispatchContext context,
  }) async {
    await runtimeController.run(actionId: actionId, context: context);
    return runtimeController.state;
  }
}
