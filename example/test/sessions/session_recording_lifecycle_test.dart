import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;
import 'package:ianvs_pty/ianvs_pty.dart';

import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/local_terminal_config_repository.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/recording/local_session_recording_repository.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/workspace/local_workspace_identity.dart';
import 'package:app/features/workspace/local_workspace_repository.dart';

import '../support/fake_pty_backend.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_profile_repository.dart';

class _RecordingConfigRepository extends LocalTerminalConfigRepository {
  @override
  Future<LocalTerminalConfigDocument?> load() async {
    return const LocalTerminalConfigDocument(
      workspace: LocalTerminalWorkspaceConfig(restoreLayout: true),
    );
  }

  @override
  Future<void> save(LocalTerminalConfigDocument document) async {}
}

class _RecordingPtyBackend extends FakePtyBackend {
  final List<String> timeline = <String>[];
  final Map<String, String> _inputPolicies = <String, String>{};

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
          'max_events': 4096,
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
}

class _RecordingHarness {
  const _RecordingHarness({
    required this.container,
    required this.backend,
    required this.workspaceRepository,
    required this.recordingRepository,
    required this.directory,
  });

  final ProviderContainer container;
  final _RecordingPtyBackend backend;
  final LocalWorkspaceRepository workspaceRepository;
  final LocalSessionRecordingRepository recordingRepository;
  final Directory directory;
}

Future<_RecordingHarness> _createHarness({
  LocalSessionRecordingRepository Function(Directory directory)?
  recordingRepositoryBuilder,
}) async {
  final directory = await Directory.systemTemp.createTemp(
    'ianvs terminal-session-recording',
  );
  final backend = _RecordingPtyBackend();
  final workspaceRepository = LocalWorkspaceRepository(
    directoryResolver: () async => directory,
  );
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
      localWorkspaceRepositoryProvider.overrideWithValue(workspaceRepository),
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
    workspaceRepository: workspaceRepository,
    recordingRepository: recordingRepository,
    directory: directory,
  );
}

void main() {
  test(
    'start and stop save redacted v1 data and associate the descriptor',
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
      expect(pane.sessionDescriptor!.recordingPath, path);
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
    'workspace switch saves and associates recording before old PTY close',
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
        await controller.openProjectWorkspace('/projects/recorded'),
        isTrue,
      );

      final stopIndex = harness.backend.timeline.indexOf('stop:$oldSessionId');
      final closeIndex = harness.backend.timeline.indexOf(
        'close:$oldSessionId',
      );
      expect(stopIndex, greaterThanOrEqualTo(0));
      expect(closeIndex, greaterThan(stopIndex));
      final previousWorkspace = await harness.workspaceRepository.loadWorkspace(
        TerminalWorkspaceIdentity.defaultWorkspace.id,
      );
      expect(
        previousWorkspace!.tabs.single.root.sessionDescriptor!.recordingPath,
        isNotNull,
      );
      expect(
        controller.activeWorkspaceIdentity,
        TerminalWorkspaceIdentity.forProject('/projects/recorded'),
      );
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

  test('controller disposal best-effort saves active recording', () async {
    final harness = await _createHarness();
    final controller = harness.container.read(
      sessionControllerProvider.notifier,
    );
    final sessionId = harness.container
        .read(sessionControllerProvider)
        .activeSessionId!;
    await controller.startSessionRecording(sessionId);

    harness.container.dispose();

    expect(harness.backend.timeline, contains('stop:$sessionId'));
    expect(_recordingFiles(harness.directory), hasLength(1));
  });
}

List<File> _recordingFiles(Directory directory) {
  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.ndjson'))
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
