part of 'shell_screen.dart';

class _RecordingLibraryLayout extends StatelessWidget {
  const _RecordingLibraryLayout({
    required this.palette,
    required this.shelfOpen,
    required this.layout,
    required this.shelf,
    required this.onClose,
  });

  final AppThemeTokens palette;
  final bool shelfOpen;
  final Widget layout;
  final Widget shelf;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (context.usesMobileNavigation) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Offstage(
              offstage: shelfOpen,
              child: ExcludeFocus(excluding: shelfOpen, child: layout),
            ),
            if (shelfOpen) Positioned.fill(child: shelf),
          ],
        );
      }
      final compact = constraints.maxWidth < 960;
      return Stack(
        children: [
          Positioned.fill(
            right: shelfOpen && !compact ? 372 : 0,
            child: ExcludeFocus(excluding: shelfOpen, child: layout),
          ),
          if (shelfOpen && compact)
            Positioned.fill(
              child: ModalBarrier(
                color: palette.inactiveScrim.withValues(alpha: 0.58),
                onDismiss: onClose,
                semanticsLabel: MaterialLocalizations.of(
                  context,
                ).modalBarrierDismissLabel,
              ),
            ),
          if (shelfOpen)
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: compact ? math.min(400, constraints.maxWidth) : 372,
              child: BlockSemantics(
                blocking: compact,
                child: KeyedSubtree(
                  key: compact
                      ? const Key('saved-recordings-shelf-compact')
                      : null,
                  child: shelf,
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// A small entry point into existing replay capabilities. Recordings stay in
/// the local library; opening this surface does not start recording a session.
class _SavedRecordingsShelf extends StatelessWidget {
  const _SavedRecordingsShelf({
    required this.palette,
    required this.entries,
    required this.selectedPath,
    required this.loading,
    required this.selectionLoading,
    required this.error,
    required this.onRefresh,
    required this.onOpenFile,
    required this.onRecent,
    required this.onToggleRecording,
    required this.recording,
    required this.pendingSave,
    required this.onSelect,
    required this.onClose,
  });

  final AppThemeTokens palette;
  final List<LocalSessionRecordingEntry> entries;
  final String? selectedPath;
  final bool loading;
  final bool selectionLoading;
  final String? error;
  final VoidCallback onRefresh;
  final VoidCallback onOpenFile;
  final VoidCallback? onRecent;
  final VoidCallback? onToggleRecording;
  final bool recording;
  final bool pendingSave;
  final ValueChanged<LocalSessionRecordingEntry> onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
    },
    child: Actions(
      actions: {
        DismissIntent: CallbackAction<DismissIntent>(
          onInvoke: (_) {
            onClose();
            return null;
          },
        ),
      },
      child: FocusScope(
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: context.l10n.replayHubTitle,
          child: Material(
            key: const Key('saved-recordings-shelf'),
            color: palette.chrome,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: palette.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(context),
                  Expanded(child: _contents(context)),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _header(BuildContext context) {
    final mobile = context.usesMobileNavigation;
    final close = MergeSemantics(
      child: Semantics(
        label: mobile ? context.l10n.mobileBack : context.l10n.close,
        child: IconButton(
          key: const Key('recording-library-close'),
          autofocus: !mobile,
          tooltip: mobile ? context.l10n.mobileBack : context.l10n.close,
          onPressed: onClose,
          icon: Icon(
            mobile ? Icons.arrow_back_ios_new_rounded : Icons.close_rounded,
          ),
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: palette.spacing.sm,
        vertical: palette.spacing.sm,
      ),
      child: Row(
        children: [
          if (mobile) close,
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: palette.spacing.sm),
              child: Text(
                context.l10n.replayHubTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          if (!mobile) close,
        ],
      ),
    );
  }

  Widget _contents(BuildContext context) {
    final ordered = [...entries]
      ..sort((a, b) {
        final date = b.createdAtUtc.compareTo(a.createdAtUtc);
        return date == 0 ? a.path.compareTo(b.path) : date;
      });
    return CustomScrollView(
      key: const Key('recording-library-scroll'),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: palette.spacing.lg),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!context.usesMobileNavigation || onRecent != null)
                  _recent(context),
                SizedBox(height: palette.spacing.lg),
                const Divider(),
                SizedBox(height: palette.spacing.sm),
                _savedControls(context),
                SizedBox(height: palette.spacing.md),
                _status(context, empty: ordered.isEmpty),
              ],
            ),
          ),
        ),
        SliverList.builder(
          itemCount: ordered.length,
          itemBuilder: (context, index) => _entry(context, ordered[index]),
        ),
        SliverToBoxAdapter(child: SizedBox(height: palette.spacing.lg)),
      ],
    );
  }

  Widget _recent(BuildContext context) {
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.replayRecentTitle, style: textTheme.titleSmall),
        SizedBox(height: palette.spacing.xs),
        if (!context.usesMobileNavigation)
          Text(l10n.replayRecentExplanation, style: textTheme.bodySmall),
        SizedBox(height: palette.spacing.sm),
        OutlinedButton.icon(
          key: const Key('shell-replay-recent-activity'),
          onPressed: selectionLoading ? null : onRecent,
          icon: const Icon(Icons.history_rounded),
          label: Text(l10n.replayRecentActivity),
        ),
        if (onRecent == null)
          Text(l10n.replayRecentNeedsSession, style: textTheme.bodySmall),
      ],
    );
  }

  Widget _savedControls(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.savedRecordings,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            MergeSemantics(
              child: Semantics(
                label: l10n.refreshRecordings,
                child: IconButton(
                  key: const Key('recording-library-refresh'),
                  tooltip: l10n.refreshRecordings,
                  onPressed: loading || selectionLoading ? null : onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ),
            ),
          ],
        ),
        if (!context.usesMobileNavigation)
          Text(
            l10n.replaySavedExplanation,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        SizedBox(height: palette.spacing.sm),
        if (!context.usesMobileNavigation && onRecent != null)
          _recordingButton(context),
        OutlinedButton.icon(
          key: const Key('recording-library-open-file'),
          onPressed: selectionLoading ? null : onOpenFile,
          icon: const Icon(Icons.folder_open_rounded),
          label: Text(l10n.replayOpenFile),
        ),
      ],
    );
  }

  Widget _recordingButton(BuildContext context) => FilledButton.tonalIcon(
    key: const Key('recording-library-toggle-recording'),
    onPressed: selectionLoading ? null : onToggleRecording,
    icon: Icon(
      recording
          ? Icons.stop_circle_outlined
          : pendingSave
          ? Icons.save_outlined
          : Icons.fiber_manual_record_outlined,
    ),
    label: Text(
      recording
          ? context.l10n.stopAndSaveRecording
          : pendingSave
          ? context.l10n.retrySavingRecording
          : context.l10n.startRecordingForReplay,
    ),
  );

  Widget _status(BuildContext context, {required bool empty}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (loading || selectionLoading) const LinearProgressIndicator(),
      if (error != null)
        Padding(
          padding: EdgeInsets.symmetric(vertical: palette.spacing.sm),
          child: Semantics(
            liveRegion: true,
            child: Text(
              error!,
              key: const Key('recording-library-error'),
              style: TextStyle(color: palette.danger),
            ),
          ),
        ),
      if (!loading && error == null && empty)
        Padding(
          padding: EdgeInsets.symmetric(vertical: palette.spacing.lg),
          child: Text(
            context.usesMobileNavigation
                ? context.l10n.mobileSavedEmpty
                : context.l10n.replayLibraryEmpty,
            key: const Key('recording-library-empty'),
          ),
        ),
    ],
  );

  Widget _entry(BuildContext context, LocalSessionRecordingEntry entry) {
    final date = entry.createdAtUtc.toLocal();
    final material = MaterialLocalizations.of(context);
    final details = entry.isReadable
        ? '${material.formatCompactDate(date)} · ${material.formatTimeOfDay(TimeOfDay.fromDateTime(date))} · ${_formatRecordingDuration(entry.duration)}'
        : context.l10n.replayRecordingUnavailable;
    return ListTile(
      key: ValueKey('recording-entry-${entry.path}'),
      selected: selectedPath == entry.path,
      enabled: entry.isReadable && !selectionLoading,
      leading: Icon(
        entry.isReadable
            ? Icons.play_circle_outline_rounded
            : Icons.error_outline_rounded,
      ),
      title: Text(
        entry.displayName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(details),
      contentPadding: EdgeInsets.symmetric(
        horizontal: palette.spacing.lg,
        vertical: palette.spacing.xs,
      ),
      onTap: entry.isReadable && !selectionLoading
          ? () => onSelect(entry)
          : null,
    );
  }
}

class _RecordingReplayLayout extends StatefulWidget {
  const _RecordingReplayLayout({
    super.key,
    this.mobile = false,
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

  final bool mobile;
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

enum _RecordingReplayErrorKind { start, seek }

class _RecordingReplayLayoutState extends State<_RecordingReplayLayout> {
  terminal.TerminalRuntimeController? _runtime;
  terminal.TerminalReplayController? _replayController;
  String? _sessionId;
  SelectionController? _selectionController;
  TerminalInputController? _inputController;
  FocusNode? _focusNode;
  _RecordingReplayErrorKind? _errorKind;
  String? _errorDetails;
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
        initialTimeMode: widget.mobile
            ? terminal.TerminalReplayTimeMode.realTime
            : terminal.TerminalReplayTimeMode.smart,
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
      _errorKind = _RecordingReplayErrorKind.start;
      _errorDetails = error.toString();
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
    if (replayState?.error case final String error) {
      _errorKind = _RecordingReplayErrorKind.seek;
      _errorDetails = error;
    } else {
      _errorKind = null;
      _errorDetails = null;
    }
    _searchMatches = _searchMatchesFor(_searchQuery);
    _activeSearchMatchIndex = _searchMatches.isEmpty
        ? 0
        : _activeSearchMatchIndex.clamp(0, _searchMatches.length - 1);
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
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final runtime = _runtime;
    final sessionId = _sessionId;
    final replayController = _replayController;
    final viewportController = _viewportController;
    final errorMessage = switch ((_errorKind, _errorDetails)) {
      (_RecordingReplayErrorKind.start, final String details) =>
        context.l10n.couldNotStartReplay(details),
      (_RecordingReplayErrorKind.seek, final String details) =>
        context.l10n.couldNotSeekRecording(details),
      _ => null,
    };
    final seekEnabled = replayController != null;
    final hasCommandMetadata = widget.recording.events.any(
      (event) =>
          event.kind == terminal.TerminalRecordingEventKind.shellSemantic &&
          event.semanticCommand != null,
    );
    final inputDisclosure =
        widget.recording.metadata.inputPolicy ==
            terminal.TerminalRecordingInputPolicy.record
        ? context.l10n.inputIncluded
        : hasCommandMetadata
        ? context.l10n.keystrokesRedactedCommandMetadataIncluded
        : context.l10n.keystrokesRedacted;
    final recordedViewportSize = _recordedViewportSizeFor(viewportController);
    final timelineTimeMap =
        replayController?.timeMap ??
        terminal.TerminalReplayTimeMap.real(widget.entry.duration);
    final timelineMarkers = _recordingTimelineMarkers(
      widget.recording,
      timelineTimeMap,
      context.l10n,
    );
    final timelineModel = _buildReplayTimelineModel(
      points: _recordingSemanticPoints(widget.recording, timelineTimeMap),
      duration: timelineTimeMap.presentationDuration,
      activityLabel: context.l10n.activity,
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
        detailLabel: context.l10n.recordingDetail(
          widget.entry.sessionId ?? context.l10n.recordedSession,
          inputDisclosure,
        ),
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

    final replayViewport = ReplayViewportFrame(
      backgroundColor: widget.terminalColors.canvasBackground,
      borderRadius: BorderRadius.circular(palette.radius.lg),
      child: Stack(
        children: [
          Positioned.fill(
            child:
                errorMessage != null ||
                    runtime == null ||
                    sessionId == null ||
                    viewportController == null ||
                    _selectionController == null ||
                    _inputController == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        errorMessage ?? context.l10n.preparingReplay,
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
    );
    if (context.usesMobileNavigation) {
      return MobileReplayPlayer(
        controller: replayController,
        title: widget.entry.displayName,
        details: inputDisclosure,
        viewport: replayViewport,
        recordedViewportSize: recordedViewportSize,
        onClose: widget.onClose,
        onSearchChanged: _updateSearch,
        searchSummary: _searchHits.isEmpty
            ? null
            : context.l10n.matchesAcrossReplay(_searchHits.length),
        onSearchPrevious: _searchHits.isEmpty
            ? null
            : () => _moveSearchMatch(-1),
        onSearchNext: _searchHits.isEmpty ? null : () => _moveSearchMatch(1),
        onCopyVisible: () => unawaited(_copyVisible()),
      );
    }

    final replayLayout = ColoredBox(
      key: const Key('recording-replay-layout'),
      color: palette.canvas,
      child: Padding(
        padding: keyboardInset > 0
            ? const EdgeInsets.all(4)
            : const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: ReplayFloatingStage(
          key: const Key('recording-replay-stage'),
          margin: keyboardInset > 0 ? 0 : 8,
          bottomInset: keyboardInset,
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
          viewport: replayViewport,
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
        label: context.l10n.replayRecordingLayout(widget.entry.displayName),
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
        _ReplaySourceMark(
          palette: palette,
          sourceLabel: context.l10n.recording,
        ),
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
                  fontWeight: FontWeight.w600,
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
          tooltip: context.l10n.fitRecordedSize,
          onPressed: onFit,
          icon: Icons.fit_screen_rounded,
          palette: palette,
        ),
        _InstantReplayControlButton(
          tooltip: context.l10n.copyVisible,
          onPressed: onCopyVisible,
          icon: Icons.copy_rounded,
          palette: palette,
        ),
        _InstantReplayControlButton(
          tooltip: context.l10n.copySelection,
          onPressed: onCopySelection,
          icon: Icons.select_all_rounded,
          palette: palette,
        ),
        _InstantReplayControlButton(
          key: const Key('recording-replay-close'),
          tooltip: context.l10n.closeReplay,
          onPressed: onClose,
          icon: Icons.close_rounded,
          palette: palette,
        ),
      ],
    );
    final keyboardActions = _InstantReplayControlButton(
      tooltip: context.l10n.closeReplay,
      onPressed: onClose,
      icon: Icons.close_rounded,
      palette: palette,
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
          : context.l10n.matchesAcrossReplay(searchMatchCount),
      onSearchChanged: onSearchChanged,
      onSearchPrevious: onSearchPrevious,
      onSearchNext: onSearchNext,
      palette: palette,
    );
    return Semantics(
      identifier: 'recording-replay-controls',
      container: true,
      explicitChildNodes: true,
      label: context.l10n.replayControlsForRecording,
      child: _ReplayDockLayout(
        timeline: timeline,
        metadata: metadata,
        transport: transport,
        search: search,
        actions: actions,
        keyboardActions: keyboardActions,
        palette: palette,
      ),
    );
  }
}

List<_ReplayTimelineMarker> _recordingTimelineMarkers(
  terminal.TerminalRecording recording,
  terminal.TerminalReplayTimeMap timeMap,
  AppLocalizations l10n,
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
            tooltip: l10n.idleInterval,
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
          terminal.TerminalRecordingEventKind.userInput => l10n.inputEvent,
          terminal.TerminalRecordingEventKind.resize => l10n.terminalResized,
          terminal.TerminalRecordingEventKind.sessionExited =>
            l10n.sessionExited,
          _ => l10n.outputEvent,
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
