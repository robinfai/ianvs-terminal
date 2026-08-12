import 'dart:async';
import 'dart:typed_data';

import 'package:ianvs_terminal_core/src/pty/ianvs_pty.dart';

import 'terminal_recording.dart';

enum TerminalReplayTimingMode { realtime, noDelay, manual }

final class TerminalReplayCheckpoint {
  const TerminalReplayCheckpoint._({
    required this.recordingId,
    required this.sourceSequence,
    required this.monotonicOffset,
    required this.nativeCheckpointId,
    required int resumeEventIndex,
  }) : _resumeEventIndex = resumeEventIndex;

  final String recordingId;
  final int sourceSequence;
  final Duration monotonicOffset;

  /// Session-scoped native checkpoint identifier used by the seek layer.
  final int nativeCheckpointId;

  final int _resumeEventIndex;
}

final class TerminalReplaySeekResult {
  const TerminalReplaySeekResult._({
    required this.targetOffset,
    required this.checkpoint,
    required this.replayedEventCount,
    required this.discardedSeekEventCount,
  });

  final Duration targetOffset;
  final TerminalReplayCheckpoint checkpoint;
  final int replayedEventCount;
  final int discardedSeekEventCount;
}

final class TerminalReplaySeekException implements Exception {
  const TerminalReplaySeekException({
    required this.sessionId,
    required this.targetOffset,
    required this.checkpointRecordingId,
  });

  final String sessionId;
  final Duration targetOffset;
  final String checkpointRecordingId;

  @override
  String toString() =>
      'TerminalReplaySeekException: native restore failed for session '
      '$sessionId at ${targetOffset.inMicroseconds}us from checkpoint '
      '$checkpointRecordingId';
}

typedef TerminalReplayTimerFactory =
    Timer Function(Duration delay, void Function() callback);

/// A read-only [PtySessionBackend] that feeds a validated recording through a
/// native replay session and therefore reuses the production parser and Frame
/// pipeline without starting a child process.
final class TerminalReplayBackend
    implements
        PtySessionBackend,
        PtySessionRequestV1Backend,
        PtySessionDiagnosticEventV1Backend,
        PtySessionGraphicAssetBackend,
        PtySessionFramePacketV1Backend,
        PtySessionRefreshHintBackend,
        PtySessionConfigV1Backend {
  static const double minPlaybackSpeed = 0.25;
  static const double maxPlaybackSpeed = 4;

  TerminalReplayBackend({
    required PtySessionBackend delegate,
    required TerminalRecording recording,
    this.timingMode = TerminalReplayTimingMode.realtime,
    double playbackSpeed = 1,
    TerminalReplayTimerFactory? timerFactory,
  }) : _delegate = delegate,
       _replayDelegate = _requireReplayDelegate(delegate),
       _recording = _validatedRecording(recording),
       _playbackSpeed = _validatedPlaybackSpeed(playbackSpeed),
       _timerFactory = timerFactory ?? _defaultTimerFactory;

  final PtySessionBackend _delegate;
  final PtyReplaySessionBackend _replayDelegate;
  final TerminalRecording _recording;
  late final Map<(int, int), TerminalRecordingGraphicAsset>
  _recordedGraphicAssets = <(int, int), TerminalRecordingGraphicAsset>{
    for (final asset in _recording.graphicAssets)
      (asset.assetId, asset.assetVersion): asset,
  };
  final TerminalReplayTimingMode timingMode;
  double _playbackSpeed;
  final TerminalReplayTimerFactory _timerFactory;
  final Map<String, _ReplaySessionState> _sessions =
      <String, _ReplaySessionState>{};

  bool get supportsReplayCheckpoints {
    final delegate = _delegate;
    return delegate is PtyReplayCheckpointBackend &&
        (delegate as PtyReplayCheckpointBackend).supportsReplayCheckpoints;
  }

  bool get supportsReplaySeek =>
      supportsReplayCheckpoints &&
      _recording.events.any(
        (event) => event.kind == TerminalRecordingEventKind.checkpoint,
      );

  double get playbackSpeed => _playbackSpeed;

  Duration get replayDuration => _recording.events.last.monotonicOffset;

  bool isSessionPaused(String sessionId) => _requireSession(sessionId).paused;

  void pauseSession(String sessionId) {
    final state = _requireSession(sessionId);
    if (state.paused) {
      return;
    }
    state.paused = true;
    state.timer?.cancel();
    state.timer = null;
  }

  void resumeSession(String sessionId) {
    final state = _requireSession(sessionId);
    if (!state.paused) {
      return;
    }
    state.paused = false;
    if (timingMode == TerminalReplayTimingMode.realtime) {
      _scheduleNext(state);
    }
  }

  void setPlaybackSpeed(double value) {
    final nextSpeed = _validatedPlaybackSpeed(value);
    if (_playbackSpeed == nextSpeed) {
      return;
    }
    _playbackSpeed = nextSpeed;
    if (timingMode != TerminalReplayTimingMode.realtime) {
      return;
    }
    for (final state in _sessions.values) {
      if (state.paused || state.nextEventIndex >= state.events.length) {
        continue;
      }
      state.timer?.cancel();
      state.timer = null;
      _scheduleNext(state);
    }
  }

  List<TerminalReplayCheckpoint> checkpointsForSession(String sessionId) {
    final state = _sessions[sessionId];
    if (state == null) {
      throw StateError('Unknown replay session $sessionId');
    }
    return List<TerminalReplayCheckpoint>.unmodifiable(
      state.checkpoints.values,
    );
  }

  Duration replayOffsetForSession(String sessionId) {
    final state = _sessions[sessionId];
    if (state == null) {
      throw StateError('Unknown replay session $sessionId');
    }
    return state.deliveredThrough;
  }

  bool advanceSessionTo(String sessionId, Duration targetOffset) {
    final state = _requireSession(sessionId);
    if (timingMode != TerminalReplayTimingMode.manual) {
      throw StateError(
        'advanceSessionTo requires TerminalReplayTimingMode.manual',
      );
    }
    final targetMicros = targetOffset.inMicroseconds;
    if (targetMicros < 0 || targetOffset > replayDuration) {
      throw RangeError.range(
        targetMicros,
        0,
        replayDuration.inMicroseconds,
        'targetOffset.inMicroseconds',
      );
    }
    if (targetOffset < state.deliveredThrough) {
      seekSession(sessionId, targetOffset);
      return true;
    }
    final startingEventIndex = state.nextEventIndex;
    while (state.nextEventIndex < state.events.length) {
      final nextOffset = state.events[state.nextEventIndex].monotonicOffset;
      if (nextOffset > targetOffset) {
        break;
      }
      _deliverAtOffset(state, nextOffset);
    }
    state.deliveredThrough = targetOffset;
    return state.nextEventIndex != startingEventIndex;
  }

  TerminalReplaySeekResult seekSession(
    String sessionId,
    Duration targetOffset,
  ) {
    final state = _sessions[sessionId];
    if (state == null) {
      throw StateError('Unknown replay session $sessionId');
    }
    if (!supportsReplaySeek) {
      throw UnsupportedError(
        'Replay seek requires current-schema checkpoint markers and native '
        'checkpoint support',
      );
    }
    final targetMicros = targetOffset.inMicroseconds;
    if (targetMicros < 0 || targetOffset > replayDuration) {
      throw RangeError.range(
        targetMicros,
        0,
        replayDuration.inMicroseconds,
        'targetOffset.inMicroseconds',
      );
    }

    TerminalReplayCheckpoint? selectedCheckpoint;
    for (final checkpoint in state.checkpoints.values) {
      if (checkpoint.monotonicOffset > targetOffset) {
        continue;
      }
      final selected = selectedCheckpoint;
      if (selected == null ||
          checkpoint.monotonicOffset > selected.monotonicOffset ||
          (checkpoint.monotonicOffset == selected.monotonicOffset &&
              checkpoint._resumeEventIndex > selected._resumeEventIndex)) {
        selectedCheckpoint = checkpoint;
      }
    }
    final checkpoint = selectedCheckpoint;
    if (checkpoint == null) {
      throw StateError(
        'No materialized replay checkpoint exists at or before '
        '${targetOffset.inMicroseconds}us',
      );
    }

    state.bufferedEvents.addAll(_delegate.pollEvents(sessionId));
    final checkpointDelegate = _delegate as PtyReplayCheckpointBackend;
    if (!checkpointDelegate.restoreReplayCheckpoint(
      sessionId,
      checkpoint.nativeCheckpointId,
    )) {
      throw TerminalReplaySeekException(
        sessionId: sessionId,
        targetOffset: targetOffset,
        checkpointRecordingId: checkpoint.recordingId,
      );
    }

    state.timer?.cancel();
    state.timer = null;
    state.nextEventIndex = checkpoint._resumeEventIndex;
    state.deliveredThrough = checkpoint.monotonicOffset;
    var replayedEventCount = 0;
    while (state.nextEventIndex < state.events.length) {
      final event = state.events[state.nextEventIndex];
      if (event.monotonicOffset > targetOffset) {
        break;
      }
      state.nextEventIndex += 1;
      _deliver(state, event);
      if (event.kind != TerminalRecordingEventKind.checkpoint) {
        replayedEventCount += 1;
      }
    }
    state.deliveredThrough = targetOffset;
    final discardedSeekEventCount = _delegate.pollEvents(sessionId).length;
    if (timingMode == TerminalReplayTimingMode.realtime && !state.paused) {
      _scheduleNext(state);
    }
    return TerminalReplaySeekResult._(
      targetOffset: targetOffset,
      checkpoint: checkpoint,
      replayedEventCount: replayedEventCount,
      discardedSeekEventCount: discardedSeekEventCount,
    );
  }

  @override
  int ping() => _delegate.ping();

  @override
  String createSessionV1(String sessionConfigV1Json) {
    final delegate = _replayDelegate;
    final configDelegate = delegate is PtyReplaySessionConfigV1Backend
        ? delegate as PtyReplaySessionConfigV1Backend
        : null;
    if (configDelegate == null) {
      throw UnsupportedError('Replay SessionConfig v1 is not supported');
    }
    return _createSession(
      () => configDelegate.createReplaySessionV1(sessionConfigV1Json),
    );
  }

  String _createSession(String Function() create) {
    final sessionId = create();
    final state = _ReplaySessionState(
      sessionId: sessionId,
      events: _playableEvents(_recording.events),
    );
    _sessions[sessionId] = state;
    try {
      _applyInitialGeometry(sessionId);
      switch (timingMode) {
        case TerminalReplayTimingMode.noDelay:
          _deliverAll(state);
        case TerminalReplayTimingMode.realtime:
          _deliverAtOffset(state, Duration.zero);
          _scheduleNext(state);
        case TerminalReplayTimingMode.manual:
          state.paused = true;
          _deliverAtOffset(state, Duration.zero);
      }
      return sessionId;
    } on Object {
      _sessions.remove(sessionId);
      state.timer?.cancel();
      _delegate.closeSession(sessionId);
      rethrow;
    }
  }

  @override
  void closeSession(String sessionId) {
    final state = _sessions.remove(sessionId);
    state?.timer?.cancel();
    _delegate.closeSession(sessionId);
  }

  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
    int cellWidth = 0,
    int cellHeight = 0,
  }) {
    _requireSession(sessionId);
    // Only recorded Resize events drive replay geometry. Ignoring view-driven
    // mutations keeps repeated playback deterministic.
  }

  @override
  void writeInput(String sessionId, List<int> bytes) {
    _requireSession(sessionId);
    throw UnsupportedError('Replay sessions are read-only');
  }

  @override
  void scrollViewport(String sessionId, int deltaLines) {
    _requireSession(sessionId);
    _delegate.scrollViewport(sessionId, deltaLines);
  }

  @override
  void scrollViewportTo(String sessionId, int offset) {
    _requireSession(sessionId);
    _delegate.scrollViewportTo(sessionId, offset);
  }

  @override
  List<PtyEvent> pollEvents(String sessionId) {
    final state = _sessions[sessionId];
    if (state == null) {
      throw StateError('Unknown replay session $sessionId');
    }
    final currentEvents = _delegate.pollEvents(sessionId);
    if (state.bufferedEvents.isEmpty) {
      return currentEvents;
    }
    final events = List<PtyEvent>.unmodifiable(<PtyEvent>[
      ...state.bufferedEvents,
      ...currentEvents,
    ]);
    state.bufferedEvents.clear();
    return events;
  }

  @override
  String? requestSessionV1Json(String sessionId, String requestV1Json) {
    _requireSession(sessionId);
    final delegate = _delegate;
    final requestDelegate = delegate is PtySessionRequestV1Backend
        ? delegate as PtySessionRequestV1Backend
        : null;
    if (requestDelegate == null) {
      throw UnsupportedError('Replay Session Request v1 is not supported');
    }
    return requestDelegate.requestSessionV1Json(sessionId, requestV1Json);
  }

  @override
  PtyDiagnosticEventV1? takeDiagnosticEventV1(String sessionId, String name) {
    _requireSession(sessionId);
    final delegate = _delegate;
    final diagnosticDelegate = delegate is PtySessionDiagnosticEventV1Backend
        ? delegate as PtySessionDiagnosticEventV1Backend
        : null;
    if (diagnosticDelegate == null) {
      throw UnsupportedError('Diagnostic Event v1 is not supported');
    }
    return diagnosticDelegate.takeDiagnosticEventV1(sessionId, name);
  }

  @override
  PtyGraphicAsset? loadGraphicAsset(
    String sessionId, {
    required int assetId,
    required int assetVersion,
  }) {
    _requireSession(sessionId);
    final recorded = _recordedGraphicAssets[(assetId, assetVersion)];
    if (recorded != null) {
      return PtyGraphicAsset(
        assetId: recorded.assetId,
        assetVersion: recorded.assetVersion,
        width: recorded.width,
        height: recorded.height,
        rgba: Uint8List.fromList(recorded.rgba),
      );
    }
    final delegate = _delegate;
    return delegate is PtySessionGraphicAssetBackend
        ? (delegate as PtySessionGraphicAssetBackend).loadGraphicAsset(
            sessionId,
            assetId: assetId,
            assetVersion: assetVersion,
          )
        : null;
  }

  @override
  Uint8List? takeFramePacketV1Protobuf(
    String sessionId, {
    required int? afterSequence,
  }) {
    _requireSession(sessionId);
    final delegate = _delegate;
    return delegate is PtySessionFramePacketV1Backend
        ? (delegate as PtySessionFramePacketV1Backend)
              .takeFramePacketV1Protobuf(
                sessionId,
                afterSequence: afterSequence,
              )
        : null;
  }

  @override
  bool get supportsRefreshHints {
    final delegate = _delegate;
    return delegate is PtySessionRefreshHintBackend &&
        (delegate as PtySessionRefreshHintBackend).supportsRefreshHints;
  }

  @override
  int refreshHintFlags(String sessionId) {
    _requireSession(sessionId);
    final delegate = _delegate;
    return delegate is PtySessionRefreshHintBackend
        ? (delegate as PtySessionRefreshHintBackend).refreshHintFlags(sessionId)
        : PtyRefreshHintFlags.none;
  }

  void _deliverAll(_ReplaySessionState state) {
    while (state.nextEventIndex < state.events.length) {
      final offset = state.events[state.nextEventIndex].monotonicOffset;
      _deliverAtOffset(state, offset);
    }
  }

  void _deliverAtOffset(_ReplaySessionState state, Duration offset) {
    while (state.nextEventIndex < state.events.length &&
        state.events[state.nextEventIndex].monotonicOffset == offset) {
      final event = state.events[state.nextEventIndex];
      state.nextEventIndex += 1;
      _deliver(state, event);
    }
    state.deliveredThrough = offset;
  }

  void _scheduleNext(_ReplaySessionState state) {
    if (!_isCurrent(state) ||
        state.paused ||
        state.nextEventIndex >= state.events.length) {
      return;
    }
    final nextOffset = state.events[state.nextEventIndex].monotonicOffset;
    final delay =
        _scaledPlaybackOffset(nextOffset) -
        _scaledPlaybackOffset(state.deliveredThrough);
    state.timer = _timerFactory(delay, () {
      state.timer = null;
      if (!_isCurrent(state) || state.paused) {
        return;
      }
      _deliverAtOffset(state, nextOffset);
      _scheduleNext(state);
    });
  }

  Duration _scaledPlaybackOffset(Duration recordingOffset) => Duration(
    microseconds: (recordingOffset.inMicroseconds / _playbackSpeed).round(),
  );

  void _deliver(_ReplaySessionState state, TerminalRecordingEvent event) {
    final sessionId = state.sessionId;
    switch (event.kind) {
      case TerminalRecordingEventKind.sessionStarted:
      case TerminalRecordingEventKind.userInput:
      case TerminalRecordingEventKind.shellSemantic:
        return;
      case TerminalRecordingEventKind.ptyOutput:
        _replayDelegate.replayOutput(sessionId, event.bytes!);
      case TerminalRecordingEventKind.resize:
        _delegate.resizeSession(
          sessionId,
          cols: event.payload['cols']! as int,
          rows: event.payload['rows']! as int,
          pixelWidth: event.payload['pixel_width']! as int,
          pixelHeight: event.payload['pixel_height']! as int,
          cellWidth: event.payload['cell_width']! as int,
          cellHeight: event.payload['cell_height']! as int,
        );
      case TerminalRecordingEventKind.sessionExited:
        _replayDelegate.replayExit(
          sessionId,
          exitCode: event.payload['exit_code'] as int?,
        );
      case TerminalRecordingEventKind.checkpoint:
        final delegate = _delegate;
        final checkpointDelegate = delegate is PtyReplayCheckpointBackend
            ? delegate as PtyReplayCheckpointBackend
            : null;
        if (checkpointDelegate == null ||
            !checkpointDelegate.supportsReplayCheckpoints) {
          return;
        }
        final recordingId = event.checkpointId!;
        if (state.checkpoints.containsKey(recordingId)) {
          return;
        }
        final nativeCheckpointId = checkpointDelegate.captureReplayCheckpoint(
          sessionId,
        );
        state.checkpoints[recordingId] = TerminalReplayCheckpoint._(
          recordingId: recordingId,
          sourceSequence: event.checkpointSourceSequence!,
          monotonicOffset: event.monotonicOffset,
          nativeCheckpointId: nativeCheckpointId,
          resumeEventIndex: state.nextEventIndex,
        );
    }
  }

  void _applyInitialGeometry(String sessionId) {
    final started = _recording.events.first;
    _delegate.resizeSession(
      sessionId,
      cols: started.payload['cols']! as int,
      rows: started.payload['rows']! as int,
      pixelWidth: 0,
      pixelHeight: 0,
    );
  }

  _ReplaySessionState _requireSession(String sessionId) {
    final state = _sessions[sessionId];
    if (state == null) {
      throw StateError('Unknown replay session $sessionId');
    }
    return state;
  }

  bool _isCurrent(_ReplaySessionState state) =>
      identical(_sessions[state.sessionId], state);
}

final class _ReplaySessionState {
  _ReplaySessionState({required this.sessionId, required this.events});

  final String sessionId;
  final List<TerminalRecordingEvent> events;
  final Map<String, TerminalReplayCheckpoint> checkpoints =
      <String, TerminalReplayCheckpoint>{};
  final List<PtyEvent> bufferedEvents = <PtyEvent>[];
  int nextEventIndex = 0;
  Duration deliveredThrough = Duration.zero;
  bool paused = false;
  Timer? timer;
}

PtyReplaySessionBackend _requireReplayDelegate(PtySessionBackend delegate) {
  if (delegate case final PtyReplaySessionBackend replayDelegate) {
    return replayDelegate;
  }
  throw ArgumentError.value(
    delegate,
    'delegate',
    'must implement PtyReplaySessionBackend',
  );
}

double _validatedPlaybackSpeed(double playbackSpeed) {
  if (!playbackSpeed.isFinite ||
      playbackSpeed < TerminalReplayBackend.minPlaybackSpeed ||
      playbackSpeed > TerminalReplayBackend.maxPlaybackSpeed) {
    throw ArgumentError.value(
      playbackSpeed,
      'playbackSpeed',
      'must be finite and between '
          '${TerminalReplayBackend.minPlaybackSpeed} and '
          '${TerminalReplayBackend.maxPlaybackSpeed}',
    );
  }
  return playbackSpeed;
}

TerminalRecording _validatedRecording(TerminalRecording recording) {
  const codec = TerminalRecordingCodec();
  final validated = codec.decode(codec.encode(recording));
  if (validated.events.isEmpty ||
      validated.events.first.kind !=
          TerminalRecordingEventKind.sessionStarted) {
    throw ArgumentError.value(
      recording,
      'recording',
      'must begin with session_started',
    );
  }
  return validated;
}

List<TerminalRecordingEvent> _playableEvents(
  List<TerminalRecordingEvent> events,
) {
  return events
      .where(
        (event) =>
            event.kind != TerminalRecordingEventKind.sessionStarted &&
            event.kind != TerminalRecordingEventKind.userInput,
      )
      .toList(growable: false);
}

Timer _defaultTimerFactory(Duration delay, void Function() callback) {
  return Timer(delay, callback);
}
