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
import 'package:app/features/sessions/session_state.dart';
import 'package:app/platform/app_shutdown_coordinator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;

import '../support/fake_pty_backend.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_profile_repository.dart';

class _RecordingConfigRepository extends LocalTerminalConfigRepository {
  @override
  Future<LocalTerminalConfigDocument?> load() async {
    return const LocalTerminalConfigDocument(
      layout: LocalTerminalLayoutConfig(restoreLayout: true),
    );
  }

  @override
  Future<void> save(LocalTerminalConfigDocument document) async {}
}

enum _RecordingCancelBehavior {
  acknowledge,
  reject,
  terminationUnknown,
  notActive,
}

enum _RecordingStartResponseFault { none, missing, malformed, correlation }

enum _RecordingPrepareResponseFault { none, missing, malformed, correlation }

class _RecordingPtyBackend extends FakePtyBackend
    implements PtySessionRequestV1Backend {
  _RecordingPtyBackend({
    List<String>? timeline,
    this.maxEvents = 4096,
    this.prepareFailuresRemaining = 0,
    this.persistentPrepareFailure = false,
    this.cancelBehavior = _RecordingCancelBehavior.acknowledge,
    this.startResponseFault = _RecordingStartResponseFault.none,
    this.prepareResponseFault = _RecordingPrepareResponseFault.none,
    this.finalizeState = 'running',
    List<String>? finalizeStates,
    this.deferHandoffArtifact = false,
  }) : timeline = timeline ?? <String>[],
       finalizeStates = finalizeStates ?? <String>[];

  final List<String> timeline;
  final int maxEvents;
  final Map<String, String> _inputPolicies = <String, String>{};
  bool observedManifestBeforePrepare = false;
  List<Object?> observedSemanticsBeforePrepare = const <Object?>[];
  int prepareFailuresRemaining;
  final bool persistentPrepareFailure;
  _RecordingCancelBehavior cancelBehavior;
  _RecordingStartResponseFault startResponseFault;
  final _RecordingPrepareResponseFault prepareResponseFault;
  String finalizeState;
  final List<String> finalizeStates;
  final bool deferHandoffArtifact;
  String? _deferredHandoffPath;
  String? _deferredHandoffSessionId;
  int prepareAttempts = 0;

  @override
  String? requestSessionJson(String sessionId, String requestJson) {
    final request = jsonDecode(requestJson) as Map<String, Object?>;
    final kind = request['kind'];
    switch (kind) {
      case 'terminal.recording_start':
        timeline.add('start:$sessionId');
        _inputPolicies[sessionId] = request['input_policy']! as String;
        if (startResponseFault == _RecordingStartResponseFault.missing) {
          return null;
        }
        if (startResponseFault == _RecordingStartResponseFault.malformed) {
          return '{malformed';
        }
        return jsonEncode(<String, Object?>{
          'ok': true,
          'max_events': maxEvents,
          'max_payload_bytes': 8 * 1024 * 1024,
        });
      case 'terminal.recording_stop':
        timeline.add('stop:$sessionId');
        return jsonEncode(<String, Object?>{
          'ok': true,
          'recording_ndjson': _recordingFixture(
            sessionId,
            inputPolicy: _inputPolicies[sessionId] ?? 'redact',
          ),
        });
      case 'terminal.recording_stop_prepare':
        timeline.add('stop:$sessionId');
        prepareAttempts += 1;
        final jobId = request['job_id']! as String;
        final directory = request['handoff_directory']! as String;
        final handoffPath = '$directory/.ianvs-recording-handoff-$jobId.ndjson';
        observedManifestBeforePrepare = File(
          '$handoffPath.manifest.json',
        ).existsSync();
        if (observedManifestBeforePrepare) {
          final manifest =
              jsonDecode(File('$handoffPath.manifest.json').readAsStringSync())
                  as Map<String, Object?>;
          observedSemanticsBeforePrepare = List<Object?>.from(
            manifest['semanticEvents']! as List,
          );
        }
        if (persistentPrepareFailure || prepareFailuresRemaining > 0) {
          if (prepareFailuresRemaining > 0) {
            prepareFailuresRemaining -= 1;
          }
          return jsonEncode(const <String, Object?>{
            'ok': false,
            'error': <String, Object?>{
              'code': 'invalid_handoff',
              'message': 'transient handoff rejection',
            },
          });
        }
        if (deferHandoffArtifact) {
          _deferredHandoffPath = handoffPath;
          _deferredHandoffSessionId = sessionId;
        } else {
          _writeHandoffArtifact(sessionId, handoffPath);
        }
        if (prepareResponseFault == _RecordingPrepareResponseFault.missing) {
          return null;
        }
        if (prepareResponseFault == _RecordingPrepareResponseFault.malformed) {
          return '{malformed';
        }
        return jsonEncode(<String, Object?>{
          'ok': true,
          'job_id': jobId,
          'handoff_path': handoffPath,
          'error_path': '$handoffPath.error.json',
        });
      case 'terminal.recording_finalize_status':
        timeline.add('status:$sessionId');
        final currentFinalizeState = finalizeStates.isEmpty
            ? finalizeState
            : finalizeStates.removeAt(0);
        return jsonEncode(<String, Object?>{
          'ok': true,
          'state': currentFinalizeState,
          if (currentFinalizeState == 'failed')
            'error': const <String, Object?>{
              'code': 'serialize_failed',
              'message': 'native finalize failed after ownership transfer',
            },
        });
      case 'terminal.recording_cancel':
        timeline.add('cancel:$sessionId');
        return switch (cancelBehavior) {
          _RecordingCancelBehavior.acknowledge => jsonEncode(
            const <String, Object?>{'ok': true},
          ),
          _RecordingCancelBehavior.reject => jsonEncode(const <String, Object?>{
            'ok': false,
            'error': <String, Object?>{
              'code': 'native_failure',
              'message': 'native cancellation rejected',
            },
          }),
          _RecordingCancelBehavior.terminationUnknown => throw StateError(
            'native cancellation transport terminated before acknowledgment',
          ),
          _RecordingCancelBehavior.notActive => jsonEncode(
            const <String, Object?>{
              'ok': false,
              'error': <String, Object?>{
                'code': 'not_active',
                'message': 'no recording is active for this session',
              },
            },
          ),
        };
      default:
        return super.requestSessionJson(sessionId, requestJson);
    }
  }

  void publishDeferredHandoffArtifact() {
    final sessionId = _deferredHandoffSessionId;
    final handoffPath = _deferredHandoffPath;
    if (sessionId == null || handoffPath == null) {
      throw StateError('No deferred native handoff is pending.');
    }
    _writeHandoffArtifact(sessionId, handoffPath);
    _deferredHandoffSessionId = null;
    _deferredHandoffPath = null;
  }

  void _writeHandoffArtifact(String sessionId, String handoffPath) {
    File(handoffPath).writeAsStringSync(
      _recordingFixture(
        sessionId,
        inputPolicy: _inputPolicies[sessionId] ?? 'redact',
      ),
      flush: true,
    );
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
    if (raw == '{malformed') {
      return raw;
    }
    return jsonEncode(<String, Object?>{
      'schema_version': 1,
      'contract': 'ianvs-session-response-v1',
      'request_id':
          (request['operation'] == 'terminal.recording_start' &&
                  startResponseFault ==
                      _RecordingStartResponseFault.correlation) ||
              (request['operation'] == 'terminal.recording_stop_prepare' &&
                  prepareResponseFault ==
                      _RecordingPrepareResponseFault.correlation)
          ? 'wrong-correlation'
          : request['request_id'],
      'session_id': sessionId,
      'operation': request['operation'],
      'ok': true,
      'timestamp_micros': 1,
      'payload': jsonDecode(raw),
    });
  }

  @override
  void closeSession(String sessionId) {
    timeline.add('close:$sessionId');
    super.closeSession(sessionId);
  }
}

class _FailingRecordingPhaseRepository extends LocalSessionRecordingRepository {
  _FailingRecordingPhaseRepository({required super.directoryResolver});

  int abandonAttempts = 0;

  @override
  void markNativeRecordingCaptureStartedSynchronously({
    required terminal.TerminalRecordingFinalizeJob job,
    required Directory handoffDirectory,
  }) {
    throw const FileSystemException('recording phase write unavailable');
  }

  @override
  void prepareNativeRecordingJobMetadataSynchronously({
    required terminal.TerminalRecordingFinalizeJob job,
    required Directory handoffDirectory,
    required List<terminal.TerminalRecordingSemanticEvent> semanticEvents,
    String? displayName,
  }) {
    throw const FileSystemException('recording phase write unavailable');
  }

  @override
  Future<void> abandonNativeRecordingJobReservation(
    terminal.TerminalRecordingFinalizeJob job,
  ) {
    abandonAttempts += 1;
    return super.abandonNativeRecordingJobReservation(job);
  }
}

class _FailingOnceRecordingRepository extends LocalSessionRecordingRepository {
  _FailingOnceRecordingRepository({required super.directoryResolver});

  bool failNextSave = true;

  @override
  Future<String> save(
    LocalSessionRecordingDestination destination,
    terminal.TerminalRecording recording, {
    String? displayName,
  }) async {
    if (failNextSave) {
      failNextSave = false;
      throw const FileSystemException('recording disk unavailable');
    }
    return super.save(destination, recording, displayName: displayName);
  }

  @override
  Future<String> finalizeNativeRecording({
    required terminal.TerminalRecordingFinalizeJob job,
    required Directory handoffDirectory,
    required LocalSessionRecordingDestination destination,
    required List<terminal.TerminalRecordingSemanticEvent> semanticEvents,
    String? displayName,
    LocalSessionRecordingFinalizeCancellation? cancellation,
    LocalSessionRecordingNativeJobStatusProbe? nativeJobStatusProbe,
  }) async {
    if (failNextSave) {
      failNextSave = false;
      throw const FileSystemException('recording disk unavailable');
    }
    return super.finalizeNativeRecording(
      job: job,
      handoffDirectory: handoffDirectory,
      destination: destination,
      semanticEvents: semanticEvents,
      displayName: displayName,
      cancellation: cancellation,
      nativeJobStatusProbe: nativeJobStatusProbe,
    );
  }
}

class _FailSecondRecordingRepository extends LocalSessionRecordingRepository {
  _FailSecondRecordingRepository({required super.directoryResolver});

  int saveAttempts = 0;

  @override
  Future<String> save(
    LocalSessionRecordingDestination destination,
    terminal.TerminalRecording recording, {
    String? displayName,
  }) async {
    saveAttempts += 1;
    if (saveAttempts == 2) {
      throw const FileSystemException('second recording disk unavailable');
    }
    return super.save(destination, recording, displayName: displayName);
  }

  @override
  Future<String> finalizeNativeRecording({
    required terminal.TerminalRecordingFinalizeJob job,
    required Directory handoffDirectory,
    required LocalSessionRecordingDestination destination,
    required List<terminal.TerminalRecordingSemanticEvent> semanticEvents,
    String? displayName,
    LocalSessionRecordingFinalizeCancellation? cancellation,
    LocalSessionRecordingNativeJobStatusProbe? nativeJobStatusProbe,
  }) async {
    saveAttempts += 1;
    if (saveAttempts == 2) {
      throw const FileSystemException('second recording disk unavailable');
    }
    return super.finalizeNativeRecording(
      job: job,
      handoffDirectory: handoffDirectory,
      destination: destination,
      semanticEvents: semanticEvents,
      displayName: displayName,
      cancellation: cancellation,
      nativeJobStatusProbe: nativeJobStatusProbe,
    );
  }
}

class _BlockingRecordingRepository extends LocalSessionRecordingRepository {
  _BlockingRecordingRepository({required super.directoryResolver});

  final Completer<void> saveStarted = Completer<void>();
  final Completer<void> allowSave = Completer<void>();

  @override
  Future<String> save(
    LocalSessionRecordingDestination destination,
    terminal.TerminalRecording recording, {
    String? displayName,
  }) async {
    if (!saveStarted.isCompleted) {
      saveStarted.complete();
    }
    await allowSave.future;
    return super.save(destination, recording, displayName: displayName);
  }

  @override
  Future<String> finalizeNativeRecording({
    required terminal.TerminalRecordingFinalizeJob job,
    required Directory handoffDirectory,
    required LocalSessionRecordingDestination destination,
    required List<terminal.TerminalRecordingSemanticEvent> semanticEvents,
    String? displayName,
    LocalSessionRecordingFinalizeCancellation? cancellation,
    LocalSessionRecordingNativeJobStatusProbe? nativeJobStatusProbe,
  }) async {
    if (!saveStarted.isCompleted) {
      saveStarted.complete();
    }
    await allowSave.future;
    return super.finalizeNativeRecording(
      job: job,
      handoffDirectory: handoffDirectory,
      destination: destination,
      semanticEvents: semanticEvents,
      displayName: displayName,
      cancellation: cancellation,
      nativeJobStatusProbe: nativeJobStatusProbe,
    );
  }
}

class _BlockingFailingRecordingRepository
    extends LocalSessionRecordingRepository {
  _BlockingFailingRecordingRepository({required super.directoryResolver});

  final Completer<void> saveStarted = Completer<void>();
  final Completer<void> allowFailure = Completer<void>();
  final Completer<void> releaseObserved = Completer<void>();
  int releaseCount = 0;

  Future<Never> _failAfterGate() async {
    if (!saveStarted.isCompleted) {
      saveStarted.complete();
    }
    await allowFailure.future;
    throw const FileSystemException('recording finalize failed after gate');
  }

  @override
  Future<String> save(
    LocalSessionRecordingDestination destination,
    terminal.TerminalRecording recording, {
    String? displayName,
  }) {
    return _failAfterGate();
  }

  @override
  Future<String> finalizeNativeRecording({
    required terminal.TerminalRecordingFinalizeJob job,
    required Directory handoffDirectory,
    required LocalSessionRecordingDestination destination,
    required List<terminal.TerminalRecordingSemanticEvent> semanticEvents,
    String? displayName,
    LocalSessionRecordingFinalizeCancellation? cancellation,
    LocalSessionRecordingNativeJobStatusProbe? nativeJobStatusProbe,
  }) {
    return _failAfterGate();
  }

  @override
  bool release(LocalSessionRecordingDestination destination) {
    releaseCount += 1;
    if (!releaseObserved.isCompleted) {
      releaseObserved.complete();
    }
    return super.release(destination);
  }
}

class _OrderedRecordingRepository extends LocalSessionRecordingRepository {
  _OrderedRecordingRepository({
    required this.timeline,
    required super.directoryResolver,
  });

  final List<String> timeline;

  @override
  Future<String> save(
    LocalSessionRecordingDestination destination,
    terminal.TerminalRecording recording, {
    String? displayName,
  }) async {
    timeline.add('recording-save-start');
    final path = await super.save(
      destination,
      recording,
      displayName: displayName,
    );
    timeline.add('recording-save-complete');
    return path;
  }

  @override
  Future<String> finalizeNativeRecording({
    required terminal.TerminalRecordingFinalizeJob job,
    required Directory handoffDirectory,
    required LocalSessionRecordingDestination destination,
    required List<terminal.TerminalRecordingSemanticEvent> semanticEvents,
    String? displayName,
    LocalSessionRecordingFinalizeCancellation? cancellation,
    LocalSessionRecordingNativeJobStatusProbe? nativeJobStatusProbe,
  }) async {
    timeline.add('recording-save-start');
    final path = await super.finalizeNativeRecording(
      job: job,
      handoffDirectory: handoffDirectory,
      destination: destination,
      semanticEvents: semanticEvents,
      displayName: displayName,
      cancellation: cancellation,
      nativeJobStatusProbe: nativeJobStatusProbe,
    );
    timeline.add('recording-save-complete');
    return path;
  }
}

class _OrderedLayoutRepository extends LocalTerminalLayoutRepository {
  _OrderedLayoutRepository({
    required this.timeline,
    required super.directoryResolver,
  });

  final List<String> timeline;

  @override
  Future<void> save(TerminalLayout layout) async {
    timeline.add('layout-save-start');
    await super.save(layout);
    timeline.add('layout-save-complete');
  }
}

class _RecordingHarness {
  const _RecordingHarness({
    required this.container,
    required this.backend,
    required this.recordingRepository,
    required this.directory,
  });

  final ProviderContainer container;
  final _RecordingPtyBackend backend;
  final LocalSessionRecordingRepository recordingRepository;
  final Directory directory;
}

class _ControlledRecordingDelay {
  final List<Completer<void>> _gates = <Completer<void>>[];
  Completer<void> _nextEntry = Completer<void>();

  Future<void> call(Duration _) {
    final gate = Completer<void>();
    _gates.add(gate);
    if (!_nextEntry.isCompleted) {
      _nextEntry.complete();
    }
    return gate.future;
  }

  Future<void> waitForPending() async {
    if (_gates.any((gate) => !gate.isCompleted)) {
      return;
    }
    await _nextEntry.future;
  }

  void releaseNext() {
    final index = _gates.indexWhere((gate) => !gate.isCompleted);
    if (index == -1) {
      throw StateError('No recording settlement delay is pending.');
    }
    _nextEntry = Completer<void>();
    _gates[index].complete();
  }
}

Future<_RecordingHarness> _createHarness({
  LocalSessionRecordingRepository Function(Directory directory)?
  recordingRepositoryBuilder,
  LocalTerminalLayoutRepository Function(Directory directory)?
  layoutRepositoryBuilder,
  List<String>? timeline,
  int recordingMaxEvents = 4096,
  int prepareFailuresRemaining = 0,
  bool persistentPrepareFailure = false,
  _RecordingCancelBehavior cancelBehavior =
      _RecordingCancelBehavior.acknowledge,
  _RecordingStartResponseFault startResponseFault =
      _RecordingStartResponseFault.none,
  _RecordingPrepareResponseFault prepareResponseFault =
      _RecordingPrepareResponseFault.none,
  String finalizeState = 'running',
  List<String>? finalizeStates,
  bool deferHandoffArtifact = false,
  AppShutdownCoordinator? shutdownCoordinator,
}) async {
  final directory = await Directory.systemTemp.createTemp(
    'ianvs terminal-session-recording',
  );
  final backend = _RecordingPtyBackend(
    timeline: timeline,
    maxEvents: recordingMaxEvents,
    prepareFailuresRemaining: prepareFailuresRemaining,
    persistentPrepareFailure: persistentPrepareFailure,
    cancelBehavior: cancelBehavior,
    startResponseFault: startResponseFault,
    prepareResponseFault: prepareResponseFault,
    finalizeState: finalizeState,
    finalizeStates: finalizeStates,
    deferHandoffArtifact: deferHandoffArtifact,
  );
  final layoutRepository =
      layoutRepositoryBuilder?.call(directory) ??
      LocalTerminalLayoutRepository(directoryResolver: () async => directory);
  final recordingRepository =
      recordingRepositoryBuilder?.call(directory) ??
      LocalSessionRecordingRepository(directoryResolver: () async => directory);
  final container = ProviderContainer(
    overrides: [
      ptySessionBackendProvider.overrideWithValue(backend),
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
        _RecordingConfigRepository(),
      ),
      localTerminalLayoutRepositoryProvider.overrideWithValue(layoutRepository),
      localSessionRecordingRepositoryProvider.overrideWithValue(
        recordingRepository,
      ),
      if (shutdownCoordinator != null)
        appShutdownCoordinatorProvider.overrideWithValue(shutdownCoordinator),
    ],
  );
  addTearDown(() async {
    container.dispose();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });
  container.read(sessionControllerProvider.notifier);
  await Future<void>.delayed(const Duration(milliseconds: 100));
  return _RecordingHarness(
    container: container,
    backend: backend,
    recordingRepository: recordingRepository,
    directory: directory,
  );
}

void main() {
  test(
    'start and stop save redacted current data outside relaunch intent',
    () async {
      final harness = await _createHarness();
      final controller = harness.container.read(
        sessionControllerProvider.notifier,
      );
      final sessionId = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;

      expect(await controller.startSessionRecording(sessionId), isTrue);
      expect(
        harness.container.read(sessionControllerProvider).recordingSessionIds,
        contains(sessionId),
      );

      final path = await controller.stopSessionRecording(sessionId);

      expect(path, isNotNull);
      expect(File(path!).existsSync(), isTrue);
      final pane = harness.container
          .read(sessionControllerProvider)
          .tabs
          .single
          .paneFor(sessionId)!;
      expect(pane.relaunchSpec!.profileId, isNotEmpty);
      expect(pane.relaunchSpec!.toJson(), isNot(contains('recordingPath')));
      expect(
        harness.container.read(sessionControllerProvider).recordingSessionIds,
        isEmpty,
      );
      final recording = await harness.recordingRepository.load(path);
      expect(
        recording.metadata.inputPolicy,
        terminal.TerminalRecordingInputPolicy.redact,
      );
      expect(harness.backend.timeline.take(2), <String>[
        'start:$sessionId',
        'stop:$sessionId',
      ]);
      expect(harness.backend.observedManifestBeforePrepare, isTrue);
    },
  );

  for (final cancelBehavior in <_RecordingCancelBehavior>[
    _RecordingCancelBehavior.reject,
    _RecordingCancelBehavior.terminationUnknown,
  ]) {
    test('phase write failure retains native ownership when cancel is '
        '${cancelBehavior.name}', () async {
      late _FailingRecordingPhaseRepository repository;
      final harness = await _createHarness(
        cancelBehavior: cancelBehavior,
        recordingRepositoryBuilder: (directory) =>
            repository = _FailingRecordingPhaseRepository(
              directoryResolver: () async => directory,
            ),
      );
      final controller = harness.container.read(
        sessionControllerProvider.notifier,
      );
      final sessionId = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;

      expect(await controller.startSessionRecording(sessionId), isFalse);

      expect(repository.abandonAttempts, 0);
      expect(
        harness.container.read(sessionControllerProvider).recordingSessionIds,
        contains(sessionId),
      );
      expect(
        harness.container
            .read(terminalLiveRecorderProvider)
            ?.isRecording(sessionId),
        isTrue,
      );
      final manifests = harness.directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.manifest.json'))
          .toList(growable: false);
      expect(manifests, hasLength(1));
      final manifest =
          jsonDecode(manifests.single.readAsStringSync())
              as Map<String, Object?>;
      expect(manifest['phase'], 'reserved');
      final jobId = manifest['jobId']! as String;
      final recovery = await repository.recoverNativeRecordings();
      expect(recovery.pendingJobIds, contains(jobId));

      harness.backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'exit',
          sessionId: sessionId,
          payload: const <String, Object?>{'code': 9},
        ),
      );
      final runtime = harness.container.read(terminalRuntimeControllerProvider);
      runtime.refreshSession(sessionId);

      expect(runtime.hasSession(sessionId), isTrue);
      expect(harness.backend.closedSessionIds, isEmpty);
      expect(repository.abandonAttempts, 0);
      expect(manifests.single.existsSync(), isTrue);
      expect(
        harness.container.read(sessionControllerProvider).lastError,
        contains('beforeSessionCloseOnExitSignal'),
      );
    });
  }

  test(
    'phase write failure abandons intent only after cancel acknowledgment',
    () async {
      late _FailingRecordingPhaseRepository repository;
      final harness = await _createHarness(
        recordingRepositoryBuilder: (directory) =>
            repository = _FailingRecordingPhaseRepository(
              directoryResolver: () async => directory,
            ),
      );
      final controller = harness.container.read(
        sessionControllerProvider.notifier,
      );
      final sessionId = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;

      expect(await controller.startSessionRecording(sessionId), isFalse);

      expect(repository.abandonAttempts, 1);
      expect(
        harness.container
            .read(terminalLiveRecorderProvider)
            ?.isRecording(sessionId),
        isFalse,
      );
      expect(
        harness.container.read(sessionControllerProvider).recordingSessionIds,
        isEmpty,
      );
      expect(
        harness.directory
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.manifest.json')),
        isEmpty,
      );
    },
  );

  for (final startFault in <_RecordingStartResponseFault>[
    _RecordingStartResponseFault.missing,
    _RecordingStartResponseFault.malformed,
    _RecordingStartResponseFault.correlation,
  ]) {
    test(
      'start ${startFault.name} response retains recoverable ownership',
      () async {
        final harness = await _createHarness(
          startResponseFault: startFault,
          cancelBehavior: _RecordingCancelBehavior.terminationUnknown,
          persistentPrepareFailure: true,
        );
        final controller = harness.container.read(
          sessionControllerProvider.notifier,
        );
        final sessionId = harness.container
            .read(sessionControllerProvider)
            .activeSessionId!;

        expect(await controller.startSessionRecording(sessionId), isFalse);

        final state = harness.container.read(sessionControllerProvider);
        expect(state.recordingSessionIds, contains(sessionId));
        expect(state.lastError, contains('native ownership retained'));
        expect(
          harness.container
              .read(terminalLiveRecorderProvider)
              ?.isRecording(sessionId),
          isTrue,
        );
        final manifest = harness.directory
            .listSync(recursive: true)
            .whereType<File>()
            .singleWhere((file) => file.path.endsWith('.manifest.json'));
        final manifestJson =
            jsonDecode(manifest.readAsStringSync()) as Map<String, Object?>;
        expect(manifestJson['phase'], 'capturing');
        final recovery = await harness.recordingRepository
            .recoverNativeRecordings();
        expect(recovery.pendingJobIds, contains(manifestJson['jobId']));

        harness.backend.enqueueEvent(
          sessionId,
          PtyEvent(
            kind: 'exit',
            sessionId: sessionId,
            payload: const <String, Object?>{'code': 9},
          ),
        );
        harness.container
            .read(terminalRuntimeControllerProvider)
            .refreshSession(sessionId);
        expect(harness.backend.closedSessionIds, isEmpty);
        expect(manifest.existsSync(), isTrue);
      },
    );
  }

  test(
    'unknown start followed by not_active cancel releases ownership for retry',
    () async {
      final harness = await _createHarness(
        startResponseFault: _RecordingStartResponseFault.missing,
        cancelBehavior: _RecordingCancelBehavior.notActive,
      );
      final controller = harness.container.read(
        sessionControllerProvider.notifier,
      );
      final sessionId = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;

      expect(await controller.startSessionRecording(sessionId), isFalse);
      expect(
        harness.container.read(sessionControllerProvider).recordingSessionIds,
        isEmpty,
      );
      expect(
        harness.container
            .read(terminalLiveRecorderProvider)
            ?.isRecording(sessionId),
        isFalse,
      );
      expect(
        harness.directory
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.manifest.json')),
        isEmpty,
      );

      harness.backend
        ..startResponseFault = _RecordingStartResponseFault.none
        ..cancelBehavior = _RecordingCancelBehavior.acknowledge;
      expect(await controller.startSessionRecording(sessionId), isTrue);
      expect(
        harness.container.read(sessionControllerProvider).recordingSessionIds,
        contains(sessionId),
      );
    },
  );

  test(
    'recording merges local SSH and nested remote command semantics',
    () async {
      final harness = await _createHarness();
      final controller = harness.container.read(
        sessionControllerProvider.notifier,
      );
      final sessionId = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;
      await controller.startSessionRecording(sessionId);

      harness.backend
        ..enqueueEvent(
          sessionId,
          PtyEvent(
            kind: 'shell_hook',
            sessionId: sessionId,
            payload: const <String, Object?>{
              'hook': 'preexec',
              'command': 'ssh prod-server',
              'pwd': '/Users/dev/project',
            },
          ),
        )
        ..enqueueEvent(
          sessionId,
          PtyEvent(
            kind: 'shell_command',
            sessionId: sessionId,
            payload: const <String, Object?>{
              'source': 'osc633',
              'eventType': 'command_start',
              'command': 'ssh prod-server',
            },
          ),
        )
        ..enqueueEvent(
          sessionId,
          PtyEvent(
            kind: 'shell_command',
            sessionId: sessionId,
            payload: const <String, Object?>{
              'source': 'osc633',
              'eventType': 'command_start',
              'command': 'ls -la',
            },
          ),
        )
        ..enqueueEvent(
          sessionId,
          PtyEvent(
            kind: 'shell_command',
            sessionId: sessionId,
            payload: const <String, Object?>{
              'source': 'osc633',
              'eventType': 'command_finished',
              'command': 'ls -la',
              'exitCode': 0,
            },
          ),
        )
        ..enqueueEvent(
          sessionId,
          PtyEvent(
            kind: 'shell_command',
            sessionId: sessionId,
            payload: const <String, Object?>{
              'source': 'osc633',
              'eventType': 'command_finished',
              'command': 'ssh prod-server',
              'exitCode': 0,
            },
          ),
        )
        ..enqueueEvent(
          sessionId,
          PtyEvent(
            kind: 'shell_hook',
            sessionId: sessionId,
            payload: const <String, Object?>{
              'hook': 'command_finished',
              'command': 'ssh prod-server',
              'pwd': '/Users/dev/project',
              'exit_code': 0,
            },
          ),
        );
      harness.container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(sessionId);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final path = await controller.stopSessionRecording(sessionId);
      final recording = await harness.recordingRepository.load(path!);
      final semantics = recording.events
          .where(
            (event) =>
                event.kind == terminal.TerminalRecordingEventKind.shellSemantic,
          )
          .toList(growable: false);

      expect(
        recording.metadata.schemaVersion,
        terminal.terminalRecordingSchemaVersion,
      );
      expect(
        semantics.map((event) => event.semanticKind),
        <terminal.TerminalRecordingSemanticKind>[
          terminal.TerminalRecordingSemanticKind.remoteSessionStarted,
          terminal.TerminalRecordingSemanticKind.commandStarted,
          terminal.TerminalRecordingSemanticKind.commandFinished,
          terminal.TerminalRecordingSemanticKind.remoteSessionFinished,
        ],
      );
      expect(semantics[1].semanticCommand, 'ls -la');
      expect(semantics[1].semanticRemote, isTrue);
      expect(semantics[3].semanticCommand, 'ssh prod-server');
    },
  );

  test(
    'rejected manual prepare keeps collecting semantics for retry',
    () async {
      final harness = await _createHarness(prepareFailuresRemaining: 1);
      final controller = harness.container.read(
        sessionControllerProvider.notifier,
      );
      final sessionId = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;
      expect(await controller.startSessionRecording(sessionId), isTrue);

      expect(await controller.stopSessionRecording(sessionId), isNull);
      expect(
        harness.container.read(sessionControllerProvider).recordingSessionIds,
        contains(sessionId),
      );

      harness.backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'shell_command',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'osc633',
            'eventType': 'command_start',
            'command': 'captured-after-rejected-prepare',
          },
        ),
      );
      harness.container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(sessionId);

      final path = await controller.stopSessionRecording(sessionId);
      final recording = await harness.recordingRepository.load(path!);
      final semantics = recording.events.where(
        (event) =>
            event.kind == terminal.TerminalRecordingEventKind.shellSemantic,
      );

      expect(
        semantics.map((event) => event.semanticCommand),
        contains('captured-after-rejected-prepare'),
      );
      expect(harness.backend.prepareAttempts, 2);
    },
  );

  test(
    'semantic flood stays bounded and preserves the latest command pair',
    () async {
      final harness = await _createHarness(recordingMaxEvents: 4);
      final controller = harness.container.read(
        sessionControllerProvider.notifier,
      );
      final sessionId = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;
      await controller.startSessionRecording(sessionId);

      for (var index = 0; index < 20; index += 1) {
        harness.backend.enqueueEvent(
          sessionId,
          PtyEvent(
            kind: 'shell_hook',
            sessionId: sessionId,
            payload: <String, Object?>{
              'hook': index.isEven ? 'precmd.pwd' : 'precmd',
              'pwd': '/tmp/flood-$index',
            },
          ),
        );
      }
      harness.backend
        ..enqueueEvent(
          sessionId,
          PtyEvent(
            kind: 'shell_command',
            sessionId: sessionId,
            payload: const <String, Object?>{
              'eventType': 'command_start',
              'command': 'echo bounded',
            },
          ),
        )
        ..enqueueEvent(
          sessionId,
          PtyEvent(
            kind: 'shell_command',
            sessionId: sessionId,
            payload: const <String, Object?>{
              'eventType': 'command_finished',
              'command': 'echo bounded',
              'exitCode': 0,
            },
          ),
        );
      harness.container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(sessionId);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final path = await controller.stopSessionRecording(sessionId);
      final recording = await harness.recordingRepository.load(path!);
      final semantics = recording.events
          .where(
            (event) =>
                event.kind == terminal.TerminalRecordingEventKind.shellSemantic,
          )
          .toList(growable: false);

      expect(semantics.length, lessThanOrEqualTo(4));
      expect(
        semantics.map((event) => event.semanticKind),
        containsAll(<terminal.TerminalRecordingSemanticKind>[
          terminal.TerminalRecordingSemanticKind.commandStarted,
          terminal.TerminalRecordingSemanticKind.commandFinished,
        ]),
      );
      expect(
        harness.container.read(sessionControllerProvider).lastError,
        contains('dropping'),
      );
    },
  );

  test(
    'failed save keeps the PTY alive and retries without a second stop',
    () async {
      final harness = await _createHarness(
        recordingRepositoryBuilder: (directory) =>
            _FailingOnceRecordingRepository(
              directoryResolver: () async => directory,
            ),
      );
      final controller = harness.container.read(
        sessionControllerProvider.notifier,
      );
      final sessionId = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;
      await controller.startSessionRecording(sessionId);

      expect(await controller.closeSession(sessionId), isFalse);
      expect(harness.backend.closedSessionIds, isNot(contains(sessionId)));
      expect(
        harness.container
            .read(sessionControllerProvider)
            .recordingPendingSaveSessionIds,
        contains(sessionId),
      );
      expect(
        harness.backend.timeline.where((event) => event.startsWith('stop:')),
        hasLength(1),
      );

      expect(await controller.closeSession(sessionId), isTrue);
      expect(harness.backend.closedSessionIds, contains(sessionId));
      expect(
        harness.backend.timeline.where((event) => event.startsWith('stop:')),
        hasLength(1),
      );
    },
  );

  test(
    'closeTab resumes recording when ZMODEM starts during recording save',
    () async {
      late _BlockingRecordingRepository blockingRepository;
      final harness = await _createHarness(
        recordingRepositoryBuilder: (directory) {
          return blockingRepository = _BlockingRecordingRepository(
            directoryResolver: () async => directory,
          );
        },
      );
      final controller = harness.container.read(
        sessionControllerProvider.notifier,
      );
      final state = harness.container.read(sessionControllerProvider);
      final sessionId = state.activeSessionId!;
      final tabSessionId = state.tabs.single.sessionId;
      expect(await controller.startSessionRecording(sessionId), isTrue);

      final closeFuture = controller.closeTab(tabSessionId);
      await blockingRepository.saveStarted.future;
      harness.backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'zmodem_detected',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'zmodem',
            'transferId': '71',
            'direction': 'receive',
          },
        ),
      );
      final runtime = harness.container.read(terminalRuntimeControllerProvider);
      runtime.refreshSession(sessionId);
      expect(runtime.isZmodemTransferActive(sessionId), isTrue);
      blockingRepository.allowSave.complete();

      expect(await closeFuture, isFalse);
      expect(harness.backend.closedSessionIds, isNot(contains(sessionId)));
      expect(
        harness.container
            .read(sessionControllerProvider)
            .tabs
            .single
            .containsSession(sessionId),
        isTrue,
      );
      expect(
        harness.container.read(sessionControllerProvider).recordingSessionIds,
        contains(sessionId),
      );
      expect(
        harness.backend.timeline.where((event) => event == 'stop:$sessionId'),
        hasLength(1),
      );
      expect(
        harness.backend.timeline.where((event) => event == 'start:$sessionId'),
        hasLength(2),
      );
    },
  );

  test(
    'closeTab resumes a saved sibling when the second recording save fails',
    () async {
      final harness = await _createHarness(
        recordingRepositoryBuilder: (directory) =>
            _FailSecondRecordingRepository(
              directoryResolver: () async => directory,
            ),
      );
      final controller = harness.container.read(
        sessionControllerProvider.notifier,
      );
      final initialState = harness.container.read(sessionControllerProvider);
      final firstSessionId = initialState.activeSessionId!;
      final tabSessionId = initialState.tabs.single.sessionId;
      controller.splitActiveSession(
        defaultTerminalProfile(),
        TerminalSplitAxis.horizontal,
      );
      final secondSessionId = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;
      expect(secondSessionId, isNot(firstSessionId));
      expect(await controller.startSessionRecording(firstSessionId), isTrue);
      expect(await controller.startSessionRecording(secondSessionId), isTrue);

      expect(await controller.closeTab(tabSessionId), isFalse);

      final state = harness.container.read(sessionControllerProvider);
      expect(state.tabs.single.effectivePanes, hasLength(2));
      expect(state.recordingSessionIds, contains(firstSessionId));
      expect(state.recordingPendingSaveSessionIds, contains(secondSessionId));
      expect(state.lastError, contains('Recording finalize failed'));
      expect(harness.backend.closedSessionIds, isEmpty);
      expect(
        harness.backend.timeline.where(
          (event) => event == 'start:$firstSessionId',
        ),
        hasLength(2),
      );
      expect(
        harness.backend.timeline.where(
          (event) => event == 'stop:$firstSessionId',
        ),
        hasLength(1),
      );
      expect(
        harness.backend.timeline.where(
          (event) => event == 'start:$secondSessionId',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'opening a terminal at a folder keeps existing recording and PTY alive',
    () async {
      final harness = await _createHarness();
      final controller = harness.container.read(
        sessionControllerProvider.notifier,
      );
      final oldSessionId = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;
      await controller.startSessionRecording(oldSessionId);

      expect(
        await controller.openTerminalAtFolder('/projects/recorded'),
        isTrue,
      );

      expect(harness.backend.timeline, isNot(contains('stop:$oldSessionId')));
      expect(harness.backend.timeline, isNot(contains('close:$oldSessionId')));
      final state = harness.container.read(sessionControllerProvider);
      expect(state.tabs, hasLength(2));
      expect(state.recordingSessionIds, contains(oldSessionId));
    },
  );

  test('observed process exit finalizes the active recording', () async {
    final harness = await _createHarness();
    final controller = harness.container.read(
      sessionControllerProvider.notifier,
    );
    final sessionId = harness.container
        .read(sessionControllerProvider)
        .activeSessionId!;
    await controller.startSessionRecording(sessionId);

    harness.backend
      ..enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'shell_command',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'source': 'osc633',
            'eventType': 'command_start',
            'command': 'persist-before-native-prepare',
          },
        ),
      )
      ..enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'exit',
          sessionId: sessionId,
          payload: const <String, Object?>{'code': 0},
        ),
      );
    harness.container
        .read(terminalRuntimeControllerProvider)
        .refreshSession(sessionId);
    await _waitFor(
      () => !harness.container
          .read(sessionControllerProvider)
          .tabs
          .any((tab) => tab.containsSession(sessionId)),
      description: 'exited recording session removal',
    );

    expect(
      harness.backend.timeline.where((event) => event == 'stop:$sessionId'),
      hasLength(1),
    );
    expect(harness.backend.observedManifestBeforePrepare, isTrue);
    expect(
      harness.backend.observedSemanticsBeforePrepare
          .whereType<Map<Object?, Object?>>()
          .map((event) => event['command']),
      contains('persist-before-native-prepare'),
    );
    await _waitFor(
      () => _recordingFiles(harness.directory).isNotEmpty,
      description: 'exited recording durable destination',
    );
    expect(_recordingFiles(harness.directory), hasLength(1));
  });

  for (final entry in <({_RecordingPrepareResponseFault fault, String status})>[
    (fault: _RecordingPrepareResponseFault.missing, status: 'running'),
    (fault: _RecordingPrepareResponseFault.malformed, status: 'ready'),
    (fault: _RecordingPrepareResponseFault.correlation, status: 'failed'),
  ]) {
    test('pre-close resolves ${entry.fault.name} prepare from '
        '${entry.status} status before PTY close', () async {
      final harness = await _createHarness(
        prepareResponseFault: entry.fault,
        finalizeState: entry.status,
      );
      final controller = harness.container.read(
        sessionControllerProvider.notifier,
      );
      final sessionId = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;
      expect(await controller.startSessionRecording(sessionId), isTrue);

      harness.backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'exit',
          sessionId: sessionId,
          payload: const <String, Object?>{'code': 0},
        ),
      );
      harness.container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(sessionId);
      await _waitFor(
        () => harness.backend.closedSessionIds.contains(sessionId),
        description: '${entry.fault.name} prepare ownership resolution',
      );

      expect(harness.backend.prepareAttempts, 1);
      expect(
        harness.backend.timeline.indexOf('status:$sessionId'),
        greaterThan(harness.backend.timeline.indexOf('stop:$sessionId')),
      );
      expect(
        harness.backend.timeline.indexOf('close:$sessionId'),
        greaterThan(harness.backend.timeline.indexOf('status:$sessionId')),
      );
      expect(
        harness.container
            .read(terminalLiveRecorderProvider)
            ?.isRecording(sessionId),
        isFalse,
      );
    });
  }

  test(
    'pre-close retries one rejected prepare before exit closes the PTY',
    () async {
      final harness = await _createHarness(prepareFailuresRemaining: 1);
      final controller = harness.container.read(
        sessionControllerProvider.notifier,
      );
      final sessionId = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;
      expect(await controller.startSessionRecording(sessionId), isTrue);

      harness.backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'exit',
          sessionId: sessionId,
          payload: const <String, Object?>{'code': 9},
        ),
      );
      harness.container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(sessionId);
      await _waitFor(
        () =>
            harness.backend.closedSessionIds.contains(sessionId) &&
            _recordingFiles(harness.directory).isNotEmpty,
        description: 'recording save and PTY close after bounded retry',
      );

      expect(_recordingFiles(harness.directory), isNotEmpty);
      expect(harness.backend.prepareAttempts, 2);
      final stops = harness.backend.timeline
          .where((event) => event == 'stop:$sessionId')
          .toList(growable: false);
      expect(stops, hasLength(2));
      expect(
        harness.backend.timeline.indexOf('close:$sessionId'),
        greaterThan(harness.backend.timeline.lastIndexOf('stop:$sessionId')),
      );
      expect(
        harness.container
            .read(terminalRuntimeControllerProvider)
            .hasSession(sessionId),
        isFalse,
      );
    },
  );

  test(
    'persistent prepare rejection keeps PTY and recoverable recording active',
    () async {
      final harness = await _createHarness(persistentPrepareFailure: true);
      final controller = harness.container.read(
        sessionControllerProvider.notifier,
      );
      final sessionId = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;
      expect(await controller.startSessionRecording(sessionId), isTrue);

      harness.backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'exit',
          sessionId: sessionId,
          payload: const <String, Object?>{'code': 9},
        ),
      );
      final runtime = harness.container.read(terminalRuntimeControllerProvider);
      runtime.refreshSession(sessionId);
      await _waitFor(
        () =>
            harness.container.read(sessionControllerProvider).lastError != null,
        description: 'visible persistent pre-close failure',
      );

      expect(harness.backend.prepareAttempts, 2);
      expect(harness.backend.timeline, isNot(contains('close:$sessionId')));
      expect(runtime.hasSession(sessionId), isTrue);
      expect(
        harness.container.read(sessionControllerProvider).recordingSessionIds,
        contains(sessionId),
      );
      expect(
        harness.container
            .read(terminalLiveRecorderProvider)
            ?.isRecording(sessionId),
        isTrue,
      );
      expect(
        harness.container.read(sessionControllerProvider).lastError,
        contains('beforeSessionCloseOnExitSignal'),
      );
      final manifests = harness.directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.manifest.json'))
          .toList(growable: false);
      expect(manifests, hasLength(1));
      final manifest = jsonDecode(await manifests.single.readAsString());
      expect(manifest, isA<Map<String, Object?>>());
      expect((manifest as Map<String, Object?>)['sessionId'], sessionId);
      expect(manifest['phase'], 'preparing');
      expect(manifest['semanticEvents'], isA<List<Object?>>());
    },
  );

  test(
    'shutdown coordinator finalizes active recording before disposal',
    () async {
      final harness = await _createHarness();
      final controller = harness.container.read(
        sessionControllerProvider.notifier,
      );
      final sessionId = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;
      await controller.startSessionRecording(sessionId);

      await harness.container.read(appShutdownCoordinatorProvider).shutdown();
      harness.container.dispose();

      expect(harness.backend.timeline, contains('stop:$sessionId'));
      expect(_recordingFiles(harness.directory), hasLength(1));
    },
  );

  for (final terminalState in <String>['ready', 'failed']) {
    test('shutdown keeps uncertain prepare claimed through late running then '
        '$terminalState settlement', () async {
      final settlementDelay = _ControlledRecordingDelay();
      final harness = await _createHarness(
        prepareResponseFault: _RecordingPrepareResponseFault.missing,
        finalizeState: 'running',
        finalizeStates: <String>['unknown', 'running'],
        deferHandoffArtifact: true,
        cancelBehavior: _RecordingCancelBehavior.notActive,
        recordingRepositoryBuilder: (directory) =>
            LocalSessionRecordingRepository(
              directoryResolver: () async => directory,
              finalizeTimeout: const Duration(microseconds: 1),
              finalizePollInterval: const Duration(milliseconds: 1),
              settlementObservationTimeout: const Duration(minutes: 1),
              delay: settlementDelay.call,
            ),
      );
      final controller = harness.container.read(
        sessionControllerProvider.notifier,
      );
      final sessionId = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;
      expect(await controller.startSessionRecording(sessionId), isTrue);

      final shutdown = harness.container
          .read(appShutdownCoordinatorProvider)
          .shutdown(bounded: false);
      await settlementDelay.waitForPending();

      expect(harness.backend.closedSessionIds, isEmpty);
      final replacementRepository = LocalSessionRecordingRepository(
        directoryResolver: () async => harness.directory,
      );
      final whileOwned = await replacementRepository.recoverNativeRecordings();
      expect(whileOwned.pendingJobIds, hasLength(1));
      expect(whileOwned.recoveredPaths, isEmpty);

      harness.backend.finalizeState = 'running';
      settlementDelay.releaseNext();
      await settlementDelay.waitForPending();
      expect(harness.backend.closedSessionIds, isEmpty);

      harness.backend.finalizeState = terminalState;
      if (terminalState == 'ready') {
        harness.backend.publishDeferredHandoffArtifact();
      }
      settlementDelay.releaseNext();
      final result = await shutdown;

      expect(result.failures, isNotEmpty);
      expect(harness.backend.closedSessionIds, <String>[sessionId]);
      expect(
        harness.backend.timeline.indexOf('close:$sessionId'),
        greaterThan(harness.backend.timeline.lastIndexOf('status:$sessionId')),
      );
      final recovered = await replacementRepository.recoverNativeRecordings();
      if (terminalState == 'ready') {
        expect(recovered.recoveredPaths, hasLength(1));
        expect(recovered.failures, isEmpty);
      } else {
        expect(recovered.recoveredPaths, isEmpty);
        expect(
          recovered.failures.single.failure,
          LocalSessionRecordingFinalizeFailure.nativeTerminationUnknown,
        );
      }
    });
  }

  for (final cancelBehavior in <_RecordingCancelBehavior>[
    _RecordingCancelBehavior.reject,
    _RecordingCancelBehavior.terminationUnknown,
  ]) {
    test(
      'explicit prepare rejection plus ${cancelBehavior.name} cancel poisons '
      'shutdown before PTY close',
      () async {
        final shutdownCoordinator = AppShutdownCoordinator(
          timeout: const Duration(microseconds: 1),
        );
        final harness = await _createHarness(
          persistentPrepareFailure: true,
          cancelBehavior: cancelBehavior,
          shutdownCoordinator: shutdownCoordinator,
        );
        final controller = harness.container.read(
          sessionControllerProvider.notifier,
        );
        final sessionId = harness.container
            .read(sessionControllerProvider)
            .activeSessionId!;
        expect(await controller.startSessionRecording(sessionId), isTrue);

        final bounded = await shutdownCoordinator.shutdown();

        expect(bounded.timedOut, isTrue);
        expect(harness.backend.prepareAttempts, 2);
        expect(harness.backend.closedSessionIds, isEmpty);
        expect(
          harness.container
              .read(terminalLiveRecorderProvider)
              ?.isRecording(sessionId),
          isTrue,
        );
        final replacementRecovery = await LocalSessionRecordingRepository(
          directoryResolver: () async => harness.directory,
        ).recoverNativeRecordings();
        expect(replacementRecovery.pendingJobIds, hasLength(1));
        var eventuallySettled = false;
        unawaited(
          shutdownCoordinator.settle().then((_) => eventuallySettled = true),
        );
        await Future<void>.value();
        expect(eventuallySettled, isFalse);
        expect(harness.backend.closedSessionIds, isEmpty);
      },
    );
  }

  test(
    'session shutdown orders recording, layout flush, then runtime close',
    () async {
      final timeline = <String>[];
      final harness = await _createHarness(
        timeline: timeline,
        recordingRepositoryBuilder: (directory) => _OrderedRecordingRepository(
          timeline: timeline,
          directoryResolver: () async => directory,
        ),
        layoutRepositoryBuilder: (directory) => _OrderedLayoutRepository(
          timeline: timeline,
          directoryResolver: () async => directory,
        ),
      );
      final controller = harness.container.read(
        sessionControllerProvider.notifier,
      );
      await controller.flushLayoutPersistence();
      final sessionId = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;
      await controller.startSessionRecording(sessionId);
      timeline.clear();

      final result = await harness.container
          .read(appShutdownCoordinatorProvider)
          .shutdown();

      expect(result.timedOut, isFalse);
      expect(result.failures, isEmpty);
      expect(controller.isShuttingDown, isTrue);
      expect(await controller.openTerminalAtFolder('/ignored'), isFalse);
      expect(
        timeline,
        containsAll(<String>[
          'stop:$sessionId',
          'recording-save-complete',
          'layout-save-complete',
          'close:$sessionId',
        ]),
      );
      expect(
        timeline.indexOf('stop:$sessionId'),
        lessThan(timeline.indexOf('recording-save-complete')),
      );
      expect(
        timeline.indexOf('recording-save-complete'),
        lessThan(timeline.indexOf('layout-save-start')),
      );
      expect(
        timeline.indexOf('layout-save-complete'),
        lessThan(timeline.indexOf('close:$sessionId')),
      );
      expect(_recordingFiles(harness.directory), hasLength(1));
      expect(
        File(
          '${harness.directory.path}/ianvs_terminal_layout.json',
        ).existsSync(),
        isTrue,
      );
    },
  );

  test(
    'shutdown crossing recording finalization leaves PTY close to infra',
    () async {
      late _BlockingRecordingRepository blockingRepository;
      final harness = await _createHarness(
        recordingRepositoryBuilder: (directory) {
          return blockingRepository = _BlockingRecordingRepository(
            directoryResolver: () async => directory,
          );
        },
      );
      final controller = harness.container.read(
        sessionControllerProvider.notifier,
      );
      final sessionId = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;
      expect(await controller.startSessionRecording(sessionId), isTrue);

      final productClose = controller.closeSession(sessionId);
      await blockingRepository.saveStarted.future;
      final shutdown = harness.container
          .read(appShutdownCoordinatorProvider)
          .shutdown(bounded: false);

      expect(controller.isShuttingDown, isTrue);
      expect(harness.backend.closedSessionIds, isEmpty);

      blockingRepository.allowSave.complete();
      expect(await productClose, isFalse);
      final result = await shutdown;

      expect(result.failures, isEmpty);
      expect(harness.backend.closedSessionIds, <String>[sessionId]);
    },
  );

  test(
    'closeTab crossing recording finalization does not resume or rewrite UI',
    () async {
      late _BlockingRecordingRepository blockingRepository;
      final harness = await _createHarness(
        recordingRepositoryBuilder: (directory) {
          return blockingRepository = _BlockingRecordingRepository(
            directoryResolver: () async => directory,
          );
        },
      );
      final controller = harness.container.read(
        sessionControllerProvider.notifier,
      );
      final state = harness.container.read(sessionControllerProvider);
      final sessionId = state.activeSessionId!;
      final tabSessionId = state.tabs.single.sessionId;
      expect(await controller.startSessionRecording(sessionId), isTrue);

      final productClose = controller.closeTab(tabSessionId);
      await blockingRepository.saveStarted.future;
      final shutdown = harness.container
          .read(appShutdownCoordinatorProvider)
          .shutdown(bounded: false);

      expect(controller.isShuttingDown, isTrue);
      expect(harness.backend.closedSessionIds, isEmpty);

      blockingRepository.allowSave.complete();
      expect(await productClose, isFalse);
      final result = await shutdown;

      expect(result.failures, isEmpty);
      expect(harness.backend.closedSessionIds, <String>[sessionId]);
      expect(
        harness.backend.timeline.where((event) => event == 'start:$sessionId'),
        hasLength(1),
      );
      expect(
        harness.container.read(sessionControllerProvider).lastError,
        isNull,
      );
    },
  );

  test(
    'stop failure crossing shutdown preserves UI error and single release',
    () async {
      late _BlockingFailingRecordingRepository blockingRepository;
      final harness = await _createHarness(
        recordingRepositoryBuilder: (directory) {
          return blockingRepository = _BlockingFailingRecordingRepository(
            directoryResolver: () async => directory,
          );
        },
      );
      final controller = harness.container.read(
        sessionControllerProvider.notifier,
      );
      final sessionId = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;
      expect(await controller.startSessionRecording(sessionId), isTrue);

      final productStop = controller.stopSessionRecording(sessionId);
      await blockingRepository.saveStarted.future;
      controller.reportRuntimeError('sentinel before shutdown');
      final shutdown = harness.container
          .read(appShutdownCoordinatorProvider)
          .shutdown(bounded: false);
      blockingRepository.allowFailure.complete();

      expect(await productStop, isNull);
      final result = await shutdown;

      expect(result.failures, hasLength(1));
      expect(
        harness.container.read(sessionControllerProvider).lastError,
        'sentinel before shutdown',
      );
      expect(blockingRepository.releaseCount, 1);
      expect(harness.backend.closedSessionIds, <String>[sessionId]);
    },
  );

  test(
    'direct stop after shutdown does not publish busy or clear the UI error',
    () async {
      late _BlockingRecordingRepository blockingRepository;
      final harness = await _createHarness(
        recordingRepositoryBuilder: (directory) {
          return blockingRepository = _BlockingRecordingRepository(
            directoryResolver: () async => directory,
          );
        },
      );
      final controller = harness.container.read(
        sessionControllerProvider.notifier,
      );
      final sessionId = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;
      expect(await controller.startSessionRecording(sessionId), isTrue);
      controller.reportRuntimeError('sentinel before shutdown');

      final shutdown = harness.container
          .read(appShutdownCoordinatorProvider)
          .shutdown(bounded: false);
      final stop = controller.stopSessionRecording(sessionId);

      final stateWhileStopping = harness.container.read(
        sessionControllerProvider,
      );
      expect(stateWhileStopping.lastError, 'sentinel before shutdown');
      expect(
        stateWhileStopping.recordingBusySessionIds,
        isNot(contains(sessionId)),
      );
      expect(await stop, isNull);

      await blockingRepository.saveStarted.future;
      blockingRepository.allowSave.complete();
      final result = await shutdown;
      expect(result.failures, isEmpty);
      expect(
        harness.container.read(sessionControllerProvider).lastError,
        'sentinel before shutdown',
      );
      expect(harness.backend.closedSessionIds, <String>[sessionId]);
    },
  );

  test(
    'runtime-exit save failure crossing shutdown preserves UI and releases once',
    () async {
      late _BlockingFailingRecordingRepository blockingRepository;
      final harness = await _createHarness(
        recordingRepositoryBuilder: (directory) {
          return blockingRepository = _BlockingFailingRecordingRepository(
            directoryResolver: () async => directory,
          );
        },
      );
      final controller = harness.container.read(
        sessionControllerProvider.notifier,
      );
      final sessionId = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;
      expect(await controller.startSessionRecording(sessionId), isTrue);

      harness.backend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'exit',
          sessionId: sessionId,
          payload: const <String, Object?>{'code': 0},
        ),
      );
      harness.container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(sessionId);
      await blockingRepository.saveStarted.future;
      controller.reportRuntimeError('sentinel before shutdown');
      final shutdown = harness.container
          .read(appShutdownCoordinatorProvider)
          .shutdown(bounded: false);
      blockingRepository.allowFailure.complete();

      await blockingRepository.releaseObserved.future;
      final result = await shutdown;
      expect(result.failures, hasLength(1));
      expect(
        harness.container.read(sessionControllerProvider).lastError,
        'sentinel before shutdown',
      );
      expect(blockingRepository.releaseCount, 1);
      expect(harness.backend.closedSessionIds, <String>[sessionId]);
    },
  );

  test('shutdown finalization never encodes in the disposal stack', () async {
    late _BlockingRecordingRepository blockingRepository;
    final harness = await _createHarness(
      recordingRepositoryBuilder: (directory) =>
          blockingRepository = _BlockingRecordingRepository(
            directoryResolver: () async => directory,
          ),
    );
    final controller = harness.container.read(
      sessionControllerProvider.notifier,
    );
    final sessionId = harness.container
        .read(sessionControllerProvider)
        .activeSessionId!;
    await controller.startSessionRecording(sessionId);
    final shutdown = harness.container
        .read(appShutdownCoordinatorProvider)
        .shutdown();

    harness.container.dispose();

    expect(blockingRepository.saveStarted.isCompleted, isFalse);
    await blockingRepository.saveStarted.future;
    expect(_recordingFiles(harness.directory), isEmpty);

    blockingRepository.allowSave.complete();
    await shutdown;
    expect(_recordingFiles(harness.directory), hasLength(1));
  });
}

List<File> _recordingFiles(Directory directory) {
  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .where(
        (file) =>
            file.path.endsWith('.ndjson') &&
            !file.path.contains('.ianvs-recording-handoff-'),
      )
      .toList(growable: false);
}

Future<void> _waitFor(
  bool Function() condition, {
  required String description,
}) async {
  final timeout = Stopwatch()..start();
  while (timeout.elapsed < const Duration(seconds: 5)) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TestFailure('Timed out waiting for $description.');
}

String _recordingFixture(String sessionId, {required String inputPolicy}) {
  return <Map<String, Object?>>[
    <String, Object?>{
      'record_type': 'metadata',
      'schema_version': 1,
      'session_id': sessionId,
      'created_at_utc': '2026-07-21T06:00:00.000Z',
      'input_policy': inputPolicy,
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
    <String, Object?>{
      'record_type': 'event',
      'schema_version': 1,
      'session_id': sessionId,
      'sequence': 1,
      'monotonic_offset_micros': 10,
      'event_kind': 'pty_output',
      'payload': <String, Object?>{'bytes_base64': 'cmVhZHkNCg=='},
    },
  ].map(jsonEncode).join('\n');
}
