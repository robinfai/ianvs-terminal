part of 'shell_screen.dart';

extension _ShellScreenStateInstantReplay on _ShellScreenState {
  List<_LogicalTerminalRow> _logicalRows(List<terminal.TerminalRow> rows) {
    final logicalRows = <_LogicalTerminalRow>[];
    var start = 0;
    while (start < rows.length) {
      final buffer = StringBuffer(rows[start].text);
      var end = start;
      while (end < rows.length - 1 && rows[end].wrapped) {
        end += 1;
        buffer.write(rows[end].text);
      }
      logicalRows.add(
        _LogicalTerminalRow(
          startRow: rows[start],
          endRow: rows[end],
          text: buffer.toString(),
        ),
      );
      start = end + 1;
    }
    return logicalRows;
  }

  void _recordInstantReplayShellHook(
    terminal.TerminalSessionShellHookEvent event,
  ) {
    final hook = event.hook?.trim().toLowerCase();
    if (hook == null) {
      return;
    }
    final command = _instantReplayMetadata(event.command, 512);
    final cwd = _instantReplayMetadata(event.cwd, 1024);
    switch (hook) {
      case 'preexec':
        final remote =
            command != null && _isInstantReplayRemoteCommand(command);
        if (remote) {
          final activeRemote = _instantReplayRemoteCommands[event.sessionId];
          if (activeRemote != null &&
              _sameInstantReplayCommand(activeRemote, command)) {
            return;
          }
          _instantReplayRemoteCommands[event.sessionId] = command;
        }
        _recordInstantReplaySemantic(
          event.sessionId,
          kind: remote
              ? terminal.TerminalRecordingSemanticKind.remoteSessionStarted
              : terminal.TerminalRecordingSemanticKind.commandStarted,
          command: command,
          cwd: cwd,
        );
      case 'command_finished':
        final remoteCommand = _instantReplayRemoteCommands.remove(
          event.sessionId,
        );
        if (remoteCommand == null &&
            command != null &&
            _isInstantReplayRemoteCommand(command)) {
          return;
        }
        _recordInstantReplaySemantic(
          event.sessionId,
          kind: remoteCommand == null
              ? terminal.TerminalRecordingSemanticKind.commandFinished
              : terminal.TerminalRecordingSemanticKind.remoteSessionFinished,
          command: remoteCommand ?? command,
          cwd: cwd,
          exitCode: event.exitCode,
        );
      case 'precmd.pwd':
        _recordInstantReplaySemantic(
          event.sessionId,
          kind: terminal.TerminalRecordingSemanticKind.directoryChanged,
          cwd: cwd,
          remote: _instantReplayRemoteCommands.containsKey(event.sessionId),
        );
      case 'precmd':
        _recordInstantReplaySemantic(
          event.sessionId,
          kind: terminal.TerminalRecordingSemanticKind.prompt,
          cwd: cwd,
          remote: _instantReplayRemoteCommands.containsKey(event.sessionId),
        );
    }
  }

  void _recordInstantReplayShellContext(
    terminal.TerminalSessionShellContextEvent event,
  ) {
    _recordInstantReplaySemantic(
      event.sessionId,
      kind: terminal.TerminalRecordingSemanticKind.directoryChanged,
      cwd: _instantReplayMetadata(event.cwd, 1024),
      hostname: _instantReplayMetadata(event.hostname, 255),
      remote: _instantReplayRemoteCommands.containsKey(event.sessionId),
    );
  }

  void _recordInstantReplayShellCommand(
    terminal.TerminalSessionShellCommandEvent event,
  ) {
    final eventType = event.eventType?.trim().toLowerCase();
    if (eventType == null) {
      return;
    }
    final command = _instantReplayMetadata(event.command, 512);
    final remoteCommand = _instantReplayRemoteCommands[event.sessionId];
    switch (eventType) {
      case 'command_start':
      case 'command_executed':
        if (command != null && _isInstantReplayRemoteCommand(command)) {
          if (remoteCommand == null) {
            _instantReplayRemoteCommands[event.sessionId] = command;
            _recordInstantReplaySemantic(
              event.sessionId,
              kind: terminal.TerminalRecordingSemanticKind.remoteSessionStarted,
              command: command,
            );
            return;
          }
          if (_sameInstantReplayCommand(remoteCommand, command)) {
            return;
          }
        }
        _recordInstantReplaySemantic(
          event.sessionId,
          kind: terminal.TerminalRecordingSemanticKind.commandStarted,
          command: command,
          remote: remoteCommand != null,
        );
      case 'command_finished':
        if (remoteCommand != null &&
            command != null &&
            _sameInstantReplayCommand(remoteCommand, command)) {
          _instantReplayRemoteCommands.remove(event.sessionId);
          _recordInstantReplaySemantic(
            event.sessionId,
            kind: terminal.TerminalRecordingSemanticKind.remoteSessionFinished,
            command: remoteCommand,
            exitCode: event.exitCode,
          );
          return;
        }
        _recordInstantReplaySemantic(
          event.sessionId,
          kind: terminal.TerminalRecordingSemanticKind.commandFinished,
          command: command,
          exitCode: event.exitCode,
          remote: remoteCommand != null,
        );
      case 'prompt_start':
      case 'mark':
        _recordInstantReplaySemantic(
          event.sessionId,
          kind: terminal.TerminalRecordingSemanticKind.prompt,
          command: command,
          remote: remoteCommand != null,
        );
    }
  }

  void _recordInstantReplaySemantic(
    String sessionId, {
    required terminal.TerminalRecordingSemanticKind kind,
    String? command,
    String? cwd,
    String? hostname,
    int? exitCode,
    bool remote = false,
  }) {
    ref
        .read(instantReplayStoreProvider)
        .recordSemantic(
          sessionId,
          kind: kind,
          command: command,
          cwd: cwd,
          hostname: hostname,
          exitCode: exitCode,
          remote: remote,
        );
  }

  String? _instantReplayMetadata(String? value, int maxLength) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized.length <= maxLength
        ? normalized
        : normalized.substring(0, maxLength);
  }

  bool _isInstantReplayRemoteCommand(String command) {
    return RegExp(
      r'^\s*(?:(?:command|exec|sudo)\s+)?(?:ssh|mosh)(?:\s|$)',
    ).hasMatch(command);
  }

  bool _sameInstantReplayCommand(String left, String right) {
    String normalize(String value) =>
        value.trim().replaceAll(RegExp(r'\s+'), ' ');
    return normalize(left) == normalize(right);
  }

  void _recordInstantReplayFrame(
    String sessionId,
    terminal.TerminalFrameDiff frame, {
    WindowMetrics? windowMetrics,
    bool enrichSessionMetadata = false,
    bool forceCheckpoint = false,
  }) {
    final viewportLogicalSize =
        _scheduledViewportSizes[sessionId] ??
        _committedViewportSizes[sessionId];
    final devicePixelRatio =
        _terminalViewportDevicePixelRatios[sessionId] ??
        windowMetrics?.devicePixelRatio;
    final viewportPixelSize =
        viewportLogicalSize == null || devicePixelRatio == null
        ? null
        : Size(
            viewportLogicalSize.width * devicePixelRatio,
            viewportLogicalSize.height * devicePixelRatio,
          );
    final store = ref.read(instantReplayStoreProvider);
    final recordFrame = forceCheckpoint ? store.checkpoint : store.record;
    recordFrame(
      sessionId,
      frame,
      viewportLogicalSize: viewportLogicalSize,
      viewportPixelSize: viewportPixelSize,
      devicePixelRatio: devicePixelRatio,
      windowContentSize: windowMetrics?.contentSize,
      windowFrameSize: windowMetrics?.frameSize,
    );
    if (enrichSessionMetadata) {
      ref
          .read(instantReplayStoreProvider)
          .enrichSessionMetadata(
            sessionId,
            viewportLogicalSize: viewportLogicalSize,
            viewportPixelSize: viewportPixelSize,
            devicePixelRatio: devicePixelRatio,
            windowContentSize: windowMetrics?.contentSize,
            windowFrameSize: windowMetrics?.frameSize,
          );
    }
  }

  Future<void> _seedInstantReplayFrame(String sessionId) async {
    final sessionController = ref.read(sessionControllerProvider.notifier);
    final frame = sessionController.viewportFor(sessionId).frame;
    final windowMetrics = await WindowBridge.metrics();
    if (!mounted) {
      return;
    }
    _recordInstantReplayFrame(
      sessionId,
      frame,
      windowMetrics: windowMetrics,
      enrichSessionMetadata: true,
      forceCheckpoint: true,
    );
  }

  Future<void> _openInstantReplay(SessionState sessionState) async {
    final activeSessionIdBeforeOpen = sessionState.activeSessionId;
    if (activeSessionIdBeforeOpen == null) {
      return;
    }
    await _seedInstantReplayFrame(activeSessionIdBeforeOpen);
    final store = ref.read(instantReplayStoreProvider);
    if (!mounted) {
      return;
    }
    _mutateState(() {
      _selectedRecordingEntry = null;
      _selectedRecording = null;
      _instantReplayLayoutSession = _InstantReplayLayoutSession(
        sourceSessionId: activeSessionIdBeforeOpen,
        sourceLabel: _instantReplaySourceLabelFor(
          sessionState,
          activeSessionIdBeforeOpen,
        ),
        retentionFrameLimit: store.frameLimit,
        frames: store.framesForReplay(activeSessionIdBeforeOpen),
        semanticEvents: store.semanticsForReplay(activeSessionIdBeforeOpen),
      );
    });
  }

  String _instantReplaySourceLabelFor(
    SessionState sessionState,
    String sessionId,
  ) {
    final tab = _tabForSession(sessionState, sessionId);
    final pane = _paneForSession(sessionState, sessionId);
    final profile = pane == null
        ? null
        : _profileForPane(pane, sessionState.profiles);
    final tabTitle = tab?.title.trim();
    final profileName = profile?.name.trim();
    return [
      if (tabTitle != null && tabTitle.isNotEmpty) tabTitle,
      if (profileName != null && profileName.isNotEmpty) profileName,
      'pane $sessionId',
    ].join(' / ');
  }

  Future<void> _copyInstantReplayVisibleText(String text) async {
    if (text.trim().isEmpty) {
      return;
    }
    await ClipboardBridge.copy(text);
    await _recordPasteHistory(text, PasteHistoryKind.copy);
  }

  void _closeInstantReplayLayout() {
    final sourceSessionId = _instantReplayLayoutSession?.sourceSessionId;
    _mutateState(() {
      _instantReplayLayoutSession = null;
    });
    if (sourceSessionId == null) {
      return;
    }
    _restoreSessionFocus(
      activeSessionIdBeforeOpen: sourceSessionId,
      activeSessionIdAfterClose: ref
          .read(sessionControllerProvider)
          .activeSessionId,
    );
  }

  Future<void> _confirmClearInstantReplayHistory(String sessionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear recent replay history?'),
        content: const Text(
          'Recent activity frames for this pane will be removed from Replay. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear history'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }
    _clearInstantReplayHistory(sessionId);
  }

  void _clearInstantReplayHistory(String sessionId) {
    ref.read(instantReplayStoreProvider).clear(sessionId);
    _mutateState(() {
      final current = _instantReplayLayoutSession;
      if (current == null || current.sourceSessionId != sessionId) {
        return;
      }
      _instantReplayLayoutSession = _InstantReplayLayoutSession(
        sourceSessionId: current.sourceSessionId,
        sourceLabel: current.sourceLabel,
        retentionFrameLimit: current.retentionFrameLimit,
        frames: const <InstantReplayFrame>[],
        semanticEvents: const <InstantReplaySemanticEvent>[],
      );
    });
  }
}
