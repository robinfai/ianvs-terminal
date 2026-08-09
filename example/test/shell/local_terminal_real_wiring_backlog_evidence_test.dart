import 'package:app/features/layout/terminal_layout_production_callbacks.dart';
import 'package:app/features/policies/local_terminal_policy_production_callbacks.dart';
import 'package:app/features/productivity/shell_productivity_production_callbacks.dart';
import 'package:app/features/shell/local_terminal_completion_evidence_report.dart';
import 'package:app/features/shell/local_terminal_p0_boundary_closure_manifest.dart';
import 'package:app/features/shell/local_terminal_production_wiring_bundle.dart';
import 'package:app/features/shell/local_terminal_production_wiring_manifest_builder.dart';
import 'package:app/features/shell/local_terminal_real_wiring_backlog_evidence.dart';
import 'package:app/features/shell/local_terminal_verification_evidence.dart';
import 'package:app/features/shell/shell_action_production_action_set.dart';
import 'package:app/features/visual/local_terminal_visual_production_callbacks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults all real wiring backlog tasks to pending', () {
    const evidence = LocalTerminalRealWiringBacklogEvidence();

    final items = evidence.toBacklogItems();

    expect(items, hasLength(6));
    expect(items.map((item) => item.status).toSet(), {
      LocalTerminalCompletionBacklogStatus.pending,
    });
    expect(items.map((item) => item.taskId), contains('T-164'));
    expect(items.map((item) => item.taskId), contains('T-169'));
  });

  test('emits every required completion backlog task id', () {
    const defaultEvidence = LocalTerminalRealWiringBacklogEvidence();
    final currentEvidence =
        LocalTerminalRealWiringBacklogEvidence.currentImplementedUnverified(
          verificationEvidence:
              LocalTerminalVerificationEvidence.defaultRequiredPending(),
        );

    expect(
      defaultEvidence.toBacklogItems().map((item) => item.taskId).toSet(),
      LocalTerminalCompletionEvidenceReport.requiredBacklogTaskIds,
    );
    expect(
      currentEvidence.toBacklogItems().map((item) => item.taskId).toSet(),
      LocalTerminalCompletionEvidenceReport.requiredBacklogTaskIds,
    );
  });

  test('current implemented wiring is blocked on verification', () {
    const verificationEvidence = LocalTerminalVerificationEvidence(
      items: [
        LocalTerminalVerificationEvidenceItem(
          gate: LocalTerminalVerificationGate.unitTests,
          status: LocalTerminalVerificationStatus.pending,
          required: true,
        ),
      ],
    );
    final evidence =
        LocalTerminalRealWiringBacklogEvidence.currentImplementedUnverified(
          verificationEvidence: verificationEvidence,
        );

    final itemsByTaskId = {
      for (final item in evidence.toBacklogItems()) item.taskId: item,
    };

    expect(
      itemsByTaskId['T-164']!.status,
      LocalTerminalCompletionBacklogStatus.blocked,
    );
    expect(
      itemsByTaskId['T-165']!.status,
      LocalTerminalCompletionBacklogStatus.blocked,
    );
    expect(
      itemsByTaskId['T-166']!.status,
      LocalTerminalCompletionBacklogStatus.blocked,
    );
    expect(
      itemsByTaskId['T-167']!.status,
      LocalTerminalCompletionBacklogStatus.blocked,
    );
    expect(
      itemsByTaskId['T-168']!.status,
      LocalTerminalCompletionBacklogStatus.blocked,
    );
    expect(
      itemsByTaskId['T-169']!.status,
      LocalTerminalCompletionBacklogStatus.blocked,
    );
    expect(
      itemsByTaskId['T-164']!.blockers,
      contains('Verification gates have not been run.'),
    );
    expect(
      itemsByTaskId['T-169']!.blockers,
      contains('Verification gate unitTests is pending.'),
    );
    expect(
      itemsByTaskId['T-169']!.blockers,
      contains('Verification gate staticAnalysis is missing.'),
    );
  });

  test(
    'verified evidence can close the completion report with a ready bundle',
    () {
      final evidence = LocalTerminalRealWiringBacklogEvidence(
        shellActionWiring: _verified(
          LocalTerminalRealWiringTask.shellActionProductionWiring,
        ),
        layoutWiring: _verified(
          LocalTerminalRealWiringTask.localLayoutProductionWiring,
        ),
        productivityWiring: _verified(
          LocalTerminalRealWiringTask.shellProductivityProductionWiring,
        ),
        policyWiring: _verified(
          LocalTerminalRealWiringTask.localTerminalPolicyProductionWiring,
        ),
        visualWiring: _verified(
          LocalTerminalRealWiringTask.localTerminalVisualProductionWiring,
        ),
        verificationAndClosure: _verified(
          LocalTerminalRealWiringTask.localTerminalVerificationAndClosure,
        ),
      );

      final report = evidence.toCompletionReport(_readyBundle());

      expect(report.canCloseObjective, isTrue);
      expect(report.blockedBacklogItems, isEmpty);
    },
  );

  test('verification evidence controls the T-169 backlog item', () {
    const verificationEvidence = LocalTerminalVerificationEvidence(
      items: [
        LocalTerminalVerificationEvidenceItem(
          gate: LocalTerminalVerificationGate.unitTests,
          status: LocalTerminalVerificationStatus.passed,
          required: true,
        ),
        LocalTerminalVerificationEvidenceItem(
          gate: LocalTerminalVerificationGate.staticAnalysis,
          status: LocalTerminalVerificationStatus.pending,
          required: true,
        ),
      ],
    );

    final taskEvidence =
        LocalTerminalRealWiringTaskEvidence.fromVerificationEvidence(
          verificationEvidence,
        );

    expect(taskEvidence.task.taskId, 'T-169');
    expect(taskEvidence.status, LocalTerminalCompletionBacklogStatus.blocked);
    expect(
      taskEvidence.blockers,
      contains('Verification gate staticAnalysis is pending.'),
    );
    expect(
      taskEvidence.blockers,
      contains('Verification gate integrationTests is missing.'),
    );
  });
}

LocalTerminalRealWiringTaskEvidence _verified(
  LocalTerminalRealWiringTask task,
) {
  return LocalTerminalRealWiringTaskEvidence.verified(
    task: task,
    evidence: const ['verified in test fixture'],
  );
}

LocalTerminalProductionWiringBundle _readyBundle() {
  return LocalTerminalProductionWiringBundle.fromDomainCallbacks(
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
    actionSet: const ShellActionProductionActionSet(
      requiredActionNames: {
        'newTab',
        'searchScrollback',
        'paste',
        'applyTheme',
      },
    ),
    actionVerification: LocalTerminalMilestoneVerificationStatus.verified,
    layoutCallbacks: TerminalLayoutProductionCallbacks(
      newTab: (_) => const TerminalLayoutBindingResult.completed(),
    ),
    layoutRequiredOperations: const [TerminalLayoutProductionOperation.newTab],
    layoutVerification: LocalTerminalMilestoneVerificationStatus.verified,
    productivityCallbacks: ShellProductivityProductionCallbacks(
      searchScrollback: (_) => const ShellProductivityBindingResult.completed(),
    ),
    productivityRequiredOperations: const [
      ShellProductivityProductionOperation.searchScrollback,
    ],
    productivityVerification: LocalTerminalMilestoneVerificationStatus.verified,
    policyCallbacks: LocalTerminalPolicyProductionCallbacks(
      paste: (_) => const LocalTerminalPolicyBindingResult.completed(),
    ),
    policyRequiredOperations: const [
      LocalTerminalPolicyProductionOperation.paste,
    ],
    policyVerification: LocalTerminalMilestoneVerificationStatus.verified,
    visualCallbacks: LocalTerminalVisualProductionCallbacks(
      applyTheme: (_) => const LocalTerminalVisualBindingResult.completed(),
    ),
    visualRequiredOperations: const [
      LocalTerminalVisualProductionOperation.applyTheme,
    ],
    visualVerification: LocalTerminalMilestoneVerificationStatus.verified,
  );
}
