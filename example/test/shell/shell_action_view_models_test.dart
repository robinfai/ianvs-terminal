import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_action_view_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shell action view models', () {
    test('command palette items include visible registry actions', () {
      final items = ShellActionViewModelBuilder.commandPaletteItems(
        hasActiveSession: true,
        productivity: const ShellProductivityState(),
      );

      expect(
        items.any((item) => item.actionId == TerminalActionId.newTab),
        isTrue,
      );
      expect(
        items.any((item) => item.actionId == TerminalActionId.previousPrompt),
        isFalse,
      );
    });

    test('view model carries disabled copy', () {
      final item = ShellActionViewModelBuilder.forDescriptor(
        descriptor: ShellActionRegistry.actions[TerminalActionId.paste]!,
        hasActiveSession: true,
        productivity: const ShellProductivityState(readOnly: true),
      );

      expect(item.enabled, isFalse);
      expect(item.disabledTitle, 'Read-only mode');
      expect(item.disabledDescription, contains('Disable read-only'));
    });

    test('view model keeps shortcut hints from registry', () {
      final item = ShellActionViewModelBuilder.forDescriptor(
        descriptor: ShellActionRegistry.actions[TerminalActionId.newTab]!,
        hasActiveSession: false,
        productivity: const ShellProductivityState(),
      );

      expect(item.shortcutHint, 'cmd+T');
    });
  });
}
