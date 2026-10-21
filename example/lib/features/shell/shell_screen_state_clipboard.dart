part of 'shell_screen.dart';

extension _ShellScreenStateClipboard on _ShellScreenState {
  bool _selectAllTerminalOutput() {
    if (_shellModalInputBlocked) return false;
    final sessions = ref.read(sessionControllerProvider);
    final sessionId = sessions.activeSessionId;
    if (sessionId == null || _terminalFocusNodes[sessionId]?.hasFocus != true) {
      return false;
    }
    final frame = ref
        .read(sessionControllerProvider.notifier)
        .existingViewportFor(sessionId)
        ?.frame;
    if (frame == null || frame.viewportRows <= 0 || frame.viewportCols <= 0) {
      return false;
    }
    // globalBottomRow also covers source rows hidden by collapsed blocks.
    // It can exceed retained history after eviction; selection_text clamps the
    // range to the retained buffer. Alternate screens have no scrollback.
    final endRow = frame.modes.alternateScreen
        ? frame.viewportRows - 1
        : frame.globalBottomRow ??
              frame.scrollbackMaxOffset + frame.viewportRows - 1;
    _selectionControllers
        .putIfAbsent(sessionId, SelectionController.new)
        .setSelection(
          terminal.TerminalSelection(
            startRow: 0,
            startCol: 0,
            endRow: endRow,
            endCol: frame.viewportCols,
          ),
        );
    return true;
  }

  Future<void> _copySelection(
    SessionController sessionController,
    String sessionId,
    SelectionController selectionController,
  ) async {
    final text = _selectionTextForSession(
      sessionController,
      sessionId,
      selectionController,
    );
    if (text.isEmpty) {
      return;
    }
    await ClipboardBridge.copyWithFeedback(context, text);
  }

  List<_TerminalAnnotation> _annotationsForSession(String sessionId) {
    return [
      for (final annotation in _annotations)
        if (annotation.sessionId == sessionId) annotation,
    ];
  }

  _TerminalAnnotation _addAnnotation({
    required String sessionId,
    required String selectedText,
    required String note,
    String source = 'user',
    int? startRow,
    int? startCol,
    int? endRow,
    int? endCol,
  }) {
    final annotation = _TerminalAnnotation(
      id: 'annotation-${_nextAnnotationId++}',
      sessionId: sessionId,
      selectedText: selectedText.trimRight(),
      note: note.trim(),
      source: source,
      startRow: startRow,
      startCol: startCol,
      endRow: endRow,
      endCol: endCol,
    );
    _mutateState(() {
      _annotations = <_TerminalAnnotation>[
        annotation,
        ..._annotations,
      ].take(_ShellScreenState._annotationLimit).toList(growable: false);
    });
    return annotation;
  }

  void _refreshProtocolAnnotationText(String sessionId) {
    final runtime = ref.read(terminalRuntimeControllerProvider);
    var changed = false;
    final next = <_TerminalAnnotation>[
      for (final annotation in _annotations)
        if (annotation.sessionId == sessionId &&
            annotation.source == 'iterm1337' &&
            annotation.selectedText.isEmpty &&
            annotation.hasTerminalRange &&
            annotation.textRefreshAttempts <
                _ShellScreenState._protocolAnnotationTextRefreshLimit)
          (() {
            final selectedText = runtime
                .selectionText(
                  sessionId,
                  terminal.TerminalSelection(
                    startRow: annotation.startRow!,
                    startCol: annotation.startCol!,
                    endRow: annotation.endRow!,
                    endCol: annotation.endCol!,
                  ),
                  block: false,
                )
                ?.trimRight();
            if (selectedText == null || selectedText.isEmpty) {
              changed = true;
              return annotation.copyWith(
                textRefreshAttempts: annotation.textRefreshAttempts + 1,
              );
            }
            changed = true;
            return annotation.copyWith(
              selectedText: selectedText,
              textRefreshAttempts: annotation.textRefreshAttempts + 1,
            );
          })()
        else
          annotation,
    ];
    if (changed) {
      _mutateState(() => _annotations = next);
    }
  }

  String _selectionTextForSession(
    SessionController sessionController,
    String sessionId,
    SelectionController selectionController,
  ) {
    final frame = sessionController.existingViewportFor(sessionId)?.frame;
    if (frame == null) return '';
    final selection = selectionController.selection;
    if (selection == null) {
      return '';
    }
    if (ref.read(referenceDemoModeProvider)) {
      return selectionController.textForFrame(frame);
    }
    final text = ref
        .read(terminalRuntimeControllerProvider)
        .selectionText(
          sessionId,
          selection,
          block: selectionController.isBlockSelection,
        );
    if (text == null) return selectionController.textForFrame(frame);
    if (text.isNotEmpty) return text;
    // A frame can still display selected text while the backend is refreshing.
    // Only use an empty-reply fallback when the entire selection is visible;
    // otherwise a partial copy would misleadingly report success.
    if (frame.viewportRowForSourceRow(selection.startRow) != null &&
        frame.viewportRowForSourceRow(selection.endRow) != null) {
      return selectionController.textForFrame(frame);
    }
    return '';
  }

  Future<void> _pasteToSession(String sessionId) async {
    final inputEpoch = _manualInputEpoch(sessionId);
    if (_manualInputBlocked(sessionId)) {
      _focusSession(sessionId);
      return;
    }
    final runtime = ref.read(terminalRuntimeControllerProvider);
    if (runtime.viewportFor(sessionId).frame.modes.mimePaste) {
      final sent = await runtime.sendOsc5522PasteEvent(
        sessionId,
        canSend: () => !_manualInputBlocked(sessionId, epoch: inputEpoch),
      );
      if (!sent && mounted) {
        _showShellSnackBar(context.l10n.osc5522PasteDeliveryFailed);
      }
      _focusSession(sessionId);
      return;
    }
    final text = await ClipboardBridge.paste();
    if (text.isEmpty || _manualInputBlocked(sessionId, epoch: inputEpoch)) {
      return;
    }
    final decision = LocalTerminalPasteDecisionResolver.resolve(
      text: text,
      readOnly: _manualInputBlocked(sessionId),
      pastePolicy: _pastePolicy,
      historyPolicy: const LocalTerminalPasteHistoryPolicy(enabled: false),
    );
    switch (decision.kind) {
      case LocalTerminalPasteDecisionKind.blockedReadOnly:
        _focusSession(sessionId);
        return;
      case LocalTerminalPasteDecisionKind.requireConfirmation:
        final confirmed = await _confirmPaste(decision);
        if (!confirmed || _manualInputBlocked(sessionId, epoch: inputEpoch)) {
          _focusSession(sessionId);
          return;
        }
      case LocalTerminalPasteDecisionKind.sendImmediately:
        break;
    }
    await _pasteTextToSession(sessionId, decision.text);
  }

  Future<bool> _confirmPaste(LocalTerminalPasteDecision decision) async {
    final lineCount = _lineCountForPasteConfirmation(decision.text);
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: appDialogAnimation(context),
      builder: (dialogContext) {
        return AlertDialog(
          key: const Key('paste-confirmation-dialog'),
          title: Text(dialogContext.l10n.confirmPaste),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dialogContext.l10n.pasteCharacterLineCount(
                    decision.text.length,
                    lineCount,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  dialogContext.l10n.preview,
                  style: Theme.of(dialogContext).textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: math.min(
                    320,
                    MediaQuery.sizeOf(dialogContext).height * 0.4,
                  ),
                  child: SingleChildScrollView(
                    child: TerminalCodePreview(
                      key: const Key('paste-confirmation-preview'),
                      text: decision.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(dialogContext.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(dialogContext.l10n.paste),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  int _lineCountForPasteConfirmation(String text) {
    if (text.isEmpty) {
      return 0;
    }
    return RegExp(r'\r\n|\r|\n').allMatches(text).length + 1;
  }

  Future<void> _pasteTextToSession(String sessionId, String text) async {
    if (_manualInputBlocked(sessionId)) return;
    final sessionState = ref.read(sessionControllerProvider);
    final sessionController = ref.read(sessionControllerProvider.notifier);
    TerminalPane? activePane;
    for (final tab in sessionState.tabs) {
      final pane = tab.paneFor(sessionId);
      if (pane != null) {
        activePane = pane;
        break;
      }
    }
    final profile = activePane == null
        ? null
        : _profileForPane(activePane, sessionState.profiles);
    final terminalConfig = profile?.toSessionConfig();
    final frame = sessionController.viewportFor(sessionId).frame;
    if (_manualInputBlocked(sessionId)) {
      return;
    }
    final bytes = TerminalInputController.clipboardPasteBytesFor(
      emulation:
          terminalConfig?.emulation ?? terminal.TerminalEmulation.xterm256,
      modes: _pasteModesFor(frame.modes),
      text: text,
    );
    if (bytes.isEmpty) {
      return;
    }
    ref.read(terminalRuntimeControllerProvider).sendInput(sessionId, bytes);
  }

  bool _sendPlainTextToSession(String sessionId, String text) {
    if (text.isEmpty) {
      return false;
    }
    if (_manualInputBlocked(sessionId)) {
      return false;
    }
    ref
        .read(terminalRuntimeControllerProvider)
        .sendInput(sessionId, Uint8List.fromList(utf8.encode(text)));
    _focusSession(sessionId);
    return true;
  }

  String _shellQuotedPath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return "''";
    }
    if (RegExp(r'^[A-Za-z0-9_./:@%+=,-]+$').hasMatch(trimmed)) {
      return trimmed;
    }
    return "'${trimmed.replaceAll("'", r"'\''")}'";
  }
}
