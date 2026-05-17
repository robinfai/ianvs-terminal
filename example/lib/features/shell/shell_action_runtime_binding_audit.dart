import 'shell_action_registry.dart';
import 'shell_action_runtime_bindings.dart';

class ShellActionRuntimeBindingAudit {
  ShellActionRuntimeBindingAudit({
    required this.requiredActions,
    required this.optionalActions,
    required this.registeredActions,
  }) : missingRequiredActions = requiredActions
           .where((actionId) => !registeredActions.contains(actionId))
           .toSet(),
       unplannedRegisteredActions = registeredActions
           .where(
             (actionId) =>
                 !requiredActions.contains(actionId) &&
                 !optionalActions.contains(actionId),
           )
           .toSet();

  factory ShellActionRuntimeBindingAudit.fromBindings({
    required ShellActionRuntimeBindings bindings,
    required Iterable<TerminalActionId> requiredActions,
    Iterable<TerminalActionId> optionalActions = const [],
  }) {
    return ShellActionRuntimeBindingAudit(
      requiredActions: requiredActions.toSet(),
      optionalActions: optionalActions.toSet(),
      registeredActions: bindings.actionIds,
    );
  }

  final Set<TerminalActionId> requiredActions;
  final Set<TerminalActionId> optionalActions;
  final Set<TerminalActionId> registeredActions;
  final Set<TerminalActionId> missingRequiredActions;
  final Set<TerminalActionId> unplannedRegisteredActions;

  bool get isComplete => missingRequiredActions.isEmpty;

  List<ShellActionRuntimeBindingAuditItem> get missingRequiredItems {
    return missingRequiredActions
        .map(
          (actionId) => ShellActionRuntimeBindingAuditItem(
            actionId: actionId,
            severity: ShellActionRuntimeBindingAuditSeverity.required,
          ),
        )
        .toList(growable: false);
  }

  List<ShellActionRuntimeBindingAuditItem> get unplannedRegisteredItems {
    return unplannedRegisteredActions
        .map(
          (actionId) => ShellActionRuntimeBindingAuditItem(
            actionId: actionId,
            severity: ShellActionRuntimeBindingAuditSeverity.unplanned,
          ),
        )
        .toList(growable: false);
  }
}

class ShellActionRuntimeBindingAuditItem {
  const ShellActionRuntimeBindingAuditItem({
    required this.actionId,
    required this.severity,
  });

  final TerminalActionId actionId;
  final ShellActionRuntimeBindingAuditSeverity severity;
}

enum ShellActionRuntimeBindingAuditSeverity { required, unplanned }
