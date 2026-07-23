import '../policies/local_terminal_policy_action_reducer.dart';
import '../productivity/shell_productivity_action_reducer.dart';
import '../productivity/shell_productivity_models.dart';
import '../visual/local_terminal_visual_action_reducer.dart';
import '../layout/terminal_layout_action_reducer.dart';
import '../layout/local_terminal_layout_models.dart';
import 'shell_action_registry.dart';

sealed class ShellActionDispatchResult {
  const ShellActionDispatchResult();
}

class ShellLayoutDispatchResult extends ShellActionDispatchResult {
  const ShellLayoutDispatchResult(this.layout);

  final TerminalLayout layout;
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
    this.layout = const TerminalLayout(),
    this.productivity = const ShellProductivityState(),
    this.policies = const LocalTerminalPolicyBundle(),
    this.visual = const LocalTerminalVisualActionContext(),
  });

  final TerminalLayout layout;
  final ShellProductivityState productivity;
  final LocalTerminalPolicyBundle policies;
  final LocalTerminalVisualActionContext visual;
}

class ShellActionDispatchContext {
  const ShellActionDispatchContext({
    required this.layout,
    required this.productivity,
    required this.policy,
    required this.visual,
  });

  final TerminalLayoutActionContext layout;
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
    final layout = TerminalLayoutActionReducer.reduce(
      layout: state.layout,
      actionId: actionId,
      context: context.layout,
    );
    if (!identical(layout, state.layout)) {
      return ShellLayoutDispatchResult(layout);
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
