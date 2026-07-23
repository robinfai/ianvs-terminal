import 'local_terminal_current_completion_state.dart';
import 'local_terminal_p0_boundary_closure_manifest.dart';
import 'local_terminal_production_wiring_manifest_builder.dart';
import 'local_terminal_shell_ui_wiring_facade.dart';
import 'local_terminal_shell_ui_wiring_snapshot.dart';
import 'local_terminal_verification_plan_records.dart';

class LocalTerminalPendingCompletionSnapshotFactory {
  const LocalTerminalPendingCompletionSnapshotFactory({
    this.p0BoundaryManifest = const LocalTerminalP0BoundaryClosureManifest(
      localTerminalPlanDocumented: false,
      roadmapTerminalLayoutAligned: false,
      remoteScopeExcluded: false,
      perMilestoneExecutionPlansCreated: false,
      competitorCoverageMapped: false,
      productionWiringChecklistCreated: false,
    ),
    this.p0Verification = LocalTerminalMilestoneVerificationStatus.notVerified,
    this.verificationPlanRecords,
  });

  final LocalTerminalP0BoundaryClosureManifest p0BoundaryManifest;
  final LocalTerminalMilestoneVerificationStatus p0Verification;
  final LocalTerminalVerificationPlanRecords? verificationPlanRecords;

  LocalTerminalShellUiWiringSnapshot build({required DateTime capturedAt}) {
    final verificationEvidence =
        (verificationPlanRecords ??
                LocalTerminalVerificationPlanRecords.defaultPending())
            .toRecorder()
            .evidence;
    final state = LocalTerminalCurrentCompletionState.pending(
      capturedAt: capturedAt,
      p0BoundaryManifest: p0BoundaryManifest,
      p0Verification: p0Verification,
      verificationEvidence: verificationEvidence,
    );

    return LocalTerminalShellUiWiringSnapshot(
      capturedAt: capturedAt,
      facade: LocalTerminalShellUiWiringFacade(
        bundle: state.bundle,
        backlogEvidence: state.backlogEvidence,
        verificationEvidence: state.verificationEvidence,
      ),
    );
  }
}
