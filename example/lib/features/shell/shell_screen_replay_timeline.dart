part of 'shell_screen.dart';

enum _ReplayTimelineMarkerKind { output, input, resize, exit, idle }

final class _ReplayTimelineMarker {
  const _ReplayTimelineMarker({
    required this.value,
    required this.kind,
    required this.tooltip,
  });

  final double value;
  final _ReplayTimelineMarkerKind kind;
  final String tooltip;
}

final class _ReplaySemanticPoint {
  const _ReplaySemanticPoint({
    required this.offset,
    required this.kind,
    this.command,
    this.cwd,
    this.hostname,
    this.exitCode,
    this.remote = false,
  });

  final Duration offset;
  final terminal.TerminalRecordingSemanticKind kind;
  final String? command;
  final String? cwd;
  final String? hostname;
  final int? exitCode;
  final bool remote;
}

enum _ReplayTimelineSegmentKind { command, remote, activity }

final class _ReplayTimelineSegment {
  const _ReplayTimelineSegment({
    required this.start,
    required this.end,
    required this.label,
    required this.kind,
    this.cwd,
    this.exitCode,
    this.remoteActivity = false,
    this.remote = false,
  });

  final Duration start;
  final Duration end;
  final String label;
  final _ReplayTimelineSegmentKind kind;
  final String? cwd;
  final int? exitCode;
  final bool remoteActivity;
  final bool remote;

  Duration get duration => end - start;

  _ReplayTimelineSegment copyWith({
    Duration? start,
    Duration? end,
    String? label,
    String? cwd,
    int? exitCode,
    bool? remoteActivity,
    bool? remote,
  }) {
    return _ReplayTimelineSegment(
      start: start ?? this.start,
      end: end ?? this.end,
      label: label ?? this.label,
      kind: kind,
      cwd: cwd ?? this.cwd,
      exitCode: exitCode ?? this.exitCode,
      remoteActivity: remoteActivity ?? this.remoteActivity,
      remote: remote ?? this.remote,
    );
  }
}

final class _ReplayTimelineModel {
  const _ReplayTimelineModel({
    required this.segments,
    required this.pathMarks,
    required this.hasSemanticCommands,
  });

  final List<_ReplayTimelineSegment> segments;
  final List<_ReplaySemanticPoint> pathMarks;
  final bool hasSemanticCommands;

  String contextLabelAt(Duration position) {
    final active = segments.lastWhere(
      (segment) => position >= segment.start && position <= segment.end,
      orElse: () => segments.first,
    );
    if (active.kind == _ReplayTimelineSegmentKind.activity) {
      return 'Activity';
    }
    if (active.remoteActivity) {
      return '${active.label} · Remote activity';
    }
    return active.label;
  }

  String? pathAt(Duration position) {
    String? path;
    for (final mark in pathMarks) {
      if (mark.offset > position) {
        break;
      }
      path = mark.cwd ?? path;
    }
    return path;
  }
}

_ReplayTimelineModel _buildReplayTimelineModel({
  required List<_ReplaySemanticPoint> points,
  required Duration duration,
}) {
  final safeDuration = duration <= Duration.zero
      ? const Duration(microseconds: 1)
      : duration;
  final segments = <_ReplayTimelineSegment>[];
  final open = <_OpenReplaySegment>[];
  final pathMarks = <_ReplaySemanticPoint>[];
  _ReplaySemanticPoint? previousPrompt;

  for (final point in points) {
    switch (point.kind) {
      case terminal.TerminalRecordingSemanticKind.commandStarted:
        _openReplayCommand(open, segments, point);
      case terminal.TerminalRecordingSemanticKind.commandFinished:
        _closeReplaySegment(
          open,
          segments,
          point,
          kind: _ReplayTimelineSegmentKind.command,
        );
      case terminal.TerminalRecordingSemanticKind.remoteSessionStarted:
        _openReplayRemoteSession(open, segments, point);
      case terminal.TerminalRecordingSemanticKind.remoteSessionFinished:
        _closeReplaySegment(
          open,
          segments,
          point,
          kind: _ReplayTimelineSegmentKind.remote,
        );
      case terminal.TerminalRecordingSemanticKind.directoryChanged:
        pathMarks.add(point);
      case terminal.TerminalRecordingSemanticKind.prompt:
        final previous = previousPrompt;
        if (previous != null &&
            point.offset > previous.offset &&
            !_hasReplaySegmentBetween(
              segments,
              open,
              previous.offset,
              point.offset,
            )) {
          segments.add(
            _ReplayTimelineSegment(
              start: previous.offset,
              end: point.offset,
              label: _replayCommandLabel(previous.command, 0),
              kind: _ReplayTimelineSegmentKind.command,
              cwd: previous.cwd,
              remote: previous.remote,
            ),
          );
        }
        previousPrompt = point;
    }
  }

  for (final item in open) {
    segments.add(
      _ReplayTimelineSegment(
        start: item.start,
        end: safeDuration,
        label: item.label,
        kind: item.kind,
        cwd: item.cwd,
        remoteActivity: item.kind == _ReplayTimelineSegmentKind.remote,
        remote: item.remote,
      ),
    );
  }
  if (segments.isEmpty) {
    segments.add(
      _ReplayTimelineSegment(
        start: Duration.zero,
        end: safeDuration,
        label: 'Activity',
        kind: _ReplayTimelineSegmentKind.activity,
      ),
    );
  }
  final finalizedSegments = _finalizeReplaySegments(segments);
  if (finalizedSegments.isEmpty) {
    finalizedSegments.add(
      _ReplayTimelineSegment(
        start: Duration.zero,
        end: safeDuration,
        label: 'Activity',
        kind: _ReplayTimelineSegmentKind.activity,
      ),
    );
  }
  pathMarks.sort((left, right) => left.offset.compareTo(right.offset));
  return _ReplayTimelineModel(
    segments: List<_ReplayTimelineSegment>.unmodifiable(finalizedSegments),
    pathMarks: List<_ReplaySemanticPoint>.unmodifiable(pathMarks),
    hasSemanticCommands: finalizedSegments.any(
      (segment) => segment.kind != _ReplayTimelineSegmentKind.activity,
    ),
  );
}

final class _OpenReplaySegment {
  const _OpenReplaySegment({
    required this.start,
    required this.label,
    required this.kind,
    required this.cwd,
    required this.remote,
  });

  final Duration start;
  final String label;
  final _ReplayTimelineSegmentKind kind;
  final String? cwd;
  final bool remote;
}

void _openReplayCommand(
  List<_OpenReplaySegment> open,
  List<_ReplayTimelineSegment> segments,
  _ReplaySemanticPoint point,
) {
  final candidate = _OpenReplaySegment(
    start: point.offset,
    label: _replayCommandLabel(point.command, 0),
    kind: _ReplayTimelineSegmentKind.command,
    cwd: point.cwd,
    remote: point.remote,
  );
  final existingIndex = open.lastIndexWhere(
    (item) =>
        item.kind == _ReplayTimelineSegmentKind.command &&
        item.remote == point.remote,
  );
  if (existingIndex == -1) {
    open.add(candidate);
    return;
  }
  final existing = open[existingIndex];
  if (_replayLabelsCanMerge(existing.label, candidate.label)) {
    open[existingIndex] = _mergeOpenReplaySegments(existing, candidate);
    return;
  }
  segments.add(_closedReplaySegment(existing, point.offset));
  open[existingIndex] = candidate;
}

void _openReplayRemoteSession(
  List<_OpenReplaySegment> open,
  List<_ReplayTimelineSegment> segments,
  _ReplaySemanticPoint point,
) {
  var candidate = _OpenReplaySegment(
    start: point.offset,
    label: _replayCommandLabel(point.command, 0),
    kind: _ReplayTimelineSegmentKind.remote,
    cwd: point.cwd,
    remote: true,
  );
  final localCommandIndex = open.lastIndexWhere(
    (item) => item.kind == _ReplayTimelineSegmentKind.command && !item.remote,
  );
  if (localCommandIndex != -1) {
    final localCommand = open[localCommandIndex];
    if (_replayLabelsCanMerge(localCommand.label, candidate.label)) {
      open.removeAt(localCommandIndex);
      candidate = _OpenReplaySegment(
        start: localCommand.start.compareTo(candidate.start) <= 0
            ? localCommand.start
            : candidate.start,
        label: _preferredReplayLabel(localCommand.label, candidate.label),
        kind: _ReplayTimelineSegmentKind.remote,
        cwd: candidate.cwd ?? localCommand.cwd,
        remote: true,
      );
    }
  }
  final existingIndex = open.lastIndexWhere(
    (item) => item.kind == _ReplayTimelineSegmentKind.remote,
  );
  if (existingIndex == -1) {
    open.add(candidate);
    return;
  }
  final existing = open[existingIndex];
  if (_replayLabelsCanMerge(existing.label, candidate.label)) {
    open[existingIndex] = _mergeOpenReplaySegments(existing, candidate);
    return;
  }
  segments.add(_closedReplaySegment(existing, point.offset));
  open[existingIndex] = candidate;
}

_OpenReplaySegment _mergeOpenReplaySegments(
  _OpenReplaySegment left,
  _OpenReplaySegment right,
) {
  return _OpenReplaySegment(
    start: left.start.compareTo(right.start) <= 0 ? left.start : right.start,
    label: _preferredReplayLabel(left.label, right.label),
    kind: left.kind,
    cwd: right.cwd ?? left.cwd,
    remote: left.remote || right.remote,
  );
}

_ReplayTimelineSegment _closedReplaySegment(
  _OpenReplaySegment item,
  Duration requestedEnd, {
  int? exitCode,
}) {
  final end = requestedEnd < item.start ? item.start : requestedEnd;
  return _ReplayTimelineSegment(
    start: item.start,
    end: end,
    label: item.label,
    kind: item.kind,
    cwd: item.cwd,
    exitCode: exitCode,
    remoteActivity: item.kind == _ReplayTimelineSegmentKind.remote,
    remote: item.remote,
  );
}

void _closeReplaySegment(
  List<_OpenReplaySegment> open,
  List<_ReplayTimelineSegment> segments,
  _ReplaySemanticPoint point, {
  required _ReplayTimelineSegmentKind kind,
}) {
  final commandLabel = point.command == null
      ? null
      : _replayCommandLabel(point.command, 0);
  var index = commandLabel == null
      ? -1
      : open.lastIndexWhere(
          (item) =>
              item.kind == kind &&
              (kind != _ReplayTimelineSegmentKind.command ||
                  item.remote == point.remote) &&
              _replayLabelsCanMerge(item.label, commandLabel),
        );
  index = index == -1
      ? open.lastIndexWhere(
          (item) =>
              item.kind == kind &&
              (kind != _ReplayTimelineSegmentKind.command ||
                  item.remote == point.remote),
        )
      : index;
  if (index == -1) {
    return;
  }
  final item = open.removeAt(index);
  segments.add(
    _closedReplaySegment(item, point.offset, exitCode: point.exitCode),
  );
}

bool _hasReplaySegmentBetween(
  List<_ReplayTimelineSegment> segments,
  List<_OpenReplaySegment> open,
  Duration start,
  Duration end,
) {
  return segments.any(
        (segment) => segment.start < end && segment.end > start,
      ) ||
      open.any((segment) => segment.start < end);
}

String _replayCommandLabel(String? command, int anonymousIndex) {
  final normalized = command?.trim();
  if (normalized == null || normalized.isEmpty) {
    return 'Command $anonymousIndex';
  }
  return normalized.replaceAll(RegExp(r'\s+'), ' ');
}

bool _isAnonymousReplayLabel(String label) => label.startsWith('Command ');

bool _replayLabelsCanMerge(String left, String right) {
  return _isAnonymousReplayLabel(left) ||
      _isAnonymousReplayLabel(right) ||
      left == right;
}

String _preferredReplayLabel(String left, String right) {
  if (_isAnonymousReplayLabel(left) && !_isAnonymousReplayLabel(right)) {
    return right;
  }
  return left;
}

bool _replaySegmentsOverlap(
  _ReplayTimelineSegment left,
  _ReplayTimelineSegment right,
) {
  return left.start < right.end && left.end > right.start;
}

_ReplayTimelineSegment _mergeClosedReplaySegments(
  _ReplayTimelineSegment left,
  _ReplayTimelineSegment right,
) {
  return _ReplayTimelineSegment(
    start: left.start.compareTo(right.start) <= 0 ? left.start : right.start,
    end: left.end.compareTo(right.end) >= 0 ? left.end : right.end,
    label: _preferredReplayLabel(left.label, right.label),
    kind: left.kind,
    cwd: right.cwd ?? left.cwd,
    exitCode: right.exitCode ?? left.exitCode,
    remoteActivity: left.remoteActivity || right.remoteActivity,
    remote: left.remote || right.remote,
  );
}

List<_ReplayTimelineSegment> _finalizeReplaySegments(
  List<_ReplayTimelineSegment> source,
) {
  final sorted =
      source
          .where(
            (segment) =>
                !(_isAnonymousReplayLabel(segment.label) &&
                    segment.kind == _ReplayTimelineSegmentKind.command &&
                    segment.duration <= const Duration(milliseconds: 100)),
          )
          .toList(growable: false)
        ..sort((left, right) {
          final byStart = left.start.compareTo(right.start);
          if (byStart != 0) {
            return byStart;
          }
          return right.duration.compareTo(left.duration);
        });
  final reconciled = <_ReplayTimelineSegment>[];
  for (final segment in sorted) {
    if (segment.kind == _ReplayTimelineSegmentKind.command) {
      final overlapIndex = reconciled.lastIndexWhere(
        (existing) =>
            existing.kind == _ReplayTimelineSegmentKind.command &&
            existing.remote == segment.remote &&
            _replaySegmentsOverlap(existing, segment),
      );
      if (overlapIndex != -1) {
        final existing = reconciled[overlapIndex];
        if (_replayLabelsCanMerge(existing.label, segment.label)) {
          reconciled[overlapIndex] = _mergeClosedReplaySegments(
            existing,
            segment,
          );
          continue;
        }
        if (existing.start < segment.start) {
          reconciled[overlapIndex] = existing.copyWith(end: segment.start);
        } else {
          reconciled.removeAt(overlapIndex);
        }
      }
    }
    reconciled.add(segment);
  }

  final remoteSessions = reconciled
      .where((segment) => segment.kind == _ReplayTimelineSegmentKind.remote)
      .toList(growable: false);
  final withoutRemoteWrappers = reconciled
      .where((segment) {
        if (segment.kind != _ReplayTimelineSegmentKind.command ||
            segment.remote) {
          return true;
        }
        return !remoteSessions.any(
          (remote) =>
              _replaySegmentsOverlap(segment, remote) &&
              (_isAnonymousReplayLabel(segment.label) ||
                  segment.label == remote.label),
        );
      })
      .toList(growable: false);

  var anonymousIndex = 0;
  return [
    for (final segment in withoutRemoteWrappers)
      segment.copyWith(
        label: _isAnonymousReplayLabel(segment.label)
            ? 'Command ${++anonymousIndex}'
            : segment.label,
        remoteActivity: segment.kind == _ReplayTimelineSegmentKind.remote
            ? !withoutRemoteWrappers.any(
                (candidate) =>
                    candidate.kind == _ReplayTimelineSegmentKind.command &&
                    candidate.remote &&
                    _replaySegmentsOverlap(candidate, segment),
              )
            : segment.remoteActivity,
      ),
  ];
}

class _ReplaySemanticTimeline extends StatelessWidget {
  const _ReplaySemanticTimeline({
    required this.timelineKey,
    required this.effectsKey,
    required this.value,
    required this.max,
    required this.position,
    required this.duration,
    required this.model,
    required this.markers,
    required this.onChanged,
    required this.palette,
    this.changeMarkerKey,
    this.idleMarkerKey,
    this.quietTrackKey,
    this.displayPosition,
    this.displayDuration,
  });

  final Key timelineKey;
  final Key effectsKey;
  final Key? changeMarkerKey;
  final Key? idleMarkerKey;
  final Key? quietTrackKey;
  final double value;
  final double max;
  final Duration position;
  final Duration duration;
  final Duration? displayPosition;
  final Duration? displayDuration;
  final _ReplayTimelineModel model;
  final List<_ReplayTimelineMarker> markers;
  final ValueChanged<double>? onChanged;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    final safeMax = max <= 0 ? 1.0 : max;
    final safeValue = value.clamp(0.0, safeMax).toDouble();
    final path = model.pathAt(position);
    final visiblePosition = displayPosition ?? position;
    final visibleDuration = displayDuration ?? duration;
    return Semantics(
      label:
          '${model.contextLabelAt(position)}, '
          '${_formatRecordingDuration(visiblePosition)} of '
          '${_formatRecordingDuration(visibleDuration)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 22,
            child: Row(
              children: [
                Icon(
                  path == null ? Icons.timeline_rounded : Icons.folder_outlined,
                  size: 14,
                  color: palette.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    path ?? model.contextLabelAt(position),
                    key: const Key('replay-timeline-context'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: palette.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${_formatRecordingDuration(visiblePosition)} / '
                  '${_formatRecordingDuration(visibleDuration)}',
                  key: const Key('replay-timeline-time'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: palette.textMuted,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 106,
            child: LayoutBuilder(
              builder: (context, constraints) {
                const inset = 12.0;
                final width = math.max(0.0, constraints.maxWidth - inset * 2);
                final progress = safeValue / safeMax;
                return Stack(
                  key: effectsKey,
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      key: changeMarkerKey,
                      left: inset,
                      right: inset,
                      top: 0,
                      height: 76,
                      child: _ReplaySegmentLane(
                        model: model,
                        max: math.max(1, duration.inMicroseconds).toDouble(),
                        width: width,
                        position: position,
                        onSeek: onChanged == null
                            ? null
                            : (offset) {
                                final durationMicros = math.max(
                                  1,
                                  duration.inMicroseconds,
                                );
                                onChanged!(
                                  safeMax *
                                      (offset.inMicroseconds / durationMicros)
                                          .clamp(0.0, 1.0),
                                );
                              },
                        palette: palette,
                      ),
                    ),
                    Positioned(
                      left: inset,
                      right: inset,
                      top: 84,
                      height: 4,
                      child: DecoratedBox(
                        key: quietTrackKey,
                        decoration: BoxDecoration(
                          color: palette.border.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    Positioned(
                      left: inset,
                      top: 84,
                      width: width * progress,
                      height: 4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: palette.accent,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    for (final marker in markers)
                      Positioned(
                        left:
                            inset +
                            (marker.value / safeMax).clamp(0.0, 1.0) * width -
                            _markerWidth(marker.kind) / 2,
                        top: _markerTop(marker.kind) + 39,
                        child: Tooltip(
                          message: marker.tooltip,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: _markerColor(marker.kind),
                              borderRadius: BorderRadius.circular(99),
                              border:
                                  marker.kind == _ReplayTimelineMarkerKind.idle
                                  ? Border.all(
                                      color: palette.canvas,
                                      width: 1.5,
                                    )
                                  : null,
                            ),
                            child: SizedBox(
                              width: _markerWidth(marker.kind),
                              height: _markerHeight(marker.kind),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 70,
                      height: 34,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 0,
                          activeTrackColor: Colors.transparent,
                          inactiveTrackColor: Colors.transparent,
                          disabledActiveTrackColor: Colors.transparent,
                          disabledInactiveTrackColor: Colors.transparent,
                          thumbColor: palette.accent,
                          disabledThumbColor: palette.textSubtle,
                          overlayColor: palette.accent.withValues(alpha: 0.14),
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                            disabledThumbRadius: 6,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 15,
                          ),
                        ),
                        child: Slider(
                          key: timelineKey,
                          value: safeValue,
                          max: safeMax,
                          onChanged: onChanged,
                        ),
                      ),
                    ),
                    for (final marker in markers)
                      if (marker.kind == _ReplayTimelineMarkerKind.idle)
                        Positioned(
                          left:
                              (inset +
                                      (marker.value / safeMax).clamp(0.0, 1.0) *
                                          width -
                                      9)
                                  .clamp(
                                    0.0,
                                    math.max(0.0, constraints.maxWidth - 18),
                                  ),
                          top: 74,
                          child: Tooltip(
                            key: idleMarkerKey,
                            message: marker.tooltip,
                            child: const ColoredBox(
                              color: Colors.transparent,
                              child: SizedBox(width: 18, height: 24),
                            ),
                          ),
                        ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 2),
          _ReplayTimelineLegend(model: model, palette: palette),
        ],
      ),
    );
  }

  Color _markerColor(_ReplayTimelineMarkerKind kind) {
    return switch (kind) {
      _ReplayTimelineMarkerKind.output => palette.textSubtle,
      _ReplayTimelineMarkerKind.input => palette.success,
      _ReplayTimelineMarkerKind.resize => palette.warning,
      _ReplayTimelineMarkerKind.exit => palette.danger,
      _ReplayTimelineMarkerKind.idle => palette.borderStrong,
    };
  }

  static double _markerWidth(_ReplayTimelineMarkerKind kind) =>
      kind == _ReplayTimelineMarkerKind.idle ? 8 : 3;

  static double _markerHeight(_ReplayTimelineMarkerKind kind) =>
      kind == _ReplayTimelineMarkerKind.idle ? 13 : 9;

  static double _markerTop(_ReplayTimelineMarkerKind kind) =>
      kind == _ReplayTimelineMarkerKind.idle ? 40.5 : 42.5;
}

class _ReplaySegmentLane extends StatelessWidget {
  const _ReplaySegmentLane({
    required this.model,
    required this.max,
    required this.width,
    required this.position,
    required this.onSeek,
    required this.palette,
  });

  final _ReplayTimelineModel model;
  final double max;
  final double width;
  final Duration position;
  final ValueChanged<Duration>? onSeek;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var index = 0; index < model.segments.length; index += 1)
          _segment(context, model.segments[index], index),
      ],
    );
  }

  Widget _segment(
    BuildContext context,
    _ReplayTimelineSegment segment,
    int index,
  ) {
    final start = (segment.start.inMicroseconds / max).clamp(0.0, 1.0);
    final end = (segment.end.inMicroseconds / max).clamp(start, 1.0);
    final rawWidth = width * (end - start);
    final cardGap = math.min(4.0, math.max(0.0, rawWidth - 4.0));
    final left = width * start + cardGap / 2;
    final segmentWidth = math.max(4.0, rawWidth - cardGap);
    final active = position >= segment.start && position <= segment.end;
    final remoteParent =
        segment.kind == _ReplayTimelineSegmentKind.remote &&
        !segment.remoteActivity;
    final remoteChild =
        segment.kind == _ReplayTimelineSegmentKind.command && segment.remote;
    final major =
        segment.kind == _ReplayTimelineSegmentKind.remote || segmentWidth >= 92;
    final background = active
        ? palette.selected
        : segment.kind == _ReplayTimelineSegmentKind.activity
        ? palette.panel.withValues(alpha: 0.62)
        : palette.panelElevated.withValues(alpha: 0.72);
    final borderColor = active
        ? palette.accent
        : segment.exitCode != null && segment.exitCode != 0
        ? palette.danger.withValues(alpha: 0.76)
        : segment.kind == _ReplayTimelineSegmentKind.remote
        ? palette.warning.withValues(alpha: 0.58)
        : palette.border;
    final top = remoteParent
        ? 0.0
        : remoteChild
        ? 30.0
        : major
        ? 4.0
        : 14.0;
    final height = remoteParent
        ? 24.0
        : remoteChild
        ? 44.0
        : major
        ? 62.0
        : 46.0;
    return Positioned(
      key: Key('replay-semantic-segment-$index'),
      left: left,
      top: top,
      width: segmentWidth,
      height: height,
      child: Tooltip(
        message: [
          segment.label,
          if (segment.cwd != null) segment.cwd!,
          if (segment.remoteActivity) 'Remote activity',
          if (segment.exitCode != null) 'Exit ${segment.exitCode}',
        ].join(' · '),
        child: Semantics(
          button: onSeek != null,
          label:
              'Jump to ${segment.label} at '
              '${_formatRecordingDuration(segment.start)}',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onSeek == null ? null : () => onSeek!(segment.start),
              borderRadius: BorderRadius.circular(palette.radius.sm),
              child: Ink(
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(palette.radius.sm),
                  border: Border.all(color: borderColor),
                ),
                padding: EdgeInsets.symmetric(horizontal: major ? 8 : 5),
                child: Row(
                  children: [
                    if (segment.kind == _ReplayTimelineSegmentKind.remote) ...[
                      Icon(
                        Icons.dns_outlined,
                        size: remoteParent ? 11 : 14,
                        color: active ? palette.accent : palette.textMuted,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: height < 34 || segmentWidth < 78
                          ? Text(
                              segment.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: active
                                        ? palette.textPrimary
                                        : palette.textMuted,
                                    fontWeight: active
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                  ),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  segment.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: active
                                            ? palette.textPrimary
                                            : palette.textMuted,
                                        fontWeight: active
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    if (segment.remoteActivity)
                                      'Remote activity',
                                    '${_formatRecordingDuration(segment.start)}'
                                        ' – '
                                        '${_formatRecordingDuration(segment.end)}',
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(color: palette.textSubtle),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReplayTimelineLegend extends StatelessWidget {
  const _ReplayTimelineLegend({required this.model, required this.palette});

  final _ReplayTimelineModel model;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: palette.textSubtle,
      fontWeight: FontWeight.w600,
    );
    return SizedBox(
      height: 22,
      child: Row(
        children: [
          _ReplayLegendItem(
            color: palette.accent,
            label: 'Command',
            style: style,
          ),
          const SizedBox(width: 14),
          _ReplayLegendItem(
            color: palette.warning,
            label: 'Remote session',
            style: style,
          ),
          const SizedBox(width: 14),
          _ReplayLegendItem(
            color: palette.borderStrong,
            label: 'Idle gap',
            style: style,
          ),
          const Spacer(),
          Flexible(
            child: Text(
              model.hasSemanticCommands
                  ? 'Shell semantics'
                  : 'Activity fallback · no shell hook',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplayLegendItem extends StatelessWidget {
  const _ReplayLegendItem({
    required this.color,
    required this.label,
    required this.style,
  });

  final Color color;
  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.84),
            borderRadius: BorderRadius.circular(2),
          ),
          child: const SizedBox(width: 8, height: 8),
        ),
        const SizedBox(width: 5),
        Text(label, style: style),
      ],
    );
  }
}

class _ReplayDockLayout extends StatelessWidget {
  const _ReplayDockLayout({
    required this.timeline,
    required this.metadata,
    required this.transport,
    required this.search,
    required this.actions,
    required this.palette,
  });

  final Widget timeline;
  final Widget metadata;
  final Widget transport;
  final Widget search;
  final Widget actions;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          palette.canvas.withValues(alpha: 0.18),
          palette.overlay,
        ),
        borderRadius: BorderRadius.circular(palette.radius.lg),
        border: Border.all(color: palette.borderStrong.withValues(alpha: 0.64)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 960;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                timeline,
                const SizedBox(height: 6),
                Divider(height: 1, color: palette.border),
                const SizedBox(height: 8),
                if (compact) ...[
                  Row(
                    children: [
                      Expanded(child: metadata),
                      actions,
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      transport,
                      const SizedBox(width: 8),
                      Expanded(child: search),
                    ],
                  ),
                ] else
                  Row(
                    children: [
                      Expanded(flex: 3, child: metadata),
                      const SizedBox(width: 12),
                      transport,
                      const SizedBox(width: 12),
                      SizedBox(width: 250, child: search),
                      const SizedBox(width: 8),
                      actions,
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
