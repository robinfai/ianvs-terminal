import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/local_terminal_keybinding_resolver.dart';
import 'package:app/features/config/shortcut_editor.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_shortcut_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shell shortcut bridge', () {
    TerminalActionId? linuxShortcut(
      LogicalKeyboardKey key, {
      bool shift = false,
      bool meta = false,
      bool control = true,
      TerminalKeyBindingScope scope = TerminalKeyBindingScope.terminalFocused,
      LocalTerminalKeybindingsConfig config =
          const LocalTerminalKeybindingsConfig(),
    }) => ShellShortcutBridge.resolve(
      key: key,
      usesMetaShortcuts: false,
      platform: TargetPlatform.linux,
      isMetaPressed: meta,
      isControlPressed: control,
      isShiftPressed: shift,
      isAltPressed: false,
      scope: scope,
      config: config,
    );

    test('Linux raw Ctrl letters remain terminal input in every scope', () {
      for (final key in [
        LogicalKeyboardKey.keyC,
        LogicalKeyboardKey.keyD,
        LogicalKeyboardKey.keyZ,
        LogicalKeyboardKey.keyL,
        LogicalKeyboardKey.keyW,
        LogicalKeyboardKey.keyT,
        LogicalKeyboardKey.keyF,
        LogicalKeyboardKey.keyK,
        LogicalKeyboardKey.keyV,
        LogicalKeyboardKey.keyQ,
        LogicalKeyboardKey.keyE,
      ]) {
        for (final scope in TerminalKeyBindingScope.values) {
          expect(
            linuxShortcut(key, scope: scope),
            isNull,
            reason: '${key.keyLabel} in $scope',
          );
        }
      }
    });

    test('Linux terminal and tab actions use distinct Ctrl Shift defaults', () {
      expect(
        linuxShortcut(LogicalKeyboardKey.keyC, shift: true),
        TerminalActionId.copy,
      );
      expect(
        linuxShortcut(LogicalKeyboardKey.keyV, shift: true),
        TerminalActionId.paste,
      );
      expect(
        linuxShortcut(LogicalKeyboardKey.keyF, shift: true),
        TerminalActionId.search,
      );
      expect(
        linuxShortcut(LogicalKeyboardKey.keyD, shift: true),
        TerminalActionId.splitRight,
      );
      expect(
        linuxShortcut(LogicalKeyboardKey.keyE, shift: true),
        TerminalActionId.splitDown,
      );
      expect(
        linuxShortcut(
          LogicalKeyboardKey.keyT,
          shift: true,
          scope: TerminalKeyBindingScope.focusedApp,
        ),
        TerminalActionId.newTab,
      );
      expect(
        linuxShortcut(
          LogicalKeyboardKey.keyW,
          shift: true,
          scope: TerminalKeyBindingScope.focusedApp,
        ),
        TerminalActionId.closeActiveTab,
      );
      expect(
        linuxShortcut(
          LogicalKeyboardKey.keyN,
          shift: true,
          scope: TerminalKeyBindingScope.focusedApp,
        ),
        TerminalActionId.newSshSession,
      );
      expect(
        linuxShortcut(
          LogicalKeyboardKey.keyP,
          shift: true,
          scope: TerminalKeyBindingScope.focusedApp,
        ),
        TerminalActionId.openLauncher,
      );
      final bindings = LocalTerminalKeyBindingResolver.resolve(
        config: const LocalTerminalKeybindingsConfig(),
        platform: TargetPlatform.linux,
      );
      expect(LocalTerminalKeyBindingResolver.conflicts(bindings), isEmpty);
    });

    test('Linux honors an exact user Ctrl override without aliasing Meta', () {
      const config = LocalTerminalKeybindingsConfig(
        overrides: {
          TerminalActionId.copy: LocalTerminalKeyBindingOverride(
            binding: LocalTerminalKeyBinding(
              scope: TerminalKeyBindingScope.terminalFocused,
              key: 'Key C',
              control: true,
            ),
          ),
          TerminalActionId.paste: LocalTerminalKeyBindingOverride(
            binding: LocalTerminalKeyBinding(
              scope: TerminalKeyBindingScope.terminalFocused,
              key: 'Key V',
              meta: true,
            ),
          ),
        },
      );
      expect(
        linuxShortcut(LogicalKeyboardKey.keyC, config: config),
        TerminalActionId.copy,
      );
      expect(
        linuxShortcut(LogicalKeyboardKey.keyC, shift: true, config: config),
        isNull,
      );
      expect(linuxShortcut(LogicalKeyboardKey.keyV, config: config), isNull);
      expect(
        linuxShortcut(
          LogicalKeyboardKey.keyV,
          meta: true,
          control: false,
          config: config,
        ),
        TerminalActionId.paste,
      );
    });

    test(
      'Linux disabled defaults stay disabled and editor shows physical binding',
      () {
        const disabled = LocalTerminalKeybindingsConfig(
          disabledDefaultActions: {TerminalActionId.copy},
        );
        expect(
          linuxShortcut(LogicalKeyboardKey.keyC, shift: true, config: disabled),
          isNull,
        );
        final binding = LocalTerminalShortcutFormatter.currentBinding(
          TerminalActionId.copy,
          const LocalTerminalKeybindingsConfig(),
          platform: TargetPlatform.linux,
        )!;
        expect(binding.control, isTrue);
        expect(binding.shift, isTrue);
        expect(binding.meta, isFalse);
        expect(
          LocalTerminalShortcutFormatter.currentBinding(
            TerminalActionId.copy,
            disabled,
            platform: TargetPlatform.linux,
          ),
          isNull,
        );
      },
    );

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
