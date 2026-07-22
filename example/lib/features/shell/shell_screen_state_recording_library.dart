part of 'shell_screen.dart';

extension _ShellScreenRecordingLibraryState on _ShellScreenState {
  Future<void> _toggleRecordingLibrary() async {
    _mutateState(() {
      _recordingsShelfOpen = !_recordingsShelfOpen;
    });
    if (_recordingsShelfOpen) {
      await _loadRecordingLibrary();
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
          _recordingLibraryError = 'Could not load recordings: $error';
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
          _recordingLibraryError = 'Could not open recording: $error';
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
    final sourcePath = await ref.read(shellRecordingFilePickerProvider)();
    if (!mounted || sourcePath == null) {
      return;
    }
    try {
      final workspaceId = ref
          .read(sessionControllerProvider.notifier)
          .activeWorkspaceIdentity
          .id;
      final entry = await ref
          .read(localSessionRecordingRepositoryProvider)
          .importRecording(sourcePath: sourcePath, workspaceId: workspaceId);
      await _loadRecordingLibrary();
      if (mounted) {
        await _selectRecording(entry);
        _showShellSnackBar('Recording imported');
      }
    } on Object catch (error) {
      _showShellSnackBar('Could not import recording: $error');
    }
  }

  Future<void> _renameRecording(LocalSessionRecordingEntry entry) async {
    final controller = TextEditingController(text: entry.displayName);
    final nextName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename recording'),
        content: TextField(
          key: const Key('recording-rename-field'),
          controller: controller,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'Recording name'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Rename'),
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
      _showShellSnackBar('Could not rename recording: $error');
    }
  }

  Future<void> _revealRecording(LocalSessionRecordingEntry entry) async {
    try {
      await ref.read(shellRecordingRevealProvider)(entry.path);
    } on Object catch (error) {
      _showShellSnackBar('Could not reveal recording: $error');
    }
  }

  Future<void> _exportRecording(LocalSessionRecordingEntry entry) async {
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
      _showShellSnackBar('Recording exported');
    } on Object catch (error) {
      _showShellSnackBar('Could not export recording: $error');
    }
  }

  Future<void> _deleteRecording(LocalSessionRecordingEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Move recording to Trash?'),
        content: Text(
          '“${entry.displayName}” will be removed from Saved Recordings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.appTheme.danger,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Move to Trash'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }
    try {
      final moved = await ref.read(shellRecordingTrashProvider)(entry.path);
      if (!moved) {
        throw const FileSystemException('The file could not be moved to Trash');
      }
      await ref
          .read(localSessionRecordingRepositoryProvider)
          .forgetRecording(entry.path);
      ref
          .read(sessionControllerProvider.notifier)
          .detachRecordingPath(entry.path);
      if (_selectedRecordingEntry?.path == entry.path) {
        _closeRecordingReplay();
      }
      await _loadRecordingLibrary();
      _showShellSnackBar('Recording moved to Trash');
    } on Object catch (error) {
      _showShellSnackBar('Could not remove recording: $error');
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
      .replaceAll(RegExp(r'[^A-Za-z0-9._ -]+'), '-')
      .replaceAll(RegExp(r'\s+'), '-');
  return normalized.isEmpty ? 'terminal-recording' : normalized;
}
