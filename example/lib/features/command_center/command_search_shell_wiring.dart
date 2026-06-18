import 'command_center_runtime.dart';
import 'command_search_index.dart';
import 'command_search_intents.dart';
import 'command_search_overlay_controller.dart';
import 'global_command_history_repository.dart';

class CommandSearchShellWiring {
  const CommandSearchShellWiring({
    this.policy = const CommandSearchInsertExecutePolicy(),
  });

  final CommandSearchInsertExecutePolicy policy;

  CommandSearchOverlayController controllerFor(
    CommandCenterRuntimeState state, {
    required String sessionId,
    GlobalCommandHistoryDocument globalHistory =
        const GlobalCommandHistoryDocument(),
  }) {
    return CommandSearchOverlayController(
      index: state.searchIndex(globalHistory: globalHistory),
      currentCwd: state.cwdForSession(sessionId),
      currentSessionId: sessionId,
      initialScope: CommandSearchHistoryScope.currentSession,
    );
  }

  CommandSearchTerminalIntent terminalIntentFor(
    CommandSearchOverlayOutput output, {
    required bool readOnly,
  }) {
    return policy.resolve(output, readOnly: readOnly);
  }
}
