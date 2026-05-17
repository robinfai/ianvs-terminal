import 'local_terminal_completion_summary.dart';
import 'local_terminal_current_completion_state.dart';
import 'local_terminal_p0_boundary_closure_manifest.dart';
import 'local_terminal_production_wiring_manifest_builder.dart';
import 'local_terminal_verification_evidence.dart';

class LocalTerminalCompletionController {
  const LocalTerminalCompletionController({required this.currentState});

  factory LocalTerminalCompletionController.pending({
    required DateTime capturedAt,
    LocalTerminalP0BoundaryClosureManifest p0BoundaryManifest =
        const LocalTerminalP0BoundaryClosureManifest(
          localTerminalPlanDocumented: false,
          roadmapLocalWorkspaceAligned: false,
          remoteScopeExcluded: false,
          perMilestoneExecutionPlansCreated: false,
          competitorCoverageMapped: false,
          productionWiringChecklistCreated: false,
        ),
    LocalTerminalMilestoneVerificationStatus p0Verification =
        LocalTerminalMilestoneVerificationStatus.notVerified,
    LocalTerminalVerificationEvidence? verificationEvidence,
  }) {
    return LocalTerminalCompletionController(
      currentState: LocalTerminalCurrentCompletionState.pending(
        capturedAt: capturedAt,
        p0BoundaryManifest: p0BoundaryManifest,
        p0Verification: p0Verification,
        verificationEvidence: verificationEvidence,
      ),
    );
  }

  factory LocalTerminalCompletionController.verified({
    required DateTime capturedAt,
    required LocalTerminalVerificationEvidence verificationEvidence,
  }) {
    return LocalTerminalCompletionController(
      currentState: LocalTerminalCurrentCompletionState.verified(
        capturedAt: capturedAt,
        verificationEvidence: verificationEvidence,
      ),
    );
  }

  final LocalTerminalCurrentCompletionState currentState;

  bool get canCloseObjective => currentState.canCloseObjective;

  LocalTerminalCompletionSummary get summary {
    return LocalTerminalCompletionSummary.fromCurrentState(currentState);
  }

  List<String> get summaryLines => summary.lines;

  String toPlainText() {
    return summary.toPlainText();
  }

  Map<String, Object?> toJson() {
    return {
      'canCloseObjective': canCloseObjective,
      'summary': summary.toJson(),
      'state': currentState.toJson(),
    };
  }
}
