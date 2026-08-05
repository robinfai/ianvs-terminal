import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/policies/local_terminal_policy_production_callbacks.dart';
import 'package:app/features/productivity/shell_productivity_production_callbacks.dart';
import 'package:app/features/shell/local_terminal_domain_wiring_summary.dart';
import 'package:app/features/shell/local_terminal_production_wiring_manifest.dart';
import 'package:app/features/visual/local_terminal_visual_production_callbacks.dart';
import 'package:app/features/layout/terminal_layout_production_callbacks.dart';

void main() {
  test('converts layout wiring into a milestone manifest', () {
    final wiring = TerminalLayoutProductionWiring(
      requiredOperations: const [
        TerminalLayoutProductionOperation.newTab,
        TerminalLayoutProductionOperation.closeTab,
      ],
      callbacks: TerminalLayoutProductionCallbacks(
        newTab: (_) => const TerminalLayoutBindingResult.completed(),
      ),
    );

    final summary = LocalTerminalDomainWiringSummary.fromLayout(wiring);
    final manifest = summary.toMilestoneManifest(
      testsPassed: false,
      analysisPassed: false,
    );

    expect(summary.milestone, LocalTerminalProductionMilestone.p2Layout);
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
      LocalTerminalDomainWiringSummary.fromLayout(
        TerminalLayoutProductionWiring(
          requiredOperations: _coreLayoutOperations,
          callbacks: _coreLayoutCallbacks(),
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
    final layoutSummary = LocalTerminalDomainWiringSummary.fromLayout(
      TerminalLayoutProductionWiring(callbacks: _coreLayoutCallbacks()),
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

    expect(layoutSummary.ready, isFalse);
    expect(layoutSummary.missingOperationNames, contains('saveLayout'));
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
