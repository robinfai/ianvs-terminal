import 'shell_action_dispatcher.dart';
import 'shell_action_registry.dart';
import 'shell_action_side_effect_executor.dart';
import 'shell_action_side_effect_plan.dart';

class ShellActionPipelineResult {
  const ShellActionPipelineResult({required this.dispatch, required this.plan});

  final ShellActionDispatchResult dispatch;
  final ShellActionSideEffectPlan plan;
}

class ShellActionPipeline {
  const ShellActionPipeline({required this.executor});

  final ShellActionSideEffectExecutor executor;

  Future<ShellActionPipelineResult> run({
    required TerminalActionId actionId,
    required ShellActionDispatchState state,
    required ShellActionDispatchContext context,
  }) async {
    final dispatch = ShellActionDispatcher.dispatch(
      actionId: actionId,
      state: state,
      context: context,
    );
    final plan = ShellActionSideEffectPlanner.plan(dispatch);
    await executor.execute(plan);

    return ShellActionPipelineResult(dispatch: dispatch, plan: plan);
  }
}
