import 'shell_action_production_binding_builder.dart';
import 'shell_action_registry.dart';

class ShellActionProductionBindingDiagnostics {
  ShellActionProductionBindingDiagnostics({required this.items});

  factory ShellActionProductionBindingDiagnostics.fromBuildResult(
    ShellActionProductionBindingBuildResult result,
  ) {
    final items = <ShellActionProductionBindingDiagnosticItem>[
      for (final actionName in result.unknownRequiredActionNames)
        ShellActionProductionBindingDiagnosticItem.unknownRequiredActionName(
          actionName,
        ),
      for (final actionName in result.unknownOptionalActionNames)
        ShellActionProductionBindingDiagnosticItem.unknownOptionalActionName(
          actionName,
        ),
      for (final actionName in result.unknownBindingNames)
        ShellActionProductionBindingDiagnosticItem.unknownBindingName(
          actionName,
        ),
      for (final actionId in result.audit.missingRequiredActions)
        ShellActionProductionBindingDiagnosticItem.missingRequiredBinding(
          actionId,
        ),
      for (final actionId in result.audit.unplannedRegisteredActions)
        ShellActionProductionBindingDiagnosticItem.unplannedBinding(actionId),
    ];

    return ShellActionProductionBindingDiagnostics(items: items);
  }

  final List<ShellActionProductionBindingDiagnosticItem> items;

  bool get hasBlockingIssues {
    return items.any((item) => item.severity.isBlocking);
  }

  bool get canCloseProductionWiring => items.isEmpty;

  List<ShellActionProductionBindingDiagnosticItem> get blockingItems {
    return items
        .where((item) => item.severity.isBlocking)
        .toList(growable: false);
  }
}

class ShellActionProductionBindingDiagnosticItem {
  const ShellActionProductionBindingDiagnosticItem._({
    required this.kind,
    required this.severity,
    required this.title,
    required this.description,
    this.actionId,
    this.actionName,
  });

  factory ShellActionProductionBindingDiagnosticItem.unknownRequiredActionName(
    String actionName,
  ) {
    return ShellActionProductionBindingDiagnosticItem._(
      kind:
          ShellActionProductionBindingDiagnosticKind.unknownRequiredActionName,
      severity: ShellActionProductionBindingDiagnosticSeverity.blocking,
      title: 'Unknown required action',
      description:
          'The production action set requires "$actionName", but the action '
          'registry does not currently expose that TerminalActionId.',
      actionName: actionName,
    );
  }

  factory ShellActionProductionBindingDiagnosticItem.unknownOptionalActionName(
    String actionName,
  ) {
    return ShellActionProductionBindingDiagnosticItem._(
      kind:
          ShellActionProductionBindingDiagnosticKind.unknownOptionalActionName,
      severity: ShellActionProductionBindingDiagnosticSeverity.advisory,
      title: 'Unknown optional action',
      description:
          'The optional production action set lists "$actionName", but the '
          'action registry does not currently expose that TerminalActionId.',
      actionName: actionName,
    );
  }

  factory ShellActionProductionBindingDiagnosticItem.unknownBindingName(
    String actionName,
  ) {
    return ShellActionProductionBindingDiagnosticItem._(
      kind: ShellActionProductionBindingDiagnosticKind.unknownBindingName,
      severity: ShellActionProductionBindingDiagnosticSeverity.blocking,
      title: 'Unknown production binding',
      description:
          'A production callback was registered for "$actionName", but the '
          'action registry does not currently expose that TerminalActionId.',
      actionName: actionName,
    );
  }

  factory ShellActionProductionBindingDiagnosticItem.missingRequiredBinding(
    TerminalActionId actionId,
  ) {
    return ShellActionProductionBindingDiagnosticItem._(
      kind: ShellActionProductionBindingDiagnosticKind.missingRequiredBinding,
      severity: ShellActionProductionBindingDiagnosticSeverity.blocking,
      title: 'Missing required production binding',
      description:
          'The required action "${actionId.name}" does not have a registered '
          'production callback.',
      actionId: actionId,
    );
  }

  factory ShellActionProductionBindingDiagnosticItem.unplannedBinding(
    TerminalActionId actionId,
  ) {
    return ShellActionProductionBindingDiagnosticItem._(
      kind: ShellActionProductionBindingDiagnosticKind.unplannedBinding,
      severity: ShellActionProductionBindingDiagnosticSeverity.advisory,
      title: 'Unplanned production binding',
      description:
          'The action "${actionId.name}" has a production callback but is not '
          'listed in the required or optional production action set.',
      actionId: actionId,
    );
  }

  final ShellActionProductionBindingDiagnosticKind kind;
  final ShellActionProductionBindingDiagnosticSeverity severity;
  final String title;
  final String description;
  final TerminalActionId? actionId;
  final String? actionName;
}

enum ShellActionProductionBindingDiagnosticKind {
  unknownRequiredActionName,
  unknownOptionalActionName,
  unknownBindingName,
  missingRequiredBinding,
  unplannedBinding,
}

enum ShellActionProductionBindingDiagnosticSeverity { blocking, advisory }

extension ShellActionProductionBindingDiagnosticSeverityX
    on ShellActionProductionBindingDiagnosticSeverity {
  bool get isBlocking {
    return this == ShellActionProductionBindingDiagnosticSeverity.blocking;
  }
}
