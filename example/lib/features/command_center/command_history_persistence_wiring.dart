import 'command_center_runtime.dart';
import 'global_command_history_repository.dart';

class CommandHistoryPersistenceWiring {
  const CommandHistoryPersistenceWiring();

  GlobalCommandHistoryDocument documentAfterSessionSync({
    required GlobalCommandHistoryDocument globalHistory,
    required CommandCenterRuntimeState runtimeState,
    required String sessionId,
  }) {
    return globalHistory.mergeSessionEntries(
      runtimeState.history.entriesForSession(sessionId),
    );
  }
}
