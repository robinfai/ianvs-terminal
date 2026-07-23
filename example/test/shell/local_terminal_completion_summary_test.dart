import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/local_terminal_completion_evidence_report.dart';
import 'package:app/features/shell/local_terminal_completion_summary.dart';
import 'package:app/features/shell/local_terminal_current_completion_state.dart';
import 'package:app/features/shell/local_terminal_p0_boundary_closure_manifest.dart';
import 'package:app/features/shell/local_terminal_production_wiring_manifest_builder.dart';

void main() {
  test('summarizes blocked current completion state', () {
    final state = LocalTerminalCurrentCompletionState.pending(
      capturedAt: DateTime.utc(2026, 5, 16),
    );

    final summary = LocalTerminalCompletionSummary.fromCurrentState(state);
    final text = summary.toPlainText();

    expect(summary.canCloseObjective, isFalse);
    expect(text, contains('Local terminal objective is blocked.'));
    expect(text, contains('Blocked milestones:'));
    expect(text, contains('Blocked real-wiring backlog items:'));
    expect(text, contains('Blocked verification gates:'));
  });

  test('keeps supplied P0 evidence but still reports remaining blockers', () {
    final state = LocalTerminalCurrentCompletionState.pending(
      capturedAt: DateTime.utc(2026, 5, 16),
      p0BoundaryManifest: const LocalTerminalP0BoundaryClosureManifest(
        localTerminalPlanDocumented: true,
        roadmapTerminalLayoutAligned: true,
        remoteScopeExcluded: true,
        perMilestoneExecutionPlansCreated: true,
        competitorCoverageMapped: true,
        productionWiringChecklistCreated: true,
      ),
      p0Verification: LocalTerminalMilestoneVerificationStatus.verified,
    );

    final summary = LocalTerminalCompletionSummary.fromCurrentState(state);

    expect(summary.canCloseObjective, isFalse);
    expect(
      summary.lines.any((line) => line.contains('p1ActionConfig')),
      isTrue,
    );
  });

  test('summarizes missing required real-wiring backlog tasks', () {
    final state = LocalTerminalCurrentCompletionState.pending(
      capturedAt: DateTime.utc(2026, 5, 16),
    );
    final report = LocalTerminalCompletionEvidenceReport(
      bundle: state.bundle,
      backlogItems: const [
        LocalTerminalCompletionBacklogItem(
          taskId: 'T-164',
          title: 'Shell action production wiring',
          status: LocalTerminalCompletionBacklogStatus.verified,
        ),
        LocalTerminalCompletionBacklogItem(
          taskId: 'T-169',
          title: 'Verification and closure',
          status: LocalTerminalCompletionBacklogStatus.verified,
        ),
      ],
    );

    final summary = LocalTerminalCompletionSummary.fromEvidence(
      report: report,
      verificationEvidence: state.verificationEvidence,
    );
    final text = summary.toPlainText();

    expect(summary.canCloseObjective, isFalse);
    expect(text, contains('Missing real-wiring backlog items:'));
    expect(text, contains('T-165'));
    expect(text, contains('T-168'));
  });
}
