import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

void main() {
  group('TerminalReplayTimeMap', () {
    test('smart mode compresses idle gaps and remains reversible', () {
      final map = TerminalReplayTimeMap.smart(
        sourceDuration: const Duration(seconds: 10),
        anchors: const <Duration>[
          Duration.zero,
          Duration(seconds: 1),
          Duration(seconds: 9),
          Duration(seconds: 10),
        ],
      );

      expect(map.sourceDuration, const Duration(seconds: 10));
      expect(map.presentationDuration, const Duration(seconds: 4));
      expect(
        map.sourceToPresentation(const Duration(seconds: 5)),
        const Duration(seconds: 2),
      );
      expect(
        map.presentationToSource(const Duration(seconds: 2)),
        const Duration(seconds: 5),
      );
      expect(
        map.sourceToPresentation(const Duration(seconds: 10)),
        const Duration(seconds: 4),
      );
    });

    test('real-time mode clamps offsets to the source range', () {
      final map = TerminalReplayTimeMap.real(const Duration(seconds: 3));

      expect(
        map.sourceToPresentation(const Duration(seconds: -1)),
        Duration.zero,
      );
      expect(
        map.presentationToSource(const Duration(seconds: 4)),
        const Duration(seconds: 3),
      );
    });

    test('rejects a non-positive smart gap', () {
      expect(
        () => TerminalReplayTimeMap.smart(
          sourceDuration: const Duration(seconds: 1),
          anchors: const <Duration>[],
          maximumGap: Duration.zero,
        ),
        throwsArgumentError,
      );
    });
  });

  group('TerminalReplayController', () {
    late _ReplayDriver driver;
    late _PeriodicScheduler scheduler;
    late TerminalReplayController controller;

    setUp(() {
      driver = _ReplayDriver(const Duration(seconds: 10));
      scheduler = _PeriodicScheduler();
      controller = TerminalReplayController(
        driver: driver,
        navigationOffsets: const <Duration>[
          Duration.zero,
          Duration(seconds: 3),
          Duration(seconds: 7),
          Duration(seconds: 10),
        ],
        smartAnchors: const <Duration>[
          Duration.zero,
          Duration(seconds: 1),
          Duration(seconds: 9),
          Duration(seconds: 10),
        ],
        initialTimeMode: TerminalReplayTimeMode.realTime,
        tickInterval: const Duration(seconds: 1),
        timerFactory: scheduler.create,
      );
    });

    tearDown(() {
      controller.dispose();
    });

    test('starts paused and uses one externally driven playback clock', () {
      expect(controller.state.status, TerminalReplayStatus.paused);
      expect(controller.state.sourcePosition, Duration.zero);

      controller.play();
      expect(controller.state.status, TerminalReplayStatus.playing);
      expect(scheduler.activeCount, 1);

      scheduler.tick();

      expect(controller.state.sourcePosition, const Duration(seconds: 1));
      expect(driver.advances, <Duration>[const Duration(seconds: 1)]);

      controller.pause();
      expect(controller.state.status, TerminalReplayStatus.paused);
      expect(scheduler.activeCount, 0);
    });

    test('restarts from zero after reaching the end', () {
      controller.seekToSource(const Duration(seconds: 10));
      controller.play();

      expect(driver.seeks, <Duration>[Duration.zero]);
      expect(controller.state.sourcePosition, Duration.zero);
      expect(controller.state.status, TerminalReplayStatus.playing);
    });

    test('uses absolute timer ticks and reanchors playback speed changes', () {
      controller.play();

      scheduler.tick();
      scheduler.tick();
      expect(controller.state.sourcePosition, const Duration(seconds: 2));

      controller.setSpeed(2);
      scheduler.tick();
      expect(controller.state.sourcePosition, const Duration(seconds: 4));
    });

    test('enters ended state at the shared presentation duration', () {
      controller.play();

      for (var index = 0; index < 10; index += 1) {
        scheduler.tick();
      }

      expect(controller.state.sourcePosition, const Duration(seconds: 10));
      expect(controller.state.status, TerminalReplayStatus.ended);
      expect(scheduler.activeCount, 0);
    });

    test('steps over shared semantic navigation offsets', () {
      controller.seekToSource(const Duration(seconds: 5));

      controller.stepPrevious();
      expect(controller.state.sourcePosition, const Duration(seconds: 3));

      controller.stepNext();
      expect(controller.state.sourcePosition, const Duration(seconds: 7));
    });

    test('switching time mode preserves the materialized source position', () {
      controller.seekToSource(const Duration(seconds: 5));
      controller.setTimeMode(TerminalReplayTimeMode.smart);

      expect(controller.state.sourcePosition, const Duration(seconds: 5));
      expect(controller.state.presentationPosition, const Duration(seconds: 2));
      expect(controller.state.presentationDuration, const Duration(seconds: 4));
    });

    test('driver failures enter a visible error state', () {
      driver.error = StateError('materialization failed');

      controller.seekToSource(const Duration(seconds: 1));

      expect(controller.state.status, TerminalReplayStatus.error);
      expect(controller.state.error, isA<StateError>());
    });

    test('validates playback speed', () {
      expect(
        () => controller.setSpeed(TerminalReplayController.minimumSpeed - 0.1),
        throwsArgumentError,
      );
      expect(
        () => controller.setSpeed(TerminalReplayController.maximumSpeed + 0.1),
        throwsArgumentError,
      );

      controller.setSpeed(2);
      expect(controller.state.speed, 2);
    });
  });
}

final class _ReplayDriver implements TerminalReplayDriver {
  _ReplayDriver(this.duration);

  @override
  final Duration duration;

  @override
  Duration position = Duration.zero;

  Object? error;
  final List<Duration> advances = <Duration>[];
  final List<Duration> seeks = <Duration>[];

  @override
  void advanceTo(Duration sourceOffset) {
    _throwIfNeeded();
    position = sourceOffset;
    advances.add(sourceOffset);
  }

  @override
  void seekTo(Duration sourceOffset) {
    _throwIfNeeded();
    position = sourceOffset;
    seeks.add(sourceOffset);
  }

  void _throwIfNeeded() {
    final currentError = error;
    if (currentError != null) {
      // The fake must preserve the exact configured replay failure object.
      // ignore: only_throw_errors
      throw currentError;
    }
  }
}

final class _PeriodicScheduler {
  _PeriodicTimer? _timer;

  int get activeCount => _timer?.isActive ?? false ? 1 : 0;

  Timer create(Duration interval, void Function(Timer timer) callback) {
    final timer = _PeriodicTimer(callback);
    _timer = timer;
    return timer;
  }

  void tick() {
    final timer = _timer;
    if (timer == null || !timer.isActive) {
      throw StateError('No periodic replay timer is active');
    }
    timer.fire();
  }
}

final class _PeriodicTimer implements Timer {
  _PeriodicTimer(this._callback);

  final void Function(Timer timer) _callback;
  bool _active = true;
  int _tick = 0;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  @override
  void cancel() {
    _active = false;
  }

  void fire() {
    if (!_active) {
      throw StateError('Replay timer is inactive');
    }
    _tick += 1;
    _callback(this);
  }
}
