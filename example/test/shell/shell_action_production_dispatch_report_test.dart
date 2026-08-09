import 'package:app/features/shell/shell_action_production_action_set.dart';
import 'package:app/features/shell/shell_action_production_callbacks.dart';
import 'package:app/features/shell/shell_action_production_dispatch_report.dart';
import 'package:app/features/shell/shell_action_production_runtime_adapter.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_action_runtime_bindings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports successful production dispatch', () async {
    final adapter = ShellActionProductionRuntimeAdapter.fromCallbacks(
      actionSet: const ShellActionProductionActionSet(
        requiredActionNames: {'newTab'},
      ),
      callbacks: ShellActionProductionCallbacks(
        newTab: (_) => const ShellActionBindingResult.completed('created'),
      ),
    );

    final report = await ShellActionProductionDispatchReport.execute(
      adapter: adapter,
      context: const ShellActionBindingContext(
        actionId: TerminalActionId.newTab,
      ),
    );

    expect(report.readyBeforeDispatch, isTrue);
    expect(report.completed, isTrue);
    expect(report.failed, isFalse);
    expect(report.toJson()['actionId'], 'newTab');
  });

  test('reports unavailable production dispatch', () async {
    final adapter = ShellActionProductionRuntimeAdapter.fromCallbacks(
      actionSet: const ShellActionProductionActionSet(
        requiredActionNames: {'newTab', 'closeTab'},
      ),
      callbacks: ShellActionProductionCallbacks(
        newTab: (_) => const ShellActionBindingResult.completed(),
      ),
    );

    final report = await ShellActionProductionDispatchReport.execute(
      adapter: adapter,
      context: const ShellActionBindingContext(
        actionId: TerminalActionId.closeActiveTab,
      ),
    );

    expect(report.readyBeforeDispatch, isFalse);
    expect(report.completed, isFalse);
    expect(report.failed, isTrue);
    expect(report.failureCode, ShellActionBindingFailureCode.unavailable);
  });
}
