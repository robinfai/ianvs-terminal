part of 'shell_screen.dart';

final class InstantReplayCommandBlockSource {
  const InstantReplayCommandBlockSource({
    required this.commandBlockId,
    required this.command,
    this.cwd,
    this.statusLabel,
  });

  factory InstantReplayCommandBlockSource.fromBlock(ShellCommandBlock block) {
    return InstantReplayCommandBlockSource(
      commandBlockId: block.id,
      command: block.command.trim().isEmpty
          ? 'Unknown command'
          : block.command.trim(),
      cwd: block.cwd?.trim(),
      statusLabel: _statusLabel(block),
    );
  }

  final String commandBlockId;
  final String command;
  final String? cwd;
  final String? statusLabel;

  String get replayHeaderLabel => 'Replay from: $command';
}

class _InstantReplayWorkspace extends StatefulWidget {
  const _InstantReplayWorkspace({
    super.key,
    required this.workspace,
    required this.palette,
    required this.runtime,
    required this.terminalColors,
    required this.font,
    required this.cursor,
    required this.onCopyVisible,
    required this.onClear,
    required this.onExit,
  });

  final _InstantReplayWorkspaceSession workspace;
  final AppThemeTokens palette;
  final terminal.TerminalRuntimeController runtime;
  final terminal.TerminalViewportColors terminalColors;
  final terminal.TerminalFontConfig font;
  final terminal.TerminalCursorConfig cursor;
  final Future<void> Function(String text) onCopyVisible;
  final void Function(String sessionId) onClear;
  final VoidCallback onExit;

  @override
  State<_InstantReplayWorkspace> createState() =>
      _InstantReplayWorkspaceState();
}

class _InstantReplayWorkspaceState extends State<_InstantReplayWorkspace> {
  static const _playbackTick = Duration(milliseconds: 16);
  static const _maxPlaybackFrameGap = Duration(seconds: 2);

  late final terminal.TerminalViewportController _viewportController;
  late final SelectionController _selectionController;
  late final TerminalInputController _inputController;
  late final FocusNode _focusNode;
  Size? _lastReplayViewportSize;
  Size _measuredReplayCellSize = terminal.terminalFallbackCellSize;
  int _activeIndex = 0;
  Duration _playheadElapsed = Duration.zero;
  Duration _playbackBaseElapsed = Duration.zero;
  bool _isPlaying = false;
  Timer? _playTimer;
  String _searchQuery = '';
  int _searchResultCount = 0;
  int _activeSearchMatchIndex = 0;
  List<terminal.TerminalSearchMatch> _activeSearchMatches = const [];

  InstantReplayFrame? get _activeFrame {
    final frames = widget.workspace.frames;
    if (frames.isEmpty) {
      return null;
    }
    final index = _activeIndex.clamp(0, frames.length - 1).toInt();
    return frames[index];
  }

  @override
  void initState() {
    super.initState();
    _activeIndex = _initialActiveIndex(widget.workspace.frames);
    _playheadElapsed = _elapsedForFrameIndex(_activeIndex);
    _viewportController = terminal.TerminalViewportController();
    _selectionController = SelectionController();
    _focusNode = FocusNode(debugLabel: 'instant-replay-workspace');
    _inputController = TerminalInputController(
      sessionId: widget.workspace.sourceSessionId,
      runtime: widget.runtime,
      readFrame: () => _viewportController.frame,
      readSelection: () =>
          _selectionController.textForFrame(_viewportController.frame),
      copySelection: ClipboardBridge.copy,
      readClipboard: () async => '',
      readOnly: () => true,
    );
    _applyActiveFrame();
  }

  @override
  void didUpdateWidget(covariant _InstantReplayWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.workspace.frames.length != oldWidget.workspace.frames.length ||
        widget.workspace.sourceSessionId !=
            oldWidget.workspace.sourceSessionId) {
      _activeIndex = _initialActiveIndex(widget.workspace.frames);
      _playheadElapsed = _elapsedForFrameIndex(_activeIndex);
      if (widget.workspace.frames.isEmpty) {
        _stopPlayback();
      }
      _applyActiveFrame();
    }
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    _focusNode.dispose();
    _viewportController.dispose();
    _selectionController.dispose();
    super.dispose();
  }

  void _applyActiveFrame() {
    final frame = _activeFrame;
    if (frame == null) {
      _viewportController.applySnapshot(terminal.TerminalFrameDiff.empty);
      _activeSearchMatches = const <terminal.TerminalSearchMatch>[];
      _activeSearchMatchIndex = 0;
      return;
    }
    _viewportController.applySnapshot(frame.snapshot);
    _activeSearchMatches = _matchesForFrame(frame, _searchQuery);
    _activeSearchMatchIndex = _activeSearchMatches.isEmpty
        ? 0
        : _activeSearchMatchIndex
              .clamp(0, _activeSearchMatches.length - 1)
              .toInt();
  }

  int _initialActiveIndex(List<InstantReplayFrame> frames) {
    final firstVisible = frames.indexWhere((frame) => frame.text.isNotEmpty);
    if (firstVisible != -1) {
      return firstVisible;
    }
    return 0;
  }

  void _updateSearch(String query) {
    setState(() {
      _stopPlayback();
      _searchQuery = query;
      _searchResultCount = 0;
      _activeSearchMatchIndex = 0;
      int? firstMatchingIndex;
      for (var index = 0; index < widget.workspace.frames.length; index += 1) {
        final matches = _matchesForFrame(widget.workspace.frames[index], query);
        if (matches.isNotEmpty && firstMatchingIndex == null) {
          firstMatchingIndex = index;
        }
        _searchResultCount += matches.length;
      }
      if (firstMatchingIndex != null) {
        _activeIndex = firstMatchingIndex;
        _playheadElapsed = _elapsedForFrameIndex(firstMatchingIndex);
      }
      _applyActiveFrame();
    });
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

  List<_InstantReplaySearchHit> _searchHits() {
    if (_searchQuery.trim().isEmpty) {
      return const <_InstantReplaySearchHit>[];
    }
    final hits = <_InstantReplaySearchHit>[];
    for (
      var frameIndex = 0;
      frameIndex < widget.workspace.frames.length;
      frameIndex += 1
    ) {
      final matches = _matchesForFrame(
        widget.workspace.frames[frameIndex],
        _searchQuery,
      );
      for (var matchIndex = 0; matchIndex < matches.length; matchIndex += 1) {
        hits.add(
          _InstantReplaySearchHit(
            frameIndex: frameIndex,
            matchIndex: matchIndex,
          ),
        );
      }
    }
    return hits;
  }

  void _moveSearchMatch(int delta) {
    final hits = _searchHits();
    if (hits.isEmpty) {
      return;
    }
    var currentIndex = hits.indexWhere(
      (hit) =>
          hit.frameIndex == _activeIndex &&
          hit.matchIndex == _activeSearchMatchIndex,
    );
    if (currentIndex == -1) {
      currentIndex = delta < 0 ? 0 : -1;
    }
    final nextIndex = (currentIndex + delta) % hits.length;
    final normalizedIndex = nextIndex < 0 ? nextIndex + hits.length : nextIndex;
    final hit = hits[normalizedIndex];
    setState(() {
      _stopPlayback();
      _activeIndex = hit.frameIndex;
      _activeSearchMatchIndex = hit.matchIndex;
      _playheadElapsed = _elapsedForFrameIndex(hit.frameIndex);
      _applyActiveFrame();
    });
  }

  String? _searchSummary() {
    if (_searchQuery.trim().isEmpty) {
      return null;
    }
    if (_searchResultCount == 0) {
      return 'No matches in replay history.';
    }
    final matchLabel = _searchResultCount == 1 ? 'match' : 'matches';
    final frameLabel = widget.workspace.frames.length == 1 ? 'frame' : 'frames';
    return '$_searchResultCount $matchLabel across ${widget.workspace.frames.length} $frameLabel';
  }

  void _setActiveIndex(int index) {
    setState(() {
      _stopPlayback();
      _activeIndex = index
          .clamp(0, math.max(0, widget.workspace.frames.length - 1))
          .toInt();
      _activeSearchMatchIndex = 0;
      _playheadElapsed = _elapsedForFrameIndex(_activeIndex);
      _applyActiveFrame();
    });
  }

  void _togglePlayback() {
    if (_isPlaying) {
      setState(_stopPlayback);
      return;
    }
    if (_playheadElapsed >= _timelineDuration) {
      return;
    }
    setState(() {
      _isPlaying = true;
    });
    _startPlaybackTimer();
  }

  void _startPlaybackTimer() {
    _playTimer?.cancel();
    if (!_isPlaying || _playheadElapsed >= _timelineDuration) {
      _stopPlayback();
      return;
    }
    _playbackBaseElapsed = _playheadElapsed;
    _playTimer = Timer.periodic(_playbackTick, (timer) {
      if (!mounted) {
        _playTimer?.cancel();
        return;
      }
      final tickElapsed = Duration(
        microseconds: _playbackTick.inMicroseconds * timer.tick,
      );
      final nextPlayhead = _playbackBaseElapsed + tickElapsed;
      final timelineDuration = _timelineDuration;
      setState(() {
        _playheadElapsed = _clampDuration(
          nextPlayhead,
          Duration.zero,
          timelineDuration,
        );
        final nextIndex = _frameIndexForElapsed(_playheadElapsed);
        if (_activeIndex != nextIndex) {
          _activeIndex = nextIndex;
          _applyActiveFrame();
        }
        if (_playheadElapsed >= timelineDuration) {
          _stopPlayback();
        }
      });
    });
  }

  Duration get _timelineDuration {
    final frames = widget.workspace.frames;
    if (frames.length <= 1) {
      return Duration.zero;
    }
    return _elapsedForFrameIndex(frames.length - 1);
  }

  Duration _elapsedForFrameIndex(int index) {
    final frames = widget.workspace.frames;
    if (frames.isEmpty || index <= 0) {
      return Duration.zero;
    }
    var elapsed = Duration.zero;
    final targetIndex = index.clamp(0, frames.length - 1).toInt();
    for (var candidate = 1; candidate <= targetIndex; candidate += 1) {
      elapsed += _playbackGapBeforeFrameIndex(candidate);
    }
    return elapsed;
  }

  Duration _playbackGapBeforeFrameIndex(int index) {
    final actualGap = _actualGapBeforeFrameIndex(index);
    if (actualGap > Duration.zero) {
      return actualGap > _maxPlaybackFrameGap
          ? _maxPlaybackFrameGap
          : actualGap;
    }
    return _playbackTick;
  }

  Duration _actualGapBeforeFrameIndex(int index) {
    final frames = widget.workspace.frames;
    if (index <= 0 || index >= frames.length) {
      return Duration.zero;
    }
    return frames[index].capturedAt.difference(frames[index - 1].capturedAt);
  }

  List<_InstantReplayIdleGapMarker> _idleGapMarkers() {
    final frames = widget.workspace.frames;
    if (frames.length <= 1) {
      return const <_InstantReplayIdleGapMarker>[];
    }
    final markers = <_InstantReplayIdleGapMarker>[];
    var elapsed = Duration.zero;
    for (var index = 1; index < frames.length; index += 1) {
      final actualGap = _actualGapBeforeFrameIndex(index);
      final playbackGap = _playbackGapBeforeFrameIndex(index);
      if (actualGap > _maxPlaybackFrameGap) {
        final markerElapsed =
            elapsed + Duration(microseconds: playbackGap.inMicroseconds ~/ 2);
        markers.add(
          _InstantReplayIdleGapMarker(
            value: _timelineValueForDuration(markerElapsed),
            tooltip: 'Idle gap: ${_formatReplayInterval(actualGap)}',
          ),
        );
      }
      elapsed += playbackGap;
    }
    return markers;
  }

  int _frameIndexForElapsed(Duration elapsed) {
    final frames = widget.workspace.frames;
    if (frames.isEmpty) {
      return 0;
    }
    var index = 0;
    for (var candidate = 1; candidate < frames.length; candidate += 1) {
      if (_elapsedForFrameIndex(candidate) <= elapsed) {
        index = candidate;
      } else {
        break;
      }
    }
    return index;
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

  Duration _clampDuration(Duration value, Duration min, Duration max) {
    if (value < min) {
      return min;
    }
    if (value > max) {
      return max;
    }
    return value;
  }

  void _stopPlayback() {
    _playTimer?.cancel();
    _playTimer = null;
    _isPlaying = false;
  }

  void _fitRecordedSize(InstantReplayFrame frame) {
    unawaited(_fitRecordedSizeToFrame(frame));
  }

  Future<void> _fitRecordedSizeToFrame(InstantReplayFrame frame) async {
    final recordedWindowContentSize = frame.windowContentSize;
    if (recordedWindowContentSize != null) {
      final currentWindowContentSize =
          (await WindowBridge.metrics())?.contentSize;
      if (currentWindowContentSize != null) {
        await _resizeWindowBy(
          Offset(
            recordedWindowContentSize.width - currentWindowContentSize.width,
            recordedWindowContentSize.height - currentWindowContentSize.height,
          ),
        );
        return;
      }
    }

    final currentViewportSize = _lastReplayViewportSize;
    if (currentViewportSize == null ||
        currentViewportSize.width <= 0 ||
        currentViewportSize.height <= 0) {
      return;
    }
    final targetSize =
        frame.viewportLogicalSize ??
        Size(
          frame.snapshot.viewportCols * _measuredReplayCellSize.width,
          frame.snapshot.viewportRows * _measuredReplayCellSize.height,
        );
    await _resizeWindowBy(
      Offset(
        targetSize.width - currentViewportSize.width,
        targetSize.height - currentViewportSize.height,
      ),
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
    final frameLabel = activeFrame == null
        ? 'No replay frames'
        : 'Recorded at ${activeFrame.snapshot.viewportCols}x${activeFrame.snapshot.viewportRows}';
    final hasMultipleFrames = widget.workspace.frames.length > 1;
    final canStepBack = activeFrame != null && _activeIndex > 0;
    final canStepForward =
        activeFrame != null &&
        _activeIndex < widget.workspace.frames.length - 1;
    final canPlay =
        activeFrame != null &&
        (_isPlaying || _playheadElapsed < _timelineDuration);
    final controls = _InstantReplayWorkspaceControls(
      key: const Key('instant-replay-controls'),
      sourceLabel: widget.workspace.sourceLabel,
      commandBlockSource: widget.workspace.commandBlockSource,
      frameLabel: frameLabel,
      frameCount: widget.workspace.frames.length,
      activeIndex: _activeIndex,
      timelineValue: _timelineValueForDuration(_playheadElapsed),
      timelineMax: math.max(
        _timelineValueForDuration(_timelineDuration),
        hasMultipleFrames ? 1.0 : 0.0,
      ),
      changeMarkerValues: [
        for (var index = 0; index < widget.workspace.frames.length; index += 1)
          _timelineValueForDuration(_elapsedForFrameIndex(index)),
      ],
      idleGapMarkers: _idleGapMarkers(),
      activeFrame: activeFrame,
      isPlaying: _isPlaying,
      onFitRecordedSize: activeFrame == null
          ? null
          : () => _fitRecordedSize(activeFrame),
      onExit: widget.onExit,
      onStepBack: canStepBack ? () => _setActiveIndex(_activeIndex - 1) : null,
      onStepForward: canStepForward
          ? () => _setActiveIndex(_activeIndex + 1)
          : null,
      onTogglePlay: canPlay ? _togglePlayback : null,
      onClear: () => widget.onClear(widget.workspace.sourceSessionId),
      searchSummary: _searchSummary(),
      onSearchChanged: _updateSearch,
      onSearchPrevious: _searchResultCount == 0
          ? null
          : () => _moveSearchMatch(-1),
      onSearchNext: _searchResultCount == 0 ? null : () => _moveSearchMatch(1),
      onCopySelection: activeFrame == null ? null : _copySelection,
      onCopyVisible: activeFrame == null
          ? null
          : () => unawaited(widget.onCopyVisible(activeFrame.text)),
      onSliderChanged: hasMultipleFrames
          ? (value) {
              setState(() {
                _stopPlayback();
                _playheadElapsed = _clampDuration(
                  _durationFromTimelineValue(value),
                  Duration.zero,
                  _timelineDuration,
                );
                _activeIndex = _frameIndexForElapsed(_playheadElapsed);
                _applyActiveFrame();
              });
            }
          : null,
      palette: palette,
    );

    Widget replayViewport() {
      return LayoutBuilder(
        builder: (context, constraints) {
          _lastReplayViewportSize = constraints.biggest;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: widget.terminalColors.canvasBackground,
              borderRadius: BorderRadius.circular(palette.radius.md),
              border: Border.all(color: palette.border),
            ),
            child: activeFrame == null
                ? Center(
                    child: Text(
                      'No replay frames captured yet.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.textSubtle,
                      ),
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(palette.radius.md),
                    child: TerminalViewport(
                      key: const Key('instant-replay-viewport'),
                      focusNode: _focusNode,
                      controller: _viewportController,
                      selectionController: _selectionController,
                      inputController: _inputController,
                      contentPadding: const EdgeInsets.all(10),
                      colors: widget.terminalColors,
                      font: widget.font,
                      cursor: widget.cursor,
                      copyOnSelect: false,
                      onMeasuredCellSizeChanged: (cellSize) {
                        _measuredReplayCellSize = cellSize;
                      },
                      searchMatches: _activeSearchMatches,
                      activeSearchMatchIndex: _activeSearchMatches.isEmpty
                          ? -1
                          : _activeSearchMatchIndex,
                      searchHighlightStyle:
                          terminal.TerminalSearchHighlightStyle(
                            activeFill: palette.accent.withValues(alpha: 0.34),
                            inactiveFill: palette.warning.withValues(
                              alpha: 0.22,
                            ),
                            activeBorder: palette.accent.withValues(
                              alpha: 0.82,
                            ),
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
                  ),
          );
        },
      );
    }

    return Semantics(
      container: true,
      explicitChildNodes: true,
      scopesRoute: true,
      namesRoute: true,
      label: 'Instant Replay workspace',
      child: ColoredBox(
        color: palette.canvas,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final controlsHeight = math.min(
                      260.0,
                      math.max(220.0, constraints.maxHeight * 0.38),
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: replayViewport()),
                        const SizedBox(height: 12),
                        SizedBox(height: controlsHeight, child: controls),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InstantReplayWorkspaceControls extends StatelessWidget {
  const _InstantReplayWorkspaceControls({
    super.key,
    required this.sourceLabel,
    required this.commandBlockSource,
    required this.frameLabel,
    required this.frameCount,
    required this.activeIndex,
    required this.timelineValue,
    required this.timelineMax,
    required this.changeMarkerValues,
    required this.idleGapMarkers,
    required this.activeFrame,
    required this.isPlaying,
    required this.onFitRecordedSize,
    required this.onExit,
    required this.onStepBack,
    required this.onStepForward,
    required this.onTogglePlay,
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
  final InstantReplayCommandBlockSource? commandBlockSource;
  final String frameLabel;
  final int frameCount;
  final int activeIndex;
  final double timelineValue;
  final double timelineMax;
  final List<double> changeMarkerValues;
  final List<_InstantReplayIdleGapMarker> idleGapMarkers;
  final InstantReplayFrame? activeFrame;
  final bool isPlaying;
  final VoidCallback? onFitRecordedSize;
  final VoidCallback onExit;
  final VoidCallback? onStepBack;
  final VoidCallback? onStepForward;
  final VoidCallback? onTogglePlay;
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          palette.canvas.withValues(alpha: 0.24),
          palette.overlay,
        ),
        borderRadius: BorderRadius.circular(palette.radius.lg),
        border: Border.all(color: palette.borderStrong.withValues(alpha: 0.72)),
        boxShadow: [
          BoxShadow(
            color: palette.canvas.withValues(alpha: 0.42),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 820;
            final playbackControls = _InstantReplayPlaybackControls(
              isPlaying: isPlaying,
              onStepBack: onStepBack,
              onTogglePlay: onTogglePlay,
              onStepForward: onStepForward,
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
              includeClose: !compact,
              palette: palette,
            );
            final header = _InstantReplayControlHeader(
              sourceLabel: sourceLabel,
              commandBlockSource: commandBlockSource,
              frameDetail: frameDetail,
              palette: palette,
            );
            final timeline = _InstantReplayTimelineDeck(
              frameCount: frameCount,
              activeIndex: activeIndex,
              timelineValue: timelineValue,
              timelineMax: timelineMax,
              onSliderChanged: onSliderChanged,
              changeMarkerValues: changeMarkerValues,
              idleGapMarkers: idleGapMarkers,
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

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: header),
                      actions.closeButton,
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(children: [playbackControls, const Spacer(), actions]),
                  const SizedBox(height: 8),
                  timeline,
                  const SizedBox(height: 8),
                  search,
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: header),
                    const SizedBox(width: 12),
                    playbackControls,
                    const SizedBox(width: 8),
                    actions,
                  ],
                ),
                const SizedBox(height: 8),
                timeline,
                const SizedBox(height: 8),
                search,
              ],
            );
          },
        ),
      ),
    );
  }

  static String _frameTimeLabel(DateTime timestamp) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${twoDigits(timestamp.hour)}:${twoDigits(timestamp.minute)}:${twoDigits(timestamp.second)}';
  }
}

class _InstantReplayControlHeader extends StatelessWidget {
  const _InstantReplayControlHeader({
    required this.sourceLabel,
    required this.commandBlockSource,
    required this.frameDetail,
    required this.palette,
  });

  final String sourceLabel;
  final InstantReplayCommandBlockSource? commandBlockSource;
  final String frameDetail;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    final source = commandBlockSource;
    final detail = source == null
        ? '$sourceLabel • $frameDetail'
        : '${source.replayHeaderLabel} • $sourceLabel • $frameDetail';
    return Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: palette.accent.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(palette.radius.md),
            border: Border.all(color: palette.accent.withValues(alpha: 0.34)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(Icons.replay_rounded, size: 17, color: palette.accent),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Replay mode',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: palette.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            detail,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: palette.textSubtle,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _InstantReplayPlaybackControls extends StatelessWidget {
  const _InstantReplayPlaybackControls({
    required this.isPlaying,
    required this.onStepBack,
    required this.onTogglePlay,
    required this.onStepForward,
    required this.palette,
  });

  final bool isPlaying;
  final VoidCallback? onStepBack;
  final VoidCallback? onTogglePlay;
  final VoidCallback? onStepForward;
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
      ],
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
      tooltip: 'Exit instant replay',
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

class _InstantReplayTimelineDeck extends StatelessWidget {
  const _InstantReplayTimelineDeck({
    required this.frameCount,
    required this.activeIndex,
    required this.timelineValue,
    required this.timelineMax,
    required this.onSliderChanged,
    required this.changeMarkerValues,
    required this.idleGapMarkers,
    required this.palette,
  });

  final int frameCount;
  final int activeIndex;
  final double timelineValue;
  final double timelineMax;
  final ValueChanged<double>? onSliderChanged;
  final List<double> changeMarkerValues;
  final List<_InstantReplayIdleGapMarker> idleGapMarkers;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    final safeMax = timelineMax <= 0 ? 1.0 : timelineMax;
    final safeValue = timelineValue.clamp(0.0, timelineMax).toDouble();
    return SizedBox(
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: _InstantReplayTimelineMarkers(
              timelineMax: safeMax,
              timelineValue: safeValue,
              changeMarkerValues: changeMarkerValues,
              idleGapMarkers: idleGapMarkers,
              palette: palette,
            ),
          ),
          Positioned.fill(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 0,
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
                thumbColor: palette.textPrimary,
                overlayColor: palette.accent.withValues(alpha: 0.16),
                disabledActiveTrackColor: Colors.transparent,
                disabledInactiveTrackColor: Colors.transparent,
                disabledThumbColor: palette.textSubtle,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 6,
                  disabledThumbRadius: 6,
                ),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 15),
              ),
              child: Slider(
                key: const Key('instant-replay-timeline'),
                value: safeValue,
                min: 0,
                max: timelineMax,
                label: frameCount <= 1
                    ? 'Latest frame'
                    : '${activeIndex + 1} of $frameCount',
                onChanged: onSliderChanged,
              ),
            ),
          ),
          Positioned.fill(
            child: _InstantReplayIdleGapTooltipOverlay(
              timelineMax: safeMax,
              idleGapMarkers: idleGapMarkers,
            ),
          ),
        ],
      ),
    );
  }
}

class _InstantReplaySearchControls extends StatelessWidget {
  const _InstantReplaySearchControls({
    required this.enabled,
    required this.searchSummary,
    required this.onSearchChanged,
    required this.onSearchPrevious,
    required this.onSearchNext,
    required this.palette,
  });

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
        key: const Key('instant-replay-search'),
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
          key: const Key('instant-replay-search-previous'),
          tooltip: 'Previous search match',
          onPressed: onSearchPrevious,
          icon: Icons.keyboard_arrow_up_rounded,
          palette: palette,
        ),
        const SizedBox(width: 4),
        _InstantReplayControlButton(
          key: const Key('instant-replay-search-next'),
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

    return IconButton(
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

class _InstantReplayIdleGapTooltipOverlay extends StatelessWidget {
  const _InstantReplayIdleGapTooltipOverlay({
    required this.timelineMax,
    required this.idleGapMarkers,
  });

  final double timelineMax;
  final List<_InstantReplayIdleGapMarker> idleGapMarkers;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalInset = 16.0;
        const hitWidth = 18.0;
        final width = constraints.maxWidth;
        final usableWidth = math.max(0.0, width - horizontalInset * 2);
        final safeMax = timelineMax <= 0 ? 1.0 : timelineMax;
        return Stack(
          children: [
            for (final marker in idleGapMarkers)
              Positioned(
                left:
                    (horizontalInset +
                            (marker.value / safeMax).clamp(0.0, 1.0) *
                                usableWidth -
                            (hitWidth - 10) / 2)
                        .clamp(0.0, math.max(0.0, width - hitWidth)),
                top: 8,
                child: Tooltip(
                  key: const Key('instant-replay-idle-marker'),
                  message: marker.tooltip,
                  child: const ColoredBox(
                    color: Colors.transparent,
                    child: SizedBox(width: hitWidth, height: 24),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _InstantReplayTimelineMarkers extends StatelessWidget {
  const _InstantReplayTimelineMarkers({
    required this.timelineMax,
    required this.timelineValue,
    required this.changeMarkerValues,
    required this.idleGapMarkers,
    required this.palette,
  });

  final double timelineMax;
  final double timelineValue;
  final List<double> changeMarkerValues;
  final List<_InstantReplayIdleGapMarker> idleGapMarkers;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          const horizontalInset = 16.0;
          final usableWidth = math.max(0.0, width - horizontalInset * 2);
          final safeMax = timelineMax <= 0 ? 1.0 : timelineMax;
          final progress = (timelineValue / safeMax).clamp(0.0, 1.0);
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              Positioned(
                left: horizontalInset,
                right: horizontalInset,
                top: 16,
                bottom: 16,
                child: DecoratedBox(
                  key: const Key('instant-replay-quiet-track'),
                  decoration: BoxDecoration(
                    color: palette.border.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Positioned(
                left: horizontalInset,
                top: 16,
                bottom: 16,
                width: usableWidth * progress,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        palette.accent,
                        Color.lerp(palette.accent, palette.success, 0.55)!,
                        palette.success,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: palette.accent.withValues(alpha: 0.20),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
              Stack(
                key: const Key('instant-replay-change-marker'),
                children: [
                  for (final value in changeMarkerValues)
                    Positioned(
                      left:
                          horizontalInset +
                          (value / safeMax).clamp(0.0, 1.0) * usableWidth,
                      top: 14,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: value <= timelineValue
                              ? palette.textPrimary
                              : palette.textSubtle,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const SizedBox(width: 5, height: 10),
                      ),
                    ),
                ],
              ),
              Stack(
                children: [
                  for (final marker in idleGapMarkers)
                    Positioned(
                      left:
                          horizontalInset +
                          (marker.value / safeMax).clamp(0.0, 1.0) *
                              usableWidth,
                      top: 12,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: palette.warning,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: palette.canvas.withValues(alpha: 0.82),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: palette.warning.withValues(alpha: 0.28),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: const SizedBox(width: 10, height: 14),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
