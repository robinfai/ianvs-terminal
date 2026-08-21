part of 'shell_screen.dart';

extension _ShellScreenRecordingLibraryState on _ShellScreenState {
  Future<void> _openRecordingFromPicker() async {
    if (_recordingSelectionLoading) {
      return;
    }
    final sourcePath = await _chooseRecordingFile();
    if (!mounted || sourcePath == null) {
      return;
    }
    await _openRecordingAtPath(sourcePath);
  }

  Future<String?> _chooseRecordingFile() async {
    String? initialDirectory;
    try {
      initialDirectory =
          (await ref
                  .read(localSessionRecordingRepositoryProvider)
                  .ensureRecordingDirectory())
              .absolute
              .path;
    } on Object {
      // The native picker remains usable if the preferred directory cannot
      // be resolved or created.
    }
    if (!mounted) {
      return null;
    }
    return ref.read(shellRecordingFilePickerProvider)(
      initialDirectory: initialDirectory,
    );
  }

  Future<bool> _openRecordingAtPath(String sourcePath) async {
    if (_recordingSelectionLoading) {
      return false;
    }
    _mutateState(() {
      _recordingSelectionLoading = true;
      _recordingLibraryError = null;
    });
    try {
      final opened = await ref
          .read(localSessionRecordingRepositoryProvider)
          .openRecording(sourcePath);
      if (!mounted) {
        return false;
      }
      _mutateState(() {
        _instantReplayLayoutSession = null;
        _selectedRecordingEntry = opened.entry;
        _selectedRecording = opened.recording;
      });
      return true;
    } on Object catch (error) {
      if (mounted) {
        _showShellSnackBar(
          context.l10n.couldNotOpenRecording(error.toString()),
        );
      }
      return false;
    } finally {
      if (mounted) {
        _mutateState(() {
          _recordingSelectionLoading = false;
        });
      }
    }
  }

  Future<void> _loadRecordingLibrary() async {
    if (_recordingLibraryLoading) {
      return;
    }
    _mutateState(() {
      _recordingLibraryLoading = true;
      _recordingLibraryError = null;
    });
    try {
      final entries = await ref
          .read(localSessionRecordingRepositoryProvider)
          .listRecordings();
      if (!mounted) {
        return;
      }
      final selectedPath = _selectedRecordingEntry?.path;
      _mutateState(() {
        _recordingEntries = entries;
        if (selectedPath != null) {
          _selectedRecordingEntry = _entryAtPath(entries, selectedPath);
          if (_selectedRecordingEntry == null) {
            _selectedRecording = null;
          }
        }
      });
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
      }
    }
  }

  Future<void> _selectRecording(LocalSessionRecordingEntry entry) async {
    if (!entry.isReadable || _recordingSelectionLoading) {
      return;
    }
    _mutateState(() {
      _recordingSelectionLoading = true;
      _recordingLibraryError = null;
    });
    try {
      final recording = await ref
          .read(localSessionRecordingRepositoryProvider)
          .load(entry.path);
      if (!mounted) {
        return;
      }
      _mutateState(() {
        _selectedRecordingEntry = entry;
        _selectedRecording = recording;
      });
    } on Object catch (error) {
      if (mounted) {
        _mutateState(() {
          _recordingLibraryError = context.l10n.couldNotOpenRecording(
            error.toString(),
          );
        });
      }
    } finally {
      if (mounted) {
        _mutateState(() {
          _recordingSelectionLoading = false;
        });
      }
    }
  }

  void _closeRecordingReplay() {
    _mutateState(() {
      _selectedRecordingEntry = null;
      _selectedRecording = null;
    });
  }

  Future<void> _importRecording() async {
    final l10n = context.l10n;
    final sourcePath = await _chooseRecordingFile();
    if (!mounted || sourcePath == null) {
      return;
    }
    try {
      final entry = await ref
          .read(localSessionRecordingRepositoryProvider)
          .importRecording(sourcePath: sourcePath);
      await _loadRecordingLibrary();
      if (mounted) {
        await _selectRecording(entry);
        _showShellSnackBar(l10n.recordingImported);
      }
    } on Object catch (error) {
      _showShellSnackBar(l10n.couldNotImportRecording(error.toString()));
    }
  }

  Future<void> _renameRecording(LocalSessionRecordingEntry entry) async {
    final l10n = context.l10n;
    final controller = TextEditingController(text: entry.displayName);
    final nextName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.renameRecording),
        content: TextField(
          key: const Key('recording-rename-field'),
          controller: controller,
          autofocus: true,
          maxLength: 120,
          decoration: InputDecoration(
            labelText: dialogContext.l10n.recordingName,
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(dialogContext.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(dialogContext.l10n.rename),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || nextName == null) {
      return;
    }
    try {
      await ref
          .read(localSessionRecordingRepositoryProvider)
          .renameRecording(entry.path, nextName);
      await _loadRecordingLibrary();
    } on Object catch (error) {
      _showShellSnackBar(l10n.couldNotRenameRecording(error.toString()));
    }
  }

  Future<void> _revealRecording(LocalSessionRecordingEntry entry) async {
    final l10n = context.l10n;
    try {
      await ref.read(shellRecordingRevealProvider)(entry.path);
    } on Object catch (error) {
      _showShellSnackBar(l10n.couldNotRevealRecording(error.toString()));
    }
  }

  Future<void> _exportRecording(LocalSessionRecordingEntry entry) async {
    final l10n = context.l10n;
    final suggestedName = '${_recordingFileName(entry.displayName)}.ndjson';
    final destination = await ref.read(shellRecordingExportPickerProvider)(
      suggestedName,
    );
    if (!mounted || destination == null) {
      return;
    }
    try {
      await ref
          .read(localSessionRecordingRepositoryProvider)
          .exportRecording(entry.path, destination);
      _showShellSnackBar(l10n.recordingExported);
    } on Object catch (error) {
      _showShellSnackBar(l10n.couldNotExportRecording(error.toString()));
    }
  }

  Future<void> _deleteRecording(LocalSessionRecordingEntry entry) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.moveRecordingToTrashQuestion),
        content: Text(
          dialogContext.l10n.recordingRemovedFromSaved(entry.displayName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.appTheme.danger,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.l10n.moveToTrash),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }
    try {
      final repository = ref.read(localSessionRecordingRepositoryProvider);
      final moved = await repository.moveRecordingToTrash(
        entry.path,
        ref.read(shellRecordingTrashProvider),
      );
      if (!moved) {
        throw const FileSystemException('The file could not be moved to Trash');
      }
      await repository.forgetRecording(entry.path);
      if (_selectedRecordingEntry?.path == entry.path) {
        _closeRecordingReplay();
      }
      await _loadRecordingLibrary();
      _showShellSnackBar(l10n.recordingMovedToTrash);
    } on Object catch (error) {
      _showShellSnackBar(l10n.couldNotRemoveRecording(error.toString()));
    }
  }

  LocalSessionRecordingEntry? _entryAtPath(
    List<LocalSessionRecordingEntry> entries,
    String path,
  ) {
    for (final entry in entries) {
      if (entry.path == path) {
        return entry;
      }
    }
    return null;
  }
}

String _recordingFileName(String value) {
  final normalized = value
      .trim()
      .replaceAll(RegExp('[^A-Za-z0-9._ -]+'), '-')
      .replaceAll(RegExp(r'\s+'), '-');
  return normalized.isEmpty ? 'terminal-recording' : normalized;
}
