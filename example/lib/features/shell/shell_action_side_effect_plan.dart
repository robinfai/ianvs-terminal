import '../policies/local_terminal_paste_decision.dart';
import '../policies/local_terminal_policy_action_reducer.dart';
import '../productivity/shell_productivity_action_reducer.dart';
import '../visual/local_terminal_visual_action_reducer.dart';
import 'shell_action_dispatcher.dart';

enum ShellActionSideEffectKind {
  updateWorkspace,
  updateProductivityState,
  scrollToPrompt,
  selectCommandOutput,
  openRecentDirectory,
  commandBlockAction,
  sendPaste,
  confirmPaste,
  blockPaste,
  showNotification,
  updateHotkeyWindowState,
  openThemePicker,
  exportScrollback,
  applyLayoutTemplate,
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
      ShellWorkspaceDispatchResult() => ShellActionSideEffectPlan(
        kind: ShellActionSideEffectKind.updateWorkspace,
        payload: result.workspace,
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
        kind: ShellActionSideEffectKind.selectCommandOutput,
        payload: result.range,
      ),
      ShellProductivityRecentDirectoryResult() => ShellActionSideEffectPlan(
        kind: ShellActionSideEffectKind.openRecentDirectory,
        payload: result.directory,
      ),
      ShellProductivityCommandBlockActionResult() => ShellActionSideEffectPlan(
        kind: ShellActionSideEffectKind.commandBlockAction,
        payload: result.actionId,
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
      LocalTerminalNotificationActionResult() => ShellActionSideEffectPlan(
        kind: ShellActionSideEffectKind.showNotification,
        payload: result.intent,
      ),
      LocalTerminalHotkeyActionResult() => ShellActionSideEffectPlan(
        kind: ShellActionSideEffectKind.updateHotkeyWindowState,
        payload: result.state,
      ),
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
      LocalTerminalOpenThemePickerResult() => const ShellActionSideEffectPlan(
        kind: ShellActionSideEffectKind.openThemePicker,
      ),
      LocalTerminalExportScrollbackResult() => ShellActionSideEffectPlan(
        kind: ShellActionSideEffectKind.exportScrollback,
        payload: result.export,
      ),
      LocalTerminalApplyLayoutTemplateResult() => ShellActionSideEffectPlan(
        kind: ShellActionSideEffectKind.applyLayoutTemplate,
        payload: result.template,
      ),
      LocalTerminalVisualNoopResult() => const ShellActionSideEffectPlan(
        kind: ShellActionSideEffectKind.none,
      ),
    };
  }
}
