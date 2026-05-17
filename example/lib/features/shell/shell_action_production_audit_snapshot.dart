import 'shell_action_production_dispatch_report.dart';
import 'shell_action_production_wiring_report.dart';

class ShellActionProductionAuditSnapshot {
  const ShellActionProductionAuditSnapshot({
    required this.capturedAt,
    required this.wiringReport,
    this.recentDispatchReports = const [],
  });

  final DateTime capturedAt;
  final ShellActionProductionWiringReport wiringReport;
  final List<ShellActionProductionDispatchReport> recentDispatchReports;

  bool get canCloseP1ActionWiring {
    return wiringReport.ready &&
        !wiringReport.hasBlockingItems &&
        !hasFailedDispatches;
  }

  bool get hasFailedDispatches {
    return recentDispatchReports.any((report) => report.failed);
  }

  Map<String, Object?> toJson() {
    return {
      'capturedAt': capturedAt.toIso8601String(),
      'canCloseP1ActionWiring': canCloseP1ActionWiring,
      'hasFailedDispatches': hasFailedDispatches,
      'wiringReport': wiringReport.toJson(),
      'recentDispatchReports': recentDispatchReports
          .map((report) => report.toJson())
          .toList(growable: false),
    };
  }
}
