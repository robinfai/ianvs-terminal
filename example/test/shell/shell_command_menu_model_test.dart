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
          TerminalActionId.splitRight,
          TerminalActionId.splitDown,
        ]),
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
  });
}
