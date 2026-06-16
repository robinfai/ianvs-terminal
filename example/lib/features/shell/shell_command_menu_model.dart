import '../productivity/command_blocks_history_feature_flags.dart';
import '../productivity/shell_productivity_models.dart';
import 'shell_action_registry.dart';
import 'shell_action_view_models.dart';

class ShellCommandMenuModel {
  const ShellCommandMenuModel._();

  static const List<TerminalActionId> defaultActionOrder = [
    TerminalActionId.newTab,
    TerminalActionId.toolbelt,
    TerminalActionId.defaults,
    TerminalActionId.profiles,
    TerminalActionId.dynamicProfiles,
    TerminalActionId.copy,
    TerminalActionId.copyMode,
    TerminalActionId.annotations,
    TerminalActionId.capturedOutput,
    TerminalActionId.paste,
    TerminalActionId.advancedPaste,
    TerminalActionId.pasteHistory,
    TerminalActionId.shellIntegrationUtilities,
    TerminalActionId.selectCommandOutput,
    TerminalActionId.tmuxIntegration,
    TerminalActionId.coprocess,
    TerminalActionId.passwordManager,
    TerminalActionId.instantReplay,
    TerminalActionId.openHistoryPeek,
    TerminalActionId.replayFromCommandBlock,
    TerminalActionId.search,
    TerminalActionId.openActionSearch,
    TerminalActionId.globalSearch,
    TerminalActionId.autocomplete,
    TerminalActionId.autoComposer,
    TerminalActionId.splitRight,
    TerminalActionId.splitDown,
    TerminalActionId.hotkeyWindow,
  ];

  static List<ShellActionMenuItemViewModel> defaultItems({
    required bool hasActiveSession,
    required ShellProductivityState productivity,
    CommandBlocksHistoryFeatureFlags commandBlocksHistory =
        CommandBlocksHistoryFeatureFlags.disabled,
    bool hasCommandBlocks = false,
    bool? hasHistoryPeekCommandBlocks,
  }) {
    return [
      for (final actionId in defaultActionOrder)
        if (ShellActionRegistry.actions[actionId] case final descriptor?)
          ShellActionViewModelBuilder.forDescriptor(
            descriptor: descriptor,
            hasActiveSession: hasActiveSession,
            productivity: productivity,
            commandBlocksHistory: commandBlocksHistory,
            hasCommandBlocks: hasCommandBlocks,
            hasHistoryPeekCommandBlocks: hasHistoryPeekCommandBlocks,
          ),
    ];
  }
}
