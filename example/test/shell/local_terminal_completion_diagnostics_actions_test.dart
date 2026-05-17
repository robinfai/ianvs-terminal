import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/local_terminal_completion_controller.dart';
import 'package:app/features/shell/local_terminal_completion_evidence_report.dart';
import 'package:app/features/shell/local_terminal_completion_diagnostics_actions.dart';
import 'package:app/features/shell/local_terminal_completion_diagnostics_view_model.dart';
import 'package:app/features/shell/local_terminal_current_completion_state.dart';
import 'package:app/features/shell/local_terminal_p0_boundary_closure_manifest.dart';
import 'package:app/features/shell/local_terminal_production_wiring_manifest_builder.dart';
import 'package:app/features/shell/local_terminal_verification_evidence.dart';

void main() {
  test(
    'builds disabled diagnostic action items from blocked controller state',
    () {
      final controller = LocalTerminalCompletionController.pending(
        capturedAt: DateTime.utc(2026, 5, 16),
      );

      final group =
          LocalTerminalCompletionDiagnosticsActionGroup.fromController(
            controller,
          );

      expect(group.canCloseObjective, isFalse);
      expect(group.hasBlockingItems, isTrue);
      expect(group.items, isNotEmpty);
      expect(group.items.every((item) => !item.enabled), isTrue);
      expect(group.items.map((item) => item.severity).toSet(), {
        LocalTerminalCompletionDiagnosticsSeverity.blocker,
      });
    },
  );

  test('keeps P1 blocker visible when P0 evidence is supplied', () {
    final controller = LocalTerminalCompletionController.pending(
      capturedAt: DateTime.utc(2026, 5, 16),
      p0BoundaryManifest: const LocalTerminalP0BoundaryClosureManifest(
        localTerminalPlanDocumented: true,
        roadmapLocalWorkspaceAligned: true,
        remoteScopeExcluded: true,
        perMilestoneExecutionPlansCreated: true,
        competitorCoverageMapped: true,
        productionWiringChecklistCreated: true,
      ),
      p0Verification: LocalTerminalMilestoneVerificationStatus.verified,
    );

    final group = LocalTerminalCompletionDiagnosticsActionGroup.fromController(
      controller,
    );

    expect(group.canCloseObjective, isFalse);
    expect(
      group.items.any((item) => item.title.contains('p1ActionConfig')),
      isTrue,
    );
  });

  test('carries missing required backlog tasks into action items', () {
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
      verificationEvidence: const LocalTerminalVerificationEvidence(items: []),
    );

    final group = LocalTerminalCompletionDiagnosticsActionGroup.fromViewModel(
      viewModel,
    );

    expect(group.canCloseObjective, isFalse);
    expect(
      group.items
          .where((item) => item.sectionTitle == 'Missing real-wiring backlog')
          .map((item) => item.title),
      containsAll(['T-165', 'T-168']),
    );
    expect(
      group.items
          .where((item) => item.sectionTitle == 'Missing verification gates')
          .map((item) => item.title),
      contains(LocalTerminalVerificationGate.integrationTests.name),
    );
  });
}
