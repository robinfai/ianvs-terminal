import 'shell_action_side_effect_executor.dart';
import 'shell_action_side_effect_plan.dart';

class ShellActionSideEffectCall {
  const ShellActionSideEffectCall({required this.kind, this.payload});

  final ShellActionSideEffectKind kind;
  final Object? payload;
}

class ShellActionTestHarness {
  ShellActionTestHarness();

  final List<ShellActionSideEffectCall> calls = <ShellActionSideEffectCall>[];

  ShellActionSideEffectExecutor executor() {
    return ShellActionSideEffectExecutor(
      ShellActionSideEffectHandlers(
        updateLayout: _record(ShellActionSideEffectKind.updateLayout),
        updateProductivityState: _record(
          ShellActionSideEffectKind.updateProductivityState,
        ),
        scrollToPrompt: _record(ShellActionSideEffectKind.scrollToPrompt),
        copyCommandOutput: _record(ShellActionSideEffectKind.copyCommandOutput),
        sendPaste: _record(ShellActionSideEffectKind.sendPaste),
        confirmPaste: _record(ShellActionSideEffectKind.confirmPaste),
        blockPaste: _record(ShellActionSideEffectKind.blockPaste),
        exportScrollback: _record(ShellActionSideEffectKind.exportScrollback),
      ),
    );
  }

  ShellActionSideEffectHandler _record(ShellActionSideEffectKind kind) {
    return (payload) async {
      calls.add(ShellActionSideEffectCall(kind: kind, payload: payload));
    };
  }
}
