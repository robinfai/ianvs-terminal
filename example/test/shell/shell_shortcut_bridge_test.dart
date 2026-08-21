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

    test('maps mac command-shift-t to new SSH session', () {
      final action = ShellShortcutBridge.resolve(
        key: LogicalKeyboardKey.keyT,
        usesMetaShortcuts: true,
        isMetaPressed: true,
        isControlPressed: false,
        isShiftPressed: true,
        isAltPressed: false,
        scope: TerminalKeyBindingScope.focusedApp,
      );

      expect(action, TerminalActionId.newSshSession);
    });

    test('maps non-mac control-shift-t to new SSH session', () {
      final action = ShellShortcutBridge.resolve(
        key: LogicalKeyboardKey.keyT,
        usesMetaShortcuts: false,
        isMetaPressed: false,
        isControlPressed: true,
        isShiftPressed: true,
        isAltPressed: false,
        scope: TerminalKeyBindingScope.focusedApp,
      );

      expect(action, TerminalActionId.newSshSession);
    });

    test('maps mac terminal-focused search shortcut to search action', () {
      final action = ShellShortcutBridge.resolve(
        key: LogicalKeyboardKey.keyF,
        usesMetaShortcuts: true,
        isMetaPressed: true,
        isControlPressed: false,
        isShiftPressed: false,
        isAltPressed: false,
        scope: TerminalKeyBindingScope.terminalFocused,
      );

      expect(action, TerminalActionId.search);
    });

    test('maps non-mac terminal-focused search shortcut to search action', () {
      final action = ShellShortcutBridge.resolve(
        key: LogicalKeyboardKey.keyF,
        usesMetaShortcuts: false,
        isMetaPressed: false,
        isControlPressed: true,
        isShiftPressed: false,
        isAltPressed: false,
        scope: TerminalKeyBindingScope.terminalFocused,
      );

      expect(action, TerminalActionId.search);
    });

    test('maps mac command-k to clear buffer', () {
      final action = ShellShortcutBridge.resolve(
        key: LogicalKeyboardKey.keyK,
        usesMetaShortcuts: true,
        isMetaPressed: true,
        isControlPressed: false,
        isShiftPressed: false,
        isAltPressed: false,
        scope: TerminalKeyBindingScope.terminalFocused,
      );

      expect(action, TerminalActionId.clearBuffer);
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

    test('maps explicit control override before platform fallback', () {
      final action = ShellShortcutBridge.resolve(
        key: LogicalKeyboardKey.keyT,
        usesMetaShortcuts: false,
        isMetaPressed: false,
        isControlPressed: true,
        isShiftPressed: false,
        isAltPressed: false,
        scope: TerminalKeyBindingScope.focusedApp,
        config: const LocalTerminalKeybindingsConfig(
          overrides: {
            TerminalActionId.openDefaults: LocalTerminalKeyBindingOverride(
              binding: LocalTerminalKeyBinding(
                scope: TerminalKeyBindingScope.focusedApp,
                key: 'Key T',
                control: true,
              ),
            ),
          },
        ),
      );

      expect(action, TerminalActionId.openDefaults);
    });
  });
}
