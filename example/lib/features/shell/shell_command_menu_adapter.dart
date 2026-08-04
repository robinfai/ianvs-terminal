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
  }) {
    return ShellActionViewModelBuilder.commandPaletteItems(
          hasActiveSession: hasActiveSession,
          productivity: productivity ?? runtimeController.state.productivity,
        )
        .where(
          (item) =>
              item.actionId != TerminalActionId.openTerminalAtFolder &&
              item.actionId != TerminalActionId.paste,
        )
        .toList(growable: false);
  }

  Future<ShellActionRuntimeState> select({
    required TerminalActionId actionId,
    required ShellActionDispatchContext context,
  }) async {
    await runtimeController.run(actionId: actionId, context: context);
    return runtimeController.state;
  }
}
