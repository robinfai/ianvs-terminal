import 'package:app/features/command_center/command_action_search_controller.dart';
import 'package:app/features/command_center/command_action_search_index.dart';
import 'package:app/features/command_center/saved_command_repository.dart';
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_command_action_search_adapter.dart';
import 'package:app/ui/foundation/terminal_theme_presets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShellCommandActionSearchAdapter', () {
    const adapter = ShellCommandActionSearchAdapter();

    test('maps visible shell actions into action search items', () {
      final items = adapter.itemsFor(
        hasActiveSession: true,
        productivity: const ShellProductivityState(),
      );

      final newTab = items.singleWhere(
        (item) => item.id == TerminalActionId.newTab.name,
      );

      expect(newTab.kind, CommandActionSearchItemKind.appAction);
      expect(newTab.title, 'New tab');
      expect(newTab.subtitle, contains('App action'));
      expect(newTab.subtitle, contains('cmd+T'));
      expect(newTab.keywords, contains('new_tab'));
      expect(newTab.keywords, contains('app'));
      expect(
        items.any((item) => item.id == TerminalActionId.previousPrompt.name),
        isFalse,
      );
    });

    test('carries disabled action context into searchable metadata', () {
      final items = adapter.itemsFor(
        hasActiveSession: true,
        productivity: const ShellProductivityState(readOnly: true),
      );

      final paste = items.singleWhere(
        (item) => item.id == TerminalActionId.paste.name,
      );

      expect(paste.title, 'Paste');
      expect(paste.subtitle, contains('Session action'));
      expect(paste.subtitle, contains('Read-only mode'));
      expect(paste.keywords, anyElement(contains('Disable read-only')));
    });

    test('adds terminal theme preset actions with encoded theme ids', () {
      final items = adapter.itemsFor(
        hasActiveSession: true,
        productivity: const ShellProductivityState(),
      );
      final preset = terminalThemePresets.first;

      final theme = items.singleWhere(
        (item) => item.id == 'applyTheme:${preset.id}',
      );

      expect(theme.title, 'Apply ${preset.name} theme');
      expect(theme.subtitle, contains('Theme preset'));
      expect(theme.keywords, contains('theme preset'));
      expect(theme.keywords, contains(preset.id));
      expect(theme.keywords, contains(preset.tone.label));
    });

    test('resolves app action outputs back to terminal action ids', () {
      const item = CommandActionSearchItem.appAction(
        id: 'toggleReadOnly',
        title: 'Toggle read only',
      );

      final actionId = adapter.actionIdFor(
        const CommandActionSearchOutput.openAction(item),
      );
      final savedCommand = adapter.actionIdFor(
        CommandActionSearchOutput.insertSavedCommand(
          CommandActionSearchItem.savedCommand(
            SavedCommandEntry(
              id: 'release-build',
              title: 'Build release',
              command: 'flutter build macos --release',
              createdAt: DateTime.utc(2026, 6, 14),
              updatedAt: DateTime.utc(2026, 6, 15),
            ),
          ),
        ),
      );

      expect(actionId, TerminalActionId.toggleReadOnly);
      expect(savedCommand, isNull);
    });
  });
}
