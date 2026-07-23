part of 'shell_screen.dart';

enum _RecordingLibraryAction { rename, reveal, export, delete }

enum _RecordingLibrarySort { newest, oldest, name }

class _RecordingLibraryLayout extends StatelessWidget {
  const _RecordingLibraryLayout({
    required this.palette,
    required this.shelfOpen,
    required this.layout,
    required this.shelf,
  });

  final AppThemeTokens palette;
  final bool shelfOpen;
  final Widget layout;
  final Widget shelf;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 960;
        if (!shelfOpen) {
          return layout;
        }
        if (compact) {
          return Stack(
            children: [
              Positioned.fill(child: layout),
              Positioned.fill(
                child: ColoredBox(
                  color: palette.inactiveScrim.withValues(alpha: 0.58),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  key: const Key('saved-recordings-shelf-compact'),
                  width: math.min(400, constraints.maxWidth),
                  child: shelf,
                ),
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: layout),
            SizedBox(width: 372, child: shelf),
          ],
        );
      },
    );
  }
}

class _SavedRecordingsShelf extends StatelessWidget {
  const _SavedRecordingsShelf({
    required this.palette,
    required this.entries,
    required this.selectedPath,
    required this.searchQuery,
    required this.sort,
    required this.playableOnly,
    required this.loading,
    required this.selectionLoading,
    required this.error,
    required this.onSearchChanged,
    required this.onSortChanged,
    required this.onPlayableOnlyChanged,
    required this.onRefresh,
    required this.onImport,
    required this.onSelect,
    required this.onRename,
    required this.onReveal,
    required this.onExport,
    required this.onDelete,
    required this.onClose,
  });

  final AppThemeTokens palette;
  final List<LocalSessionRecordingEntry> entries;
  final String? selectedPath;
  final String searchQuery;
  final _RecordingLibrarySort sort;
  final bool playableOnly;
  final bool loading;
  final bool selectionLoading;
  final String? error;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_RecordingLibrarySort> onSortChanged;
  final ValueChanged<bool> onPlayableOnlyChanged;
  final VoidCallback onRefresh;
  final VoidCallback onImport;
  final ValueChanged<LocalSessionRecordingEntry> onSelect;
  final ValueChanged<LocalSessionRecordingEntry> onRename;
  final ValueChanged<LocalSessionRecordingEntry> onReveal;
  final ValueChanged<LocalSessionRecordingEntry> onExport;
  final ValueChanged<LocalSessionRecordingEntry> onDelete;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final grouped = _groupedEntries();
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Saved terminal recordings',
      child: DecoratedBox(
        key: const Key('saved-recordings-shelf'),
        decoration: BoxDecoration(
          color: palette.chrome,
          border: Border(left: BorderSide(color: palette.border)),
          boxShadow: palette.elevation.floating,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Saved Recordings',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const Key('recording-library-import'),
                    onPressed: onImport,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(82, 30),
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                    ),
                    icon: const Icon(Icons.file_download_outlined, size: 16),
                    label: const Text('Import…'),
                  ),
                  Semantics(
                    label: 'Refresh recordings',
                    button: true,
                    child: IconButton(
                      tooltip: 'Refresh recordings',
                      onPressed: loading ? null : onRefresh,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                    ),
                  ),
                  Semantics(
                    label: 'Close Saved Recordings',
                    button: true,
                    child: IconButton(
                      key: const Key('saved-recordings-shelf-close'),
                      tooltip: 'Close Saved Recordings',
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('recording-library-search'),
                      onChanged: onSearchChanged,
                      decoration: InputDecoration(
                        hintText: 'Search recordings',
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        isDense: true,
                        filled: true,
                        fillColor: palette.panel,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            palette.radius.md,
                          ),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Semantics(
                    label: playableOnly
                        ? 'Filter: Playable only'
                        : 'Filter: All recordings',
                    button: true,
                    child: PopupMenuButton<bool>(
                      tooltip: 'Filter recordings',
                      initialValue: playableOnly,
                      onSelected: onPlayableOnlyChanged,
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: false,
                          child: Text('All recordings'),
                        ),
                        PopupMenuItem(
                          value: true,
                          child: Text('Playable only'),
                        ),
                      ],
                      icon: Icon(
                        Icons.filter_list_rounded,
                        color: playableOnly
                            ? palette.accent
                            : palette.textSubtle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
              child: Row(
                children: [
                  const Spacer(),
                  Semantics(
                    label: 'Sort: ${_recordingSortLabel(sort)}',
                    button: true,
                    child: PopupMenuButton<_RecordingLibrarySort>(
                      tooltip: 'Recording sort order',
                      initialValue: sort,
                      onSelected: onSortChanged,
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: _RecordingLibrarySort.newest,
                          child: Text('Newest'),
                        ),
                        PopupMenuItem(
                          value: _RecordingLibrarySort.oldest,
                          child: Text('Oldest'),
                        ),
                        PopupMenuItem(
                          value: _RecordingLibrarySort.name,
                          child: Text('Name'),
                        ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _recordingSortLabel(sort),
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(color: palette.textMuted),
                            ),
                            const SizedBox(width: 3),
                            Icon(
                              Icons.arrow_drop_down_rounded,
                              size: 17,
                              color: palette.textSubtle,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (loading) const LinearProgressIndicator(minHeight: 2),
            if (error case final String message)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                child: Text(
                  message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.danger),
                ),
              ),
            Expanded(
              child: grouped.isEmpty && !loading
                  ? _RecordingLibraryEmptyState(
                      palette: palette,
                      hasSearch: searchQuery.trim().isNotEmpty,
                      onImport: onImport,
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                      itemCount: 1,
                      itemBuilder: (context, index) {
                        return _RecordingGroup(
                          palette: palette,
                          title: 'All Recordings',
                          entries: grouped,
                          selectedPath: selectedPath,
                          selectionLoading: selectionLoading,
                          onSelect: onSelect,
                          onRename: onRename,
                          onReveal: onReveal,
                          onExport: onExport,
                          onDelete: onDelete,
                        );
                      },
                    ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: palette.panel.withValues(alpha: 0.58),
                border: Border(top: BorderSide(color: palette.border)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 15,
                          color: palette.textSubtle,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            selectedPath == null
                                ? 'Recordings may contain sensitive terminal output.'
                                : 'This recording may contain sensitive output.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: palette.textSubtle),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          '${entries.length} ${entries.length == 1 ? 'recording' : 'recordings'}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: palette.textSubtle),
                        ),
                        const Spacer(),
                        Text(
                          _formatRecordingBytes(
                            entries.fold<int>(
                              0,
                              (sum, entry) => sum + entry.fileSizeBytes,
                            ),
                          ),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: palette.textSubtle),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<LocalSessionRecordingEntry> _groupedEntries() {
    final needle = searchQuery.trim().toLowerCase();
    final filtered = entries
        .where((entry) {
          if (playableOnly && !entry.isReadable) {
            return false;
          }
          return needle.isEmpty ||
              entry.displayName.toLowerCase().contains(needle) ||
              (entry.sessionId?.toLowerCase().contains(needle) ?? false);
        })
        .toList(growable: false);
    filtered.sort(
      (left, right) => switch (sort) {
        _RecordingLibrarySort.newest => right.createdAtUtc.compareTo(
          left.createdAtUtc,
        ),
        _RecordingLibrarySort.oldest => left.createdAtUtc.compareTo(
          right.createdAtUtc,
        ),
        _RecordingLibrarySort.name => left.displayName.toLowerCase().compareTo(
          right.displayName.toLowerCase(),
        ),
      },
    );
    return filtered;
  }
}

class _RecordingLibraryEmptyState extends StatelessWidget {
  const _RecordingLibraryEmptyState({
    required this.palette,
    required this.hasSearch,
    required this.onImport,
  });

  final AppThemeTokens palette;
  final bool hasSearch;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasSearch ? Icons.search_off_rounded : Icons.movie_outlined,
              size: 32,
              color: palette.textSubtle,
            ),
            const SizedBox(height: 10),
            Text(
              hasSearch ? 'No matching recordings' : 'No saved recordings',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: palette.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (!hasSearch) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.file_download_outlined, size: 16),
                label: const Text('Import…'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecordingGroup extends StatelessWidget {
  const _RecordingGroup({
    required this.palette,
    required this.title,
    required this.entries,
    required this.selectedPath,
    required this.selectionLoading,
    required this.onSelect,
    required this.onRename,
    required this.onReveal,
    required this.onExport,
    required this.onDelete,
  });

  final AppThemeTokens palette;
  final String title;
  final List<LocalSessionRecordingEntry> entries;
  final String? selectedPath;
  final bool selectionLoading;
  final ValueChanged<LocalSessionRecordingEntry> onSelect;
  final ValueChanged<LocalSessionRecordingEntry> onRename;
  final ValueChanged<LocalSessionRecordingEntry> onReveal;
  final ValueChanged<LocalSessionRecordingEntry> onExport;
  final ValueChanged<LocalSessionRecordingEntry> onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: palette.textSubtle,
                      letterSpacing: 0.7,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${entries.length}',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: palette.textSubtle),
                ),
              ],
            ),
          ),
          for (final entry in entries)
            _RecordingLibraryRow(
              palette: palette,
              entry: entry,
              selected: entry.path == selectedPath,
              busy: selectionLoading && entry.path == selectedPath,
              onSelect: () => onSelect(entry),
              onRename: () => onRename(entry),
              onReveal: () => onReveal(entry),
              onExport: () => onExport(entry),
              onDelete: () => onDelete(entry),
            ),
        ],
      ),
    );
  }
}

class _RecordingLibraryRow extends StatelessWidget {
  const _RecordingLibraryRow({
    required this.palette,
    required this.entry,
    required this.selected,
    required this.busy,
    required this.onSelect,
    required this.onRename,
    required this.onReveal,
    required this.onExport,
    required this.onDelete,
  });

  final AppThemeTokens palette;
  final LocalSessionRecordingEntry entry;
  final bool selected;
  final bool busy;
  final VoidCallback onSelect;
  final VoidCallback onRename;
  final VoidCallback onReveal;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final date = entry.createdAtUtc.toLocal();
    final subtitle = [
      '${_twoDigits(date.month)}/${_twoDigits(date.day)} ${_twoDigits(date.hour)}:${_twoDigits(date.minute)}',
      _formatRecordingDuration(entry.duration),
      _formatRecordingBytes(entry.fileSizeBytes),
    ].join('  ·  ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? palette.selected : Colors.transparent,
        borderRadius: BorderRadius.circular(palette.radius.md),
        child: InkWell(
          key: Key('recording-library-row-${entry.path}'),
          borderRadius: BorderRadius.circular(palette.radius.md),
          onTap: entry.isReadable ? onSelect : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 3, 9),
            child: Row(
              children: [
                Container(
                  width: 31,
                  height: 31,
                  decoration: BoxDecoration(
                    color: entry.isReadable
                        ? palette.accent.withValues(alpha: 0.12)
                        : palette.dangerContainer,
                    borderRadius: BorderRadius.circular(palette.radius.md),
                  ),
                  alignment: Alignment.center,
                  child: busy
                      ? SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: palette.accent,
                          ),
                        )
                      : Icon(
                          entry.isReadable
                              ? Icons.play_arrow_rounded
                              : Icons.error_outline_rounded,
                          size: 18,
                          color: entry.isReadable
                              ? palette.accent
                              : palette.danger,
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        entry.error ?? subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: entry.error == null
                              ? palette.textSubtle
                              : palette.danger,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Semantics(
                  label: 'Actions for ${entry.displayName}',
                  button: true,
                  child: PopupMenuButton<_RecordingLibraryAction>(
                    tooltip: 'Recording actions',
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      size: 18,
                      color: palette.textSubtle,
                    ),
                    onSelected: (action) {
                      switch (action) {
                        case _RecordingLibraryAction.rename:
                          onRename();
                        case _RecordingLibraryAction.reveal:
                          onReveal();
                        case _RecordingLibraryAction.export:
                          onExport();
                        case _RecordingLibraryAction.delete:
                          onDelete();
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _RecordingLibraryAction.rename,
                        child: Text('Rename…'),
                      ),
                      PopupMenuItem(
                        value: _RecordingLibraryAction.reveal,
                        child: Text('Reveal in Finder'),
                      ),
                      PopupMenuItem(
                        value: _RecordingLibraryAction.export,
                        child: Text('Export…'),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: _RecordingLibraryAction.delete,
                        child: Text('Move to Trash'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordingReplayLayout extends StatefulWidget {
  const _RecordingReplayLayout({
    super.key,
    required this.palette,
    required this.entry,
    required this.layoutName,
    required this.recording,
    required this.delegate,
    required this.sessionConfig,
    required this.terminalColors,
    required this.font,
    required this.cursor,
    required this.onClose,
  });

  final AppThemeTokens palette;
  final LocalSessionRecordingEntry entry;
  final String layoutName;
  final terminal.TerminalRecording recording;
  final pty.PtySessionBackend delegate;
  final terminal.TerminalSessionConfig sessionConfig;
  final terminal.TerminalViewportColors terminalColors;
  final terminal.TerminalFontConfig font;
  final terminal.TerminalCursorConfig cursor;
  final VoidCallback onClose;

  @override
  State<_RecordingReplayLayout> createState() => _RecordingReplayLayoutState();
}

class _RecordingReplayLayoutState extends State<_RecordingReplayLayout> {
  static const _speeds = <double>[0.25, 0.5, 1, 2, 4];

  terminal.TerminalReplayBackend? _backend;
  terminal.TerminalRuntimeController? _runtime;
  String? _sessionId;
  SelectionController? _selectionController;
  TerminalInputController? _inputController;
  FocusNode? _focusNode;
  Timer? _positionTimer;
  Duration _position = Duration.zero;
  double _speed = 1;
  bool _isPlaying = true;
  bool _searchOpen = false;
  String? _error;
  List<terminal.TerminalSearchMatch> _searchMatches = const [];

  terminal.TerminalViewportController? get _viewportController {
    final runtime = _runtime;
    final sessionId = _sessionId;
    return runtime == null || sessionId == null
        ? null
        : runtime.viewportFor(sessionId);
  }

  @override
  void initState() {
    super.initState();
    _initializeReplay();
  }

  void _initializeReplay() {
    try {
      terminal.TerminalRecording replayRecording = widget.recording;
      try {
        replayRecording = const terminal.TerminalRecordingCheckpointPlanner(
          playableEventsPerCheckpoint: 64,
        ).addCheckpoints(widget.recording);
      } on Object {
        // A valid v1 recording still remains playable without seek support.
      }
      final backend = terminal.TerminalReplayBackend(
        delegate: widget.delegate,
        recording: replayRecording,
      );
      final runtime = terminal.TerminalRuntimeController(
        backend: backend,
        copyToClipboard: ClipboardBridge.copy,
        readClipboard: ClipboardBridge.paste,
      );
      final sessionId = runtime.createSession(widget.sessionConfig);
      final selectionController = SelectionController();
      final focusNode = FocusNode(debugLabel: 'recording-replay');
      final inputController = TerminalInputController(
        sessionId: sessionId,
        runtime: runtime,
        readFrame: () => runtime.viewportFor(sessionId).frame,
        readSelection: () => selectionController.textForFrame(
          runtime.viewportFor(sessionId).frame,
        ),
        copySelection: ClipboardBridge.copy,
        readClipboard: ClipboardBridge.paste,
        readOnly: () => true,
      );
      _backend = backend;
      _runtime = runtime;
      _sessionId = sessionId;
      _selectionController = selectionController;
      _focusNode = focusNode;
      _inputController = inputController;
      _positionTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (!mounted) {
          return;
        }
        runtime.refreshSession(sessionId);
        final nextPosition = backend.replayOffsetForSession(sessionId);
        final playing =
            nextPosition < backend.replayDuration &&
            !backend.isSessionPaused(sessionId);
        if (nextPosition != _position || playing != _isPlaying) {
          setState(() {
            _position = nextPosition;
            _isPlaying = playing;
          });
        }
      });
    } on Object catch (error) {
      _error = 'Could not start replay: $error';
      _isPlaying = false;
    }
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _focusNode?.dispose();
    _selectionController?.dispose();
    _runtime?.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    final backend = _backend;
    final sessionId = _sessionId;
    if (backend == null || sessionId == null) {
      return;
    }
    setState(() {
      if (_isPlaying) {
        backend.pauseSession(sessionId);
        _isPlaying = false;
      } else {
        if (_position >= backend.replayDuration && backend.supportsReplaySeek) {
          _seek(Duration.zero);
        }
        backend.resumeSession(sessionId);
        _isPlaying = true;
      }
    });
  }

  void _setSpeed(double speed) {
    _backend?.setPlaybackSpeed(speed);
    setState(() {
      _speed = speed;
    });
  }

  void _seek(Duration target) {
    final backend = _backend;
    final runtime = _runtime;
    final sessionId = _sessionId;
    if (backend == null || runtime == null || sessionId == null) {
      return;
    }
    final clamped = Duration(
      microseconds: target.inMicroseconds.clamp(
        0,
        backend.replayDuration.inMicroseconds,
      ),
    );
    try {
      backend.seekSession(sessionId, clamped);
      runtime.refreshSession(sessionId);
      setState(() {
        _position = clamped;
      });
    } on Object catch (error) {
      setState(() {
        _error = 'Could not seek recording: $error';
      });
    }
  }

  void _updateSearch(String query) {
    final runtime = _runtime;
    final sessionId = _sessionId;
    if (runtime == null || sessionId == null || query.trim().isEmpty) {
      setState(() {
        _searchMatches = const [];
      });
      return;
    }
    final result = runtime.searchTextResult(sessionId, query);
    setState(() {
      _searchMatches = result.matches;
    });
  }

  Future<void> _copyVisible() async {
    final frame = _viewportController?.frame;
    if (frame == null) {
      return;
    }
    await ClipboardBridge.copy(frame.rows.map((row) => row.text).join('\n'));
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final backend = _backend;
    final runtime = _runtime;
    final sessionId = _sessionId;
    final viewportController = _viewportController;
    final seekEnabled = backend?.supportsReplaySeek ?? false;
    final duration = backend?.replayDuration ?? widget.entry.duration;
    final maxMicros = math.max(1, duration.inMicroseconds);
    final sliderValue = _position.inMicroseconds.clamp(0, maxMicros).toDouble();
    final replayLayout = ColoredBox(
      key: const Key('recording-replay-layout'),
      color: palette.canvas,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RecordingReplayMetadataBar(
              palette: palette,
              entry: widget.entry,
              layoutName: widget.layoutName,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.terminalColors.canvasBackground,
                  border: Border.all(color: palette.borderStrong),
                  borderRadius: BorderRadius.circular(palette.radius.lg),
                  boxShadow: palette.elevation.floating,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(palette.radius.lg),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child:
                            _error != null ||
                                runtime == null ||
                                sessionId == null ||
                                viewportController == null ||
                                _selectionController == null ||
                                _inputController == null
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    _error ?? 'Preparing replay…',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: palette.textMuted),
                                  ),
                                ),
                              )
                            : TerminalViewport(
                                key: const Key('recording-replay-viewport'),
                                controller: viewportController,
                                selectionController: _selectionController!,
                                inputController: _inputController!,
                                focusNode: _focusNode,
                                contentPadding: const EdgeInsets.fromLTRB(
                                  14,
                                  48,
                                  14,
                                  14,
                                ),
                                colors: widget.terminalColors,
                                useFrameDefaultColors: false,
                                font: widget.font,
                                cursor: widget.cursor,
                                graphicsCache: runtime.graphicsCacheFor(
                                  sessionId,
                                ),
                                searchMatches: _searchMatches,
                                activeSearchMatchIndex: _searchMatches.isEmpty
                                    ? -1
                                    : 0,
                                onScrollLines: (delta) =>
                                    runtime.scrollViewport(sessionId, delta),
                                onScrollToOffset: (offset) =>
                                    runtime.scrollViewportTo(sessionId, offset),
                                onOpenLink: (url) => unawaited(
                                  WindowBridge.openExternalUrl(url),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _RecordingReplayDock(
              palette: palette,
              position: _position,
              duration: duration,
              sliderValue: sliderValue,
              sliderMax: maxMicros.toDouble(),
              seekEnabled: seekEnabled,
              isPlaying: _isPlaying,
              speed: _speed,
              searchOpen: _searchOpen,
              searchMatchCount: _searchMatches.length,
              onToggle: _togglePlayback,
              onSeek: (value) => _seek(Duration(microseconds: value.round())),
              onJumpBack: seekEnabled
                  ? () => _seek(_position - const Duration(seconds: 10))
                  : null,
              onJumpForward: seekEnabled
                  ? () => _seek(_position + const Duration(seconds: 10))
                  : null,
              onSpeedChanged: _setSpeed,
              onToggleSearch: () {
                setState(() {
                  _searchOpen = !_searchOpen;
                  if (!_searchOpen) {
                    _searchMatches = const [];
                  }
                });
              },
              onSearchChanged: _updateSearch,
              onCopy: _copyVisible,
              onFit: () {
                _focusNode?.requestFocus();
                if (runtime != null && sessionId != null) {
                  runtime.scrollViewportTo(sessionId, 0);
                }
              },
              onClose: widget.onClose,
            ),
          ],
        ),
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: Semantics(
        identifier: 'recording-replay-layout',
        container: true,
        explicitChildNodes: true,
        label: 'Recording replay layout for ${widget.entry.displayName}',
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: replayLayout,
        ),
      ),
    );
  }
}

class _RecordingReplayMetadataBar extends StatelessWidget {
  const _RecordingReplayMetadataBar({
    required this.palette,
    required this.entry,
    required this.layoutName,
  });

  final AppThemeTokens palette;
  final LocalSessionRecordingEntry entry;
  final String layoutName;

  @override
  Widget build(BuildContext context) {
    final date = entry.createdAtUtc.toLocal();
    return SizedBox(
      height: 48,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: palette.chrome,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(palette.radius.md),
        ),
        child: Row(
          children: [
            Flexible(
              flex: 2,
              child: Text(
                entry.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _ReplayMetadataDivider(palette: palette),
            _ReplayMetadataItem(
              palette: palette,
              icon: Icons.folder_outlined,
              label: layoutName,
            ),
            _ReplayMetadataDivider(palette: palette),
            _ReplayMetadataItem(
              palette: palette,
              icon: Icons.calendar_today_outlined,
              label:
                  '${_monthName(date.month)} ${date.day} at ${_twoDigits(date.hour)}:${_twoDigits(date.minute)}',
            ),
            _ReplayMetadataDivider(palette: palette),
            _ReplayMetadataItem(
              palette: palette,
              icon:
                  entry.inputPolicy ==
                      terminal.TerminalRecordingInputPolicy.record
                  ? Icons.keyboard_alt_outlined
                  : Icons.shield_outlined,
              label:
                  entry.inputPolicy ==
                      terminal.TerminalRecordingInputPolicy.record
                  ? 'Input included'
                  : 'Input redacted',
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplayMetadataItem extends StatelessWidget {
  const _ReplayMetadataItem({
    required this.palette,
    required this.icon,
    required this.label,
  });

  final AppThemeTokens palette;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: palette.textSubtle),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: palette.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplayMetadataDivider extends StatelessWidget {
  const _ReplayMetadataDivider({required this.palette});

  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: palette.border,
    );
  }
}

class _RecordingReplayDock extends StatelessWidget {
  const _RecordingReplayDock({
    required this.palette,
    required this.position,
    required this.duration,
    required this.sliderValue,
    required this.sliderMax,
    required this.seekEnabled,
    required this.isPlaying,
    required this.speed,
    required this.searchOpen,
    required this.searchMatchCount,
    required this.onToggle,
    required this.onSeek,
    required this.onJumpBack,
    required this.onJumpForward,
    required this.onSpeedChanged,
    required this.onToggleSearch,
    required this.onSearchChanged,
    required this.onCopy,
    required this.onFit,
    required this.onClose,
  });

  final AppThemeTokens palette;
  final Duration position;
  final Duration duration;
  final double sliderValue;
  final double sliderMax;
  final bool seekEnabled;
  final bool isPlaying;
  final double speed;
  final bool searchOpen;
  final int searchMatchCount;
  final VoidCallback onToggle;
  final ValueChanged<double> onSeek;
  final VoidCallback? onJumpBack;
  final VoidCallback? onJumpForward;
  final ValueChanged<double> onSpeedChanged;
  final VoidCallback onToggleSearch;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onCopy;
  final VoidCallback onFit;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final replayControls = DecoratedBox(
      decoration: BoxDecoration(
        color: palette.chrome,
        borderRadius: BorderRadius.circular(palette.radius.lg),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _ReplayIconButton(
                  label: 'Back 10 seconds',
                  onPressed: onJumpBack,
                  icon: Icons.replay_10_rounded,
                ),
                Semantics(
                  label: isPlaying ? 'Pause replay' : 'Play replay',
                  button: true,
                  child: FilledButton(
                    key: const Key('recording-replay-toggle'),
                    onPressed: onToggle,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(56, 56),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(palette.radius.md),
                      ),
                    ),
                    child: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 25,
                    ),
                  ),
                ),
                _ReplayIconButton(
                  label: 'Forward 10 seconds',
                  onPressed: onJumpForward,
                  icon: Icons.forward_10_rounded,
                ),
                const SizedBox(width: 8),
                Text(
                  '${_formatRecordingDuration(position)} / ${_formatRecordingDuration(duration)}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: palette.textMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: sliderValue,
                    max: sliderMax,
                    onChanged: seekEnabled ? onSeek : null,
                  ),
                ),
                Semantics(
                  label:
                      'Playback speed ${speed == speed.roundToDouble() ? speed.toInt() : speed} times',
                  button: true,
                  child: PopupMenuButton<double>(
                    key: const Key('recording-replay-speed'),
                    tooltip: 'Playback speed',
                    onSelected: onSpeedChanged,
                    itemBuilder: (context) => [
                      for (final item in _RecordingReplayLayoutState._speeds)
                        PopupMenuItem(
                          value: item,
                          child: Text(
                            '${item == item.roundToDouble() ? item.toInt() : item}×',
                          ),
                        ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '${speed == speed.roundToDouble() ? speed.toInt() : speed}×',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: palette.textMuted,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ),
                ),
                _ReplayIconButton(
                  label: 'Search replay',
                  onPressed: onToggleSearch,
                  icon: Icons.search_rounded,
                  color: searchOpen ? palette.accent : null,
                ),
                _ReplayIconButton(
                  label: 'Copy visible output',
                  onPressed: onCopy,
                  icon: Icons.copy_all_outlined,
                ),
                TextButton(onPressed: onFit, child: const Text('Fit')),
                _ReplayIconButton(
                  key: const Key('recording-replay-close'),
                  label: 'Close replay',
                  onPressed: onClose,
                  icon: Icons.close_rounded,
                ),
              ],
            ),
            if (searchOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
                child: TextField(
                  key: const Key('recording-replay-search'),
                  autofocus: true,
                  onChanged: onSearchChanged,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Search replay output',
                    hintText: 'Search visible replay output',
                    suffixText: '$searchMatchCount matches',
                    prefixIcon: const Icon(Icons.search_rounded, size: 17),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return Semantics(
      identifier: 'recording-replay-controls',
      container: true,
      explicitChildNodes: true,
      label: 'Recording replay controls',
      child: replayControls,
    );
  }
}

class _ReplayIconButton extends StatelessWidget {
  const _ReplayIconButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.icon,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      enabled: onPressed != null,
      child: IconButton(
        tooltip: label,
        onPressed: onPressed,
        icon: Icon(icon, size: 20, color: color),
      ),
    );
  }
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String _monthName(int value) => const <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
][value.clamp(1, 12) - 1];

String _recordingSortLabel(_RecordingLibrarySort value) => switch (value) {
  _RecordingLibrarySort.newest => 'Newest',
  _RecordingLibrarySort.oldest => 'Oldest',
  _RecordingLibrarySort.name => 'Name',
};

String _formatRecordingDuration(Duration value) {
  final totalSeconds = math.max(0, value.inSeconds);
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${_twoDigits(minutes)}:${_twoDigits(seconds)}';
  }
  return '${_twoDigits(minutes)}:${_twoDigits(seconds)}';
}

String _formatRecordingBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
