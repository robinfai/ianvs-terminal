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

class _RecordingPtyBackend extends FakePtyBackend {
  _RecordingPtyBackend({List<String>? timeline, this.maxEvents = 4096})
    : timeline = timeline ?? <String>[];

  final List<String> timeline;
  final int maxEvents;
  final Map<String, String> _inputPolicies = <String, String>{};
  bool observedManifestBeforePrepare = false;

  @override
  String? requestSessionJson(String sessionId, String requestJson) {
    final request = jsonDecode(requestJson) as Map<String, Object?>;
    final kind = request['kind'];
    switch (kind) {
      case 'terminal.recording_start':
        timeline.add('start:$sessionId');
        _inputPolicies[sessionId] = request['input_policy']! as String;
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
        final jobId = request['job_id']! as String;
        final directory = request['handoff_directory']! as String;
        final handoffPath = '$directory/.ianvs-recording-handoff-$jobId.ndjson';
        observedManifestBeforePrepare = File(
          '$handoffPath.manifest.json',
        ).existsSync();
        File(handoffPath).writeAsStringSync(
          _recordingFixture(
            sessionId,
            inputPolicy: _inputPolicies[sessionId] ?? 'redact',
          ),
          flush: true,
        );
        return jsonEncode(<String, Object?>{
          'ok': true,
          'job_id': jobId,
          'handoff_path': handoffPath,
          'error_path': '$handoffPath.error.json',
        });
      case 'terminal.recording_cancel':
        timeline.add('cancel:$sessionId');
        return jsonEncode(const <String, Object?>{'ok': true});
      default:
        return super.requestSessionJson(sessionId, requestJson);
    }
  }

  @override
  void closeSession(String sessionId) {
    timeline.add('close:$sessionId');
    super.closeSession(sessionId);
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
  }) {
    return _failAfterGate();
  }

  @override
  void release(LocalSessionRecordingDestination destination) {
    releaseCount += 1;
    if (!releaseObserved.isCompleted) {
      releaseObserved.complete();
    }
    super.release(destination);
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
  }) async {
    timeline.add('recording-save-start');
    final path = await super.finalizeNativeRecording(
      job: job,
      handoffDirectory: handoffDirectory,
      destination: destination,
      semanticEvents: semanticEvents,
      displayName: displayName,
      cancellation: cancellation,
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

Future<_RecordingHarness> _createHarness({
  LocalSessionRecordingRepository Function(Directory directory)?
  recordingRepositoryBuilder,
  LocalTerminalLayoutRepository Function(Directory directory)?
  layoutRepositoryBuilder,
  List<String>? timeline,
  int recordingMaxEvents = 4096,
}) async {
  final directory = await Directory.systemTemp.createTemp(
    'ianvs terminal-session-recording',
  );
  final backend = _RecordingPtyBackend(
    timeline: timeline,
    maxEvents: recordingMaxEvents,
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
    'start and stop save redacted v1 data outside relaunch intent',
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
        terminal.terminalRecordingSemanticSchemaVersion,
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
      () => !harness.container
          .read(sessionControllerProvider)
          .tabs
          .any((tab) => tab.containsSession(sessionId)),
      description: 'exited recording session removal',
    );

    expect(harness.backend.timeline, contains('stop:$sessionId'));
    expect(_recordingFiles(harness.directory), hasLength(1));
  });

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

      controller.finalizeRecordingBeforeRuntimeClose(sessionId);
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
            !file.path.contains('.ianvs-recording-handoff-v1-'),
      )
      .toList(growable: false);
}

Future<void> _waitFor(
  bool Function() condition, {
  required String description,
}) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
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
