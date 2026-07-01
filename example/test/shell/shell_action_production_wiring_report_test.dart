import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/shell_action_production_action_set.dart';
import 'package:app/features/shell/shell_action_production_callbacks.dart';
import 'package:app/features/shell/shell_action_production_wiring_report.dart';
import 'package:app/features/shell/shell_action_production_wiring_state.dart';
import 'package:app/features/shell/shell_action_runtime_bindings.dart';

void main() {
  test('reports ready production wiring as clean json', () {
    final state = ShellActionProductionWiringState.fromCallbacks(
      actionSet: const ShellActionProductionActionSet(
        requiredActionNames: {'newTab'},
      ),
      callbacks: ShellActionProductionCallbacks(
        newTab: (_) => const ShellActionBindingResult.completed(),
      ),
    );

    final report = ShellActionProductionWiringReport.fromState(state);

    expect(report.ready, isTrue);
    expect(report.hasBlockingItems, isFalse);
    expect(report.toJson()['blockingItems'], isEmpty);
  });

  test('reports missing callbacks as blocking json items', () {
    final state = ShellActionProductionWiringState.fromCallbacks(
      actionSet: const ShellActionProductionActionSet(
        requiredActionNames: {'newTab', 'closeTab'},
      ),
      callbacks: ShellActionProductionCallbacks(
        newTab: (_) => const ShellActionBindingResult.completed(),
      ),
    );

    final report = ShellActionProductionWiringReport.fromState(state);
    final json = report.toJson();

    expect(report.ready, isFalse);
    expect(report.hasBlockingItems, isTrue);
    expect(json['ready'], isFalse);
    expect(report.blockingItems.single.actionId, 'closeActiveTab');
  });

  test('reports default P1 baseline wiring as clean', () {
    final state = ShellActionProductionWiringState.fromCallbacks(
      actionSet: ShellActionProductionActionSet.defaults(),
      callbacks: _baselineCallbacks(),
    );

    final report = ShellActionProductionWiringReport.fromState(state);
    final json = report.toJson();

    expect(report.ready, isTrue);
    expect(report.hasBlockingItems, isFalse);
    expect(report.blockingItems, isEmpty);
    expect(report.advisoryItems, isEmpty);
    expect(json['ready'], isTrue);
    expect(json['blockingItems'], isEmpty);
    expect(json['advisoryItems'], isEmpty);
  });
}

ShellActionProductionCallbacks _baselineCallbacks() {
  return ShellActionProductionCallbacks(
    newTab: _complete,
    closeTab: _complete,
    reopenClosedTab: _complete,
    reopenClosedPane: _complete,
    duplicateCurrentCwd: _complete,
    toolbelt: _complete,
    splitRight: _complete,
    splitDown: _complete,
    closePane: _complete,
    focusNextPane: _complete,
    focusPreviousPane: _complete,
    copy: _complete,
    copyMode: _complete,
    paste: _complete,
    advancedPaste: _complete,
    pasteHistory: _complete,
    instantReplay: _complete,
    globalSearch: _complete,
    autocomplete: _complete,
    autoComposer: _complete,
    copyCommandOutput: _complete,
    searchScrollback: _complete,
    nextPrompt: _complete,
    previousPrompt: _complete,
    selectCommandOutput: _complete,
    shellIntegrationUtilities: _complete,
    openRecentDirectory: _complete,
    tmuxIntegration: _complete,
    coprocess: _complete,
    annotations: _complete,
    capturedOutput: _complete,
    passwordManager: _complete,
    clearScrollback: _complete,
    toggleReadOnly: _complete,
    toggleCommandPalette: _complete,
    toggleHotkeyWindow: _complete,
    openDefaults: _complete,
    defaults: _complete,
    profiles: _complete,
    dynamicProfiles: _complete,
    openThemePicker: _complete,
    applyLayoutTemplate: _complete,
    exportScrollback: _complete,
    resizePaneLeft: _complete,
    swapPane: _complete,
    zoomPane: _complete,
    toggleCommandFinishedNotify: _complete,
    toggleBellNotify: _complete,
    toggleActivityMonitor: _complete,
  );
}

ShellActionBindingResult _complete(ShellActionBindingContext context) {
  return const ShellActionBindingResult.completed();
}
