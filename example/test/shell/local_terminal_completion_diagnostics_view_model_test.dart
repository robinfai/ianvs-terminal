import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/local_terminal_completion_controller.dart';
import 'package:app/features/shell/local_terminal_completion_evidence_report.dart';
import 'package:app/features/shell/local_terminal_completion_diagnostics_view_model.dart';
import 'package:app/features/shell/local_terminal_current_completion_state.dart';
import 'package:app/features/shell/local_terminal_p0_boundary_closure_manifest.dart';
import 'package:app/features/shell/local_terminal_production_wiring_manifest_builder.dart';

void main() {
  test('builds blocked diagnostics from pending controller state', () {
    final controller = LocalTerminalCompletionController.pending(
      capturedAt: DateTime.utc(2026, 5, 16),
    );

    final viewModel =
        LocalTerminalCompletionDiagnosticsViewModel.fromController(controller);

    expect(viewModel.canCloseObjective, isFalse);
    expect(viewModel.status, LocalTerminalCompletionDiagnosticsStatus.blocked);
    expect(viewModel.title, contains('blocked'));
    expect(
      viewModel.sections.map((section) => section.title),
      containsAll(const [
        'Blocked milestones',
        'Blocked real-wiring backlog',
        'Blocked verification gates',
      ]),
    );
  });

  test('supplying P0 evidence still surfaces remaining blockers', () {
    final controller = LocalTerminalCompletionController.pending(
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

    final viewModel =
        LocalTerminalCompletionDiagnosticsViewModel.fromController(controller);

    expect(viewModel.canCloseObjective, isFalse);
    expect(
      viewModel.toJson()['status'],
      LocalTerminalCompletionDiagnosticsStatus.blocked.name,
    );
    expect(
      viewModel.sections
          .expand((section) => section.items)
          .any((item) => item.label.contains('p1ActionConfig')),
      isTrue,
    );
  });

  test('surfaces missing required real-wiring backlog tasks', () {
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

    final viewModel = LocalTerminalCompletionDiagnosticsViewModel.fromEvidence(
      report: report,
      verificationEvidence: state.verificationEvidence,
    );

    expect(viewModel.canCloseObjective, isFalse);
    expect(
      viewModel.sections.map((section) => section.title),
      contains('Missing real-wiring backlog'),
    );
    expect(
      viewModel.sections
          .expand((section) => section.items)
          .map((item) => item.label),
      containsAll(['T-165', 'T-168']),
    );
  });
}
