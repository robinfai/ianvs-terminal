part of 'shell_screen.dart';

extension _ShellScreenAiObserver on _ShellScreenState {
  // Human UI callbacks, including closures captured before opening AI, must
  // recheck ownership. This is separate from the AI endpoint's read-only test:
  // an observer must not revoke the already approved AI operation.
  int _manualInputEpoch(String sessionId) => _manualInputEpochs[sessionId] ?? 0;

  void _revokeManualInput(String sessionId) {
    _manualInputEpochs[sessionId] = ++_manualInputSerial;
  }

  bool _manualInputBlocked(String sessionId, {int? epoch}) =>
      !mounted ||
      (epoch != null && epoch != _manualInputEpoch(sessionId)) ||
      _openAiSessions.contains(sessionId) ||
      _isSessionReadOnly(sessionId);

  void _observeAiTerminal(String sessionId, {String? targetSessionId}) {
    if (!_openAiSessions.contains(sessionId)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
    _mutateState(() {
      _observedAiTargets[sessionId] = targetSessionId ?? sessionId;
    });
  }

  Widget _presentAiWorkspace(
    String sessionId, {
    required Widget workspace,
    required String targetLabel,
    required terminal.TerminalFontConfig font,
    TerminalViewportColors? colors,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dual =
            defaultTargetPlatform == TargetPlatform.iOS &&
            constraints.maxWidth >= 960 &&
            constraints.maxHeight >= 600;
        final observing = _observedAiTargets.containsKey(sessionId);
        final source = _observedAiTargets[sessionId] ?? sessionId;
        final sessions = ref.read(sessionControllerProvider.notifier);
        final viewport = sessions.existingViewportFor(source);
        final sourcePane = _paneForSession(_sessionState, source);
        final showObserver = dual || observing;
        final showTask = dual || !observing;
        final paneWidth = dual
            ? constraints.maxWidth / 2
            : constraints.maxWidth;
        void back() {
          // Return to the existing task/anchor, without restoring write focus.
          FocusManager.instance.primaryFocus?.unfocus();
          _mutateState(() => _observedAiTargets.remove(sessionId));
        }

        final observer = viewport == null
            ? Center(
                child: TextButton(
                  onPressed: back,
                  child: Text(
                    Localizations.localeOf(context).languageCode == 'zh'
                        ? '原终端已不可用 · 返回任务'
                        : 'Original terminal unavailable · Return to task',
                  ),
                ),
              )
            : TerminalAiObserver(
                key: ValueKey('ai-observer-source-$source'),
                sessionId: source,
                targetLabel: sourcePane?.title ?? targetLabel,
                viewport: viewport,
                colors: colors,
                font: font,
                graphicsCache: sessions.graphicsCacheFor(source),
                readSelectionText: (selection, {required block}) => ref
                    .read(terminalRuntimeControllerProvider)
                    .selectionText(source, selection, block: block),
                onScrollLines: (delta) => ref
                    .read(terminalRuntimeControllerProvider)
                    .scrollViewport(source, delta),
                onScrollToOffset: (offset) => ref
                    .read(terminalRuntimeControllerProvider)
                    .scrollViewportTo(source, offset),
                onBack: dual ? null : back,
                autofocus: observing,
                onTakeOver: sourcePane == null || sourcePane.isExited
                    ? null
                    : () {
                        // Cancellation/revocation happens before returning any
                        // manual input capability. No interrupt byte is sent.
                        _closeAi(sessionId);
                        if (source != sessionId) {
                          _activateSession(sessions, source);
                        }
                      },
              );
        // Keep both element locations stable across rotation and the dual-pane
        // threshold. An offstage task retains selection, draft and scroll state.
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: paneWidth,
              child: Offstage(
                offstage: !showTask,
                child: ExcludeFocus(
                  excluding: !showTask,
                  child: TickerMode(enabled: showTask, child: workspace),
                ),
              ),
            ),
            Positioned(
              left: dual ? paneWidth : 0,
              top: 0,
              bottom: 0,
              width: paneWidth,
              child: Offstage(
                offstage: !showObserver,
                child: ExcludeFocus(
                  excluding: !showObserver,
                  child: TickerMode(enabled: showObserver, child: observer),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
