import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_shortcut_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shell shortcut bridge', () {
    test('maps mac meta shortcut to default action', () {
      final action = ShellShortcutBridge.resolve(
        key: LogicalKeyboardKey.keyT,
        usesMetaShortcuts: true,
        isMetaPressed: true,
        isControlPressed: false,
        isShiftPressed: false,
        isAltPressed: false,
        scope: TerminalKeyBindingScope.focusedApp,
      );

      expect(action, TerminalActionId.newTab);
    });

    test('maps non-mac control shortcut to default action', () {
      final action = ShellShortcutBridge.resolve(
        key: LogicalKeyboardKey.keyT,
        usesMetaShortcuts: false,
        isMetaPressed: false,
        isControlPressed: true,
        isShiftPressed: false,
        isAltPressed: false,
        scope: TerminalKeyBindingScope.focusedApp,
      );

      expect(action, TerminalActionId.newTab);
    });

    test('maps config override to action', () {
      final action = ShellShortcutBridge.resolve(
        key: LogicalKeyboardKey.keyN,
        usesMetaShortcuts: true,
        isMetaPressed: true,
        isControlPressed: false,
        isShiftPressed: false,
        isAltPressed: false,
        scope: TerminalKeyBindingScope.focusedApp,
        config: const LocalTerminalKeybindingsConfig(
          overrides: {
            TerminalActionId.newTab: LocalTerminalKeyBindingOverride(
              binding: LocalTerminalKeyBinding(
                scope: TerminalKeyBindingScope.focusedApp,
                key: 'Key N',
                meta: true,
              ),
            ),
          },
        ),
      );

      expect(action, TerminalActionId.newTab);
    });
  });
}
