import 'package:app/features/productivity/command_blocks_history_feature_flags.dart';
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_command_menu_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shell command menu model', () {
    test('keeps existing command menu action order', () {
      expect(
        ShellCommandMenuModel.defaultActionOrder.first,
        TerminalActionId.newTab,
      );
      expect(
        ShellCommandMenuModel.defaultActionOrder.last,
        TerminalActionId.hotkeyWindow,
      );
      expect(
        ShellCommandMenuModel.defaultActionOrder,
        containsAll([
          TerminalActionId.profiles,
          TerminalActionId.dynamicProfiles,
          TerminalActionId.commandSearch,
          TerminalActionId.splitRight,
          TerminalActionId.splitDown,
        ]),
      );
      expect(
        ShellCommandMenuModel.defaultActionOrder,
        isNot(
          containsAll([
            TerminalActionId.saveCommandSnapshot,
            TerminalActionId.compareLastCommandRun,
            TerminalActionId.markCommandBlock,
          ]),
        ),
      );
    });

    test('builds default menu item view models in fixed order', () {
      final items = ShellCommandMenuModel.defaultItems(
        hasActiveSession: true,
        productivity: const ShellProductivityState(),
      );

      expect(items.first.actionId, TerminalActionId.newTab);
      expect(items.last.actionId, TerminalActionId.hotkeyWindow);
      expect(items.length, ShellCommandMenuModel.defaultActionOrder.length);
    });

    test('default menu item carries disabled reason when unavailable', () {
      final items = ShellCommandMenuModel.defaultItems(
        hasActiveSession: false,
        productivity: const ShellProductivityState(),
      );

      final splitRight = items.singleWhere(
        (item) => item.actionId == TerminalActionId.splitRight,
      );

      expect(splitRight.enabled, isFalse);
      expect(splitRight.disabledTitle, 'No active session');
    });

    test('default menu passes command block gate inputs into items', () {
      final items = ShellCommandMenuModel.defaultItems(
        hasActiveSession: true,
        productivity: const ShellProductivityState(),
        commandBlocksHistory: _commandBlocksHistoryFlags,
        hasCommandBlocks: true,
      );

      final commandSearch = items.singleWhere(
        (item) => item.actionId == TerminalActionId.commandSearch,
      );

      expect(commandSearch.enabled, isTrue);
    });
  });
}

const _commandBlocksHistoryFlags = CommandBlocksHistoryFeatureFlags(
  enabled: true,
  commandBlocks: true,
  failureSnapshots: true,
  reviewWorkspaceEntrypoints: true,
  outputDiff: true,
);
