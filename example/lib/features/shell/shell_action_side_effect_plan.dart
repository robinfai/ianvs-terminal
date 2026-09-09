import '../policies/local_terminal_paste_decision.dart';
import '../policies/local_terminal_policy_action_reducer.dart';
import '../productivity/shell_productivity_action_reducer.dart';
import '../visual/local_terminal_visual_action_reducer.dart';
import 'shell_action_dispatcher.dart';

enum ShellActionSideEffectKind {
  updateLayout,
  updateProductivityState,
  scrollToPrompt,
  copyCommandOutput,
  sendPaste,
  confirmPaste,
  blockPaste,
  exportScrollback,
  none,
}

class ShellActionSideEffectPlan {
  const ShellActionSideEffectPlan({required this.kind, this.payload});

  final ShellActionSideEffectKind kind;
  final Object? payload;
}

class ShellActionSideEffectPlanner {
  const ShellActionSideEffectPlanner._();

  static ShellActionSideEffectPlan plan(ShellActionDispatchResult result) {
    return switch (result) {
      ShellLayoutDispatchResult() => ShellActionSideEffectPlan(
        kind: ShellActionSideEffectKind.updateLayout,
        payload: result.layout,
      ),
      ShellProductivityDispatchResult() => _productivity(result.result),
      ShellPolicyDispatchResult() => _policy(result.result),
      ShellVisualDispatchResult() => _visual(result.result),
      ShellUnhandledDispatchResult() => const ShellActionSideEffectPlan(
        kind: ShellActionSideEffectKind.none,
      ),
    };
  }

  static ShellActionSideEffectPlan _productivity(
    ShellProductivityActionResult result,
  ) {
    return switch (result) {
      ShellProductivityStateResult() => ShellActionSideEffectPlan(
        kind: ShellActionSideEffectKind.updateProductivityState,
        payload: result.state,
      ),
      ShellProductivityPromptResult() => ShellActionSideEffectPlan(
        kind: ShellActionSideEffectKind.scrollToPrompt,
        payload: result.prompt,
      ),
      ShellProductivityCommandOutputResult() => ShellActionSideEffectPlan(
        kind: ShellActionSideEffectKind.copyCommandOutput,
        payload: result.range,
      ),
      ShellProductivitySearchResult() => ShellActionSideEffectPlan(
        kind: ShellActionSideEffectKind.updateProductivityState,
        payload: result.search,
      ),
      ShellProductivityNoopResult() => const ShellActionSideEffectPlan(
        kind: ShellActionSideEffectKind.none,
      ),
    };
  }

  static ShellActionSideEffectPlan _policy(
    LocalTerminalPolicyActionResult result,
  ) {
    return switch (result) {
      LocalTerminalPasteActionResult() => _paste(result.decision),
      LocalTerminalPolicyNoopResult() => const ShellActionSideEffectPlan(
        kind: ShellActionSideEffectKind.none,
      ),
    };
  }

  static ShellActionSideEffectPlan _paste(LocalTerminalPasteDecision decision) {
    return switch (decision.kind) {
      LocalTerminalPasteDecisionKind.sendImmediately =>
        ShellActionSideEffectPlan(
          kind: ShellActionSideEffectKind.sendPaste,
          payload: decision,
        ),
      LocalTerminalPasteDecisionKind.requireConfirmation =>
        ShellActionSideEffectPlan(
          kind: ShellActionSideEffectKind.confirmPaste,
          payload: decision,
        ),
      LocalTerminalPasteDecisionKind.blockedReadOnly =>
        ShellActionSideEffectPlan(
          kind: ShellActionSideEffectKind.blockPaste,
          payload: decision,
        ),
    };
  }

  static ShellActionSideEffectPlan _visual(
    LocalTerminalVisualActionResult result,
  ) {
    return switch (result) {
      LocalTerminalExportScrollbackResult() => ShellActionSideEffectPlan(
        kind: ShellActionSideEffectKind.exportScrollback,
        payload: result.export,
      ),
      LocalTerminalVisualNoopResult() => const ShellActionSideEffectPlan(
        kind: ShellActionSideEffectKind.none,
      ),
    };
  }
}
