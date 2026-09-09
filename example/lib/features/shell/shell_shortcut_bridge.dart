import 'package:flutter/services.dart';

import '../config/local_terminal_config_models.dart';
import '../config/local_terminal_key_event_resolver.dart';
import '../config/local_terminal_keybinding_resolver.dart';
import 'shell_action_registry.dart';

class ShellShortcutBridge {
  const ShellShortcutBridge._();

  static TerminalActionId? resolve({
    required LogicalKeyboardKey key,
    required bool usesMetaShortcuts,
    required bool isMetaPressed,
    required bool isControlPressed,
    required bool isShiftPressed,
    required bool isAltPressed,
    required TerminalKeyBindingScope scope,
    LocalTerminalKeybindingsConfig config =
        const LocalTerminalKeybindingsConfig(),
  }) {
    final bindings = LocalTerminalKeyBindingResolver.resolve(config: config);
    final exactSnapshot = LocalTerminalKeyEventSnapshot(
      key: key,
      scope: scope,
      meta: isMetaPressed,
      control: isControlPressed,
      shift: isShiftPressed,
      alt: isAltPressed,
    );
    final exactAction = LocalTerminalKeyEventResolver.resolve(
      event: exactSnapshot,
      bindings: bindings,
    );
    if (exactAction != null) {
      return exactAction;
    }

    final platformSnapshot = LocalTerminalKeyEventSnapshot(
      key: key,
      scope: scope,
      meta: usesMetaShortcuts
          ? isMetaPressed && !isControlPressed
          : isControlPressed && !isMetaPressed,
      control: false,
      shift: isShiftPressed,
      alt: isAltPressed,
    );

    return LocalTerminalKeyEventResolver.resolve(
      event: platformSnapshot,
      bindings: bindings,
    );
  }
}
