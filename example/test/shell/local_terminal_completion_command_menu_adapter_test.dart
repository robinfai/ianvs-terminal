import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/local_terminal_completion_command_menu_adapter.dart';
import 'package:app/features/shell/local_terminal_completion_controller.dart';
import 'package:app/features/shell/local_terminal_completion_evidence_report.dart';
import 'package:app/features/shell/local_terminal_completion_diagnostics_actions.dart';
import 'package:app/features/shell/local_terminal_completion_diagnostics_view_model.dart';
import 'package:app/features/shell/local_terminal_completion_menu_model.dart';
import 'package:app/features/shell/local_terminal_current_completion_state.dart';
import 'package:app/features/shell/local_terminal_p0_boundary_closure_manifest.dart';
import 'package:app/features/shell/local_terminal_production_wiring_manifest_builder.dart';
import 'package:app/features/shell/local_terminal_verification_evidence.dart';

void main() {
  test('groups blocked completion diagnostics into command menu sections', () {
    final controller = LocalTerminalCompletionController.pending(
      capturedAt: DateTime.utc(2026, 5, 16),
    );

    final adapter = LocalTerminalCompletionCommandMenuAdapter.fromController(
      controller,
    );
    final sections = adapter.buildSections();

    expect(sections, isNotEmpty);
    expect(sections.any((section) => section.hasBlockedItems), isTrue);
    expect(
      sections.map((section) => section.title),
      contains('Blocked milestones'),
    );
    expect(adapter.toJson()['hasBlockedEntries'], isTrue);
  });

  test('keeps remaining blockers after P0 evidence is supplied', () {
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

    final sections = LocalTerminalCompletionCommandMenuAdapter.fromController(
      controller,
    ).buildSections();

    expect(
      sections
          .expand((section) => section.items)
          .any((item) => item.title.contains('p1ActionConfig')),
      isTrue,
    );
  });

  test('carries missing required backlog tasks into command menu sections', () {
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

    final sections = LocalTerminalCompletionCommandMenuAdapter(
      model: model,
    ).buildSections();

    final missingSection = sections.singleWhere(
      (section) => section.title == 'Missing real-wiring backlog',
    );
    expect(missingSection.hasBlockedItems, isTrue);
    expect(
      missingSection.items.map((item) => item.title),
      containsAll(['T-165', 'T-168']),
    );
    final missingVerificationSection = sections.singleWhere(
      (section) => section.title == 'Missing verification gates',
    );
    expect(missingVerificationSection.hasBlockedItems, isTrue);
    expect(
      missingVerificationSection.items.map((item) => item.title),
      contains(LocalTerminalVerificationGate.integrationTests.name),
    );
  });
}
