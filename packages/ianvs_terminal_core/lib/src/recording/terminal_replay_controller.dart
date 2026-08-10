import 'dart:async';

import 'package:flutter/foundation.dart';

enum TerminalReplayStatus { paused, playing, seeking, ended, error }

enum TerminalReplayTimeMode { realTime, smart }

abstract interface class TerminalReplayDriver {
  Duration get duration;

  Duration get position;

  void advanceTo(Duration sourceOffset);

  void seekTo(Duration sourceOffset);
}

typedef TerminalReplayPeriodicTimerFactory =
    Timer Function(Duration interval, void Function(Timer timer) callback);

@immutable
final class TerminalReplayState {
  const TerminalReplayState({
    required this.status,
    required this.sourcePosition,
    required this.presentationPosition,
    required this.sourceDuration,
    required this.presentationDuration,
    required this.speed,
    required this.timeMode,
    this.error,
  });

  final TerminalReplayStatus status;
  final Duration sourcePosition;
  final Duration presentationPosition;
  final Duration sourceDuration;
  final Duration presentationDuration;
  final double speed;
  final TerminalReplayTimeMode timeMode;
  final Object? error;

  bool get isPlaying => status == TerminalReplayStatus.playing;

  bool get isEnded => status == TerminalReplayStatus.ended;

  TerminalReplayState copyWith({
    TerminalReplayStatus? status,
    Duration? sourcePosition,
    Duration? presentationPosition,
    Duration? sourceDuration,
    Duration? presentationDuration,
    double? speed,
    TerminalReplayTimeMode? timeMode,
    Object? error,
    bool clearError = false,
  }) {
    return TerminalReplayState(
      status: status ?? this.status,
      sourcePosition: sourcePosition ?? this.sourcePosition,
      presentationPosition: presentationPosition ?? this.presentationPosition,
      sourceDuration: sourceDuration ?? this.sourceDuration,
      presentationDuration: presentationDuration ?? this.presentationDuration,
      speed: speed ?? this.speed,
      timeMode: timeMode ?? this.timeMode,
      error: clearError ? null : error ?? this.error,
    );
  }
}

@immutable
final class TerminalReplayTimeMap {
  TerminalReplayTimeMap._({
    required this.sourceDuration,
    required List<_TerminalReplayTimeSegment> segments,
  }) : _segments = List<_TerminalReplayTimeSegment>.unmodifiable(segments),
       presentationDuration = segments.isEmpty
           ? Duration.zero
           : segments.last.presentationEnd;

  factory TerminalReplayTimeMap.real(Duration sourceDuration) {
    final duration = _nonNegativeDuration(sourceDuration);
    return TerminalReplayTimeMap._(
      sourceDuration: duration,
      segments: duration == Duration.zero
          ? const <_TerminalReplayTimeSegment>[]
          : <_TerminalReplayTimeSegment>[
              _TerminalReplayTimeSegment(
                sourceStart: Duration.zero,
                sourceEnd: duration,
                presentationStart: Duration.zero,
                presentationEnd: duration,
              ),
            ],
    );
  }

  factory TerminalReplayTimeMap.smart({
    required Duration sourceDuration,
    required Iterable<Duration> anchors,
    Duration maximumGap = const Duration(seconds: 2),
  }) {
    final duration = _nonNegativeDuration(sourceDuration);
    if (maximumGap <= Duration.zero) {
      throw ArgumentError.value(
        maximumGap,
        'maximumGap',
        'must be greater than zero',
      );
    }
    if (duration == Duration.zero) {
      return TerminalReplayTimeMap.real(Duration.zero);
    }
    final normalizedAnchors = <int>{
      0,
      duration.inMicroseconds,
      for (final anchor in anchors)
        anchor.inMicroseconds.clamp(0, duration.inMicroseconds),
    }.toList()..sort();
    final segments = <_TerminalReplayTimeSegment>[];
    var presentationStart = Duration.zero;
    for (var index = 1; index < normalizedAnchors.length; index += 1) {
      final sourceStart = Duration(microseconds: normalizedAnchors[index - 1]);
      final sourceEnd = Duration(microseconds: normalizedAnchors[index]);
      final sourceGap = sourceEnd - sourceStart;
      final presentationGap = sourceGap > maximumGap ? maximumGap : sourceGap;
      final presentationEnd = presentationStart + presentationGap;
      segments.add(
        _TerminalReplayTimeSegment(
          sourceStart: sourceStart,
          sourceEnd: sourceEnd,
          presentationStart: presentationStart,
          presentationEnd: presentationEnd,
        ),
      );
      presentationStart = presentationEnd;
    }
    return TerminalReplayTimeMap._(
      sourceDuration: duration,
      segments: segments,
    );
  }

  final Duration sourceDuration;
  final Duration presentationDuration;
  final List<_TerminalReplayTimeSegment> _segments;

  Duration sourceToPresentation(Duration sourceOffset) {
    if (_segments.isEmpty) {
      return Duration.zero;
    }
    final source = _clampDuration(sourceOffset, Duration.zero, sourceDuration);
    final segment = _segmentForSource(source);
    return _mapDuration(
      value: source,
      inputStart: segment.sourceStart,
      inputEnd: segment.sourceEnd,
      outputStart: segment.presentationStart,
      outputEnd: segment.presentationEnd,
    );
  }

  Duration presentationToSource(Duration presentationOffset) {
    if (_segments.isEmpty) {
      return Duration.zero;
    }
    final presentation = _clampDuration(
      presentationOffset,
      Duration.zero,
      presentationDuration,
    );
    final segment = _segmentForPresentation(presentation);
    return _mapDuration(
      value: presentation,
      inputStart: segment.presentationStart,
      inputEnd: segment.presentationEnd,
      outputStart: segment.sourceStart,
      outputEnd: segment.sourceEnd,
    );
  }

  _TerminalReplayTimeSegment _segmentForSource(Duration value) {
    for (final segment in _segments) {
      if (value <= segment.sourceEnd) {
        return segment;
      }
    }
    return _segments.last;
  }

  _TerminalReplayTimeSegment _segmentForPresentation(Duration value) {
    for (final segment in _segments) {
      if (value <= segment.presentationEnd) {
        return segment;
      }
    }
    return _segments.last;
  }
}

@immutable
final class _TerminalReplayTimeSegment {
  const _TerminalReplayTimeSegment({
    required this.sourceStart,
    required this.sourceEnd,
    required this.presentationStart,
    required this.presentationEnd,
  });

  final Duration sourceStart;
  final Duration sourceEnd;
  final Duration presentationStart;
  final Duration presentationEnd;
}

final class TerminalReplayController extends ChangeNotifier {
  TerminalReplayController({
    required TerminalReplayDriver driver,
    Iterable<Duration> navigationOffsets = const <Duration>[],
    Iterable<Duration> smartAnchors = const <Duration>[],
    TerminalReplayTimeMode initialTimeMode = TerminalReplayTimeMode.smart,
    double initialSpeed = 1,
    Duration maximumSmartGap = const Duration(seconds: 2),
    Duration tickInterval = const Duration(milliseconds: 16),
    TerminalReplayPeriodicTimerFactory? timerFactory,
  }) : _driver = driver,
       _maximumSmartGap = maximumSmartGap,
       _tickInterval = tickInterval,
       _timerFactory = timerFactory ?? _defaultPeriodicTimerFactory,
       _navigationOffsets = _normalizedOffsets(
         navigationOffsets,
         driver.duration,
       ),
       _smartAnchors = _normalizedOffsets(smartAnchors, driver.duration),
       _realTimeMap = TerminalReplayTimeMap.real(driver.duration),
       _smartTimeMap = TerminalReplayTimeMap.smart(
         sourceDuration: driver.duration,
         anchors: smartAnchors,
         maximumGap: maximumSmartGap,
       ),
       _state = TerminalReplayState(
         status: TerminalReplayStatus.paused,
         sourcePosition: _clampDuration(
           driver.position,
           Duration.zero,
           driver.duration,
         ),
         presentationPosition: Duration.zero,
         sourceDuration: driver.duration,
         presentationDuration: Duration.zero,
         speed: _validatedSpeed(initialSpeed),
         timeMode: initialTimeMode,
       ) {
    if (tickInterval <= Duration.zero) {
      throw ArgumentError.value(
        tickInterval,
        'tickInterval',
        'must be greater than zero',
      );
    }
    final timeMap = _timeMapFor(initialTimeMode);
    _state = _state.copyWith(
      presentationPosition: timeMap.sourceToPresentation(_state.sourcePosition),
      presentationDuration: timeMap.presentationDuration,
    );
  }

  static const double minimumSpeed = 0.25;
  static const double maximumSpeed = 4;

  final TerminalReplayDriver _driver;
  final Duration _maximumSmartGap;
  final Duration _tickInterval;
  final TerminalReplayPeriodicTimerFactory _timerFactory;
  final List<Duration> _navigationOffsets;
  final List<Duration> _smartAnchors;
  final TerminalReplayTimeMap _realTimeMap;
  final TerminalReplayTimeMap _smartTimeMap;

  TerminalReplayState _state;
  Timer? _timer;
  Duration _playbackBasePresentation = Duration.zero;

  TerminalReplayState get state => _state;

  TerminalReplayTimeMap get timeMap => _timeMapFor(_state.timeMode);

  List<Duration> get navigationOffsets => _navigationOffsets;

  List<Duration> get smartAnchors => _smartAnchors;

  Duration get maximumSmartGap => _maximumSmartGap;

  bool get canStepPrevious =>
      _navigationOffsets.any((offset) => offset < _state.sourcePosition);

  bool get canStepNext =>
      _navigationOffsets.any((offset) => offset > _state.sourcePosition);

  void play() {
    if (_state.status == TerminalReplayStatus.playing ||
        _state.sourceDuration == Duration.zero) {
      return;
    }
    if (_state.sourcePosition >= _state.sourceDuration) {
      if (!_materialize(Duration.zero, seeking: true)) {
        return;
      }
    }
    _playbackBasePresentation = _state.presentationPosition;
    _timer?.cancel();
    _timer = _timerFactory(_tickInterval, _handleTimer);
    _setState(
      _state.copyWith(status: TerminalReplayStatus.playing, clearError: true),
    );
  }

  void pause() {
    if (_state.status != TerminalReplayStatus.playing) {
      return;
    }
    _cancelPlaybackTimer();
    _setState(_state.copyWith(status: TerminalReplayStatus.paused));
  }

  void togglePlayback() {
    if (_state.status == TerminalReplayStatus.playing) {
      pause();
    } else {
      play();
    }
  }

  void setSpeed(double value) {
    final speed = _validatedSpeed(value);
    if (_state.speed == speed) {
      return;
    }
    _setState(_state.copyWith(speed: speed));
    if (_state.status == TerminalReplayStatus.playing) {
      _restartPlaybackTimer();
    }
  }

  void setTimeMode(TerminalReplayTimeMode mode) {
    if (_state.timeMode == mode) {
      return;
    }
    final nextMap = _timeMapFor(mode);
    _setState(
      _state.copyWith(
        timeMode: mode,
        presentationPosition: nextMap.sourceToPresentation(
          _state.sourcePosition,
        ),
        presentationDuration: nextMap.presentationDuration,
      ),
    );
    if (_state.status == TerminalReplayStatus.playing) {
      _restartPlaybackTimer();
    }
  }

  void seekToSource(Duration sourceOffset) {
    _cancelPlaybackTimer();
    _materialize(sourceOffset, seeking: true);
  }

  void seekToPresentation(Duration presentationOffset) {
    seekToSource(timeMap.presentationToSource(presentationOffset));
  }

  void stepPrevious() {
    Duration? target;
    for (final offset in _navigationOffsets) {
      if (offset >= _state.sourcePosition) {
        break;
      }
      target = offset;
    }
    if (target != null) {
      seekToSource(target);
    }
  }

  void stepNext() {
    for (final offset in _navigationOffsets) {
      if (offset > _state.sourcePosition) {
        seekToSource(offset);
        return;
      }
    }
  }

  @override
  void dispose() {
    _cancelPlaybackTimer();
    super.dispose();
  }

  void _handleTimer(Timer timer) {
    _tick(timer.tick);
  }

  void _tick(int timerTick) {
    if (_state.status != TerminalReplayStatus.playing) {
      return;
    }
    final scaledElapsed = Duration(
      microseconds: (_tickInterval.inMicroseconds * timerTick * _state.speed)
          .round(),
    );
    final nextPresentation = _clampDuration(
      _playbackBasePresentation + scaledElapsed,
      Duration.zero,
      _state.presentationDuration,
    );
    final nextSource = timeMap.presentationToSource(nextPresentation);
    if (!_materialize(nextSource, seeking: false)) {
      return;
    }
    if (nextPresentation >= _state.presentationDuration) {
      _cancelPlaybackTimer();
      _setState(_state.copyWith(status: TerminalReplayStatus.ended));
    }
  }

  bool _materialize(Duration requestedSource, {required bool seeking}) {
    final source = _clampDuration(
      requestedSource,
      Duration.zero,
      _state.sourceDuration,
    );
    try {
      if (source < _driver.position) {
        _driver.seekTo(source);
      } else {
        _driver.advanceTo(source);
      }
      final presentation = timeMap.sourceToPresentation(source);
      _setState(
        _state.copyWith(
          status: seeking ? TerminalReplayStatus.paused : _state.status,
          sourcePosition: source,
          presentationPosition: presentation,
          clearError: true,
        ),
      );
      return true;
    } on Object catch (error) {
      _cancelPlaybackTimer();
      _setState(
        _state.copyWith(status: TerminalReplayStatus.error, error: error),
      );
      return false;
    }
  }

  void _cancelPlaybackTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _restartPlaybackTimer() {
    _timer?.cancel();
    _playbackBasePresentation = _state.presentationPosition;
    _timer = _timerFactory(_tickInterval, _handleTimer);
  }

  TerminalReplayTimeMap _timeMapFor(TerminalReplayTimeMode mode) {
    return switch (mode) {
      TerminalReplayTimeMode.realTime => _realTimeMap,
      TerminalReplayTimeMode.smart => _smartTimeMap,
    };
  }

  void _setState(TerminalReplayState nextState) {
    if (identical(_state, nextState)) {
      return;
    }
    _state = nextState;
    notifyListeners();
  }
}

Timer _defaultPeriodicTimerFactory(
  Duration interval,
  void Function(Timer timer) callback,
) {
  return Timer.periodic(interval, callback);
}

double _validatedSpeed(double value) {
  if (!value.isFinite ||
      value < TerminalReplayController.minimumSpeed ||
      value > TerminalReplayController.maximumSpeed) {
    throw ArgumentError.value(
      value,
      'value',
      'must be finite and between '
          '${TerminalReplayController.minimumSpeed} and '
          '${TerminalReplayController.maximumSpeed}',
    );
  }
  return value;
}

Duration _nonNegativeDuration(Duration value) {
  return value < Duration.zero ? Duration.zero : value;
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

Duration _mapDuration({
  required Duration value,
  required Duration inputStart,
  required Duration inputEnd,
  required Duration outputStart,
  required Duration outputEnd,
}) {
  final inputSpan = (inputEnd - inputStart).inMicroseconds;
  if (inputSpan <= 0) {
    return outputStart;
  }
  final outputSpan = (outputEnd - outputStart).inMicroseconds;
  final offset = (value - inputStart).inMicroseconds;
  return outputStart +
      Duration(microseconds: (offset * outputSpan / inputSpan).round());
}

List<Duration> _normalizedOffsets(
  Iterable<Duration> offsets,
  Duration duration,
) {
  final maximum = _nonNegativeDuration(duration).inMicroseconds;
  final values = <int>{
    for (final offset in offsets) offset.inMicroseconds.clamp(0, maximum),
  }.toList()..sort();
  return List<Duration>.unmodifiable(
    values.map((value) => Duration(microseconds: value)),
  );
}
