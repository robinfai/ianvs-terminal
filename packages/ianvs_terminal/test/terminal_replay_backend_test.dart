import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

void main() {
  group('TerminalReplayBackend', () {
    test('no-delay mode replays the same ordered event stream every time', () {
      final driver = _ReplayDriver();
      final backend = TerminalReplayBackend(
        delegate: driver,
        recording: _recording(),
        timingMode: TerminalReplayTimingMode.noDelay,
      );

      final firstSessionId = backend.createSession('{"profile":"first"}');
      final firstCalls = List<String>.from(driver.calls);
      driver.calls.clear();
      final secondSessionId = backend.createSession('{"profile":"second"}');

      expect(firstSessionId, 'replay-1');
      expect(secondSessionId, 'replay-2');
      expect(firstCalls, <String>[
        'create:replay-1',
        'resize:replay-1:80x24:0x0:0x0',
        'output:replay-1:first',
        'resize:replay-1:100x30:1000x600:10x20',
        'output:replay-1:second',
        'exit:replay-1:7',
      ]);
      expect(driver.calls, <String>[
        'create:replay-2',
        'resize:replay-2:80x24:0x0:0x0',
        'output:replay-2:first',
        'resize:replay-2:100x30:1000x600:10x20',
        'output:replay-2:second',
        'exit:replay-2:7',
      ]);
    });

    test('current synchronized initial screen output is replayed exactly', () {
      final driver = _ReplayDriver();
      final backend = TerminalReplayBackend(
        delegate: driver,
        recording: _initialScreenRecording(),
        timingMode: TerminalReplayTimingMode.noDelay,
      );

      backend.createSession('{}');

      expect(driver.replayOutputs, hasLength(1));
      expect(driver.replayOutputs.single, <int>[
        ..._synchronizedStartFixture,
        ..._currentInitialScreenBodyFixture,
        ..._synchronizedEndFixture,
      ]);
    });

    test('realtime mode honors offsets and stable same-offset ordering', () {
      final driver = _ReplayDriver();
      final scheduler = _ReplayScheduler();
      final backend = TerminalReplayBackend(
        delegate: driver,
        recording: _recording(),
        timingMode: TerminalReplayTimingMode.realtime,
        timerFactory: scheduler.createTimer,
      );

      final sessionId = backend.createSession('{}');

      expect(sessionId, 'replay-1');
      expect(driver.calls, <String>[
        'create:replay-1',
        'resize:replay-1:80x24:0x0:0x0',
      ]);
      expect(scheduler.nextDelay, const Duration(milliseconds: 10));

      scheduler.runNext();
      expect(driver.calls.last, 'output:replay-1:first');
      expect(scheduler.nextDelay, const Duration(milliseconds: 10));

      scheduler.runNext();
      expect(driver.calls.skip(3), <String>[
        'resize:replay-1:100x30:1000x600:10x20',
        'output:replay-1:second',
      ]);
      expect(scheduler.nextDelay, const Duration(milliseconds: 10));

      scheduler.runNext();
      expect(driver.calls.last, 'exit:replay-1:7');
      expect(scheduler.hasPending, isFalse);
    });

    test(
      'manual mode advances only when the shared controller requests it',
      () {
        final driver = _ReplayDriver();
        final backend = TerminalReplayBackend(
          delegate: driver,
          recording: const TerminalRecordingCheckpointPlanner(
            playableEventsPerCheckpoint: 2,
          ).addCheckpoints(_recording()),
          timingMode: TerminalReplayTimingMode.manual,
        );

        final sessionId = backend.createSession('{}');
        expect(driver.calls, <String>[
          'create:replay-1',
          'resize:replay-1:80x24:0x0:0x0',
          'checkpoint:replay-1:1',
        ]);
        expect(backend.replayOffsetForSession(sessionId), Duration.zero);

        expect(
          backend.advanceSessionTo(sessionId, const Duration(milliseconds: 20)),
          isTrue,
        );
        expect(
          driver.calls,
          containsAllInOrder(<String>[
            'output:replay-1:first',
            'resize:replay-1:100x30:1000x600:10x20',
            'output:replay-1:second',
          ]),
        );
        expect(
          backend.replayOffsetForSession(sessionId),
          const Duration(milliseconds: 20),
        );

        expect(
          backend.advanceSessionTo(sessionId, const Duration(milliseconds: 20)),
          isFalse,
        );
        expect(
          backend.advanceSessionTo(sessionId, const Duration(milliseconds: 15)),
          isTrue,
        );
        expect(driver.calls.last, 'output:replay-1:first');
        expect(
          backend.replayOffsetForSession(sessionId),
          const Duration(milliseconds: 15),
        );
      },
    );

    test(
      'manual advancement rejects other timing modes and invalid ranges',
      () {
        final realtime = TerminalReplayBackend(
          delegate: _ReplayDriver(),
          recording: _recording(),
        );
        final realtimeSessionId = realtime.createSession('{}');
        expect(
          () => realtime.advanceSessionTo(
            realtimeSessionId,
            const Duration(milliseconds: 5),
          ),
          throwsStateError,
        );

        final manual = TerminalReplayBackend(
          delegate: _ReplayDriver(),
          recording: _recording(),
          timingMode: TerminalReplayTimingMode.manual,
        );
        final manualSessionId = manual.createSession('{}');
        expect(
          () => manual.advanceSessionTo(
            manualSessionId,
            const Duration(microseconds: -1),
          ),
          throwsRangeError,
        );
        expect(
          () => manual.advanceSessionTo(
            manualSessionId,
            const Duration(milliseconds: 31),
          ),
          throwsRangeError,
        );
      },
    );

    test('realtime mode scales the absolute schedule by playback speed', () {
      final driver = _ReplayDriver();
      final scheduler = _ReplayScheduler();
      final backend = TerminalReplayBackend(
        delegate: driver,
        recording: _recording(),
        timingMode: TerminalReplayTimingMode.realtime,
        playbackSpeed: 2,
        timerFactory: scheduler.createTimer,
      );

      backend.createSession('{}');

      expect(scheduler.nextDelay, const Duration(milliseconds: 5));
      scheduler.runNext();
      expect(driver.calls.last, 'output:replay-1:first');
      expect(scheduler.nextDelay, const Duration(milliseconds: 5));
      scheduler.runNext();
      expect(driver.calls.skip(3), <String>[
        'resize:replay-1:100x30:1000x600:10x20',
        'output:replay-1:second',
      ]);
      expect(scheduler.nextDelay, const Duration(milliseconds: 5));
      scheduler.runNext();
      expect(driver.calls.last, 'exit:replay-1:7');
      expect(scheduler.hasPending, isFalse);
    });

    test('realtime playback can pause, resume, and change speed', () {
      final driver = _ReplayDriver();
      final scheduler = _ReplayScheduler();
      final backend = TerminalReplayBackend(
        delegate: driver,
        recording: _recording(),
        timingMode: TerminalReplayTimingMode.realtime,
        timerFactory: scheduler.createTimer,
      );
      final sessionId = backend.createSession('{}');

      expect(backend.isSessionPaused(sessionId), isFalse);
      expect(scheduler.nextDelay, const Duration(milliseconds: 10));

      backend.pauseSession(sessionId);

      expect(backend.isSessionPaused(sessionId), isTrue);
      expect(scheduler.hasPending, isFalse);
      expect(scheduler.runNext, throwsStateError);

      backend.setPlaybackSpeed(2);
      backend.resumeSession(sessionId);

      expect(backend.playbackSpeed, 2);
      expect(backend.isSessionPaused(sessionId), isFalse);
      expect(scheduler.nextDelay, const Duration(milliseconds: 5));
      scheduler.runNext();
      expect(driver.calls.last, 'output:replay-1:first');
    });

    test('speed scaling does not accumulate per-segment rounding drift', () {
      final scheduler = _ReplayScheduler();
      final backend = TerminalReplayBackend(
        delegate: _ReplayDriver(),
        recording: _microsecondRecording(),
        playbackSpeed: 2,
        timerFactory: scheduler.createTimer,
      );

      backend.createSession('{}');

      expect(scheduler.nextDelay, const Duration(microseconds: 1));
      scheduler.runNext();
      expect(scheduler.nextDelay, Duration.zero);
      scheduler.runNext();
      expect(scheduler.nextDelay, const Duration(microseconds: 1));
      scheduler.runNext();
      expect(scheduler.hasPending, isFalse);
    });

    test('playback speed is bounded and finite', () {
      expect(TerminalReplayBackend.minPlaybackSpeed, 0.25);
      expect(TerminalReplayBackend.maxPlaybackSpeed, 4);

      for (final speed in <double>[
        0,
        -1,
        0.249,
        4.001,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => TerminalReplayBackend(
            delegate: _ReplayDriver(),
            recording: _recording(),
            playbackSpeed: speed,
          ),
          throwsArgumentError,
          reason: 'speed=$speed',
        );
      }
    });

    test('no-delay mode remains immediate at a non-default speed', () {
      final driver = _ReplayDriver();
      final scheduler = _ReplayScheduler();
      final backend = TerminalReplayBackend(
        delegate: driver,
        recording: _recording(),
        timingMode: TerminalReplayTimingMode.noDelay,
        playbackSpeed: 0.5,
        timerFactory: scheduler.createTimer,
      );

      backend.createSession('{}');

      expect(driver.calls.last, 'exit:replay-1:7');
      expect(scheduler.hasPending, isFalse);
    });

    test(
      'historical input is never written and live mutation is read-only',
      () {
        final driver = _ReplayDriver();
        final backend = TerminalReplayBackend(
          delegate: driver,
          recording: _recording(),
          timingMode: TerminalReplayTimingMode.noDelay,
        );
        final sessionId = backend.createSession('{}');

        expect(driver.calls, everyElement(isNot(contains('secret'))));
        expect(
          () => backend.writeInput(sessionId, utf8.encode('live input')),
          throwsUnsupportedError,
        );
        backend.resizeSession(
          sessionId,
          cols: 200,
          rows: 60,
          pixelWidth: 2000,
          pixelHeight: 1200,
        );
        expect(
          driver.calls.where((call) => call.startsWith('resize:')),
          <String>[
            'resize:replay-1:80x24:0x0:0x0',
            'resize:replay-1:100x30:1000x600:10x20',
          ],
        );
      },
    );

    test('delegates frames events scrolling and cancellation by session', () {
      final driver = _ReplayDriver();
      final scheduler = _ReplayScheduler();
      final backend = TerminalReplayBackend(
        delegate: driver,
        recording: _recording(),
        timingMode: TerminalReplayTimingMode.realtime,
        timerFactory: scheduler.createTimer,
      );
      final sessionId = backend.createSession('{}');

      expect(backend.takeFrameDiffJson(sessionId), '{"frame_kind":"snapshot"}');
      final events = backend.pollEvents(sessionId);
      expect(events, hasLength(1));
      expect(events.single.kind, 'started');
      expect(events.single.sessionId, sessionId);
      backend.scrollViewport(sessionId, -3);
      backend.scrollViewportTo(sessionId, 8);
      backend.closeSession(sessionId);

      expect(
        driver.calls,
        containsAll(<String>[
          'scroll:replay-1:-3',
          'scrollTo:replay-1:8',
          'close:replay-1',
        ]),
      );
      expect(scheduler.cancelCount, 1);
      expect(scheduler.runNext, throwsStateError);
    });

    test('serves bundled graphic assets before the native fallback', () {
      final driver = _ReplayDriver();
      final recording = const TerminalRecordingGraphicAssetBundler().bundle(
        _recording(),
        graphicAssets: <TerminalRecordingGraphicAsset>[
          TerminalRecordingGraphicAsset(
            assetId: 7,
            assetVersion: 3,
            width: 1,
            height: 1,
            rgba: <int>[11, 22, 33, 255],
          ),
        ],
      );
      final backend = TerminalReplayBackend(
        delegate: driver,
        recording: recording,
        timingMode: TerminalReplayTimingMode.noDelay,
      );
      final sessionId = backend.createSession('{}');

      final bundled = backend.loadGraphicAsset(
        sessionId,
        assetId: 7,
        assetVersion: 3,
      );
      final fallback = backend.loadGraphicAsset(
        sessionId,
        assetId: 9,
        assetVersion: 1,
      );

      expect(bundled, isNotNull);
      expect(bundled!.width, 1);
      expect(bundled.height, 1);
      expect(bundled.rgba, <int>[11, 22, 33, 255]);
      bundled.rgba[0] = 99;
      expect(
        backend.loadGraphicAsset(sessionId, assetId: 7, assetVersion: 3)!.rgba,
        <int>[11, 22, 33, 255],
      );
      expect(fallback, isNotNull);
      expect(fallback!.rgba, <int>[9, 1, 0, 255]);
      expect(driver.assetRequests, <String>['replay-1:9:1']);
    });

    test(
      'preserves Frame Packet v1 and its acknowledgement through replay',
      () {
        final driver = _ReplayDriver();
        final backend = TerminalReplayBackend(
          delegate: driver,
          recording: _recording(),
          timingMode: TerminalReplayTimingMode.noDelay,
        );
        final sessionId = backend.createSession('{}');
        final packetBackend = backend as PtySessionFramePacketV1Backend;

        expect(packetBackend.supportsFramePacketV1, isTrue);
        expect(
          packetBackend.takeFramePacketV1Protobuf(sessionId, afterSequence: 3),
          <int>[10, 1],
        );
        expect(driver.packetRequests, <(String, int?)>[(sessionId, 3)]);
      },
    );

    test('routes SessionConfig v1 through the replay-specific capability', () {
      final driver = _ReplayDriver();
      final backend = TerminalReplayBackend(
        delegate: driver,
        recording: _recording(),
        timingMode: TerminalReplayTimingMode.noDelay,
      );

      expect(
        (backend as PtySessionConfigV1Backend).supportsSessionConfigV1,
        isTrue,
      );
      final sessionId = backend.createSessionV1('{"schema_version":1}');

      expect(sessionId, 'replay-1');
      expect(driver.versionedCreateConfigs, <String>['{"schema_version":1}']);
      expect(driver.legacyCreateConfigs, isEmpty);
    });

    test('preserves Session Request v1 through the replay delegate', () {
      final driver = _ReplayDriver();
      final backend = TerminalReplayBackend(
        delegate: driver,
        recording: _recording(),
        timingMode: TerminalReplayTimingMode.noDelay,
      );
      final sessionId = backend.createSession('{}');

      expect(
        (backend as PtySessionRequestV1Backend).supportsSessionRequestV1,
        isTrue,
      );
      expect(
        backend.requestSessionV1Json(sessionId, '{"schema_version":1}'),
        '{"ok":true}',
      );
      expect(driver.versionedRequests, <String>[
        '$sessionId:{"schema_version":1}',
      ]);
    });

    test('preserves Diagnostic Event v1 through the replay delegate', () {
      final driver = _NumericDiagnosticReplayDriver();
      final backend = TerminalReplayBackend(
        delegate: driver,
        recording: _recording(),
        timingMode: TerminalReplayTimingMode.noDelay,
      );
      final sessionId = backend.createSession('{}');
      final diagnosticBackend = backend as PtySessionDiagnosticEventV1Backend;

      expect(diagnosticBackend.supportsDiagnosticEventV1, isTrue);
      final event = diagnosticBackend.takeDiagnosticEventV1(
        sessionId,
        'session_stats',
      );

      expect(event, isNotNull);
      expect(event!.sessionId, sessionId);
      expect(event.name, 'session_stats');
      expect(event.payload['bytes_read'], 4);
      expect(driver.diagnosticRequests, <String>['$sessionId:session_stats']);
    });

    test(
      'materializes current checkpoint markers through the native delegate',
      () {
        final driver = _ReplayDriver();
        final recording = const TerminalRecordingCheckpointPlanner(
          playableEventsPerCheckpoint: 2,
        ).addCheckpoints(_recording());
        final backend = TerminalReplayBackend(
          delegate: driver,
          recording: recording,
          timingMode: TerminalReplayTimingMode.noDelay,
        );

        final sessionId = backend.createSession('{}');
        final checkpoints = backend.checkpointsForSession(sessionId);

        expect(backend.supportsReplayCheckpoints, isTrue);
        expect(
          checkpoints.map((checkpoint) => checkpoint.recordingId),
          <String>['checkpoint-0', 'checkpoint-3', 'checkpoint-4'],
        );
        expect(
          checkpoints.map((checkpoint) => checkpoint.sourceSequence),
          <int>[0, 3, 4],
        );
        expect(
          driver.calls.where((call) => call.startsWith('checkpoint:')),
          <String>[
            'checkpoint:replay-1:1',
            'checkpoint:replay-1:2',
            'checkpoint:replay-1:3',
          ],
        );
      },
    );

    test('seeks backward by restoring and replaying from a checkpoint', () {
      final driver = _ReplayDriver();
      final recording = const TerminalRecordingCheckpointPlanner(
        playableEventsPerCheckpoint: 2,
      ).addCheckpoints(_recording());
      final backend = TerminalReplayBackend(
        delegate: driver,
        recording: recording,
        timingMode: TerminalReplayTimingMode.noDelay,
      );
      final sessionId = backend.createSession('{}');
      final captureCalls = driver.calls
          .where((call) => call.startsWith('checkpoint:'))
          .toList();
      driver.calls.clear();

      final result = backend.seekSession(
        sessionId,
        const Duration(milliseconds: 15),
      );

      expect(backend.supportsReplaySeek, isTrue);
      expect(backend.replayDuration, const Duration(milliseconds: 30));
      expect(
        backend.replayOffsetForSession(sessionId),
        const Duration(milliseconds: 15),
      );
      expect(result.targetOffset, const Duration(milliseconds: 15));
      expect(result.checkpoint.recordingId, 'checkpoint-0');
      expect(result.replayedEventCount, 1);
      expect(result.discardedSeekEventCount, 0);
      expect(driver.calls, <String>[
        'restore:replay-1:1',
        'output:replay-1:first',
      ]);
      expect(captureCalls, hasLength(3));
      expect(
        driver.calls.where((call) => call.startsWith('checkpoint:')),
        isEmpty,
        reason: 'known checkpoint markers must not be materialized again',
      );
      expect(
        backend.pollEvents(sessionId).map((event) => event.kind),
        <String>['started', 'exit'],
        reason: 'events pending before seek must remain observable once',
      );
    });

    test('exact seek uses the latest checkpoint at the target offset', () {
      final driver = _ReplayDriver();
      final backend = TerminalReplayBackend(
        delegate: driver,
        recording: const TerminalRecordingCheckpointPlanner(
          playableEventsPerCheckpoint: 2,
        ).addCheckpoints(_recording()),
        timingMode: TerminalReplayTimingMode.noDelay,
      );
      final sessionId = backend.createSession('{}');
      driver.calls.clear();

      final result = backend.seekSession(
        sessionId,
        const Duration(milliseconds: 20),
      );

      expect(result.checkpoint.recordingId, 'checkpoint-4');
      expect(result.replayedEventCount, 0);
      expect(driver.calls, <String>['restore:replay-1:3']);
    });

    test(
      'seek preserves pending events and discards regenerated lifecycle',
      () {
        final driver = _ReplayDriver();
        final backend = TerminalReplayBackend(
          delegate: driver,
          recording: const TerminalRecordingCheckpointPlanner(
            playableEventsPerCheckpoint: 2,
          ).addCheckpoints(_recording()),
          timingMode: TerminalReplayTimingMode.noDelay,
        );
        final sessionId = backend.createSession('{}');

        final result = backend.seekSession(
          sessionId,
          const Duration(milliseconds: 30),
        );

        expect(result.checkpoint.recordingId, 'checkpoint-4');
        expect(result.replayedEventCount, 1);
        expect(result.discardedSeekEventCount, 1);
        expect(
          backend.pollEvents(sessionId).map((event) => event.kind),
          <String>['started', 'exit'],
        );
        expect(backend.pollEvents(sessionId), isEmpty);
      },
    );

    test('realtime seek replaces the timer from the requested offset', () {
      final driver = _ReplayDriver();
      final scheduler = _ReplayScheduler();
      final backend = TerminalReplayBackend(
        delegate: driver,
        recording: const TerminalRecordingCheckpointPlanner(
          playableEventsPerCheckpoint: 2,
        ).addCheckpoints(_recording()),
        timingMode: TerminalReplayTimingMode.realtime,
        timerFactory: scheduler.createTimer,
      );
      final sessionId = backend.createSession('{}');
      expect(scheduler.nextDelay, const Duration(milliseconds: 10));
      driver.calls.clear();

      final result = backend.seekSession(
        sessionId,
        const Duration(milliseconds: 15),
      );

      expect(result.replayedEventCount, 1);
      expect(scheduler.cancelCount, 1);
      expect(scheduler.nextDelay, const Duration(milliseconds: 5));
      expect(driver.calls, <String>[
        'restore:replay-1:1',
        'output:replay-1:first',
      ]);
    });

    test('seek rejects unsupported ranges and failed native restore', () {
      final legacyBackend = TerminalReplayBackend(
        delegate: _ReplayDriver(supportsCheckpoints: false),
        recording: const TerminalRecordingCheckpointPlanner(
          playableEventsPerCheckpoint: 2,
        ).addCheckpoints(_recording()),
        timingMode: TerminalReplayTimingMode.noDelay,
      );
      final legacySessionId = legacyBackend.createSession('{}');
      expect(legacyBackend.supportsReplaySeek, isFalse);
      expect(
        () => legacyBackend.seekSession(legacySessionId, Duration.zero),
        throwsUnsupportedError,
      );

      final scheduler = _ReplayScheduler();
      final failingBackend = TerminalReplayBackend(
        delegate: _ReplayDriver(restoreSucceeds: false),
        recording: const TerminalRecordingCheckpointPlanner(
          playableEventsPerCheckpoint: 2,
        ).addCheckpoints(_recording()),
        timingMode: TerminalReplayTimingMode.realtime,
        timerFactory: scheduler.createTimer,
      );
      final sessionId = failingBackend.createSession('{}');
      expect(
        () => failingBackend.seekSession(
          sessionId,
          const Duration(microseconds: -1),
        ),
        throwsRangeError,
      );
      expect(
        () => failingBackend.seekSession(
          sessionId,
          const Duration(milliseconds: 31),
        ),
        throwsRangeError,
      );
      expect(
        () => failingBackend.seekSession(
          sessionId,
          const Duration(milliseconds: 15),
        ),
        throwsA(isA<TerminalReplaySeekException>()),
      );
      expect(scheduler.hasPending, isTrue);
      expect(failingBackend.replayOffsetForSession(sessionId), Duration.zero);
    });

    test('legacy replay delegates ignore checkpoint markers safely', () {
      final driver = _ReplayDriver(supportsCheckpoints: false);
      final recording = const TerminalRecordingCheckpointPlanner(
        playableEventsPerCheckpoint: 2,
      ).addCheckpoints(_recording());
      final backend = TerminalReplayBackend(
        delegate: driver,
        recording: recording,
        timingMode: TerminalReplayTimingMode.noDelay,
      );

      final sessionId = backend.createSession('{}');

      expect(backend.supportsReplayCheckpoints, isFalse);
      expect(backend.checkpointsForSession(sessionId), isEmpty);
      expect(driver.calls.last, 'exit:replay-1:7');
    });

    test(
      'seek restores the expected Frame through the real native core',
      () {
        final delegate = NativePtyBackend.fromBindings(
          NativePtyBindings(
            ffi.DynamicLibrary.open(_workspaceCoreLibraryPath!),
          ),
        );
        final backend = TerminalReplayBackend(
          delegate: delegate,
          recording: const TerminalRecordingCheckpointPlanner(
            playableEventsPerCheckpoint: 2,
          ).addCheckpoints(_recording()),
          timingMode: TerminalReplayTimingMode.noDelay,
        );
        final sessionId = backend.createSession(
          '{"id":"native-seek","name":"Native Seek","launch":{"program":"/definitely/not/a/child"}}',
        );

        try {
          final result = backend.seekSession(
            sessionId,
            const Duration(milliseconds: 15),
          );
          final frame = backend.takeFrameDiffJson(sessionId);

          expect(result.checkpoint.recordingId, 'checkpoint-0');
          expect(frame, contains('first'));
          expect(frame, isNot(contains('second')));
        } finally {
          backend.closeSession(sessionId);
        }
      },
      skip: _workspaceCoreLibraryPath == null
          ? 'libianvs_core.dylib is unavailable for this test run.'
          : false,
    );
  });
}

final String? _workspaceCoreLibraryPath = _resolveWorkspaceCoreLibraryPath();

String? _resolveWorkspaceCoreLibraryPath() {
  if (!Platform.isMacOS) {
    return null;
  }
  const candidates = <String>[
    'native/core/target/debug/libianvs_core.dylib',
    '../native/core/target/debug/libianvs_core.dylib',
    '../../native/core/target/debug/libianvs_core.dylib',
  ];
  for (final candidate in candidates) {
    final file = File(candidate);
    if (file.existsSync()) {
      return file.absolute.path;
    }
  }
  return null;
}

TerminalRecording _recording() {
  const sessionId = 'fixture-replay';
  return TerminalRecording(
    metadata: TerminalRecordingMetadata(
      sessionId: sessionId,
      createdAtUtc: DateTime.utc(2026, 7, 21),
      inputPolicy: TerminalRecordingInputPolicy.record,
    ),
    events: <TerminalRecordingEvent>[
      TerminalRecordingEvent.sessionStarted(
        sessionId: sessionId,
        sequence: 0,
        monotonicOffset: Duration.zero,
        terminalEmulation: 'xterm256',
        cols: 80,
        rows: 24,
      ),
      TerminalRecordingEvent.ptyOutput(
        sessionId: sessionId,
        sequence: 1,
        monotonicOffset: const Duration(milliseconds: 10),
        bytes: utf8.encode('first'),
      ),
      TerminalRecordingEvent.userInput(
        sessionId: sessionId,
        sequence: 2,
        monotonicOffset: const Duration(milliseconds: 15),
        bytes: utf8.encode('secret'),
      ),
      TerminalRecordingEvent.resize(
        sessionId: sessionId,
        sequence: 3,
        monotonicOffset: const Duration(milliseconds: 20),
        cols: 100,
        rows: 30,
        pixelWidth: 1000,
        pixelHeight: 600,
        cellWidth: 10,
        cellHeight: 20,
      ),
      TerminalRecordingEvent.ptyOutput(
        sessionId: sessionId,
        sequence: 4,
        monotonicOffset: const Duration(milliseconds: 20),
        bytes: utf8.encode('second'),
      ),
      TerminalRecordingEvent.sessionExited(
        sessionId: sessionId,
        sequence: 5,
        monotonicOffset: const Duration(milliseconds: 30),
        exitCode: 7,
      ),
    ],
  );
}

const _synchronizedStartFixture = <int>[
  0x1b,
  0x5b,
  0x3f,
  0x32,
  0x30,
  0x32,
  0x36,
  0x68,
];
const _synchronizedEndFixture = <int>[
  0x1b,
  0x5b,
  0x3f,
  0x32,
  0x30,
  0x32,
  0x36,
  0x6c,
];
const _currentInitialScreenBodyFixture = <int>[
  0x1b,
  0x5b,
  0x32,
  0x4a,
  0x1b,
  0x5b,
  0x48,
  0x66,
  0x69,
  0x72,
  0x73,
  0x74,
  0x1b,
  0x5b,
  0x3f,
  0x32,
  0x35,
  0x68,
];

TerminalRecording _initialScreenRecording() {
  const sessionId = 'fixture-initial-screen';
  return TerminalRecording(
    metadata: TerminalRecordingMetadata(
      sessionId: sessionId,
      createdAtUtc: DateTime.utc(2026, 7, 25),
      inputPolicy: TerminalRecordingInputPolicy.redact,
    ),
    events: <TerminalRecordingEvent>[
      TerminalRecordingEvent.sessionStarted(
        sessionId: sessionId,
        sequence: 0,
        monotonicOffset: Duration.zero,
        terminalEmulation: 'xterm256',
        cols: 80,
        rows: 24,
      ),
      TerminalRecordingEvent.ptyOutput(
        sessionId: sessionId,
        sequence: 1,
        monotonicOffset: Duration.zero,
        bytes: <int>[
          ..._synchronizedStartFixture,
          ..._currentInitialScreenBodyFixture,
          ..._synchronizedEndFixture,
        ],
      ),
    ],
  );
}

TerminalRecording _microsecondRecording() {
  const sessionId = 'fixture-microsecond-replay';
  return TerminalRecording(
    metadata: TerminalRecordingMetadata(
      sessionId: sessionId,
      createdAtUtc: DateTime.utc(2026, 7, 21),
      inputPolicy: TerminalRecordingInputPolicy.redact,
    ),
    events: <TerminalRecordingEvent>[
      TerminalRecordingEvent.sessionStarted(
        sessionId: sessionId,
        sequence: 0,
        monotonicOffset: Duration.zero,
        terminalEmulation: 'xterm256',
        cols: 80,
        rows: 24,
      ),
      for (var sequence = 1; sequence <= 3; sequence += 1)
        TerminalRecordingEvent.ptyOutput(
          sessionId: sessionId,
          sequence: sequence,
          monotonicOffset: Duration(microseconds: sequence),
          bytes: <int>[sequence],
        ),
    ],
  );
}

class _ReplayDriver
    implements
        PtySessionBackend,
        PtyReplaySessionBackend,
        PtyReplayCheckpointBackend,
        PtyReplaySessionConfigV1Backend,
        PtySessionRequestV1Backend,
        PtySessionDiagnosticEventV1Backend,
        PtySessionGraphicAssetBackend,
        PtySessionFramePacketV1Backend {
  _ReplayDriver({this.supportsCheckpoints = true, this.restoreSucceeds = true});

  final bool supportsCheckpoints;
  final bool restoreSucceeds;
  final List<String> calls = <String>[];
  final List<List<int>> replayOutputs = <List<int>>[];
  final List<String> versionedCreateConfigs = <String>[];
  final List<String> legacyCreateConfigs = <String>[];
  final List<String> versionedRequests = <String>[];
  final List<String> diagnosticRequests = <String>[];
  final List<String> assetRequests = <String>[];
  final List<(String, int?)> packetRequests = <(String, int?)>[];
  final List<PtyEvent> pendingEvents = <PtyEvent>[];
  int _sessionSeed = 0;
  int _checkpointSeed = 0;

  @override
  PtyGraphicAsset? loadGraphicAsset(
    String sessionId, {
    required int assetId,
    required int assetVersion,
  }) {
    assetRequests.add('$sessionId:$assetId:$assetVersion');
    return PtyGraphicAsset(
      assetId: assetId,
      assetVersion: assetVersion,
      width: 1,
      height: 1,
      rgba: Uint8List.fromList(<int>[assetId, assetVersion, 0, 255]),
    );
  }

  @override
  bool get supportsReplayCheckpoints => supportsCheckpoints;

  @override
  int captureReplayCheckpoint(String sessionId) {
    final checkpointId = ++_checkpointSeed;
    calls.add('checkpoint:$sessionId:$checkpointId');
    return checkpointId;
  }

  @override
  bool restoreReplayCheckpoint(String sessionId, int checkpointId) {
    calls.add('restore:$sessionId:$checkpointId');
    return restoreSucceeds;
  }

  @override
  int ping() => 42;

  @override
  String createReplaySession(String sessionConfigJson) {
    legacyCreateConfigs.add(sessionConfigJson);
    final sessionId = 'replay-${++_sessionSeed}';
    calls.add('create:$sessionId');
    pendingEvents.add(PtyEvent(kind: 'started', sessionId: sessionId));
    return sessionId;
  }

  @override
  bool get supportsReplaySessionConfigV1 => true;

  @override
  String createReplaySessionV1(String sessionConfigV1Json) {
    versionedCreateConfigs.add(sessionConfigV1Json);
    final sessionId = 'replay-${++_sessionSeed}';
    calls.add('create:$sessionId');
    pendingEvents.add(PtyEvent(kind: 'started', sessionId: sessionId));
    return sessionId;
  }

  @override
  bool get supportsSessionRequestV1 => true;

  @override
  String? requestSessionV1Json(String sessionId, String requestV1Json) {
    versionedRequests.add('$sessionId:$requestV1Json');
    return '{"ok":true}';
  }

  @override
  bool get supportsDiagnosticEventV1 => true;

  @override
  PtyDiagnosticEventV1? takeDiagnosticEventV1(String sessionId, String name) {
    diagnosticRequests.add('$sessionId:$name');
    return PtyDiagnosticEventV1.fromJson(<String, Object?>{
      'schema_version': 1,
      'contract': 'ianvs-runtime-envelope-v1',
      'message_class': 'diagnostic',
      'message_name': name,
      'session_id': sessionId,
      'sequence': diagnosticRequests.length - 1,
      'timestamp_micros': 1,
      'payload': <String, Object?>{'bytes_read': 4},
    });
  }

  @override
  bool get supportsFramePacketV1 => true;

  @override
  Uint8List? takeFramePacketV1Protobuf(
    String sessionId, {
    required int? afterSequence,
  }) {
    packetRequests.add((sessionId, afterSequence));
    return Uint8List.fromList(const <int>[10, 1]);
  }

  @override
  void replayOutput(String sessionId, List<int> bytes) {
    replayOutputs.add(List<int>.unmodifiable(bytes));
    calls.add('output:$sessionId:${utf8.decode(bytes)}');
  }

  @override
  void replayExit(String sessionId, {int? exitCode}) {
    calls.add('exit:$sessionId:$exitCode');
    pendingEvents.add(
      PtyEvent(
        kind: 'exit',
        sessionId: sessionId,
        payload: <String, Object?>{'code': exitCode},
      ),
    );
  }

  @override
  String createSession(String sessionConfigJson) {
    throw UnsupportedError('live session creation is not used by replay');
  }

  @override
  void closeSession(String sessionId) => calls.add('close:$sessionId');

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
    calls.add(
      'resize:$sessionId:${cols}x$rows:'
      '${pixelWidth}x$pixelHeight:${cellWidth}x$cellHeight',
    );
  }

  @override
  void writeInput(String sessionId, List<int> bytes) {
    calls.add('write:$sessionId:${base64Encode(bytes)}');
  }

  @override
  void scrollViewport(String sessionId, int deltaLines) {
    calls.add('scroll:$sessionId:$deltaLines');
  }

  @override
  void scrollViewportTo(String sessionId, int offset) {
    calls.add('scrollTo:$sessionId:$offset');
  }

  @override
  String? takeFrameDiffJson(String sessionId) => '{"frame_kind":"snapshot"}';

  @override
  List<PtyEvent> pollEvents(String sessionId) {
    final events = pendingEvents
        .where((event) => event.sessionId == sessionId)
        .toList(growable: false);
    pendingEvents.removeWhere((event) => event.sessionId == sessionId);
    return events;
  }
}

final class _NumericDiagnosticReplayDriver extends _ReplayDriver {
  @override
  String createReplaySession(String sessionConfigJson) {
    legacyCreateConfigs.add(sessionConfigJson);
    calls.add('create:1');
    return '1';
  }
}

final class _ReplayScheduler {
  final List<_ReplayTimer> _timers = <_ReplayTimer>[];
  int cancelCount = 0;

  Timer createTimer(Duration delay, void Function() callback) {
    final timer = _ReplayTimer(
      delay: delay,
      callback: callback,
      onCancel: () => cancelCount += 1,
    );
    _timers.add(timer);
    return timer;
  }

  bool get hasPending => _timers.any((timer) => timer.isActive);

  Duration? get nextDelay => _timers
      .where((timer) => timer.isActive)
      .map((timer) => timer.delay)
      .firstOrNull;

  void runNext() {
    final timer = _timers.where((timer) => timer.isActive).firstOrNull;
    if (timer == null) {
      throw StateError('No replay timer is pending');
    }
    timer.fire();
  }
}

final class _ReplayTimer implements Timer {
  _ReplayTimer({
    required this.delay,
    required this.callback,
    required this.onCancel,
  });

  final Duration delay;
  final void Function() callback;
  final void Function() onCancel;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => _active ? 0 : 1;

  @override
  void cancel() {
    if (!_active) {
      return;
    }
    _active = false;
    onCancel();
  }

  void fire() {
    if (!_active) {
      throw StateError('Replay timer is not active');
    }
    _active = false;
    callback();
  }
}
