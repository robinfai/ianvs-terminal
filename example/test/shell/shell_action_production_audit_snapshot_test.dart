import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/shell_action_production_action_set.dart';
import 'package:app/features/shell/shell_action_production_audit_snapshot.dart';
import 'package:app/features/shell/shell_action_production_callbacks.dart';
import 'package:app/features/shell/shell_action_production_dispatch_report.dart';
import 'package:app/features/shell/shell_action_production_wiring_report.dart';
import 'package:app/features/shell/shell_action_production_wiring_state.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_action_runtime_bindings.dart';

void main() {
  test('exports a clean wiring snapshot as json', () {
    final state = ShellActionProductionWiringState.fromCallbacks(
      actionSet: const ShellActionProductionActionSet(
        requiredActionNames: {'newTab'},
      ),
      callbacks: ShellActionProductionCallbacks(
        newTab: (_) => const ShellActionBindingResult.completed(),
      ),
    );
    final snapshot = ShellActionProductionAuditSnapshot(
      capturedAt: DateTime.utc(2026, 5, 16),
      wiringReport: ShellActionProductionWiringReport.fromState(state),
    );

    final json = snapshot.toJson();

    expect(snapshot.canCloseP1ActionWiring, isTrue);
    expect(json['capturedAt'], '2026-05-16T00:00:00.000Z');
    expect(json['canCloseP1ActionWiring'], isTrue);
  });

  test('does not close P1 action wiring when blocking items exist', () {
    final state = ShellActionProductionWiringState.fromCallbacks(
      actionSet: const ShellActionProductionActionSet(
        requiredActionNames: {'newTab', 'closeTab'},
      ),
      callbacks: ShellActionProductionCallbacks(
        newTab: (_) => const ShellActionBindingResult.completed(),
      ),
    );
    final snapshot = ShellActionProductionAuditSnapshot(
      capturedAt: DateTime.utc(2026, 5, 16),
      wiringReport: ShellActionProductionWiringReport.fromState(state),
    );

    expect(snapshot.canCloseP1ActionWiring, isFalse);
    expect(snapshot.toJson()['canCloseP1ActionWiring'], isFalse);
  });

  test('closes P1 action wiring snapshot for default baseline wiring', () {
    final state = ShellActionProductionWiringState.fromCallbacks(
      actionSet: ShellActionProductionActionSet.defaults(),
      callbacks: _baselineCallbacks(),
    );
    final snapshot = ShellActionProductionAuditSnapshot(
      capturedAt: DateTime.utc(2026, 5, 16),
      wiringReport: ShellActionProductionWiringReport.fromState(state),
    );
    final json = snapshot.toJson();
    final wiringReportJson = json['wiringReport'] as Map<String, Object?>;

    expect(snapshot.canCloseP1ActionWiring, isTrue);
    expect(snapshot.hasFailedDispatches, isFalse);
    expect(json['canCloseP1ActionWiring'], isTrue);
    expect(wiringReportJson['ready'], isTrue);
    expect(wiringReportJson['blockingItems'], isEmpty);
  });

  test('failed recent dispatch blocks P1 action wiring closure', () {
    final state = ShellActionProductionWiringState.fromCallbacks(
      actionSet: const ShellActionProductionActionSet(
        requiredActionNames: {'newTab'},
      ),
      callbacks: ShellActionProductionCallbacks(
        newTab: (_) => const ShellActionBindingResult.completed(),
      ),
    );
    final snapshot = ShellActionProductionAuditSnapshot(
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
    );

    expect(snapshot.hasFailedDispatches, isTrue);
    expect(snapshot.canCloseP1ActionWiring, isFalse);
    expect(snapshot.toJson()['hasFailedDispatches'], isTrue);
    expect(snapshot.toJson()['canCloseP1ActionWiring'], isFalse);
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
    clearBuffer: _complete,
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
