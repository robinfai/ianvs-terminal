import 'shell_action_production_action_name_resolver.dart';
import 'shell_action_production_action_set.dart';
import 'shell_action_registry.dart';
import 'shell_action_runtime_binding_audit.dart';
import 'shell_action_runtime_bindings.dart';

class ShellActionProductionBindingBuilder {
  ShellActionProductionBindingBuilder({
    ShellActionProductionActionSet? actionSet,
    Map<String, ShellActionBinding> bindingsByName = const {},
  }) : actionSet = actionSet ?? ShellActionProductionActionSet.defaults(),
       bindingsByName = Map.unmodifiable(bindingsByName);

  final ShellActionProductionActionSet actionSet;
  final Map<String, ShellActionBinding> bindingsByName;

  ShellActionProductionBindingBuildResult build() {
    const actionNameResolver = ShellActionProductionActionNameResolver();
    final resolvedBindings = <TerminalActionId, ShellActionBinding>{};
    final unknownBindingNames = <String>{};

    for (final entry in bindingsByName.entries) {
      final actionId = actionNameResolver.resolve(entry.key);
      if (actionId == null) {
        unknownBindingNames.add(entry.key);
        continue;
      }
      resolvedBindings[actionId] = entry.value;
    }

    final bindings = ShellActionRuntimeBindings(bindings: resolvedBindings);

    return ShellActionProductionBindingBuildResult(
      bindings: bindings,
      audit: actionSet.auditBindings(bindings),
      unknownBindingNames: unknownBindingNames,
      unknownRequiredActionNames: actionSet.unknownRequiredActionNames,
      unknownOptionalActionNames: actionSet.unknownOptionalActionNames,
    );
  }
}

class ShellActionProductionBindingBuildResult {
  const ShellActionProductionBindingBuildResult({
    required this.bindings,
    required this.audit,
    required this.unknownBindingNames,
    required this.unknownRequiredActionNames,
    required this.unknownOptionalActionNames,
  });

  final ShellActionRuntimeBindings bindings;
  final ShellActionRuntimeBindingAudit audit;
  final Set<String> unknownBindingNames;
  final Set<String> unknownRequiredActionNames;
  final Set<String> unknownOptionalActionNames;

  bool get hasUnknownNames {
    return unknownBindingNames.isNotEmpty ||
        unknownRequiredActionNames.isNotEmpty ||
        unknownOptionalActionNames.isNotEmpty;
  }

  bool get isComplete => !hasUnknownNames && audit.isComplete;
}
