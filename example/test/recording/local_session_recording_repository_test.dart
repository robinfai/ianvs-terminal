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

    test('lists, renames, imports, and exports validated recordings', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-recording-library',
      );
      final externalDirectory = await Directory.systemTemp.createTemp(
        'ianvs terminal-recording-library-external',
      );
      addTearDown(() async {
        await directory.delete(recursive: true);
        await externalDirectory.delete(recursive: true);
      });
      final repository = LocalSessionRecordingRepository(
        directoryResolver: () async => directory,
      );
      final recording = _recording('runtime-library');
      final destination = await repository.reserve(
        workspaceId: 'workspace-library',
        descriptorId: 'descriptor-library',
        runtimeSessionId: 'runtime-library',
        createdAtUtc: recording.metadata.createdAtUtc,
      );
      await repository.save(
        destination,
        recording,
        displayName: 'Foundation shell debug',
      );

      var entries = await repository.listRecordings();

      expect(entries, hasLength(1));
      expect(entries.single.workspaceId, 'workspace-library');
      expect(entries.single.displayName, 'Foundation shell debug');
      expect(entries.single.duration, const Duration(microseconds: 10));
      expect(entries.single.inputPolicy, TerminalRecordingInputPolicy.redact);

      await repository.renameRecording(
        entries.single.path,
        'vttest regression',
      );
      entries = await repository.listRecordings();
      expect(entries.single.displayName, 'vttest regression');

      final source = File('${externalDirectory.path}/import.ndjson');
      await source.writeAsString(
        const TerminalRecordingCodec().encode(_recording('runtime-import')),
      );
      final imported = await repository.importRecording(
        sourcePath: source.path,
        workspaceId: 'workspace-library',
        displayName: 'Imported recording',
      );

      expect(imported.displayName, 'Imported recording');
      expect(await File(imported.path).exists(), isTrue);

      final exportPath = '${externalDirectory.path}/export.ndjson';
      await repository.exportRecording(imported.path, exportPath);
      final exported = await repository.load(exportPath);
      expect(exported.metadata.sessionId, 'runtime-import');
    });
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
