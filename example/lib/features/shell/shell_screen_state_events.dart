part of 'shell_screen.dart';

extension _ShellScreenStateEvents on _ShellScreenState {
  Future<void> _handleNativePasteMenu() async {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId == null) {
      return;
    }
    await _pasteToSession(activeSessionId);
  }

  Future<void> _handleNativeFindMenu(NativeFindAction action) async {
    if (!mounted) {
      return;
    }
    switch (action) {
      case NativeFindAction.next:
        if (!_isSearchOpen) {
          _openSearch();
          return;
        }
        _moveSearchMatch(1);
        return;
      case NativeFindAction.previous:
        if (!_isSearchOpen) {
          _openSearch();
          return;
        }
        _moveSearchMatch(-1);
        return;
      case NativeFindAction.show:
      case NativeFindAction.replace:
      case NativeFindAction.useSelection:
      case NativeFindAction.jumpToSelection:
        _openSearch();
        return;
    }
  }

  void _handleTerminalSessionEvent(terminal.TerminalSessionEvent event) {
    switch (event) {
      case terminal.TerminalSessionFrameEvent(:final sessionId, :final frame):
        final frameSequence =
            (_terminalFrameSequenceBySession[sessionId] ?? 0) + 1;
        _terminalFrameSequenceBySession[sessionId] = frameSequence;
        _recordInstantReplayFrame(sessionId, frame);
        _markNewOutputBadge(sessionId, frame);
        _feedCoprocess(sessionId, frame, frameSequence: frameSequence);
        _runProfileTriggers(sessionId, frame, frameSequence: frameSequence);
        _notifyInactiveActivity(sessionId, frame);
        _refreshSearchMatchesAfterFrame(sessionId, frame);
        _scheduleRenderableSessionSwap(sessionId);
      case terminal.TerminalSessionExitEvent():
        _terminalFrameSequenceBySession.remove(event.sessionId);
        _lastNewOutputFramePreviews.remove(event.sessionId);
        _searchRefreshFrameSignatures.remove(event.sessionId);
        _sessionsSeenForNewOutputBadges.remove(event.sessionId);
        _sessionsWithNewOutput.remove(event.sessionId);
        _triggerMatchesBySession.remove(event.sessionId);
        _commandBlockSnapshotsBySession.remove(event.sessionId);
        _stopCoprocess(event.sessionId);
        _clearCapturedOutput(event.sessionId);
        _notifySessionExit(event.sessionId, event.exitCode);
      case terminal.TerminalSessionBellEvent():
        _notifyBell(event.sessionId);
      case terminal.TerminalSessionShellHookEvent():
        _recordCommandBlockShellHook(event);
        _notifyShellHook(event);
    }
  }

  void _recordCommandBlockShellHook(
    terminal.TerminalSessionShellHookEvent event,
  ) {
    if (event.hook != 'command_finished' ||
        !_commandBlocksHistoryFeatureFlags.enabled ||
        !_commandBlocksHistoryFeatureFlags.commandBlocks) {
      return;
    }

    final promptOffset = event.promptScrollbackOffset;
    if (promptOffset == null || promptOffset < 0) {
      return;
    }

    var snapshot =
        _commandBlockSnapshotsBySession[event.sessionId] ??
        const ShellCommandBlockSnapshot();
    final previousPrompt = snapshot.lastPrompt;
    final command = event.command?.trim() ?? '';
    if (previousPrompt != null &&
        command.isNotEmpty &&
        promptOffset > previousPrompt.row) {
      final outputStartRow = previousPrompt.row + 1;
      final outputEndRow = promptOffset - 1;
      if (outputEndRow >= outputStartRow) {
        snapshot = ShellCommandBlockController.reduce(
          snapshot,
          ShellCommandOutputRangeEvent(
            commandId: _commandBlockIdForShellHook(event),
            startRow: outputStartRow,
            endRow: outputEndRow,
          ),
          flags: _commandBlocksHistoryFeatureFlags,
        );
        snapshot = ShellCommandBlockController.reduce(
          snapshot,
          ShellCommandFinishedEvent(
            command: command,
            cwd: event.cwd,
            exitCode: event.exitCode,
          ),
          flags: _commandBlocksHistoryFeatureFlags,
        );
      }
    }

    snapshot = ShellCommandBlockController.reduce(
      snapshot,
      ShellPromptMarkEvent(
        id: _promptMarkIdForShellHook(event),
        row: promptOffset,
        cwd: event.cwd,
      ),
      flags: _commandBlocksHistoryFeatureFlags,
    );

    if (!mounted) {
      return;
    }
    _mutateState(() {
      _commandBlockSnapshotsBySession[event.sessionId] = snapshot;
    });
  }

  String _commandBlockIdForShellHook(
    terminal.TerminalSessionShellHookEvent event,
  ) {
    return '${event.sessionId}:command:${event.promptScrollbackOffset}';
  }

  String _promptMarkIdForShellHook(
    terminal.TerminalSessionShellHookEvent event,
  ) {
    return '${event.sessionId}:prompt:${event.promptScrollbackOffset}';
  }

  void _notifyInactiveActivity(
    String sessionId,
    terminal.TerminalFrameDiff frame,
  ) {
    if (!_activityNotificationsEnabled) {
      return;
    }
    final preview = _framePreview(frame);
    final hasSeenSession = !_sessionsSeenForActivityNotifications.add(
      sessionId,
    );
    final previousPreview = _lastActivityFramePreviews[sessionId];
    _lastActivityFramePreviews[sessionId] = preview;
    if (hasSeenSession &&
        previousPreview != preview &&
        _notificationSessionIsInactive(sessionId) &&
        preview != null &&
        _activityNotificationAllowed(sessionId)) {
      _sendShellNotification(
        title: 'Activity in ${_sessionTitleForNotification(sessionId)}',
        body: preview,
        identifier: 'ianvs-terminal.activity.$sessionId',
      );
    }
  }

  void _markNewOutputBadge(String sessionId, terminal.TerminalFrameDiff frame) {
    final preview = _framePreview(frame);
    final hasSeenSession = !_sessionsSeenForNewOutputBadges.add(sessionId);
    final previousPreview = _lastNewOutputFramePreviews[sessionId];
    _lastNewOutputFramePreviews[sessionId] = preview;
    if (!hasSeenSession ||
        previousPreview == preview ||
        preview == null ||
        !_sessionTabIsInactive(sessionId)) {
      return;
    }
    if (_sessionsWithNewOutput.contains(sessionId)) {
      return;
    }
    if (!mounted) {
      return;
    }
    _mutateState(() {
      _sessionsWithNewOutput.add(sessionId);
    });
  }

  void _notifySessionExit(String sessionId, int? exitCode) {
    _sendShellNotification(
      title: 'Session ended',
      body:
          '${_sessionTitleForNotification(sessionId)} exited${exitCode == null ? '' : ' with code $exitCode'}.',
      identifier:
          'ianvs-terminal.exit.$sessionId.${DateTime.now().microsecondsSinceEpoch}',
    );
  }

  void _notifyBell(String sessionId) {
    if (!_bellNotificationsEnabled) {
      return;
    }
    _sendShellNotification(
      title: 'Bell in ${_sessionTitleForNotification(sessionId)}',
      body: 'The terminal requested attention.',
      identifier: 'ianvs-terminal.bell.$sessionId',
    );
  }

  void _notifyShellHook(terminal.TerminalSessionShellHookEvent event) {
    if (event.hook != 'command_finished') {
      return;
    }
    if (!_commandFinishedNotificationsEnabled) {
      return;
    }
    final command = event.command;
    final exitCode = event.exitCode;
    _sendShellNotification(
      title: 'Command finished',
      body: [
        if (command != null && command.trim().isNotEmpty) command.trim(),
        if (exitCode != null) 'Exit code $exitCode',
      ].join('\n'),
      identifier:
          'ianvs-terminal.command.${event.sessionId}.${DateTime.now().microsecondsSinceEpoch}',
    );
  }

  Future<void> _loadNotificationPreferences() async {
    final configBootstrap = await _loadNotificationConfig();
    final preferences = LocalTerminalConfigPreferencesAdapter.toAppPreferences(
      configBootstrap.config,
    );
    if (!mounted) {
      return;
    }
    _mutateState(() {
      _notificationConfigSource = configBootstrap.source;
      _notificationLocalConfig = configBootstrap.config;
      _keybindingsConfig = configBootstrap.config.keybindings;
      _clipboardConfig = configBootstrap.config.clipboard;
      _bracketedPastePolicy = configBootstrap.config.paste.bracketedPaste;
      _pastePolicy = _pastePolicyFromConfig(configBootstrap.config.paste);
      _pasteHistoryPolicy = _pasteHistoryPolicyFromConfig(
        configBootstrap.config.paste,
      );
      _pasteHistoryEntries = _pasteHistoryEntries
          .take(_effectivePasteHistoryLimit)
          .toList();
      _commandBlocksHistoryFeatureFlags =
          CommandBlocksHistoryFeatureFlags.fromConfig(
            configBootstrap.config.commandBlocksHistory,
          );
      _commandFinishedNotificationsEnabled =
          preferences.notifications.commandFinished;
      _bellNotificationsEnabled = preferences.notifications.bell;
      _activityNotificationsEnabled = preferences.notifications.activity;
      if (!_commandBlocksHistoryFeatureFlags.enabled ||
          !_commandBlocksHistoryFeatureFlags.commandBlocks) {
        _commandBlockSnapshotsBySession.clear();
        _isHistoryPeekOpen = false;
      }
    });
  }

  Future<LocalTerminalConfigBootstrapResult> _loadNotificationConfig() async {
    try {
      return await ref.read(localTerminalConfigLoaderProvider).load();
    } on Object {
      final legacyPreferences = await ref
          .read(appPreferencesRepositoryProvider)
          .load();
      return LocalTerminalConfigBootstrap.resolve(
        localConfig: null,
        legacyAppPreferences: legacyPreferences,
      );
    }
  }

  Future<void> _saveNotificationPreferences() async {
    final notifications = TerminalAppNotifications(
      commandFinished: _commandFinishedNotificationsEnabled,
      bell: _bellNotificationsEnabled,
      activity: _activityNotificationsEnabled,
    );
    final localConfig = await _loadLocalNotificationConfigForSave();
    if (localConfig != null) {
      final nextConfig = localConfig.copyWith(
        notifications: LocalTerminalNotificationsConfig(
          enabled:
              notifications.commandFinished ||
              notifications.bell ||
              notifications.activity,
          commandFinished: notifications.commandFinished,
          bell: notifications.bell,
          activity: notifications.activity,
        ),
      );
      _notificationConfigSource =
          LocalTerminalConfigBootstrapSource.localConfig;
      _notificationLocalConfig = nextConfig;
      await ref.read(localTerminalConfigRepositoryProvider).save(nextConfig);
      return;
    }

    final repository = ref.read(appPreferencesRepositoryProvider);
    final preferences =
        await repository.load() ?? const TerminalAppPreferencesDocument();
    await repository.save(preferences.copyWith(notifications: notifications));
  }

  Future<LocalTerminalConfigDocument?>
  _loadLocalNotificationConfigForSave() async {
    final repository = ref.read(localTerminalConfigRepositoryProvider);
    if (_notificationConfigSource ==
        LocalTerminalConfigBootstrapSource.localConfig) {
      return await repository.load() ?? _notificationLocalConfig;
    }
    return repository.load();
  }

  LocalTerminalPastePolicy _pastePolicyFromConfig(
    LocalTerminalPasteConfig config,
  ) {
    return LocalTerminalPastePolicy(
      confirmLargePaste: config.confirmLargePaste,
      confirmMultilinePaste: config.confirmMultilinePaste,
      historySize: config.historySize,
    );
  }

  LocalTerminalPasteHistoryPolicy _pasteHistoryPolicyFromConfig(
    LocalTerminalPasteConfig config,
  ) {
    return LocalTerminalPasteHistoryPolicy(
      enabled: config.historySize > 0,
      maxEntries: config.historySize,
    );
  }

  terminal.TerminalFrameModes _pasteModesFor(
    terminal.TerminalFrameModes frameModes,
  ) {
    return switch (_bracketedPastePolicy) {
      LocalTerminalBracketedPastePolicy.auto => frameModes,
      LocalTerminalBracketedPastePolicy.force =>
        const terminal.TerminalFrameModes(bracketedPaste: true),
      LocalTerminalBracketedPastePolicy.plain =>
        terminal.TerminalFrameModes.empty,
    };
  }

  Future<bool> _toggleHotkeyWindowWithFeedback() async {
    final status = await WindowBridge.hotkeyStatus();
    if (status != null && !status.registered) {
      _showHotkeyWindowFailure(status);
      return false;
    }
    try {
      await WindowBridge.toggleHotkeyWindow();
      return true;
    } on PlatformException catch (error) {
      _showHotkeyWindowFailure(status, error: error);
      return false;
    }
  }

  void _showHotkeyWindowFailure(
    HotkeyWindowStatus? status, {
    PlatformException? error,
  }) {
    if (!mounted) {
      return;
    }
    final details = <String>[
      'Hotkey window unavailable',
      if (status != null) 'shortcut: ${status.shortcut}',
      if (status?.errorCode != null) 'error: ${status!.errorCode}',
      if (error?.message != null && error!.message!.trim().isNotEmpty)
        error.message!.trim(),
    ].join(' - ');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(details)));
  }
}
