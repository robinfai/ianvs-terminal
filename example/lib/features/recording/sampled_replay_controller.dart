import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

/// Presents stored structured screens without creating a terminal runtime, PTY,
/// shell parser or historical host action dispatcher.
final class SampledReplayController extends ChangeNotifier {
  SampledReplayController(this.file) {
    graphics = TerminalGraphicsCache(
      loadAsset: (key) async {
        final binding = _assets[key];
        if (binding == null || _disposed) return null;
        final asset = await file.loadAsset(binding);
        return _disposed || !identical(_assets[key], binding) ? null : asset;
      },
    );
  }

  final SampledRecordingFile file;
  final TerminalViewportController viewport = TerminalViewportController();
  late final TerminalGraphicsCache graphics;
  Map<TerminalGraphicAssetKey, SampledRecordingAsset> _assets = {};
  final Stopwatch _clock = Stopwatch();
  Duration _anchor = Duration.zero;
  Timer? _timer;
  double _speed = 1;
  Duration _position = Duration.zero;
  Duration? _sampleOffset;
  _Seek? _pendingSeek;
  RecordingFileCancellation? _seekCancellation;
  bool _seeking = false;
  int _generation = 0;
  int _playRequest = 0;
  bool _disposed = false;
  String? _error;
  String? _timelineError;
  bool _timelineLoading = false;
  RecordingFileCancellation? _timelineCancellation;
  List<SampledTimelineEvent> _events = const [];
  final List<int> _previousCursors = [];
  int _cursor = 0;
  int? _nextCursor;

  Duration get duration => file.info.duration;
  Duration get position => _position;
  Duration? get sampleOffset => _sampleOffset;
  bool get loading => _seeking;
  bool get playing => _timer != null;
  double get speed => _speed;
  String? get error => _error;
  String? get timelineError => _timelineError;
  bool get timelineLoading => _timelineLoading;
  List<SampledTimelineEvent> get events => _events;
  bool get hasNextPage => _nextCursor != null;
  bool get hasPreviousPage => _previousCursors.isNotEmpty;

  Future<void> initialize({Duration position = Duration.zero}) async {
    await Future.wait([seek(position), _loadTimeline(0)]);
  }

  Future<void> seek(Duration target) {
    pause();
    return _request(target);
  }

  Future<void> _request(Duration target) {
    if (_disposed) return Future<void>.value();
    final request = _Seek(
      Duration(
        microseconds: target.inMicroseconds.clamp(0, duration.inMicroseconds),
      ),
      ++_generation,
    );
    _pendingSeek?.complete();
    _pendingSeek = request;
    _seekCancellation?.cancel();
    if (!_seeking) unawaited(_drain());
    return request.done.future;
  }

  Future<void> _drain() async {
    _seeking = true;
    _error = null;
    notifyListeners();
    while (!_disposed && _pendingSeek != null) {
      final request = _pendingSeek!;
      _pendingSeek = null;
      final cancellation = RecordingFileCancellation();
      _seekCancellation = cancellation;
      try {
        final screen = await file.seek(
          request.target,
          cancellation: cancellation,
        );
        if (_disposed || request.generation != _generation) continue;
        if (screen == null) {
          _assets = {};
          graphics.evictExcept({});
          viewport.applySnapshot(TerminalFrameDiff.empty);
        } else {
          _assets = {for (final asset in screen.assets) asset.key: asset};
          // A frame owns at most 32 MiB of retained RGBA data. Evict previous
          // frame assets (including pending loads) before publishing the frame.
          graphics.evictExcept(_assets.keys.toSet());
          viewport.applySnapshot(screen.frame);
        }
        _sampleOffset = screen?.offset;
        _position = request.target;
        _error = null;
      } on RecordingFileCancelled {
        // A replaced seek has no visible error and never publishes its frame.
      } on Object catch (error) {
        if (!_disposed && request.generation == _generation) {
          _error = error.toString();
          pause();
        }
      } finally {
        request.complete();
      }
    }
    _seekCancellation = null;
    _seeking = false;
    if (!_disposed) notifyListeners();
  }

  void play() {
    if (_disposed || playing || duration == Duration.zero) return;
    final request = ++_playRequest;
    if (_position >= duration) {
      unawaited(
        _request(Duration.zero).then((_) {
          if (!_disposed && _error == null && request == _playRequest) play();
        }),
      );
      return;
    }
    _anchor = _position;
    _clock
      ..reset()
      ..start();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_seeking) return;
      final next =
          _anchor +
          Duration(microseconds: (_clock.elapsedMicroseconds * _speed).round());
      if (next >= duration) pause();
      unawaited(_request(next));
    });
    notifyListeners();
  }

  void pause() {
    _playRequest++;
    if (_timer == null) return;
    _timer?.cancel();
    _timer = null;
    _clock.stop();
    if (!_disposed) notifyListeners();
  }

  void setSpeed(double speed) {
    if (!const <double>[0.5, 1, 2, 4].contains(speed)) {
      throw ArgumentError.value(speed, 'speed');
    }
    final resume = playing;
    pause();
    _speed = speed;
    if (resume) play();
    if (!_disposed) notifyListeners();
  }

  Future<bool> _loadTimeline(int cursor) async {
    if (_disposed || _timelineLoading) return false;
    _timelineLoading = true;
    _timelineError = null;
    final cancellation = RecordingFileCancellation();
    _timelineCancellation = cancellation;
    notifyListeners();
    try {
      final page = await file.timeline(
        cursor: cursor,
        limit: 64,
        cancellation: cancellation,
      );
      if (_disposed) return false;
      _events = page.events;
      _cursor = cursor;
      _nextCursor = page.nextCursor;
      return true;
    } on RecordingFileCancelled {
      return false;
    } on Object catch (error) {
      if (!_disposed) _timelineError = error.toString();
      return false;
    } finally {
      _timelineLoading = false;
      _timelineCancellation = null;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> nextPage() async {
    final next = _nextCursor;
    final previous = _cursor;
    if (next != null && await _loadTimeline(next)) {
      if (_previousCursors.length == 128) _previousCursors.removeAt(0);
      _previousCursors.add(previous);
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> previousPage() async {
    if (_previousCursors.isEmpty) return;
    if (await _loadTimeline(_previousCursors.last)) {
      _previousCursors.removeLast();
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> firstPage() async {
    if (await _loadTimeline(0)) {
      _previousCursors.clear();
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _clock.stop();
    _seekCancellation?.cancel();
    _timelineCancellation?.cancel();
    _pendingSeek?.complete();
    _pendingSeek = null;
    graphics.dispose();
    viewport.dispose();
    super.dispose();
  }
}

final class _Seek {
  _Seek(this.target, this.generation);
  final Duration target;
  final int generation;
  final Completer<void> done = Completer<void>();
  void complete() {
    if (!done.isCompleted) done.complete();
  }
}
