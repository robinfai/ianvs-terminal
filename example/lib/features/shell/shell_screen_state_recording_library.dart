part of 'shell_screen.dart';

extension _ShellScreenRecordingLibraryState on _ShellScreenState {
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

  Future<bool> _loadRecordingAtPath(String sourcePath, int generation) async {
    if (_selectedRecordingEntry?.path == sourcePath) {
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
    _showSelectedRecording(opened);
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

  void _showSelectedRecording(SampledOpenedRecording opened) {
    _releaseSelectedRecording();
    FocusManager.instance.primaryFocus?.unfocus();
    _mutateState(() {
      _recordingShelfOpen = false;
      _recordingReturnFocus = null;
      _instantReplayLayoutSession = null;
      _selectedRecordingOwner = opened;
      _selectedRecordingEntry = opened.entry;
      _selectedRecording = opened.recording;
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
