import 'package:app/features/shell/local_terminal_completion_controller.dart';
import 'package:app/features/shell/local_terminal_p0_boundary_closure_manifest.dart';
import 'package:app/features/shell/local_terminal_production_wiring_manifest_builder.dart';
import 'package:app/features/shell/local_terminal_verification_plan_records.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pending controller exposes blocked completion state', () {
    final controller = LocalTerminalCompletionController.pending(
      capturedAt: DateTime.utc(2026, 5, 16),
    );

    expect(controller.canCloseObjective, isFalse);
    expect(controller.summaryLines, isNotEmpty);
    expect(
      controller.toPlainText(),
      contains('Local terminal objective is blocked.'),
    );
    expect(controller.toJson()['canCloseObjective'], isFalse);
  });

  test('explicit P0 evidence does not close remaining production blockers', () {
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

    expect(controller.canCloseObjective, isFalse);
    expect(controller.toPlainText(), contains('p1ActionConfig'));
  });

  test('verified controller closes with latest passed records', () {
    final controller = LocalTerminalCompletionController.verified(
      capturedAt: DateTime.utc(2026, 5, 16),
      verificationEvidence: LocalTerminalVerificationPlanRecords.latestPassed()
          .toRecorder()
          .evidence,
    );

    expect(controller.canCloseObjective, isTrue);
    expect(
      controller.toPlainText(),
      contains('Local terminal objective can close.'),
    );
    expect(controller.toJson()['canCloseObjective'], isTrue);
  });
}
