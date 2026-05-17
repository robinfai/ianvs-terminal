import '../policies/local_terminal_policy_action_reducer.dart';
import '../productivity/shell_productivity_action_reducer.dart';
import '../productivity/shell_productivity_models.dart';
import '../visual/local_terminal_visual_action_reducer.dart';
import '../workspace/local_workspace_action_reducer.dart';
import '../workspace/local_workspace_models.dart';
import 'shell_action_registry.dart';

sealed class ShellActionDispatchResult {
  const ShellActionDispatchResult();
}

class ShellWorkspaceDispatchResult extends ShellActionDispatchResult {
  const ShellWorkspaceDispatchResult(this.workspace);

  final TerminalWorkspace workspace;
}

class ShellProductivityDispatchResult extends ShellActionDispatchResult {
  const ShellProductivityDispatchResult(this.result);

  final ShellProductivityActionResult result;
}

class ShellPolicyDispatchResult extends ShellActionDispatchResult {
  const ShellPolicyDispatchResult(this.result);

  final LocalTerminalPolicyActionResult result;
}

class ShellVisualDispatchResult extends ShellActionDispatchResult {
  const ShellVisualDispatchResult(this.result);

  final LocalTerminalVisualActionResult result;
}

class ShellUnhandledDispatchResult extends ShellActionDispatchResult {
  const ShellUnhandledDispatchResult();
}

class ShellActionDispatchState {
  const ShellActionDispatchState({
    this.workspace = const TerminalWorkspace(),
    this.productivity = const ShellProductivityState(),
    this.policies = const LocalTerminalPolicyBundle(),
    this.visual = const LocalTerminalVisualActionContext(),
  });

  final TerminalWorkspace workspace;
  final ShellProductivityState productivity;
  final LocalTerminalPolicyBundle policies;
  final LocalTerminalVisualActionContext visual;
}

class ShellActionDispatchContext {
  const ShellActionDispatchContext({
    required this.workspace,
    required this.productivity,
    required this.policy,
    required this.visual,
  });

  final LocalWorkspaceActionContext workspace;
  final ShellProductivityActionContext productivity;
  final LocalTerminalPolicyActionContext policy;
  final LocalTerminalVisualActionContext visual;
}

class ShellActionDispatcher {
  const ShellActionDispatcher._();

  static ShellActionDispatchResult dispatch({
    required TerminalActionId actionId,
    required ShellActionDispatchState state,
    required ShellActionDispatchContext context,
  }) {
    final workspace = LocalWorkspaceActionReducer.reduce(
      workspace: state.workspace,
      actionId: actionId,
      context: context.workspace,
    );
    if (!identical(workspace, state.workspace)) {
      return ShellWorkspaceDispatchResult(workspace);
    }

    final productivity = ShellProductivityActionReducer.reduce(
      state: state.productivity,
      actionId: actionId,
      context: context.productivity,
    );
    if (productivity is! ShellProductivityNoopResult) {
      return ShellProductivityDispatchResult(productivity);
    }

    final policy = LocalTerminalPolicyActionReducer.reduce(
      actionId: actionId,
      policies: state.policies,
      context: context.policy,
    );
    if (policy is! LocalTerminalPolicyNoopResult) {
      return ShellPolicyDispatchResult(policy);
    }

    final visual = LocalTerminalVisualActionReducer.reduce(
      actionId: actionId,
      context: context.visual,
    );
    if (visual is! LocalTerminalVisualNoopResult) {
      return ShellVisualDispatchResult(visual);
    }

    return const ShellUnhandledDispatchResult();
  }
}
