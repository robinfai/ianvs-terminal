import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/policies/local_terminal_policy_production_callbacks.dart';
import 'package:app/features/productivity/shell_productivity_production_callbacks.dart';
import 'package:app/features/shell/local_terminal_domain_wiring_summary.dart';
import 'package:app/features/shell/local_terminal_p0_boundary_closure_manifest.dart';
import 'package:app/features/shell/local_terminal_production_wiring_manifest.dart';
import 'package:app/features/shell/local_terminal_production_wiring_manifest_builder.dart';
import 'package:app/features/shell/shell_action_production_action_set.dart';
import 'package:app/features/shell/shell_action_production_audit_snapshot.dart';
import 'package:app/features/shell/shell_action_production_callbacks.dart';
import 'package:app/features/shell/shell_action_production_closure_manifest.dart';
import 'package:app/features/shell/shell_action_production_wiring_report.dart';
import 'package:app/features/shell/shell_action_production_wiring_state.dart';
import 'package:app/features/shell/shell_action_runtime_bindings.dart';
import 'package:app/features/visual/local_terminal_visual_production_callbacks.dart';
import 'package:app/features/layout/terminal_layout_production_callbacks.dart';

void main() {
  test('keeps missing domain summaries as blockers', () {
    final manifest = LocalTerminalProductionWiringManifestBuilder(
      capturedAt: DateTime.utc(2026, 5, 16),
      actionClosureManifest: _readyActionClosureManifest(),
      p0BoundaryManifest: _readyP0BoundaryManifest(),
      p0Verification: LocalTerminalMilestoneVerificationStatus.verified,
    ).build();

    expect(manifest.canCloseAll, isFalse);
    expect(
      manifest.blockedMilestones.map((entry) => entry.milestone),
      contains(LocalTerminalProductionMilestone.p2Layout),
    );
    expect(
      manifest
          .milestoneFor(LocalTerminalProductionMilestone.p2Layout)
          ?.effectiveBlockers,
      contains('Production wiring summary is missing.'),
    );
  });

  test('builds closeable manifest when all domains are ready and verified', () {
    final layoutSummary = LocalTerminalDomainWiringSummary.fromLayout(
      TerminalLayoutProductionWiring(
        requiredOperations: const [TerminalLayoutProductionOperation.newTab],
        callbacks: TerminalLayoutProductionCallbacks(
          newTab: (_) => const TerminalLayoutBindingResult.completed(),
        ),
      ),
    );
    final productivitySummary =
        LocalTerminalDomainWiringSummary.fromProductivity(
          ShellProductivityProductionWiring(
            requiredOperations: const [
              ShellProductivityProductionOperation.searchScrollback,
            ],
            callbacks: ShellProductivityProductionCallbacks(
              searchScrollback: (_) =>
                  const ShellProductivityBindingResult.completed(),
            ),
          ),
        );
    final readySummary = LocalTerminalDomainWiringSummary(
      milestone: LocalTerminalProductionMilestone.p4Policy,
      ready: true,
      registeredOperationNames: const ['paste'],
      missingOperationNames: const [],
    );
    final visualSummary = LocalTerminalDomainWiringSummary(
      milestone: LocalTerminalProductionMilestone.p5Visual,
      ready: true,
      registeredOperationNames: const ['applyTheme'],
      missingOperationNames: const [],
    );

    final manifest = LocalTerminalProductionWiringManifestBuilder(
      capturedAt: DateTime.utc(2026, 5, 16),
      actionClosureManifest: _readyActionClosureManifest(),
      p0BoundaryManifest: _readyP0BoundaryManifest(),
      p0Verification: LocalTerminalMilestoneVerificationStatus.verified,
      layoutSummary: layoutSummary,
      layoutVerification: LocalTerminalMilestoneVerificationStatus.verified,
      productivitySummary: productivitySummary,
      productivityVerification:
          LocalTerminalMilestoneVerificationStatus.verified,
      policySummary: readySummary,
      policyVerification: LocalTerminalMilestoneVerificationStatus.verified,
      visualSummary: visualSummary,
      visualVerification: LocalTerminalMilestoneVerificationStatus.verified,
    ).build();

    expect(manifest.canCloseAll, isTrue);
    expect(manifest.blockedMilestones, isEmpty);
  });

  test('builds closeable manifest from current P2-P5 core summaries', () {
    final manifest = LocalTerminalProductionWiringManifestBuilder(
      capturedAt: DateTime.utc(2026, 5, 16),
      actionClosureManifest: _readyActionClosureManifest(),
      p0BoundaryManifest: _readyP0BoundaryManifest(),
      p0Verification: LocalTerminalMilestoneVerificationStatus.verified,
      layoutSummary: _coreLayoutSummary(),
      layoutVerification: LocalTerminalMilestoneVerificationStatus.verified,
      productivitySummary: _coreProductivitySummary(),
      productivityVerification:
          LocalTerminalMilestoneVerificationStatus.verified,
      policySummary: _corePolicySummary(),
      policyVerification: LocalTerminalMilestoneVerificationStatus.verified,
      visualSummary: _coreVisualSummary(),
      visualVerification: LocalTerminalMilestoneVerificationStatus.verified,
    ).build();

    expect(manifest.canCloseAll, isTrue);
    expect(manifest.blockedMilestones, isEmpty);
    expect(
      manifest
          .milestoneFor(LocalTerminalProductionMilestone.p2Layout)
          ?.canClose,
      isTrue,
    );
    expect(
      manifest
          .milestoneFor(LocalTerminalProductionMilestone.p5Visual)
          ?.canClose,
      isTrue,
    );
  });

  test('keeps verification blockers for ready core summaries', () {
    final manifest = LocalTerminalProductionWiringManifestBuilder(
      capturedAt: DateTime.utc(2026, 5, 16),
      actionClosureManifest: _readyActionClosureManifest(),
      p0BoundaryManifest: _readyP0BoundaryManifest(),
      p0Verification: LocalTerminalMilestoneVerificationStatus.verified,
      layoutSummary: _coreLayoutSummary(),
      productivitySummary: _coreProductivitySummary(),
      policySummary: _corePolicySummary(),
      visualSummary: _coreVisualSummary(),
    ).build();

    final workspaceManifest = manifest.milestoneFor(
      LocalTerminalProductionMilestone.p2Layout,
    );

    expect(manifest.canCloseAll, isFalse);
    expect(workspaceManifest?.wiringReady, isTrue);
    expect(workspaceManifest?.testsPassed, isFalse);
    expect(
      workspaceManifest?.effectiveBlockers,
      contains('Required tests have not passed.'),
    );
    expect(
      workspaceManifest?.effectiveBlockers,
      contains('Static analysis has not passed.'),
    );
  });
}

LocalTerminalP0BoundaryClosureManifest _readyP0BoundaryManifest() {
  return const LocalTerminalP0BoundaryClosureManifest(
    localTerminalPlanDocumented: true,
    roadmapTerminalLayoutAligned: true,
    remoteScopeExcluded: true,
    perMilestoneExecutionPlansCreated: true,
    competitorCoverageMapped: true,
    productionWiringChecklistCreated: true,
  );
}

ShellActionProductionClosureManifest _readyActionClosureManifest() {
  final state = ShellActionProductionWiringState.fromCallbacks(
    actionSet: const ShellActionProductionActionSet(
      requiredActionNames: {'newTab'},
    ),
    callbacks: ShellActionProductionCallbacks(
      newTab: (_) => const ShellActionBindingResult.completed(),
    ),
  );

  return ShellActionProductionClosureManifest(
    snapshot: ShellActionProductionAuditSnapshot(
      capturedAt: DateTime.utc(2026, 5, 16),
      wiringReport: ShellActionProductionWiringReport.fromState(state),
    ),
    testsPassed: true,
    analysisPassed: true,
  );
}

LocalTerminalDomainWiringSummary _coreLayoutSummary() {
  return LocalTerminalDomainWiringSummary.fromLayout(
    TerminalLayoutProductionWiring(
      requiredOperations: _coreLayoutOperations,
      callbacks: _coreLayoutCallbacks(),
    ),
  );
}

const _coreLayoutOperations = [
  TerminalLayoutProductionOperation.newTab,
  TerminalLayoutProductionOperation.closeTab,
  TerminalLayoutProductionOperation.reopenClosedTab,
  TerminalLayoutProductionOperation.reopenClosedPane,
  TerminalLayoutProductionOperation.duplicateCurrentCwd,
  TerminalLayoutProductionOperation.splitRight,
  TerminalLayoutProductionOperation.splitDown,
  TerminalLayoutProductionOperation.closePane,
  TerminalLayoutProductionOperation.focusNextPane,
  TerminalLayoutProductionOperation.focusPreviousPane,
  TerminalLayoutProductionOperation.resizePane,
  TerminalLayoutProductionOperation.swapPane,
  TerminalLayoutProductionOperation.zoomPane,
];

TerminalLayoutProductionCallbacks _coreLayoutCallbacks() {
  return TerminalLayoutProductionCallbacks(
    newTab: _completeLayout,
    closeTab: _completeLayout,
    reopenClosedTab: _completeLayout,
    reopenClosedPane: _completeLayout,
    duplicateCurrentCwd: _completeLayout,
    splitRight: _completeLayout,
    splitDown: _completeLayout,
    closePane: _completeLayout,
    focusNextPane: _completeLayout,
    focusPreviousPane: _completeLayout,
    resizePane: _completeLayout,
    swapPane: _completeLayout,
    zoomPane: _completeLayout,
  );
}

TerminalLayoutBindingResult _completeLayout(
  TerminalLayoutBindingContext context,
) {
  return const TerminalLayoutBindingResult.completed();
}

LocalTerminalDomainWiringSummary _coreProductivitySummary() {
  return LocalTerminalDomainWiringSummary.fromProductivity(
    ShellProductivityProductionWiring(
      requiredOperations: _coreProductivityOperations,
      callbacks: _coreProductivityCallbacks(),
    ),
  );
}

const _coreProductivityOperations = [
  ShellProductivityProductionOperation.nextPrompt,
  ShellProductivityProductionOperation.previousPrompt,
  ShellProductivityProductionOperation.selectCommandOutput,
  ShellProductivityProductionOperation.copyCommandOutput,
  ShellProductivityProductionOperation.openRecentDirectory,
  ShellProductivityProductionOperation.searchScrollback,
  ShellProductivityProductionOperation.nextSearchMatch,
  ShellProductivityProductionOperation.previousSearchMatch,
  ShellProductivityProductionOperation.clearSearch,
  ShellProductivityProductionOperation.clearScrollback,
  ShellProductivityProductionOperation.toggleReadOnly,
];

ShellProductivityProductionCallbacks _coreProductivityCallbacks() {
  return ShellProductivityProductionCallbacks(
    nextPrompt: _completeProductivity,
    previousPrompt: _completeProductivity,
    selectCommandOutput: _completeProductivity,
    copyCommandOutput: _completeProductivity,
    openRecentDirectory: _completeProductivity,
    searchScrollback: _completeProductivity,
    nextSearchMatch: _completeProductivity,
    previousSearchMatch: _completeProductivity,
    clearSearch: _completeProductivity,
    clearScrollback: _completeProductivity,
    toggleReadOnly: _completeProductivity,
  );
}

ShellProductivityBindingResult _completeProductivity(
  ShellProductivityBindingContext context,
) {
  return const ShellProductivityBindingResult.completed();
}

LocalTerminalDomainWiringSummary _corePolicySummary() {
  return LocalTerminalDomainWiringSummary.fromPolicy(
    LocalTerminalPolicyProductionWiring(
      requiredOperations: _corePolicyOperations,
      callbacks: _corePolicyCallbacks(),
    ),
  );
}

const _corePolicyOperations = [
  LocalTerminalPolicyProductionOperation.copy,
  LocalTerminalPolicyProductionOperation.paste,
  LocalTerminalPolicyProductionOperation.pasteHistory,
  LocalTerminalPolicyProductionOperation.pasteAsBracketed,
  LocalTerminalPolicyProductionOperation.confirmLargePaste,
  LocalTerminalPolicyProductionOperation.confirmMultilinePaste,
  LocalTerminalPolicyProductionOperation.recordPasteHistory,
  LocalTerminalPolicyProductionOperation.osc52Copy,
  LocalTerminalPolicyProductionOperation.emitBellNotification,
  LocalTerminalPolicyProductionOperation.emitCommandFinishedNotification,
  LocalTerminalPolicyProductionOperation.emitActivityNotification,
  LocalTerminalPolicyProductionOperation.toggleHotkeyWindow,
];

LocalTerminalPolicyProductionCallbacks _corePolicyCallbacks() {
  return LocalTerminalPolicyProductionCallbacks(
    copy: _completePolicy,
    paste: _completePolicy,
    pasteHistory: _completePolicy,
    pasteAsBracketed: _completePolicy,
    confirmLargePaste: _completePolicy,
    confirmMultilinePaste: _completePolicy,
    recordPasteHistory: _completePolicy,
    osc52Copy: _completePolicy,
    emitBellNotification: _completePolicy,
    emitCommandFinishedNotification: _completePolicy,
    emitActivityNotification: _completePolicy,
    toggleHotkeyWindow: _completePolicy,
  );
}

LocalTerminalPolicyBindingResult _completePolicy(
  LocalTerminalPolicyBindingContext context,
) {
  return const LocalTerminalPolicyBindingResult.completed();
}

LocalTerminalDomainWiringSummary _coreVisualSummary() {
  return LocalTerminalDomainWiringSummary.fromVisual(
    LocalTerminalVisualProductionWiring(
      requiredOperations: _coreVisualOperations,
      callbacks: _coreVisualCallbacks(),
    ),
  );
}

const _coreVisualOperations = [
  LocalTerminalVisualProductionOperation.openThemePicker,
  LocalTerminalVisualProductionOperation.applyTheme,
  LocalTerminalVisualProductionOperation.applyLayoutTemplate,
  LocalTerminalVisualProductionOperation.exportScrollback,
  LocalTerminalVisualProductionOperation.applyPaneVisualPolicy,
  LocalTerminalVisualProductionOperation.applySplitDividerPolicy,
];

LocalTerminalVisualProductionCallbacks _coreVisualCallbacks() {
  return LocalTerminalVisualProductionCallbacks(
    openThemePicker: _completeVisual,
    applyTheme: _completeVisual,
    applyLayoutTemplate: _completeVisual,
    exportScrollback: _completeVisual,
    applyPaneVisualPolicy: _completeVisual,
    applySplitDividerPolicy: _completeVisual,
  );
}

LocalTerminalVisualBindingResult _completeVisual(
  LocalTerminalVisualBindingContext context,
) {
  return const LocalTerminalVisualBindingResult.completed();
}
