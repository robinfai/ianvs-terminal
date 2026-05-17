import 'local_terminal_completion_diagnostics_actions.dart';
import 'local_terminal_completion_diagnostics_view_model.dart';
import 'local_terminal_completion_command_menu_adapter.dart';
import 'local_terminal_completion_evidence_report.dart';
import 'local_terminal_completion_menu_model.dart';
import 'local_terminal_completion_summary.dart';
import 'local_terminal_production_wiring_bundle.dart';
import 'local_terminal_real_wiring_backlog_evidence.dart';
import 'local_terminal_verification_evidence.dart';

class LocalTerminalShellUiWiringFacade {
  LocalTerminalShellUiWiringFacade({
    required this.bundle,
    required this.backlogEvidence,
    required this.verificationEvidence,
  }) {
    final builtReport = backlogEvidence.toCompletionReport(bundle);
    final builtSummary = LocalTerminalCompletionSummary.fromEvidence(
      report: builtReport,
      verificationEvidence: verificationEvidence,
    );
    final builtDiagnosticsViewModel =
        LocalTerminalCompletionDiagnosticsViewModel.fromEvidence(
          report: builtReport,
          verificationEvidence: verificationEvidence,
        );
    final builtDiagnosticsActionGroup =
        LocalTerminalCompletionDiagnosticsActionGroup.fromViewModel(
          builtDiagnosticsViewModel,
        );

    report = builtReport;
    summary = builtSummary;
    diagnosticsViewModel = builtDiagnosticsViewModel;
    diagnosticsActionGroup = builtDiagnosticsActionGroup;
    completionMenuModel = LocalTerminalCompletionMenuModel.fromActionGroup(
      builtDiagnosticsActionGroup,
    );
    commandMenuAdapter = LocalTerminalCompletionCommandMenuAdapter(
      model: completionMenuModel,
    );
  }

  final LocalTerminalProductionWiringBundle bundle;
  final LocalTerminalRealWiringBacklogEvidence backlogEvidence;
  final LocalTerminalVerificationEvidence verificationEvidence;
  late final LocalTerminalCompletionEvidenceReport report;
  late final LocalTerminalCompletionSummary summary;
  late final LocalTerminalCompletionDiagnosticsViewModel diagnosticsViewModel;
  late final LocalTerminalCompletionDiagnosticsActionGroup
  diagnosticsActionGroup;
  late final LocalTerminalCompletionMenuModel completionMenuModel;
  late final LocalTerminalCompletionCommandMenuAdapter commandMenuAdapter;

  bool get canCloseObjective {
    return report.canCloseObjective && verificationEvidence.canClose;
  }

  int get requiredBacklogBlockerCount {
    return report.requiredBacklogBlockerCount;
  }

  String toPlainText() {
    return summary.toPlainText();
  }

  Map<String, Object?> toJson() {
    return {
      'canCloseObjective': canCloseObjective,
      'requiredBacklogBlockerCount': requiredBacklogBlockerCount,
      'report': report.toJson(),
      'summary': summary.toJson(),
      'diagnostics': diagnosticsViewModel.toJson(),
      'menuModel': completionMenuModel.toJson(),
      'commandMenu': commandMenuAdapter.toJson(),
    };
  }
}
