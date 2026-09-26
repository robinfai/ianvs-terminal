part of 'shell_screen.dart';

extension _ShellScreenRecordingLibraryState on _ShellScreenState {
  Widget _buildRecordingShelf({
    required AppThemeTokens palette,
    required SessionController sessionController,
    required String? activeSessionId,
  }) => _SavedRecordingsShelf(
    palette: palette,
    entries: _recordingEntries,
    mutationPaths: _recordingMutationPaths,
    selectedPath: _selectedRecordingEntry?.path,
    loading: _recordingLibraryLoading,
    selectionLoading: _recordingSelectionLoading,
    error: _recordingLibraryError,
    onRefresh: () => unawaited(_loadRecordingLibrary()),
    onOpenFile: () => unawaited(_openRecordingFromPicker()),
    onSearch: () => unawaited(_searchSavedRecordings()),
    onRetention: () => unawaited(_editRecordingRetention()),
    onKeep: (entry) => unawaited(_setRecordingKeep(entry)),
    onDelete: (entry) => unawaited(_deleteSavedRecording(entry)),
    onRecent: activeSessionId == null
        ? null
        : () => unawaited(_openInstantReplay(_sessionState)),
    onToggleRecording:
        activeSessionId == null ||
            _sessionState.recordingBusySessionIds.contains(activeSessionId)
        ? null
        : () => unawaited(
            _toggleActiveSessionRecording(sessionController, activeSessionId),
          ),
    recording: _sessionState.recordingSessionIds.contains(activeSessionId),
    pendingSave: _sessionState.recordingPendingSaveSessionIds.contains(
      activeSessionId,
    ),
    onSelect: (entry) => unawaited(_selectRecording(entry)),
    onClose: _closeRecordingLibrary,
  );

  Future<void> _openRecordingLibrary({FocusNode? returnFocus}) async {
    if (_recordingShelfOpen) return;
    _recordingReturnFocus = returnFocus ?? FocusManager.instance.primaryFocus;
    _recordingReturnFocus?.unfocus();
    _mutateState(() {
      _invalidateRecordingOpen();
      _recordingShelfOpen = true;
    });
    await _loadRecordingLibrary();
  }

  void _invalidateRecordingOpen() {
    _recordingOpenCancellation?.cancel();
    _recordingOpenCancellation = null;
    _recordingOpenGeneration++;
    _recordingSelectionLoading = false;
  }

  bool _isCurrentRecordingOpen(int generation) =>
      mounted && generation == _recordingOpenGeneration;

  int _beginRecordingOpen() {
    _recordingOpenCancellation?.cancel();
    _recordingOpenCancellation = terminal.RecordingFileCancellation();
    _mutateState(() {
      _recordingOpenGeneration++;
      _recordingSelectionLoading = true;
      _recordingLibraryError = null;
    });
    return _recordingOpenGeneration;
  }

  void _finishRecordingOpen(int generation) {
    if (_isCurrentRecordingOpen(generation)) {
      _mutateState(() => _recordingSelectionLoading = false);
    }
  }

  void _closeRecordingLibrary() {
    final returnFocus = _recordingReturnFocus;
    _recordingReturnFocus = null;
    _mutateState(() {
      _invalidateRecordingOpen();
      _recordingShelfOpen = false;
    });
    if (context.usesMobileNavigation) return;
    final generation = _recordingOpenGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isCurrentRecordingOpen(generation) || _recordingShelfOpen) return;
      if (returnFocus?.context != null && returnFocus!.canRequestFocus) {
        returnFocus.requestFocus();
      } else if (_selectedRecording == null &&
          _instantReplayLayoutSession == null) {
        final sessionId = ref.read(sessionControllerProvider).activeSessionId;
        if (sessionId != null) _focusNodeFor(sessionId).requestFocus();
      }
    });
  }

  Future<void> _openRecordingFromPicker() async {
    if (_recordingSelectionLoading) return;
    final generation = _beginRecordingOpen();
    try {
      final sourcePath = await _chooseRecordingFile(generation);
      if (!_isCurrentRecordingOpen(generation) || sourcePath == null) return;
      await _loadRecordingAtPath(sourcePath, generation);
    } on Object catch (error) {
      _recordingOpenFailed(error, generation);
    } finally {
      _finishRecordingOpen(generation);
    }
  }

  Future<String?> _chooseRecordingFile(int generation) async {
    String? initialDirectory;
    try {
      initialDirectory =
          (await ref
                  .read(sampledRecordingLibraryProvider)
                  .ensureRecordingDirectory())
              .absolute
              .path;
    } on Object {
      // A file can still be opened when the library directory is unavailable.
    }
    if (!_isCurrentRecordingOpen(generation)) return null;
    return ref.read(shellRecordingFilePickerProvider)(
      initialDirectory: initialDirectory,
    );
  }

  Future<bool> _openRecordingAtPath(String sourcePath) async {
    if (_recordingSelectionLoading) return false;
    final generation = _beginRecordingOpen();
    try {
      return await _loadRecordingAtPath(sourcePath, generation);
    } on Object catch (error) {
      _recordingOpenFailed(error, generation);
      return false;
    } finally {
      _finishRecordingOpen(generation);
    }
  }

  Future<bool> _loadRecordingAtPath(
    String sourcePath,
    int generation, {
    Duration? initialPosition,
  }) async {
    if (_selectedRecordingEntry?.path == sourcePath &&
        initialPosition == null) {
      if (_isCurrentRecordingOpen(generation)) {
        _mutateState(() => _recordingShelfOpen = false);
      }
      return true;
    }
    final opened = await ref
        .read(sampledRecordingLibraryProvider)
        .openRecording(sourcePath, cancellation: _recordingOpenCancellation);
    if (!_isCurrentRecordingOpen(generation)) {
      await opened.close();
      return false;
    }
    _showSelectedRecording(
      opened,
      initialPosition: initialPosition ?? Duration.zero,
    );
    return true;
  }

  void _releaseSelectedRecording() {
    final owner = _selectedRecordingOwner;
    _selectedRecordingOwner = null;
    if (owner != null) unawaited(owner.close());
  }

  void _recordingOpenFailed(Object error, int generation) {
    if (!_isCurrentRecordingOpen(generation)) return;
    final message = context.l10n.couldNotOpenRecording(error.toString());
    _mutateState(() => _recordingLibraryError = message);
    _showShellSnackBar(message);
  }

  void _showSelectedRecording(
    SampledOpenedRecording opened, {
    Duration initialPosition = Duration.zero,
  }) {
    _releaseSelectedRecording();
    FocusManager.instance.primaryFocus?.unfocus();
    _mutateState(() {
      _recordingShelfOpen = false;
      _recordingReturnFocus = null;
      _instantReplayLayoutSession = null;
      _selectedRecordingOwner = opened;
      _selectedRecordingEntry = opened.entry;
      _selectedRecording = opened.recording;
      _selectedRecordingInitialPosition = initialPosition;
      _recordingPlaybackGeneration++;
    });
  }

  Future<void> _loadRecordingLibrary() async {
    if (!mounted) return;
    if (_recordingLibraryLoading) {
      _recordingLibraryReloadRequested = true;
      return;
    }
    _mutateState(() {
      _recordingLibraryLoading = true;
      _recordingLibraryError = null;
    });
    try {
      final entries = await ref
          .read(sampledRecordingLibraryProvider)
          .listRecordings();
      if (!mounted) {
        return;
      }
      _mutateState(() => _recordingEntries = entries);
    } on Object catch (error) {
      if (mounted) {
        _mutateState(() {
          _recordingLibraryError = context.l10n.couldNotLoadRecordings(
            error.toString(),
          );
        });
      }
    } finally {
      if (mounted) {
        _mutateState(() {
          _recordingLibraryLoading = false;
        });
        if (_recordingLibraryReloadRequested) {
          _recordingLibraryReloadRequested = false;
          unawaited(_loadRecordingLibrary());
        }
      }
    }
  }

  Future<void> _searchSavedRecordings() async {
    final hit = await showRecordingSearch(
      context: context,
      library: ref.read(sampledRecordingLibraryProvider),
    );
    if (!mounted || hit == null) return;
    final generation = _beginRecordingOpen();
    try {
      await _loadRecordingAtPath(
        hit.path,
        generation,
        initialPosition: hit.offset,
      );
    } on Object catch (error) {
      _recordingOpenFailed(error, generation);
    } finally {
      _finishRecordingOpen(generation);
    }
  }

  Future<void> _editRecordingRetention() async {
    final applied = await showRecordingRetention(
      context: context,
      library: ref.read(sampledRecordingLibraryProvider),
    );
    if (mounted && applied == true) await _loadRecordingLibrary();
  }

  Future<void> _setRecordingKeep(SampledRecordingEntry entry) =>
      _mutateRecording(
        entry,
        () => ref
            .read(sampledRecordingLibraryProvider)
            .setKeep(entry.path, !entry.keep),
      );

  Future<void> _deleteSavedRecording(SampledRecordingEntry entry) async {
    if (_selectedRecordingEntry?.path == entry.path) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.recordingDeleteTitle),
        content: SingleChildScrollView(
          child: Text(context.l10n.recordingDeleteWarning(entry.displayName)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            key: const Key('recording-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await _mutateRecording(
      entry,
      () =>
          ref.read(sampledRecordingLibraryProvider).deleteRecording(entry.path),
    );
  }

  Future<void> _mutateRecording(
    SampledRecordingEntry entry,
    Future<void> Function() action,
  ) async {
    if (_recordingMutationPaths.contains(entry.path)) return;
    _mutateState(() => _recordingMutationPaths.add(entry.path));
    try {
      await action();
      if (mounted) await _loadRecordingLibrary();
    } on Object catch (error) {
      if (mounted) {
        final message = context.l10n.recordingManageError('$error');
        _mutateState(() => _recordingLibraryError = message);
        _showShellSnackBar(message);
      }
    } finally {
      if (mounted) {
        _mutateState(() => _recordingMutationPaths.remove(entry.path));
      }
    }
  }

  Future<void> _selectRecording(SampledRecordingEntry entry) async {
    if (!entry.isReadable || _recordingSelectionLoading) return;
    final generation = _beginRecordingOpen();
    try {
      await _loadRecordingAtPath(entry.path, generation);
    } on Object catch (error) {
      _recordingOpenFailed(error, generation);
    } finally {
      _finishRecordingOpen(generation);
    }
  }

  void _closeRecordingReplay() {
    _releaseSelectedRecording();
    _mutateState(() {
      _invalidateRecordingOpen();
      _selectedRecordingEntry = null;
      _selectedRecording = null;
    });
    if (context.usesMobileNavigation) {
      unawaited(_openRecordingLibrary());
    } else {
      _focusSession(ref.read(sessionControllerProvider).activeSessionId);
    }
  }
}
