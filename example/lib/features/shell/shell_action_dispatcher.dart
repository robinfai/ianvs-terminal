import '../command_center/command_block_action_reducer.dart';
import '../command_center/command_block_actions.dart';
import '../command_center/command_block_models.dart';
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

class ShellCommandBlockDispatchResult extends ShellActionDispatchResult {
  const ShellCommandBlockDispatchResult(this.result);

  final CommandBlockActionResult result;
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
    this.commandBlock = const ShellCommandBlockActionContext(),
  });

  final LocalWorkspaceActionContext workspace;
  final ShellProductivityActionContext productivity;
  final LocalTerminalPolicyActionContext policy;
  final LocalTerminalVisualActionContext visual;
  final ShellCommandBlockActionContext commandBlock;
}

class ShellCommandBlockActionContext {
  const ShellCommandBlockActionContext({
    this.activeBlock,
    this.hasTerminalFrame = true,
    this.reducer = const CommandBlockActionReducer(),
  });

  final CommandBlock? activeBlock;
  final bool hasTerminalFrame;
  final CommandBlockActionReducer reducer;
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

    final commandBlock = _dispatchCommandBlockAction(
      actionId: actionId,
      state: state,
      context: context.commandBlock,
    );
    if (commandBlock != null) {
      return ShellCommandBlockDispatchResult(commandBlock);
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

CommandBlockActionResult? _dispatchCommandBlockAction({
  required TerminalActionId actionId,
  required ShellActionDispatchState state,
  required ShellCommandBlockActionContext context,
}) {
  final action = _commandBlockActionFor(actionId);
  final block = context.activeBlock;
  if (action == null || block == null) {
    return null;
  }
  return context.reducer.reduce(
    action,
    block,
    readOnly: state.productivity.readOnly,
    hasTerminalFrame: context.hasTerminalFrame,
  );
}

CommandBlockAction? _commandBlockActionFor(TerminalActionId actionId) {
  return switch (actionId) {
    TerminalActionId.copyBlockOutput => CommandBlockAction.copyOutput,
    TerminalActionId.saveBlockOutput => CommandBlockAction.saveOutput,
    TerminalActionId.openInReview => CommandBlockAction.openReviewEntrypoint,
    TerminalActionId.searchWithinBlock => CommandBlockAction.searchWithinBlock,
    TerminalActionId.reInputBlockCommand => CommandBlockAction.reInput,
    TerminalActionId.rerunBlockCommand => CommandBlockAction.rerun,
    _ => null,
  };
}
