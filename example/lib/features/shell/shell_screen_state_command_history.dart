part of 'shell_screen.dart';

extension _ShellScreenStateCommandHistory on _ShellScreenState {
  Future<void> _loadGlobalCommandHistory() async {
    final loaded = await _globalCommandHistoryRepository.load();
    if (!mounted) {
      return;
    }
    _mutateState(() {
      _globalCommandHistory = loaded;
      _commandSearchOverlayController = null;
    });
  }

  void _scheduleGlobalCommandHistorySave(String sessionId) {
    _globalCommandHistorySaveChain = _globalCommandHistorySaveChain
        .then<void>((_) => _saveGlobalCommandHistoryForSession(sessionId))
        .catchError((Object _) {});
  }

  Future<void> _saveGlobalCommandHistoryForSession(String sessionId) async {
    await _globalCommandHistoryLoad;
    final nextHistory = _commandHistoryPersistenceWiring
        .documentAfterSessionSync(
          globalHistory: _globalCommandHistory,
          runtimeState: _commandCenterRuntime,
          sessionId: sessionId,
        );
    _globalCommandHistory = nextHistory;
    await _globalCommandHistoryRepository.save(nextHistory);
    if (!mounted) {
      return;
    }
    _mutateState(() {
      _commandSearchOverlayController = null;
    });
  }
}
