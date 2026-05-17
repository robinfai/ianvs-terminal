import 'shell_action_production_action_set.dart';
import 'shell_action_production_callbacks.dart';
import 'shell_action_production_executor.dart';
import 'shell_action_production_wiring_state.dart';
import 'shell_action_runtime_bindings.dart';

typedef ShellActionProductionExternalExecutor =
    Future<ShellActionBindingResult> Function(
      ShellActionBindingContext context,
    );

class ShellActionProductionRuntimeAdapter {
  const ShellActionProductionRuntimeAdapter({required this.executor});

  factory ShellActionProductionRuntimeAdapter.fromCallbacks({
    required ShellActionProductionCallbacks callbacks,
    ShellActionProductionActionSet? actionSet,
  }) {
    return ShellActionProductionRuntimeAdapter(
      executor: ShellActionProductionExecutor(
        wiringState: ShellActionProductionWiringState.fromCallbacks(
          callbacks: callbacks,
          actionSet: actionSet,
        ),
      ),
    );
  }

  final ShellActionProductionExecutor executor;

  bool get isReady => executor.isReady;

  ShellActionProductionExternalExecutor asExternalExecutor() {
    return execute;
  }

  Future<ShellActionBindingResult> execute(
    ShellActionBindingContext context,
  ) async {
    final result = await executor.execute(
      context.actionId,
      tabId: context.tabId,
      paneId: context.paneId,
      cwd: context.cwd,
      payload: context.payload,
    );
    return result.bindingResult;
  }
}
