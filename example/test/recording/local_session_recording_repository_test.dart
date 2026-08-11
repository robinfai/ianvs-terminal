import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/features/recording/local_session_recording_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

void main() {
  group('Local session recording repository', () {
    test('resolves and creates the canonical recording directory', () async {
      final supportDirectory = await Directory.systemTemp.createTemp(
        'ianvs terminal-recording-directory',
      );
      addTearDown(() => supportDirectory.delete(recursive: true));
      final repository = LocalSessionRecordingRepository(
        directoryResolver: () async => supportDirectory,
      );

      final recordingDirectory = await repository.ensureRecordingDirectory();

      expect(
        recordingDirectory.path,
        Directory(
          '${supportDirectory.path}${Platform.pathSeparator}ianvs_recordings',
        ).absolute.path,
      );
      expect(await recordingDirectory.exists(), isTrue);
    });

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
          runtimeSessionId: 'runtime-1',
          createdAtUtc: recording.metadata.createdAtUtc,
        );
        final firstPath = await repository.save(first, recording);
        final second = await repository.reserve(
          runtimeSessionId: 'runtime-1',
          createdAtUtc: recording.metadata.createdAtUtc,
        );

        expect(firstPath, first.file.absolute.path);
        expect(await first.file.exists(), isTrue);
        expect(second.file.path, isNot(first.file.path));
        expect(first.file.path, endsWith('.ndjson'));
        expect(first.file.parent.path, endsWith('ianvs_recordings'));
        expect(first.file.path, isNot(contains('workspace-')));
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

    test('save awaits background encoding before the atomic flush', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-recording-background-encode',
      );
      addTearDown(() => directory.delete(recursive: true));
      final allowEncode = Completer<void>();
      final encodeStarted = Completer<void>();
      final repository = LocalSessionRecordingRepository(
        directoryResolver: () async => directory,
        encoder: (recording) async {
          encodeStarted.complete();
          await allowEncode.future;
          return const TerminalRecordingCodec().encode(recording);
        },
      );
      final recording = _recording('background-encode');
      final destination = await repository.reserve(
        runtimeSessionId: recording.metadata.sessionId,
        createdAtUtc: recording.metadata.createdAtUtc,
      );

      final save = repository.save(destination, recording);
      await encodeStarted.future;

      expect(await destination.file.exists(), isFalse);
      allowEncode.complete();
      await save;
      expect(await destination.file.exists(), isTrue);
    });

    test(
      'default path delegates whole-file save and load to worker seams',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-file-worker',
        );
        addTearDown(() => directory.delete(recursive: true));
        var writerCalls = 0;
        var readerCalls = 0;
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
          fileWriter: (path, recording) async {
            writerCalls += 1;
            await File(path).writeAsString(
              const TerminalRecordingCodec().encode(recording),
              flush: true,
            );
          },
          fileReader: (path) async {
            readerCalls += 1;
            return const TerminalRecordingCodec().decode(
              await File(path).readAsString(),
            );
          },
        );
        final recording = _recording('whole-file-worker');
        final destination = await repository.reserve(
          runtimeSessionId: recording.metadata.sessionId,
          createdAtUtc: recording.metadata.createdAtUtc,
        );

        final path = await repository.save(destination, recording);
        final loaded = await repository.load(path);

        expect(writerCalls, 1);
        expect(readerCalls, 1);
        expect(loaded.metadata.sessionId, recording.metadata.sessionId);
      },
    );

    test('rejects an invalid runtime session id', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-recording-invalid',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = LocalSessionRecordingRepository(
        directoryResolver: () async => directory,
      );

      await expectLater(
        repository.reserve(
          runtimeSessionId: '',
          createdAtUtc: DateTime.utc(2026, 7, 21),
        ),
        throwsFormatException,
      );
      expect(directory.listSync(), isEmpty);
    });

    test('opens an external recording without importing it', () async {
      final supportDirectory = await Directory.systemTemp.createTemp(
        'ianvs terminal-recording-open-support',
      );
      final externalDirectory = await Directory.systemTemp.createTemp(
        'ianvs terminal-recording-open-external',
      );
      addTearDown(() async {
        await supportDirectory.delete(recursive: true);
        await externalDirectory.delete(recursive: true);
      });
      final source = File('${externalDirectory.path}/direct-replay.ndjson');
      await source.writeAsString(
        const TerminalRecordingCodec().encode(_recording('runtime-direct')),
      );
      final repository = LocalSessionRecordingRepository(
        directoryResolver: () async => supportDirectory,
      );

      final opened = await repository.openRecording(source.path);

      expect(opened.entry.path, source.absolute.path);
      expect(opened.entry.displayName, 'direct-replay');
      expect(opened.entry.sessionId, 'runtime-direct');
      expect(opened.recording.metadata.sessionId, 'runtime-direct');
      expect(
        Directory('${supportDirectory.path}/ianvs_recordings').existsSync(),
        isFalse,
      );
    });

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
        displayName: 'Imported recording',
      );

      expect(imported.displayName, 'Imported recording');
      expect(await File(imported.path).exists(), isTrue);

      final exportPath = '${externalDirectory.path}/export.ndjson';
      await repository.exportRecording(imported.path, exportPath);
      final exported = await repository.load(exportPath);
      expect(exported.metadata.sessionId, 'runtime-import');
    });

    test(
      'keeps legacy workspace-partitioned recordings discoverable',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-legacy-library',
        );
        addTearDown(() => directory.delete(recursive: true));
        final legacyFile = File(
          '${directory.path}/ianvs_recordings/workspace-project-old/'
          'legacy.ndjson',
        );
        await legacyFile.parent.create(recursive: true);
        await legacyFile.writeAsString(
          const TerminalRecordingCodec().encode(_recording('legacy-runtime')),
        );
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );

        final entries = await repository.listRecordings();

        expect(entries, hasLength(1));
        expect(entries.single.path, legacyFile.absolute.path);
        expect(entries.single.sessionId, 'legacy-runtime');
      },
    );

    test('migrates the v1 name index using lightweight metadata reads', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-recording-index-migration',
      );
      addTearDown(() => directory.delete(recursive: true));
      final root = Directory('${directory.path}/ianvs_recordings');
      await root.create(recursive: true);
      final recordingFile = File('${root.path}/legacy.ndjson').absolute;
      await recordingFile.writeAsString(
        '${jsonEncode(<String, Object?>{'record_type': 'metadata', 'schema_version': 1, 'session_id': 'legacy-index-session', 'created_at_utc': '2026-07-21T06:00:00.000Z', 'input_policy': 'redact'})}\n'
        '{invalid-middle-record}\n'
        '${jsonEncode(<String, Object?>{
          'record_type': 'event',
          'schema_version': 1,
          'session_id': 'legacy-index-session',
          'sequence': 1,
          'monotonic_offset_micros': 42,
          'event_kind': 'pty_output',
          'payload': <String, Object?>{'bytes_base64': 'QQ=='},
        })}\n',
      );
      final indexFile = File('${root.path}/library-v1.json');
      await indexFile.writeAsString(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'names': <String, String>{
            recordingFile.path: 'Migrated display name',
          },
        }),
      );
      var fullDecodeCount = 0;
      final repository = LocalSessionRecordingRepository(
        directoryResolver: () async => directory,
        decoder: (source) async {
          fullDecodeCount += 1;
          return const TerminalRecordingCodec().decode(source);
        },
      );

      final entries = await repository.listRecordings();

      expect(entries, hasLength(1));
      expect(entries.single.displayName, 'Migrated display name');
      expect(entries.single.sessionId, 'legacy-index-session');
      expect(entries.single.duration, const Duration(microseconds: 42));
      expect(entries.single.isReadable, isTrue);
      expect(fullDecodeCount, 0);
      await expectLater(
        repository.load(recordingFile.path),
        throwsFormatException,
      );
      expect(fullDecodeCount, 1);
      final migrated = jsonDecode(await indexFile.readAsString()) as Map;
      expect(migrated['schemaVersion'], 2);
      expect(migrated['entries'] as Map, contains(recordingFile.path));
    });

    test('quarantines a corrupt metadata index and rebuilds it', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-recording-index-quarantine',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = LocalSessionRecordingRepository(
        directoryResolver: () async => directory,
      );
      final recording = _recording('quarantine-runtime');
      final destination = await repository.reserve(
        runtimeSessionId: recording.metadata.sessionId,
        createdAtUtc: recording.metadata.createdAtUtc,
      );
      await repository.save(destination, recording);
      final root = destination.file.parent;
      final indexFile = File('${root.path}/library-v1.json');
      await indexFile.writeAsString('{not-json');

      final entries = await repository.listRecordings();

      expect(entries.single.sessionId, 'quarantine-runtime');
      expect(
        root.listSync().whereType<File>().where(
          (file) => file.path.contains('library-v1.json.corrupt.'),
        ),
        hasLength(1),
      );
      final rebuilt = jsonDecode(await indexFile.readAsString()) as Map;
      expect(rebuilt['schemaVersion'], 2);
    });

    test(
      'native handoff finalizes decode merge encode and atomic write off-isolate',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-native-finalize',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final handoffDirectory = await repository
            .ensureNativeHandoffDirectory();
        if (!Platform.isWindows) {
          expect((await handoffDirectory.stat()).mode & 0x1ff, 0x1c0);
        }
        const jobId = '0123456789abcdef0123456789abcdef';
        final handoff = File(
          '${handoffDirectory.path}/'
          '.ianvs-recording-handoff-$jobId.ndjson',
        );
        await handoff.writeAsString(
          const TerminalRecordingCodec().encode(_recording('native-worker')),
          flush: true,
        );
        final destination = await repository.reserve(
          runtimeSessionId: 'native-worker',
          createdAtUtc: DateTime.utc(2026, 7, 21, 6),
        );
        final job = TerminalRecordingFinalizeJob(
          sessionId: 'native-worker',
          jobId: jobId,
          handoffPath: handoff.path,
          errorPath: '${handoff.path}.error.json',
        );

        final path = await repository.finalizeNativeRecording(
          job: job,
          handoffDirectory: handoffDirectory,
          destination: destination,
          semanticEvents: const <TerminalRecordingSemanticEvent>[
            TerminalRecordingSemanticEvent(
              monotonicOffset: Duration(microseconds: 5),
              kind: TerminalRecordingSemanticKind.commandStarted,
              command: 'pwd',
            ),
          ],
        );

        expect(path, destination.file.absolute.path);
        expect(await handoff.exists(), isFalse);
        final finalized = await repository.load(path);
        expect(
          finalized.metadata.schemaVersion,
          terminalRecordingSemanticSchemaVersion,
        );
        expect(
          finalized.events.map((event) => event.kind),
          contains(TerminalRecordingEventKind.shellSemantic),
        );
        expect(
          finalized.events
              .firstWhere(
                (event) =>
                    event.kind == TerminalRecordingEventKind.shellSemantic,
              )
              .semanticCommand,
          'pwd',
        );
      },
    );

    test('native handoff timeout retains ready-to-recover paths', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-recording-native-timeout',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = LocalSessionRecordingRepository(
        directoryResolver: () async => directory,
        finalizeTimeout: const Duration(milliseconds: 2),
        finalizePollInterval: const Duration(milliseconds: 1),
      );
      final handoffDirectory = await repository.ensureNativeHandoffDirectory();
      const jobId = 'fedcba9876543210fedcba9876543210';
      final handoffPath =
          '${handoffDirectory.path}/'
          '.ianvs-recording-handoff-$jobId.ndjson';
      final destination = await repository.reserve(
        runtimeSessionId: 'native-timeout',
        createdAtUtc: DateTime.utc(2026, 7, 21, 6),
      );
      final job = TerminalRecordingFinalizeJob(
        sessionId: 'native-timeout',
        jobId: jobId,
        handoffPath: handoffPath,
        errorPath: '$handoffPath.error.json',
      );

      await expectLater(
        repository.finalizeNativeRecording(
          job: job,
          handoffDirectory: handoffDirectory,
          destination: destination,
          semanticEvents: const <TerminalRecordingSemanticEvent>[],
        ),
        throwsA(
          isA<LocalSessionRecordingFinalizeException>().having(
            (error) => error.failure,
            'failure',
            LocalSessionRecordingFinalizeFailure.timedOut,
          ),
        ),
      );
      expect(await handoffDirectory.exists(), isTrue);
      expect(await destination.file.exists(), isFalse);
      expect(await File('$handoffPath.manifest.json').exists(), isTrue);

      await File(handoffPath).writeAsString(
        const TerminalRecordingCodec().encode(_recording('native-timeout')),
        flush: true,
      );
      final path = await repository.finalizeNativeRecording(
        job: job,
        handoffDirectory: handoffDirectory,
        destination: destination,
        semanticEvents: const <TerminalRecordingSemanticEvent>[],
      );
      expect(path, destination.file.path);
      expect(await File('$handoffPath.manifest.json').exists(), isFalse);
    });

    test(
      'native handoff cancellation is bounded and leaves job untouched',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-native-cancel',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final handoffDirectory = await repository
            .ensureNativeHandoffDirectory();
        const jobId = '00112233445566778899aabbccddeeff';
        final handoffPath =
            '${handoffDirectory.path}/'
            '.ianvs-recording-handoff-$jobId.ndjson';
        final cancellation = LocalSessionRecordingFinalizeCancellation()
          ..cancel();
        final destination = await repository.reserve(
          runtimeSessionId: 'native-cancel',
          createdAtUtc: DateTime.utc(2026, 7, 21, 6),
        );

        await expectLater(
          repository.finalizeNativeRecording(
            job: TerminalRecordingFinalizeJob(
              sessionId: 'native-cancel',
              jobId: jobId,
              handoffPath: handoffPath,
              errorPath: '$handoffPath.error.json',
            ),
            handoffDirectory: handoffDirectory,
            destination: destination,
            semanticEvents: const <TerminalRecordingSemanticEvent>[],
            cancellation: cancellation,
          ),
          throwsA(
            isA<LocalSessionRecordingFinalizeException>().having(
              (error) => error.failure,
              'failure',
              LocalSessionRecordingFinalizeFailure.cancelled,
            ),
          ),
        );
        expect(await destination.file.exists(), isFalse);
      },
    );

    test('a new repository instance recovers a ready manifest job', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-recording-native-restart',
      );
      addTearDown(() => directory.delete(recursive: true));
      final firstProcess = LocalSessionRecordingRepository(
        directoryResolver: () async => directory,
      );
      final handoffDirectory = await firstProcess
          .ensureNativeHandoffDirectory();
      const jobId = '11223344556677889900aabbccddeeff';
      final handoff = File(
        '${handoffDirectory.path}/'
        '.ianvs-recording-handoff-$jobId.ndjson',
      );
      await handoff.writeAsString(
        const TerminalRecordingCodec().encode(_recording('restart-worker')),
        flush: true,
      );
      final destination = await firstProcess.reserve(
        runtimeSessionId: 'restart-worker',
        createdAtUtc: DateTime.utc(2026, 7, 21, 6),
      );
      final job = TerminalRecordingFinalizeJob(
        sessionId: 'restart-worker',
        jobId: jobId,
        handoffPath: handoff.path,
        errorPath: '${handoff.path}.error.json',
      );
      await firstProcess.registerNativeRecordingJob(
        job: job,
        handoffDirectory: handoffDirectory,
        destination: destination,
        semanticEvents: const <TerminalRecordingSemanticEvent>[
          TerminalRecordingSemanticEvent(
            monotonicOffset: Duration(microseconds: 5),
            kind: TerminalRecordingSemanticKind.commandStarted,
            command: 'recover-me',
          ),
        ],
        displayName: 'Recovered recording',
      );
      final secondProcess = LocalSessionRecordingRepository(
        directoryResolver: () async => directory,
      );

      final recovery = await secondProcess.recoverNativeRecordings();

      expect(recovery.failures, isEmpty);
      expect(recovery.pendingJobIds, isEmpty);
      expect(recovery.recoveredPaths, <String>[destination.file.path]);
      expect(await handoff.exists(), isFalse);
      expect(await File('${handoff.path}.manifest.json').exists(), isFalse);
      final recovered = await secondProcess.load(destination.file.path);
      expect(
        recovered.events
            .where(
              (event) => event.kind == TerminalRecordingEventKind.shellSemantic,
            )
            .single
            .semanticCommand,
        'recover-me',
      );
      final entries = await secondProcess.listRecordings();
      expect(entries.single.displayName, 'Recovered recording');
    });

    test(
      'intent manifest exists before native prepare and a stale intent writes nothing',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-native-intent',
        );
        addTearDown(() => directory.delete(recursive: true));
        final owner = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final handoffDirectory = await owner.ensureNativeHandoffDirectory();
        final destination = await owner.reserve(
          runtimeSessionId: 'intent-only',
          createdAtUtc: DateTime.utc(2026, 7, 21, 6),
        );
        final job = await owner.reserveNativeRecordingJob(
          sessionId: 'intent-only',
          handoffDirectory: handoffDirectory,
          destination: destination,
          semanticEvents: const <TerminalRecordingSemanticEvent>[],
        );

        expect(await File('${job.handoffPath}.manifest.json').exists(), isTrue);
        expect(await File(job.handoffPath).exists(), isFalse);
        final cancellation = LocalSessionRecordingFinalizeCancellation()
          ..cancel();
        await expectLater(
          owner.finalizeNativeRecording(
            job: job,
            handoffDirectory: handoffDirectory,
            destination: destination,
            semanticEvents: const <TerminalRecordingSemanticEvent>[],
            cancellation: cancellation,
          ),
          throwsA(
            isA<LocalSessionRecordingFinalizeException>().having(
              (error) => error.failure,
              'failure',
              LocalSessionRecordingFinalizeFailure.cancelled,
            ),
          ),
        );

        final recovery = await LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        ).recoverNativeRecordings();

        expect(recovery.recoveredPaths, isEmpty);
        expect(recovery.pendingJobIds, contains(job.jobId));
        expect(await destination.file.exists(), isFalse);
      },
    );

    test(
      'ready handoff after prepare crash retains its destination mapping',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-native-prepare-crash',
        );
        addTearDown(() => directory.delete(recursive: true));
        final owner = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final handoffDirectory = await owner.ensureNativeHandoffDirectory();
        final destination = await owner.reserve(
          runtimeSessionId: 'prepare-crash',
          createdAtUtc: DateTime.utc(2026, 7, 21, 6),
        );
        final job = await owner.reserveNativeRecordingJob(
          sessionId: 'prepare-crash',
          handoffDirectory: handoffDirectory,
          destination: destination,
          semanticEvents: const <TerminalRecordingSemanticEvent>[
            TerminalRecordingSemanticEvent(
              monotonicOffset: Duration(microseconds: 5),
              kind: TerminalRecordingSemanticKind.commandStarted,
              command: 'recover-after-crash',
            ),
          ],
        );
        await File(job.handoffPath).writeAsString(
          const TerminalRecordingCodec().encode(_recording('prepare-crash')),
          flush: true,
        );
        final cancellation = LocalSessionRecordingFinalizeCancellation()
          ..cancel();
        await expectLater(
          owner.finalizeNativeRecording(
            job: job,
            handoffDirectory: handoffDirectory,
            destination: destination,
            semanticEvents: const <TerminalRecordingSemanticEvent>[],
            cancellation: cancellation,
          ),
          throwsA(isA<LocalSessionRecordingFinalizeException>()),
        );

        final recoveryRepository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final recovery = await recoveryRepository.recoverNativeRecordings();

        expect(recovery.failures, isEmpty);
        expect(recovery.recoveredPaths, <String>[destination.file.path]);
        final recording = await recoveryRepository.load(destination.file.path);
        expect(
          recording.events
              .where(
                (event) =>
                    event.kind == TerminalRecordingEventKind.shellSemantic,
              )
              .single
              .semanticCommand,
          'recover-after-crash',
        );
      },
    );

    test(
      'live cross-process claim prevents recovery from harvesting the same job',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-native-process-claim',
        );
        addTearDown(() => directory.delete(recursive: true));
        final owner = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final handoffDirectory = await owner.ensureNativeHandoffDirectory();
        final destination = await owner.reserve(
          runtimeSessionId: 'process-claim',
          createdAtUtc: DateTime.utc(2026, 7, 21, 6),
        );
        final job = await owner.reserveNativeRecordingJob(
          sessionId: 'process-claim',
          handoffDirectory: handoffDirectory,
          destination: destination,
          semanticEvents: const <TerminalRecordingSemanticEvent>[],
        );
        await File(job.handoffPath).writeAsString(
          const TerminalRecordingCodec().encode(_recording('process-claim')),
          flush: true,
        );
        final cancellation = LocalSessionRecordingFinalizeCancellation()
          ..cancel();
        await expectLater(
          owner.finalizeNativeRecording(
            job: job,
            handoffDirectory: handoffDirectory,
            destination: destination,
            semanticEvents: const <TerminalRecordingSemanticEvent>[],
            cancellation: cancellation,
          ),
          throwsA(isA<LocalSessionRecordingFinalizeException>()),
        );
        final claim = File('${job.handoffPath}.claim');
        await claim.writeAsString('stable-claim', flush: true);
        final helper = _recordingHandoffLockHolder();
        final process = await Process.start(
          _standaloneDartExecutable(),
          <String>[helper.path, claim.path],
          environment: const <String, String>{'DART_VM_OPTIONS': ''},
        );
        addTearDown(process.kill);
        final locked = await process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .where((line) => line == 'locked')
            .first
            .timeout(const Duration(seconds: 5));
        expect(locked, 'locked');

        final recoveryRepository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final whileClaimed = await recoveryRepository.recoverNativeRecordings();

        expect(whileClaimed.recoveredPaths, isEmpty);
        expect(whileClaimed.pendingJobIds, contains(job.jobId));
        expect(await destination.file.exists(), isFalse);
        expect(await claim.readAsString(), 'stable-claim');

        process.stdin.writeln('release');
        await process.stdin.flush();
        await process.stdin.close();
        expect(await process.exitCode, 0);
        final afterRelease = await recoveryRepository.recoverNativeRecordings();

        expect(afterRelease.failures, isEmpty);
        expect(afterRelease.recoveredPaths, <String>[destination.file.path]);
        expect(await claim.readAsString(), 'stable-claim');
        final ownerRetry = await owner.finalizeNativeRecording(
          job: job,
          handoffDirectory: handoffDirectory,
          destination: destination,
          semanticEvents: const <TerminalRecordingSemanticEvent>[],
        );
        expect(ownerRetry, destination.file.path);
        expect(
          await File('${job.handoffPath}.manifest.json').exists(),
          isFalse,
        );
        expect(await claim.readAsString(), 'stable-claim');
      },
    );

    test(
      'another repository create never deletes an empty live directory',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-native-create-race',
        );
        addTearDown(() => directory.delete(recursive: true));
        final firstProcess = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final secondProcess = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final firstHandoff = await firstProcess.ensureNativeHandoffDirectory();

        final secondHandoff = await secondProcess
            .ensureNativeHandoffDirectory();

        expect(await firstHandoff.exists(), isTrue);
        expect(await secondHandoff.exists(), isTrue);
        expect(secondHandoff.path, isNot(firstHandoff.path));
        await _completeInterleavedHandoff(
          firstProcess,
          firstHandoff,
          sessionId: 'create-race',
          jobId: '22334455667788990011aabbccddeeff',
        );
      },
    );

    test(
      'startup recovery never deletes an empty live foreign directory',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-native-recovery-race',
        );
        addTearDown(() => directory.delete(recursive: true));
        final firstProcess = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final recoveryProcess = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final firstHandoff = await firstProcess.ensureNativeHandoffDirectory();

        final recovery = await recoveryProcess.recoverNativeRecordings();

        expect(recovery.recoveredPaths, isEmpty);
        expect(await firstHandoff.exists(), isTrue);
        await _completeInterleavedHandoff(
          firstProcess,
          firstHandoff,
          sessionId: 'recovery-race',
          jobId: '33445566778899001122aabbccddeeff',
        );
      },
    );
  });
}

String _standaloneDartExecutable() {
  var directory = File(Platform.resolvedExecutable).parent;
  for (var depth = 0; depth < 8; depth += 1) {
    final candidate = File(
      '${directory.path}${Platform.pathSeparator}dart-sdk'
      '${Platform.pathSeparator}bin${Platform.pathSeparator}dart',
    );
    if (candidate.existsSync()) {
      return candidate.path;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      break;
    }
    directory = parent;
  }
  return Platform.resolvedExecutable;
}

File _recordingHandoffLockHolder() {
  final roots = <Directory>[
    Directory.current,
    Directory('${Directory.current.path}${Platform.pathSeparator}example'),
    File.fromUri(Platform.script).parent,
  ];
  final visited = <String>{};
  for (final root in roots) {
    var directory = root.absolute;
    for (var depth = 0; depth < 12; depth += 1) {
      if (visited.add(directory.path)) {
        final helper = File(
          '${directory.path}${Platform.pathSeparator}test'
          '${Platform.pathSeparator}recording${Platform.pathSeparator}support'
          '${Platform.pathSeparator}recording_handoff_lock_holder.dart',
        );
        final packageMarker = File(
          '${directory.path}${Platform.pathSeparator}lib'
          '${Platform.pathSeparator}app.dart',
        );
        if (helper.existsSync() && packageMarker.existsSync()) {
          return helper;
        }
      }
      final parent = directory.parent;
      if (parent.path == directory.path) {
        break;
      }
      directory = parent;
    }
  }
  throw StateError('Could not resolve the example package test support path.');
}

Future<void> _completeInterleavedHandoff(
  LocalSessionRecordingRepository repository,
  Directory handoffDirectory, {
  required String sessionId,
  required String jobId,
}) async {
  final handoff = File(
    '${handoffDirectory.path}/'
    '.ianvs-recording-handoff-$jobId.ndjson',
  );
  await handoff.writeAsString(
    const TerminalRecordingCodec().encode(_recording(sessionId)),
    flush: true,
  );
  final destination = await repository.reserve(
    runtimeSessionId: sessionId,
    createdAtUtc: DateTime.utc(2026, 7, 21, 6),
  );
  final job = TerminalRecordingFinalizeJob(
    sessionId: sessionId,
    jobId: jobId,
    handoffPath: handoff.path,
    errorPath: '${handoff.path}.error.json',
  );
  await repository.registerNativeRecordingJob(
    job: job,
    handoffDirectory: handoffDirectory,
    destination: destination,
    semanticEvents: const <TerminalRecordingSemanticEvent>[],
  );
  await repository.finalizeNativeRecording(
    job: job,
    handoffDirectory: handoffDirectory,
    destination: destination,
    semanticEvents: const <TerminalRecordingSemanticEvent>[],
  );
  expect(await destination.file.exists(), isTrue);
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
