import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import 'package:app/features/recording/local_session_recording_repository.dart';

void main() {
  group('Local session recording repository', () {
    test(
      'reserves collision-safe files and roundtrips validated v1 data',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-repository',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final recording = _recording('runtime-1');

        final first = await repository.reserve(
          workspaceId: 'workspace-1',
          descriptorId: 'descriptor-1',
          runtimeSessionId: 'runtime-1',
          createdAtUtc: recording.metadata.createdAtUtc,
        );
        final firstPath = await repository.save(first, recording);
        final second = await repository.reserve(
          workspaceId: 'workspace-1',
          descriptorId: 'descriptor-1',
          runtimeSessionId: 'runtime-1',
          createdAtUtc: recording.metadata.createdAtUtc,
        );

        expect(firstPath, first.file.absolute.path);
        expect(await first.file.exists(), isTrue);
        expect(second.file.path, isNot(first.file.path));
        expect(first.file.path, endsWith('.ndjson'));
        final loaded = await repository.load(firstPath);
        expect(loaded.metadata.sessionId, 'runtime-1');
        expect(
          loaded.metadata.inputPolicy,
          TerminalRecordingInputPolicy.redact,
        );
        expect(
          loaded.events.map((event) => event.kind),
          <TerminalRecordingEventKind>[
            TerminalRecordingEventKind.sessionStarted,
            TerminalRecordingEventKind.ptyOutput,
          ],
        );
      },
    );

    test(
      'rejects invalid identity segments before creating a destination',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-invalid',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );

        await expectLater(
          repository.reserve(
            workspaceId: '',
            descriptorId: 'descriptor-1',
            runtimeSessionId: 'runtime-1',
            createdAtUtc: DateTime.utc(2026, 7, 21),
          ),
          throwsFormatException,
        );
        expect(directory.listSync(), isEmpty);
      },
    );
  });
}

TerminalRecording _recording(String sessionId) {
  return TerminalRecording(
    metadata: TerminalRecordingMetadata(
      sessionId: sessionId,
      createdAtUtc: DateTime.utc(2026, 7, 21, 6),
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
        monotonicOffset: const Duration(microseconds: 10),
        bytes: const <int>[114, 101, 97, 100, 121, 13, 10],
      ),
    ],
  );
}
