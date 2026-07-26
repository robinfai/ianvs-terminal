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

final class _RecordingReplayRuntime {
  const _RecordingReplayRuntime({
    required this.backend,
    required this.runtime,
    required this.sessionId,
  });

  final terminal.TerminalReplayBackend backend;
  final terminal.TerminalRuntimeController runtime;
  final String sessionId;
}

final class _RecordingReplayDriver implements terminal.TerminalReplayDriver {
  _RecordingReplayDriver({
    required _RecordingReplayRuntime replayRuntime,
    required _RecordingReplayRuntime Function() recreate,
    required ValueChanged<_RecordingReplayRuntime> onRecreated,
  }) : _replayRuntime = replayRuntime,
       _recreate = recreate,
       _onRecreated = onRecreated;

  _RecordingReplayRuntime _replayRuntime;
  final _RecordingReplayRuntime Function() _recreate;
  final ValueChanged<_RecordingReplayRuntime> _onRecreated;

  @override
  Duration get duration => _replayRuntime.backend.replayDuration;

  @override
  Duration get position =>
      _replayRuntime.backend.replayOffsetForSession(_replayRuntime.sessionId);

  @override
  void advanceTo(Duration sourceOffset) {
    final current = _replayRuntime;
    final deliveredEvents = current.backend.advanceSessionTo(
      current.sessionId,
      sourceOffset,
    );
    if (deliveredEvents) {
      current.runtime.refreshSession(current.sessionId);
    }
  }

  @override
  void seekTo(Duration sourceOffset) {
    final current = _replayRuntime;
    try {
      current.backend.seekSession(current.sessionId, sourceOffset);
      current.runtime.refreshSession(current.sessionId);
      return;
    } on UnsupportedError {
      _rebuildFromStart(sourceOffset);
    } on terminal.TerminalReplaySeekException {
      _rebuildFromStart(sourceOffset);
    }
  }

  void _rebuildFromStart(Duration sourceOffset) {
    final previous = _replayRuntime;
    final replacement = _recreate();
    _replayRuntime = replacement;
    _onRecreated(replacement);
    previous.runtime.dispose();
    replacement.backend.advanceSessionTo(replacement.sessionId, sourceOffset);
    replacement.runtime.refreshSession(replacement.sessionId);
  }
}

class _RecordingReplayLayoutState extends State<_RecordingReplayLayout> {
  terminal.TerminalRuntimeController? _runtime;
  terminal.TerminalReplayController? _replayController;
  String? _sessionId;
  SelectionController? _selectionController;
  TerminalInputController? _inputController;
  FocusNode? _focusNode;
  String? _error;
  String _searchQuery = '';
  late final RecordingReplaySearchIndex _searchIndex;
  List<RecordingReplaySearchHit> _searchHits =
      const <RecordingReplaySearchHit>[];
  int _activeSearchHitIndex = 0;
  List<terminal.TerminalSearchMatch> _searchMatches = const [];
  int _activeSearchMatchIndex = 0;
  Size _measuredReplayCellSize = terminal.terminalFallbackCellSize;
  Size? _lastReplayViewportSize;
  bool _isReplayDockDragging = false;

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
    _searchIndex = RecordingReplaySearchIndex(widget.recording);
    _initializeReplay();
  }

  void _initializeReplay() {
    try {
      terminal.TerminalRecording replayRecording = widget.recording;
      try {
        replayRecording = const terminal.TerminalRecordingCheckpointPlanner(
          playableEventsPerCheckpoint: 128,
        ).addCheckpoints(widget.recording);
      } on Object {
        // A valid v1 recording still remains playable without seek support.
      }
      final replayRuntime = _createReplayRuntime(replayRecording);
      final selectionController = SelectionController();
      final focusNode = FocusNode(debugLabel: 'recording-replay');
      final inputController = _createReplayInputController(
        replayRuntime,
        selectionController,
      );
      final replayDriver = _RecordingReplayDriver(
        replayRuntime: replayRuntime,
        recreate: () => _createReplayRuntime(replayRecording),
        onRecreated: (replacement) {
          _runtime = replacement.runtime;
          _sessionId = replacement.sessionId;
          _inputController = _createReplayInputController(
            replacement,
            selectionController,
          );
        },
      );
      final replayController = terminal.TerminalReplayController(
        driver: replayDriver,
        navigationOffsets: _recordingNavigationOffsets(widget.recording),
        smartAnchors: _recordingPlaybackAnchors(widget.recording),
      )..addListener(_handleReplayChanged);
      _runtime = replayRuntime.runtime;
      _replayController = replayController;
      _sessionId = replayRuntime.sessionId;
      _selectionController = selectionController;
      _focusNode = focusNode;
      _inputController = inputController;
      replayRuntime.runtime.refreshSession(replayRuntime.sessionId);
    } on Object catch (error) {
      _error = 'Could not start replay: $error';
    }
  }

  _RecordingReplayRuntime _createReplayRuntime(
    terminal.TerminalRecording replayRecording,
  ) {
    final backend = terminal.TerminalReplayBackend(
      delegate: widget.delegate,
      recording: replayRecording,
      timingMode: terminal.TerminalReplayTimingMode.manual,
    );
    final runtime = terminal.TerminalRuntimeController(
      backend: backend,
      copyToClipboard: ClipboardBridge.copy,
      readClipboard: ClipboardBridge.paste,
    );
    final sessionId = runtime.createSession(widget.sessionConfig);
    return _RecordingReplayRuntime(
      backend: backend,
      runtime: runtime,
      sessionId: sessionId,
    );
  }

  TerminalInputController _createReplayInputController(
    _RecordingReplayRuntime replayRuntime,
    SelectionController selectionController,
  ) {
    final runtime = replayRuntime.runtime;
    final sessionId = replayRuntime.sessionId;
    return TerminalInputController(
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
  }

  @override
  void dispose() {
    _replayController
      ?..removeListener(_handleReplayChanged)
      ..dispose();
    _focusNode?.dispose();
    _selectionController?.dispose();
    _runtime?.dispose();
    super.dispose();
  }

  void _handleReplayChanged() {
    if (!mounted || _isReplayDockDragging) {
      return;
    }
    setState(_synchronizeReplayUiState);
  }

  void _handleDockDragStateChanged(bool dragging) {
    _isReplayDockDragging = dragging;
    if (!dragging && mounted) {
      setState(_synchronizeReplayUiState);
    }
  }

  void _synchronizeReplayUiState() {
    final replayState = _replayController?.state;
    _error = replayState?.error == null
        ? null
        : 'Could not seek recording: ${replayState!.error}';
    _searchMatches = _searchMatchesFor(_searchQuery);
    _activeSearchMatchIndex = _searchMatches.isEmpty
        ? 0
        : _activeSearchMatchIndex.clamp(0, _searchMatches.length - 1).toInt();
  }

  void _updateSearch(String query) {
    _searchQuery = query;
    _searchHits = _searchIndex.search(query);
    _activeSearchHitIndex = 0;
    _activeSearchMatchIndex = 0;
    final firstHit = _searchHits.firstOrNull;
    if (firstHit != null) {
      _replayController?.seekToSource(firstHit.offset);
      return;
    }
    setState(() {
      _searchMatches = _searchMatchesFor(query);
    });
  }

  List<terminal.TerminalSearchMatch> _searchMatchesFor(String query) {
    final runtime = _runtime;
    final sessionId = _sessionId;
    if (runtime == null || sessionId == null || query.trim().isEmpty) {
      return const [];
    }
    return runtime.searchTextResult(sessionId, query).matches;
  }

  void _moveSearchMatch(int delta) {
    if (_searchHits.isEmpty) {
      return;
    }
    _activeSearchHitIndex =
        (_activeSearchHitIndex + delta) % _searchHits.length;
    if (_activeSearchHitIndex < 0) {
      _activeSearchHitIndex += _searchHits.length;
    }
    _activeSearchMatchIndex = 0;
    _replayController?.seekToSource(_searchHits[_activeSearchHitIndex].offset);
  }

  Future<void> _copyVisible() async {
    final frame = _viewportController?.frame;
    if (frame == null) {
      return;
    }
    await ClipboardBridge.copy(frame.rows.map((row) => row.text).join('\n'));
  }

  Future<void> _copySelection() async {
    final selectionController = _selectionController;
    final frame = _viewportController?.frame;
    if (selectionController == null || frame == null) {
      return;
    }
    final selectedText = selectionController.textForFrame(frame);
    if (selectedText.trim().isEmpty) {
      return;
    }
    await ClipboardBridge.copy(selectedText);
  }

  Size? _recordedViewportSizeFor(
    terminal.TerminalViewportController? controller,
  ) {
    final frame = controller?.frame;
    if (frame == null || frame.viewportCols <= 0 || frame.viewportRows <= 0) {
      return null;
    }
    const viewportPadding = 24.0;
    return Size(
      frame.viewportCols * _measuredReplayCellSize.width + viewportPadding,
      frame.viewportRows * _measuredReplayCellSize.height + viewportPadding,
    );
  }

  Future<void> _fitRecordedSize(Size? recordedViewportSize) async {
    final currentViewportSize = _lastReplayViewportSize;
    if (recordedViewportSize == null ||
        currentViewportSize == null ||
        currentViewportSize.width <= 0 ||
        currentViewportSize.height <= 0) {
      return;
    }
    final widthDelta = math.max(
      0.0,
      recordedViewportSize.width - currentViewportSize.width,
    );
    final heightDelta = math.max(
      0.0,
      recordedViewportSize.height - currentViewportSize.height,
    );
    if (widthDelta == 0 && heightDelta == 0) {
      return;
    }
    await WindowBridge.resizeBy(
      widthDelta: widthDelta,
      heightDelta: heightDelta,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final runtime = _runtime;
    final sessionId = _sessionId;
    final replayController = _replayController;
    final viewportController = _viewportController;
    final seekEnabled = replayController != null;
    final hasCommandMetadata = widget.recording.events.any(
      (event) =>
          event.kind == terminal.TerminalRecordingEventKind.shellSemantic &&
          event.semanticCommand != null,
    );
    final inputDisclosure =
        widget.recording.metadata.inputPolicy ==
            terminal.TerminalRecordingInputPolicy.record
        ? 'Input included'
        : hasCommandMetadata
        ? 'Keystrokes redacted · command metadata included'
        : 'Keystrokes redacted';
    final recordedViewportSize = _recordedViewportSizeFor(viewportController);
    final timelineTimeMap =
        replayController?.timeMap ??
        terminal.TerminalReplayTimeMap.real(widget.entry.duration);
    final timelineMarkers = _recordingTimelineMarkers(
      widget.recording,
      timelineTimeMap,
    );
    final timelineModel = _buildReplayTimelineModel(
      points: _recordingSemanticPoints(widget.recording, timelineTimeMap),
      duration: timelineTimeMap.presentationDuration,
    );

    Widget replayDock() {
      final replayState = replayController?.state;
      final duration =
          replayState?.presentationDuration ?? widget.entry.duration;
      final maxMicros = math.max(1, duration.inMicroseconds);
      final sliderValue =
          replayState?.presentationPosition.inMicroseconds
              .clamp(0, maxMicros)
              .toDouble() ??
          0;
      return _RecordingReplayDock(
        palette: palette,
        sourceLabel: widget.entry.displayName,
        detailLabel:
            '${widget.entry.sessionId ?? 'Recorded session'} · '
            '$inputDisclosure',
        position: replayState?.presentationPosition ?? Duration.zero,
        duration: duration,
        sourcePosition: replayState?.sourcePosition ?? Duration.zero,
        sourceDuration: replayState?.sourceDuration ?? widget.entry.duration,
        sliderValue: sliderValue,
        sliderMax: maxMicros.toDouble(),
        timelineMarkers: timelineMarkers,
        timelineModel: timelineModel,
        seekEnabled: seekEnabled,
        isPlaying: replayState?.isPlaying ?? false,
        speed: replayState?.speed ?? 1,
        timeMode:
            replayState?.timeMode ?? terminal.TerminalReplayTimeMode.smart,
        searchMatchCount: _searchHits.length,
        onToggle: replayController?.togglePlayback ?? () {},
        onSeek: (value) => replayController?.seekToPresentation(
          Duration(microseconds: value.round()),
        ),
        onStepBack: replayController?.canStepPrevious ?? false
            ? replayController?.stepPrevious
            : null,
        onStepForward: replayController?.canStepNext ?? false
            ? replayController?.stepNext
            : null,
        onSpeedChanged: (value) => replayController?.setSpeed(value),
        onTimeModeChanged: (value) => replayController?.setTimeMode(value),
        onSearchChanged: _updateSearch,
        onSearchPrevious: _searchHits.isEmpty
            ? null
            : () => _moveSearchMatch(-1),
        onSearchNext: _searchHits.isEmpty ? null : () => _moveSearchMatch(1),
        onCopyVisible: _copyVisible,
        onCopySelection: _copySelection,
        onFit: () {
          _focusNode?.requestFocus();
          if (runtime != null && sessionId != null) {
            runtime.scrollViewportTo(sessionId, 0);
          }
          unawaited(_fitRecordedSize(recordedViewportSize));
        },
        onClose: widget.onClose,
      );
    }

    final replayLayout = ColoredBox(
      key: const Key('recording-replay-layout'),
      color: palette.canvas,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: ReplayFloatingStage(
          key: const Key('recording-replay-stage'),
          recordedViewportSize: recordedViewportSize,
          viewportFitKey: const Key('recording-replay-fit'),
          viewportContentKey: const Key('recording-replay-fit-content'),
          floatingDockKey: const Key('recording-replay-floating-dock'),
          dragHandleKey: const Key('recording-replay-dock-drag-handle'),
          dragHandleColor: palette.textMuted,
          onAvailableSizeChanged: (size) {
            _lastReplayViewportSize = size;
          },
          onDockDragStateChanged: _handleDockDragStateChanged,
          viewport: ReplayViewportFrame(
            backgroundColor: widget.terminalColors.canvasBackground,
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
                          contentPadding: const EdgeInsets.all(12),
                          colors: widget.terminalColors,
                          useFrameDefaultColors: false,
                          font: widget.font,
                          cursor: widget.cursor,
                          onMeasuredCellSizeChanged: (cellSize) {
                            if (_measuredReplayCellSize == cellSize) {
                              return;
                            }
                            setState(() {
                              _measuredReplayCellSize = cellSize;
                            });
                          },
                          graphicsCache: runtime.graphicsCacheFor(sessionId),
                          searchMatches: _searchMatches,
                          activeSearchMatchIndex: _searchMatches.isEmpty
                              ? -1
                              : _activeSearchMatchIndex,
                          onScrollLines: (delta) =>
                              runtime.scrollViewport(sessionId, delta),
                          onScrollToOffset: (offset) =>
                              runtime.scrollViewportTo(sessionId, offset),
                          onOpenLink: (url) =>
                              unawaited(WindowBridge.openExternalUrl(url)),
                        ),
                ),
              ],
            ),
          ),
          dock: replayController == null
              ? replayDock()
              : ListenableBuilder(
                  listenable: replayController,
                  builder: (context, _) => replayDock(),
                ),
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
        label: 'Replay recording layout for ${widget.entry.displayName}',
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: replayLayout,
        ),
      ),
    );
  }
}

class _RecordingReplayDock extends StatelessWidget {
  const _RecordingReplayDock({
    required this.palette,
    required this.sourceLabel,
    required this.detailLabel,
    required this.position,
    required this.duration,
    required this.sourcePosition,
    required this.sourceDuration,
    required this.sliderValue,
    required this.sliderMax,
    required this.timelineMarkers,
    required this.timelineModel,
    required this.seekEnabled,
    required this.isPlaying,
    required this.speed,
    required this.timeMode,
    required this.searchMatchCount,
    required this.onToggle,
    required this.onSeek,
    required this.onStepBack,
    required this.onStepForward,
    required this.onSpeedChanged,
    required this.onTimeModeChanged,
    required this.onSearchChanged,
    required this.onSearchPrevious,
    required this.onSearchNext,
    required this.onCopyVisible,
    required this.onCopySelection,
    required this.onFit,
    required this.onClose,
  });

  final AppThemeTokens palette;
  final String sourceLabel;
  final String detailLabel;
  final Duration position;
  final Duration duration;
  final Duration sourcePosition;
  final Duration sourceDuration;
  final double sliderValue;
  final double sliderMax;
  final List<_ReplayTimelineMarker> timelineMarkers;
  final _ReplayTimelineModel timelineModel;
  final bool seekEnabled;
  final bool isPlaying;
  final double speed;
  final terminal.TerminalReplayTimeMode timeMode;
  final int searchMatchCount;
  final VoidCallback onToggle;
  final ValueChanged<double> onSeek;
  final VoidCallback? onStepBack;
  final VoidCallback? onStepForward;
  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<terminal.TerminalReplayTimeMode> onTimeModeChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback? onSearchPrevious;
  final VoidCallback? onSearchNext;
  final VoidCallback onCopyVisible;
  final VoidCallback onCopySelection;
  final VoidCallback onFit;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final metadata = Row(
      children: [
        _ReplaySourceMark(palette: palette, sourceLabel: 'Recording'),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                sourceLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                detailLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: palette.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final transport = _InstantReplayPlaybackControls(
      toggleKey: const Key('recording-replay-toggle'),
      speedKey: const Key('recording-replay-speed'),
      timeModeKey: const Key('recording-replay-time-mode'),
      isPlaying: isPlaying,
      speed: speed,
      timeMode: timeMode,
      onStepBack: onStepBack,
      onTogglePlay: onToggle,
      onStepForward: onStepForward,
      onSpeedChanged: onSpeedChanged,
      onTimeModeChanged: onTimeModeChanged,
      palette: palette,
    );
    final actions = Wrap(
      spacing: 5,
      runSpacing: 5,
      alignment: WrapAlignment.end,
      children: [
        _InstantReplayControlButton(
          key: const Key('recording-replay-fit-recorded-size'),
          tooltip: 'Fit recorded size',
          onPressed: onFit,
          icon: Icons.fit_screen_rounded,
          palette: palette,
        ),
        _InstantReplayControlButton(
          tooltip: 'Copy visible',
          onPressed: onCopyVisible,
          icon: Icons.copy_rounded,
          palette: palette,
        ),
        _InstantReplayControlButton(
          tooltip: 'Copy selection',
          onPressed: onCopySelection,
          icon: Icons.select_all_rounded,
          palette: palette,
        ),
        _InstantReplayControlButton(
          key: const Key('recording-replay-close'),
          tooltip: 'Close replay',
          onPressed: onClose,
          icon: Icons.close_rounded,
          palette: palette,
        ),
      ],
    );
    final timeline = _ReplaySemanticTimeline(
      timelineKey: const Key('recording-replay-timeline'),
      effectsKey: const Key('recording-replay-timeline-effects'),
      palette: palette,
      value: sliderValue,
      max: sliderMax,
      position: position,
      duration: duration,
      displayPosition: sourcePosition,
      displayDuration: sourceDuration,
      model: timelineModel,
      markers: timelineMarkers,
      onChanged: seekEnabled ? onSeek : null,
    );
    final search = _InstantReplaySearchControls(
      searchKey: const Key('recording-replay-search'),
      previousKey: const Key('recording-replay-search-previous'),
      nextKey: const Key('recording-replay-search-next'),
      enabled: true,
      searchSummary: searchMatchCount == 0
          ? null
          : '$searchMatchCount ${searchMatchCount == 1 ? 'match' : 'matches'} across replay',
      onSearchChanged: onSearchChanged,
      onSearchPrevious: onSearchPrevious,
      onSearchNext: onSearchNext,
      palette: palette,
    );
    return Semantics(
      identifier: 'recording-replay-controls',
      container: true,
      explicitChildNodes: true,
      label: 'Replay controls for recording',
      child: _ReplayDockLayout(
        timeline: timeline,
        metadata: metadata,
        transport: transport,
        search: search,
        actions: actions,
        palette: palette,
      ),
    );
  }
}

List<_ReplayTimelineMarker> _recordingTimelineMarkers(
  terminal.TerminalRecording recording,
  terminal.TerminalReplayTimeMap timeMap,
) {
  const maximumVisibleEventMarkers = 96;
  const minimumIdleGap = Duration(seconds: 2);
  final durationMicros = math.max(
    1,
    timeMap.presentationDuration.inMicroseconds,
  );
  final events = recording.events
      .where(
        (event) =>
            event.kind != terminal.TerminalRecordingEventKind.checkpoint &&
            event.kind != terminal.TerminalRecordingEventKind.sessionStarted &&
            event.kind != terminal.TerminalRecordingEventKind.shellSemantic,
      )
      .toList(growable: false);
  final candidates = <_ReplayTimelineMarker>[];
  terminal.TerminalRecordingEvent? previous;
  for (final event in events) {
    final previousEvent = previous;
    if (previousEvent != null) {
      final gap = event.monotonicOffset - previousEvent.monotonicOffset;
      if (gap >= minimumIdleGap) {
        candidates.add(
          _ReplayTimelineMarker(
            value: timeMap
                .sourceToPresentation(
                  previousEvent.monotonicOffset +
                      Duration(microseconds: gap.inMicroseconds ~/ 2),
                )
                .inMicroseconds
                .toDouble(),
            kind: _ReplayTimelineMarkerKind.idle,
            tooltip: 'Idle interval',
          ),
        );
      }
    }
    previous = event;
    candidates.add(
      _ReplayTimelineMarker(
        value: timeMap
            .sourceToPresentation(event.monotonicOffset)
            .inMicroseconds
            .clamp(0, durationMicros)
            .toDouble(),
        kind: switch (event.kind) {
          terminal.TerminalRecordingEventKind.userInput =>
            _ReplayTimelineMarkerKind.input,
          terminal.TerminalRecordingEventKind.resize =>
            _ReplayTimelineMarkerKind.resize,
          terminal.TerminalRecordingEventKind.sessionExited =>
            _ReplayTimelineMarkerKind.exit,
          _ => _ReplayTimelineMarkerKind.output,
        },
        tooltip: switch (event.kind) {
          terminal.TerminalRecordingEventKind.userInput => 'Input event',
          terminal.TerminalRecordingEventKind.resize => 'Terminal resized',
          terminal.TerminalRecordingEventKind.sessionExited => 'Session exited',
          _ => 'Output event',
        },
      ),
    );
  }
  if (candidates.length <= maximumVisibleEventMarkers) {
    return candidates;
  }

  final important = candidates
      .where((marker) => marker.kind != _ReplayTimelineMarkerKind.output)
      .toList(growable: false);
  final output = candidates
      .where((marker) => marker.kind == _ReplayTimelineMarkerKind.output)
      .toList(growable: false);
  final outputBudget = math.max(
    0,
    maximumVisibleEventMarkers - important.length,
  );
  if (outputBudget == 0) {
    return important.take(maximumVisibleEventMarkers).toList(growable: false);
  }
  final sampled = <_ReplayTimelineMarker>[...important];
  for (var index = 0; index < outputBudget; index += 1) {
    final sourceIndex = outputBudget == 1
        ? output.length - 1
        : (index * (output.length - 1) / (outputBudget - 1)).round();
    sampled.add(output[sourceIndex]);
  }
  sampled.sort((a, b) => a.value.compareTo(b.value));
  return sampled;
}

List<_ReplaySemanticPoint> _recordingSemanticPoints(
  terminal.TerminalRecording recording,
  terminal.TerminalReplayTimeMap timeMap,
) {
  return [
    for (final event in recording.events)
      if (event.kind == terminal.TerminalRecordingEventKind.shellSemantic &&
          event.semanticKind != null)
        _ReplaySemanticPoint(
          offset: timeMap.sourceToPresentation(event.monotonicOffset),
          kind: event.semanticKind!,
          command: event.semanticCommand,
          cwd: event.semanticCwd,
          hostname: event.semanticHostname,
          exitCode: event.semanticExitCode,
          remote: event.semanticRemote,
        ),
  ];
}

List<Duration> _recordingNavigationOffsets(
  terminal.TerminalRecording recording,
) {
  final semanticOffsets = <Duration>[
    for (final event in recording.events)
      if (event.kind == terminal.TerminalRecordingEventKind.shellSemantic &&
          (event.semanticKind ==
                  terminal.TerminalRecordingSemanticKind.commandStarted ||
              event.semanticKind ==
                  terminal.TerminalRecordingSemanticKind.remoteSessionStarted ||
              event.semanticKind ==
                  terminal.TerminalRecordingSemanticKind.prompt))
        event.monotonicOffset,
  ];
  if (semanticOffsets.isNotEmpty) {
    return semanticOffsets;
  }

  const activityGap = Duration(milliseconds: 800);
  final offsets = <Duration>[];
  Duration? previousOffset;
  for (final event in recording.events) {
    if (event.kind != terminal.TerminalRecordingEventKind.ptyOutput &&
        event.kind != terminal.TerminalRecordingEventKind.resize &&
        event.kind != terminal.TerminalRecordingEventKind.sessionExited) {
      continue;
    }
    final previous = previousOffset;
    if (previous == null || event.monotonicOffset - previous > activityGap) {
      offsets.add(event.monotonicOffset);
    }
    previousOffset = event.monotonicOffset;
  }
  return offsets;
}

List<Duration> _recordingPlaybackAnchors(terminal.TerminalRecording recording) {
  return <Duration>[
    for (final event in recording.events)
      if (event.kind == terminal.TerminalRecordingEventKind.ptyOutput ||
          event.kind == terminal.TerminalRecordingEventKind.resize ||
          event.kind == terminal.TerminalRecordingEventKind.sessionExited)
        event.monotonicOffset,
  ];
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

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
