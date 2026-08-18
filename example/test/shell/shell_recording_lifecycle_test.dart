import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/local_terminal_config_repository.dart';
import 'package:app/features/layout/local_terminal_layout_models.dart';
import 'package:app/features/layout/local_terminal_layout_repository.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/recording/local_session_recording_repository.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../support/fake_pty_backend.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_profile_repository.dart';
import '../support/no_io_local_session_recording_repository.dart';

class _RecordingShellBackend extends FakePtyBackend
    implements PtySessionRequestV1Backend {
  bool observedManifestBeforePrepare = false;
  final Completer<void> recordingStarted = Completer<void>();
  int recordingStartCount = 0;
  int recordingPrepareCount = 0;

  @override
  String? requestSessionJson(String sessionId, String requestJson) {
    final request = jsonDecode(requestJson) as Map<String, Object?>;
    return switch (request['kind']) {
      'terminal.recording_start' => _startRecording(),
      'terminal.recording_stop' => jsonEncode(<String, Object?>{
        'ok': true,
        'recording_ndjson': _recordingFixture(sessionId),
      }),
      'terminal.recording_stop_prepare' => _prepareRecording(
        sessionId,
        request,
      ),
      'terminal.recording_finalize_status' => jsonEncode(
        const <String, Object?>{'ok': true, 'state': 'ready'},
      ),
      'terminal.recording_cancel' => jsonEncode(const <String, Object?>{
        'ok': true,
      }),
      _ => super.requestSessionJson(sessionId, requestJson),
    };
  }

  String _startRecording() {
    recordingStartCount += 1;
    if (!recordingStarted.isCompleted) {
      recordingStarted.complete();
    }
    return jsonEncode(<String, Object?>{
      'ok': true,
      'max_events': 4096,
      'max_payload_bytes': 8 * 1024 * 1024,
    });
  }

  String _prepareRecording(String sessionId, Map<String, Object?> request) {
    recordingPrepareCount += 1;
    final jobId = request['job_id']! as String;
    final directory = request['handoff_directory']! as String;
    final handoffPath = '$directory/.ianvs-recording-handoff-$jobId.ndjson';
    observedManifestBeforePrepare = File(
      '$handoffPath.manifest.json',
    ).existsSync();
    File(
      handoffPath,
    ).writeAsStringSync(_recordingFixture(sessionId), flush: true);
    return jsonEncode(<String, Object?>{
      'ok': true,
      'job_id': jobId,
      'handoff_path': handoffPath,
      'error_path': '$handoffPath.error.json',
    });
  }

  @override
  String? requestSessionV1Json(String sessionId, String requestV1Json) {
    final request = (jsonDecode(requestV1Json) as Map).cast<String, Object?>();
    final payload = (request['payload']! as Map).cast<String, Object?>();
    final raw = requestSessionJson(
      sessionId,
      jsonEncode(<String, Object?>{'kind': request['operation'], ...payload}),
    );
    if (raw == null) {
      return null;
    }
    return jsonEncode(<String, Object?>{
      'schema_version': 1,
      'contract': 'ianvs-session-response-v1',
      'request_id': request['request_id'],
      'session_id': sessionId,
      'operation': request['operation'],
      'ok': true,
      'timestamp_micros': 1,
      'payload': jsonDecode(raw),
    });
  }
}

class _RecordingShellConfigRepository extends LocalTerminalConfigRepository {
  @override
  Future<LocalTerminalConfigDocument?> load() async {
    return const LocalTerminalConfigDocument(
      layout: LocalTerminalLayoutConfig(restoreLayout: true),
    );
  }

  @override
  Future<void> save(LocalTerminalConfigDocument document) async {}
}

class _WidgetRecordingRepository extends LocalSessionRecordingRepository
    with NoIoLocalSessionRecordingRecovery {
  _WidgetRecordingRepository(this.directory)
    : super(directoryResolver: () async => directory);

  final Directory directory;
  int openedCount = 0;
  int nativeFinalizeCount = 0;
  final Completer<void> nativeFinalized = Completer<void>();
  static const _reservationNonce = '0123456789abcdef0123456789abcdef';
  static const _jobId = 'abcdef0123456789abcdef0123456789';

  File get _destination => File('${directory.path}/recording.ndjson');

  Directory get _handoffDirectory => Directory('${directory.path}/handoff');

  File get _manifest => File('${_job.handoffPath}.manifest.json');

  TerminalRecordingFinalizeJob get _job => TerminalRecordingFinalizeJob(
    sessionId: '1',
    jobId: _jobId,
    handoffPath:
        '${_handoffDirectory.path}/.ianvs-recording-handoff-$_jobId.ndjson',
    errorPath:
        '${_handoffDirectory.path}/.ianvs-recording-handoff-$_jobId.ndjson.error.json',
  );

  @override
  Future<LocalSessionRecordingDestination> reserve({
    required String runtimeSessionId,
    required DateTime createdAtUtc,
  }) async {
    return LocalSessionRecordingDestination(
      _destination,
      reservationNonce: _reservationNonce,
    );
  }

  @override
  bool release(LocalSessionRecordingDestination destination) => true;

  @override
  Future<Directory> ensureNativeHandoffDirectory() async {
    _handoffDirectory.createSync(recursive: true);
    return _handoffDirectory;
  }

  @override
  Future<TerminalRecordingFinalizeJob> reserveNativeRecordingJob({
    required String sessionId,
    required Directory handoffDirectory,
    required LocalSessionRecordingDestination destination,
    required List<TerminalRecordingSemanticEvent> semanticEvents,
    String? displayName,
  }) async {
    final job = TerminalRecordingFinalizeJob(
      sessionId: sessionId,
      jobId: _jobId,
      handoffPath:
          '${handoffDirectory.path}/.ianvs-recording-handoff-$_jobId.ndjson',
      errorPath:
          '${handoffDirectory.path}/.ianvs-recording-handoff-$_jobId.ndjson.error.json',
    );
    _writeManifest(
      job: job,
      destination: destination,
      phase: 'reserved',
      semanticEvents: semanticEvents,
      displayName: displayName,
    );
    return job;
  }

  @override
  void markNativeRecordingCaptureStartedSynchronously({
    required TerminalRecordingFinalizeJob job,
    required Directory handoffDirectory,
  }) {
    _updateManifest(job, phase: 'capturing');
  }

  @override
  void prepareNativeRecordingJobMetadataSynchronously({
    required TerminalRecordingFinalizeJob job,
    required Directory handoffDirectory,
    required List<TerminalRecordingSemanticEvent> semanticEvents,
    String? displayName,
  }) {
    _updateManifest(
      job,
      phase: 'preparing',
      semanticEvents: semanticEvents,
      displayName: displayName,
    );
  }

  @override
  Future<void> registerNativeRecordingJob({
    required TerminalRecordingFinalizeJob job,
    required Directory handoffDirectory,
    required LocalSessionRecordingDestination destination,
    required List<TerminalRecordingSemanticEvent> semanticEvents,
    String? displayName,
  }) async {
    if (!_manifest.existsSync()) {
      throw StateError('Current recording manifest is missing.');
    }
  }

  @override
  Future<String> finalizeNativeRecording({
    required TerminalRecordingFinalizeJob job,
    required Directory handoffDirectory,
    required LocalSessionRecordingDestination destination,
    required List<TerminalRecordingSemanticEvent> semanticEvents,
    String? displayName,
    LocalSessionRecordingFinalizeCancellation? cancellation,
    LocalSessionRecordingNativeJobStatusProbe? nativeJobStatusProbe,
  }) async {
    nativeFinalizeCount += 1;
    final source = File(job.handoffPath);
    final decoded = const TerminalRecordingCodec().decode(
      source.readAsStringSync(),
    );
    final recording = const TerminalRecordingSemanticMerger().merge(
      decoded,
      semanticEvents,
    );
    final part = File('${destination.file.path}.part');
    part.writeAsStringSync(
      const TerminalRecordingCodec().encode(recording),
      flush: true,
    );
    part.renameSync(destination.file.path);
    source.deleteSync();
    _manifest.deleteSync();
    if (!nativeFinalized.isCompleted) {
      nativeFinalized.complete();
    }
    return destination.file.path;
  }

  @override
  Future<LocalSessionOpenedRecording> openRecording(
    String recordingPath,
  ) async {
    openedCount += 1;
    final file = File(recordingPath);
    final recording = const TerminalRecordingCodec().decode(
      file.readAsStringSync(),
    );
    final stat = file.statSync();
    return LocalSessionOpenedRecording(
      entry: LocalSessionRecordingEntry(
        path: file.path,
        displayName: 'recording',
        createdAtUtc: recording.metadata.createdAtUtc,
        duration: recording.events.last.monotonicOffset,
        fileSizeBytes: stat.size,
        sessionId: recording.metadata.sessionId,
        schemaVersion: recording.metadata.schemaVersion,
        inputPolicy: recording.metadata.inputPolicy,
      ),
      recording: recording,
    );
  }

  void _updateManifest(
    TerminalRecordingFinalizeJob job, {
    required String phase,
    List<TerminalRecordingSemanticEvent>? semanticEvents,
    String? displayName,
  }) {
    final manifest = (jsonDecode(_manifest.readAsStringSync()) as Map)
        .cast<String, Object?>();
    manifest['phase'] = phase;
    if (semanticEvents != null) {
      manifest['semanticEvents'] = _semanticJson(semanticEvents);
    }
    if (displayName != null) {
      manifest['displayName'] = displayName;
    }
    _writeJsonAtomically(_manifest, manifest);
  }

  void _writeManifest({
    required TerminalRecordingFinalizeJob job,
    required LocalSessionRecordingDestination destination,
    required String phase,
    required List<TerminalRecordingSemanticEvent> semanticEvents,
    String? displayName,
  }) {
    _writeJsonAtomically(_manifest, <String, Object?>{
      'schemaVersion': 1,
      'jobId': job.jobId,
      'sessionId': job.sessionId,
      'handoffPath': job.handoffPath,
      'errorPath': job.errorPath,
      'destinationPath': destination.file.path,
      'createdAtUtc': DateTime.utc(2026, 7, 21, 6).toIso8601String(),
      'ownerPid': pid,
      'phase': phase,
      'destinationReservationNonce': destination.reservationNonce,
      'displayName': ?displayName,
      'semanticEvents': _semanticJson(semanticEvents),
    });
  }

  List<Map<String, Object?>> _semanticJson(
    List<TerminalRecordingSemanticEvent> events,
  ) {
    return events
        .map(
          (event) => <String, Object?>{
            'monotonicOffsetMicros': event.monotonicOffset.inMicroseconds,
            'kind': event.kind.name,
            if (event.command != null) 'command': event.command,
            if (event.cwd != null) 'cwd': event.cwd,
            if (event.hostname != null) 'hostname': event.hostname,
            if (event.exitCode != null) 'exitCode': event.exitCode,
            'remote': event.remote,
          },
        )
        .toList(growable: false);
  }

  void _writeJsonAtomically(File file, Map<String, Object?> value) {
    final part = File('${file.path}.part');
    part.writeAsStringSync(jsonEncode(value), flush: true);
    part.renameSync(file.path);
  }
}

class _MemoryLayoutRepository extends LocalTerminalLayoutRepository {
  TerminalLayout? layout;

  @override
  Future<TerminalLayout?> load() => Future.value(layout);

  @override
  Future<void> save(TerminalLayout layout) {
    this.layout = layout;
    return Future<void>.value();
  }
}

void main() {
  testWidgets(
    'command palette starts and stops redacted capture without a title bar action',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'ianvs terminal-recording-shell',
      );
      addTearDown(() {
        if (directory.existsSync()) {
          directory.deleteSync(recursive: true);
        }
      });
      final recordingRepository = _WidgetRecordingRepository(directory);
      final recordingBackend = _RecordingShellBackend();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ptySessionBackendProvider.overrideWithValue(recordingBackend),
            profileRepositoryProvider.overrideWithValue(
              MemoryProfileRepository(
                TerminalProfilesDocument(
                  profiles: <TerminalProfile>[defaultTerminalProfile()],
                ),
              ),
            ),
            appPreferencesRepositoryProvider.overrideWithValue(
              MemoryAppPreferencesRepository(null),
            ),
            localTerminalConfigRepositoryProvider.overrideWithValue(
              _RecordingShellConfigRepository(),
            ),
            localTerminalLayoutRepositoryProvider.overrideWithValue(
              _MemoryLayoutRepository(),
            ),
            localSessionRecordingRepositoryProvider.overrideWithValue(
              recordingRepository,
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.light(),
            darkTheme: ThemeData.dark(),
            home: const ShellScreen(),
          ),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      await _pumpUntil(
        tester,
        () =>
            find.byKey(const Key('shell-chrome-menu')).evaluate().isNotEmpty &&
            container.read(sessionControllerProvider).activeSessionId != null,
        phase: 'initial shell command palette control',
      );
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;

      expect(
        find.byKey(const Key('shell-chrome-session-recording')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('shell-chrome-menu')));
      await _pumpUntil(
        tester,
        () => find.text('Start recording for Replay').evaluate().isNotEmpty,
        phase: 'command palette open for recording start',
      );
      expect(find.text('Replay'), findsOneWidget);
      expect(find.text('Replay recent activity'), findsOneWidget);
      expect(find.text('Open recording in Replay…'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('shell-command-search-field')),
        'recording',
      );
      await tester.pump(const Duration(milliseconds: 200));
      final startRecordingAction = find.byKey(
        const Key('shell-toggle-session-recording'),
      );
      await tester.ensureVisible(startRecordingAction);
      await tester.pump();
      await tester.tap(startRecordingAction);
      await _pumpUntil(
        tester,
        () => recordingBackend.recordingStarted.isCompleted,
        phase: 'current recording start request',
      );

      expect(container.read(sessionControllerProvider).lastError, isNull);
      expect(
        container.read(sessionControllerProvider).recordingSessionIds,
        contains(sessionId),
      );
      expect(recordingBackend.recordingStartCount, 1);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('shell-chrome-menu')));
      await _pumpUntil(
        tester,
        () => find.text('Stop & save recording').evaluate().isNotEmpty,
        phase: 'command palette open',
      );
      await tester.enterText(
        find.byKey(const Key('shell-command-search-field')),
        'recording',
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Stop & save recording'), findsOneWidget);
      final recordingAction = find.byKey(
        const Key('shell-toggle-session-recording'),
      );
      await tester.ensureVisible(recordingAction);
      await tester.pump();
      await tester.tap(recordingAction);
      await _pumpUntil(
        tester,
        () => recordingRepository.nativeFinalized.isCompleted,
        phase: 'current recording finalize',
      );
      await _pumpUntil(
        tester,
        () => find.textContaining('Recording saved ·').evaluate().isNotEmpty,
        phase: 'recording saved feedback',
      );

      final recordingFiles = directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.ndjson'))
          .toList(growable: false);
      expect(recordingFiles, hasLength(1));
      final pane = container
          .read(sessionControllerProvider)
          .tabs
          .single
          .paneFor(sessionId)!;
      expect(pane.relaunchSpec!.toJson(), isNot(contains('recordingPath')));
      expect(
        container.read(sessionControllerProvider).recordingSessionIds,
        isEmpty,
      );
      expect(
        container
            .read(sessionControllerProvider)
            .recordingPendingSaveSessionIds,
        isEmpty,
      );
      expect(
        container.read(sessionControllerProvider).recordingBusySessionIds,
        isEmpty,
      );
      expect(recordingBackend.observedManifestBeforePrepare, isTrue);
      expect(recordingBackend.recordingPrepareCount, 1);
      expect(recordingRepository.nativeFinalizeCount, 1);
      expect(find.textContaining('Recording saved ·'), findsOneWidget);
      expect(find.text('Replay'), findsOneWidget);
      expect(find.text(directory.path), findsNothing);
      expect(find.text('Reveal'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 300));
      tester
          .widget<TextButton>(find.byKey(const Key('recording-saved-replay')))
          .onPressed!();
      await tester.pump(const Duration(milliseconds: 300));
      expect(recordingRepository.openedCount, 1);
      await _pumpUntil(
        tester,
        () => find
            .byKey(const Key('recording-replay-layout'))
            .evaluate()
            .isNotEmpty,
        phase: 'saved recording replay',
      );
      expect(find.text('Recording'), findsOneWidget);
      expect(
        find.byKey(const Key('replay-semantic-segment-0')),
        findsOneWidget,
      );
      expect(find.text('Activity'), findsWidgets);
    },
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  required String phase,
}) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 20));
    if (predicate()) {
      return;
    }
  }
  throw TestFailure('Timed out waiting for $phase.');
}

String _recordingFixture(String sessionId) {
  return <Map<String, Object?>>[
    <String, Object?>{
      'record_type': 'metadata',
      'schema_version': 1,
      'session_id': sessionId,
      'created_at_utc': '2026-07-21T06:00:00.000Z',
      'input_policy': 'redact',
    },
    <String, Object?>{
      'record_type': 'event',
      'schema_version': 1,
      'session_id': sessionId,
      'sequence': 0,
      'monotonic_offset_micros': 0,
      'event_kind': 'session_started',
      'payload': <String, Object?>{
        'terminal_emulation': 'xterm256',
        'cols': 80,
        'rows': 24,
      },
    },
  ].map(jsonEncode).join('\n');
}
