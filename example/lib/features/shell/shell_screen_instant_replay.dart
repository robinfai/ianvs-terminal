part of 'shell_screen.dart';

final class _InstantReplayDriver implements terminal.TerminalReplayDriver {
  _InstantReplayDriver({
    required List<InstantReplayFrame> frames,
    required terminal.TerminalViewportController viewportController,
  }) : frames = List<InstantReplayFrame>.unmodifiable(frames),
       _viewportController = viewportController,
       sourceOffsets = _sourceOffsetsFor(frames) {
    _applyFrameAt(Duration.zero);
  }

  final List<InstantReplayFrame> frames;
  final List<Duration> sourceOffsets;
  final terminal.TerminalViewportController _viewportController;
  bool _hasAppliedFrame = false;

  @override
  Duration position = Duration.zero;

  @override
  Duration get duration =>
      sourceOffsets.isEmpty ? Duration.zero : sourceOffsets.last;

  int activeIndex = 0;

  InstantReplayFrame? get activeFrame {
    if (frames.isEmpty) {
      return null;
    }
    return frames[activeIndex.clamp(0, frames.length - 1)];
  }

  Duration offsetForFrameIndex(int index) {
    if (sourceOffsets.isEmpty) {
      return Duration.zero;
    }
    return sourceOffsets[index.clamp(0, sourceOffsets.length - 1)];
  }

  Duration offsetForCapturedAt(DateTime capturedAt) {
    if (frames.isEmpty || !capturedAt.isAfter(frames.first.capturedAt)) {
      return Duration.zero;
    }
    final offset = capturedAt.difference(frames.first.capturedAt);
    return offset > duration ? duration : offset;
  }

  @override
  void advanceTo(Duration sourceOffset) {
    _applyFrameAt(sourceOffset);
  }

  @override
  void seekTo(Duration sourceOffset) {
    _applyFrameAt(sourceOffset);
  }

  void _applyFrameAt(Duration requestedOffset) {
    if (frames.isEmpty) {
      position = Duration.zero;
      activeIndex = 0;
      _viewportController.applySnapshot(terminal.TerminalFrameDiff.empty);
      return;
    }
    final clamped = requestedOffset < Duration.zero
        ? Duration.zero
        : requestedOffset > duration
        ? duration
        : requestedOffset;
    var nextIndex = 0;
    for (var index = 1; index < sourceOffsets.length; index += 1) {
      if (sourceOffsets[index] > clamped) {
        break;
      }
      nextIndex = index;
    }
    position = clamped;
    if (_hasAppliedFrame && activeIndex == nextIndex) {
      return;
    }
    activeIndex = nextIndex;
    _viewportController.applySnapshot(frames[nextIndex].snapshot);
    _hasAppliedFrame = true;
  }

  static List<Duration> _sourceOffsetsFor(List<InstantReplayFrame> frames) {
    if (frames.isEmpty) {
      return const <Duration>[];
    }
    final offsets = <Duration>[Duration.zero];
    for (var index = 1; index < frames.length; index += 1) {
      final actual = frames[index].capturedAt.difference(
        frames.first.capturedAt,
      );
      final minimum = offsets.last + const Duration(milliseconds: 16);
      offsets.add(actual > minimum ? actual : minimum);
    }
    return List<Duration>.unmodifiable(offsets);
  }
}

class _InstantReplayLayout extends StatefulWidget {
  const _InstantReplayLayout({
    super.key,
    required this.layout,
    required this.palette,
    required this.runtime,
    required this.terminalColors,
    required this.font,
    required this.cursor,
    required this.onCopyVisible,
    required this.onClear,
    required this.onExit,
  });

  final _InstantReplayLayoutSession layout;
  final AppThemeTokens palette;
  final terminal.TerminalRuntimeController runtime;
  final terminal.TerminalViewportColors terminalColors;
  final terminal.TerminalFontConfig font;
  final terminal.TerminalCursorConfig cursor;
  final Future<void> Function(String text) onCopyVisible;
  final void Function(String sessionId) onClear;
  final VoidCallback onExit;

  @override
  State<_InstantReplayLayout> createState() => _InstantReplayLayoutState();
}

class _InstantReplayLayoutState extends State<_InstantReplayLayout> {
  late final terminal.TerminalViewportController _viewportController;
  late final SelectionController _selectionController;
  late final TerminalInputController _inputController;
  late final FocusNode _focusNode;
  late _InstantReplayDriver _replayDriver;
  late terminal.TerminalReplayController _replayController;
  Size? _lastReplayViewportSize;
  Size _measuredReplayCellSize = terminal.terminalFallbackCellSize;
  String _searchQuery = '';
  int _searchResultCount = 0;
  int _activeSearchMatchIndex = 0;
  List<terminal.TerminalSearchMatch> _activeSearchMatches = const [];
  List<_InstantReplaySearchHit> _searchHits = const <_InstantReplaySearchHit>[];
  bool _isReplayDockDragging = false;

  InstantReplayFrame? get _activeFrame => _replayDriver.activeFrame;

  @override
  void initState() {
    super.initState();
    _viewportController = terminal.TerminalViewportController();
    _selectionController = SelectionController();
    _focusNode = FocusNode(debugLabel: 'instant-replay-layout');
    _inputController = TerminalInputController(
      sessionId: widget.layout.sourceSessionId,
      runtime: widget.runtime,
      readFrame: () => _viewportController.frame,
      readSelection: () =>
          _selectionController.textForFrame(_viewportController.frame),
      copySelection: ClipboardBridge.copy,
      readClipboard: () async => '',
      readOnly: () => true,
    );
    _configureReplay();
  }

  @override
  void didUpdateWidget(covariant _InstantReplayLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.layout.frames.length != oldWidget.layout.frames.length ||
        widget.layout.sourceSessionId != oldWidget.layout.sourceSessionId) {
      _replayController
        ..removeListener(_handleReplayChanged)
        ..dispose();
      _configureReplay();
    }
  }

  @override
  void dispose() {
    _replayController
      ..removeListener(_handleReplayChanged)
      ..dispose();
    _focusNode.dispose();
    _viewportController.dispose();
    _selectionController.dispose();
    super.dispose();
  }

  void _configureReplay() {
    _replayDriver = _InstantReplayDriver(
      frames: widget.layout.frames,
      viewportController: _viewportController,
    );
    final semanticNavigation = _instantReplayNavigationOffsets();
    _replayController = terminal.TerminalReplayController(
      driver: _replayDriver,
      navigationOffsets: semanticNavigation.isEmpty
          ? _replayDriver.sourceOffsets
          : semanticNavigation,
      smartAnchors: _replayDriver.sourceOffsets,
    )..addListener(_handleReplayChanged);
    _searchHits = _buildSearchHits(_searchQuery);
    _searchResultCount = _searchHits.length;
    _refreshSearchMatches();
  }

  List<Duration> _instantReplayNavigationOffsets() {
    return [
      for (final event in widget.layout.semanticEvents)
        if (event.kind ==
                terminal.TerminalRecordingSemanticKind.commandStarted ||
            event.kind ==
                terminal.TerminalRecordingSemanticKind.remoteSessionStarted ||
            event.kind == terminal.TerminalRecordingSemanticKind.prompt)
          _replayDriver.offsetForCapturedAt(event.capturedAt),
    ];
  }

  void _handleReplayChanged() {
    if (!mounted || _isReplayDockDragging) {
      return;
    }
    setState(_refreshSearchMatches);
  }

  void _handleDockDragStateChanged(bool dragging) {
    _isReplayDockDragging = dragging;
    if (!dragging && mounted) {
      setState(_refreshSearchMatches);
    }
  }

  void _refreshSearchMatches() {
    final frame = _activeFrame;
    if (frame == null) {
      _activeSearchMatches = const <terminal.TerminalSearchMatch>[];
      _activeSearchMatchIndex = 0;
      return;
    }
    _activeSearchMatches = _matchesForFrame(frame, _searchQuery);
    _activeSearchMatchIndex = _activeSearchMatches.isEmpty
        ? 0
        : _activeSearchMatchIndex
              .clamp(0, _activeSearchMatches.length - 1)
              .toInt();
  }

  void _updateSearch(String query) {
    _searchQuery = query;
    _activeSearchMatchIndex = 0;
    _searchHits = _buildSearchHits(query);
    _searchResultCount = _searchHits.length;
    final firstHit = _searchHits.firstOrNull;
    if (firstHit != null) {
      _activeSearchMatchIndex = firstHit.matchIndex;
      _replayController.seekToSource(
        _replayDriver.offsetForFrameIndex(firstHit.firstFrameIndex),
      );
      return;
    }
    setState(_refreshSearchMatches);
  }

  List<terminal.TerminalSearchMatch> _matchesForFrame(
    InstantReplayFrame frame,
    String query,
  ) {
    final needle = query.trim();
    if (needle.isEmpty) {
      return const <terminal.TerminalSearchMatch>[];
    }
    final normalizedNeedle = needle.toLowerCase();
    final matches = <terminal.TerminalSearchMatch>[];
    for (final row in frame.snapshot.rows) {
      final normalizedText = row.text.toLowerCase();
      final textCells = terminal.TerminalTextCells.fromText(row.text);
      var start = normalizedText.indexOf(normalizedNeedle);
      while (start != -1) {
        final end = start + needle.length;
        matches.add(
          terminal.TerminalSearchMatch(
            row: row.index,
            startCol: textCells.columnForCodeUnit(start),
            endCol: textCells.columnForCodeUnit(end),
            text: row.text.substring(start, end),
            scrollbackOffset: frame.snapshot.scrollbackOffset,
          ),
        );
        start = normalizedText.indexOf(normalizedNeedle, start + needle.length);
      }
    }
    return matches;
  }

  List<_InstantReplaySearchHit> _buildSearchHits(String query) {
    if (query.trim().isEmpty) {
      return const <_InstantReplaySearchHit>[];
    }
    final hits = <_InstantReplaySearchHit>[];
    final activeHitIndexes = <_InstantReplaySearchMatchKey, int>{};
    for (
      var frameIndex = 0;
      frameIndex < widget.layout.frames.length;
      frameIndex += 1
    ) {
      final matches = _matchesForFrame(widget.layout.frames[frameIndex], query);
      final visibleKeys = <_InstantReplaySearchMatchKey>{};
      for (var matchIndex = 0; matchIndex < matches.length; matchIndex += 1) {
        final matchKey = _searchMatchKey(matches[matchIndex]);
        visibleKeys.add(matchKey);
        final activeHitIndex = activeHitIndexes[matchKey];
        if (activeHitIndex == null) {
          activeHitIndexes[matchKey] = hits.length;
          hits.add(
            _InstantReplaySearchHit(
              firstFrameIndex: frameIndex,
              lastFrameIndex: frameIndex,
              matchIndex: matchIndex,
              matchKey: matchKey,
            ),
          );
          continue;
        }
        hits[activeHitIndex] = hits[activeHitIndex].extendThrough(frameIndex);
      }
      activeHitIndexes.removeWhere(
        (matchKey, _) => !visibleKeys.contains(matchKey),
      );
    }
    return List<_InstantReplaySearchHit>.unmodifiable(hits);
  }

  _InstantReplaySearchMatchKey _searchMatchKey(
    terminal.TerminalSearchMatch match,
  ) {
    return (
      row: match.row,
      startCol: match.startCol,
      endCol: match.endCol,
      normalizedText: match.text.toLowerCase(),
      scrollbackOffset: match.scrollbackOffset,
    );
  }

  void _moveSearchMatch(int delta) {
    if (_searchHits.isEmpty) {
      return;
    }
    final activeMatch =
        _activeSearchMatchIndex >= 0 &&
            _activeSearchMatchIndex < _activeSearchMatches.length
        ? _activeSearchMatches[_activeSearchMatchIndex]
        : null;
    final activeMatchKey = activeMatch == null
        ? null
        : _searchMatchKey(activeMatch);
    var currentIndex = activeMatchKey == null
        ? -1
        : _searchHits.indexWhere(
            (hit) => hit.contains(
              frameIndex: _replayDriver.activeIndex,
              key: activeMatchKey,
            ),
          );
    if (currentIndex == -1) {
      currentIndex = delta < 0 ? 0 : -1;
    }
    final nextIndex = (currentIndex + delta) % _searchHits.length;
    final normalizedIndex = nextIndex < 0
        ? nextIndex + _searchHits.length
        : nextIndex;
    final hit = _searchHits[normalizedIndex];
    _activeSearchMatchIndex = hit.matchIndex;
    _replayController.seekToSource(
      _replayDriver.offsetForFrameIndex(hit.firstFrameIndex),
    );
  }

  String? _searchSummary() {
    if (_searchQuery.trim().isEmpty) {
      return null;
    }
    if (_searchResultCount == 0) {
      return 'No matches in replay history.';
    }
    final matchLabel = _searchResultCount == 1 ? 'match' : 'matches';
    return '$_searchResultCount unique $matchLabel in replay';
  }

  List<_ReplaySemanticPoint> _instantReplaySemanticPoints() {
    return [
      for (final event in widget.layout.semanticEvents)
        _ReplaySemanticPoint(
          offset: _replayController.timeMap.sourceToPresentation(
            _replayDriver.offsetForCapturedAt(event.capturedAt),
          ),
          kind: event.kind,
          command: event.command,
          cwd: event.cwd,
          hostname: event.hostname,
          exitCode: event.exitCode,
          remote: event.remote,
        ),
    ];
  }

  List<_InstantReplayIdleGapMarker> _idleGapMarkers() {
    final offsets = _replayDriver.sourceOffsets;
    if (offsets.length <= 1) {
      return const <_InstantReplayIdleGapMarker>[];
    }
    final markers = <_InstantReplayIdleGapMarker>[];
    for (var index = 1; index < offsets.length; index += 1) {
      final actualGap = offsets[index] - offsets[index - 1];
      if (actualGap > _replayController.maximumSmartGap) {
        final presentationStart = _replayController.timeMap
            .sourceToPresentation(offsets[index - 1]);
        final presentationEnd = _replayController.timeMap.sourceToPresentation(
          offsets[index],
        );
        final markerElapsed =
            presentationStart +
            Duration(
              microseconds:
                  (presentationEnd - presentationStart).inMicroseconds ~/ 2,
            );
        markers.add(
          _InstantReplayIdleGapMarker(
            value: _timelineValueForDuration(markerElapsed),
            tooltip: 'Idle gap: ${_formatReplayInterval(actualGap)}',
          ),
        );
      }
    }
    return markers;
  }

  Duration _durationFromTimelineValue(double value) {
    return Duration(
      microseconds: (value * Duration.microsecondsPerMillisecond).round(),
    );
  }

  double _timelineValueForDuration(Duration duration) {
    return duration.inMicroseconds / Duration.microsecondsPerMillisecond;
  }

  String _formatReplayInterval(Duration duration) {
    if (duration < const Duration(seconds: 1)) {
      return '${duration.inMilliseconds}ms';
    }
    if (duration < const Duration(minutes: 1)) {
      final seconds = duration.inMilliseconds / Duration.millisecondsPerSecond;
      final decimalPlaces = seconds >= 10 || seconds == seconds.roundToDouble()
          ? 0
          : 1;
      return '${seconds.toStringAsFixed(decimalPlaces)}s';
    }
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${minutes}m ${seconds}s';
  }

  void _fitRecordedSize(InstantReplayFrame frame) {
    unawaited(_fitRecordedSizeToFrame(frame));
  }

  Future<void> _fitRecordedSizeToFrame(InstantReplayFrame frame) async {
    final currentViewportSize = _lastReplayViewportSize;
    if (currentViewportSize == null ||
        currentViewportSize.width <= 0 ||
        currentViewportSize.height <= 0) {
      return;
    }
    final targetSize = _recordedViewportSizeFor(frame);
    await _resizeWindowBy(
      Offset(
        math.max(0, targetSize.width - currentViewportSize.width),
        math.max(0, targetSize.height - currentViewportSize.height),
      ),
    );
  }

  Size _recordedViewportSizeFor(InstantReplayFrame frame) {
    const viewportPadding = 20.0;
    final gridSize = Size(
      frame.snapshot.viewportCols * _measuredReplayCellSize.width +
          viewportPadding,
      frame.snapshot.viewportRows * _measuredReplayCellSize.height +
          viewportPadding,
    );
    final logicalSize = frame.viewportLogicalSize;
    if (logicalSize == null ||
        logicalSize.width <= 0 ||
        logicalSize.height <= 0) {
      return gridSize;
    }
    return Size(
      math.max(logicalSize.width, gridSize.width),
      math.max(logicalSize.height, gridSize.height),
    );
  }

  Future<void> _resizeWindowBy(Offset delta) async {
    if (delta.dx == 0 && delta.dy == 0) {
      return;
    }
    await WindowBridge.resizeBy(widthDelta: delta.dx, heightDelta: delta.dy);
  }

  Future<void> _copySelection() async {
    final selectedText = _selectionController.textForFrame(
      _viewportController.frame,
    );
    if (selectedText.trim().isEmpty) {
      return;
    }
    await ClipboardBridge.copy(selectedText);
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final activeFrame = _activeFrame;
    final recordedViewportSize = activeFrame == null
        ? null
        : _recordedViewportSizeFor(activeFrame);
    Widget replayControls() {
      final liveFrame = _activeFrame;
      final replayState = _replayController.state;
      final frameLabel = liveFrame == null
          ? 'No replay frames'
          : 'Recorded at ${liveFrame.snapshot.viewportCols}x${liveFrame.snapshot.viewportRows}';
      final hasMultipleFrames = widget.layout.frames.length > 1;
      final canPlay = liveFrame != null && hasMultipleFrames;
      return _InstantReplayLayoutControls(
        key: const Key('instant-replay-controls'),
        sourceLabel: widget.layout.sourceLabel,
        frameLabel: frameLabel,
        retentionFrameLimit: widget.layout.retentionFrameLimit,
        frameCount: widget.layout.frames.length,
        timelineValue: _timelineValueForDuration(
          replayState.presentationPosition,
        ),
        timelineMax: math.max(
          _timelineValueForDuration(replayState.presentationDuration),
          hasMultipleFrames ? 1.0 : 0.0,
        ),
        changeMarkerValues: [
          for (final offset in _replayDriver.sourceOffsets)
            _timelineValueForDuration(
              _replayController.timeMap.sourceToPresentation(offset),
            ),
        ],
        idleGapMarkers: _idleGapMarkers(),
        semanticPoints: _instantReplaySemanticPoints(),
        position: replayState.presentationPosition,
        duration: replayState.presentationDuration,
        sourcePosition: replayState.sourcePosition,
        sourceDuration: replayState.sourceDuration,
        activeFrame: liveFrame,
        isPlaying: replayState.isPlaying,
        playbackSpeed: replayState.speed,
        timeMode: replayState.timeMode,
        onFitRecordedSize: liveFrame == null
            ? null
            : () => _fitRecordedSize(liveFrame),
        onExit: widget.onExit,
        onStepBack: _replayController.canStepPrevious
            ? _replayController.stepPrevious
            : null,
        onStepForward: _replayController.canStepNext
            ? _replayController.stepNext
            : null,
        onTogglePlay: canPlay ? _replayController.togglePlayback : null,
        onSpeedChanged: _replayController.setSpeed,
        onTimeModeChanged: _replayController.setTimeMode,
        onClear: () => widget.onClear(widget.layout.sourceSessionId),
        searchSummary: _searchSummary(),
        onSearchChanged: _updateSearch,
        onSearchPrevious: _searchResultCount == 0
            ? null
            : () => _moveSearchMatch(-1),
        onSearchNext: _searchResultCount == 0
            ? null
            : () => _moveSearchMatch(1),
        onCopySelection: liveFrame == null ? null : _copySelection,
        onCopyVisible: liveFrame == null
            ? null
            : () => unawaited(widget.onCopyVisible(liveFrame.text)),
        onSliderChanged: hasMultipleFrames
            ? (value) => _replayController.seekToPresentation(
                _durationFromTimelineValue(value),
              )
            : null,
        palette: palette,
      );
    }

    Widget replayViewport() {
      return ReplayViewportFrame(
        backgroundColor: widget.terminalColors.canvasBackground,
        borderRadius: BorderRadius.circular(palette.radius.md),
        child: activeFrame == null
            ? Center(
                child: Text(
                  'No replay frames captured yet.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: palette.textSubtle),
                ),
              )
            : TerminalViewport(
                key: const Key('instant-replay-viewport'),
                focusNode: _focusNode,
                controller: _viewportController,
                selectionController: _selectionController,
                inputController: _inputController,
                contentPadding: const EdgeInsets.all(10),
                colors: widget.terminalColors,
                useFrameDefaultColors: false,
                font: widget.font,
                cursor: widget.cursor,
                copyOnSelect: false,
                onMeasuredCellSizeChanged: (cellSize) {
                  if (_measuredReplayCellSize == cellSize) {
                    return;
                  }
                  setState(() {
                    _measuredReplayCellSize = cellSize;
                  });
                },
                searchMatches: _activeSearchMatches,
                activeSearchMatchIndex: _activeSearchMatches.isEmpty
                    ? -1
                    : _activeSearchMatchIndex,
                searchHighlightStyle: terminal.TerminalSearchHighlightStyle(
                  activeFill: palette.accent.withValues(alpha: 0.34),
                  inactiveFill: palette.warning.withValues(alpha: 0.22),
                  activeBorder: palette.accent.withValues(alpha: 0.82),
                  radius: 3,
                ),
                onHostKeyEvent: (event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.escape) {
                    widget.onExit();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
                onOpenLink: (url) =>
                    unawaited(WindowBridge.openExternalUrl(url)),
              ),
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onExit,
      },
      child: Semantics(
        identifier: 'instant-replay-layout',
        container: true,
        explicitChildNodes: true,
        label: 'Replay recent activity layout',
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: ColoredBox(
            color: palette.canvas,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ReplayFloatingStage(
                key: const Key('instant-replay-stage'),
                recordedViewportSize: recordedViewportSize,
                viewportFitKey: const Key('instant-replay-fit'),
                viewportContentKey: const Key('instant-replay-fit-content'),
                floatingDockKey: const Key('instant-replay-floating-dock'),
                dragHandleKey: const Key('instant-replay-dock-drag-handle'),
                dragHandleColor: palette.textMuted,
                onAvailableSizeChanged: (size) {
                  _lastReplayViewportSize = size;
                },
                onDockDragStateChanged: _handleDockDragStateChanged,
                viewport: replayViewport(),
                dock: ListenableBuilder(
                  listenable: _replayController,
                  builder: (context, _) => replayControls(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InstantReplayLayoutControls extends StatelessWidget {
  const _InstantReplayLayoutControls({
    super.key,
    required this.sourceLabel,
    required this.frameLabel,
    required this.retentionFrameLimit,
    required this.frameCount,
    required this.timelineValue,
    required this.timelineMax,
    required this.changeMarkerValues,
    required this.idleGapMarkers,
    required this.semanticPoints,
    required this.position,
    required this.duration,
    required this.sourcePosition,
    required this.sourceDuration,
    required this.activeFrame,
    required this.isPlaying,
    required this.playbackSpeed,
    required this.timeMode,
    required this.onFitRecordedSize,
    required this.onExit,
    required this.onStepBack,
    required this.onStepForward,
    required this.onTogglePlay,
    required this.onSpeedChanged,
    required this.onTimeModeChanged,
    required this.onClear,
    required this.searchSummary,
    required this.onSearchChanged,
    required this.onSearchPrevious,
    required this.onSearchNext,
    required this.onCopySelection,
    required this.onCopyVisible,
    required this.onSliderChanged,
    required this.palette,
  });

  final String sourceLabel;
  final String frameLabel;
  final int retentionFrameLimit;
  final int frameCount;
  final double timelineValue;
  final double timelineMax;
  final List<double> changeMarkerValues;
  final List<_InstantReplayIdleGapMarker> idleGapMarkers;
  final List<_ReplaySemanticPoint> semanticPoints;
  final Duration position;
  final Duration duration;
  final Duration sourcePosition;
  final Duration sourceDuration;
  final InstantReplayFrame? activeFrame;
  final bool isPlaying;
  final double playbackSpeed;
  final terminal.TerminalReplayTimeMode timeMode;
  final VoidCallback? onFitRecordedSize;
  final VoidCallback onExit;
  final VoidCallback? onStepBack;
  final VoidCallback? onStepForward;
  final VoidCallback? onTogglePlay;
  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<terminal.TerminalReplayTimeMode> onTimeModeChanged;
  final VoidCallback onClear;
  final String? searchSummary;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback? onSearchPrevious;
  final VoidCallback? onSearchNext;
  final Future<void> Function()? onCopySelection;
  final VoidCallback? onCopyVisible;
  final ValueChanged<double>? onSliderChanged;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    final frame = activeFrame;
    final timestamp = frame?.capturedAt;
    final frameDetail = timestamp == null
        ? frameLabel
        : '$frameLabel • ${_frameTimeLabel(timestamp)}';
    final playbackControls = _InstantReplayPlaybackControls(
      isPlaying: isPlaying,
      speed: playbackSpeed,
      timeMode: timeMode,
      onStepBack: onStepBack,
      onTogglePlay: onTogglePlay,
      onStepForward: onStepForward,
      onSpeedChanged: onSpeedChanged,
      onTimeModeChanged: onTimeModeChanged,
      palette: palette,
    );
    final actions = _InstantReplayActionControls(
      activeFrame: frame,
      frameCount: frameCount,
      onFitRecordedSize: onFitRecordedSize,
      onCopyVisible: onCopyVisible,
      onCopySelection: onCopySelection,
      onClear: onClear,
      onExit: onExit,
      includeClose: true,
      palette: palette,
    );
    final header = _InstantReplayControlHeader(
      sourceLabel: sourceLabel,
      frameDetail: frameDetail,
      retentionPolicyLabel: _retentionPolicyLabel(retentionFrameLimit),
      palette: palette,
    );
    final timeline = _ReplaySemanticTimeline(
      timelineKey: const Key('instant-replay-timeline'),
      effectsKey: const Key('instant-replay-timeline-effects'),
      changeMarkerKey: const Key('instant-replay-change-marker'),
      idleMarkerKey: const Key('instant-replay-idle-marker'),
      quietTrackKey: const Key('instant-replay-quiet-track'),
      value: timelineValue,
      max: timelineMax <= 0 ? 1 : timelineMax,
      position: position,
      duration: duration,
      displayPosition: sourcePosition,
      displayDuration: sourceDuration,
      model: _buildReplayTimelineModel(
        points: semanticPoints,
        duration: duration,
      ),
      markers: [
        for (final value in changeMarkerValues)
          _ReplayTimelineMarker(
            value: value,
            kind: _ReplayTimelineMarkerKind.output,
            tooltip: 'Terminal changed',
          ),
        for (final marker in idleGapMarkers)
          _ReplayTimelineMarker(
            value: marker.value,
            kind: _ReplayTimelineMarkerKind.idle,
            tooltip: marker.tooltip,
          ),
      ],
      onChanged: onSliderChanged,
      palette: palette,
    );
    final search = _InstantReplaySearchControls(
      enabled: frameCount > 0,
      searchSummary: searchSummary,
      onSearchChanged: onSearchChanged,
      onSearchPrevious: onSearchPrevious,
      onSearchNext: onSearchNext,
      palette: palette,
    );
    return Semantics(
      identifier: 'instant-replay-controls',
      container: true,
      explicitChildNodes: true,
      label: 'Replay controls for recent activity',
      child: _ReplayDockLayout(
        timeline: timeline,
        metadata: header,
        transport: playbackControls,
        search: search,
        actions: actions,
        palette: palette,
      ),
    );
  }

  static String _frameTimeLabel(DateTime timestamp) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${twoDigits(timestamp.hour)}:${twoDigits(timestamp.minute)}:${twoDigits(timestamp.second)}';
  }

  static String _retentionPolicyLabel(int frameLimit) {
    if (frameLimit <= 0) {
      return 'Retention disabled';
    }
    return 'Retains latest $frameLimit frame${frameLimit == 1 ? '' : 's'}';
  }
}

class _InstantReplayControlHeader extends StatelessWidget {
  const _InstantReplayControlHeader({
    required this.sourceLabel,
    required this.frameDetail,
    required this.retentionPolicyLabel,
    required this.palette,
  });

  final String sourceLabel;
  final String frameDetail;
  final String retentionPolicyLabel;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ReplaySourceMark(palette: palette, sourceLabel: 'Recent activity'),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$sourceLabel • $frameDetail',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: palette.textSubtle,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                retentionPolicyLabel,
                key: const Key('instant-replay-retention-policy'),
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
  }
}

class _InstantReplayPlaybackControls extends StatelessWidget {
  const _InstantReplayPlaybackControls({
    this.toggleKey,
    this.speedKey = const Key('instant-replay-speed'),
    this.timeModeKey = const Key('instant-replay-time-mode'),
    required this.isPlaying,
    required this.speed,
    required this.timeMode,
    required this.onStepBack,
    required this.onTogglePlay,
    required this.onStepForward,
    required this.onSpeedChanged,
    required this.onTimeModeChanged,
    required this.palette,
  });

  final Key? toggleKey;
  final Key speedKey;
  final Key timeModeKey;
  final bool isPlaying;
  final double speed;
  final terminal.TerminalReplayTimeMode timeMode;
  final VoidCallback? onStepBack;
  final VoidCallback? onTogglePlay;
  final VoidCallback? onStepForward;
  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<terminal.TerminalReplayTimeMode> onTimeModeChanged;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _InstantReplayControlButton(
          tooltip: 'Step back in replay',
          onPressed: onStepBack,
          icon: Icons.skip_previous_rounded,
          palette: palette,
        ),
        const SizedBox(width: 4),
        _InstantReplayControlButton(
          key: toggleKey,
          tooltip: isPlaying ? 'Pause replay' : 'Play replay',
          onPressed: onTogglePlay,
          icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          active: isPlaying,
          palette: palette,
        ),
        const SizedBox(width: 4),
        _InstantReplayControlButton(
          tooltip: 'Step forward in replay',
          onPressed: onStepForward,
          icon: Icons.skip_next_rounded,
          palette: palette,
        ),
        const SizedBox(width: 4),
        _ReplaySpeedControl(
          key: speedKey,
          speed: speed,
          onSpeedChanged: onSpeedChanged,
          palette: palette,
        ),
        const SizedBox(width: 4),
        _ReplayTimeModeControl(
          key: timeModeKey,
          mode: timeMode,
          onChanged: onTimeModeChanged,
          palette: palette,
        ),
      ],
    );
  }
}

const _replayPlaybackSpeeds = <double>[0.25, 0.5, 1, 2, 4];

class _ReplaySpeedControl extends StatelessWidget {
  const _ReplaySpeedControl({
    super.key,
    required this.speed,
    required this.onSpeedChanged,
    required this.palette,
  });

  final double speed;
  final ValueChanged<double> onSpeedChanged;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    final speedLabel = speed == speed.roundToDouble()
        ? speed.toInt().toString()
        : speed.toString();
    return Semantics(
      label: 'Playback speed $speedLabel times',
      button: true,
      child: PopupMenuButton<double>(
        tooltip: 'Playback speed',
        onSelected: onSpeedChanged,
        itemBuilder: (context) => [
          for (final item in _replayPlaybackSpeeds)
            PopupMenuItem(
              value: item,
              child: Text(
                '${item == item.roundToDouble() ? item.toInt() : item}×',
              ),
            ),
        ],
        child: Container(
          height: 36,
          constraints: const BoxConstraints(minWidth: 46),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: palette.canvas.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(palette.radius.md),
            border: Border.all(
              color: palette.borderStrong.withValues(alpha: 0.54),
            ),
          ),
          child: Text(
            '$speedLabel×',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: palette.textSubtle,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReplayTimeModeControl extends StatelessWidget {
  const _ReplayTimeModeControl({
    super.key,
    required this.mode,
    required this.onChanged,
    required this.palette,
  });

  final terminal.TerminalReplayTimeMode mode;
  final ValueChanged<terminal.TerminalReplayTimeMode> onChanged;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    final label = switch (mode) {
      terminal.TerminalReplayTimeMode.realTime => 'Real',
      terminal.TerminalReplayTimeMode.smart => 'Smart',
    };
    return Semantics(
      label: '$label replay timing',
      button: true,
      child: PopupMenuButton<terminal.TerminalReplayTimeMode>(
        tooltip: 'Replay timing',
        onSelected: onChanged,
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: terminal.TerminalReplayTimeMode.smart,
            child: Text('Smart · skip long idle gaps'),
          ),
          PopupMenuItem(
            value: terminal.TerminalReplayTimeMode.realTime,
            child: Text('Real time · preserve all gaps'),
          ),
        ],
        child: Container(
          height: 36,
          constraints: const BoxConstraints(minWidth: 58),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: palette.canvas.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(palette.radius.md),
            border: Border.all(
              color: palette.borderStrong.withValues(alpha: 0.54),
            ),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: palette.textSubtle,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _InstantReplayActionControls extends StatelessWidget {
  const _InstantReplayActionControls({
    required this.activeFrame,
    required this.frameCount,
    required this.onFitRecordedSize,
    required this.onCopyVisible,
    required this.onCopySelection,
    required this.onClear,
    required this.onExit,
    required this.includeClose,
    required this.palette,
  });

  final InstantReplayFrame? activeFrame;
  final int frameCount;
  final VoidCallback? onFitRecordedSize;
  final VoidCallback? onCopyVisible;
  final Future<void> Function()? onCopySelection;
  final VoidCallback onClear;
  final VoidCallback onExit;
  final bool includeClose;
  final AppThemeTokens palette;

  Widget get closeButton {
    return _InstantReplayControlButton(
      tooltip: 'Close replay',
      onPressed: onExit,
      icon: Icons.close_rounded,
      palette: palette,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _InstantReplayControlButton(
          key: const Key('instant-replay-fit-recorded-size'),
          tooltip: 'Fit recorded size',
          onPressed: onFitRecordedSize,
          icon: Icons.fit_screen_rounded,
          palette: palette,
        ),
        _InstantReplayControlButton(
          key: const Key('instant-replay-copy-visible'),
          tooltip: 'Copy visible',
          onPressed: onCopyVisible,
          icon: Icons.copy_rounded,
          palette: palette,
        ),
        _InstantReplayControlButton(
          key: const Key('instant-replay-copy-selection'),
          tooltip: 'Copy selection',
          onPressed: onCopySelection == null
              ? null
              : () => unawaited(onCopySelection!()),
          icon: Icons.select_all_rounded,
          palette: palette,
        ),
        _InstantReplayControlButton(
          key: const Key('instant-replay-clear'),
          tooltip: 'Clear history',
          onPressed: frameCount == 0 ? null : onClear,
          icon: Icons.delete_outline_rounded,
          palette: palette,
        ),
        if (includeClose) closeButton,
      ],
    );
  }
}

class _InstantReplaySearchControls extends StatelessWidget {
  const _InstantReplaySearchControls({
    this.searchKey = const Key('instant-replay-search'),
    this.previousKey = const Key('instant-replay-search-previous'),
    this.nextKey = const Key('instant-replay-search-next'),
    required this.enabled,
    required this.searchSummary,
    required this.onSearchChanged,
    required this.onSearchPrevious,
    required this.onSearchNext,
    required this.palette,
  });

  final Key searchKey;
  final Key previousKey;
  final Key nextKey;
  final bool enabled;
  final String? searchSummary;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback? onSearchPrevious;
  final VoidCallback? onSearchNext;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    final searchField = Focus(
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey != LogicalKeyboardKey.enter) {
          return KeyEventResult.ignored;
        }
        if (HardwareKeyboard.instance.isShiftPressed) {
          onSearchPrevious?.call();
        } else {
          onSearchNext?.call();
        }
        return KeyEventResult.handled;
      },
      child: TextField(
        key: searchKey,
        enabled: enabled,
        onChanged: onSearchChanged,
        textInputAction: TextInputAction.search,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: palette.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        cursorColor: palette.accent,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search_rounded, size: 19),
          hintText: 'Search replay',
          isDense: true,
          filled: true,
          fillColor: palette.canvas.withValues(alpha: 0.28),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 10,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(palette.radius.md),
            borderSide: BorderSide(
              color: palette.borderStrong.withValues(alpha: 0.62),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(palette.radius.md),
            borderSide: BorderSide(color: palette.accent, width: 1.5),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(palette.radius.md),
            borderSide: BorderSide(
              color: palette.border.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: searchField),
        const SizedBox(width: 6),
        _InstantReplayControlButton(
          key: previousKey,
          tooltip: 'Previous search match',
          onPressed: onSearchPrevious,
          icon: Icons.keyboard_arrow_up_rounded,
          palette: palette,
        ),
        const SizedBox(width: 4),
        _InstantReplayControlButton(
          key: nextKey,
          tooltip: 'Next search match',
          onPressed: onSearchNext,
          icon: Icons.keyboard_arrow_down_rounded,
          active: onSearchNext != null,
          palette: palette,
        ),
        if (searchSummary != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: _SearchSummaryText(
              searchSummary: searchSummary!,
              palette: palette,
            ),
          ),
        ],
      ],
    );
  }
}

class _InstantReplayControlButton extends StatelessWidget {
  const _InstantReplayControlButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    required this.palette,
    this.active = false,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;
  final AppThemeTokens palette;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final background = active
        ? palette.accent
        : palette.canvas.withValues(alpha: 0.18);
    final foreground = !enabled
        ? palette.textSubtle.withValues(alpha: 0.54)
        : active
        ? palette.canvas
        : palette.textSubtle;
    final borderColor = active
        ? palette.accent.withValues(alpha: 0.68)
        : palette.borderStrong.withValues(alpha: 0.54);

    return Semantics(
      label: tooltip,
      button: true,
      enabled: enabled,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
        style: ButtonStyle(
          fixedSize: const WidgetStatePropertyAll(Size.square(36)),
          minimumSize: const WidgetStatePropertyAll(Size.square(36)),
          maximumSize: const WidgetStatePropertyAll(Size.square(36)),
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          visualDensity: VisualDensity.compact,
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return palette.canvas.withValues(alpha: 0.08);
            }
            if (states.contains(WidgetState.hovered) && !active) {
              return palette.accent.withValues(alpha: 0.14);
            }
            return background;
          }),
          foregroundColor: WidgetStatePropertyAll(foreground),
          overlayColor: WidgetStatePropertyAll(
            palette.accent.withValues(alpha: active ? 0.20 : 0.12),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(palette.radius.md),
              side: BorderSide(color: borderColor),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchSummaryText extends StatelessWidget {
  const _SearchSummaryText({
    required this.searchSummary,
    required this.palette,
  });

  final String searchSummary;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return Text(
      searchSummary,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: palette.textSubtle,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
