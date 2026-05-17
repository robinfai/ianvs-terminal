import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/policies/local_terminal_policy_production_callbacks.dart';
import 'package:app/features/productivity/shell_productivity_production_callbacks.dart';
import 'package:app/features/shell/local_terminal_domain_wiring_summary.dart';
import 'package:app/features/shell/local_terminal_production_wiring_manifest.dart';
import 'package:app/features/visual/local_terminal_visual_production_callbacks.dart';
import 'package:app/features/workspace/local_workspace_production_callbacks.dart';

void main() {
  test('converts workspace wiring into a milestone manifest', () {
    final wiring = LocalWorkspaceProductionWiring(
      requiredOperations: const [
        LocalWorkspaceProductionOperation.newTab,
        LocalWorkspaceProductionOperation.closeTab,
      ],
      callbacks: LocalWorkspaceProductionCallbacks(
        newTab: (_) => const LocalWorkspaceBindingResult.completed(),
      ),
    );

    final summary = LocalTerminalDomainWiringSummary.fromWorkspace(wiring);
    final manifest = summary.toMilestoneManifest(
      testsPassed: false,
      analysisPassed: false,
    );

    expect(summary.milestone, LocalTerminalProductionMilestone.p2Workspace);
    expect(summary.ready, isFalse);
    expect(summary.missingOperationNames, ['closeTab']);
    expect(manifest.canClose, isFalse);
    expect(
      manifest.effectiveBlockers,
      contains('Missing production callback for closeTab.'),
    );
  });

  test(
    'converts ready productivity wiring into a closeable manifest input',
    () {
      final wiring = ShellProductivityProductionWiring(
        requiredOperations: const [
          ShellProductivityProductionOperation.searchScrollback,
        ],
        callbacks: ShellProductivityProductionCallbacks(
          searchScrollback: (_) =>
              const ShellProductivityBindingResult.completed(),
        ),
      );

      final summary = LocalTerminalDomainWiringSummary.fromProductivity(wiring);
      final manifest = summary.toMilestoneManifest(
        testsPassed: true,
        analysisPassed: true,
      );

      expect(summary.ready, isTrue);
      expect(summary.missingOperationNames, isEmpty);
      expect(manifest.canClose, isTrue);
    },
  );

  test('summarizes current P2-P5 core baselines as ready', () {
    final summaries = [
      LocalTerminalDomainWiringSummary.fromWorkspace(
        LocalWorkspaceProductionWiring(
          requiredOperations: _coreWorkspaceOperations,
          callbacks: _coreWorkspaceCallbacks(),
        ),
      ),
      LocalTerminalDomainWiringSummary.fromProductivity(
        ShellProductivityProductionWiring(
          requiredOperations: _coreProductivityOperations,
          callbacks: _coreProductivityCallbacks(),
        ),
      ),
      LocalTerminalDomainWiringSummary.fromPolicy(
        LocalTerminalPolicyProductionWiring(
          requiredOperations: _corePolicyOperations,
          callbacks: _corePolicyCallbacks(),
        ),
      ),
      LocalTerminalDomainWiringSummary.fromVisual(
        LocalTerminalVisualProductionWiring(
          requiredOperations: _coreVisualOperations,
          callbacks: _coreVisualCallbacks(),
        ),
      ),
    ];

    for (final summary in summaries) {
      final manifest = summary.toMilestoneManifest(
        testsPassed: true,
        analysisPassed: true,
      );

      expect(summary.ready, isTrue);
      expect(summary.missingOperationNames, isEmpty);
      expect(summary.hasMissingOperations, isFalse);
      expect(manifest.canClose, isTrue);
    }
  });

  test('summarizes advanced gaps when all operations are required', () {
    final workspaceSummary = LocalTerminalDomainWiringSummary.fromWorkspace(
      LocalWorkspaceProductionWiring(callbacks: _coreWorkspaceCallbacks()),
    );
    final productivitySummary =
        LocalTerminalDomainWiringSummary.fromProductivity(
          ShellProductivityProductionWiring(
            callbacks: _coreProductivityCallbacks(),
          ),
        );
    final policySummary = LocalTerminalDomainWiringSummary.fromPolicy(
      LocalTerminalPolicyProductionWiring(callbacks: _corePolicyCallbacks()),
    );
    final visualSummary = LocalTerminalDomainWiringSummary.fromVisual(
      LocalTerminalVisualProductionWiring(callbacks: _coreVisualCallbacks()),
    );

    expect(workspaceSummary.ready, isFalse);
    expect(workspaceSummary.missingOperationNames, contains('saveLayout'));
    expect(productivitySummary.ready, isFalse);
    expect(
      productivitySummary.missingOperationNames,
      contains('jumpToCommandBlock'),
    );
    expect(policySummary.ready, isFalse);
    expect(
      policySummary.missingOperationNames,
      contains('emitSilenceNotification'),
    );
    expect(visualSummary.ready, isFalse);
    expect(visualSummary.missingOperationNames, contains('importThemePreset'));
  });
}

const _coreWorkspaceOperations = [
  LocalWorkspaceProductionOperation.newTab,
  LocalWorkspaceProductionOperation.closeTab,
  LocalWorkspaceProductionOperation.reopenClosedTab,
  LocalWorkspaceProductionOperation.duplicateCurrentCwd,
  LocalWorkspaceProductionOperation.splitRight,
  LocalWorkspaceProductionOperation.splitDown,
  LocalWorkspaceProductionOperation.closePane,
  LocalWorkspaceProductionOperation.focusNextPane,
  LocalWorkspaceProductionOperation.focusPreviousPane,
  LocalWorkspaceProductionOperation.resizePane,
  LocalWorkspaceProductionOperation.swapPane,
  LocalWorkspaceProductionOperation.zoomPane,
];

LocalWorkspaceProductionCallbacks _coreWorkspaceCallbacks() {
  return LocalWorkspaceProductionCallbacks(
    newTab: _completeWorkspace,
    closeTab: _completeWorkspace,
    reopenClosedTab: _completeWorkspace,
    duplicateCurrentCwd: _completeWorkspace,
    splitRight: _completeWorkspace,
    splitDown: _completeWorkspace,
    closePane: _completeWorkspace,
    focusNextPane: _completeWorkspace,
    focusPreviousPane: _completeWorkspace,
    resizePane: _completeWorkspace,
    swapPane: _completeWorkspace,
    zoomPane: _completeWorkspace,
  );
}

LocalWorkspaceBindingResult _completeWorkspace(
  LocalWorkspaceBindingContext context,
) {
  return const LocalWorkspaceBindingResult.completed();
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
