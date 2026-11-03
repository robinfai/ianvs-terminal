import 'dart:async';

/// Periodic cleanup never overlaps itself. Shutdown stops scheduling and waits
/// for the actual filesystem work, rather than treating cancellation as done.
final class RecordingRetentionMaintenance {
  RecordingRetentionMaintenance({
    required this.run,
    required this.onError,
    this.interval = const Duration(minutes: 5),
  }) {
    if (interval <= Duration.zero) {
      throw ArgumentError.value(interval, 'interval', 'Must be positive');
    }
  }

  final Future<void> Function() run;
  final void Function(Object error) onError;
  final Duration interval;
  Timer? _timer;
  Future<void>? _running;
  bool _stopped = false;

  void start() {
    if (_stopped || _timer != null) return;
    _timer = Timer.periodic(interval, (_) => unawaited(tick()));
  }

  Future<void> tick() {
    if (_stopped) return Future<void>.value();
    return _running ??= _perform().whenComplete(() => _running = null);
  }

  Future<void> _perform() async {
    try {
      await run();
    } on Object catch (error) {
      if (!_stopped) onError(error);
    }
  }

  Future<void> stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
    return _running ?? Future<void>.value();
  }
}
