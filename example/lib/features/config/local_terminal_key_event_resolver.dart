import 'package:flutter/services.dart';

import '../shell/shell_action_registry.dart';
import 'local_terminal_keybinding_resolver.dart';

class LocalTerminalKeyEventSnapshot {
  const LocalTerminalKeyEventSnapshot({
    required this.key,
    required this.scope,
    this.meta = false,
    this.control = false,
    this.shift = false,
    this.alt = false,
  });

  final LogicalKeyboardKey key;
  final TerminalKeyBindingScope scope;
  final bool meta;
  final bool control;
  final bool shift;
  final bool alt;

  String get signature {
    final parts = <String>[
      scope.name,
      if (meta) 'meta',
      if (control) 'control',
      if (shift) 'shift',
      if (alt) 'alt',
      key.debugName ?? key.keyLabel,
    ];
    return parts.join('+');
  }
}

class LocalTerminalKeyEventResolver {
  const LocalTerminalKeyEventResolver._();

  static TerminalActionId? resolve({
    required LocalTerminalKeyEventSnapshot event,
    required List<ResolvedLocalTerminalKeyBinding> bindings,
  }) {
    for (final binding in bindings) {
      if (binding.signature == event.signature) {
        return binding.actionId;
      }
    }
    return null;
  }
}
