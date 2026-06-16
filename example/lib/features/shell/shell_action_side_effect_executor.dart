import 'shell_action_side_effect_plan.dart';

typedef ShellActionSideEffectHandler = Future<void> Function(Object? payload);

class ShellActionSideEffectHandlers {
  const ShellActionSideEffectHandlers({
    this.updateWorkspace,
    this.updateProductivityState,
    this.scrollToPrompt,
    this.selectCommandOutput,
    this.openRecentDirectory,
    this.commandBlockAction,
    this.sendPaste,
    this.confirmPaste,
    this.blockPaste,
    this.showNotification,
    this.updateHotkeyWindowState,
    this.openThemePicker,
    this.exportScrollback,
    this.applyLayoutTemplate,
  });

  final ShellActionSideEffectHandler? updateWorkspace;
  final ShellActionSideEffectHandler? updateProductivityState;
  final ShellActionSideEffectHandler? scrollToPrompt;
  final ShellActionSideEffectHandler? selectCommandOutput;
  final ShellActionSideEffectHandler? openRecentDirectory;
  final ShellActionSideEffectHandler? commandBlockAction;
  final ShellActionSideEffectHandler? sendPaste;
  final ShellActionSideEffectHandler? confirmPaste;
  final ShellActionSideEffectHandler? blockPaste;
  final ShellActionSideEffectHandler? showNotification;
  final ShellActionSideEffectHandler? updateHotkeyWindowState;
  final ShellActionSideEffectHandler? openThemePicker;
  final ShellActionSideEffectHandler? exportScrollback;
  final ShellActionSideEffectHandler? applyLayoutTemplate;
}

class ShellActionSideEffectExecutor {
  const ShellActionSideEffectExecutor(this.handlers);

  final ShellActionSideEffectHandlers handlers;

  Future<void> execute(ShellActionSideEffectPlan plan) async {
    final handler = switch (plan.kind) {
      ShellActionSideEffectKind.updateWorkspace => handlers.updateWorkspace,
      ShellActionSideEffectKind.updateProductivityState =>
        handlers.updateProductivityState,
      ShellActionSideEffectKind.scrollToPrompt => handlers.scrollToPrompt,
      ShellActionSideEffectKind.selectCommandOutput =>
        handlers.selectCommandOutput,
      ShellActionSideEffectKind.openRecentDirectory =>
        handlers.openRecentDirectory,
      ShellActionSideEffectKind.commandBlockAction =>
        handlers.commandBlockAction,
      ShellActionSideEffectKind.sendPaste => handlers.sendPaste,
      ShellActionSideEffectKind.confirmPaste => handlers.confirmPaste,
      ShellActionSideEffectKind.blockPaste => handlers.blockPaste,
      ShellActionSideEffectKind.showNotification => handlers.showNotification,
      ShellActionSideEffectKind.updateHotkeyWindowState =>
        handlers.updateHotkeyWindowState,
      ShellActionSideEffectKind.openThemePicker => handlers.openThemePicker,
      ShellActionSideEffectKind.exportScrollback => handlers.exportScrollback,
      ShellActionSideEffectKind.applyLayoutTemplate =>
        handlers.applyLayoutTemplate,
      ShellActionSideEffectKind.none => null,
    };

    await handler?.call(plan.payload);
  }
}
