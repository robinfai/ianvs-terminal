import 'shell_action_production_action_set.dart';
import 'shell_action_production_binding_builder.dart';
import 'shell_action_production_binding_diagnostics.dart';
import 'shell_action_production_callbacks.dart';
import 'shell_action_registry.dart';
import 'shell_action_runtime_bindings.dart';

class ShellActionProductionWiringState {
  ShellActionProductionWiringState({
    required this.buildResult,
    required this.diagnostics,
  });

  factory ShellActionProductionWiringState.fromCallbacks({
    required ShellActionProductionCallbacks callbacks,
    ShellActionProductionActionSet? actionSet,
  }) {
    return ShellActionProductionWiringState.fromBuildResult(
      callbacks.build(actionSet: actionSet),
    );
  }

  factory ShellActionProductionWiringState.fromBuildResult(
    ShellActionProductionBindingBuildResult buildResult,
  ) {
    return ShellActionProductionWiringState(
      buildResult: buildResult,
      diagnostics: ShellActionProductionBindingDiagnostics.fromBuildResult(
        buildResult,
      ),
    );
  }

  final ShellActionProductionBindingBuildResult buildResult;
  final ShellActionProductionBindingDiagnostics diagnostics;

  ShellActionRuntimeBindings get bindings => buildResult.bindings;

  bool get isReady {
    return buildResult.isComplete && diagnostics.canCloseProductionWiring;
  }

  bool get hasBlockingDiagnostics => diagnostics.hasBlockingIssues;

  List<ShellActionProductionBindingDiagnosticItem> get blockingDiagnostics {
    return diagnostics.blockingItems;
  }

  Future<ShellActionBindingResult> run(
    TerminalActionId actionId, {
    String? tabId,
    String? paneId,
    String? cwd,
    Object? payload,
  }) {
    return bindings.run(
      actionId,
      tabId: tabId,
      paneId: paneId,
      cwd: cwd,
      payload: payload,
    );
  }
}
