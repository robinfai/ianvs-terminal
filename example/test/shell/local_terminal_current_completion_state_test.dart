import 'package:app/features/shell/local_terminal_completion_evidence_report.dart';
import 'package:app/features/shell/local_terminal_current_completion_state.dart';
import 'package:app/features/shell/local_terminal_p0_boundary_closure_manifest.dart';
import 'package:app/features/shell/local_terminal_production_wiring_manifest_builder.dart';
import 'package:app/features/shell/local_terminal_verification_plan_records.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pending state is blocked by default', () {
    final state = LocalTerminalCurrentCompletionState.pending(
      capturedAt: DateTime.utc(2026, 5, 16),
    );

    expect(state.canCloseObjective, isFalse);
    expect(state.report.blockedMilestones, isNotEmpty);
    expect(state.report.blockedBacklogItems, isNotEmpty);
    expect(state.toJson()['canCloseObjective'], isFalse);
  });

  test('pending state can include explicit P0 boundary evidence', () {
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

    expect(state.bundle.manifest.blockedMilestones, isNotEmpty);
    expect(state.canCloseObjective, isFalse);
  });

  test('pending state reports current wiring as implemented but unverified', () {
    final state = LocalTerminalCurrentCompletionState.pending(
      capturedAt: DateTime.utc(2026, 5, 16),
    );

    final backlogByTaskId = {
      for (final item in state.backlogEvidence.toBacklogItems())
        item.taskId: item,
    };

    expect(
      backlogByTaskId['T-164']!.status,
      LocalTerminalCompletionBacklogStatus.blocked,
    );
    expect(
      backlogByTaskId['T-165']!.status,
      LocalTerminalCompletionBacklogStatus.blocked,
    );
    expect(
      backlogByTaskId['T-166']!.status,
      LocalTerminalCompletionBacklogStatus.blocked,
    );
    expect(
      backlogByTaskId['T-167']!.status,
      LocalTerminalCompletionBacklogStatus.blocked,
    );
    expect(
      backlogByTaskId['T-168']!.status,
      LocalTerminalCompletionBacklogStatus.blocked,
    );
    expect(
      backlogByTaskId['T-169']!.status,
      LocalTerminalCompletionBacklogStatus.blocked,
    );
    expect(
      backlogByTaskId['T-164']!.evidence,
      contains(
        'ShellScreen command menu and shortcut dispatch use production action runtime for the current P1 action baseline.',
      ),
    );
    expect(backlogByTaskId['T-169']!.blockers, isNotEmpty);
    expect(state.canCloseObjective, isFalse);
  });

  test(
    'verified state closes the current objective with latest passed records',
    () {
      final verificationEvidence =
          LocalTerminalVerificationPlanRecords.latestPassed()
              .toRecorder()
              .evidence;
      final state = LocalTerminalCurrentCompletionState.verified(
        capturedAt: DateTime.utc(2026, 5, 16),
        verificationEvidence: verificationEvidence,
      );

      expect(verificationEvidence.canClose, isTrue);
      expect(state.canCloseObjective, isTrue);
      expect(state.report.canCloseObjective, isTrue);
      expect(state.report.blockedMilestones, isEmpty);
      expect(state.report.blockedBacklogItems, isEmpty);
      expect(state.report.requiredBacklogBlockerCount, 0);
      expect(state.report.productionMilestoneBlockerCount, 0);
      expect(state.toJson()['canCloseObjective'], isTrue);
    },
  );
}
