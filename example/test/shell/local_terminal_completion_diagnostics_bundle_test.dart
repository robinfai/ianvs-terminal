import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/local_terminal_completion_controller.dart';
import 'package:app/features/shell/local_terminal_completion_diagnostics_bundle.dart';
import 'package:app/features/shell/local_terminal_completion_evidence_report.dart';
import 'package:app/features/shell/local_terminal_current_completion_state.dart';
import 'package:app/features/shell/local_terminal_p0_boundary_closure_manifest.dart';
import 'package:app/features/shell/local_terminal_production_wiring_manifest_builder.dart';
import 'package:app/features/shell/local_terminal_verification_evidence.dart';

void main() {
  test('bundles pending completion diagnostics from one controller', () {
    final bundle = LocalTerminalCompletionDiagnosticsBundle(
      controller: LocalTerminalCompletionController.pending(
        capturedAt: DateTime.utc(2026, 5, 16),
      ),
    );

    expect(bundle.canCloseObjective, isFalse);
    expect(bundle.hasBlockedMenuEntries, isTrue);
    expect(bundle.toPlainText(), contains('blocked'));
    expect(bundle.toJson()['canCloseObjective'], isFalse);
  });

  test('keeps remaining blockers visible when P0 evidence is supplied', () {
    final bundle = LocalTerminalCompletionDiagnosticsBundle(
      controller: LocalTerminalCompletionController.pending(
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
      ),
    );

    expect(bundle.canCloseObjective, isFalse);
    expect(bundle.toPlainText(), contains('p1ActionConfig'));
    expect(bundle.commandMenuAdapter.buildSections(), isNotEmpty);
  });

  test('carries missing required backlog through bundle outputs', () {
    final bundle = LocalTerminalCompletionDiagnosticsBundle(
      controller: _controllerWithMissingRequiredBacklog(),
    );
    final sections = bundle.commandMenuAdapter.buildSections();

    expect(bundle.canCloseObjective, isFalse);
    expect(
      bundle.toPlainText(),
      contains('Missing real-wiring backlog items:'),
    );
    expect(bundle.toPlainText(), contains('T-165'));
    expect(
      sections.any((section) => section.title == 'Missing real-wiring backlog'),
      isTrue,
    );
    expect(bundle.toJson()['canCloseObjective'], isFalse);
  });

  test('carries missing verification gates through bundle outputs', () {
    final bundle = LocalTerminalCompletionDiagnosticsBundle(
      controller: _controllerWithMissingVerificationEvidence(),
    );
    final sections = bundle.commandMenuAdapter.buildSections();

    expect(bundle.canCloseObjective, isFalse);
    expect(bundle.toPlainText(), contains('Missing verification gates:'));
    expect(
      bundle.toPlainText(),
      contains(LocalTerminalVerificationGate.integrationTests.name),
    );
    expect(
      sections.any((section) => section.title == 'Missing verification gates'),
      isTrue,
    );
    expect(bundle.toJson()['canCloseObjective'], isFalse);
  });
}

LocalTerminalCompletionController _controllerWithMissingRequiredBacklog() {
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

  return LocalTerminalCompletionController(
    currentState: LocalTerminalCurrentCompletionState(
      bundle: state.bundle,
      verificationEvidence: state.verificationEvidence,
      backlogEvidence: state.backlogEvidence,
      report: report,
    ),
  );
}

LocalTerminalCompletionController _controllerWithMissingVerificationEvidence() {
  final state = LocalTerminalCurrentCompletionState.pending(
    capturedAt: DateTime.utc(2026, 5, 16),
  );

  return LocalTerminalCompletionController(
    currentState: LocalTerminalCurrentCompletionState(
      bundle: state.bundle,
      verificationEvidence: const LocalTerminalVerificationEvidence(items: []),
      backlogEvidence: state.backlogEvidence,
      report: state.report,
    ),
  );
}
