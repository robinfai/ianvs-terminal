import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

void main() {
  group('TerminalRecordingCheckpointPlanner', () {
    test(
      'upgrades v1 and inserts deterministic initial periodic and final checkpoints',
      () {
        const planner = TerminalRecordingCheckpointPlanner(
          playableEventsPerCheckpoint: 2,
        );

        final upgraded = planner.addCheckpoints(_recording());

        expect(upgraded.metadata.schemaVersion, 2);
        expect(
          upgraded.events.map((event) => event.sequence),
          List<int>.generate(upgraded.events.length, (index) => index),
        );
        expect(
          upgraded.events.map((event) => event.schemaVersion).toSet(),
          <int>{2},
        );
        final checkpoints = upgraded.events
            .where(
              (event) => event.kind == TerminalRecordingEventKind.checkpoint,
            )
            .toList(growable: false);
        expect(
          checkpoints.map((event) => event.checkpointSourceSequence),
          <int>[0, 2, 3],
        );
        expect(checkpoints.map((event) => event.checkpointId), <String>[
          'checkpoint-0',
          'checkpoint-2',
          'checkpoint-3',
        ]);
        expect(
          const TerminalRecordingCodec()
              .decode(const TerminalRecordingCodec().encode(upgraded))
              .events,
          hasLength(upgraded.events.length),
        );
      },
    );

    test('replanning strips old markers and stays byte deterministic', () {
      const planner = TerminalRecordingCheckpointPlanner(
        playableEventsPerCheckpoint: 1,
      );
      const codec = TerminalRecordingCodec();
      final first = planner.addCheckpoints(_recording());

      final second = planner.addCheckpoints(first);

      expect(codec.encode(second), codec.encode(first));
    });

    test('validates policy bounds', () {
      expect(
        () => const TerminalRecordingCheckpointPlanner(
          playableEventsPerCheckpoint: 0,
        ).addCheckpoints(_recording()),
        throwsArgumentError,
      );
      expect(
        () => const TerminalRecordingCheckpointPlanner(
          maxCheckpoints: 1,
        ).addCheckpoints(_recording()),
        throwsArgumentError,
      );
    });

    test('delays checkpoints until a split control string is terminated', () {
      const planner = TerminalRecordingCheckpointPlanner(
        playableEventsPerCheckpoint: 1,
      );
      final recording = _recordingWithSplitControlString();

      final planned = planner.addCheckpoints(recording);
      final checkpoints = planned.events
          .where((event) => event.kind == TerminalRecordingEventKind.checkpoint)
          .toList(growable: false);

      expect(checkpoints.map((event) => event.checkpointSourceSequence), <int>[
        0,
        2,
      ]);
    });
  });
}

TerminalRecording _recording() {
  const sessionId = 'checkpoint-plan';
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
      TerminalRecordingEvent.ptyOutput(
        sessionId: sessionId,
        sequence: 1,
        monotonicOffset: const Duration(milliseconds: 1),
        bytes: utf8.encode('one'),
      ),
      TerminalRecordingEvent.resize(
        sessionId: sessionId,
        sequence: 2,
        monotonicOffset: const Duration(milliseconds: 2),
        cols: 100,
        rows: 30,
        pixelWidth: 1000,
        pixelHeight: 600,
      ),
      TerminalRecordingEvent.ptyOutput(
        sessionId: sessionId,
        sequence: 3,
        monotonicOffset: const Duration(milliseconds: 3),
        bytes: utf8.encode('two'),
      ),
      TerminalRecordingEvent.sessionExited(
        sessionId: sessionId,
        sequence: 4,
        monotonicOffset: const Duration(milliseconds: 4),
        exitCode: 0,
      ),
    ],
  );
}

TerminalRecording _recordingWithSplitControlString() {
  const sessionId = 'checkpoint-split-control';
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
      TerminalRecordingEvent.ptyOutput(
        sessionId: sessionId,
        sequence: 1,
        monotonicOffset: const Duration(milliseconds: 1),
        bytes: utf8.encode('\x1b]0;partial'),
      ),
      TerminalRecordingEvent.ptyOutput(
        sessionId: sessionId,
        sequence: 2,
        monotonicOffset: const Duration(milliseconds: 2),
        bytes: utf8.encode(' title\x07safe'),
      ),
    ],
  );
}
