import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/local_terminal_key_event_resolver.dart';
import 'package:app/features/config/local_terminal_keybinding_resolver.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local terminal key event resolver', () {
    test('maps key event snapshot to resolved default action', () {
      final bindings = LocalTerminalKeyBindingResolver.resolve(
        config: const LocalTerminalKeybindingsConfig(),
      );

      final action = LocalTerminalKeyEventResolver.resolve(
        event: const LocalTerminalKeyEventSnapshot(
          key: LogicalKeyboardKey.keyT,
          scope: TerminalKeyBindingScope.focusedApp,
          meta: true,
        ),
        bindings: bindings,
      );

      expect(action, TerminalActionId.newTab);
    });

    test('maps key event snapshot to user override action', () {
      final bindings = LocalTerminalKeyBindingResolver.resolve(
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

      final action = LocalTerminalKeyEventResolver.resolve(
        event: const LocalTerminalKeyEventSnapshot(
          key: LogicalKeyboardKey.keyN,
          scope: TerminalKeyBindingScope.focusedApp,
          meta: true,
        ),
        bindings: bindings,
      );

      expect(action, TerminalActionId.newTab);
    });

    test('returns null for unmatched events', () {
      final action = LocalTerminalKeyEventResolver.resolve(
        event: const LocalTerminalKeyEventSnapshot(
          key: LogicalKeyboardKey.keyZ,
          scope: TerminalKeyBindingScope.focusedApp,
          meta: true,
        ),
        bindings: const [],
      );

      expect(action, isNull);
    });
  });
}
