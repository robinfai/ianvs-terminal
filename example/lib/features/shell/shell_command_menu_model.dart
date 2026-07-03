import '../productivity/shell_productivity_models.dart';
import 'shell_action_registry.dart';
import 'shell_action_view_models.dart';

class ShellCommandMenuModel {
  const ShellCommandMenuModel._();

  static const List<TerminalActionId> defaultActionOrder = [
    TerminalActionId.newTab,
    TerminalActionId.defaults,
    TerminalActionId.profiles,
    TerminalActionId.dynamicProfiles,
    TerminalActionId.paste,
    TerminalActionId.tmuxIntegration,
    TerminalActionId.coprocess,
    TerminalActionId.passwordManager,
    TerminalActionId.instantReplay,
    TerminalActionId.search,
    TerminalActionId.globalSearch,
  ];

  static List<ShellActionMenuItemViewModel> defaultItems({
    required bool hasActiveSession,
    required ShellProductivityState productivity,
  }) {
    return [
      for (final actionId in defaultActionOrder)
        if (ShellActionRegistry.actions[actionId] case final descriptor?)
          ShellActionViewModelBuilder.forDescriptor(
            descriptor: descriptor,
            hasActiveSession: hasActiveSession,
            productivity: productivity,
          ),
    ];
  }
}
