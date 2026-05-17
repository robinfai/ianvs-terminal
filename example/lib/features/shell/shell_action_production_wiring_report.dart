import 'shell_action_production_binding_diagnostics.dart';
import 'shell_action_production_wiring_state.dart';

class ShellActionProductionWiringReport {
  const ShellActionProductionWiringReport({
    required this.ready,
    required this.blockingItems,
    required this.advisoryItems,
  });

  factory ShellActionProductionWiringReport.fromState(
    ShellActionProductionWiringState state,
  ) {
    final blockingItems = <ShellActionProductionWiringReportItem>[];
    final advisoryItems = <ShellActionProductionWiringReportItem>[];

    for (final item in state.diagnostics.items) {
      final reportItem = ShellActionProductionWiringReportItem.fromDiagnostic(
        item,
      );
      if (item.severity.isBlocking) {
        blockingItems.add(reportItem);
      } else {
        advisoryItems.add(reportItem);
      }
    }

    return ShellActionProductionWiringReport(
      ready: state.isReady,
      blockingItems: List.unmodifiable(blockingItems),
      advisoryItems: List.unmodifiable(advisoryItems),
    );
  }

  final bool ready;
  final List<ShellActionProductionWiringReportItem> blockingItems;
  final List<ShellActionProductionWiringReportItem> advisoryItems;

  bool get hasBlockingItems => blockingItems.isNotEmpty;

  Map<String, Object?> toJson() {
    return {
      'ready': ready,
      'blockingItems': blockingItems.map((item) => item.toJson()).toList(),
      'advisoryItems': advisoryItems.map((item) => item.toJson()).toList(),
    };
  }
}

class ShellActionProductionWiringReportItem {
  const ShellActionProductionWiringReportItem({
    required this.kind,
    required this.severity,
    required this.title,
    required this.description,
    required this.actionId,
    required this.actionName,
  });

  factory ShellActionProductionWiringReportItem.fromDiagnostic(
    ShellActionProductionBindingDiagnosticItem item,
  ) {
    return ShellActionProductionWiringReportItem(
      kind: item.kind.name,
      severity: item.severity.name,
      title: item.title,
      description: item.description,
      actionId: item.actionId?.name,
      actionName: item.actionName,
    );
  }

  final String kind;
  final String severity;
  final String title;
  final String description;
  final String? actionId;
  final String? actionName;

  Map<String, Object?> toJson() {
    return {
      'kind': kind,
      'severity': severity,
      'title': title,
      'description': description,
      'actionId': actionId,
      'actionName': actionName,
    };
  }
}
