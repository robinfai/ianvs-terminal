import 'dart:convert';
import 'package:app/features/recording/recording_replay_navigation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

void main() {
  test(
    'frame navigation retains output boundaries even with late semantics',
    () {
      final recording = TerminalRecording(
        metadata: TerminalRecordingMetadata(
          sessionId: 's',
          createdAtUtc: DateTime.utc(2026, 10, 30),
          inputPolicy: TerminalRecordingInputPolicy.redact,
        ),
        events: [
          for (final (sequence, micros) in [
            (1, 100000),
            (2, 200000),
            (3, 50000000),
          ])
            TerminalRecordingEvent.ptyOutput(
              sessionId: 's',
              sequence: sequence,
              monotonicOffset: Duration(microseconds: micros),
              bytes: utf8.encode('output'),
            ),
          TerminalRecordingEvent.shellSemantic(
            sessionId: 's',
            sequence: 4,
            monotonicOffset: const Duration(seconds: 50),
            semanticKind: TerminalRecordingSemanticKind.prompt,
          ),
        ],
      );
      expect(recordingReplayNavigationOffsets(recording), [
        Duration.zero,
        const Duration(milliseconds: 100),
        const Duration(milliseconds: 200),
        const Duration(seconds: 50),
      ]);
    },
  );
  test('empty recordings retain the initial frame', () {
    expect(
      recordingReplayNavigationOffsets(
        TerminalRecording(
          metadata: TerminalRecordingMetadata(
            sessionId: 's',
            createdAtUtc: DateTime.utc(2026, 10, 30),
            inputPolicy: TerminalRecordingInputPolicy.redact,
          ),
          events: const [],
        ),
      ),
      [Duration.zero],
    );
  });
}
