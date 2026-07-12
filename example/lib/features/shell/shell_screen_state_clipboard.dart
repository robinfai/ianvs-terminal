part of 'shell_screen.dart';

extension _ShellScreenStateClipboard on _ShellScreenState {
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
    await ClipboardBridge.copy(text);
    await _recordPasteHistory(text, PasteHistoryKind.copy);
  }

  Future<void> _loadPasteHistory() async {
    final document = await ref.read(pasteHistoryRepositoryProvider).load();
    if (!mounted) {
      return;
    }
    final loadedEntries = document?.entries ?? const <PasteHistoryEntry>[];
    _mutateState(() {
      _pasteHistoryLoaded = true;
      _pasteHistoryPersistToDisk = document != null;
      _pasteHistoryEntries = _mergePasteHistoryEntries(
        _pasteHistoryEntries,
        loadedEntries,
      );
    });
  }

  Future<void> _recordPasteHistory(String text, PasteHistoryKind kind) async {
    final normalizedText = text.trimRight();
    if (normalizedText.trim().isEmpty) {
      return;
    }
    final nextEntry = PasteHistoryEntry(
      text: normalizedText,
      kind: kind,
      createdAt: DateTime.now(),
    );
    final nextEntries = <PasteHistoryEntry>[
      nextEntry,
      for (final entry in _pasteHistoryEntries)
        if (entry.text != normalizedText) entry,
    ].take(_effectivePasteHistoryLimit).toList();

    if (mounted) {
      _mutateState(() {
        _pasteHistoryEntries = nextEntries;
        _pasteHistoryLoaded = true;
      });
    } else {
      _pasteHistoryEntries = nextEntries;
    }

    if (_pasteHistoryPersistToDisk) {
      await ref
          .read(pasteHistoryRepositoryProvider)
          .save(PasteHistoryDocument(entries: nextEntries));
    }
  }

  int get _effectivePasteHistoryLimit {
    if (_pasteHistoryPolicy.maxEntries <= 0) {
      return 0;
    }
    return math.min(
      _ShellScreenState._pasteHistoryLimit,
      _pasteHistoryPolicy.maxEntries,
    );
  }

  List<PasteHistoryEntry> _mergePasteHistoryEntries(
    List<PasteHistoryEntry> leading,
    List<PasteHistoryEntry> trailing,
  ) {
    final seenTexts = <String>{};
    return <PasteHistoryEntry>[
      for (final entry in [...leading, ...trailing])
        if (entry.text.trim().isNotEmpty && seenTexts.add(entry.text)) entry,
    ].take(_effectivePasteHistoryLimit).toList();
  }

  Future<void> _setPasteHistoryPersistence(bool enabled) async {
    _mutateState(() {
      _pasteHistoryPersistToDisk = enabled;
      _pasteHistoryLoaded = true;
    });
    final repository = ref.read(pasteHistoryRepositoryProvider);
    if (enabled) {
      await repository.save(
        PasteHistoryDocument(entries: _pasteHistoryEntries),
      );
    } else {
      await repository.clearDiskHistory();
    }
  }

  Future<void> _clearPasteHistory() async {
    _mutateState(() {
      _pasteHistoryEntries = const [];
      _pasteHistoryLoaded = true;
    });
    if (_pasteHistoryPersistToDisk) {
      await ref
          .read(pasteHistoryRepositoryProvider)
          .save(const PasteHistoryDocument());
    }
  }

  List<_TerminalAnnotation> _annotationsForSession(String sessionId) {
    return [
      for (final annotation in _annotations)
        if (annotation.sessionId == sessionId) annotation,
    ];
  }

  Future<void> _openAnnotations(
    SessionController sessionController,
    String sessionId,
    SelectionController selectionController,
  ) async {
    final selectedText = _selectionTextForSession(
      sessionController,
      sessionId,
      selectionController,
    ).trimRight();
    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: animationsEnabled
          ? null
          : AnimationStyle.noAnimation,
      builder: (sheetContext) {
        return _AnnotationsSheet(
          entries: _annotationsForSession(sessionId),
          selectedText: selectedText,
          onAdd: (note) => _addAnnotation(
            sessionId: sessionId,
            selectedText: selectedText,
            note: note,
          ),
          onRemove: _removeAnnotation,
        );
      },
    );
  }

  _TerminalAnnotation _addAnnotation({
    required String sessionId,
    required String selectedText,
    required String note,
  }) {
    final annotation = _TerminalAnnotation(
      id: 'annotation-${_nextAnnotationId++}',
      sessionId: sessionId,
      selectedText: selectedText.trimRight(),
      note: note.trim(),
    );
    _mutateState(() {
      _annotations = <_TerminalAnnotation>[
        annotation,
        ..._annotations,
      ].take(_ShellScreenState._annotationLimit).toList(growable: false);
    });
    return annotation;
  }

  void _removeAnnotation(String annotationId) {
    _mutateState(() {
      _annotations = [
        for (final annotation in _annotations)
          if (annotation.id != annotationId) annotation,
      ];
    });
  }

  List<_CapturedOutputEntry> _capturedOutputForSession(String sessionId) {
    return [
      for (final entry in _capturedOutputEntries)
        if (entry.sessionId == sessionId) entry,
    ];
  }

  Future<void> _openCapturedOutput(String sessionId) async {
    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: animationsEnabled
          ? null
          : AnimationStyle.noAnimation,
      builder: (sheetContext) {
        return _CapturedOutputSheet(
          entries: _capturedOutputForSession(sessionId),
          onClear: () => _clearCapturedOutput(sessionId),
          onCopy: (text) => unawaited(ClipboardBridge.copy(text)),
        );
      },
    );
  }

  void _clearCapturedOutput(String sessionId) {
    if (!mounted) {
      _capturedOutputEntries = [
        for (final entry in _capturedOutputEntries)
          if (entry.sessionId != sessionId) entry,
      ];
      return;
    }
    _mutateState(() {
      _capturedOutputEntries = [
        for (final entry in _capturedOutputEntries)
          if (entry.sessionId != sessionId) entry,
      ];
    });
  }

  String _selectionTextForSession(
    SessionController sessionController,
    String sessionId,
    SelectionController selectionController,
  ) {
    final frame = sessionController.viewportFor(sessionId).frame;
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
    return text ?? selectionController.textForFrame(frame);
  }

  void _enterCopyMode(
    SessionController sessionController,
    String sessionId,
    SelectionController selectionController,
  ) {
    final frame = sessionController.viewportFor(sessionId).frame;
    if (frame.viewportRows <= 0 || frame.viewportCols <= 0) {
      return;
    }

    final row = (frame.viewportStartRow + frame.cursor.row)
        .clamp(
          frame.viewportStartRow,
          frame.viewportStartRow + frame.viewportRows - 1,
        )
        .toInt();
    final cursorCol = frame.cursor.col.clamp(0, frame.viewportCols).toInt();
    final anchorCol = cursorCol >= frame.viewportCols
        ? (frame.viewportCols - 1).clamp(0, frame.viewportCols).toInt()
        : cursorCol;
    final extentCol = (anchorCol + 1).clamp(0, frame.viewportCols).toInt();

    _mutateState(() {
      _isCopyModeOpen = true;
      _copyModeSessionId = sessionId;
      _isSearchOpen = false;
      _resetAutocompleteState();
      _resetAutoComposerState(clearText: true);
      _copyModeAnchorRow = row;
      _copyModeAnchorCol = anchorCol;
      _copyModeExtentRow = row;
      _copyModeExtentCol = extentCol;
    });
    selectionController.setSelection(
      terminal.TerminalSelection(
        startRow: row,
        startCol: anchorCol,
        endRow: row,
        endCol: extentCol,
      ),
    );
    _focusSession(sessionId);
  }

  KeyEventResult? _handleCopyModeKey(
    KeyEvent event,
    SessionController sessionController,
    String? activeSessionId,
  ) {
    if (!_isCopyModeOpen) {
      return null;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.handled;
    }
    if (activeSessionId == null) {
      _closeCopyMode(null);
      return KeyEventResult.handled;
    }
    final copyModeSessionId = _copyModeSessionId;
    if (copyModeSessionId == null || copyModeSessionId != activeSessionId) {
      _closeCopyMode(
        copyModeSessionId == null
            ? null
            : _selectionControllers[copyModeSessionId],
      );
      return null;
    }
    final selectionController = _selectionControllers[copyModeSessionId];
    if (selectionController == null) {
      _closeCopyMode(null);
      return KeyEventResult.handled;
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        _closeCopyMode(selectionController);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        unawaited(
          _copySelection(
            sessionController,
            copyModeSessionId,
            selectionController,
          ),
        );
        _closeCopyMode(selectionController);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _moveCopyModeSelection(
          sessionController,
          copyModeSessionId,
          selectionController,
          columnDelta: -1,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _moveCopyModeSelection(
          sessionController,
          copyModeSessionId,
          selectionController,
          columnDelta: 1,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _moveCopyModeSelection(
          sessionController,
          copyModeSessionId,
          selectionController,
          rowDelta: -1,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _moveCopyModeSelection(
          sessionController,
          copyModeSessionId,
          selectionController,
          rowDelta: 1,
        );
        return KeyEventResult.handled;
      default:
        return KeyEventResult.handled;
    }
  }

  void _moveCopyModeSelection(
    SessionController sessionController,
    String sessionId,
    SelectionController selectionController, {
    int rowDelta = 0,
    int columnDelta = 0,
  }) {
    final anchorRow = _copyModeAnchorRow;
    final anchorCol = _copyModeAnchorCol;
    final extentRow = _copyModeExtentRow;
    final extentCol = _copyModeExtentCol;
    if (anchorRow == null ||
        anchorCol == null ||
        extentRow == null ||
        extentCol == null) {
      return;
    }
    final frame = sessionController.viewportFor(sessionId).frame;
    final minRow = frame.viewportStartRow;
    final maxRow = frame.viewportStartRow + frame.viewportRows - 1;
    final nextRow = (extentRow + rowDelta).clamp(minRow, maxRow).toInt();
    final nextCol = (extentCol + columnDelta)
        .clamp(0, frame.viewportCols)
        .toInt();

    _mutateState(() {
      _copyModeExtentRow = nextRow;
      _copyModeExtentCol = nextCol;
    });
    selectionController.setSelection(
      terminal.TerminalSelection(
        startRow: anchorRow,
        startCol: anchorCol,
        endRow: nextRow,
        endCol: nextCol,
      ),
    );
  }

  void _closeCopyMode(SelectionController? selectionController) {
    _mutateState(() {
      _resetCopyModeState();
    });
    selectionController?.clear();
    _focusSession(ref.read(sessionControllerProvider).activeSessionId);
  }

  void _resetCopyModeState() {
    _isCopyModeOpen = false;
    _copyModeSessionId = null;
    _copyModeAnchorRow = null;
    _copyModeAnchorCol = null;
    _copyModeExtentRow = null;
    _copyModeExtentCol = null;
  }

  Future<void> _pasteToSession(String sessionId) async {
    if (_isSessionReadOnly(sessionId)) {
      _focusSession(sessionId);
      return;
    }
    final runtime = ref.read(terminalRuntimeControllerProvider);
    if (runtime.viewportFor(sessionId).frame.modes.mimePaste) {
      final sent = await runtime.sendOsc5522PasteEvent(sessionId);
      if (!sent && mounted) {
        _showShellSnackBar('OSC 5522 paste event could not be delivered');
      }
      _focusSession(sessionId);
      return;
    }
    final text = await ClipboardBridge.paste();
    if (text.isEmpty) {
      return;
    }
    final decision = LocalTerminalPasteDecisionResolver.resolve(
      text: text,
      readOnly: _isSessionReadOnly(sessionId),
      pastePolicy: _pastePolicy,
      historyPolicy: _pasteHistoryPolicy,
    );
    switch (decision.kind) {
      case LocalTerminalPasteDecisionKind.blockedReadOnly:
        _focusSession(sessionId);
        return;
      case LocalTerminalPasteDecisionKind.requireConfirmation:
        final confirmed = await _confirmPaste(decision);
        if (!confirmed) {
          _focusSession(sessionId);
          return;
        }
      case LocalTerminalPasteDecisionKind.sendImmediately:
        break;
    }
    await _pasteTextToSession(sessionId, decision.text);
    if (decision.captureHistory) {
      await _recordPasteHistory(decision.text, PasteHistoryKind.paste);
    }
  }

  Future<bool> _confirmPaste(LocalTerminalPasteDecision decision) async {
    final lineCount = _lineCountForPasteConfirmation(decision.text);
    final preview = _pasteConfirmationPreview(decision.text);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          key: const Key('paste-confirmation-dialog'),
          title: const Text('Confirm paste'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paste ${decision.text.length} characters across $lineCount lines?',
              ),
              const SizedBox(height: 12),
              Text(
                'Preview',
                style: Theme.of(
                  dialogContext,
                ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 140),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(dialogContext)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(dialogContext).colorScheme.outlineVariant,
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      preview,
                      key: const Key('paste-confirmation-preview'),
                      style: Theme.of(
                        dialogContext,
                      ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Paste'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  String _pasteConfirmationPreview(String text) {
    const maxLines = 6;
    const maxCharacters = 240;
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    final previewLines = lines.take(maxLines).toList();
    var preview = previewLines.join('\n');
    var truncated = lines.length > maxLines;
    if (preview.length > maxCharacters) {
      preview = preview.substring(0, maxCharacters).trimRight();
      truncated = true;
    }
    return truncated ? '$preview\n...' : preview;
  }

  int _lineCountForPasteConfirmation(String text) {
    if (text.isEmpty) {
      return 0;
    }
    return RegExp(r'\r\n|\r|\n').allMatches(text).length + 1;
  }

  Future<void> _pasteTextToSession(String sessionId, String text) async {
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
    if (_isSessionReadOnly(sessionId)) {
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
    if (_isSessionReadOnly(sessionId)) {
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
