import '../shell/shell_action_registry.dart';
import 'local_terminal_config_models.dart';

enum LocalTerminalKeyBindingSource { defaultBinding, userOverride }

class ResolvedLocalTerminalKeyBinding {
  const ResolvedLocalTerminalKeyBinding({
    required this.actionId,
    required this.signature,
    required this.source,
  });

  final TerminalActionId actionId;
  final String signature;
  final LocalTerminalKeyBindingSource source;
}

class ResolvedLocalTerminalKeyBindingConflict {
  const ResolvedLocalTerminalKeyBindingConflict({
    required this.signature,
    required this.actionIds,
  });

  final String signature;
  final Set<TerminalActionId> actionIds;
}

class LocalTerminalKeyBindingResolver {
  const LocalTerminalKeyBindingResolver._();

  static List<ResolvedLocalTerminalKeyBinding> resolve({
    required LocalTerminalKeybindingsConfig config,
    Map<TerminalActionId, TerminalActionDescriptor> registry =
        ShellActionRegistry.actions,
  }) {
    final resolved = <ResolvedLocalTerminalKeyBinding>[];

    for (final entry in registry.entries) {
      final actionId = entry.key;
      if (!entry.value.hasUserEntryPoint) {
        continue;
      }
      if (config.disabledDefaultActions.contains(actionId)) {
        continue;
      }

      final override = config.overrides[actionId];
      if (override != null) {
        if (!override.enabled) {
          continue;
        }

        final binding = override.binding;
        if (binding != null) {
          resolved.add(
            ResolvedLocalTerminalKeyBinding(
              actionId: actionId,
              signature: binding.signature,
              source: LocalTerminalKeyBindingSource.userOverride,
            ),
          );
          continue;
        }
      }

      final defaultBinding = entry.value.defaultKeyBinding;
      if (defaultBinding == null) {
        continue;
      }

      resolved.add(
        ResolvedLocalTerminalKeyBinding(
          actionId: actionId,
          signature: defaultBinding.signature,
          source: LocalTerminalKeyBindingSource.defaultBinding,
        ),
      );
    }

    return List<ResolvedLocalTerminalKeyBinding>.unmodifiable(resolved);
  }

  static List<ResolvedLocalTerminalKeyBindingConflict> conflicts(
    Iterable<ResolvedLocalTerminalKeyBinding> bindings,
  ) {
    final actionsBySignature = <String, Set<TerminalActionId>>{};
    for (final binding in bindings) {
      actionsBySignature
          .putIfAbsent(binding.signature, () => <TerminalActionId>{})
          .add(binding.actionId);
    }

    return actionsBySignature.entries
        .where((entry) => entry.value.length > 1)
        .map(
          (entry) => ResolvedLocalTerminalKeyBindingConflict(
            signature: entry.key,
            actionIds: Set<TerminalActionId>.unmodifiable(entry.value),
          ),
        )
        .toList(growable: false);
  }
}
