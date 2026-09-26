import 'dart:io';

import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/local_terminal_config_repository.dart';
import 'package:app/features/layout/local_terminal_layout_repository.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/recording/sampled_recording_library.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/platform/app_shutdown_coordinator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart'
    show TerminalRecordingInputPolicy;

import '../support/memory_app_preferences_repository.dart';
import '../support/memory_profile_repository.dart';
import '../support/sampled_recording_backend.dart';

class _Config extends LocalTerminalConfigRepository {
  @override
  Future<LocalTerminalConfigDocument?> load() async =>
      const LocalTerminalConfigDocument(
        layout: LocalTerminalLayoutConfig(restoreLayout: true),
      );
  @override
  Future<void> save(LocalTerminalConfigDocument document) async {}
}

Future<void> _wait(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) fail('State did not settle');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late Directory directory;
  late SampledTestBackend backend;
  late SampledRecordingLibrary library;
  late ProviderContainer container;
  late AppShutdownCoordinator shutdown;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sampled-session-test-');
    backend = SampledTestBackend();
    library = SampledRecordingLibrary(
      files: NoSampledFileReads(),
      directoryResolver: () async =>
          Directory('${directory.path}/recordings-v2'),
    );
    shutdown = AppShutdownCoordinator(
      timeout: const Duration(milliseconds: 80),
    );
    container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(backend),
        profileRepositoryProvider.overrideWithValue(
          MemoryProfileRepository(
            TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          MemoryAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(_Config()),
        localTerminalLayoutRepositoryProvider.overrideWithValue(
          LocalTerminalLayoutRepository(
            directoryResolver: () async => directory,
          ),
        ),
        sampledRecordingLibraryProvider.overrideWithValue(library),
        appShutdownCoordinatorProvider.overrideWithValue(shutdown),
      ],
    );
    container.read(sessionControllerProvider.notifier);
    await _wait(() => container.read(sessionControllerProvider).isReady);
  });
  tearDown(() async {
    backend
      ..loseStop = false
      ..loseStatus = false
      ..deferSettlement = false
      ..corruptIdentity = false;
    backend.loseStopFor.clear();
    await shutdown.shutdown(bounded: false);
    container.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'manual capture persists identity before native start and stops into new library',
    () async {
      final controller = container.read(sessionControllerProvider.notifier);
      final id = container.read(sessionControllerProvider).activeSessionId!;
      expect(await controller.startSessionRecording(id), isTrue);
      expect(backend.manifestBeforeStart, isTrue);
      expect(
        container.read(sessionControllerProvider).recordingSessionIds,
        contains(id),
      );
      final path = await controller.stopSessionRecording(id);
      expect(path, endsWith('.trailrec'));
      expect(library.activeClaims, isEmpty);
      expect((await library.listRecordings()).single.state, 'finished');
      expect(
        backend.actions.every(
          (op) => op.startsWith('terminal.sampled_recording_'),
        ),
        isTrue,
      );
    },
  );

  test(
    'a lost start reply retains ownership and user can finish using the saved identity',
    () async {
      final controller = container.read(sessionControllerProvider.notifier);
      final id = container.read(sessionControllerProvider).activeSessionId!;
      backend.loseStart = true;
      expect(await controller.startSessionRecording(id), isFalse);
      expect(
        container
            .read(sessionControllerProvider)
            .recordingPendingSaveSessionIds,
        contains(id),
      );
      expect(library.activeClaims.length, 1);
      expect((await library.recover()).busy, 1);
      expect(await controller.stopSessionRecording(id), isNotNull);
      expect(library.activeClaims, isEmpty);
    },
  );

  test(
    'lost stop response blocks close and retry finishes without losing the claim',
    () async {
      final controller = container.read(sessionControllerProvider.notifier);
      final id = container.read(sessionControllerProvider).activeSessionId!;
      await controller.startSessionRecording(id);
      backend.loseStop = true;
      expect(await controller.closeSession(id), isFalse);
      expect(backend.closedSessionIds, isEmpty);
      expect(library.activeClaims.length, 1);
      backend.loseStop = false;
      expect(await controller.closeSession(id), isTrue);
      expect(library.activeClaims, isEmpty);
      expect(backend.closedSessionIds, contains(id));
    },
  );

  test(
    'rejected native close starts a fresh continuation for the still-live pane',
    () async {
      final controller = container.read(sessionControllerProvider.notifier);
      final id = container.read(sessionControllerProvider).activeSessionId!;
      await controller.startSessionRecording(id);
      backend.failingCloseSessionIds.add(id);
      expect(await controller.closeSession(id), isFalse);
      expect(backend.capturedIds.toSet().length, 2);
      expect(library.activeClaims.length, 1);
      expect(
        container.read(sessionControllerProvider).recordingSessionIds,
        contains(id),
      );
      backend.failingCloseSessionIds.clear();
    },
  );

  test(
    'observed process exit retains writer monitoring after runtime removal',
    () async {
      final controller = container.read(sessionControllerProvider.notifier);
      final id = container.read(sessionControllerProvider).activeSessionId!;
      await controller.startSessionRecording(id);
      backend.enqueueEvent(
        id,
        PtyEvent(kind: 'exit', sessionId: id, payload: const {'code': 0}),
      );
      container.read(terminalRuntimeControllerProvider).refreshSession(id);
      await _wait(() => library.activeClaims.isEmpty);
      expect((await library.listRecordings()).single.state, 'finished');
      expect(backend.closedSessionIds, contains(id));
    },
  );

  test('raw input recording is rejected before reserving a file', () async {
    final controller = container.read(sessionControllerProvider.notifier);
    final id = container.read(sessionControllerProvider).activeSessionId!;
    expect(
      await controller.startSessionRecording(
        id,
        inputPolicy: TerminalRecordingInputPolicy.record,
      ),
      isFalse,
    );
    expect(await library.listRecordings(), isEmpty);
    expect(backend.capturedIds, isEmpty);
  });

  test(
    'concurrent starts reserve one identity and relaunch layout excludes recording',
    () async {
      final controller = container.read(sessionControllerProvider.notifier);
      final id = container.read(sessionControllerProvider).activeSessionId!;
      final starts = await Future.wait([
        controller.startSessionRecording(id),
        controller.startSessionRecording(id),
      ]);
      expect(starts.where((value) => value), hasLength(1));
      expect(backend.capturedIds, hasLength(1));
      await controller.flushLayoutPersistence();
      final layout = await File(
        '${directory.path}/ianvs_terminal_layout.json',
      ).readAsString();
      expect(layout, isNot(contains('.trailrec')));
      expect(layout, isNot(contains(backend.capturedIds.single)));
    },
  );

  test(
    'a mismatched start identity retains ownership until a correlated stop settles',
    () async {
      final controller = container.read(sessionControllerProvider.notifier);
      final id = container.read(sessionControllerProvider).activeSessionId!;
      backend.corruptIdentity = true;
      expect(await controller.startSessionRecording(id), isFalse);
      expect(library.activeClaims, hasLength(1));
      expect(await controller.closeSession(id), isFalse);
      expect(backend.closedSessionIds, isEmpty);
      backend.corruptIdentity = false;
      expect(await controller.closeSession(id), isTrue);
      expect(library.activeClaims, isEmpty);
    },
  );

  test(
    'opening another folder leaves the original capture and PTY alive',
    () async {
      final controller = container.read(sessionControllerProvider.notifier);
      final id = container.read(sessionControllerProvider).activeSessionId!;
      await controller.startSessionRecording(id);
      expect(
        await controller.openTerminalAtFolder('/projects/recorded'),
        isTrue,
      );
      expect(container.read(sessionControllerProvider).tabs, hasLength(2));
      expect(
        container.read(sessionControllerProvider).recordingSessionIds,
        contains(id),
      );
      expect(backend.actions.where((op) => op.endsWith('_stop')), isEmpty);
      expect(backend.closedSessionIds, isEmpty);
    },
  );

  test(
    'a sibling stop failure resumes the already-saved pane before rejecting tab close',
    () async {
      final controller = container.read(sessionControllerProvider.notifier);
      final initial = container.read(sessionControllerProvider);
      final first = initial.activeSessionId!;
      controller.splitActiveSession(
        defaultTerminalProfile(),
        TerminalSplitAxis.horizontal,
      );
      final second = container.read(sessionControllerProvider).activeSessionId!;
      await controller.startSessionRecording(first);
      await controller.startSessionRecording(second);
      backend.loseStopFor.add(second);
      expect(await controller.closeTab(initial.tabs.single.sessionId), isFalse);
      final state = container.read(sessionControllerProvider);
      expect(state.tabs.single.effectivePanes, hasLength(2));
      expect(state.recordingSessionIds, contains(first));
      expect(state.recordingPendingSaveSessionIds, contains(second));
      expect(backend.capturedIds, hasLength(3));
      expect(backend.closedSessionIds, isEmpty);
    },
  );

  test(
    'a transfer beginning during stop preserves the pane and starts a continuation',
    () async {
      final controller = container.read(sessionControllerProvider.notifier);
      final state = container.read(sessionControllerProvider);
      final id = state.activeSessionId!;
      await controller.startSessionRecording(id);
      backend.onRequest = (operation, sessionId) {
        if (!operation.endsWith('_stop')) return;
        backend.onRequest = null;
        backend.enqueueEvent(
          id,
          PtyEvent(
            kind: 'zmodem_detected',
            sessionId: id,
            payload: const {
              'source': 'zmodem',
              'transferId': '71',
              'direction': 'receive',
            },
          ),
        );
        container.read(terminalRuntimeControllerProvider).refreshSession(id);
      };
      expect(await controller.closeTab(state.tabs.single.sessionId), isFalse);
      expect(backend.closedSessionIds, isEmpty);
      expect(backend.capturedIds, hasLength(2));
      expect(
        container.read(sessionControllerProvider).recordingSessionIds,
        contains(id),
      );
    },
  );

  for (final phase in ['finished', 'failed']) {
    test(
      'shutdown keeps the PTY and file claim until $phase settlement',
      () async {
        final controller = container.read(sessionControllerProvider.notifier);
        final id = container.read(sessionControllerProvider).activeSessionId!;
        await controller.startSessionRecording(id);
        backend
          ..deferSettlement = true
          ..terminalPhase = phase;
        final result = await shutdown.shutdown();
        expect(result.timedOut, isTrue);
        expect(result.unsafeToTerminate, isTrue);
        expect(backend.closedSessionIds, isEmpty);
        expect((await library.recover()).busy, 1);
        expect(await controller.openTerminalAtFolder('/ignored'), isFalse);
        backend.deferSettlement = false;
        await shutdown.settle();
        expect(library.activeClaims, isEmpty);
        expect(backend.closedSessionIds, [id]);
        expect(
          (await library.listRecordings()).single.state,
          phase == 'finished' ? 'finished' : 'interrupted',
        );
        expect(
          backend.timeline.indexOf('terminal.sampled_recording_release:$id'),
          lessThan(backend.timeline.indexOf('close:$id')),
        );
      },
    );
  }

  test(
    'shutdown crossing a manual close shares the writer and does not resume capture',
    () async {
      final controller = container.read(sessionControllerProvider.notifier);
      final id = container.read(sessionControllerProvider).activeSessionId!;
      await controller.startSessionRecording(id);
      backend.deferSettlement = true;
      final closing = controller.closeSession(id);
      await _wait(
        () => backend.actions.contains('terminal.sampled_recording_stop'),
      );
      final ending = shutdown.shutdown(bounded: false);
      expect(controller.isShuttingDown, isTrue);
      backend.deferSettlement = false;
      expect(await closing, isFalse);
      expect((await ending).safeToTerminate, isTrue);
      expect(backend.capturedIds, hasLength(1));
      expect(
        backend.actions.where((op) => op.endsWith('_release')),
        hasLength(1),
      );
      expect(backend.closedSessionIds, [id]);
    },
  );

  test(
    'shutdown retries a lost stop response without dropping its file claim',
    () async {
      final controller = container.read(sessionControllerProvider.notifier);
      final id = container.read(sessionControllerProvider).activeSessionId!;
      await controller.startSessionRecording(id);
      backend.loseStop = true;
      final result = await shutdown.shutdown();
      expect(result.unsafeToTerminate, isTrue);
      expect(library.activeClaims, hasLength(1));
      expect(backend.closedSessionIds, isEmpty);
      final errorBefore = container.read(sessionControllerProvider).lastError;
      expect(await controller.stopSessionRecording(id), isNull);
      expect(container.read(sessionControllerProvider).lastError, errorBefore);
      backend.loseStop = false;
      await shutdown.settle();
      expect(library.activeClaims, isEmpty);
      expect(backend.closedSessionIds, [id]);
    },
  );
}
