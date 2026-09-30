import 'package:flutter/foundation.dart';
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
    TargetPlatform? platform,
  }) {
    final targetPlatform = usesMetaShortcuts
        ? TargetPlatform.macOS
        : platform ?? defaultTargetPlatform;
    final bindings = LocalTerminalKeyBindingResolver.resolve(
      config: config,
      platform: targetPlatform,
    );
    final exactSnapshot = LocalTerminalKeyEventSnapshot(
      key: key,
      scope: scope,
      meta: isMetaPressed,
      control: isControlPressed,
      shift: isShiftPressed,
      alt: isAltPressed,
    );
    final exactOverride = LocalTerminalKeyEventResolver.resolve(
      event: exactSnapshot,
      bindings: bindings
          .where(
            (binding) =>
                binding.source == LocalTerminalKeyBindingSource.userOverride,
          )
          .toList(growable: false),
    );
    if (exactOverride != null) return exactOverride;
    final exactAction = LocalTerminalKeyEventResolver.resolve(
      event: exactSnapshot,
      bindings: bindings,
    );
    if (exactAction != null) {
      return exactAction;
    }

    // Linux defaults are already physical Ctrl+Shift bindings. Translating a
    // remaining Ctrl event to Meta would steal raw terminal input and would
    // also give an explicitly configured Meta binding an unintended alias.
    if (targetPlatform == TargetPlatform.linux) return null;

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
