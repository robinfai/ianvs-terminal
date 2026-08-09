import 'package:app/features/layout/terminal_layout_production_callbacks.dart';
import 'package:app/features/policies/local_terminal_policy_production_callbacks.dart';
import 'package:app/features/productivity/shell_productivity_production_callbacks.dart';
import 'package:app/features/shell/local_terminal_completion_evidence_report.dart';
import 'package:app/features/shell/local_terminal_p0_boundary_closure_manifest.dart';
import 'package:app/features/shell/local_terminal_production_wiring_bundle.dart';
import 'package:app/features/shell/local_terminal_production_wiring_manifest_builder.dart';
import 'package:app/features/shell/shell_action_production_action_set.dart';
import 'package:app/features/visual/local_terminal_visual_production_callbacks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('can close objective only with clean manifest and verified backlog', () {
    final report = LocalTerminalCompletionEvidenceReport(
      bundle: _readyBundle(),
      backlogItems: const [
        LocalTerminalCompletionBacklogItem(
          taskId: 'T-164',
          title: 'Shell action production wiring',
          status: LocalTerminalCompletionBacklogStatus.verified,
        ),
        LocalTerminalCompletionBacklogItem(
          taskId: 'T-165',
          title: 'Local layout production wiring',
          status: LocalTerminalCompletionBacklogStatus.verified,
        ),
        LocalTerminalCompletionBacklogItem(
          taskId: 'T-166',
          title: 'Shell productivity production wiring',
          status: LocalTerminalCompletionBacklogStatus.verified,
        ),
        LocalTerminalCompletionBacklogItem(
          taskId: 'T-167',
          title: 'Local terminal policy production wiring',
          status: LocalTerminalCompletionBacklogStatus.verified,
        ),
        LocalTerminalCompletionBacklogItem(
          taskId: 'T-168',
          title: 'Local terminal visual production wiring',
          status: LocalTerminalCompletionBacklogStatus.verified,
        ),
        LocalTerminalCompletionBacklogItem(
          taskId: 'T-169',
          title: 'Verification and closure',
          status: LocalTerminalCompletionBacklogStatus.verified,
        ),
      ],
    );

    expect(report.canCloseObjective, isTrue);
    expect(report.blockedBacklogItems, isEmpty);
    expect(report.missingRequiredProductionMilestones, isEmpty);
    expect(report.productionMilestoneBlockerCount, 0);
    expect(report.requiredBacklogBlockerCount, 0);
    expect(report.missingRequiredBacklogTaskIds, isEmpty);
    expect(report.toJson()['canCloseObjective'], isTrue);
    expect(report.toJson()['missingRequiredProductionMilestones'], isEmpty);
    expect(report.toJson()['productionMilestoneBlockerCount'], 0);
  });

  test('does not close when required backlog tasks are missing', () {
    final report = LocalTerminalCompletionEvidenceReport(
      bundle: _readyBundle(),
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

    expect(report.canCloseObjective, isFalse);
    expect(report.blockedBacklogItems, isEmpty);
    expect(report.requiredBacklogBlockerCount, 4);
    expect(
      report.missingRequiredBacklogTaskIds,
      containsAll({'T-165', 'T-166', 'T-167', 'T-168'}),
    );
    expect(report.toJson()['requiredBacklogBlockerCount'], 4);
    expect(
      report.toJson()['missingRequiredBacklogTaskIds'],
      containsAll(['T-165', 'T-166', 'T-167', 'T-168']),
    );
  });

  test('keeps pending backlog items as objective blockers', () {
    final report = LocalTerminalCompletionEvidenceReport(
      bundle: _readyBundle(),
      backlogItems: const [
        LocalTerminalCompletionBacklogItem(
          taskId: 'T-164',
          title: 'Shell action production wiring',
          status: LocalTerminalCompletionBacklogStatus.pending,
          blockers: ['Production callbacks are not populated.'],
        ),
      ],
    );

    expect(report.canCloseObjective, isFalse);
    expect(report.blockedBacklogItems.single.taskId, 'T-164');
    expect(report.requiredBacklogBlockerCount, 6);
    expect(report.toJson()['blockedBacklogItems'], ['T-164']);
  });
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
