import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/policies/local_terminal_policy_production_callbacks.dart';
import 'package:app/features/productivity/shell_productivity_production_callbacks.dart';
import 'package:app/features/shell/local_terminal_p0_boundary_closure_manifest.dart';
import 'package:app/features/shell/local_terminal_production_wiring_bundle.dart';
import 'package:app/features/shell/local_terminal_production_wiring_manifest.dart';
import 'package:app/features/shell/local_terminal_production_wiring_manifest_builder.dart';
import 'package:app/features/shell/shell_action_production_action_set.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_action_runtime_bindings.dart';
import 'package:app/features/visual/local_terminal_visual_production_callbacks.dart';
import 'package:app/features/layout/terminal_layout_production_callbacks.dart';

void main() {
  test('builds a closeable manifest from ready domain callbacks', () async {
    final bundle = LocalTerminalProductionWiringBundle.fromDomainCallbacks(
      capturedAt: DateTime.utc(2026, 5, 16),
      p0BoundaryManifest: _readyP0(),
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
        newTab: (_) => const TerminalLayoutBindingResult.completed('tab'),
      ),
      layoutRequiredOperations: const [
        TerminalLayoutProductionOperation.newTab,
      ],
      layoutVerification: LocalTerminalMilestoneVerificationStatus.verified,
      productivityCallbacks: ShellProductivityProductionCallbacks(
        searchScrollback: (_) =>
            const ShellProductivityBindingResult.completed('search'),
      ),
      productivityRequiredOperations: const [
        ShellProductivityProductionOperation.searchScrollback,
      ],
      productivityVerification:
          LocalTerminalMilestoneVerificationStatus.verified,
      policyCallbacks: LocalTerminalPolicyProductionCallbacks(
        paste: (_) => const LocalTerminalPolicyBindingResult.completed('paste'),
      ),
      policyRequiredOperations: const [
        LocalTerminalPolicyProductionOperation.paste,
      ],
      policyVerification: LocalTerminalMilestoneVerificationStatus.verified,
      visualCallbacks: LocalTerminalVisualProductionCallbacks(
        applyTheme: (_) =>
            const LocalTerminalVisualBindingResult.completed('theme'),
      ),
      visualRequiredOperations: const [
        LocalTerminalVisualProductionOperation.applyTheme,
      ],
      visualVerification: LocalTerminalMilestoneVerificationStatus.verified,
    );

    final result = await bundle.actionWiringState.run(TerminalActionId.newTab);

    expect(bundle.canCloseAll, isTrue);
    expect(result.message, 'tab');
  });

  test(
    'keeps missing domain callbacks visible in action and domain manifests',
    () {
      final bundle = LocalTerminalProductionWiringBundle.fromDomainCallbacks(
        capturedAt: DateTime.utc(2026, 5, 16),
        p0BoundaryManifest: _readyP0(),
        p0Verification: LocalTerminalMilestoneVerificationStatus.verified,
        actionSet: const ShellActionProductionActionSet(
          requiredActionNames: {'newTab'},
        ),
        actionVerification: LocalTerminalMilestoneVerificationStatus.verified,
        layoutCallbacks: const TerminalLayoutProductionCallbacks(),
        layoutRequiredOperations: const [
          TerminalLayoutProductionOperation.newTab,
        ],
        layoutVerification: LocalTerminalMilestoneVerificationStatus.verified,
        productivityRequiredOperations: const [],
        productivityVerification:
            LocalTerminalMilestoneVerificationStatus.verified,
        policyRequiredOperations: const [],
        policyVerification: LocalTerminalMilestoneVerificationStatus.verified,
        visualRequiredOperations: const [],
        visualVerification: LocalTerminalMilestoneVerificationStatus.verified,
      );

      final actionManifest = bundle.manifest.milestoneFor(
        LocalTerminalProductionMilestone.p1ActionConfig,
      );
      final workspaceManifest = bundle.manifest.milestoneFor(
        LocalTerminalProductionMilestone.p2Layout,
      );

      expect(bundle.canCloseAll, isFalse);
      expect(actionManifest?.canClose, isFalse);
      expect(workspaceManifest?.canClose, isFalse);
      expect(
        workspaceManifest?.effectiveBlockers,
        contains('Missing production callback for newTab.'),
      );
    },
  );

  test('builds closeable manifest from current P2-P5 core baselines', () async {
    final bundle = LocalTerminalProductionWiringBundle.fromDomainCallbacks(
      capturedAt: DateTime.utc(2026, 5, 16),
      p0BoundaryManifest: _readyP0(),
      p0Verification: LocalTerminalMilestoneVerificationStatus.verified,
      actionSet: const ShellActionProductionActionSet(
        requiredActionNames: {
          'newTab',
          'closeTab',
          'reopenClosedTab',
          'reopenClosedPane',
          'duplicateCurrentCwd',
          'splitRight',
          'splitDown',
          'closePane',
          'focusNextPane',
          'focusPreviousPane',
          'copy',
          'paste',
          'pasteHistory',
          'copyCommandOutput',
          'searchScrollback',
          'nextSearchMatch',
          'previousSearchMatch',
          'clearSearch',
          'nextPrompt',
          'previousPrompt',
          'selectCommandOutput',
          'openRecentDirectory',
          'clearBuffer',
          'toggleReadOnly',
          'toggleCommandPalette',
          'toggleHotkeyWindow',
          'openThemePicker',
          'applyLayoutTemplate',
          'exportScrollback',
          'resizePane',
          'swapPane',
          'zoomPane',
          'applyTheme',
        },
      ),
      actionVerification: LocalTerminalMilestoneVerificationStatus.verified,
      toggleCommandPalette: _completeAction,
      layoutCallbacks: _coreLayoutCallbacks(),
      layoutRequiredOperations: _coreLayoutOperations,
      layoutVerification: LocalTerminalMilestoneVerificationStatus.verified,
      productivityCallbacks: _coreProductivityCallbacks(),
      productivityRequiredOperations: _coreProductivityOperations,
      productivityVerification:
          LocalTerminalMilestoneVerificationStatus.verified,
      policyCallbacks: _corePolicyCallbacks(),
      policyRequiredOperations: _corePolicyOperations,
      policyVerification: LocalTerminalMilestoneVerificationStatus.verified,
      visualCallbacks: _coreVisualCallbacks(),
      visualRequiredOperations: _coreVisualOperations,
      visualVerification: LocalTerminalMilestoneVerificationStatus.verified,
    );

    final resizeResult = await bundle.actionWiringState.run(
      TerminalActionId.resizePane,
      paneId: 'pane-1',
    );
    final paletteResult = await bundle.actionWiringState.run(
      TerminalActionId.openCommandMenu,
    );

    expect(bundle.canCloseAll, isTrue);
    expect(bundle.manifest.blockedMilestones, isEmpty);
    expect(bundle.layoutSummary.ready, isTrue);
    expect(bundle.productivitySummary.ready, isTrue);
    expect(bundle.policySummary.ready, isTrue);
    expect(bundle.visualSummary.ready, isTrue);
    expect(resizeResult.completed, isTrue);
    expect(paletteResult.completed, isTrue);
  });

  test('keeps verification blockers when core baseline wiring is ready', () {
    final bundle = LocalTerminalProductionWiringBundle.fromDomainCallbacks(
      capturedAt: DateTime.utc(2026, 5, 16),
      p0BoundaryManifest: _readyP0(),
      p0Verification: LocalTerminalMilestoneVerificationStatus.verified,
      actionSet: const ShellActionProductionActionSet(
        requiredActionNames: {'newTab'},
      ),
      actionVerification: LocalTerminalMilestoneVerificationStatus.verified,
      layoutCallbacks: _coreLayoutCallbacks(),
      layoutRequiredOperations: _coreLayoutOperations,
      layoutVerification: LocalTerminalMilestoneVerificationStatus.notVerified,
      productivityCallbacks: _coreProductivityCallbacks(),
      productivityRequiredOperations: _coreProductivityOperations,
      productivityVerification:
          LocalTerminalMilestoneVerificationStatus.notVerified,
      policyCallbacks: _corePolicyCallbacks(),
      policyRequiredOperations: _corePolicyOperations,
      policyVerification: LocalTerminalMilestoneVerificationStatus.notVerified,
      visualCallbacks: _coreVisualCallbacks(),
      visualRequiredOperations: _coreVisualOperations,
      visualVerification: LocalTerminalMilestoneVerificationStatus.notVerified,
    );

    final workspaceManifest = bundle.manifest.milestoneFor(
      LocalTerminalProductionMilestone.p2Layout,
    );

    expect(bundle.layoutSummary.ready, isTrue);
    expect(bundle.canCloseAll, isFalse);
    expect(workspaceManifest?.wiringReady, isTrue);
    expect(workspaceManifest?.testsPassed, isFalse);
    expect(
      workspaceManifest?.effectiveBlockers,
      contains('Required tests have not passed.'),
    );
  });
}

LocalTerminalP0BoundaryClosureManifest _readyP0() {
  return const LocalTerminalP0BoundaryClosureManifest(
    localTerminalPlanDocumented: true,
    roadmapTerminalLayoutAligned: true,
    remoteScopeExcluded: true,
    perMilestoneExecutionPlansCreated: true,
    competitorCoverageMapped: true,
    productionWiringChecklistCreated: true,
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
  ShellProductivityProductionOperation.clearBuffer,
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
    clearBuffer: _completeProductivity,
    toggleReadOnly: _completeProductivity,
  );
}

ShellProductivityBindingResult _completeProductivity(
  ShellProductivityBindingContext context,
) {
  return const ShellProductivityBindingResult.completed();
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

ShellActionBindingResult _completeAction(ShellActionBindingContext context) {
  return const ShellActionBindingResult.completed();
}
