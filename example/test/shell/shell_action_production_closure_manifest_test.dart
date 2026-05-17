import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/shell_action_production_action_set.dart';
import 'package:app/features/shell/shell_action_production_audit_snapshot.dart';
import 'package:app/features/shell/shell_action_production_callbacks.dart';
import 'package:app/features/shell/shell_action_production_closure_manifest.dart';
import 'package:app/features/shell/shell_action_production_dispatch_report.dart';
import 'package:app/features/shell/shell_action_production_wiring_report.dart';
import 'package:app/features/shell/shell_action_production_wiring_state.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_action_runtime_bindings.dart';

void main() {
  test('closes only when wiring, tests, and analysis are complete', () {
    final state = ShellActionProductionWiringState.fromCallbacks(
      actionSet: const ShellActionProductionActionSet(
        requiredActionNames: {'newTab'},
      ),
      callbacks: ShellActionProductionCallbacks(
        newTab: (_) => const ShellActionBindingResult.completed(),
      ),
    );
    final manifest = ShellActionProductionClosureManifest(
      snapshot: ShellActionProductionAuditSnapshot(
        capturedAt: DateTime.utc(2026, 5, 16),
        wiringReport: ShellActionProductionWiringReport.fromState(state),
      ),
      testsPassed: true,
      analysisPassed: true,
    );

    expect(manifest.canClose, isTrue);
    expect(manifest.blockers, isEmpty);
  });

  test('keeps verification gaps as blockers', () {
    final state = ShellActionProductionWiringState.fromCallbacks(
      actionSet: const ShellActionProductionActionSet(
        requiredActionNames: {'newTab'},
      ),
      callbacks: ShellActionProductionCallbacks(
        newTab: (_) => const ShellActionBindingResult.completed(),
      ),
    );
    final manifest = ShellActionProductionClosureManifest(
      snapshot: ShellActionProductionAuditSnapshot(
        capturedAt: DateTime.utc(2026, 5, 16),
        wiringReport: ShellActionProductionWiringReport.fromState(state),
      ),
      testsPassed: false,
      analysisPassed: false,
    );

    expect(manifest.canClose, isFalse);
    expect(
      manifest.blockers,
      contains('Required action wiring tests have not passed.'),
    );
    expect(manifest.blockers, contains('Static analysis has not passed.'));
  });

  test('default P1 baseline closure requires verification evidence', () {
    final state = ShellActionProductionWiringState.fromCallbacks(
      actionSet: ShellActionProductionActionSet.defaults(),
      callbacks: _baselineCallbacks(),
    );
    final snapshot = ShellActionProductionAuditSnapshot(
      capturedAt: DateTime.utc(2026, 5, 16),
      wiringReport: ShellActionProductionWiringReport.fromState(state),
    );

    final unverifiedManifest = ShellActionProductionClosureManifest(
      snapshot: snapshot,
      testsPassed: false,
      analysisPassed: false,
    );
    final verifiedManifest = ShellActionProductionClosureManifest(
      snapshot: snapshot,
      testsPassed: true,
      analysisPassed: true,
    );

    expect(snapshot.canCloseP1ActionWiring, isTrue);
    expect(unverifiedManifest.wiringReady, isTrue);
    expect(unverifiedManifest.canClose, isFalse);
    expect(
      unverifiedManifest.blockers,
      contains('Required action wiring tests have not passed.'),
    );
    expect(
      unverifiedManifest.blockers,
      contains('Static analysis has not passed.'),
    );
    expect(verifiedManifest.canClose, isTrue);
    expect(verifiedManifest.blockers, isEmpty);
  });

  test('failed recent dispatch blocks closure', () {
    final state = ShellActionProductionWiringState.fromCallbacks(
      actionSet: const ShellActionProductionActionSet(
        requiredActionNames: {'newTab'},
      ),
      callbacks: ShellActionProductionCallbacks(
        newTab: (_) => const ShellActionBindingResult.completed(),
      ),
    );
    final manifest = ShellActionProductionClosureManifest(
      snapshot: ShellActionProductionAuditSnapshot(
        capturedAt: DateTime.utc(2026, 5, 16),
        wiringReport: ShellActionProductionWiringReport.fromState(state),
        recentDispatchReports: const [
          ShellActionProductionDispatchReport(
            actionId: TerminalActionId.newTab,
            readyBeforeDispatch: true,
            completed: false,
            failed: true,
            failureCode: ShellActionBindingFailureCode.platformFailure,
            message: 'Window bridge failed.',
          ),
        ],
      ),
      testsPassed: true,
      analysisPassed: true,
    );

    expect(manifest.canClose, isFalse);
    expect(
      manifest.blockers,
      contains('Recent production action dispatch failed.'),
    );
  });
}

ShellActionProductionCallbacks _baselineCallbacks() {
  return ShellActionProductionCallbacks(
    newTab: _complete,
    closeTab: _complete,
    reopenClosedTab: _complete,
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
