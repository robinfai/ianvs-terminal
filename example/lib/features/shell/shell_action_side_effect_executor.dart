import 'shell_action_side_effect_plan.dart';

typedef ShellActionSideEffectHandler = Future<void> Function(Object? payload);

class ShellActionSideEffectHandlers {
  const ShellActionSideEffectHandlers({
    this.updateLayout,
    this.updateProductivityState,
    this.scrollToPrompt,
    this.copyCommandOutput,
    this.sendPaste,
    this.confirmPaste,
    this.blockPaste,
    this.exportScrollback,
  });

  final ShellActionSideEffectHandler? updateLayout;
  final ShellActionSideEffectHandler? updateProductivityState;
  final ShellActionSideEffectHandler? scrollToPrompt;
  final ShellActionSideEffectHandler? copyCommandOutput;
  final ShellActionSideEffectHandler? sendPaste;
  final ShellActionSideEffectHandler? confirmPaste;
  final ShellActionSideEffectHandler? blockPaste;
  final ShellActionSideEffectHandler? exportScrollback;
}

class ShellActionSideEffectExecutor {
  const ShellActionSideEffectExecutor(this.handlers);

  final ShellActionSideEffectHandlers handlers;

  Future<void> execute(ShellActionSideEffectPlan plan) async {
    final handler = switch (plan.kind) {
      ShellActionSideEffectKind.updateLayout => handlers.updateLayout,
      ShellActionSideEffectKind.updateProductivityState =>
        handlers.updateProductivityState,
      ShellActionSideEffectKind.scrollToPrompt => handlers.scrollToPrompt,
      ShellActionSideEffectKind.copyCommandOutput => handlers.copyCommandOutput,
      ShellActionSideEffectKind.sendPaste => handlers.sendPaste,
      ShellActionSideEffectKind.confirmPaste => handlers.confirmPaste,
      ShellActionSideEffectKind.blockPaste => handlers.blockPaste,
      ShellActionSideEffectKind.exportScrollback => handlers.exportScrollback,
      ShellActionSideEffectKind.none => null,
    };

    await handler?.call(plan.payload);
  }
}
