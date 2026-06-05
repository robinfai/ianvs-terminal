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

  void _recordInstantReplayFrame(
    String sessionId,
    terminal.TerminalFrameDiff frame, {
    WindowMetrics? windowMetrics,
    bool enrichSessionMetadata = false,
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
    ref
        .read(instantReplayStoreProvider)
        .record(
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
      _instantReplayWorkspaceSession = _InstantReplayWorkspaceSession(
        sourceSessionId: activeSessionIdBeforeOpen,
        sourceLabel: _instantReplaySourceLabelFor(
          sessionState,
          activeSessionIdBeforeOpen,
        ),
        frames: store.framesForReplay(activeSessionIdBeforeOpen),
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

  void _closeInstantReplayWorkspace() {
    final sourceSessionId = _instantReplayWorkspaceSession?.sourceSessionId;
    _mutateState(() {
      _instantReplayWorkspaceSession = null;
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

  void _clearInstantReplayHistory(String sessionId) {
    ref.read(instantReplayStoreProvider).clear(sessionId);
    _mutateState(() {
      final current = _instantReplayWorkspaceSession;
      if (current == null || current.sourceSessionId != sessionId) {
        return;
      }
      _instantReplayWorkspaceSession = _InstantReplayWorkspaceSession(
        sourceSessionId: current.sourceSessionId,
        sourceLabel: current.sourceLabel,
        frames: const <InstantReplayFrame>[],
      );
    });
  }
}
