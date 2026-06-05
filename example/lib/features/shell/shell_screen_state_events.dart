part of 'shell_screen.dart';

class ShellCommandBlockShellHookReducer {
  const ShellCommandBlockShellHookReducer._();

  static bool supportsHook(String? hook) {
    return switch (hook?.trim()) {
      'precmd.pwd' || 'cwd' || 'preexec' || 'command_finished' => true,
      _ => false,
    };
  }

  static ShellCommandBlockSnapshot reduce({
    required ShellCommandBlockSnapshot snapshot,
    required CommandBlocksHistoryFeatureFlags flags,
    required String sessionId,
    required String? hook,
    String? command,
    String? cwd,
    int? exitCode,
    int? promptScrollbackOffset,
    List<TerminalShellPromptMark> promptMarks =
        const <TerminalShellPromptMark>[],
    int? viewportEndRow,
  }) {
    if (!flags.enabled || !flags.commandBlocks) {
      return const ShellCommandBlockSnapshot();
    }
    return switch (hook?.trim()) {
      'precmd.pwd' ||
      'cwd' => _cwdChanged(snapshot: snapshot, flags: flags, cwd: cwd),
      'preexec' => _preexec(
        snapshot: snapshot,
        flags: flags,
        sessionId: sessionId,
        command: command,
        cwd: cwd,
        promptScrollbackOffset: promptScrollbackOffset,
        promptMarks: promptMarks,
      ),
      'command_finished' => _commandFinished(
        snapshot: snapshot,
        flags: flags,
        sessionId: sessionId,
        command: command,
        cwd: cwd,
        exitCode: exitCode,
        promptScrollbackOffset: promptScrollbackOffset,
        promptMarks: promptMarks,
        viewportEndRow: viewportEndRow,
      ),
      _ => snapshot,
    };
  }

  static ShellCommandBlockSnapshot _cwdChanged({
    required ShellCommandBlockSnapshot snapshot,
    required CommandBlocksHistoryFeatureFlags flags,
    required String? cwd,
  }) {
    final currentCwd = _trimmedShellHookText(cwd);
    if (currentCwd == null) {
      return snapshot;
    }
    return ShellCommandBlockController.reduce(
      snapshot,
      ShellCwdChangedEvent(currentCwd),
      flags: flags,
    );
  }

  static ShellCommandBlockSnapshot _preexec({
    required ShellCommandBlockSnapshot snapshot,
    required CommandBlocksHistoryFeatureFlags flags,
    required String sessionId,
    required String? command,
    required String? cwd,
    required int? promptScrollbackOffset,
    required List<TerminalShellPromptMark> promptMarks,
  }) {
    if (_trimmedShellHookText(command) == null) {
      return snapshot;
    }
    final marks = _validPromptMarks(promptMarks);
    final promptMark = _lastPromptMark(marks);
    final startRow =
        _validShellHookRow(promptScrollbackOffset) ??
        promptMark?.scrollbackOffset;
    if (startRow == null) {
      return snapshot;
    }
    return ShellCommandBlockController.reduce(
      snapshot,
      ShellPromptMarkEvent(
        id: _promptMarkId(sessionId, startRow),
        row: startRow,
        cwd:
            _trimmedShellHookText(cwd) ??
            _trimmedShellHookText(promptMark?.cwd),
      ),
      flags: flags,
    );
  }

  static ShellCommandBlockSnapshot _commandFinished({
    required ShellCommandBlockSnapshot snapshot,
    required CommandBlocksHistoryFeatureFlags flags,
    required String sessionId,
    required String? command,
    required String? cwd,
    required int? exitCode,
    required int? promptScrollbackOffset,
    required List<TerminalShellPromptMark> promptMarks,
    required int? viewportEndRow,
  }) {
    final commandText = _trimmedShellHookText(command);
    if (commandText == null) {
      return snapshot;
    }

    final plan = _finishPlan(
      snapshot: snapshot,
      promptMarks: promptMarks,
      promptScrollbackOffset: promptScrollbackOffset,
      viewportEndRow: viewportEndRow,
    );
    if (plan == null) {
      return snapshot;
    }

    var next = snapshot;
    if (next.lastPrompt?.row != plan.startRow) {
      next = ShellCommandBlockController.reduce(
        next,
        ShellPromptMarkEvent(
          id: _promptMarkId(sessionId, plan.startRow),
          row: plan.startRow,
          cwd: plan.startCwd,
        ),
        flags: flags,
      );
    }
    next = ShellCommandBlockController.reduce(
      next,
      ShellCommandOutputRangeEvent(
        commandId: _commandBlockId(sessionId, plan.startRow, plan.outputEndRow),
        startRow: plan.startRow + 1,
        endRow: plan.outputEndRow,
      ),
      flags: flags,
    );
    next = ShellCommandBlockController.reduce(
      next,
      ShellCommandFinishedEvent(
        command: commandText,
        cwd: _trimmedShellHookText(cwd),
        exitCode: exitCode,
      ),
      flags: flags,
    );
    final endPromptRow = plan.endPromptRow;
    if (endPromptRow != null) {
      next = ShellCommandBlockController.reduce(
        next,
        ShellPromptMarkEvent(
          id: _promptMarkId(sessionId, endPromptRow),
          row: endPromptRow,
          cwd: plan.endCwd,
        ),
        flags: flags,
      );
    }
    return next;
  }

  static _ShellCommandBlockFinishPlan? _finishPlan({
    required ShellCommandBlockSnapshot snapshot,
    required List<TerminalShellPromptMark> promptMarks,
    required int? promptScrollbackOffset,
    required int? viewportEndRow,
  }) {
    final marks = _validPromptMarks(promptMarks);
    final explicitEndRow = _validShellHookRow(promptScrollbackOffset);
    final viewportEnd = _validShellHookRow(viewportEndRow);
    final snapshotStart = snapshot.lastPrompt;

    if (snapshotStart != null && snapshotStart.row >= 0) {
      final matchingEndMark = _nextPromptMarkAfter(marks, snapshotStart.row);
      final endPromptRow =
          explicitEndRow != null && explicitEndRow > snapshotStart.row
          ? explicitEndRow
          : matchingEndMark?.scrollbackOffset;
      return _finishPlanIfValid(
        startRow: snapshotStart.row,
        startCwd: snapshotStart.cwd,
        outputEndRow: endPromptRow == null ? viewportEnd : endPromptRow - 1,
        endPromptRow: endPromptRow,
        endCwd: matchingEndMark?.cwd,
      );
    }

    if (explicitEndRow != null) {
      final startMark = _lastPromptMarkBefore(marks, explicitEndRow);
      if (startMark != null) {
        return _finishPlanIfValid(
          startRow: startMark.scrollbackOffset,
          startCwd: startMark.cwd,
          outputEndRow: explicitEndRow - 1,
          endPromptRow: explicitEndRow,
          endCwd: null,
        );
      }
    }

    if (marks.length >= 2) {
      final startMark = marks[marks.length - 2];
      final endMark = marks.last;
      return _finishPlanIfValid(
        startRow: startMark.scrollbackOffset,
        startCwd: startMark.cwd,
        outputEndRow: endMark.scrollbackOffset - 1,
        endPromptRow: endMark.scrollbackOffset,
        endCwd: endMark.cwd,
      );
    }

    if (marks.length == 1) {
      final startMark = marks.single;
      return _finishPlanIfValid(
        startRow: startMark.scrollbackOffset,
        startCwd: startMark.cwd,
        outputEndRow: viewportEnd,
      );
    }
    return null;
  }

  static _ShellCommandBlockFinishPlan? _finishPlanIfValid({
    required int startRow,
    required String? startCwd,
    required int? outputEndRow,
    int? endPromptRow,
    String? endCwd,
  }) {
    if (startRow < 0 || outputEndRow == null || outputEndRow < startRow + 1) {
      return null;
    }
    return _ShellCommandBlockFinishPlan(
      startRow: startRow,
      startCwd: startCwd,
      outputEndRow: outputEndRow,
      endPromptRow: endPromptRow,
      endCwd: endCwd,
    );
  }

  static List<TerminalShellPromptMark> _validPromptMarks(
    List<TerminalShellPromptMark> promptMarks,
  ) {
    final marks = promptMarks
        .where((mark) => mark.scrollbackOffset >= 0)
        .toList(growable: false);
    marks.sort((a, b) => a.scrollbackOffset.compareTo(b.scrollbackOffset));
    return marks;
  }

  static TerminalShellPromptMark? _lastPromptMark(
    List<TerminalShellPromptMark> marks,
  ) {
    return marks.isEmpty ? null : marks.last;
  }

  static TerminalShellPromptMark? _lastPromptMarkBefore(
    List<TerminalShellPromptMark> marks,
    int row,
  ) {
    for (final mark in marks.reversed) {
      if (mark.scrollbackOffset < row) {
        return mark;
      }
    }
    return null;
  }

  static TerminalShellPromptMark? _nextPromptMarkAfter(
    List<TerminalShellPromptMark> marks,
    int row,
  ) {
    for (final mark in marks) {
      if (mark.scrollbackOffset > row) {
        return mark;
      }
    }
    return null;
  }

  static int? _validShellHookRow(int? value) {
    if (value == null || value < 0) {
      return null;
    }
    return value;
  }

  static String _commandBlockId(String sessionId, int startRow, int endRow) {
    return '$sessionId:command:$startRow:$endRow';
  }

  static String _promptMarkId(String sessionId, int row) {
    return '$sessionId:prompt:$row';
  }

  static String? _trimmedShellHookText(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }
}

class _ShellCommandBlockFinishPlan {
  const _ShellCommandBlockFinishPlan({
    required this.startRow,
    required this.startCwd,
    required this.outputEndRow,
    this.endPromptRow,
    this.endCwd,
  });

  final int startRow;
  final String? startCwd;
  final int outputEndRow;
  final int? endPromptRow;
  final String? endCwd;
}

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
    if (!_commandBlocksHistoryFeatureFlags.enabled ||
        !_commandBlocksHistoryFeatureFlags.commandBlocks) {
      if (_commandBlockSnapshotsBySession.containsKey(event.sessionId) &&
          mounted) {
        _mutateState(() {
          _commandBlockSnapshotsBySession.remove(event.sessionId);
          _isHistoryPeekOpen = false;
        });
      }
      return;
    }
    if (!ShellCommandBlockShellHookReducer.supportsHook(event.hook)) {
      return;
    }

    final sessionController = ref.read(sessionControllerProvider.notifier);
    final frame = sessionController.viewportFor(event.sessionId).frame;
    final promptMarks = _effectivePromptMarksForSession(
      event.sessionId,
      sessionState: ref.read(sessionControllerProvider),
    );
    final snapshot = ShellCommandBlockShellHookReducer.reduce(
      snapshot:
          _commandBlockSnapshotsBySession[event.sessionId] ??
          const ShellCommandBlockSnapshot(),
      flags: _commandBlocksHistoryFeatureFlags,
      sessionId: event.sessionId,
      hook: event.hook,
      command: event.command,
      cwd: event.cwd,
      exitCode: event.exitCode,
      promptScrollbackOffset: event.promptScrollbackOffset,
      promptMarks: promptMarks,
      viewportEndRow: frame.scrollbackMaxOffset,
    );

    if (!mounted) {
      return;
    }
    _mutateState(() {
      _commandBlockSnapshotsBySession[event.sessionId] = snapshot;
    });
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
