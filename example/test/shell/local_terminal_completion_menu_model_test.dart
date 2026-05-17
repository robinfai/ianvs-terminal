import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/local_terminal_completion_controller.dart';
import 'package:app/features/shell/local_terminal_completion_evidence_report.dart';
import 'package:app/features/shell/local_terminal_completion_diagnostics_actions.dart';
import 'package:app/features/shell/local_terminal_completion_diagnostics_view_model.dart';
import 'package:app/features/shell/local_terminal_current_completion_state.dart';
import 'package:app/features/shell/local_terminal_completion_menu_model.dart';
import 'package:app/features/shell/local_terminal_p0_boundary_closure_manifest.dart';
import 'package:app/features/shell/local_terminal_production_wiring_manifest_builder.dart';
import 'package:app/features/shell/local_terminal_verification_evidence.dart';

void main() {
  test('builds menu entries from blocked completion controller state', () {
    final controller = LocalTerminalCompletionController.pending(
      capturedAt: DateTime.utc(2026, 5, 16),
    );

    final model = LocalTerminalCompletionMenuModel.fromController(controller);

    expect(model.title, contains('blocked'));
    expect(model.entries, isNotEmpty);
    expect(model.hasBlockedEntries, isTrue);
    expect(model.entries.every((entry) => !entry.enabled), isTrue);
    expect(model.entries.map((entry) => entry.severity).toSet(), {
      LocalTerminalCompletionDiagnosticsSeverity.blocker,
    });
  });

  test('keeps remaining blockers visible when P0 evidence is supplied', () {
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

    final model = LocalTerminalCompletionMenuModel.fromController(controller);

    expect(model.hasBlockedEntries, isTrue);
    expect(
      model.entries.any((entry) => entry.label.contains('p1ActionConfig')),
      isTrue,
    );
  });

  test('carries missing required backlog tasks into menu entries', () {
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

    final model = LocalTerminalCompletionMenuModel.fromActionGroup(group);

    expect(model.hasBlockedEntries, isTrue);
    expect(
      model.entries
          .where((entry) => entry.sectionTitle == 'Missing real-wiring backlog')
          .map((entry) => entry.label),
      containsAll(['T-165', 'T-168']),
    );
    expect(
      model.entries
          .where((entry) => entry.sectionTitle == 'Missing verification gates')
          .map((entry) => entry.label),
      contains(LocalTerminalVerificationGate.integrationTests.name),
    );
  });
}
