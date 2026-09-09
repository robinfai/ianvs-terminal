import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/local_terminal_keybinding_resolver.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local terminal keybinding resolver', () {
    test('uses registry defaults when config has no overrides', () {
      final resolved = LocalTerminalKeyBindingResolver.resolve(
        config: const LocalTerminalKeybindingsConfig(),
      );

      expect(
        resolved.any((binding) => binding.actionId == TerminalActionId.newTab),
        isTrue,
      );
      expect(LocalTerminalKeyBindingResolver.conflicts(resolved), isEmpty);
    });

    test('disabled default action removes registry binding', () {
      final resolved = LocalTerminalKeyBindingResolver.resolve(
        config: const LocalTerminalKeybindingsConfig(
          disabledDefaultActions: {TerminalActionId.newTab},
        ),
      );

      expect(
        resolved.any((binding) => binding.actionId == TerminalActionId.newTab),
        isFalse,
      );
    });

    test('disabled user override removes registry binding', () {
      final resolved = LocalTerminalKeyBindingResolver.resolve(
        config: const LocalTerminalKeybindingsConfig(
          overrides: {
            TerminalActionId.newTab: LocalTerminalKeyBindingOverride(
              enabled: false,
            ),
          },
        ),
      );

      expect(
        resolved.any((binding) => binding.actionId == TerminalActionId.newTab),
        isFalse,
      );
    });

    test('enabled override without binding falls back to registry default', () {
      final resolved = LocalTerminalKeyBindingResolver.resolve(
        config: const LocalTerminalKeybindingsConfig(
          overrides: {
            TerminalActionId.newTab: LocalTerminalKeyBindingOverride(),
          },
        ),
      );

      final newTab = resolved.singleWhere(
        (binding) => binding.actionId == TerminalActionId.newTab,
      );

      expect(newTab.source, LocalTerminalKeyBindingSource.defaultBinding);
    });

    test('user override replaces registry default binding', () {
      final resolved = LocalTerminalKeyBindingResolver.resolve(
        config: const LocalTerminalKeybindingsConfig(
          overrides: {
            TerminalActionId.newTab: LocalTerminalKeyBindingOverride(
              binding: LocalTerminalKeyBinding(
                scope: TerminalKeyBindingScope.focusedApp,
                key: 'KeyN',
                meta: true,
              ),
            ),
          },
        ),
      );

      final newTab = resolved.singleWhere(
        (binding) => binding.actionId == TerminalActionId.newTab,
      );

      expect(newTab.source, LocalTerminalKeyBindingSource.userOverride);
      expect(newTab.signature, 'focusedApp+meta+Key N');
    });

    test('detects resolved override conflicts', () {
      final resolved = LocalTerminalKeyBindingResolver.resolve(
        config: const LocalTerminalKeybindingsConfig(
          overrides: {
            TerminalActionId.newTab: LocalTerminalKeyBindingOverride(
              binding: LocalTerminalKeyBinding(
                scope: TerminalKeyBindingScope.focusedApp,
                key: 'KeyN',
                meta: true,
              ),
            ),
            TerminalActionId.openDefaults: LocalTerminalKeyBindingOverride(
              binding: LocalTerminalKeyBinding(
                scope: TerminalKeyBindingScope.focusedApp,
                key: 'KeyN',
                meta: true,
              ),
            ),
          },
        ),
      );

      final conflicts = LocalTerminalKeyBindingResolver.conflicts(resolved);

      expect(conflicts, hasLength(1));
      expect(
        conflicts.single.actionIds,
        containsAll({TerminalActionId.newTab, TerminalActionId.openDefaults}),
      );
    });
  });
}
