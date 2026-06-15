import '../terminal/terminal.dart' as terminal;
import 'command_center_runtime.dart';
import 'shell_hook_lifecycle_adapter.dart';

class CommandCenterShellEventWiringResult {
  const CommandCenterShellEventWiringResult({
    required this.state,
    required this.event,
    required this.ignoredReason,
  });

  final CommandCenterRuntimeState state;
  final CommandLifecycleEvent? event;
  final ShellHookLifecycleIgnoredReason? ignoredReason;

  bool get applied => event != null;
}

class CommandCenterShellEventWiring {
  const CommandCenterShellEventWiring({
    this.adapter = const ShellHookLifecycleAdapter(),
    this.reducer = const CommandCenterRuntimeReducer(),
  });

  final ShellHookLifecycleAdapter adapter;
  final CommandCenterRuntimeReducer reducer;

  CommandCenterShellEventWiringResult applyShellHook(
    CommandCenterRuntimeState state,
    terminal.TerminalSessionShellHookEvent event, {
    DateTime? receivedAt,
  }) {
    final adapted = adapter.adapt(event, receivedAt: receivedAt);
    final lifecycleEvent = adapted.event;
    if (lifecycleEvent == null) {
      return CommandCenterShellEventWiringResult(
        state: state,
        event: null,
        ignoredReason: adapted.ignoredReason,
      );
    }
    return CommandCenterShellEventWiringResult(
      state: reducer.apply(state, lifecycleEvent),
      event: lifecycleEvent,
      ignoredReason: null,
    );
  }
}
