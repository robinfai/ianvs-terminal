import 'package:app/features/shell/shell_action_production_action_set.dart';
import 'package:app/features/shell/shell_action_production_audit_snapshot.dart';
import 'package:app/features/shell/shell_action_production_callbacks.dart';
import 'package:app/features/shell/shell_action_production_closure_manifest.dart';
import 'package:app/features/shell/shell_action_production_dispatch_report.dart';
import 'package:app/features/shell/shell_action_production_wiring_report.dart';
import 'package:app/features/shell/shell_action_production_wiring_state.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_action_runtime_bindings.dart';
import 'package:flutter_test/flutter_test.dart';

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
