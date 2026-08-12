import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/features/recording/local_session_recording_repository.dart';
import 'package:cryptography/cryptography.dart';
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
          '${await supportDirectory.resolveSymbolicLinks()}'
          '${Platform.pathSeparator}ianvs_recordings',
        ).absolute.path,
      );
      expect(await recordingDirectory.exists(), isTrue);
    });

    test('native handoff canonicalizes ancestor symlink and dot-dot', () async {
      if (Platform.isWindows) {
        return;
      }
      final container = await Directory.systemTemp.createTemp(
        'ianvs terminal-recording-canonical-alias',
      );
      addTearDown(() => container.delete(recursive: true));
      final target = Directory('${container.path}/target')..createSync();
      Directory('${target.path}/child').createSync();
      final alias = Link('${container.path}/alias')..createSync(target.path);

      for (final supportPath in <String>[
        alias.path,
        '${target.path}/child/..',
      ]) {
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => Directory(supportPath),
        );
        final handoff = await repository.ensureNativeHandoffDirectory();
        final canonical = await handoff.resolveSymbolicLinks();

        expect(handoff.path, canonical);
        expect(handoff.path, startsWith(await target.resolveSymbolicLinks()));
        expect(handoff.path, isNot(contains('${Platform.pathSeparator}..')));
      }
    });

    test(
      'macOS var alias produces the native canonical job identity',
      () async {
        if (!Platform.isMacOS) {
          return;
        }
        final support = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-var-alias',
        );
        addTearDown(() => support.delete(recursive: true));
        final canonicalSupport = await support.resolveSymbolicLinks();
        if (!canonicalSupport.startsWith('/private/var/')) {
          return;
        }
        final aliasSupport =
            '/var/${canonicalSupport.substring('/private/var/'.length)}';
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => Directory(aliasSupport),
        );
        final handoff = await repository.ensureNativeHandoffDirectory();
        final destination = await repository.reserve(
          runtimeSessionId: 'var-alias',
          createdAtUtc: DateTime.utc(2026, 7, 21, 6),
        );
        final job = await repository.reserveNativeRecordingJob(
          sessionId: 'var-alias',
          handoffDirectory: Directory(
            handoff.path.replaceFirst('/private/var/', '/var/'),
          ),
          destination: destination,
          semanticEvents: const <TerminalRecordingSemanticEvent>[],
        );

        expect(job.handoffPath, startsWith('/private/var/'));
        expect(job.handoffPath, startsWith(handoff.path));
        await repository.abandonNativeRecordingJobReservation(job);
      },
    );

    test('claim aliases are mutually exclusive inside one process', () async {
      if (Platform.isWindows) {
        return;
      }
      final container = await Directory.systemTemp.createTemp(
        'ianvs terminal-recording-claim-alias',
      );
      addTearDown(() => container.delete(recursive: true));
      final support = Directory('${container.path}/support')..createSync();
      final alias = Link('${container.path}/support-alias')
        ..createSync(support.path);
      final owner = LocalSessionRecordingRepository(
        directoryResolver: () async => support,
      );
      final contender = LocalSessionRecordingRepository(
        directoryResolver: () async => Directory(alias.path),
      );
      final handoff = await owner.ensureNativeHandoffDirectory();
      final destination = await owner.reserve(
        runtimeSessionId: 'claim-alias',
        createdAtUtc: DateTime.utc(2026, 7, 21, 6),
      );
      final job = await owner.reserveNativeRecordingJob(
        sessionId: 'claim-alias',
        handoffDirectory: handoff,
        destination: destination,
        semanticEvents: const <TerminalRecordingSemanticEvent>[],
      );
      addTearDown(() => owner.abandonNativeRecordingJobReservation(job));
      final aliasHandoff = Directory(
        '${alias.path}${Platform.pathSeparator}ianvs_recordings'
        '${Platform.pathSeparator}'
        '${handoff.path.split(Platform.pathSeparator).last}',
      );
      final aliasJob = TerminalRecordingFinalizeJob(
        sessionId: job.sessionId,
        jobId: job.jobId,
        handoffPath:
            '${aliasHandoff.path}${Platform.pathSeparator}'
            '${File(job.handoffPath).uri.pathSegments.last}',
        errorPath:
            '${aliasHandoff.path}${Platform.pathSeparator}'
            '${File(job.errorPath).uri.pathSegments.last}',
      );

      await expectLater(
        contender.registerNativeRecordingJob(
          job: aliasJob,
          handoffDirectory: aliasHandoff,
          destination: destination,
          semanticEvents: const <TerminalRecordingSemanticEvent>[],
        ),
        throwsA(
          isA<LocalSessionRecordingFinalizeException>().having(
            (error) => error.failure,
            'failure',
            LocalSessionRecordingFinalizeFailure.claimedByAnotherProcess,
          ),
        ),
      );
    });

    test(
      'definitive start rejection releases the full destination ownership',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-abandon-reservation',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final contender = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final createdAtUtc = DateTime.utc(2026, 7, 21, 6);
        const sessionId = 'definitive-start-rejection';
        final destination = await repository.reserve(
          runtimeSessionId: sessionId,
          createdAtUtc: createdAtUtc,
        );
        final handoff = await repository.ensureNativeHandoffDirectory();
        final job = await repository.reserveNativeRecordingJob(
          sessionId: sessionId,
          handoffDirectory: handoff,
          destination: destination,
          semanticEvents: const <TerminalRecordingSemanticEvent>[],
        );
        final claim = File('${destination.file.path}.ianvs-reservation.lock');
        final decodedClaim =
            jsonDecode(await claim.readAsString()) as Map<String, Object?>;
        final reference = File(decodedClaim['sidecarReferencePath']! as String);
        final manifest = File('${job.handoffPath}.manifest.json');

        await repository.abandonNativeRecordingJobReservation(job);
        await repository.abandonNativeRecordingJobReservation(job);

        expect(await manifest.exists(), isFalse);
        expect(await claim.exists(), isFalse);
        expect(await reference.exists(), isFalse);
        expect(repository.release(destination), isFalse);
        final reused = await contender.reserve(
          runtimeSessionId: sessionId,
          createdAtUtc: createdAtUtc,
        );
        expect(reused.file.path, destination.file.path);
        expect(contender.release(reused), isTrue);
      },
    );

    test('handoff canonicalization failure is typed and fail closed', () async {
      final support = await Directory.systemTemp.createTemp(
        'ianvs terminal-recording-canonical-failure',
      );
      addTearDown(() => support.delete(recursive: true));
      final repository = LocalSessionRecordingRepository(
        directoryResolver: () async => support,
      );
      final destination = await repository.reserve(
        runtimeSessionId: 'canonical-failure',
        createdAtUtc: DateTime.utc(2026, 7, 21, 6),
      );

      await expectLater(
        repository.reserveNativeRecordingJob(
          sessionId: 'canonical-failure',
          handoffDirectory: Directory(
            '${support.path}/missing/'
            '.ianvs-recording-handoff-never-created',
          ),
          destination: destination,
          semanticEvents: const <TerminalRecordingSemanticEvent>[],
        ),
        throwsA(
          isA<LocalSessionRecordingFinalizeException>().having(
            (error) => error.failure,
            'failure',
            LocalSessionRecordingFinalizeFailure.invalidHandoff,
          ),
        ),
      );
    });

    test(
      'reserves collision-safe files and roundtrips current recording data',
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

    test(
      'cross-process destination claim selects a distinct deterministic path',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-destination-cross-process',
        );
        addTearDown(() => directory.delete(recursive: true));
        var lockBackoffs = 0;
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
          destinationLockRetryLimit: 2,
          destinationLockRetryDelay: Duration.zero,
          delay: (_) async {
            lockBackoffs += 1;
          },
        );
        final root = await repository.ensureRecordingDirectory();
        final createdAtUtc = DateTime.utc(2026, 7, 21, 6);
        const sessionId = 'shared-display-name';
        final sessionSegment = base64Url
            .encode(utf8.encode(sessionId))
            .replaceAll('=', '');
        final basePath =
            '${root.path}${Platform.pathSeparator}'
            '${createdAtUtc.microsecondsSinceEpoch}-$sessionSegment.ndjson';
        final claim = File('$basePath.ianvs-reservation.lock');
        final process = await Process.start(
          _standaloneDartExecutable(),
          <String>[
            _recordingDestinationReservationHolder().path,
            claim.path,
            basePath,
            sessionId,
            '0123456789abcdef0123456789abcdef',
          ],
          environment: const <String, String>{'DART_VM_OPTIONS': ''},
        );
        var released = false;
        addTearDown(() async {
          if (!released) {
            process.stdin.writeln('release');
            await process.stdin.flush();
            await process.stdin.close();
            await process.exitCode;
          }
        });
        expect(
          await process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first
              .timeout(const Duration(seconds: 5)),
          'reserved',
        );

        final destination = await repository.reserve(
          runtimeSessionId: sessionId,
          createdAtUtc: createdAtUtc,
        );

        expect(destination.file.path, isNot(basePath));
        expect(destination.file.path, endsWith('-2.ndjson'));
        expect(lockBackoffs, 1);
        repository.release(destination);
        process.stdin.writeln('release');
        await process.stdin.flush();
        await process.stdin.close();
        expect(await process.exitCode, 0);
        released = true;
      },
    );

    test(
      'busy destination registry fails after bounded injected backoff',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-destination-registry-busy',
        );
        addTearDown(() => directory.delete(recursive: true));
        var lockBackoffs = 0;
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
          destinationLockRetryLimit: 3,
          destinationLockRetryDelay: Duration.zero,
          delay: (_) async {
            lockBackoffs += 1;
          },
        );
        final root = await repository.ensureRecordingDirectory();
        final registry = File(
          '${root.path}${Platform.pathSeparator}'
          '.ianvs-destination-reservations.lock',
        );
        final process = await Process.start(
          _standaloneDartExecutable(),
          <String>[_recordingHandoffLockHolder().path, registry.path],
          environment: const <String, String>{'DART_VM_OPTIONS': ''},
        );
        var released = false;
        addTearDown(() async {
          if (!released) {
            process.stdin.writeln('release');
            await process.stdin.flush();
            await process.stdin.close();
            await process.exitCode;
          }
        });
        expect(
          await process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first
              .timeout(const Duration(seconds: 5)),
          'locked',
        );

        await expectLater(
          repository.reserve(
            runtimeSessionId: 'registry-busy',
            createdAtUtc: DateTime.utc(2026, 7, 21, 6),
          ),
          throwsA(isA<LocalSessionRecordingDestinationBusyException>()),
        );
        expect(lockBackoffs, 2);

        process.stdin.writeln('release');
        await process.stdin.flush();
        await process.stdin.close();
        expect(await process.exitCode, 0);
        released = true;
      },
    );

    test(
      'stale and double release cannot clear a live destination nonce',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-destination-stale-release',
        );
        addTearDown(() => directory.delete(recursive: true));
        final owner = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final contender = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final createdAtUtc = DateTime.utc(2026, 7, 21, 6);
        final destination = await owner.reserve(
          runtimeSessionId: 'stale-release',
          createdAtUtc: createdAtUtc,
        );
        final stale = LocalSessionRecordingDestination(
          destination.file,
          reservationNonce: destination.reservationNonce.startsWith('0')
              ? '1${destination.reservationNonce.substring(1)}'
              : '0${destination.reservationNonce.substring(1)}',
        );

        expect(owner.release(stale), isFalse);
        final whileOwned = await contender.reserve(
          runtimeSessionId: 'stale-release',
          createdAtUtc: createdAtUtc,
        );
        expect(whileOwned.file.path, isNot(destination.file.path));
        expect(contender.release(whileOwned), isTrue);
        expect(owner.release(destination), isTrue);
        expect(owner.release(destination), isFalse);

        final reentered = await contender.reserve(
          runtimeSessionId: 'stale-release',
          createdAtUtc: createdAtUtc,
        );
        expect(reentered.file.path, destination.file.path);
        expect(contender.release(reentered), isTrue);
      },
    );

    test(
      'reserve rejects a non-current claim without creating sidecars',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-reserve-unsupported-claim',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final root = await repository.ensureRecordingDirectory();
        final createdAtUtc = DateTime.utc(2026, 7, 21, 6);
        const sessionId = 'unsupported-claim-reserve';
        final sessionSegment = base64Url
            .encode(utf8.encode(sessionId))
            .replaceAll('=', '');
        final destinationPath =
            '${root.path}${Platform.pathSeparator}'
            '${createdAtUtc.microsecondsSinceEpoch}-$sessionSegment.ndjson';
        final claim = File('$destinationPath.ianvs-reservation.lock');
        final original = utf8.encode(
          '{"schemaVersion":0,"owner":"old-format"}',
        );
        await claim.writeAsBytes(original, flush: true);
        final pathsBefore = _relativeEntityPaths(root);

        await expectLater(
          repository.reserve(
            runtimeSessionId: sessionId,
            createdAtUtc: createdAtUtc,
          ),
          throwsA(
            isA<LocalSessionRecordingUnsupportedSidecarSchemaException>()
                .having((error) => error.path, 'path', claim.path)
                .having((error) => error.schemaVersion, 'schemaVersion', 0),
          ),
        );

        expect(await claim.readAsBytes(), original);
        expect(_relativeEntityPaths(root), pathsBefore);
      },
    );

    test(
      'native bind rejects a non-current claim before manifest creation',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-bind-unsupported-claim',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final destination = await repository.reserve(
          runtimeSessionId: 'unsupported-claim-bind',
          createdAtUtc: DateTime.utc(2026, 7, 21, 6),
        );
        addTearDown(() => repository.release(destination));
        final handoffDirectory = await repository
            .ensureNativeHandoffDirectory();
        final claim = File('${destination.file.path}.ianvs-reservation.lock');
        final original = utf8.encode(
          '{"schemaVersion":0,"owner":"old-format"}',
        );
        await claim.writeAsBytes(original, flush: true);
        final root = await repository.ensureRecordingDirectory();
        final pathsBefore = _relativeEntityPaths(root);

        await expectLater(
          repository.reserveNativeRecordingJob(
            sessionId: 'unsupported-claim-bind',
            handoffDirectory: handoffDirectory,
            destination: destination,
            semanticEvents: const <TerminalRecordingSemanticEvent>[],
          ),
          throwsA(
            isA<LocalSessionRecordingUnsupportedSidecarSchemaException>()
                .having((error) => error.path, 'path', claim.path)
                .having((error) => error.schemaVersion, 'schemaVersion', 0),
          ),
        );

        expect(await claim.readAsBytes(), original);
        expect(_relativeEntityPaths(root), pathsBefore);
      },
    );

    test(
      'native finalize rejects a non-current marker before any write',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-finalize-unsupported-marker',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final destination = await repository.reserve(
          runtimeSessionId: 'unsupported-marker-finalize',
          createdAtUtc: DateTime.utc(2026, 7, 21, 6),
        );
        addTearDown(() => repository.release(destination));
        final handoffDirectory = await repository
            .ensureNativeHandoffDirectory();
        final job = await repository.reserveNativeRecordingJob(
          sessionId: 'unsupported-marker-finalize',
          handoffDirectory: handoffDirectory,
          destination: destination,
          semanticEvents: const <TerminalRecordingSemanticEvent>[],
        );
        await File(job.handoffPath).writeAsString(
          const TerminalRecordingCodec().encode(
            _recording('unsupported-marker-finalize'),
          ),
          flush: true,
        );
        final marker = File('${destination.file.path}.ianvs-completed.json');
        final original = utf8.encode(
          '{"schemaVersion":0,"owner":"old-format"}',
        );
        await marker.writeAsBytes(original, flush: true);
        final root = await repository.ensureRecordingDirectory();
        final pathsBefore = _relativeEntityPaths(root);

        await expectLater(
          repository.finalizeNativeRecording(
            job: job,
            handoffDirectory: handoffDirectory,
            destination: destination,
            semanticEvents: const <TerminalRecordingSemanticEvent>[],
          ),
          throwsA(
            isA<LocalSessionRecordingUnsupportedSidecarSchemaException>()
                .having((error) => error.path, 'path', marker.path)
                .having((error) => error.schemaVersion, 'schemaVersion', 0),
          ),
        );

        expect(await marker.readAsBytes(), original);
        expect(await destination.file.exists(), isFalse);
        expect(_relativeEntityPaths(root), pathsBefore);
        await marker.delete();
        await repository.abandonNativeRecordingJobReservation(job);
      },
    );

    test(
      'native bind rejects a non-current reference without mutation',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-bind-unsupported-reference',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final destination = await repository.reserve(
          runtimeSessionId: 'unsupported-reference-bind',
          createdAtUtc: DateTime.utc(2026, 7, 21, 6),
        );
        addTearDown(() => repository.release(destination));
        final root = await repository.ensureRecordingDirectory();
        final reference = File(
          '${root.path}${Platform.pathSeparator}.ianvs-destination-sidecars'
          '${Platform.pathSeparator}buckets'
          '${Platform.pathSeparator}${destination.reservationNonce.substring(0, 2)}'
          '${Platform.pathSeparator}${destination.reservationNonce}.json',
        );
        final original = utf8.encode(
          '{"schemaVersion":0,"owner":"old-format"}',
        );
        await reference.writeAsBytes(original, flush: true);
        final handoffDirectory = await repository
            .ensureNativeHandoffDirectory();
        final pathsBefore = _relativeEntityPaths(root);

        await expectLater(
          repository.reserveNativeRecordingJob(
            sessionId: 'unsupported-reference-bind',
            handoffDirectory: handoffDirectory,
            destination: destination,
            semanticEvents: const <TerminalRecordingSemanticEvent>[],
          ),
          throwsA(
            isA<LocalSessionRecordingUnsupportedSidecarSchemaException>()
                .having((error) => error.path, 'path', reference.path)
                .having((error) => error.schemaVersion, 'schemaVersion', 0),
          ),
        );

        expect(await reference.readAsBytes(), original);
        expect(_relativeEntityPaths(root), pathsBefore);
      },
    );

    test('save never overwrites a file that appeared after reserve', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-recording-destination-appeared',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = LocalSessionRecordingRepository(
        directoryResolver: () async => directory,
      );
      final destination = await repository.reserve(
        runtimeSessionId: 'appeared-after-reserve',
        createdAtUtc: DateTime.utc(2026, 7, 21, 6),
      );
      addTearDown(() => repository.release(destination));
      await destination.file.writeAsString('unrelated sentinel', flush: true);

      await expectLater(
        repository.save(destination, _recording('appeared-after-reserve')),
        throwsA(isA<FileSystemException>()),
      );

      expect(await destination.file.readAsString(), 'unrelated sentinel');
    });

    test(
      'trash mutation holds the destination claim until move completes',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-trash-claim',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final destination = await repository.reserve(
          runtimeSessionId: 'trash-claim',
          createdAtUtc: DateTime.utc(2026, 7, 21, 6),
        );
        await repository.save(destination, _recording('trash-claim'));
        final claim = File('${destination.file.path}.ianvs-reservation.lock');

        final moved = await repository.moveRecordingToTrash(
          destination.file.path,
          (path) async {
            final probe = await _probeRecordingHandoffClaim(
              directory: directory,
              claim: claim,
              jobId: 'trash-claim',
            );
            expect(probe['pendingJobIds'], <Object?>['trash-claim']);
            await File(path).delete();
            return true;
          },
        );

        expect(moved, isTrue);
        await repository.forgetRecording(destination.file.path);
        expect(await claim.exists(), isFalse);
      },
    );

    test(
      'trash refuses an active recording reservation without releasing it',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-trash-active',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final destination = await repository.reserve(
          runtimeSessionId: 'trash-active',
          createdAtUtc: DateTime.utc(2026, 7, 21, 6),
        );
        final handoffDirectory = await repository
            .ensureNativeHandoffDirectory();
        final job = await repository.reserveNativeRecordingJob(
          sessionId: 'trash-active',
          handoffDirectory: handoffDirectory,
          destination: destination,
          semanticEvents: const <TerminalRecordingSemanticEvent>[],
        );
        var moverCalls = 0;

        await expectLater(
          repository.moveRecordingToTrash(destination.file.path, (_) async {
            moverCalls += 1;
            return true;
          }),
          throwsA(isA<LocalSessionRecordingDestinationBusyException>()),
        );

        expect(moverCalls, 0);
        final claim = File('${destination.file.path}.ianvs-reservation.lock');
        final probe = await _probeRecordingHandoffClaim(
          directory: directory,
          claim: claim,
          jobId: 'trash-active',
        );
        expect(probe['pendingJobIds'], <Object?>['trash-active']);
        await repository.abandonNativeRecordingJobReservation(job);
        expect(repository.release(destination), isFalse);
      },
    );

    test(
      'trash rejects a non-current persisted claim without moving',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-trash-unsupported-claim',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final destination = await repository.reserve(
          runtimeSessionId: 'trash-unsupported-claim',
          createdAtUtc: DateTime.utc(2026, 7, 21, 6),
        );
        await repository.save(
          destination,
          _recording('trash-unsupported-claim'),
        );
        final claim = File('${destination.file.path}.ianvs-reservation.lock');
        final original = utf8.encode(
          '{"schemaVersion":0,"owner":"old-format"}',
        );
        await claim.writeAsBytes(original, flush: true);
        final destinationBefore = await destination.file.readAsBytes();
        final root = await repository.ensureRecordingDirectory();
        final pathsBefore = _relativeEntityPaths(root);
        var moverCalls = 0;

        await expectLater(
          repository.moveRecordingToTrash(destination.file.path, (_) async {
            moverCalls += 1;
            return true;
          }),
          throwsA(
            isA<LocalSessionRecordingUnsupportedSidecarSchemaException>()
                .having((error) => error.path, 'path', claim.path)
                .having((error) => error.schemaVersion, 'schemaVersion', 0),
          ),
        );

        expect(moverCalls, 0);
        expect(await claim.readAsBytes(), original);
        expect(await destination.file.readAsBytes(), destinationBefore);
        expect(_relativeEntityPaths(root), pathsBefore);
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
      final indexFile = File('${root.path}/library.json');
      await indexFile.writeAsString('{not-json');

      final entries = await repository.listRecordings();

      expect(entries.single.sessionId, 'quarantine-runtime');
      expect(
        root.listSync().whereType<File>().where(
          (file) => file.path.contains('library.json.corrupt.'),
        ),
        hasLength(1),
      );
      final rebuilt = jsonDecode(await indexFile.readAsString()) as Map;
      expect(rebuilt['schemaVersion'], 1);
    });

    test(
      'non-current recording metadata is typed unsupported and not indexed',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-metadata-unsupported',
        );
        addTearDown(() => directory.delete(recursive: true));
        final root = Directory('${directory.path}/ianvs_recordings');
        await root.create(recursive: true);
        final recording = File('${root.path}/unsupported.ndjson');
        final original = utf8.encode(
          '${jsonEncode(<String, Object?>{'record_type': 'metadata', 'schema_version': 0, 'session_id': 'unsupported-metadata', 'created_at_utc': '2026-07-21T06:00:00.000Z', 'input_policy': 'redact'})}\n',
        );
        await recording.writeAsBytes(original, flush: true);
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final pathsBefore = _relativeEntityPaths(root);
        final canonicalRecordingPath = await recording.resolveSymbolicLinks();

        await expectLater(
          repository.listRecordings(),
          throwsA(
            isA<LocalSessionRecordingUnsupportedSchemaException>()
                .having((error) => error.path, 'path', canonicalRecordingPath)
                .having((error) => error.schemaVersion, 'schemaVersion', 0),
          ),
        );

        expect(await recording.readAsBytes(), original);
        expect(_relativeEntityPaths(root), pathsBefore);
        expect(await File('${root.path}/library.json').exists(), isFalse);
      },
    );

    test(
      'rejects an unsupported metadata index without modifying it',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-index-unsupported',
        );
        addTearDown(() => directory.delete(recursive: true));
        final root = Directory('${directory.path}/ianvs_recordings');
        await root.create(recursive: true);
        final index = File('${root.path}/library.json');
        const contents = '{"schemaVersion":0,"names":{}}';
        await index.writeAsString(contents, flush: true);
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );

        await expectLater(
          repository.listRecordings(),
          throwsA(isA<UnsupportedError>()),
        );

        expect(await index.readAsString(), contents);
        expect(
          root.listSync().whereType<File>().where(
            (file) => file.path.contains('library.json.corrupt.'),
          ),
          isEmpty,
        );
      },
    );

    test('cached error cannot hide matching-stat non-current metadata', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-recording-index-error-schema',
      );
      addTearDown(() => directory.delete(recursive: true));
      final root = Directory('${directory.path}/ianvs_recordings');
      await root.create(recursive: true);
      final recording = File('${root.path}/unsupported.ndjson').absolute;
      await recording.writeAsString(
        '${jsonEncode(<String, Object?>{'record_type': 'metadata', 'schema_version': 0, 'session_id': 'cached-error-schema', 'created_at_utc': '2026-07-21T06:00:00.000Z', 'input_policy': 'redact'})}\n',
        flush: true,
      );
      final stat = await recording.stat();
      final index = File('${root.path}/library.json');
      final forged = jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'names': <String, String>{},
        'entries': <String, Object?>{
          recording.path: <String, Object?>{
            'modifiedMicros': stat.modified.toUtc().microsecondsSinceEpoch,
            'fileSizeBytes': stat.size,
            'createdAtUtc': stat.modified.toUtc().toIso8601String(),
            'durationMicros': 0,
            'error': 'cached parse failure',
          },
        },
      });
      await index.writeAsString(forged, flush: true);
      final repository = LocalSessionRecordingRepository(
        directoryResolver: () async => directory,
      );
      final canonicalRecordingPath = await recording.resolveSymbolicLinks();

      await expectLater(
        repository.listRecordings(),
        throwsA(
          isA<LocalSessionRecordingUnsupportedSchemaException>()
              .having((error) => error.path, 'path', canonicalRecordingPath)
              .having((error) => error.schemaVersion, 'schemaVersion', 0),
        ),
      );

      expect(await index.readAsString(), forged);
    });

    test(
      'forget cleans only owned destination sidecars with bounded registry',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-sidecar-lifecycle',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        for (var index = 0; index < 3; index += 1) {
          final sessionId = 'sidecar-save-$index';
          final destination = await repository.reserve(
            runtimeSessionId: sessionId,
            createdAtUtc: DateTime.utc(2026, 7, 21, index + 1),
          );
          await repository.save(destination, _recording(sessionId));
          final reservation = File(
            '${destination.file.path}.ianvs-reservation.lock',
          );
          expect(await reservation.exists(), isTrue);
          await destination.file.delete();
          await repository.forgetRecording(destination.file.path);
          expect(await reservation.exists(), isFalse);
        }

        final handoffDirectory = await repository
            .ensureNativeHandoffDirectory();
        const jobId = '33333333333333333333333333333333';
        final handoff = File(
          '${handoffDirectory.path}/'
          '.ianvs-recording-handoff-$jobId.ndjson',
        );
        await handoff.writeAsString(
          const TerminalRecordingCodec().encode(_recording('sidecar-native')),
          flush: true,
        );
        final destination = await repository.reserve(
          runtimeSessionId: 'sidecar-native',
          createdAtUtc: DateTime.utc(2026, 7, 21, 5),
        );
        await repository.finalizeNativeRecording(
          job: TerminalRecordingFinalizeJob(
            sessionId: 'sidecar-native',
            jobId: jobId,
            handoffPath: handoff.path,
            errorPath: '${handoff.path}.error.json',
          ),
          handoffDirectory: handoffDirectory,
          destination: destination,
          semanticEvents: const <TerminalRecordingSemanticEvent>[],
        );
        final reservation = File(
          '${destination.file.path}.ianvs-reservation.lock',
        );
        final marker = File('${destination.file.path}.ianvs-completed.json');
        expect(await reservation.exists(), isTrue);
        expect(await marker.exists(), isTrue);
        await destination.file.delete();
        await repository.forgetRecording(destination.file.path);

        expect(await reservation.exists(), isFalse);
        expect(await marker.exists(), isFalse);
        final root = await repository.ensureRecordingDirectory();
        final sidecars = root
            .listSync(followLinks: false)
            .whereType<File>()
            .where(
              (file) =>
                  file.path.endsWith('.ianvs-reservation.lock') ||
                  file.path.endsWith('.ianvs-completed.json'),
            );
        expect(sidecars, isEmpty);
        expect(
          root
              .listSync(followLinks: false)
              .whereType<File>()
              .where(
                (file) =>
                    file.path.endsWith('.ianvs-destination-reservations.lock'),
              ),
          hasLength(1),
        );
      },
    );

    test(
      'forget preserves sidecars whose marker identity does not match',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-sidecar-foreign-marker',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final destination = await repository.reserve(
          runtimeSessionId: 'sidecar-foreign',
          createdAtUtc: DateTime.utc(2026, 7, 21, 5),
        );
        await repository.save(destination, _recording('sidecar-foreign'));
        final reservation = File(
          '${destination.file.path}.ianvs-reservation.lock',
        );
        final marker = File('${destination.file.path}.ianvs-completed.json');
        await marker.writeAsString(
          jsonEncode(<String, Object?>{
            'schemaVersion': 1,
            'jobId': '44444444444444444444444444444444',
            'sessionId': 'another-session',
            'destinationPath': destination.file.path,
            'destinationReservationNonce': '55555555555555555555555555555555',
            'byteLength': 0,
            'sha256': List<String>.filled(64, '0').join(),
          }),
          flush: true,
        );
        await destination.file.delete();

        await expectLater(
          repository.forgetRecording(destination.file.path),
          throwsA(isA<FileSystemException>()),
        );

        expect(await reservation.exists(), isTrue);
        expect(await marker.exists(), isTrue);
      },
    );

    test(
      'forget rejects a non-current marker without deleting sidecars',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-forget-unsupported-marker',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final destination = await repository.reserve(
          runtimeSessionId: 'forget-unsupported-marker',
          createdAtUtc: DateTime.utc(2026, 7, 21, 5),
        );
        await repository.save(
          destination,
          _recording('forget-unsupported-marker'),
        );
        await destination.file.delete();
        final claim = File('${destination.file.path}.ianvs-reservation.lock');
        final marker = File('${destination.file.path}.ianvs-completed.json');
        final markerBytes = utf8.encode(
          '{"schemaVersion":0,"owner":"old-format"}',
        );
        await marker.writeAsBytes(markerBytes, flush: true);
        final claimBefore = await claim.readAsBytes();
        final root = await repository.ensureRecordingDirectory();
        final pathsBefore = _relativeEntityPaths(root);

        await expectLater(
          repository.forgetRecording(destination.file.path),
          throwsA(
            isA<LocalSessionRecordingUnsupportedSidecarSchemaException>()
                .having((error) => error.path, 'path', marker.path)
                .having((error) => error.schemaVersion, 'schemaVersion', 0),
          ),
        );

        expect(await marker.readAsBytes(), markerBytes);
        expect(await claim.readAsBytes(), claimBefore);
        expect(_relativeEntityPaths(root), pathsBefore);
      },
    );

    test(
      'cleanup rechecks destination absence while both claims are held',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-sidecar-cleanup-barrier',
        );
        addTearDown(() => directory.delete(recursive: true));
        final cleanupEntered = Completer<void>();
        final allowCleanup = Completer<void>();
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
          destinationCleanupBarrier: (_) async {
            cleanupEntered.complete();
            await allowCleanup.future;
          },
        );
        final destination = await repository.reserve(
          runtimeSessionId: 'cleanup-barrier',
          createdAtUtc: DateTime.utc(2026, 7, 21, 5),
        );
        await repository.save(destination, _recording('cleanup-barrier'));
        final reservation = File(
          '${destination.file.path}.ianvs-reservation.lock',
        );
        final reservationBefore = await reservation.readAsBytes();
        await destination.file.delete();

        final cleanup = repository.forgetRecording(destination.file.path);
        await cleanupEntered.future;
        await destination.file.writeAsString(
          const TerminalRecordingCodec().encode(_recording('cleanup-barrier')),
          flush: true,
        );
        allowCleanup.complete();
        await cleanup;

        expect(await destination.file.exists(), isTrue);
        expect(await reservation.readAsBytes(), reservationBefore);
      },
    );

    test(
      'cleanup reports busy after bounded claim backoff and can retry',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-sidecar-cleanup-busy',
        );
        addTearDown(() => directory.delete(recursive: true));
        var lockBackoffs = 0;
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
          destinationLockRetryLimit: 2,
          destinationLockRetryDelay: Duration.zero,
          delay: (_) async {
            lockBackoffs += 1;
          },
        );
        final destination = await repository.reserve(
          runtimeSessionId: 'cleanup-busy',
          createdAtUtc: DateTime.utc(2026, 7, 21, 5),
        );
        await repository.save(destination, _recording('cleanup-busy'));
        await destination.file.delete();
        final claim = File('${destination.file.path}.ianvs-reservation.lock');
        final process = await Process.start(
          _standaloneDartExecutable(),
          <String>[_recordingHandoffLockHolder().path, claim.path],
          environment: const <String, String>{'DART_VM_OPTIONS': ''},
        );
        var released = false;
        addTearDown(() async {
          if (!released) {
            process.stdin.writeln('release');
            await process.stdin.flush();
            await process.stdin.close();
            await process.exitCode;
          }
        });
        expect(
          await process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first
              .timeout(const Duration(seconds: 5)),
          'locked',
        );

        await expectLater(
          repository.forgetRecording(destination.file.path),
          throwsA(isA<LocalSessionRecordingDestinationBusyException>()),
        );
        expect(lockBackoffs, 1);
        expect(await claim.exists(), isTrue);

        process.stdin.writeln('release');
        await process.stdin.flush();
        await process.stdin.close();
        expect(await process.exitCode, 0);
        released = true;
        await repository.forgetRecording(destination.file.path);
        expect(await claim.exists(), isFalse);
      },
    );

    test('orphan sidecar GC is batched and persists its cursor', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-recording-sidecar-gc-batch',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = LocalSessionRecordingRepository(
        directoryResolver: () async => directory,
      );
      final root = await repository.ensureRecordingDirectory();
      final claims = <File>[];
      for (var index = 0; index < 40; index += 1) {
        final destination = await repository.reserve(
          runtimeSessionId: 'orphan-$index',
          createdAtUtc: DateTime.utc(
            2026,
            7,
            21,
          ).add(Duration(microseconds: index)),
        );
        claims.add(File('${destination.file.path}.ianvs-reservation.lock'));
        expect(repository.release(destination), isTrue);
      }
      final indexRoot = Directory(
        '${root.path}${Platform.pathSeparator}'
        '.ianvs-destination-sidecars',
      );
      for (var index = 0; index < 1000; index += 1) {
        await File(
          '${indexRoot.path}${Platform.pathSeparator}'
          'unrelated-${index.toString().padLeft(4, '0')}',
        ).writeAsString('unrelated');
      }

      final cursor = File(
        '${indexRoot.path}${Platform.pathSeparator}cursor.json',
      );
      for (var pass = 0; pass < 256; pass += 1) {
        await repository.listRecordings();
        expect(
          repository.destinationSidecarReferencesInspectedForTesting,
          lessThanOrEqualTo(32),
        );
      }

      expect(claims.where((claim) => claim.existsSync()), isEmpty);
      expect(await cursor.exists(), isTrue);
      expect((jsonDecode(await cursor.readAsString()) as Map)['bucket'], 0);
    });

    test(
      'GC bounded bucket processes all 32 entries before advancing',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-sidecar-gc-leaf-continuation',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final root = await repository.ensureRecordingDirectory();
        final indexRoot = Directory(
          '${root.path}${Platform.pathSeparator}.ianvs-destination-sidecars',
        );
        final bucket = Directory(
          '${indexRoot.path}${Platform.pathSeparator}buckets'
          '${Platform.pathSeparator}aa',
        );
        await bucket.create(recursive: true);
        final cursor = File(
          '${indexRoot.path}${Platform.pathSeparator}cursor.json',
        );
        await File(
          '${indexRoot.path}${Platform.pathSeparator}.gc.lock',
        ).writeAsString('', flush: true);
        await cursor.writeAsString(
          '{"schemaVersion":1,"bucket":170,"quarantineSerial":0}',
          flush: true,
        );
        for (var index = 0; index < 32; index += 1) {
          final nonce =
              'aa${index.toRadixString(16).padLeft(2, '0')}'
              '${List<String>.filled(28, '0').join()}';
          final destination = File('${root.path}/live-$index.ndjson');
          await destination.writeAsString(
            const TerminalRecordingCodec().encode(_recording('live-gc-$index')),
            flush: true,
          );
          await _writeCurrentDestinationSidecars(
            destination: destination,
            nonce: nonce,
            sessionId: 'live-gc-$index',
          );
        }

        await repository.listRecordings();
        expect(repository.destinationSidecarReferencesInspectedForTesting, 32);
        final cursorAfterFirst = jsonDecode(await cursor.readAsString()) as Map;
        expect(cursorAfterFirst['bucket'], 171);

        const orphanNonce = 'abff0000000000000000000000000000';
        final orphanDestination = File(
          '${root.path}/orphan-next-bucket.ndjson',
        );
        final orphanSidecars = await _writeCurrentDestinationSidecars(
          destination: orphanDestination,
          nonce: orphanNonce,
          sessionId: 'orphan-next-bucket',
        );

        await repository.listRecordings();

        expect(
          repository.destinationSidecarReferencesInspectedForTesting,
          lessThanOrEqualTo(32),
        );
        expect(await orphanSidecars.claim.exists(), isFalse);
        expect(await orphanSidecars.reference.exists(), isFalse);
      },
    );

    test(
      'non-current GC cursor is typed unsupported and never rewritten',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-sidecar-cursor-unsupported',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final root = await repository.ensureRecordingDirectory();
        final indexRoot = Directory(
          '${root.path}${Platform.pathSeparator}'
          '.ianvs-destination-sidecars',
        );
        await indexRoot.create(recursive: true);
        final cursor = File(
          '${indexRoot.path}${Platform.pathSeparator}cursor.json',
        );
        final original = utf8.encode(
          '{"schemaVersion":0,"shard":17,"quarantineSerial":9}',
        );
        await cursor.writeAsBytes(original, flush: true);
        final pathsBefore = _relativeEntityPaths(root);

        await expectLater(
          repository.recoverNativeRecordings(),
          throwsA(
            isA<LocalSessionRecordingUnsupportedSidecarSchemaException>()
                .having((error) => error.path, 'path', cursor.path)
                .having((error) => error.schemaVersion, 'schemaVersion', 0),
          ),
        );

        expect(await cursor.readAsBytes(), original);
        expect(_relativeEntityPaths(root), pathsBefore);
      },
    );

    test(
      'non-current GC reference is typed unsupported and never quarantined',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-sidecar-reference-unsupported',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final destination = await repository.reserve(
          runtimeSessionId: 'unsupported-reference',
          createdAtUtc: DateTime.utc(2026, 7, 21, 5),
        );
        expect(repository.release(destination), isTrue);
        final root = await repository.ensureRecordingDirectory();
        final indexRoot = Directory(
          '${root.path}${Platform.pathSeparator}'
          '.ianvs-destination-sidecars',
        );
        final reference = File(
          '${indexRoot.path}${Platform.pathSeparator}'
          'buckets${Platform.pathSeparator}'
          '${destination.reservationNonce.substring(0, 2)}'
          '${Platform.pathSeparator}${destination.reservationNonce}.json',
        );
        final original = utf8.encode(
          jsonEncode(<String, Object?>{
            'schemaVersion': 0,
            'destinationPath': destination.file.path,
            'sessionId': 'unsupported-reference',
            'nonce': destination.reservationNonce,
          }),
        );
        await reference.writeAsBytes(original, flush: true);
        final cursor = File(
          '${indexRoot.path}${Platform.pathSeparator}cursor.json',
        );
        await cursor.writeAsString(
          jsonEncode(<String, Object?>{
            'schemaVersion': 1,
            'bucket': int.parse(
              destination.reservationNonce.substring(0, 2),
              radix: 16,
            ),
            'quarantineSerial': 0,
          }),
          flush: true,
        );
        final cursorBefore = await cursor.readAsBytes();
        final claim = File('${destination.file.path}.ianvs-reservation.lock');
        final claimBefore = await claim.readAsBytes();
        final pathsBefore = _relativeEntityPaths(root);

        await expectLater(
          repository.recoverNativeRecordings(),
          throwsA(
            isA<LocalSessionRecordingUnsupportedSidecarSchemaException>()
                .having((error) => error.path, 'path', reference.path)
                .having((error) => error.schemaVersion, 'schemaVersion', 0),
          ),
        );

        expect(await reference.readAsBytes(), original);
        expect(await cursor.readAsBytes(), cursorBefore);
        expect(await claim.readAsBytes(), claimBefore);
        expect(_relativeEntityPaths(root), pathsBefore);
      },
    );

    test(
      'non-current GC claim is typed unsupported and never quarantined',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-sidecar-claim-unsupported',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final destination = await repository.reserve(
          runtimeSessionId: 'unsupported-claim',
          createdAtUtc: DateTime.utc(2026, 7, 21, 5),
        );
        expect(repository.release(destination), isTrue);
        final root = await repository.ensureRecordingDirectory();
        final indexRoot = Directory(
          '${root.path}${Platform.pathSeparator}'
          '.ianvs-destination-sidecars',
        );
        final reference = File(
          '${indexRoot.path}${Platform.pathSeparator}'
          'buckets${Platform.pathSeparator}'
          '${destination.reservationNonce.substring(0, 2)}'
          '${Platform.pathSeparator}${destination.reservationNonce}.json',
        );
        final referenceBefore = await reference.readAsBytes();
        final claim = File('${destination.file.path}.ianvs-reservation.lock');
        final original = utf8.encode(
          jsonEncode(<String, Object?>{
            'schemaVersion': 0,
            'destinationPath': destination.file.path,
            'sessionId': 'unsupported-claim',
            'nonce': destination.reservationNonce,
          }),
        );
        await claim.writeAsBytes(original, flush: true);
        final cursor = File(
          '${indexRoot.path}${Platform.pathSeparator}cursor.json',
        );
        await cursor.writeAsString(
          jsonEncode(<String, Object?>{
            'schemaVersion': 1,
            'bucket': int.parse(
              destination.reservationNonce.substring(0, 2),
              radix: 16,
            ),
            'quarantineSerial': 0,
          }),
          flush: true,
        );
        final cursorBefore = await cursor.readAsBytes();
        final pathsBefore = _relativeEntityPaths(root);

        await expectLater(
          repository.listRecordings(),
          throwsA(
            isA<LocalSessionRecordingUnsupportedSidecarSchemaException>()
                .having((error) => error.path, 'path', claim.path)
                .having((error) => error.schemaVersion, 'schemaVersion', 0),
          ),
        );

        expect(await claim.readAsBytes(), original);
        expect(await reference.readAsBytes(), referenceBefore);
        expect(await cursor.readAsBytes(), cursorBefore);
        expect(_relativeEntityPaths(root), pathsBefore);
      },
    );

    test(
      'malformed claim with non-current marker is never quarantined',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-sidecar-marker-unsupported',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final destination = await repository.reserve(
          runtimeSessionId: 'unsupported-marker-gc',
          createdAtUtc: DateTime.utc(2026, 7, 21, 5),
        );
        expect(repository.release(destination), isTrue);
        final root = await repository.ensureRecordingDirectory();
        final claim = File('${destination.file.path}.ianvs-reservation.lock');
        const malformedClaim = '{partial-current';
        await claim.writeAsString(malformedClaim, flush: true);
        final marker = File('${destination.file.path}.ianvs-completed.json');
        const markerContents = '{"schemaVersion":0,"owner":"old-format"}';
        await marker.writeAsString(markerContents, flush: true);
        final indexRoot = Directory(
          '${root.path}${Platform.pathSeparator}.ianvs-destination-sidecars',
        );
        final cursor = File(
          '${indexRoot.path}${Platform.pathSeparator}cursor.json',
        );
        await cursor.writeAsString(
          jsonEncode(<String, Object?>{
            'schemaVersion': 1,
            'bucket': int.parse(
              destination.reservationNonce.substring(0, 2),
              radix: 16,
            ),
            'quarantineSerial': 0,
          }),
          flush: true,
        );
        final pathsBefore = _relativeEntityPaths(root);

        await expectLater(
          repository.listRecordings(),
          throwsA(
            isA<LocalSessionRecordingUnsupportedSidecarSchemaException>()
                .having((error) => error.path, 'path', marker.path)
                .having((error) => error.schemaVersion, 'schemaVersion', 0),
          ),
        );

        expect(await claim.readAsString(), malformedClaim);
        expect(await marker.readAsString(), markerContents);
        expect(_relativeEntityPaths(root), pathsBefore);
      },
    );

    test(
      'GC rejects a non-current sidecar injected after preflight without mutation',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-sidecar-prelock-race',
        );
        addTearDown(() => directory.delete(recursive: true));
        Map<String, Map<String, Object?>>? injectedSnapshot;
        late final File injectedCursor;
        var barrierCalls = 0;
        late final LocalSessionRecordingRepository repository;
        repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
          destinationGcPreLockBarrier: (indexRoot) async {
            barrierCalls += 1;
            await injectedCursor.writeAsString(
              '{"schemaVersion":0,"owner":"concurrent-old-format"}',
              flush: true,
            );
            injectedSnapshot = _recordingTreeSnapshot(
              await repository.ensureRecordingDirectory(),
            );
          },
        );
        final destination = await repository.reserve(
          runtimeSessionId: 'gc-prelock-race',
          createdAtUtc: DateTime.utc(2026, 7, 21, 5),
        );
        final root = await repository.ensureRecordingDirectory();
        injectedCursor = File(
          '${root.path}${Platform.pathSeparator}.ianvs-destination-sidecars'
          '${Platform.pathSeparator}cursor.json',
        );

        await expectLater(
          repository.listRecordings(),
          throwsA(
            isA<LocalSessionRecordingUnsupportedSidecarSchemaException>()
                .having((error) => error.path, 'path', injectedCursor.path)
                .having((error) => error.schemaVersion, 'schemaVersion', 0),
          ),
        );

        expect(barrierCalls, 1);
        expect(injectedSnapshot, isNotNull);
        expect(_recordingTreeSnapshot(root), injectedSnapshot);
        await injectedCursor.delete();
        expect(repository.release(destination), isTrue);
      },
    );

    test(
      'quarantine slot wrap never overwrites non-current metadata',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-sidecar-slot-unsupported',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final root = await repository.ensureRecordingDirectory();
        final indexRoot = Directory(
          '${root.path}${Platform.pathSeparator}.ianvs-destination-sidecars',
        );
        const nonce = 'bb000000000000000000000000000000';
        final reference = File(
          '${indexRoot.path}${Platform.pathSeparator}bb'
          '${Platform.pathSeparator}$nonce.json',
        );
        await reference.parent.create(recursive: true);
        const malformedReference = '{partial-current';
        await reference.writeAsString(malformedReference, flush: true);
        final quarantine = Directory(
          '${indexRoot.path}${Platform.pathSeparator}quarantine',
        );
        await quarantine.create(recursive: true);
        final slot = File('${quarantine.path}/slot-00.reference.json');
        const slotContents = '{"schemaVersion":0,"owner":"old-format"}';
        await slot.writeAsString(slotContents, flush: true);
        final cursor = File('${indexRoot.path}/cursor.json');
        await cursor.writeAsString(
          '{"schemaVersion":1,"shard":187,"quarantineSerial":0}',
          flush: true,
        );
        final pathsBefore = _relativeEntityPaths(root);

        await expectLater(
          repository.listRecordings(),
          throwsA(
            isA<LocalSessionRecordingUnsupportedSidecarSchemaException>()
                .having((error) => error.path, 'path', slot.path)
                .having((error) => error.schemaVersion, 'schemaVersion', 0),
          ),
        );

        expect(await reference.readAsString(), malformedReference);
        expect(await slot.readAsString(), slotContents);
        expect(_relativeEntityPaths(root), pathsBefore);
      },
    );

    test(
      'quarantine expiry preflights every entry before deleting any',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-sidecar-expiry-unsupported',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
          now: () => DateTime.utc(2026, 8, 12),
        );
        final root = await repository.ensureRecordingDirectory();
        final indexRoot = Directory(
          '${root.path}${Platform.pathSeparator}.ianvs-destination-sidecars',
        );
        final quarantine = Directory(
          '${indexRoot.path}${Platform.pathSeparator}quarantine',
        );
        await quarantine.create(recursive: true);
        final current = File('${quarantine.path}/slot-00.reference.json');
        final unsupported = File('${quarantine.path}/slot-01.reference.json');
        const currentContents = '{"schemaVersion":1,"partial":true}';
        const unsupportedContents = '{"schemaVersion":0,"owner":"old-format"}';
        await current.writeAsString(currentContents, flush: true);
        await unsupported.writeAsString(unsupportedContents, flush: true);
        final expiredAt = DateTime.utc(2026, 7, 1);
        await current.setLastModified(expiredAt);
        await unsupported.setLastModified(expiredAt);
        final cursor = File('${indexRoot.path}/cursor.json');
        await cursor.writeAsString(
          '{"schemaVersion":1,"shard":0,"quarantineSerial":2}',
          flush: true,
        );
        final pathsBefore = _relativeEntityPaths(root);

        await expectLater(
          repository.listRecordings(),
          throwsA(
            isA<LocalSessionRecordingUnsupportedSidecarSchemaException>()
                .having((error) => error.path, 'path', unsupported.path)
                .having((error) => error.schemaVersion, 'schemaVersion', 0),
          ),
        );

        expect(await current.readAsString(), currentContents);
        expect(await unsupported.readAsString(), unsupportedContents);
        expect(_relativeEntityPaths(root), pathsBefore);
      },
    );

    test(
      'orphan sidecar GC quarantines an unlocked malformed bundle',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-sidecar-gc-malformed',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final destination = await repository.reserve(
          runtimeSessionId: 'malformed-orphan',
          createdAtUtc: DateTime.utc(2026, 7, 21, 5),
        );
        expect(repository.release(destination), isTrue);
        final claim = File('${destination.file.path}.ianvs-reservation.lock');
        await claim.writeAsString('{malformed', flush: true);
        final root = await repository.ensureRecordingDirectory();
        final indexRoot = Directory(
          '${root.path}${Platform.pathSeparator}'
          '.ianvs-destination-sidecars',
        );
        final reference = File(
          '${indexRoot.path}${Platform.pathSeparator}'
          'buckets${Platform.pathSeparator}'
          '${destination.reservationNonce.substring(0, 2)}'
          '${Platform.pathSeparator}${destination.reservationNonce}.json',
        );
        final targetShard = int.parse(
          destination.reservationNonce.substring(0, 2),
          radix: 16,
        );

        for (var pass = 0; pass <= targetShard; pass += 1) {
          await repository.listRecordings();
          expect(
            repository.destinationSidecarReferencesInspectedForTesting,
            lessThanOrEqualTo(32),
          );
        }

        expect(await claim.exists(), isFalse);
        expect(await reference.exists(), isFalse);
        final quarantine = Directory(
          '${indexRoot.path}${Platform.pathSeparator}quarantine',
        );
        expect(
          quarantine.listSync(followLinks: false).whereType<File>().length,
          lessThanOrEqualTo(96),
        );
        expect(
          quarantine
              .listSync(followLinks: false)
              .whereType<File>()
              .map((file) => file.uri.pathSegments.last),
          containsAll(<String>['slot-00.claim.lock', 'slot-00.reference.json']),
        );
      },
    );

    test('orphan sidecar GC quarantines only a stale reference', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-recording-sidecar-gc-stale-reference',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = LocalSessionRecordingRepository(
        directoryResolver: () async => directory,
      );
      final destination = await repository.reserve(
        runtimeSessionId: 'stale-reference',
        createdAtUtc: DateTime.utc(2026, 7, 21, 5),
      );
      expect(repository.release(destination), isTrue);
      const staleNonce = 'ffffffffffffffffffffffffffffffff';
      final root = await repository.ensureRecordingDirectory();
      final indexRoot = Directory(
        '${root.path}${Platform.pathSeparator}'
        '.ianvs-destination-sidecars',
      );
      final staleReference = File(
        '${indexRoot.path}${Platform.pathSeparator}buckets'
        '${Platform.pathSeparator}ff'
        '${Platform.pathSeparator}$staleNonce.json',
      );
      await staleReference.parent.create(recursive: true);
      await staleReference.writeAsString(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'destinationPath': destination.file.path,
          'sessionId': 'stale-reference',
          'nonce': staleNonce,
        }),
        flush: true,
      );
      final claim = File('${destination.file.path}.ianvs-reservation.lock');
      final claimBefore = await claim.readAsBytes();
      final process = await Process.start(
        _standaloneDartExecutable(),
        <String>[_recordingHandoffLockHolder().path, claim.path],
        environment: const <String, String>{'DART_VM_OPTIONS': ''},
      );
      var released = false;
      addTearDown(() async {
        if (!released) {
          process.stdin.writeln('release');
          await process.stdin.flush();
          await process.stdin.close();
          await process.exitCode;
        }
      });
      expect(
        await process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(seconds: 5)),
        'locked',
      );

      for (var pass = 0; pass < 256; pass += 1) {
        await repository.listRecordings();
      }

      expect(await staleReference.exists(), isFalse);
      expect(await claim.readAsBytes(), claimBefore);
      process.stdin.writeln('release');
      await process.stdin.flush();
      await process.stdin.close();
      expect(await process.exitCode, 0);
      released = true;
    });

    test('orphan sidecar GC never deletes a live foreign claim', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-recording-sidecar-gc-live',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = LocalSessionRecordingRepository(
        directoryResolver: () async => directory,
        destinationLockRetryLimit: 1,
        destinationLockRetryDelay: Duration.zero,
      );
      final destination = await repository.reserve(
        runtimeSessionId: 'live-foreign',
        createdAtUtc: DateTime.utc(2026, 7, 21, 5),
      );
      expect(repository.release(destination), isTrue);
      final claim = File('${destination.file.path}.ianvs-reservation.lock');
      final process = await Process.start(
        _standaloneDartExecutable(),
        <String>[_recordingHandoffLockHolder().path, claim.path],
        environment: const <String, String>{'DART_VM_OPTIONS': ''},
      );
      var released = false;
      addTearDown(() async {
        if (!released) {
          process.stdin.writeln('release');
          await process.stdin.flush();
          await process.stdin.close();
          await process.exitCode;
        }
      });
      expect(
        await process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(seconds: 5)),
        'locked',
      );

      final targetShard = int.parse(
        destination.reservationNonce.substring(0, 2),
        radix: 16,
      );
      for (var pass = 0; pass <= targetShard; pass += 1) {
        await repository.listRecordings();
      }
      expect(await claim.exists(), isTrue);

      process.stdin.writeln('release');
      await process.stdin.flush();
      await process.stdin.close();
      expect(await process.exitCode, 0);
      released = true;
      for (var pass = 0; pass < 256; pass += 1) {
        await repository.listRecordings();
      }
      expect(await claim.exists(), isFalse);
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
        var nativeStatusConsumeCount = 0;

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
          nativeJobStatusProbe: (_, {required consumeTerminal}) {
            expect(consumeTerminal, isTrue);
            nativeStatusConsumeCount += 1;
            return const TerminalRecordingFinalizeJobStatus(
              state: TerminalRecordingFinalizeJobState.ready,
            );
          },
        );

        expect(path, destination.file.absolute.path);
        expect(nativeStatusConsumeCount, 1);
        expect(await handoff.exists(), isFalse);
        final finalized = await repository.load(path);
        expect(
          finalized.metadata.schemaVersion,
          terminalRecordingSchemaVersion,
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

    test(
      'completion marker failure retains handoff and manifest ownership',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-native-marker-failure',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final handoffDirectory = await repository
            .ensureNativeHandoffDirectory();
        const jobId = '89abcdef0123456789abcdef01234567';
        final handoff = File(
          '${handoffDirectory.path}/'
          '.ianvs-recording-handoff-$jobId.ndjson',
        );
        await handoff.writeAsString(
          const TerminalRecordingCodec().encode(_recording('marker-failure')),
          flush: true,
        );
        final destination = await repository.reserve(
          runtimeSessionId: 'marker-failure',
          createdAtUtc: DateTime.utc(2026, 7, 21, 6),
        );
        addTearDown(() => repository.release(destination));
        final markerDirectory = Directory(
          '${destination.file.path}.ianvs-completed.json',
        );
        await markerDirectory.create();
        final job = TerminalRecordingFinalizeJob(
          sessionId: 'marker-failure',
          jobId: jobId,
          handoffPath: handoff.path,
          errorPath: '${handoff.path}.error.json',
        );

        await expectLater(
          repository.finalizeNativeRecording(
            job: job,
            handoffDirectory: handoffDirectory,
            destination: destination,
            semanticEvents: const <TerminalRecordingSemanticEvent>[],
          ),
          throwsA(isA<FileSystemException>()),
        );

        expect(await destination.file.exists(), isTrue);
        expect(await handoff.exists(), isTrue);
        expect(await File('${handoff.path}.manifest.json').exists(), isTrue);
        var trashMoverCalls = 0;
        await expectLater(
          repository.moveRecordingToTrash(destination.file.path, (_) async {
            trashMoverCalls += 1;
            return true;
          }),
          throwsA(isA<LocalSessionRecordingDestinationBusyException>()),
        );
        expect(trashMoverCalls, 0);
        final claimProbe = await _probeRecordingHandoffClaim(
          directory: directory,
          claim: File('${destination.file.path}.ianvs-reservation.lock'),
          jobId: 'marker-failure',
        );
        expect(claimProbe['pendingJobIds'], <Object?>['marker-failure']);

        await markerDirectory.delete();
        final recoveredPath = await repository.finalizeNativeRecording(
          job: job,
          handoffDirectory: handoffDirectory,
          destination: destination,
          semanticEvents: const <TerminalRecordingSemanticEvent>[],
        );

        expect(recoveredPath, destination.file.path);
        expect(await handoff.exists(), isFalse);
        expect(await File('${handoff.path}.manifest.json').exists(), isFalse);
        expect(
          (await repository.load(recoveredPath)).metadata.sessionId,
          'marker-failure',
        );
      },
    );

    test(
      'destination replacement after handoff comparison is never blessed',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-native-compare-replace',
        );
        addTearDown(() => directory.delete(recursive: true));
        var identityChecks = 0;
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
          destinationIdentityReader: (path) async {
            identityChecks += 1;
            final identity = await _fileContentIdentity(path);
            if (identityChecks == 1) {
              await File(path).writeAsString('replacement', flush: true);
            }
            return identity;
          },
        );
        final handoffDirectory = await repository
            .ensureNativeHandoffDirectory();
        const jobId = '99abcdef0123456789abcdef01234567';
        final handoff = File(
          '${handoffDirectory.path}/'
          '.ianvs-recording-handoff-$jobId.ndjson',
        );
        await handoff.writeAsString(
          const TerminalRecordingCodec().encode(_recording('compare-replace')),
          flush: true,
        );
        final destination = await repository.reserve(
          runtimeSessionId: 'compare-replace',
          createdAtUtc: DateTime.utc(2026, 7, 21, 6),
        );
        addTearDown(() => repository.release(destination));
        final job = TerminalRecordingFinalizeJob(
          sessionId: 'compare-replace',
          jobId: jobId,
          handoffPath: handoff.path,
          errorPath: '${handoff.path}.error.json',
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
              LocalSessionRecordingFinalizeFailure.invalidHandoff,
            ),
          ),
        );

        expect(identityChecks, 2);
        expect(await destination.file.readAsString(), 'replacement');
        expect(await handoff.exists(), isTrue);
        expect(await File('${handoff.path}.manifest.json').exists(), isTrue);
        expect(
          await File('${destination.file.path}.ianvs-completed.json').exists(),
          isTrue,
        );
      },
    );

    test(
      'native timeout retains its live lease until another process can recover',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-native-timeout',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
          finalizeTimeout: const Duration(milliseconds: 1),
          finalizePollInterval: const Duration(milliseconds: 20),
        );
        final handoffDirectory = await repository
            .ensureNativeHandoffDirectory();
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
        await repository.registerNativeRecordingJob(
          job: job,
          handoffDirectory: handoffDirectory,
          destination: destination,
          semanticEvents: const <TerminalRecordingSemanticEvent>[],
        );
        addTearDown(() => repository.abandonNativeRecordingJobReservation(job));

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

        final whileWorkerIsLive = await repository.recoverNativeRecordings();
        expect(whileWorkerIsLive.recoveredPaths, isEmpty);
        expect(
          whileWorkerIsLive.failures,
          isEmpty,
          reason: whileWorkerIsLive.failures
              .map((failure) => '${failure.failure}: ${failure.message}')
              .join('\n'),
        );
        expect(whileWorkerIsLive.pendingJobIds, contains(job.jobId));
        final claim = File('$handoffPath.claim');
        final processProbe = await _probeRecordingHandoffClaim(
          directory: directory,
          claim: claim,
          jobId: job.jobId,
        );
        expect(processProbe['pendingJobIds'], <Object?>[job.jobId]);

        await File(handoffPath).writeAsString(
          const TerminalRecordingCodec().encode(_recording('native-timeout')),
          flush: true,
        );
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
        process.stdin.writeln('release');
        await process.stdin.flush();
        await process.stdin.close();
        expect(await process.exitCode, 0);
        expect(repository.release(destination), isTrue);

        final recoveryRepository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final recovered = await recoveryRepository.recoverNativeRecordings();
        expect(recovered.failures, isEmpty);
        expect(recovered.pendingJobIds, isEmpty);
        expect(recovered.recoveredPaths, <String>[destination.file.path]);
        expect(await File('$handoffPath.manifest.json').exists(), isFalse);
      },
    );

    test(
      'terminal native failure releases observer lease with typed recovery',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-native-terminal-failure',
        );
        addTearDown(() => directory.delete(recursive: true));
        final firstDelayEntered = Completer<void>();
        final firstDelay = Completer<void>();
        final observerDelayEntered = Completer<void>();
        final observerDelay = Completer<void>();
        var delayCalls = 0;
        var terminalFailure = false;
        final statusConsumeRequests = <bool>[];
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
          finalizeTimeout: const Duration(microseconds: 1),
          finalizePollInterval: const Duration(milliseconds: 1),
          delay: (_) {
            delayCalls += 1;
            if (delayCalls == 1) {
              firstDelayEntered.complete();
              return firstDelay.future;
            }
            if (delayCalls == 2) {
              observerDelayEntered.complete();
              return observerDelay.future;
            }
            return Future<void>.value();
          },
        );
        final handoffDirectory = await repository
            .ensureNativeHandoffDirectory();
        final destination = await repository.reserve(
          runtimeSessionId: 'native-terminal-failure',
          createdAtUtc: DateTime.utc(2026, 7, 21, 6),
        );
        const jobId = '1234567890abcdef1234567890abcdef';
        final handoffPath =
            '${handoffDirectory.path}/'
            '.ianvs-recording-handoff-$jobId.ndjson';
        final job = TerminalRecordingFinalizeJob(
          sessionId: 'native-terminal-failure',
          jobId: jobId,
          handoffPath: handoffPath,
          errorPath: '$handoffPath.error.json',
        );
        await repository.registerNativeRecordingJob(
          job: job,
          handoffDirectory: handoffDirectory,
          destination: destination,
          semanticEvents: const <TerminalRecordingSemanticEvent>[],
        );

        final finalize = repository.finalizeNativeRecording(
          job: job,
          handoffDirectory: handoffDirectory,
          destination: destination,
          semanticEvents: const <TerminalRecordingSemanticEvent>[],
          nativeJobStatusProbe: (_, {required consumeTerminal}) {
            statusConsumeRequests.add(consumeTerminal);
            return TerminalRecordingFinalizeJobStatus(
              state: terminalFailure
                  ? TerminalRecordingFinalizeJobState.failed
                  : TerminalRecordingFinalizeJobState.running,
              errorCode: terminalFailure ? 'serialize_failed' : null,
              message: terminalFailure ? 'both markers failed' : null,
            );
          },
        );
        final finalizeExpectation = expectLater(
          finalize,
          throwsA(
            isA<LocalSessionRecordingFinalizeException>().having(
              (error) => error.failure,
              'failure',
              LocalSessionRecordingFinalizeFailure.timedOut,
            ),
          ),
        );
        await firstDelayEntered.future;
        firstDelay.complete();
        await finalizeExpectation;
        await observerDelayEntered.future;
        final settlement = repository.nativeSettlementFutureForTesting(jobId);
        expect(settlement, isNotNull);
        terminalFailure = true;
        observerDelay.complete();
        await settlement;
        expect(statusConsumeRequests, isNotEmpty);
        expect(statusConsumeRequests.last, isTrue);
        expect(statusConsumeRequests.where((consume) => consume), hasLength(1));
        expect(
          statusConsumeRequests.take(statusConsumeRequests.length - 1),
          everyElement(isFalse),
        );

        final recovery = await LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        ).recoverNativeRecordings();
        expect(recovery.pendingJobIds, isEmpty);
        expect(recovery.recoveredPaths, isEmpty);
        expect(
          recovery.failures.single.failure,
          LocalSessionRecordingFinalizeFailure.nativeTerminationUnknown,
        );
        expect(recovery.failures.single.message, contains('serialize_failed'));
        expect(await File('$handoffPath.manifest.json').exists(), isTrue);
        await repository.abandonNativeRecordingJobReservation(job);
      },
    );

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

        final job = TerminalRecordingFinalizeJob(
          sessionId: 'native-cancel',
          jobId: jobId,
          handoffPath: handoffPath,
          errorPath: '$handoffPath.error.json',
        );
        await repository.registerNativeRecordingJob(
          job: job,
          handoffDirectory: handoffDirectory,
          destination: destination,
          semanticEvents: const <TerminalRecordingSemanticEvent>[],
        );
        addTearDown(() => repository.abandonNativeRecordingJobReservation(job));
        await expectLater(
          repository.finalizeNativeRecording(
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
        expect(await destination.file.exists(), isFalse);
        final whileWorkerIsLive = await repository.recoverNativeRecordings();
        expect(whileWorkerIsLive.pendingJobIds, contains(job.jobId));
        expect(whileWorkerIsLive.failures, isEmpty);
        await repository.abandonNativeRecordingJobReservation(job);
      },
    );

    test(
      'abandon waits for a racing observer write before exact cleanup',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-observer-abandon',
        );
        addTearDown(() => directory.delete(recursive: true));
        final finalizeDelayEntered = Completer<void>();
        final releaseFinalizeDelay = Completer<void>();
        final persistenceEntered = Completer<void>();
        final releasePersistence = Completer<void>();
        var delayCalls = 0;
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
          finalizeTimeout: const Duration(milliseconds: 1),
          finalizePollInterval: const Duration(milliseconds: 1),
          delay: (_) {
            delayCalls += 1;
            if (delayCalls == 1) {
              finalizeDelayEntered.complete();
              return releaseFinalizeDelay.future;
            }
            return Future<void>.value();
          },
          settlementPersistenceBarrier: (_) async {
            persistenceEntered.complete();
            await releasePersistence.future;
          },
        );
        final handoffDirectory = await repository
            .ensureNativeHandoffDirectory();
        final destination = await repository.reserve(
          runtimeSessionId: 'observer-abandon',
          createdAtUtc: DateTime.utc(2026, 7, 21, 6),
        );
        const jobId = 'abcddcba01234567abcddcba01234567';
        final handoffPath =
            '${handoffDirectory.path}/'
            '.ianvs-recording-handoff-$jobId.ndjson';
        final job = TerminalRecordingFinalizeJob(
          sessionId: 'observer-abandon',
          jobId: jobId,
          handoffPath: handoffPath,
          errorPath: '$handoffPath.error.json',
        );
        await repository.registerNativeRecordingJob(
          job: job,
          handoffDirectory: handoffDirectory,
          destination: destination,
          semanticEvents: const <TerminalRecordingSemanticEvent>[],
        );
        final claim = File('${destination.file.path}.ianvs-reservation.lock');
        final decodedClaim =
            jsonDecode(await claim.readAsString()) as Map<String, Object?>;
        final reference = File(decodedClaim['sidecarReferencePath']! as String);
        final manifest = File('$handoffPath.manifest.json');

        final finalize = repository.finalizeNativeRecording(
          job: job,
          handoffDirectory: handoffDirectory,
          destination: destination,
          semanticEvents: const <TerminalRecordingSemanticEvent>[],
          nativeJobStatusProbe: (_, {required consumeTerminal}) {
            return const TerminalRecordingFinalizeJobStatus(
              state: TerminalRecordingFinalizeJobState.failed,
              errorCode: 'serialize_failed',
              message: 'marker write failed',
            );
          },
        );
        final finalizeExpectation = expectLater(
          finalize,
          throwsA(
            isA<LocalSessionRecordingFinalizeException>().having(
              (error) => error.failure,
              'failure',
              LocalSessionRecordingFinalizeFailure.timedOut,
            ),
          ),
        );
        await finalizeDelayEntered.future;
        releaseFinalizeDelay.complete();
        await finalizeExpectation;
        await persistenceEntered.future;
        final abandon = repository.abandonNativeRecordingJobReservation(job);
        releasePersistence.complete();

        await abandon;
        expect(await manifest.exists(), isFalse);
        expect(await claim.exists(), isFalse);
        expect(await reference.exists(), isFalse);
        expect(repository.nativeSettlementFutureForTesting(jobId), isNull);
        expect(repository.release(destination), isFalse);
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
      final cancellation = LocalSessionRecordingFinalizeCancellation()
        ..cancel();
      await expectLater(
        firstProcess.finalizeNativeRecording(
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
      expect(firstProcess.release(destination), isTrue);
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
      'recovery rejects non-current handoff schema without mutation',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-unsupported-schema',
        );
        addTearDown(() => directory.delete(recursive: true));
        final owner = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final handoffDirectory = await owner.ensureNativeHandoffDirectory();
        final destination = await owner.reserve(
          runtimeSessionId: 'unsupported-schema',
          createdAtUtc: DateTime.utc(2026, 7, 21, 6),
        );
        const jobId = 'aabbccddeeff00112233445566778899';
        final handoff = File(
          '${handoffDirectory.path}/'
          '.ianvs-recording-handoff-$jobId.ndjson',
        );
        final handoffContents = const TerminalRecordingCodec().encode(
          _recording('unsupported-schema'),
        );
        await handoff.writeAsString(handoffContents, flush: true);
        final manifest = File('${handoff.path}.manifest.json');
        final manifestContents = jsonEncode(<String, Object?>{
          'schemaVersion': 0,
          'jobId': jobId,
        });
        await manifest.writeAsString(manifestContents, flush: true);
        expect(owner.release(destination), isTrue);

        final recovery = await LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        ).recoverNativeRecordings();

        expect(recovery.recoveredPaths, isEmpty);
        expect(recovery.failures, hasLength(1));
        expect(
          recovery.failures.single.failure,
          LocalSessionRecordingFinalizeFailure.unsupportedManifestSchema,
        );
        expect(await handoff.readAsString(), handoffContents);
        expect(await manifest.readAsString(), manifestContents);
        expect(await destination.file.exists(), isFalse);
      },
    );

    test(
      'matching durable destination identity completes a missing-handoff retry',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-native-completion-identity',
        );
        addTearDown(() => directory.delete(recursive: true));
        final owner = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final handoffDirectory = await owner.ensureNativeHandoffDirectory();
        final destination = await owner.reserve(
          runtimeSessionId: 'completion-identity',
          createdAtUtc: DateTime.utc(2026, 7, 21, 6),
        );
        final job = await owner.reserveNativeRecordingJob(
          sessionId: 'completion-identity',
          handoffDirectory: handoffDirectory,
          destination: destination,
          semanticEvents: const <TerminalRecordingSemanticEvent>[],
        );
        final manifest = File('${job.handoffPath}.manifest.json');
        final manifestContents = await manifest.readAsString();
        await File(job.handoffPath).writeAsString(
          const TerminalRecordingCodec().encode(
            _recording('completion-identity'),
          ),
          flush: true,
        );
        await owner.finalizeNativeRecording(
          job: job,
          handoffDirectory: handoffDirectory,
          destination: destination,
          semanticEvents: const <TerminalRecordingSemanticEvent>[],
        );
        expect(await File(job.handoffPath).exists(), isFalse);
        await manifest.writeAsString(manifestContents, flush: true);

        final recovery = await LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        ).recoverNativeRecordings();

        expect(
          recovery.failures,
          isEmpty,
          reason: recovery.failures
              .map((failure) => '${failure.failure}: ${failure.message}')
              .join('\n'),
        );
        expect(recovery.pendingJobIds, isEmpty);
        expect(recovery.recoveredPaths, <String>[destination.file.path]);
        expect(await manifest.exists(), isFalse);
        expect(
          (await owner.load(destination.file.path)).metadata.sessionId,
          'completion-identity',
        );
      },
    );

    test(
      'current-schema recovery rejects destination dot-dot escape',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-native-current-dotdot',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final handoffDirectory = await repository
            .ensureNativeHandoffDirectory();
        final root = await repository.ensureRecordingDirectory();
        final external = File(
          '${root.path}${Platform.pathSeparator}..${Platform.pathSeparator}'
          'current-outside.ndjson',
        );
        if (await external.exists()) {
          await external.delete();
        }
        const jobId = '33445566778899001122aabbccddeeff';
        final handoff = await _writeCurrentRecoveryHandoff(
          handoffDirectory: handoffDirectory,
          jobId: jobId,
          sessionId: 'current-dotdot',
          destinationPath: external.path,
        );
        final manifest = File('${handoff.path}.manifest.json');

        final recovery = await LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        ).recoverNativeRecordings();

        expect(recovery.recoveredPaths, isEmpty);
        expect(recovery.failures, hasLength(1));
        expect(
          recovery.failures.single.failure,
          LocalSessionRecordingFinalizeFailure.invalidHandoff,
        );
        expect(await external.exists(), isFalse);
        expect(await handoff.exists(), isTrue);
        expect(await manifest.exists(), isTrue);
      },
    );

    test(
      'current-schema recovery rejects destination parent symlink outside',
      () async {
        if (Platform.isWindows) {
          return;
        }
        final container = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-native-current-parent-link',
        );
        addTearDown(() => container.delete(recursive: true));
        final support = Directory('${container.path}/support')
          ..createSync(recursive: true);
        final outside = Directory('${container.path}/outside')
          ..createSync(recursive: true);
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => support,
        );
        final handoffDirectory = await repository
            .ensureNativeHandoffDirectory();
        final root = await repository.ensureRecordingDirectory();
        final outsideLink = Link('${root.path}/outside-link');
        await outsideLink.create(outside.path);
        final external = File('${outsideLink.path}/current-outside.ndjson');
        const jobId = '44556677889900112233aabbccddeeff';
        final handoff = await _writeCurrentRecoveryHandoff(
          handoffDirectory: handoffDirectory,
          jobId: jobId,
          sessionId: 'current-parent-link',
          destinationPath: external.path,
        );
        final manifest = File('${handoff.path}.manifest.json');

        final recovery = await LocalSessionRecordingRepository(
          directoryResolver: () async => support,
        ).recoverNativeRecordings();

        expect(recovery.recoveredPaths, isEmpty);
        expect(recovery.failures, hasLength(1));
        expect(
          recovery.failures.single.failure,
          LocalSessionRecordingFinalizeFailure.invalidHandoff,
        );
        expect(await external.exists(), isFalse);
        expect(await handoff.exists(), isTrue);
        expect(await manifest.exists(), isTrue);
      },
    );

    test(
      'current-schema recovery rejects existing destination leaf symlink',
      () async {
        if (Platform.isWindows) {
          return;
        }
        final container = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-native-current-leaf-link',
        );
        addTearDown(() => container.delete(recursive: true));
        final support = Directory('${container.path}/support')
          ..createSync(recursive: true);
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => support,
        );
        final handoffDirectory = await repository
            .ensureNativeHandoffDirectory();
        final root = await repository.ensureRecordingDirectory();
        final external = File('${container.path}/outside.ndjson');
        await external.writeAsString('external sentinel', flush: true);
        final destinationLink = Link('${root.path}/completed.ndjson');
        await destinationLink.create(external.path);
        const jobId = '55667788990011223344aabbccddeeff';
        final handoff = await _writeCurrentRecoveryHandoff(
          handoffDirectory: handoffDirectory,
          jobId: jobId,
          sessionId: 'current-leaf-link',
          destinationPath: destinationLink.path,
        );
        final manifest = File('${handoff.path}.manifest.json');

        final recovery = await LocalSessionRecordingRepository(
          directoryResolver: () async => support,
        ).recoverNativeRecordings();

        expect(recovery.recoveredPaths, isEmpty);
        expect(recovery.failures, hasLength(1));
        expect(
          recovery.failures.single.failure,
          LocalSessionRecordingFinalizeFailure.invalidHandoff,
        );
        expect(await external.readAsString(), 'external sentinel');
        expect(
          await FileSystemEntity.type(destinationLink.path, followLinks: false),
          FileSystemEntityType.link,
        );
        expect(await handoff.exists(), isTrue);
        expect(await manifest.exists(), isTrue);
      },
    );

    test(
      'crafted manifest cannot overwrite or consume an unrelated recording',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-native-unrelated-destination',
        );
        addTearDown(() => directory.delete(recursive: true));
        final owner = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final unrelatedDestination = await owner.reserve(
          runtimeSessionId: 'unrelated-owner',
          createdAtUtc: DateTime.utc(2026, 7, 21, 5),
        );
        await owner.save(unrelatedDestination, _recording('unrelated-owner'));
        final originalBytes = await unrelatedDestination.file.readAsBytes();
        final handoffDirectory = await owner.ensureNativeHandoffDirectory();
        const craftedJobId = '66778899001122334455aabbccddeeff';
        final handoff = await _writeCurrentRecoveryHandoff(
          handoffDirectory: handoffDirectory,
          jobId: craftedJobId,
          sessionId: 'crafted-owner',
          destinationPath: unrelatedDestination.file.path,
        );
        final manifest = File('${handoff.path}.manifest.json');

        final recovery = await LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        ).recoverNativeRecordings();

        expect(recovery.recoveredPaths, isEmpty);
        expect(recovery.pendingJobIds, isEmpty);
        expect(recovery.failures, hasLength(1));
        expect(
          recovery.failures.single.failure,
          LocalSessionRecordingFinalizeFailure.invalidHandoff,
        );
        expect(await unrelatedDestination.file.readAsBytes(), originalBytes);
        expect(
          (await owner.load(unrelatedDestination.file.path)).metadata.sessionId,
          'unrelated-owner',
        );
        expect(await handoff.exists(), isTrue);
        expect(await manifest.exists(), isTrue);
      },
    );

    test(
      'missing handoff cannot consume a crafted unrelated destination',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-native-missing-handoff-identity',
        );
        addTearDown(() => directory.delete(recursive: true));
        final owner = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final unrelatedDestination = await owner.reserve(
          runtimeSessionId: 'missing-handoff-unrelated',
          createdAtUtc: DateTime.utc(2026, 7, 21, 5),
        );
        await owner.save(
          unrelatedDestination,
          _recording('missing-handoff-unrelated'),
        );
        final originalBytes = await unrelatedDestination.file.readAsBytes();
        final handoffDirectory = await owner.ensureNativeHandoffDirectory();
        const craftedJobId = '77889900112233445566aabbccddeeff';
        final handoff = await _writeCurrentRecoveryHandoff(
          handoffDirectory: handoffDirectory,
          jobId: craftedJobId,
          sessionId: 'missing-handoff-crafted',
          destinationPath: unrelatedDestination.file.path,
        );
        final manifest = File('${handoff.path}.manifest.json');
        await handoff.delete();

        final recovery = await LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        ).recoverNativeRecordings();

        expect(recovery.recoveredPaths, isEmpty);
        expect(recovery.failures, hasLength(1));
        expect(
          recovery.failures.single.failure,
          LocalSessionRecordingFinalizeFailure.invalidHandoff,
        );
        expect(await unrelatedDestination.file.readAsBytes(), originalBytes);
        expect(await manifest.exists(), isTrue);
      },
    );

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
        expect(recovery.pendingJobIds, isEmpty);
        expect(recovery.failures.single.jobId, job.jobId);
        expect(recovery.failures.single.message, contains('abandoned'));
        expect(await File('${job.handoffPath}.manifest.json').exists(), isTrue);
        expect(await destination.file.exists(), isFalse);
      },
    );

    test(
      'reserved intent atomically refreshes late semantic metadata',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-native-intent-refresh',
        );
        addTearDown(() => directory.delete(recursive: true));
        final repository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final handoffDirectory = await repository
            .ensureNativeHandoffDirectory();
        final destination = await repository.reserve(
          runtimeSessionId: 'intent-refresh',
          createdAtUtc: DateTime.utc(2026, 7, 21, 6),
        );
        final job = await repository.reserveNativeRecordingJob(
          sessionId: 'intent-refresh',
          handoffDirectory: handoffDirectory,
          destination: destination,
          semanticEvents: const <TerminalRecordingSemanticEvent>[],
        );
        await File(job.handoffPath).writeAsString(
          const TerminalRecordingCodec().encode(_recording('intent-refresh')),
          flush: true,
        );
        const lateSemantics = <TerminalRecordingSemanticEvent>[
          TerminalRecordingSemanticEvent(
            monotonicOffset: Duration(microseconds: 5),
            kind: TerminalRecordingSemanticKind.commandStarted,
            command: 'captured-after-start',
          ),
        ];

        await repository.registerNativeRecordingJob(
          job: job,
          handoffDirectory: handoffDirectory,
          destination: destination,
          semanticEvents: lateSemantics,
          displayName: 'Late metadata',
        );
        await repository.finalizeNativeRecording(
          job: job,
          handoffDirectory: handoffDirectory,
          destination: destination,
          semanticEvents: lateSemantics,
          displayName: 'Late metadata',
        );

        final recording = await repository.load(destination.file.path);
        expect(
          recording.events
              .where(
                (event) =>
                    event.kind == TerminalRecordingEventKind.shellSemantic,
              )
              .single
              .semanticCommand,
          'captured-after-start',
        );
        expect(
          (await repository.listRecordings()).single.displayName,
          'Late metadata',
        );
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
          semanticEvents: const <TerminalRecordingSemanticEvent>[],
        );
        const crashSemantics = <TerminalRecordingSemanticEvent>[
          TerminalRecordingSemanticEvent(
            monotonicOffset: Duration(microseconds: 5),
            kind: TerminalRecordingSemanticKind.commandStarted,
            command: 'recover-after-crash',
          ),
        ];
        owner
          ..markNativeRecordingCaptureStartedSynchronously(
            job: job,
            handoffDirectory: handoffDirectory,
          )
          ..prepareNativeRecordingJobMetadataSynchronously(
            job: job,
            handoffDirectory: handoffDirectory,
            semanticEvents: crashSemantics,
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
        expect(owner.release(destination), isTrue);

        final recoveryRepository = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final recovery = await recoveryRepository.recoverNativeRecordings();

        expect(
          recovery.failures,
          isEmpty,
          reason: recovery.failures
              .map((failure) => '${failure.failure}: ${failure.message}')
              .join('\n'),
        );
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
      'abandoned pre-start intent is diagnosed without mtime deletion',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recording-native-abandoned-start',
        );
        addTearDown(() => directory.delete(recursive: true));
        final owner = LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        );
        final handoffDirectory = await owner.ensureNativeHandoffDirectory();
        final destination = await owner.reserve(
          runtimeSessionId: 'abandoned-start',
          createdAtUtc: DateTime.utc(2026, 7, 21, 6),
        );
        final job = await owner.reserveNativeRecordingJob(
          sessionId: 'abandoned-start',
          handoffDirectory: handoffDirectory,
          destination: destination,
          semanticEvents: const <TerminalRecordingSemanticEvent>[],
        );
        final manifest = File('${job.handoffPath}.manifest.json');
        final persistedIntent = await manifest.readAsString();
        await owner.abandonNativeRecordingJobReservation(job);
        await manifest.writeAsString(persistedIntent, flush: true);

        final recovery = await LocalSessionRecordingRepository(
          directoryResolver: () async => directory,
        ).recoverNativeRecordings();

        expect(recovery.pendingJobIds, isEmpty);
        expect(recovery.recoveredPaths, isEmpty);
        expect(
          recovery.failures.single.message,
          allOf(contains('reserved'), contains('abandoned')),
        );
        expect(await manifest.exists(), isTrue);
        expect(await destination.file.exists(), isFalse);
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
        expect(owner.release(destination), isTrue);
        final afterRelease = await recoveryRepository.recoverNativeRecordings();

        expect(
          afterRelease.failures,
          isEmpty,
          reason: afterRelease.failures
              .map((failure) => '${failure.failure}: ${failure.message}')
              .join('\n'),
        );
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

Future<File> _writeCurrentRecoveryHandoff({
  required Directory handoffDirectory,
  required String jobId,
  required String sessionId,
  required String destinationPath,
}) async {
  final handoff = File(
    '${handoffDirectory.path}${Platform.pathSeparator}'
    '.ianvs-recording-handoff-$jobId.ndjson',
  );
  await handoff.writeAsString(
    const TerminalRecordingCodec().encode(_recording(sessionId)),
    flush: true,
  );
  await File('${handoff.path}.manifest.json').writeAsString(
    jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'jobId': jobId,
      'sessionId': sessionId,
      'handoffPath': handoff.path,
      'errorPath': '${handoff.path}.error.json',
      'destinationPath': destinationPath,
      'createdAtUtc': DateTime.utc(2026, 7, 21, 6).toIso8601String(),
      'ownerPid': pid,
      'phase': 'nativePrepared',
      'destinationReservationNonce': jobId,
      'semanticEvents': const <Object?>[],
    }),
    flush: true,
  );
  return handoff;
}

Future<Map<String, Object?>> _probeRecordingHandoffClaim({
  required Directory directory,
  required File claim,
  required String jobId,
}) async {
  final helper = File('${directory.path}/recording_claim_probe.dart');
  await helper.writeAsString('''
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final handle = await File(arguments[0]).open(mode: FileMode.append);
  var pending = false;
  try {
    await handle.lock(FileLock.exclusive);
  } on FileSystemException {
    pending = true;
  } finally {
    if (!pending) {
      await handle.unlock();
    }
    await handle.close();
  }
  stdout.write(jsonEncode(<String, Object?>{
    'pendingJobIds': pending ? <String>[arguments[1]] : <String>[],
  }));
}
''', flush: true);
  final result = await Process.run(
    _standaloneDartExecutable(),
    <String>[helper.path, claim.path, jobId],
    environment: const <String, String>{'DART_VM_OPTIONS': ''},
  ).timeout(const Duration(seconds: 5));
  if (result.exitCode != 0) {
    throw StateError('Recording claim probe failed: ${result.stderr}');
  }
  return (jsonDecode(result.stdout as String) as Map).map(
    (key, value) => MapEntry(key as String, value),
  );
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

File _recordingDestinationReservationHolder() {
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
          '${Platform.pathSeparator}'
          'recording_destination_reservation_holder.dart',
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
  throw StateError('Could not resolve the destination claim test helper.');
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

Future<(int, String)> _fileContentIdentity(String path) async {
  final bytes = await File(path).readAsBytes();
  final hash = await Sha256().hash(bytes);
  return (
    bytes.length,
    hash.bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
  );
}

Future<({File claim, File reference})> _writeCurrentDestinationSidecars({
  required File destination,
  required String nonce,
  required String sessionId,
}) async {
  final indexRoot = Directory(
    '${destination.parent.path}${Platform.pathSeparator}'
    '.ianvs-destination-sidecars',
  );
  final reference = File(
    '${indexRoot.path}${Platform.pathSeparator}buckets'
    '${Platform.pathSeparator}${nonce.substring(0, 2)}'
    '${Platform.pathSeparator}$nonce.json',
  );
  await reference.parent.create(recursive: true);
  await reference.writeAsString(
    jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'destinationPath': destination.path,
      'sessionId': sessionId,
      'nonce': nonce,
    }),
    flush: true,
  );
  final claim = File('${destination.path}.ianvs-reservation.lock');
  await claim.writeAsString(
    jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'destinationPath': destination.path,
      'sessionId': sessionId,
      'nonce': nonce,
      'sidecarReferencePath': reference.path,
    }),
    flush: true,
  );
  return (claim: claim, reference: reference);
}

List<String> _relativeEntityPaths(Directory root) {
  return root
      .listSync(recursive: true, followLinks: false)
      .map((entity) => entity.path.substring(root.path.length))
      .toList(growable: false)
    ..sort();
}

Map<String, Map<String, Object?>> _recordingTreeSnapshot(Directory root) {
  final entities = <FileSystemEntity>[
    root,
    ...root.listSync(recursive: true, followLinks: false),
  ]..sort((left, right) => left.path.compareTo(right.path));
  final snapshot = <String, Map<String, Object?>>{};
  for (final entity in entities) {
    final stat = entity.statSync();
    final relativePath = entity.path == root.path
        ? '.'
        : entity.path.substring(root.path.length);
    snapshot[relativePath] = <String, Object?>{
      'type': stat.type.toString(),
      'modifiedMicros': stat.modified.microsecondsSinceEpoch,
      if (entity is File) 'bytes': entity.readAsBytesSync(),
    };
  }
  return snapshot;
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
