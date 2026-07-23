import '../policies/local_terminal_policy_production_callbacks.dart';
import '../productivity/shell_productivity_production_callbacks.dart';
import '../visual/local_terminal_visual_production_callbacks.dart';
import '../layout/terminal_layout_production_callbacks.dart';
import 'local_terminal_completion_evidence_report.dart';
import 'local_terminal_p0_boundary_closure_manifest.dart';
import 'local_terminal_production_wiring_bundle.dart';
import 'local_terminal_production_wiring_manifest_builder.dart';
import 'local_terminal_real_wiring_backlog_evidence.dart';
import 'local_terminal_verification_evidence.dart';
import 'shell_action_production_action_set.dart';

class LocalTerminalCurrentCompletionState {
  const LocalTerminalCurrentCompletionState({
    required this.bundle,
    required this.verificationEvidence,
    required this.backlogEvidence,
    required this.report,
  });

  factory LocalTerminalCurrentCompletionState.pending({
    required DateTime capturedAt,
    LocalTerminalP0BoundaryClosureManifest p0BoundaryManifest =
        const LocalTerminalP0BoundaryClosureManifest(
          localTerminalPlanDocumented: false,
          roadmapTerminalLayoutAligned: false,
          remoteScopeExcluded: false,
          perMilestoneExecutionPlansCreated: false,
          competitorCoverageMapped: false,
          productionWiringChecklistCreated: false,
        ),
    LocalTerminalMilestoneVerificationStatus p0Verification =
        LocalTerminalMilestoneVerificationStatus.notVerified,
    LocalTerminalVerificationEvidence? verificationEvidence,
  }) {
    final verification =
        verificationEvidence ??
        LocalTerminalVerificationEvidence.defaultRequiredPending();
    final bundle = LocalTerminalProductionWiringBundle.fromDomainCallbacks(
      capturedAt: capturedAt,
      p0BoundaryManifest: p0BoundaryManifest,
      p0Verification: p0Verification,
    );
    final backlogEvidence =
        LocalTerminalRealWiringBacklogEvidence.currentImplementedUnverified(
          verificationEvidence: verification,
        );

    return LocalTerminalCurrentCompletionState(
      bundle: bundle,
      verificationEvidence: verification,
      backlogEvidence: backlogEvidence,
      report: backlogEvidence.toCompletionReport(bundle),
    );
  }

  factory LocalTerminalCurrentCompletionState.verified({
    required DateTime capturedAt,
    required LocalTerminalVerificationEvidence verificationEvidence,
  }) {
    final bundle = LocalTerminalProductionWiringBundle.fromDomainCallbacks(
      capturedAt: capturedAt,
      p0BoundaryManifest: const LocalTerminalP0BoundaryClosureManifest(
        localTerminalPlanDocumented: true,
        roadmapTerminalLayoutAligned: true,
        remoteScopeExcluded: true,
        perMilestoneExecutionPlansCreated: true,
        competitorCoverageMapped: true,
        productionWiringChecklistCreated: true,
      ),
      p0Verification: LocalTerminalMilestoneVerificationStatus.verified,
      actionSet: const ShellActionProductionActionSet(
        requiredActionNames: {
          'newTab',
          'searchScrollback',
          'paste',
          'applyTheme',
        },
      ),
      actionVerification: LocalTerminalMilestoneVerificationStatus.verified,
      layoutCallbacks: TerminalLayoutProductionCallbacks(
        newTab: (_) => const TerminalLayoutBindingResult.completed(),
      ),
      layoutRequiredOperations: const [
        TerminalLayoutProductionOperation.newTab,
      ],
      layoutVerification: LocalTerminalMilestoneVerificationStatus.verified,
      productivityCallbacks: ShellProductivityProductionCallbacks(
        searchScrollback: (_) =>
            const ShellProductivityBindingResult.completed(),
      ),
      productivityRequiredOperations: const [
        ShellProductivityProductionOperation.searchScrollback,
      ],
      productivityVerification:
          LocalTerminalMilestoneVerificationStatus.verified,
      policyCallbacks: LocalTerminalPolicyProductionCallbacks(
        paste: (_) => const LocalTerminalPolicyBindingResult.completed(),
      ),
      policyRequiredOperations: const [
        LocalTerminalPolicyProductionOperation.paste,
      ],
      policyVerification: LocalTerminalMilestoneVerificationStatus.verified,
      visualCallbacks: LocalTerminalVisualProductionCallbacks(
        applyTheme: (_) => const LocalTerminalVisualBindingResult.completed(),
      ),
      visualRequiredOperations: const [
        LocalTerminalVisualProductionOperation.applyTheme,
      ],
      visualVerification: LocalTerminalMilestoneVerificationStatus.verified,
    );
    final backlogEvidence =
        LocalTerminalRealWiringBacklogEvidence.currentVerified(
          verificationEvidence: verificationEvidence,
        );

    return LocalTerminalCurrentCompletionState(
      bundle: bundle,
      verificationEvidence: verificationEvidence,
      backlogEvidence: backlogEvidence,
      report: backlogEvidence.toCompletionReport(bundle),
    );
  }

  final LocalTerminalProductionWiringBundle bundle;
  final LocalTerminalVerificationEvidence verificationEvidence;
  final LocalTerminalRealWiringBacklogEvidence backlogEvidence;
  final LocalTerminalCompletionEvidenceReport report;

  bool get canCloseObjective {
    return report.canCloseObjective && verificationEvidence.canClose;
  }

  Map<String, Object?> toJson() {
    return {
      'canCloseObjective': canCloseObjective,
      'verificationEvidence': verificationEvidence.toJson(),
      'completionReport': report.toJson(),
    };
  }
}
