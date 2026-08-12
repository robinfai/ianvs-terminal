import 'dart:async';
import 'dart:convert';
import 'dart:io' show FileSystemException;

import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/local_terminal_config_repository.dart';
import 'package:app/features/layout/local_terminal_layout_models.dart';
import 'package:app/features/layout/local_terminal_layout_repository.dart';
import 'package:app/features/persistence/versioned_document.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/preferences/app_preferences_repository.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/profiles/profile_repository.dart';
import 'package:app/features/recording/local_session_recording_repository.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_ports.dart';
import 'package:app/features/sessions/session_shutdown.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/ssh/ssh_feature_access.dart';
import 'package:app/platform/app_shutdown_coordinator.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;

import '../support/fake_pty_backend.dart';

Future<void> _waitForCondition({
  required bool Function() condition,
  required String description,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue, reason: 'Timed out waiting for $description.');
}

class _TestProfileRepository extends ProfileRepository {
  _TestProfileRepository(this._document);

  TerminalProfilesDocument _document;
  final List<TerminalProfilesDocument> savedDocuments = [];

  @override
  Future<TerminalProfilesDocument> load() async => _document;

  @override
  Future<void> save(TerminalProfilesDocument document) async {
    savedDocuments.add(document);
    _document = document;
  }
}

class _FailingOnceProfileRepository extends ProfileRepository {
  _FailingOnceProfileRepository(this._document);

  final TerminalProfilesDocument _document;
  int loadAttempts = 0;

  @override
  Future<TerminalProfilesDocument> load() async {
    loadAttempts += 1;
    if (loadAttempts == 1) {
      throw const FileSystemException('profiles unavailable');
    }
    return _document;
  }

  @override
  Future<void> save(TerminalProfilesDocument document) async {}
}

class _BlockingFailingProfileRepository extends ProfileRepository {
  final Completer<void> loadStarted = Completer<void>();
  final Completer<void> allowFailure = Completer<void>();
  int loadAttempts = 0;

  @override
  Future<TerminalProfilesDocument> load() async {
    loadAttempts += 1;
    if (!loadStarted.isCompleted) {
      loadStarted.complete();
    }
    await allowFailure.future;
    throw const FileSystemException('bootstrap profile load failed');
  }

  @override
  Future<void> save(TerminalProfilesDocument document) async {}
}

class _TestSessionController extends SessionController {
  @override
  SessionState build() {
    return SessionState.initial();
  }
}

class _BootstrapOverrideSessionController extends SessionController {
  _BootstrapOverrideSessionController(this.profileId);

  final String profileId;

  @override
  String? get bootstrapDefaultProfileIdOverride => profileId;
}

class _TestAppPreferencesRepository extends AppPreferencesRepository {
  _TestAppPreferencesRepository(this._document);

  TerminalAppPreferencesDocument? _document;
  int loadAttempts = 0;
  final List<TerminalAppPreferencesDocument> savedDocuments = [];

  @override
  Future<TerminalAppPreferencesDocument?> load() async {
    loadAttempts += 1;
    return _document;
  }

  @override
  Future<void> save(TerminalAppPreferencesDocument document) async {
    savedDocuments.add(document);
    _document = document;
  }
}

class _TestLocalTerminalConfigRepository extends LocalTerminalConfigRepository {
  _TestLocalTerminalConfigRepository(this._document);

  LocalTerminalConfigDocument? _document;
  final List<LocalTerminalConfigDocument> savedDocuments = [];

  @override
  Future<LocalTerminalConfigDocument?> load() async => _document;

  @override
  Future<void> save(LocalTerminalConfigDocument document) async {
    savedDocuments.add(document);
    _document = document;
  }
}

class _ThrowingLocalTerminalConfigRepository
    extends LocalTerminalConfigRepository {
  @override
  Future<LocalTerminalConfigDocument?> load() async {
    throw const FileSystemException('local config unavailable');
  }

  @override
  Future<void> save(LocalTerminalConfigDocument document) async {}
}

class _MissingPluginLocalTerminalConfigRepository
    extends LocalTerminalConfigRepository {
  @override
  Future<LocalTerminalConfigDocument?> load() async {
    throw MissingPluginException('test local path provider');
  }
}

class _MissingPluginApiTerminalConfigRepository
    extends TerminalConfigRepository {
  @override
  Future<LocalTerminalConfigDocument?> load() async {
    throw MissingPluginException('test API adapter');
  }

  @override
  Future<void> save(LocalTerminalConfigDocument document) async {}

  @override
  Future<LocalTerminalConfigDocument> update(
    LocalTerminalConfigDocument Function(LocalTerminalConfigDocument current)
    transform, {
    LocalTerminalConfigDocument fallback = const LocalTerminalConfigDocument(),
  }) async {
    throw MissingPluginException('test API adapter');
  }
}

class _TestLocalTerminalLayoutRepository extends LocalTerminalLayoutRepository {
  _TestLocalTerminalLayoutRepository(this.document);

  TerminalLayout? document;
  int loadAttempts = 0;
  final List<TerminalLayout> savedDocuments = [];

  @override
  Future<TerminalLayout?> load() async {
    loadAttempts += 1;
    return document;
  }

  @override
  Future<void> save(TerminalLayout workspace) async {
    savedDocuments.add(workspace);
    document = workspace;
  }
}

class _RevisionedTestTerminalLayoutRepository extends TerminalLayoutRepository {
  VersionedDocument<TerminalLayout?> document = const VersionedDocument(
    value: null,
    revision: 0,
  );
  final List<VersionedDocument<TerminalLayout>> savedDocuments = [];

  @override
  Future<TerminalLayout?> load() async => document.value;

  @override
  Future<VersionedDocument<TerminalLayout?>> loadVersioned() async => document;

  @override
  Future<void> save(TerminalLayout layout) async {
    throw StateError('Versioned writes are required by this test repository.');
  }

  @override
  Future<VersionedDocument<TerminalLayout>> saveVersioned(
    VersionedDocument<TerminalLayout> layout,
  ) async {
    if (layout.revision == null) {
      throw StateError('Missing Data API revision token.');
    }
    savedDocuments.add(layout);
    final saved = layout.withRevision((layout.revision ?? 0) + 1);
    document = saved;
    return saved;
  }
}

class _CorruptLocalTerminalLayoutRepository
    extends LocalTerminalLayoutRepository {
  int saveAttempts = 0;

  @override
  Future<TerminalLayout?> load() async {
    throw const FormatException('corrupt terminal layout');
  }

  @override
  Future<void> save(TerminalLayout workspace) async {
    saveAttempts += 1;
  }
}

class _EmptyLocalSessionRecordingRepository
    extends LocalSessionRecordingRepository {
  @override
  Future<LocalSessionRecordingRecoveryResult> recoverNativeRecordings() async {
    return const LocalSessionRecordingRecoveryResult(
      recoveredPaths: <String>[],
      pendingJobIds: <String>[],
      orphanPaths: <String>[],
      failures: <LocalSessionRecordingRecoveryFailure>[],
    );
  }
}

class _BlockingRecoveryRecordingRepository
    extends LocalSessionRecordingRepository {
  final Completer<void> recoveryStarted = Completer<void>();
  final Completer<void> allowRecovery = Completer<void>();
  int recoveryAttempts = 0;

  @override
  Future<LocalSessionRecordingRecoveryResult> recoverNativeRecordings() async {
    recoveryAttempts += 1;
    if (!recoveryStarted.isCompleted) {
      recoveryStarted.complete();
    }
    await allowRecovery.future;
    return const LocalSessionRecordingRecoveryResult(
      recoveredPaths: <String>[],
      pendingJobIds: <String>[],
      orphanPaths: <String>[],
      failures: <LocalSessionRecordingRecoveryFailure>[],
    );
  }
}

class _BlockingRepairLocalTerminalConfigRepository
    extends LocalTerminalConfigRepository {
  final Completer<void> repairStarted = Completer<void>();
  final Completer<void> allowRepair = Completer<void>();
  int repairWrites = 0;

  @override
  Future<LocalTerminalConfigDocument?> load() async {
    return const LocalTerminalConfigDocument(
      defaultProfileId: 'missing-profile',
      layout: LocalTerminalLayoutConfig(restoreLayout: false),
    );
  }

  @override
  Future<void> save(LocalTerminalConfigDocument document) async {
    repairWrites += 1;
    if (!repairStarted.isCompleted) {
      repairStarted.complete();
    }
    await allowRepair.future;
  }
}

class _EventfulPtyBackend
    implements
        PtySessionBackend,
        PtySessionConfigV1Backend,
        PtySessionFramePacketV1Backend,
        PtySessionRequestV1Backend {
  _EventfulPtyBackend(this._delegate);

  final FakePtyBackend _delegate;

  void enqueueEvent(String sessionId, Map<String, Object?> event) {
    _delegate.enqueueEvent(
      sessionId,
      PtyEvent(
        kind: event['kind']! as String,
        sessionId: sessionId,
        payload: (event['payload'] as Map?)?.cast<String, Object?>(),
      ),
    );
  }

  void enqueueExit(String sessionId, {int? code}) {
    enqueueEvent(sessionId, {
      'kind': 'exit',
      'session_id': int.parse(sessionId),
      'payload': code == null ? null : {'code': code},
    });
  }

  void setFrame(String sessionId, Map<String, Object?> frame) {
    _delegate.setFrame(sessionId, frame);
  }

  @override
  int ping() => _delegate.ping();

  String createSession(String sessionConfigJson) =>
      _delegate.createSession(sessionConfigJson);

  @override
  String createSessionV1(String sessionConfigV1Json) =>
      _delegate.createSessionV1(sessionConfigV1Json);

  @override
  void closeSession(String sessionId) => _delegate.closeSession(sessionId);

  @override
  List<PtyEvent> pollEvents(String sessionId) =>
      _delegate.pollEvents(sessionId);

  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
    int cellWidth = 0,
    int cellHeight = 0,
  }) => _delegate.resizeSession(
    sessionId,
    cols: cols,
    rows: rows,
    pixelWidth: pixelWidth,
    pixelHeight: pixelHeight,
    cellWidth: cellWidth,
    cellHeight: cellHeight,
  );

  @override
  void scrollViewport(String sessionId, int deltaLines) =>
      _delegate.scrollViewport(sessionId, deltaLines);

  @override
  void scrollViewportTo(String sessionId, int offset) =>
      _delegate.scrollViewportTo(sessionId, offset);

  @override
  void writeInput(String sessionId, List<int> bytes) =>
      _delegate.writeInput(sessionId, bytes);

  @override
  String? requestSessionV1Json(String sessionId, String requestV1Json) =>
      _delegate.requestSessionV1Json(sessionId, requestV1Json);

  @override
  Uint8List? takeFramePacketV1Protobuf(
    String sessionId, {
    required int? afterSequence,
  }) => _delegate.takeFramePacketV1Protobuf(
    sessionId,
    afterSequence: afterSequence,
  );
}

class _SshEventfulPtyBackend extends _EventfulPtyBackend
    implements PtySessionConfigV1Backend, PtyRuntimeCapabilityBackend {
  _SshEventfulPtyBackend(super.delegate);

  @override
  final PtyRuntimeCapabilities runtimeCapabilities =
      PtyRuntimeCapabilities.fromJson(<String, Object?>{
        'schema_version': 1,
        'runtime_contract': 'ianvs-runtime-contract-v1',
        'frame_schema_versions': <Object?>['terminal-frame-diff-v1'],
        'recording_schema_versions': <Object?>[],
        'features': <Object?>['session-config.json.v1', 'ssh-session.v1'],
      });

  @override
  String createSessionV1(String sessionConfigV1Json) {
    return _delegate.createSession(sessionConfigV1Json);
  }
}

class _CountingPtyBackend extends FakePtyBackend {
  int takeFrameDiffCalls = 0;
  int pollEventsCalls = 0;

  @override
  Uint8List? takeFramePacketV1Protobuf(
    String sessionId, {
    required int? afterSequence,
  }) {
    takeFrameDiffCalls += 1;
    return super.takeFramePacketV1Protobuf(
      sessionId,
      afterSequence: afterSequence,
    );
  }

  @override
  List<PtyEvent> pollEvents(String sessionId) {
    pollEventsCalls += 1;
    return super.pollEvents(sessionId);
  }
}

class _DelayedFramePtyBackend extends _CountingPtyBackend {
  _DelayedFramePtyBackend({this.revealOnRead = 3});

  final int revealOnRead;

  @override
  String createSession(String sessionConfigJson) {
    final sessionId = super.createSession(sessionConfigJson);
    setFrame(sessionId, {
      'rows': [
        {'index': 0, 'text': '', 'style_runs': const <Object?>[]},
      ],
      'cursor': {'row': 0, 'col': 0, 'visible': true},
      'selection': null,
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': [
        {'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
    });
    return sessionId;
  }

  @override
  Uint8List? takeFramePacketV1Protobuf(
    String sessionId, {
    required int? afterSequence,
  }) {
    final framePacket = super.takeFramePacketV1Protobuf(
      sessionId,
      afterSequence: afterSequence,
    );
    final reads = takeFrameDiffCalls;
    if (reads < revealOnRead) {
      setFrame(sessionId, {
        'rows': [
          {'index': 0, 'text': '', 'style_runs': const <Object?>[]},
        ],
        'cursor': {'row': 0, 'col': 0, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': [
          {'start': 0, 'end': 1},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
      });
    } else {
      setFrame(sessionId, {
        'rows': [
          {'index': 0, 'text': 'driver ready', 'style_runs': const <Object?>[]},
        ],
        'cursor': {'row': 0, 'col': 0, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': [
          {'start': 0, 'end': 1},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
      });
    }
    return framePacket;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'runtime provider teardown retries a temporarily busy native close',
    () async {
      final backend = FakePtyBackend();
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(backend),
          sessionPollingEnabledProvider.overrideWithValue(false),
          driverWarmUpRefreshEnabledProvider.overrideWithValue(false),
        ],
      );
      final runtime = container.read(terminalRuntimeControllerProvider);
      final sessionId = runtime.createSession(
        const terminal.TerminalSessionConfig(
          launch: terminal.TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      backend.failingCloseSessionIds.add(sessionId);

      // Riverpod invokes the provider's void onDispose callback only once.
      container.dispose();
      expect(runtime.hasSession(sessionId), isTrue);

      backend.failingCloseSessionIds.remove(sessionId);

      await _waitForCondition(
        description: 'provider-owned runtime autonomously retrying disposal',
        condition: () => !runtime.hasSession(sessionId),
      );
      expect(backend.closedSessionIds, contains(sessionId));
    },
  );

  test('runtime provider disposal starts ordered shared shutdown', () async {
    final backend = FakePtyBackend();
    final applicationGate = Completer<void>();
    final applicationStarted = Completer<void>();
    final shutdownCoordinator = AppShutdownCoordinator();
    shutdownCoordinator.registerTask('recording-layout-gate', () async {
      applicationStarted.complete();
      await applicationGate.future;
    });
    final container = ProviderContainer(
      overrides: [
        appShutdownCoordinatorProvider.overrideWithValue(shutdownCoordinator),
        ptySessionBackendProvider.overrideWithValue(backend),
        sessionPollingEnabledProvider.overrideWithValue(false),
        driverWarmUpRefreshEnabledProvider.overrideWithValue(false),
      ],
    );
    final runtime = container.read(terminalRuntimeControllerProvider);
    final sessionId = runtime.createSession(
      const terminal.TerminalSessionConfig(
        launch: terminal.TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );

    container.dispose();
    await applicationStarted.future;

    expect(shutdownCoordinator.hasStarted, isTrue);
    expect(runtime.hasSession(sessionId), isTrue);
    expect(backend.closedSessionIds, isEmpty);

    applicationGate.complete();
    final result = await shutdownCoordinator.settle();
    expect(result.failures, isEmpty);
    expect(runtime.hasSession(sessionId), isFalse);
    expect(backend.closedSessionIds, <String>[sessionId]);
  });

  test(
    'session provider disposal starts application before infrastructure',
    () async {
      final backend = FakePtyBackend();
      final applicationGate = Completer<void>();
      final applicationStarted = Completer<void>();
      var infrastructureStarted = false;
      final shutdownCoordinator = AppShutdownCoordinator();
      shutdownCoordinator
        ..registerTask('session-first-application-probe', () async {
          applicationStarted.complete();
          await applicationGate.future;
        })
        ..registerTask(
          'session-first-infrastructure-probe',
          () async {
            infrastructureStarted = true;
          },
          phase: AppShutdownPhase.infrastructure,
        );
      final container = ProviderContainer(
        overrides: [
          appShutdownCoordinatorProvider.overrideWithValue(shutdownCoordinator),
          ptySessionBackendProvider.overrideWithValue(backend),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              TerminalProfilesDocument(
                profiles: <TerminalProfile>[defaultTerminalProfile()],
              ),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            _TestLocalTerminalConfigRepository(
              const LocalTerminalConfigDocument(
                layout: LocalTerminalLayoutConfig(restoreLayout: false),
              ),
            ),
          ),
          localTerminalLayoutRepositoryProvider.overrideWithValue(
            _TestLocalTerminalLayoutRepository(null),
          ),
          localSessionRecordingRepositoryProvider.overrideWithValue(
            _EmptyLocalSessionRecordingRepository(),
          ),
          sessionPollingEnabledProvider.overrideWithValue(false),
        ],
      );
      final ready = Completer<void>();
      final subscription = container.listen<SessionState>(
        sessionControllerProvider,
        (previous, next) {
          if (next.isReady && !ready.isCompleted) {
            ready.complete();
          }
        },
        fireImmediately: true,
      );
      container.read(sessionControllerProvider.notifier);
      await ready.future;
      subscription.close();

      // Invalidate only the Session provider so it is deterministically the
      // first Ready-graph owner disposed; TerminalRuntime remains mounted.
      container.invalidate(sessionControllerProvider);
      await applicationStarted.future;

      expect(shutdownCoordinator.hasStarted, isTrue);
      expect(infrastructureStarted, isFalse);

      applicationGate.complete();
      final result = await shutdownCoordinator.settle();
      expect(result.failures, isEmpty);
      expect(infrastructureStarted, isTrue);
      container.dispose();
    },
  );

  test(
    'shutdown settles shared recording recovery bootstrap before infra',
    () async {
      final backend = FakePtyBackend();
      final recordingRepository = _BlockingRecoveryRecordingRepository();
      final shutdownCoordinator = AppShutdownCoordinator();
      var infrastructureStarted = false;
      shutdownCoordinator.registerTask(
        'bootstrap-recovery-infrastructure-probe',
        () async => infrastructureStarted = true,
        phase: AppShutdownPhase.infrastructure,
      );
      final container = ProviderContainer(
        overrides: [
          appShutdownCoordinatorProvider.overrideWithValue(shutdownCoordinator),
          ptySessionBackendProvider.overrideWithValue(backend),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              TerminalProfilesDocument(
                profiles: <TerminalProfile>[defaultTerminalProfile()],
              ),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            _TestLocalTerminalConfigRepository(
              const LocalTerminalConfigDocument(
                layout: LocalTerminalLayoutConfig(restoreLayout: false),
              ),
            ),
          ),
          localTerminalLayoutRepositoryProvider.overrideWithValue(
            _TestLocalTerminalLayoutRepository(null),
          ),
          localSessionRecordingRepositoryProvider.overrideWithValue(
            recordingRepository,
          ),
          sessionPollingEnabledProvider.overrideWithValue(false),
          driverWarmUpRefreshEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(sessionControllerProvider.notifier);
      await recordingRepository.recoveryStarted.future;

      var retryCompleted = false;
      final retry = controller.retryBootstrap().whenComplete(() {
        retryCompleted = true;
      });
      final shutdown = shutdownCoordinator.shutdown(bounded: false);

      expect(controller.isShuttingDown, isTrue);
      expect(retryCompleted, isFalse);
      expect(infrastructureStarted, isFalse);
      expect(controller.hasRuntimeEventSubscriptionForTesting, isFalse);
      expect(backend.lastCreatedSessionPayload, isNull);

      recordingRepository.allowRecovery.complete();
      await retry;
      final result = await shutdown;

      expect(result.failures, isEmpty);
      expect(infrastructureStarted, isTrue);
      expect(recordingRepository.recoveryAttempts, 1);
      expect(controller.hasRuntimeEventSubscriptionForTesting, isFalse);
      expect(backend.lastCreatedSessionPayload, isNull);
      final state = container.read(sessionControllerProvider);
      expect(state.isReady, isFalse);
      expect(state.tabs, isEmpty);
      expect(state.lastError, isNull);
    },
  );

  test(
    'shutdown settles an in-flight config repair before infra without publishing',
    () async {
      final backend = FakePtyBackend();
      final configRepository = _BlockingRepairLocalTerminalConfigRepository();
      final shutdownCoordinator = AppShutdownCoordinator();
      var infrastructureStarted = false;
      shutdownCoordinator.registerTask(
        'bootstrap-config-infrastructure-probe',
        () async => infrastructureStarted = true,
        phase: AppShutdownPhase.infrastructure,
      );
      final container = ProviderContainer(
        overrides: [
          appShutdownCoordinatorProvider.overrideWithValue(shutdownCoordinator),
          ptySessionBackendProvider.overrideWithValue(backend),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              TerminalProfilesDocument(
                profiles: <TerminalProfile>[defaultTerminalProfile()],
              ),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            configRepository,
          ),
          localTerminalLayoutRepositoryProvider.overrideWithValue(
            _TestLocalTerminalLayoutRepository(null),
          ),
          localSessionRecordingRepositoryProvider.overrideWithValue(
            _EmptyLocalSessionRecordingRepository(),
          ),
          sessionPollingEnabledProvider.overrideWithValue(false),
          driverWarmUpRefreshEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(sessionControllerProvider.notifier);
      await configRepository.repairStarted.future;

      final shutdown = shutdownCoordinator.shutdown(bounded: false);

      expect(controller.isShuttingDown, isTrue);
      expect(infrastructureStarted, isFalse);
      expect(controller.hasRuntimeEventSubscriptionForTesting, isFalse);
      expect(backend.lastCreatedSessionPayload, isNull);

      configRepository.allowRepair.complete();
      final result = await shutdown;

      expect(result.failures, isEmpty);
      expect(infrastructureStarted, isTrue);
      expect(configRepository.repairWrites, 1);
      expect(controller.hasRuntimeEventSubscriptionForTesting, isFalse);
      expect(backend.lastCreatedSessionPayload, isNull);
      final state = container.read(sessionControllerProvider);
      expect(state.isReady, isFalse);
      expect(state.tabs, isEmpty);
      expect(state.lastError, isNull);
    },
  );

  test(
    'bootstrap failure crossing shutdown is aggregated before infra without UI',
    () async {
      final backend = FakePtyBackend();
      final profileRepository = _BlockingFailingProfileRepository();
      final shutdownCoordinator = AppShutdownCoordinator();
      var infrastructureStarted = false;
      shutdownCoordinator.registerTask(
        'bootstrap-failure-infrastructure-probe',
        () async => infrastructureStarted = true,
        phase: AppShutdownPhase.infrastructure,
      );
      final container = ProviderContainer(
        overrides: [
          appShutdownCoordinatorProvider.overrideWithValue(shutdownCoordinator),
          ptySessionBackendProvider.overrideWithValue(backend),
          profileRepositoryProvider.overrideWithValue(profileRepository),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            _TestLocalTerminalConfigRepository(
              const LocalTerminalConfigDocument(
                layout: LocalTerminalLayoutConfig(restoreLayout: false),
              ),
            ),
          ),
          localTerminalLayoutRepositoryProvider.overrideWithValue(
            _TestLocalTerminalLayoutRepository(null),
          ),
          localSessionRecordingRepositoryProvider.overrideWithValue(
            _EmptyLocalSessionRecordingRepository(),
          ),
          sessionPollingEnabledProvider.overrideWithValue(false),
          driverWarmUpRefreshEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(sessionControllerProvider.notifier);
      await profileRepository.loadStarted.future;

      final shutdown = shutdownCoordinator.shutdown(bounded: false);

      expect(controller.isShuttingDown, isTrue);
      expect(infrastructureStarted, isFalse);
      expect(container.read(sessionControllerProvider).lastError, isNull);

      profileRepository.allowFailure.complete();
      final result = await shutdown;

      expect(infrastructureStarted, isTrue);
      expect(profileRepository.loadAttempts, 1);
      expect(result.failures, hasLength(1));
      final shutdownError = result.failures.single.error;
      expect(shutdownError, isA<SessionShutdownAggregateException>());
      final aggregate = shutdownError as SessionShutdownAggregateException;
      expect(aggregate.failures, hasLength(1));
      expect(
        aggregate.failures.single.resource,
        SessionShutdownResource.bootstrap,
      );
      expect(aggregate.failures.single.error, isA<FileSystemException>());
      expect(controller.hasRuntimeEventSubscriptionForTesting, isFalse);
      expect(backend.lastCreatedSessionPayload, isNull);
      final state = container.read(sessionControllerProvider);
      expect(state.isReady, isFalse);
      expect(state.tabs, isEmpty);
      expect(state.lastError, isNull);
    },
  );

  test('session controller publishes and dismisses runtime errors', () {
    final container = ProviderContainer(
      overrides: [
        sessionControllerProvider.overrideWith(_TestSessionController.new),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(sessionControllerProvider.notifier);

    controller.reportRuntimeError('ZMODEM transport failed');

    expect(
      container.read(sessionControllerProvider).lastError,
      'ZMODEM transport failed',
    );

    controller.dismissLastError();

    expect(container.read(sessionControllerProvider).lastError, isNull);
  });

  final defaultProfile = TerminalProfile(
    id: 'default',
    name: 'Local Shell',
    shell: '/bin/zsh',
  );
  final sshProfile = TerminalProfile(
    id: 'ssh',
    name: 'SSH',
    shell: '/usr/bin/ssh',
  );

  test('session lifecycle updates tabs and active session', () {
    final coreClient = FakePtyBackend();
    final container = ProviderContainer(
      overrides: [
        localSessionRecordingRepositoryProvider.overrideWithValue(
          _EmptyLocalSessionRecordingRepository(),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          _TestLocalTerminalConfigRepository(null),
        ),
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);

    expect(container.read(sessionControllerProvider).tabs, isEmpty);
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-1'));
    expect(container.read(sessionControllerProvider).tabs, hasLength(1));
    final first = container.read(sessionControllerProvider).activeSessionId;
    expect(first, isNotNull);

    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-2'));
    expect(container.read(sessionControllerProvider).tabs, hasLength(2));
    final second = container.read(sessionControllerProvider).activeSessionId;
    expect(second, isNotNull);
    expect(second, isNot(equals(first)));

    controller.activateSession(first!);
    expect(container.read(sessionControllerProvider).activeSessionId, first);

    unawaited(controller.closeSession(first));
    final afterCloseFirst = container.read(sessionControllerProvider);
    expect(afterCloseFirst.tabs, hasLength(1));
    expect(afterCloseFirst.activeSessionId, second);

    unawaited(controller.closeSession(second!));
    final afterCloseSecond = container.read(sessionControllerProvider);
    expect(afterCloseSecond.tabs, isEmpty);
    expect(afterCloseSecond.activeSessionId, isNull);
  });

  test('session activation updates runtime foreground refresh classes', () {
    final coreClient = FakePtyBackend();
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(sessionControllerProvider.notifier);
    final runtime = container.read(terminalRuntimeControllerProvider);

    controller.createSession(defaultTerminalProfile().copyWith(id: 'one'));
    final first = container.read(sessionControllerProvider).activeSessionId!;
    controller.createSession(defaultTerminalProfile().copyWith(id: 'two'));
    final second = container.read(sessionControllerProvider).activeSessionId!;

    expect(
      runtime.refreshPolicySnapshotFor(first).refreshClass,
      terminal.TerminalRefreshClass.background,
    );
    expect(
      runtime.refreshPolicySnapshotFor(second).refreshClass,
      terminal.TerminalRefreshClass.interactive,
    );

    controller.activateSession(first);

    expect(
      runtime.refreshPolicySnapshotFor(first).refreshClass,
      terminal.TerminalRefreshClass.interactive,
    );
    expect(
      runtime.refreshPolicySnapshotFor(second).refreshClass,
      terminal.TerminalRefreshClass.background,
    );
  });

  test(
    'activating a new session preserves existing background backoff',
    () async {
      final coreClient = FakePtyBackend();
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          sessionControllerProvider.overrideWith(_TestSessionController.new),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              const TerminalProfilesDocument(profiles: []),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          sessionPollingEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(sessionControllerProvider.notifier);
      final runtime = container.read(terminalRuntimeControllerProvider);

      controller.createSession(defaultTerminalProfile().copyWith(id: 'one'));
      final first = container.read(sessionControllerProvider).activeSessionId!;
      controller.createSession(defaultTerminalProfile().copyWith(id: 'two'));
      coreClient.clearFrame(first);

      runtime.refreshSession(first);
      await Future<void>.delayed(Duration.zero);
      runtime.refreshSession(first);
      await Future<void>.delayed(Duration.zero);
      expect(
        runtime.refreshPolicySnapshotFor(first).pumpMetrics.currentDelay,
        const Duration(milliseconds: 132),
      );

      controller.createSession(defaultTerminalProfile().copyWith(id: 'three'));

      expect(
        runtime.refreshPolicySnapshotFor(first).pumpMetrics.currentDelay,
        const Duration(milliseconds: 132),
        reason: 'unchanged background sessions must keep their backoff',
      );
    },
  );

  test('backend write failures surface in session state', () async {
    final coreClient = FakePtyBackend();
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-1'));
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    coreClient.failingOperations.add('writeInput');
    container
        .read(terminalRuntimeControllerProvider)
        .sendInput(sessionId, Uint8List.fromList(const <int>[0x41]));
    await Future<void>.delayed(Duration.zero);

    final state = container.read(sessionControllerProvider);
    expect(state.lastError, contains('writeInput'));
    expect(state.lastError, contains(sessionId));
    expect(state.lastError, contains('writeInput failed'));
    expect(coreClient.writes, isEmpty);
  });

  test('session creation failures surface in session state', () {
    final coreClient = FakePtyBackend()..failingOperations.add('createSession');
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);

    expect(
      () => controller.createSession(
        defaultTerminalProfile().copyWith(id: 'shell-1'),
      ),
      returnsNormally,
    );

    final state = container.read(sessionControllerProvider);
    expect(state.tabs, isEmpty);
    expect(state.activeSessionId, isNull);
    expect(state.lastError, contains('createSession'));
    expect(state.lastError, contains('createSession failed'));
  });

  test('reorderTab moves tabs without changing the active session', () {
    final coreClient = FakePtyBackend();
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-1'));
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-2'));
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-3'));

    final initialTabs = container.read(sessionControllerProvider).tabs;
    final first = initialTabs[0].sessionId;
    final second = initialTabs[1].sessionId;
    final third = initialTabs[2].sessionId;

    controller.activateSession(second);
    controller.reorderTab(oldIndex: 0, newIndex: 2);

    var state = container.read(sessionControllerProvider);
    expect(state.tabs.map((tab) => tab.sessionId), [second, third, first]);
    expect(state.activeSessionId, second);

    controller.reorderTab(oldIndex: 2, newIndex: 0);
    state = container.read(sessionControllerProvider);
    expect(state.tabs.map((tab) => tab.sessionId), [first, second, third]);
    expect(state.activeSessionId, second);

    controller.reorderTab(oldIndex: -1, newIndex: 2);
    expect(
      container
          .read(sessionControllerProvider)
          .tabs
          .map((tab) => tab.sessionId),
      [first, second, third],
    );
  });

  test('moveSessionToPane merges standalone tabs without restarting them', () {
    final coreClient = FakePtyBackend();
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    controller.createSession(defaultTerminalProfile().copyWith(id: 'left'));
    controller.createSession(defaultTerminalProfile().copyWith(id: 'right'));
    final initialState = container.read(sessionControllerProvider);
    final leftSessionId = initialState.tabs.first.sessionId;
    final rightSessionId = initialState.tabs.last.sessionId;

    expect(
      controller.moveSessionToPane(
        sourceSessionId: leftSessionId,
        targetSessionId: rightSessionId,
        axis: TerminalSplitAxis.horizontal,
        before: true,
      ),
      isTrue,
    );

    final mergedState = container.read(sessionControllerProvider);
    expect(mergedState.tabs, hasLength(1));
    expect(mergedState.activeSessionId, leftSessionId);
    final layout = mergedState.tabs.single.effectivePaneLayout;
    expect(layout.splitAxis, TerminalSplitAxis.horizontal);
    expect(layout.first!.pane!.sessionId, leftSessionId);
    expect(layout.second!.pane!.sessionId, rightSessionId);
    expect(
      mergedState.tabs.single.effectivePanes.map((pane) => pane.sessionId),
      [leftSessionId, rightSessionId],
    );
  });

  test('detachPaneToTab restores a split pane as a standalone tab', () {
    final coreClient = FakePtyBackend();
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    controller.createSession(defaultTerminalProfile().copyWith(id: 'one'));
    final detachedSessionId = container
        .read(sessionControllerProvider)
        .tabs
        .single
        .sessionId;
    controller.splitActiveSession(
      defaultTerminalProfile().copyWith(id: 'two'),
      TerminalSplitAxis.horizontal,
    );
    final retainedSessionId = container
        .read(sessionControllerProvider)
        .tabs
        .single
        .effectivePanes
        .firstWhere((pane) => pane.sessionId != detachedSessionId)
        .sessionId;

    expect(
      controller.detachPaneToTab(
        sessionId: detachedSessionId,
        insertionIndex: 0,
      ),
      isTrue,
    );

    final detachedState = container.read(sessionControllerProvider);
    expect(detachedState.tabs, hasLength(2));
    expect(detachedState.tabs.first.sessionId, detachedSessionId);
    expect(
      detachedState.tabs.first.effectivePanes.single.sessionId,
      detachedSessionId,
    );
    expect(
      detachedState.tabs.last.effectivePanes.single.sessionId,
      retainedSessionId,
    );
    expect(
      detachedState.tabs.map((tab) => tab.sessionId).toSet(),
      hasLength(2),
    );
    expect(detachedState.activeSessionId, detachedSessionId);
  });

  test('moveSessionToPane can reposition an existing split pane', () {
    final coreClient = FakePtyBackend();
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    controller.createSession(defaultTerminalProfile().copyWith(id: 'one'));
    controller.createSession(defaultTerminalProfile().copyWith(id: 'two'));
    final initialTabs = container.read(sessionControllerProvider).tabs;
    final movingSessionId = initialTabs.first.sessionId;
    final targetSessionId = initialTabs.last.sessionId;
    controller.moveSessionToPane(
      sourceSessionId: movingSessionId,
      targetSessionId: targetSessionId,
      axis: TerminalSplitAxis.horizontal,
      before: true,
    );

    expect(
      controller.moveSessionToPane(
        sourceSessionId: movingSessionId,
        targetSessionId: targetSessionId,
        axis: TerminalSplitAxis.vertical,
        before: false,
      ),
      isTrue,
    );

    final movedLayout = container
        .read(sessionControllerProvider)
        .tabs
        .single
        .effectivePaneLayout;
    expect(movedLayout.splitAxis, TerminalSplitAxis.vertical);
    expect(movedLayout.first!.pane!.sessionId, targetSessionId);
    expect(movedLayout.second!.pane!.sessionId, movingSessionId);
  });

  test('xterm sessions advertise 24-bit color support', () {
    final coreClient = FakePtyBackend();
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);

    controller.createSession(defaultTerminalProfile().copyWith(id: 'xterm'));

    expect(coreClient.lastCreatedSessionPayload!['launch'], {
      'program': defaultTerminalProfile().shell,
      'args': defaultTerminalProfile().args,
      'env': {'TERM': 'xterm-256color', 'COLORTERM': 'truecolor'},
      'cwd': defaultTerminalProfile().cwd,
    });
    expect(
      container
          .read(sessionControllerProvider)
          .tabs
          .single
          .profileSnapshot!
          .env,
      {'TERM': 'xterm-256color', 'COLORTERM': 'truecolor'},
    );
  });

  test('vt220 sessions keep a conservative terminal environment', () {
    final coreClient = FakePtyBackend();
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);

    controller.createSession(vt220TerminalProfile().copyWith(id: 'vt220'));

    expect(coreClient.lastCreatedSessionPayload!['launch'], {
      'program': vt220TerminalProfile().shell,
      'args': vt220TerminalProfile().args,
      'env': {'TERM': 'vt220'},
      'cwd': vt220TerminalProfile().cwd,
    });
  });

  test('closing inactive session keeps current active session', () {
    final coreClient = FakePtyBackend();
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);

    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-1'));
    final first = container.read(sessionControllerProvider).activeSessionId!;
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-2'));
    final second = container
        .read(sessionControllerProvider)
        .tabs
        .last
        .sessionId;
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-3'));
    final third = container.read(sessionControllerProvider).activeSessionId!;

    expect(third, isNotNull);
    expect(third, isNot(equals(first)));
    expect(third, isNot(equals(second)));

    controller.activateSession(first);
    expect(container.read(sessionControllerProvider).activeSessionId, first);

    unawaited(controller.closeSession(second));
    final afterCloseInactive = container.read(sessionControllerProvider);
    expect(afterCloseInactive.tabs, hasLength(2));
    expect(
      afterCloseInactive.tabs.any((tab) => tab.sessionId == second),
      isFalse,
    );
    expect(afterCloseInactive.activeSessionId, first);
  });

  test('splitActiveSession adds panes inside the active tab', () {
    final coreClient = FakePtyBackend();
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    final profile = defaultTerminalProfile().copyWith(id: 'shell-1');

    controller.createSession(profile);
    final firstSessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);

    final splitState = container.read(sessionControllerProvider);
    expect(splitState.tabs, hasLength(1));
    expect(splitState.tabs.single.effectivePanes, hasLength(2));
    expect(splitState.tabs.single.splitAxis, TerminalSplitAxis.horizontal);
    expect(splitState.activeSessionId, isNot(firstSessionId));
    expect(splitState.tabs.single.containsSession(firstSessionId), isTrue);
    expect(
      splitState.tabs.single.containsSession(splitState.activeSessionId!),
      isTrue,
    );
    expect(coreClient.lastCreatedSessionPayload!['launch'], {
      'program': profile.shell,
      'args': profile.args,
      'env': {'TERM': 'xterm-256color', 'COLORTERM': 'truecolor'},
      'cwd': profile.cwd,
    });

    final secondSessionId = splitState.activeSessionId!;
    controller.activateSession(firstSessionId);
    expect(
      container.read(sessionControllerProvider).activeSessionId,
      firstSessionId,
    );

    unawaited(controller.closeSession(firstSessionId));
    final afterCloseFirst = container.read(sessionControllerProvider);
    expect(afterCloseFirst.tabs, hasLength(1));
    expect(afterCloseFirst.tabs.single.effectivePanes, hasLength(1));
    expect(afterCloseFirst.activeSessionId, secondSessionId);

    unawaited(controller.closeSession(secondSessionId));
    final afterCloseSecond = container.read(sessionControllerProvider);
    expect(afterCloseSecond.tabs, isEmpty);
    expect(afterCloseSecond.activeSessionId, isNull);
  });

  test('reopenClosedPane restores the most recent pane in the active tab', () {
    final coreClient = FakePtyBackend();
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    final profile = defaultTerminalProfile().copyWith(id: 'shell-1');

    controller.createSession(profile);
    final firstSessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;
    controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);
    final closedSessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    unawaited(controller.closeSession(closedSessionId));

    final afterClose = container.read(sessionControllerProvider);
    expect(afterClose.activeSessionId, firstSessionId);
    expect(afterClose.tabs.single.effectivePanes, hasLength(1));
    expect(controller.canReopenClosedPane, isTrue);

    final reopenedSessionId = controller.reopenClosedPane();

    final reopenedState = container.read(sessionControllerProvider);
    final reopenedTab = reopenedState.tabs.single;
    expect(reopenedSessionId, isNotNull);
    expect(reopenedSessionId, isNot(closedSessionId));
    expect(reopenedState.activeSessionId, reopenedSessionId);
    expect(reopenedTab.effectivePanes, hasLength(2));
    expect(reopenedTab.containsSession(firstSessionId), isTrue);
    expect(reopenedTab.containsSession(reopenedSessionId!), isTrue);
    expect(reopenedTab.splitAxis, TerminalSplitAxis.horizontal);
    expect(controller.canReopenClosedPane, isFalse);
  });

  test('reopenClosedPane restores a closed split root pane', () {
    final coreClient = FakePtyBackend();
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    final profile = defaultTerminalProfile().copyWith(id: 'shell-1');

    controller.createSession(profile);
    final rootSessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;
    controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);
    final survivingSessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    controller.activateSession(rootSessionId);
    unawaited(controller.closeSession(rootSessionId));

    final afterRootClose = container.read(sessionControllerProvider);
    expect(afterRootClose.tabs, hasLength(1));
    expect(afterRootClose.tabs.single.sessionId, rootSessionId);
    expect(afterRootClose.tabs.single.effectivePanes, hasLength(1));
    expect(afterRootClose.tabs.single.containsSession(rootSessionId), isFalse);
    expect(afterRootClose.activeSessionId, survivingSessionId);
    expect(controller.canReopenClosedPane, isTrue);

    final reopenedSessionId = controller.reopenClosedPane();

    final reopenedState = container.read(sessionControllerProvider);
    final reopenedTab = reopenedState.tabs.single;
    expect(reopenedSessionId, isNotNull);
    expect(reopenedSessionId, isNot(rootSessionId));
    expect(reopenedState.activeSessionId, reopenedSessionId);
    expect(reopenedTab.effectivePanes, hasLength(2));
    expect(reopenedTab.containsSession(survivingSessionId), isTrue);
    expect(reopenedTab.containsSession(reopenedSessionId!), isTrue);
  });

  test('closeTab closes remaining pane after split root pane was closed', () {
    final coreClient = FakePtyBackend();
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    final profile = defaultTerminalProfile().copyWith(id: 'shell-1');

    controller.createSession(profile);
    final rootSessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;
    controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);
    final survivingSessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    controller.activateSession(rootSessionId);
    unawaited(controller.closeSession(rootSessionId));

    final afterRootClose = container.read(sessionControllerProvider);
    expect(afterRootClose.tabs.single.sessionId, rootSessionId);
    expect(afterRootClose.activeSessionId, survivingSessionId);

    unawaited(controller.closeTab(afterRootClose.tabs.single.sessionId));

    final afterCloseTab = container.read(sessionControllerProvider);
    expect(afterCloseTab.tabs, isEmpty);
    expect(afterCloseTab.activeSessionId, isNull);
  });

  test(
    'closeTab reconciles panes already closed when a later pane becomes busy',
    () async {
      final coreClient = FakePtyBackend();
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          sessionControllerProvider.overrideWith(_TestSessionController.new),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              const TerminalProfilesDocument(profiles: []),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(sessionControllerProvider.notifier);
      final runtime = container.read(terminalRuntimeControllerProvider);
      final profile = defaultTerminalProfile().copyWith(id: 'shell-1');

      controller.createSession(profile);
      final firstSessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;
      controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);
      final secondSessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;
      final tabSessionId = container
          .read(sessionControllerProvider)
          .tabs
          .single
          .sessionId;
      coreClient.failingCloseSessionIds.add(secondSessionId);

      expect(await controller.closeTab(tabSessionId), isFalse);

      final afterFailure = container.read(sessionControllerProvider);
      expect(afterFailure.tabs, hasLength(1));
      expect(afterFailure.tabs.single.effectivePanes, hasLength(1));
      expect(afterFailure.tabs.single.containsSession(firstSessionId), isFalse);
      expect(afterFailure.tabs.single.containsSession(secondSessionId), isTrue);
      expect(runtime.hasSession(firstSessionId), isFalse);
      expect(runtime.hasSession(secondSessionId), isTrue);
      expect(coreClient.closedSessionIds, <String>[firstSessionId]);

      coreClient.failingCloseSessionIds.clear();
      expect(await controller.closeTab(tabSessionId), isTrue);
      expect(container.read(sessionControllerProvider).tabs, isEmpty);
      expect(runtime.hasSession(secondSessionId), isFalse);
    },
  );

  test(
    'closing active pane in inactive split tab reassigns tab active pane',
    () {
      final coreClient = FakePtyBackend();
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          sessionControllerProvider.overrideWith(_TestSessionController.new),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              const TerminalProfilesDocument(profiles: []),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(sessionControllerProvider.notifier);
      final profile = defaultTerminalProfile().copyWith(id: 'shell-1');

      controller.createSession(profile);
      final foregroundSessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;
      controller.createSession(profile);
      final splitRootSessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;
      controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);
      final closingPaneSessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;

      controller.activateSession(foregroundSessionId);
      unawaited(controller.closeSession(closingPaneSessionId));

      final afterClose = container.read(sessionControllerProvider);
      final backgroundTab = afterClose.tabs.firstWhere(
        (tab) => tab.sessionId == splitRootSessionId,
      );
      expect(afterClose.activeSessionId, foregroundSessionId);
      expect(backgroundTab.effectivePanes, hasLength(1));
      expect(backgroundTab.containsSession(closingPaneSessionId), isFalse);
      expect(backgroundTab.activePaneSessionId, isNull);
      expect(backgroundTab.activeSessionId, splitRootSessionId);
    },
  );

  test('splitSession targets an inactive pane inside a split tab', () {
    final coreClient = FakePtyBackend();
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    final profile = defaultTerminalProfile().copyWith(id: 'shell-1');

    controller.createSession(profile);
    final firstSessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;
    controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);
    final secondSessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    controller.splitSession(
      firstSessionId,
      profile,
      TerminalSplitAxis.vertical,
    );

    final splitState = container.read(sessionControllerProvider);
    final newSessionId = splitState.activeSessionId!;
    final layout = splitState.tabs.single.effectivePaneLayout;
    expect(splitState.tabs, hasLength(1));
    expect(splitState.tabs.single.effectivePanes, hasLength(3));
    expect(secondSessionId, isNot(firstSessionId));
    expect(newSessionId, isNot(firstSessionId));
    expect(newSessionId, isNot(secondSessionId));
    expect(layout.splitAxis, TerminalSplitAxis.horizontal);
    expect(layout.first!.splitAxis, TerminalSplitAxis.vertical);
    expect(layout.first!.containsSession(firstSessionId), isTrue);
    expect(layout.first!.containsSession(newSessionId), isTrue);
    expect(layout.second!.pane!.sessionId, secondSessionId);
  });

  test('splitActiveSession supports nested mixed directions', () {
    final coreClient = FakePtyBackend();
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    final profile = defaultTerminalProfile().copyWith(id: 'shell-1');

    controller.createSession(profile);
    final firstSessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);
    final secondSessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    controller.splitActiveSession(profile, TerminalSplitAxis.vertical);

    final splitState = container.read(sessionControllerProvider);
    final tab = splitState.tabs.single;
    expect(tab.effectivePanes, hasLength(3));
    expect(tab.effectivePaneLayout.splitAxis, TerminalSplitAxis.horizontal);
    expect(
      tab.effectivePaneLayout.second!.splitAxis,
      TerminalSplitAxis.vertical,
    );
    expect(tab.containsSession(firstSessionId), isTrue);
    expect(tab.containsSession(secondSessionId), isTrue);
    expect(splitState.activeSessionId, isNot(firstSessionId));
    expect(splitState.activeSessionId, isNot(secondSessionId));

    unawaited(controller.closeSession(secondSessionId));
    final afterCloseNestedPane = container.read(sessionControllerProvider);
    expect(afterCloseNestedPane.tabs.single.effectivePanes, hasLength(2));
    expect(
      afterCloseNestedPane.tabs.single.effectivePaneLayout.splitAxis,
      TerminalSplitAxis.horizontal,
    );
  });

  test('resizePaneSplit targets an inactive split tab', () {
    final coreClient = FakePtyBackend();
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    final profile = defaultTerminalProfile().copyWith(id: 'shell-1');

    controller.createSession(profile);
    final firstSessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;
    controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);
    final splitLayoutId = container
        .read(sessionControllerProvider)
        .tabs
        .single
        .effectivePaneLayout
        .id;

    controller.createSession(profile);
    final activeOtherTabSessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    controller.resizePaneSplit(firstSessionId, splitLayoutId, 0.35);

    final resizedState = container.read(sessionControllerProvider);
    expect(resizedState.activeSessionId, activeOtherTabSessionId);
    expect(resizedState.tabs.first.effectivePaneLayout.ratio, 0.35);
    expect(resizedState.tabs.last.effectivePaneLayout.ratio, 0.5);
  });

  test('reopenClosedTab preserves nested pane layout shape', () {
    final coreClient = FakePtyBackend();
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    final profile = defaultTerminalProfile().copyWith(id: 'shell-1');

    controller.createSession(profile);
    controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);
    controller.splitActiveSession(profile, TerminalSplitAxis.vertical);

    final originalTab = container.read(sessionControllerProvider).tabs.single;
    controller.resizeActivePaneSplit(originalTab.effectivePaneLayout.id, 0.35);
    final resizedRoot = container
        .read(sessionControllerProvider)
        .tabs
        .single
        .effectivePaneLayout;
    controller.resizeActivePaneSplit(resizedRoot.second!.id, 0.65);
    final beforeClose = container.read(sessionControllerProvider);
    final activeBeforeClose = beforeClose.activeSessionId;

    unawaited(controller.closeTab(beforeClose.tabs.single.sessionId));
    expect(container.read(sessionControllerProvider).tabs, isEmpty);

    controller.reopenClosedTab();

    final reopenedState = container.read(sessionControllerProvider);
    final reopenedTab = reopenedState.tabs.single;
    final reopenedLayout = reopenedTab.effectivePaneLayout;
    expect(reopenedTab.effectivePanes, hasLength(3));
    expect(reopenedLayout.splitAxis, TerminalSplitAxis.horizontal);
    expect(reopenedLayout.ratio, 0.35);
    expect(reopenedLayout.second!.splitAxis, TerminalSplitAxis.vertical);
    expect(reopenedLayout.second!.ratio, 0.65);
    expect(reopenedState.activeSessionId, isNot(activeBeforeClose));
    expect(reopenedState.activeSessionId, reopenedLayout.second!.second!.id);
  });

  test('reopenClosedTab backgrounds every unselected recreated pane', () {
    final coreClient = FakePtyBackend();
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    final runtime = container.read(terminalRuntimeControllerProvider);
    final profile = defaultTerminalProfile().copyWith(id: 'shell-1');

    controller.createSession(profile);
    controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);
    unawaited(
      controller.closeTab(
        container.read(sessionControllerProvider).tabs.single.sessionId,
      ),
    );

    controller.reopenClosedTab();

    final reopenedState = container.read(sessionControllerProvider);
    final reopenedTab = reopenedState.tabs.single;
    final activeSessionId = reopenedState.activeSessionId!;
    final inactiveSessionIds = reopenedTab.effectivePanes
        .map((pane) => pane.sessionId)
        .where((sessionId) => sessionId != activeSessionId)
        .toList(growable: false);
    expect(inactiveSessionIds, hasLength(1));
    expect(
      runtime.refreshPolicySnapshotFor(activeSessionId).refreshClass,
      terminal.TerminalRefreshClass.interactive,
    );
    for (final sessionId in inactiveSessionIds) {
      expect(
        runtime.refreshPolicySnapshotFor(sessionId).refreshClass,
        terminal.TerminalRefreshClass.background,
      );
    }
  });

  test(
    'reopenClosedTab keeps the closed tab queued when session creation fails',
    () {
      final coreClient = FakePtyBackend();
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          sessionControllerProvider.overrideWith(_TestSessionController.new),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              const TerminalProfilesDocument(profiles: []),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(sessionControllerProvider.notifier);
      final profile = defaultTerminalProfile().copyWith(id: 'shell-1');

      controller.createSession(profile);
      final closedSessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;
      unawaited(controller.closeTab(closedSessionId));
      expect(container.read(sessionControllerProvider).tabs, isEmpty);
      expect(controller.canReopenClosedTab, isTrue);

      coreClient.failingOperations.add('createSession');
      controller.reopenClosedTab();

      expect(container.read(sessionControllerProvider).tabs, isEmpty);
      expect(controller.canReopenClosedTab, isTrue);
      expect(
        container.read(sessionControllerProvider).lastError,
        contains('createSession failed'),
      );

      coreClient.failingOperations.clear();
      controller.reopenClosedTab();

      expect(container.read(sessionControllerProvider).tabs, hasLength(1));
      expect(controller.canReopenClosedTab, isFalse);
    },
  );

  test('resizeActiveSession dedupes identical size requests', () {
    final coreBindings = FakePtyBackend();
    final coreClient = coreBindings;
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-1'));
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    controller.resizeActiveSession(const Size(640, 480), 2.0);
    expect(coreBindings.resizeCalls, hasLength(1));
    expect(
      coreBindings.resizeCalls.single,
      [int.parse(sessionId), 71, 26, 1280, 960],
      reason:
          'falls back to the default cell size before viewport metrics exist',
    );

    controller.resizeActiveSession(const Size(640, 480), 2.0);
    expect(
      coreBindings.resizeCalls,
      hasLength(1),
      reason: 'duplicate call skipped',
    );

    controller.resizeActiveSession(const Size(644, 480), 2.0);
    expect(
      coreBindings.resizeCalls,
      hasLength(2),
      reason: 'pixel-only viewport changes still update native pixel size',
    );
    expect(coreBindings.resizeCalls.last, [
      int.parse(sessionId),
      71,
      26,
      1288,
      960,
    ]);

    controller.resizeActiveSession(const Size(644, 480), 2.0);
    expect(
      coreBindings.resizeCalls,
      hasLength(2),
      reason: 'full metric duplicate skipped',
    );

    controller.resizeActiveSession(const Size(650, 480), 2.0);
    expect(coreBindings.resizeCalls, hasLength(3));

    final last = coreBindings.resizeCalls.last;
    expect(last[0], equals(int.parse(sessionId)));
    expect(last[1], greaterThan(0));
    expect(last[2], greaterThan(0));
    expect(last[3], greaterThan(0));
    expect(last[4], greaterThan(0));
  });

  test('resizeActiveSession uses the provided inner viewport size as-is', () {
    final coreBindings = FakePtyBackend();
    final coreClient = coreBindings;
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-1'));
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    controller.resizeActiveSession(const Size(1540, 1106), 2.0);

    expect(coreBindings.resizeCalls.single, [
      int.parse(sessionId),
      171,
      61,
      3080,
      2212,
    ]);
  });

  test(
    'resizeActiveSession prefers measured viewport cell size when available',
    () {
      final coreBindings = FakePtyBackend();
      final coreClient = coreBindings;
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          sessionControllerProvider.overrideWith(_TestSessionController.new),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              const TerminalProfilesDocument(profiles: []),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(sessionControllerProvider.notifier);
      controller.createSession(
        defaultTerminalProfile().copyWith(id: 'shell-1'),
      );
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;

      controller
          .viewportFor(sessionId)
          .updateMeasuredCellSize(const Size(10, 20));

      controller.resizeActiveSession(const Size(640, 480), 2.0);

      expect(coreBindings.resizeCalls, hasLength(1));
      expect(coreBindings.resizeCalls.single, [
        int.parse(sessionId),
        64,
        24,
        1280,
        960,
      ]);
    },
  );

  test('refreshing a session applies OSC window titles to the tab title', () {
    final coreBindings = FakePtyBackend();
    final coreClient = coreBindings;
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          _TestLocalTerminalConfigRepository(
            const LocalTerminalConfigDocument(
              clipboard: LocalTerminalClipboardConfig(
                osc52: LocalTerminalOsc52Policy.allow,
              ),
            ),
          ),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-1'));
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    coreBindings.setFrame(int.parse(sessionId), {
      'rows': [
        {
          'index': 0,
          'text': 'ianvs terminal ready',
          'style_runs': const <Object?>[],
        },
      ],
      'cursor': {'row': 0, 'col': 4, 'visible': true},
      'selection': null,
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': [
        {'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'window_title': 'Build Target',
    });

    controller.resizeActiveSession(const Size(640, 480), 1.0);

    expect(
      container.read(sessionControllerProvider).tabs.single.title,
      'Build Target',
    );
  });

  test('refreshing a session falls back to OSC icon names with UTF-8 text', () {
    final coreBindings = FakePtyBackend();
    final coreClient = coreBindings;
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          _TestLocalTerminalConfigRepository(
            const LocalTerminalConfigDocument(
              clipboard: LocalTerminalClipboardConfig(
                osc52: LocalTerminalOsc52Policy.allow,
              ),
            ),
          ),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-1'));
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    coreBindings.setFrame(int.parse(sessionId), {
      'rows': [
        {
          'index': 0,
          'text': 'ianvs terminal ready',
          'style_runs': const <Object?>[],
        },
      ],
      'cursor': {'row': 0, 'col': 4, 'visible': true},
      'selection': null,
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': [
        {'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'window_title': null,
      'window_icon_name': '构建目标',
    });

    controller.resizeActiveSession(const Size(640, 480), 1.0);

    expect(container.read(sessionControllerProvider).tabs.single.title, '构建目标');
  });

  test('inactive root pane OSC title does not replace active pane title', () {
    final coreBindings = FakePtyBackend();
    final coreClient = coreBindings;
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          _TestLocalTerminalConfigRepository(
            const LocalTerminalConfigDocument(
              layout: LocalTerminalLayoutConfig(restoreLayout: false),
            ),
          ),
        ),
        localTerminalLayoutRepositoryProvider.overrideWithValue(
          _TestLocalTerminalLayoutRepository(null),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    Map<String, Object?> frameWithTitle(String title) {
      return <String, Object?>{
        'rows': <Object?>[
          <String, Object?>{
            'index': 0,
            'text': title,
            'style_runs': const <Object?>[],
          },
        ],
        'cursor': <String, Object?>{
          'row': 0,
          'col': title.length,
          'visible': true,
        },
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': <Object?>[
          <String, Object?>{'start': 0, 'end': 1},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
        'window_title': title,
        'window_icon_name': null,
      };
    }

    final controller = container.read(sessionControllerProvider.notifier);
    final profile = defaultTerminalProfile().copyWith(id: 'shell-1');
    controller.createSession(profile);
    final rootSessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;
    controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);
    final activeSessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    coreBindings.setFrame(
      int.parse(activeSessionId),
      frameWithTitle('Active Pane'),
    );
    controller.resizeSession(activeSessionId, const Size(640, 480), 1.0);
    coreBindings.setFrame(int.parse(rootSessionId), frameWithTitle('Deploy'));
    controller.resizeSession(rootSessionId, const Size(640, 480), 1.0);

    final tab = container.read(sessionControllerProvider).tabs.single;
    expect(tab.activeSessionId, activeSessionId);
    expect(tab.activePane.title, 'Active Pane');
    expect(tab.paneFor(rootSessionId)?.title, 'Deploy');
  });

  testWidgets('terminal content preview follows active tab visible panes', (
    tester,
  ) async {
    final coreBindings = FakePtyBackend();
    final coreClient = coreBindings;
    final published = <({bool hasContent, String? preview})>[];
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          _TestLocalTerminalConfigRepository(
            const LocalTerminalConfigDocument(
              layout: LocalTerminalLayoutConfig(restoreLayout: false),
            ),
          ),
        ),
        localTerminalLayoutRepositoryProvider.overrideWithValue(
          _TestLocalTerminalLayoutRepository(null),
        ),
        sessionTerminalContentPublisherProvider.overrideWithValue(({
          required terminalHasVisibleContent,
          required terminalPreview,
        }) {
          published.add((
            hasContent: terminalHasVisibleContent,
            preview: terminalPreview,
          ));
        }),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    Map<String, Object?> frameWithText(String text) {
      return <String, Object?>{
        'rows': <Object?>[
          <String, Object?>{
            'index': 0,
            'text': text,
            'style_runs': const <Object?>[],
          },
        ],
        'cursor': <String, Object?>{
          'row': 0,
          'col': text.length,
          'visible': true,
        },
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': <Object?>[
          <String, Object?>{'start': 0, 'end': 1},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
        'window_title': null,
        'window_icon_name': null,
      };
    }

    final controller = container.read(sessionControllerProvider.notifier);
    final runtime = container.read(terminalRuntimeControllerProvider);
    final profile = defaultTerminalProfile().copyWith(id: 'shell-1');
    controller.createSession(profile);
    final rootSessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;
    controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);
    final activePaneSessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    coreBindings.setFrame(
      int.parse(activePaneSessionId),
      frameWithText('Active Pane'),
    );
    runtime.refreshSession(activePaneSessionId);
    await tester.pump();
    expect(published.last, (hasContent: true, preview: 'Active Pane'));

    coreBindings.setFrame(int.parse(rootSessionId), frameWithText('Deploy'));
    runtime.refreshSession(rootSessionId);
    await tester.pump();
    expect(published.last, (hasContent: true, preview: 'Active Pane'));

    coreBindings.setFrame(int.parse(activePaneSessionId), frameWithText('   '));
    runtime.refreshSession(activePaneSessionId);
    await tester.pump();
    expect(published.last, (hasContent: true, preview: 'Deploy'));

    controller.createSession(profile);
    final otherTabSessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;
    coreBindings.setFrame(
      int.parse(otherTabSessionId),
      frameWithText('Other Tab'),
    );
    runtime.refreshSession(otherTabSessionId);
    await tester.pump();
    expect(published.last, (hasContent: true, preview: 'Other Tab'));

    final publishCount = published.length;
    coreBindings.setFrame(
      int.parse(rootSessionId),
      frameWithText('Updated Deploy'),
    );
    runtime.refreshSession(rootSessionId);
    await tester.pump();
    expect(published, hasLength(publishCount));
  });

  testWidgets(
    'shell hook metadata updates per-session shell integration state',
    (tester) async {
      final bindings = _EventfulPtyBackend(FakePtyBackend());
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(bindings),
          sessionControllerProvider.overrideWith(_TestSessionController.new),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              const TerminalProfilesDocument(profiles: []),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          sessionPollingEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(sessionControllerProvider.notifier);
      controller.createSession(
        defaultTerminalProfile().copyWith(id: 'shell-1'),
      );
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;
      await tester.pump();

      bindings.setFrame(sessionId, <String, Object?>{
        'rows': <Object?>[],
        'cursor': <String, Object?>{'row': 0, 'col': 0, 'visible': true},
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': <Object?>[],
        'scrollback_offset': 0,
        'scrollback_max_offset': 40,
        'global_bottom_row': 100,
      });

      bindings.enqueueEvent(sessionId, {
        'kind': 'shell_hook',
        'payload': const <String, Object?>{
          'hook': 'command_finished',
          'command': 'git status',
          'pwd': '/tmp/project',
          'shell': 'zsh',
          'host': 'workstation.local',
          'user': 'dev',
          'exit_code': 0,
          'prompt_scrollback_offset': 12,
        },
      });
      bindings.enqueueEvent(sessionId, {
        'kind': 'shell_hook',
        'payload': const <String, Object?>{
          'hook': 'command_finished',
          'command': 'dart test',
          'cwd': '/tmp/project',
          'prompt_scrollback_offset': 36,
        },
      });

      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(sessionId);
      await tester.pump(const Duration(milliseconds: 40));

      final shellIntegration = container
          .read(sessionControllerProvider)
          .tabs
          .single
          .activePane
          .shellIntegration;
      expect(shellIntegration.currentDirectory, '/tmp/project');
      expect(shellIntegration.shell, 'zsh');
      expect(shellIntegration.hostname, 'workstation.local');
      expect(shellIntegration.username, 'dev');
      expect(shellIntegration.lastCommand, 'dart test');
      expect(shellIntegration.lastExitCode, 0);
      expect(shellIntegration.recentCommands, <String>[
        'dart test',
        'git status',
      ]);
      expect(shellIntegration.recentDirectories, <String>['/tmp/project']);
      expect(
        shellIntegration.promptMarks.map((mark) => mark.globalLine).toList(),
        <int>[64, 88],
      );
    },
  );

  testWidgets('OSC 1337 mark and integration version update shell state', (
    tester,
  ) async {
    final bindings = _EventfulPtyBackend(FakePtyBackend());
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(bindings),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    container
        .read(sessionControllerProvider.notifier)
        .createSession(defaultTerminalProfile().copyWith(id: 'osc1337-meta'));
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;
    await tester.pump();

    bindings.enqueueEvent(sessionId, {
      'kind': 'shell_command',
      'payload': const <String, Object?>{
        'source': 'osc1337',
        'eventType': 'integration_version',
        'version': '17',
        'shell': 'zsh',
      },
    });
    bindings.enqueueEvent(sessionId, {
      'kind': 'shell_command',
      'payload': const <String, Object?>{
        'source': 'osc1337',
        'eventType': 'mark',
        'cursorLine': 84,
      },
    });
    container.read(terminalRuntimeControllerProvider).refreshSession(sessionId);
    await tester.pump(const Duration(milliseconds: 40));

    final integration = container
        .read(sessionControllerProvider)
        .tabs
        .single
        .activePane
        .shellIntegration;
    expect(integration.shell, 'zsh');
    expect(integration.integrationVersion, '17');
    expect(integration.promptMarks, hasLength(1));
    expect(integration.promptMarks.single.globalLine, 84);
    expect(integration.promptMarks.single.cwd, isNull);
    expect(integration.recentCommands, isEmpty);
  });

  testWidgets(
    'OSC 1337 ReportVariable denies first then reports allowed product state',
    (tester) async {
      final fakeBackend = FakePtyBackend();
      final bindings = _EventfulPtyBackend(fakeBackend);
      final configRepository = _TestLocalTerminalConfigRepository(null);
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(bindings),
          sessionControllerProvider.overrideWith(_TestSessionController.new),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              const TerminalProfilesDocument(profiles: []),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            configRepository,
          ),
          sessionPollingEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(sessionControllerProvider.notifier);
      controller.createSession(
        defaultTerminalProfile().copyWith(
          id: 'osc1337-report-variable',
          name: 'Report profile',
        ),
      );
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;
      await tester.pump();

      bindings.enqueueEvent(sessionId, {
        'kind': 'shell_context',
        'payload': const <String, Object?>{
          'source': 'osc1337_current_dir',
          'cwd': '/product/current',
          'hostname': 'product.example',
          'username': 'alice',
        },
      });
      bindings.enqueueEvent(sessionId, {
        'kind': 'report_variable_request',
        'payload': const <String, Object?>{
          'source': 'iterm1337',
          'name': 'session.path',
          'value': '/native/stale',
        },
      });
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(sessionId);
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        ascii.decode(fakeBackend.writes.last),
        '\x1b]1337;ReportVariable=\x07',
      );

      await controller.setOsc1337ReportVariableDecision(
        'session.path',
        LocalTerminalReportVariablePolicy.allow,
      );
      expect(
        configRepository
            .savedDocuments
            .last
            .hostActions
            .osc1337ReportVariables['session.path'],
        LocalTerminalReportVariablePolicy.allow,
      );
      bindings.enqueueEvent(sessionId, {
        'kind': 'report_variable_request',
        'payload': const <String, Object?>{
          'source': 'iterm1337',
          'name': 'session.path',
          'value': '/native/stale',
        },
      });
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(sessionId);
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        ascii.decode(fakeBackend.writes.last),
        '\x1b]1337;ReportVariable=L3Byb2R1Y3QvY3VycmVudA==\x07',
      );

      await controller.setOsc1337ReportVariableDecision('session.path', null);
      expect(
        configRepository.savedDocuments.last.hostActions.osc1337ReportVariables,
        isEmpty,
      );
    },
  );

  testWidgets('frames without current global coordinates drop prompt marks', (
    tester,
  ) async {
    final bindings = _EventfulPtyBackend(FakePtyBackend());
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(bindings),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    controller.createSession(defaultTerminalProfile().copyWith(id: 'legacy'));
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;
    bindings.setFrame(sessionId, <String, Object?>{
      'rows': <Object?>[],
      'cursor': <String, Object?>{'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': <Object?>[],
      'scrollback_offset': 0,
      'scrollback_max_offset': 40,
    });

    bindings.enqueueEvent(sessionId, {
      'kind': 'shell_hook',
      'payload': const <String, Object?>{
        'hook': 'prompt_started',
        'prompt_scrollback_offset': 12,
      },
    });
    container.read(terminalRuntimeControllerProvider).refreshSession(sessionId);
    await tester.pump(const Duration(milliseconds: 40));

    final marks = container
        .read(sessionControllerProvider)
        .tabs
        .single
        .activePane
        .shellIntegration
        .promptMarks;
    expect(marks, isEmpty);
  });

  testWidgets('shell hook metadata switches to a matching profile', (
    tester,
  ) async {
    final defaultProfile = defaultTerminalProfile().copyWith(
      id: 'local',
      name: 'Local',
    );
    final rootProfile = defaultTerminalProfile().copyWith(
      id: 'root',
      name: 'Root Session',
      switchRules: const [
        TerminalProfileSwitchRule(
          kind: TerminalProfileSwitchRuleKind.username,
          pattern: 'root',
        ),
      ],
    );
    final bindings = _EventfulPtyBackend(FakePtyBackend());
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(bindings),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            TerminalProfilesDocument(profiles: [defaultProfile, rootProfile]),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          _TestLocalTerminalConfigRepository(
            const LocalTerminalConfigDocument(
              layout: LocalTerminalLayoutConfig(restoreLayout: false),
            ),
          ),
        ),
        localTerminalLayoutRepositoryProvider.overrideWithValue(
          _TestLocalTerminalLayoutRepository(null),
        ),
        localSessionRecordingRepositoryProvider.overrideWithValue(
          _EmptyLocalSessionRecordingRepository(),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionControllerProvider);
    await tester.pump(const Duration(milliseconds: 50));
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    bindings.enqueueEvent(sessionId, {
      'kind': 'shell_hook',
      'payload': const <String, Object?>{
        'hook': 'command_finished',
        'command': 'sudo -s',
        'user': 'root',
        'pwd': '/root',
      },
    });
    container.read(terminalRuntimeControllerProvider).refreshSession(sessionId);
    await tester.pump();

    final pane = container
        .read(sessionControllerProvider)
        .tabs
        .single
        .activePane;
    expect(pane.profileId, 'root');
    expect(pane.title, 'Root Session');
    expect(pane.profileSnapshot?.name, 'Root Session');
    expect(pane.shellIntegration.username, 'root');
  });

  testWidgets('automatic profile switching restores the baseline profile', (
    tester,
  ) async {
    final defaultProfile = defaultTerminalProfile().copyWith(
      id: 'local',
      name: 'Local',
    );
    final rootProfile = defaultTerminalProfile().copyWith(
      id: 'root',
      name: 'Root Session',
      switchRules: const [
        TerminalProfileSwitchRule(
          kind: TerminalProfileSwitchRuleKind.username,
          pattern: 'root',
        ),
      ],
    );
    final bindings = _EventfulPtyBackend(FakePtyBackend());
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(bindings),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            TerminalProfilesDocument(profiles: [defaultProfile, rootProfile]),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          _TestLocalTerminalConfigRepository(
            const LocalTerminalConfigDocument(
              layout: LocalTerminalLayoutConfig(restoreLayout: false),
            ),
          ),
        ),
        localTerminalLayoutRepositoryProvider.overrideWithValue(
          _TestLocalTerminalLayoutRepository(null),
        ),
        localSessionRecordingRepositoryProvider.overrideWithValue(
          _EmptyLocalSessionRecordingRepository(),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionControllerProvider);
    await tester.pump(const Duration(milliseconds: 50));
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    bindings.enqueueEvent(sessionId, {
      'kind': 'shell_hook',
      'payload': const <String, Object?>{
        'hook': 'command_finished',
        'command': 'sudo -s',
        'user': 'root',
        'pwd': '/root',
      },
    });
    container.read(terminalRuntimeControllerProvider).refreshSession(sessionId);
    await tester.pump();

    expect(
      container
          .read(sessionControllerProvider)
          .tabs
          .single
          .activePane
          .profileId,
      'root',
    );

    bindings.enqueueEvent(sessionId, {
      'kind': 'shell_hook',
      'payload': const <String, Object?>{
        'hook': 'command_finished',
        'command': 'exit',
        'user': 'dev',
        'pwd': '/Users/dev',
      },
    });
    container.read(terminalRuntimeControllerProvider).refreshSession(sessionId);
    await tester.pump();

    final pane = container
        .read(sessionControllerProvider)
        .tabs
        .single
        .activePane;
    expect(pane.profileId, 'local');
    expect(pane.title, 'Local');
    expect(pane.profileSnapshot?.name, 'Local');
    expect(pane.shellIntegration.username, 'dev');
  });

  testWidgets('automatic profile restore preserves split pane OSC metadata', (
    tester,
  ) async {
    final defaultProfile = defaultTerminalProfile().copyWith(
      id: 'local',
      name: 'Local',
    );
    final rootProfile = defaultTerminalProfile().copyWith(
      id: 'root',
      name: 'Root Session',
      switchRules: const [
        TerminalProfileSwitchRule(
          kind: TerminalProfileSwitchRuleKind.username,
          pattern: 'root',
        ),
      ],
    );
    final bindings = _EventfulPtyBackend(FakePtyBackend());
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(bindings),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            TerminalProfilesDocument(profiles: [defaultProfile, rootProfile]),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          _TestLocalTerminalConfigRepository(
            const LocalTerminalConfigDocument(
              layout: LocalTerminalLayoutConfig(restoreLayout: false),
            ),
          ),
        ),
        localTerminalLayoutRepositoryProvider.overrideWithValue(
          _TestLocalTerminalLayoutRepository(null),
        ),
        localSessionRecordingRepositoryProvider.overrideWithValue(
          _EmptyLocalSessionRecordingRepository(),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionControllerProvider);
    await tester.pump(const Duration(milliseconds: 50));
    final controller = container.read(sessionControllerProvider.notifier);
    controller.splitActiveSession(defaultProfile, TerminalSplitAxis.horizontal);
    await tester.pump();

    final targetSessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    void enqueue(String kind, Map<String, Object?> payload) {
      bindings.enqueueEvent(targetSessionId, {
        'kind': kind,
        'payload': payload,
      });
    }

    Future<void> flush() async {
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(targetSessionId);
      await tester.pump();
    }

    enqueue('session_badge', const <String, Object?>{'text': 'Deploy'});
    enqueue('session_tab_status', const <String, Object?>{
      'source': 'osc21337',
      'indicatorPresent': true,
      'indicator': '#ff9500',
      'statusPresent': true,
      'status': 'Working',
      'statusColorPresent': true,
      'statusColor': '#5f87ff',
    });
    enqueue('session_progress', const <String, Object?>{
      'source': 'osc9;4',
      'action': 'set',
      'state': 'normal',
      'percent': 30,
      'label': 'Deploy',
    });
    enqueue('session_progress', const <String, Object?>{
      'source': 'osc934',
      'named': true,
      'action': 'set',
      'id': 'build',
      'state': 'normal',
      'percent': 80,
      'label': 'Compile',
    });
    enqueue('session_notification', const <String, Object?>{
      'source': 'osc777',
      'title': 'Deploy done',
      'message': 'Inactive metadata should survive restore',
    });
    await flush();

    enqueue('shell_hook', const <String, Object?>{
      'hook': 'command_finished',
      'command': 'sudo -s',
      'user': 'root',
      'pwd': '/root',
    });
    await flush();
    expect(
      container
          .read(sessionControllerProvider)
          .tabs
          .single
          .paneFor(targetSessionId)!
          .profileId,
      'root',
    );

    enqueue('shell_hook', const <String, Object?>{
      'hook': 'command_finished',
      'command': 'exit',
      'user': 'dev',
      'pwd': '/Users/dev',
    });
    await flush();

    final pane = container
        .read(sessionControllerProvider)
        .tabs
        .single
        .paneFor(targetSessionId)!;
    expect(pane.profileId, 'local');
    expect(pane.oscBadge, 'Deploy');
    expect(pane.tabStatus.indicator, '#ff9500');
    expect(pane.tabStatus.status, 'Working');
    expect(pane.tabStatus.statusColor, '#5f87ff');
    expect(pane.progress?.label, 'Deploy');
    expect(pane.namedProgress['build']?.label, 'Compile');
    expect(pane.recentNotifications.single.title, 'Deploy done');
    expect(pane.shellIntegration.username, 'dev');
  });

  testWidgets(
    'shell context ignores OSC metadata when shell integration is disabled',
    (tester) async {
      final baseProfile = defaultTerminalProfile();
      final disabledProfile = baseProfile.copyWith(
        id: 'disabled',
        name: 'Disabled Integration',
        sessionConfig: baseProfile.sessionConfig.copyWith(
          shellIntegration: const terminal.TerminalShellIntegrationConfig(
            enabled: false,
          ),
        ),
      );
      final bindings = _EventfulPtyBackend(FakePtyBackend());
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(bindings),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              TerminalProfilesDocument(profiles: [disabledProfile]),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            _TestLocalTerminalConfigRepository(
              const LocalTerminalConfigDocument(
                layout: LocalTerminalLayoutConfig(restoreLayout: false),
              ),
            ),
          ),
          localTerminalLayoutRepositoryProvider.overrideWithValue(
            _TestLocalTerminalLayoutRepository(null),
          ),
          localSessionRecordingRepositoryProvider.overrideWithValue(
            _EmptyLocalSessionRecordingRepository(),
          ),
          sessionPollingEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionControllerProvider);
      await tester.pump(const Duration(milliseconds: 50));
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;

      bindings.enqueueEvent(sessionId, {
        'kind': 'shell_context',
        'payload': const <String, Object?>{
          'source': 'osc7',
          'cwd': '/tmp/project',
          'hostname': 'localhost',
          'username': 'dev',
        },
      });
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(sessionId);
      await tester.pump(const Duration(milliseconds: 40));

      final pane = container
          .read(sessionControllerProvider)
          .tabs
          .single
          .activePane;
      expect(pane.shellIntegration.currentDirectory, isNull);
      expect(pane.shellIntegration.hostname, isNull);
      expect(pane.shellIntegration.username, isNull);
    },
  );

  testWidgets(
    'shell context remote cwd does not trigger local directory profile switch',
    (tester) async {
      final localProfile = defaultTerminalProfile().copyWith(
        id: 'local',
        name: 'Local',
      );
      final projectProfile = defaultTerminalProfile().copyWith(
        id: 'project',
        name: 'Project',
        switchRules: const [
          TerminalProfileSwitchRule(
            kind: TerminalProfileSwitchRuleKind.directory,
            pattern: '/srv/app',
          ),
        ],
      );
      final bindings = _EventfulPtyBackend(FakePtyBackend());
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(bindings),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              TerminalProfilesDocument(
                profiles: [localProfile, projectProfile],
              ),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            _TestLocalTerminalConfigRepository(
              const LocalTerminalConfigDocument(
                layout: LocalTerminalLayoutConfig(restoreLayout: false),
              ),
            ),
          ),
          localTerminalLayoutRepositoryProvider.overrideWithValue(
            _TestLocalTerminalLayoutRepository(null),
          ),
          localSessionRecordingRepositoryProvider.overrideWithValue(
            _EmptyLocalSessionRecordingRepository(),
          ),
          sessionPollingEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionControllerProvider);
      await tester.pump(const Duration(milliseconds: 50));
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;

      bindings.enqueueEvent(sessionId, {
        'kind': 'shell_context',
        'payload': const <String, Object?>{
          'source': 'osc7',
          'cwd': '/srv/app',
          'hostname': 'remote.example',
          'username': 'deploy',
        },
      });
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(sessionId);
      await tester.pump(const Duration(milliseconds: 40));

      var pane = container
          .read(sessionControllerProvider)
          .tabs
          .single
          .activePane;
      expect(pane.profileId, 'local');
      expect(pane.shellIntegration.currentDirectory, '/srv/app');
      expect(pane.shellIntegration.hostname, 'remote.example');

      bindings.enqueueEvent(sessionId, {
        'kind': 'shell_context',
        'payload': const <String, Object?>{
          'source': 'osc7',
          'cwd': '/srv/app',
          'hostname': null,
          'username': null,
        },
      });
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(sessionId);
      await tester.pump();

      pane = container.read(sessionControllerProvider).tabs.single.activePane;
      expect(pane.profileId, 'project');
      expect(pane.shellIntegration.hostname, isNull);
      expect(pane.shellIntegration.username, isNull);
    },
  );

  testWidgets('shell command scrolled-out zones evict prompt marks', (
    tester,
  ) async {
    final bindings = _EventfulPtyBackend(FakePtyBackend());
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(bindings),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          _TestLocalTerminalConfigRepository(null),
        ),
        localTerminalLayoutRepositoryProvider.overrideWithValue(
          _TestLocalTerminalLayoutRepository(null),
        ),
        localSessionRecordingRepositoryProvider.overrideWithValue(
          _EmptyLocalSessionRecordingRepository(),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionControllerProvider);
    await tester.pump(const Duration(milliseconds: 50));
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    void enqueueShellCommand(Map<String, Object?> payload) {
      bindings.enqueueEvent(sessionId, {
        'kind': 'shell_command',
        'payload': payload,
      });
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(sessionId);
    }

    enqueueShellCommand(const <String, Object?>{
      'source': 'osc133',
      'eventType': 'prompt_start',
      'cursorLine': 42,
      'command': 'echo ok',
      'promptKind': 'initial',
      'aid': 'outer-shell',
    });
    await tester.pump();
    enqueueShellCommand(const <String, Object?>{
      'source': 'osc133',
      'eventType': 'semantic_prompt',
      'cursorLine': 43,
      'promptKind': 'secondary',
      'aid': 'outer-shell',
      'freshLine': false,
    });
    await tester.pump();
    enqueueShellCommand(const <String, Object?>{
      'source': 'osc133',
      'eventType': 'zone_opened',
      'zoneId': 7,
      'zoneType': 'prompt',
      'absRowStart': 42,
    });
    await tester.pump();
    enqueueShellCommand(const <String, Object?>{
      'source': 'osc133',
      'eventType': 'prompt_start',
      'cursorLine': 84,
      'command': 'echo next',
    });
    await tester.pump();
    enqueueShellCommand(const <String, Object?>{
      'source': 'osc133',
      'eventType': 'zone_opened',
      'zoneId': 8,
      'zoneType': 'prompt',
      'absRowStart': 84,
    });
    await tester.pump();

    var pane = container.read(sessionControllerProvider).tabs.single.activePane;
    expect(pane.shellIntegration.promptMarks.map((mark) => mark.zoneId), <int?>[
      7,
      8,
    ]);
    expect(pane.shellIntegration.promptMarks.first.promptKind, 'initial');
    expect(pane.shellIntegration.promptMarks.first.aid, 'outer-shell');

    enqueueShellCommand(const <String, Object?>{
      'source': 'osc133',
      'eventType': 'zone_scrolled_out',
      'zoneId': 7,
      'zoneType': 'prompt',
    });
    await tester.pump();

    pane = container.read(sessionControllerProvider).tabs.single.activePane;
    expect(pane.shellIntegration.promptMarks, hasLength(1));
    expect(pane.shellIntegration.promptMarks.single.zoneId, 8);
    expect(pane.shellIntegration.promptMarks.single.globalLine, 84);
  });

  testWidgets('shell context user variables are allowlisted and capped', (
    tester,
  ) async {
    final bindings = _EventfulPtyBackend(FakePtyBackend());
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(bindings),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          _TestLocalTerminalConfigRepository(null),
        ),
        localTerminalLayoutRepositoryProvider.overrideWithValue(
          _TestLocalTerminalLayoutRepository(null),
        ),
        localSessionRecordingRepositoryProvider.overrideWithValue(
          _EmptyLocalSessionRecordingRepository(),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionControllerProvider);
    await tester.pump(const Duration(milliseconds: 50));
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    bindings.enqueueEvent(sessionId, {
      'kind': 'shell_user_var',
      'payload': <String, Object?>{
        'name': 'IANVS_TEST',
        'value': '${List.filled(600, 'x').join()}\u0007',
      },
    });
    bindings.enqueueEvent(sessionId, {
      'kind': 'shell_user_var',
      'payload': const <String, Object?>{
        'name': 'SECRET_TOKEN',
        'value': 'do-not-store',
      },
    });
    container.read(terminalRuntimeControllerProvider).refreshSession(sessionId);
    await tester.pump();

    final userVariables = container
        .read(sessionControllerProvider)
        .tabs
        .single
        .activePane
        .shellIntegration
        .userVariables;
    expect(userVariables.keys, <String>['IANVS_TEST']);
    expect(userVariables['IANVS_TEST']!.runes, hasLength(512));
    expect(userVariables['IANVS_TEST'], isNot(contains('\u0007')));
  });

  testWidgets(
    'OSC notification metadata is bounded and duplicate bursts collapse',
    (tester) async {
      final bindings = _EventfulPtyBackend(FakePtyBackend());
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(bindings),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            _TestLocalTerminalConfigRepository(null),
          ),
          localTerminalLayoutRepositoryProvider.overrideWithValue(
            _TestLocalTerminalLayoutRepository(null),
          ),
          localSessionRecordingRepositoryProvider.overrideWithValue(
            _EmptyLocalSessionRecordingRepository(),
          ),
          sessionPollingEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionControllerProvider);
      await tester.pump(const Duration(milliseconds: 50));
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;

      for (var index = 0; index < 2; index += 1) {
        bindings.enqueueEvent(sessionId, {
          'kind': 'session_notification',
          'payload': <String, Object?>{
            'source': 'osc777',
            'title': '${List.filled(200, 'T').join()}\u0007',
            'message': '${List.filled(600, 'M').join()}\u0007',
          },
        });
      }
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(sessionId);
      await tester.pump();

      final notifications = container
          .read(sessionControllerProvider)
          .tabs
          .single
          .activePane
          .recentNotifications;
      expect(notifications, hasLength(1));
      expect(notifications.single.count, 2);
      expect(notifications.single.title.runes, hasLength(160));
      expect(notifications.single.message.runes, hasLength(512));
      expect(notifications.single.title, isNot(contains('\u0007')));
    },
  );

  testWidgets('OSC 99 updates and closes a correlated notification', (
    tester,
  ) async {
    final bindings = _EventfulPtyBackend(FakePtyBackend());
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(bindings),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          _TestLocalTerminalConfigRepository(null),
        ),
        localTerminalLayoutRepositoryProvider.overrideWithValue(
          _TestLocalTerminalLayoutRepository(null),
        ),
        localSessionRecordingRepositoryProvider.overrideWithValue(
          _EmptyLocalSessionRecordingRepository(),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionControllerProvider);
    await tester.pump(const Duration(milliseconds: 50));
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    bindings.enqueueEvent(sessionId, {
      'kind': 'session_notification',
      'payload': <String, Object?>{
        'source': 'osc99',
        'action': 'show',
        'id': 'build',
        'title': 'Building',
        'message': 'Started',
        'application': 'buildctl',
        'types': <String>['deploy'],
        'expiresAfterMs': 500,
        'reportActivation': true,
        'reportClose': true,
        'buttons': <String>['Approve', 'Retry'],
      },
    });
    bindings.enqueueEvent(sessionId, {
      'kind': 'session_notification',
      'payload': <String, Object?>{
        'source': 'osc99',
        'action': 'update',
        'id': 'build',
        'title': 'Building',
        'message': 'Complete',
        'application': 'buildctl',
        'types': <String>['deploy'],
        'expiresAfterMs': 1000,
        'reportActivation': true,
        'reportClose': true,
        'buttons': <String>['Approve', 'Retry'],
      },
    });
    container.read(terminalRuntimeControllerProvider).refreshSession(sessionId);
    await tester.pump();

    var notifications = container
        .read(sessionControllerProvider)
        .tabs
        .single
        .activePane
        .recentNotifications;
    expect(notifications, hasLength(1));
    expect(notifications.single.identifier, 'build');
    expect(notifications.single.message, 'Complete');
    expect(notifications.single.applicationName, 'buildctl');
    expect(notifications.single.notificationTypes, <String>['deploy']);
    expect(notifications.single.expiresAfterMs, 1000);
    expect(notifications.single.reportActivation, isTrue);
    expect(notifications.single.reportClose, isTrue);
    expect(notifications.single.buttons, <String>['Approve', 'Retry']);

    bindings.enqueueEvent(sessionId, {
      'kind': 'session_notification',
      'payload': <String, Object?>{
        'source': 'osc99',
        'action': 'close',
        'id': 'build',
        'title': '',
        'message': '',
      },
    });
    container.read(terminalRuntimeControllerProvider).refreshSession(sessionId);
    await tester.pump();

    notifications = container
        .read(sessionControllerProvider)
        .tabs
        .single
        .activePane
        .recentNotifications;
    expect(notifications, isEmpty);
  });

  testWidgets(
    'OSC 99 reports only current explicit notification interactions',
    (tester) async {
      final backend = FakePtyBackend();
      final bindings = _EventfulPtyBackend(backend);
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(bindings),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            _TestLocalTerminalConfigRepository(null),
          ),
          localTerminalLayoutRepositoryProvider.overrideWithValue(
            _TestLocalTerminalLayoutRepository(null),
          ),
          localSessionRecordingRepositoryProvider.overrideWithValue(
            _EmptyLocalSessionRecordingRepository(),
          ),
          sessionPollingEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionControllerProvider);
      await tester.pump(const Duration(milliseconds: 50));
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;
      bindings.enqueueEvent(sessionId, {
        'kind': 'session_notification',
        'payload': <String, Object?>{
          'source': 'osc99',
          'action': 'show',
          'id': 'deploy-1',
          'title': 'Deploy ready',
          'message': 'Choose an action',
          'reportActivation': true,
          'reportClose': true,
          'buttons': <String>['\u0085', 'Retry'],
        },
      });
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(sessionId);
      await tester.pump();
      backend.writes.clear();
      backend.writesBySession.clear();

      final controller = container.read(sessionControllerProvider.notifier);
      final offeredNotification = container
          .read(sessionControllerProvider)
          .tabs
          .single
          .activePane
          .recentNotifications
          .single;
      expect(offeredNotification.buttons, <String>['', 'Retry']);
      expect(
        controller.reportSessionNotificationAction(
          sessionId,
          offeredNotification,
        ),
        isTrue,
      );
      expect(
        controller.reportSessionNotificationAction(
          sessionId,
          offeredNotification,
          buttonNumber: 2,
        ),
        isTrue,
      );
      expect(
        controller.reportSessionNotificationAction(
          sessionId,
          offeredNotification,
          buttonNumber: 3,
        ),
        isFalse,
      );
      expect(backend.writes.map(utf8.decode), <String>[
        '\x1b]99;i=deploy-1;\x1b\\',
        '\x1b]99;i=deploy-1;2\x1b\\',
      ]);
      expect(
        backend.writesBySession.map((entry) => entry.key),
        everyElement(sessionId),
      );

      bindings.enqueueEvent(sessionId, {
        'kind': 'session_notification',
        'payload': <String, Object?>{
          'source': 'osc99',
          'action': 'update',
          'id': 'deploy-1',
          'title': 'Deploy changed',
          'message': 'New action set',
          'reportActivation': true,
          'reportClose': true,
          'buttons': <String>['Open logs'],
        },
      });
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(sessionId);
      await tester.pump();
      expect(
        controller.reportSessionNotificationAction(
          sessionId,
          offeredNotification,
        ),
        isFalse,
      );
      final updatedNotification = container
          .read(sessionControllerProvider)
          .tabs
          .single
          .activePane
          .recentNotifications
          .single;
      expect(
        controller.dismissSessionNotification(sessionId, updatedNotification),
        isTrue,
      );
      expect(
        utf8.decode(backend.writes.last),
        '\x1b]99;i=deploy-1:p=close;\x1b\\',
      );
      expect(
        backend.jsonRequests.any(
          (request) =>
              request['kind'] == 'terminal.dismiss_osc99_notification' &&
              request['id'] == 'deploy-1',
        ),
        isTrue,
      );
      expect(
        container
            .read(sessionControllerProvider)
            .tabs
            .single
            .activePane
            .recentNotifications,
        isEmpty,
      );
      expect(
        controller.reportSessionNotificationAction(
          sessionId,
          updatedNotification,
        ),
        isFalse,
      );

      bindings.enqueueEvent(sessionId, {
        'kind': 'session_notification',
        'payload': <String, Object?>{
          'source': 'osc99',
          'action': 'show',
          'id': 'bad?id',
          'title': 'Invalid identifier',
          'message': '',
          'reportActivation': true,
        },
      });
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(sessionId);
      await tester.pump();
      final invalidIdentifierNotification = container
          .read(sessionControllerProvider)
          .tabs
          .single
          .activePane
          .recentNotifications
          .single;
      expect(invalidIdentifierNotification.identifier, isNull);
      expect(
        controller.reportSessionNotificationAction(
          sessionId,
          invalidIdentifierNotification,
        ),
        isFalse,
      );
      expect(backend.writes, hasLength(3));
    },
  );

  testWidgets('OSC 99 positive expiry removes product notification state', (
    tester,
  ) async {
    final backend = FakePtyBackend();
    final bindings = _EventfulPtyBackend(backend);
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(bindings),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          _TestLocalTerminalConfigRepository(null),
        ),
        localTerminalLayoutRepositoryProvider.overrideWithValue(
          _TestLocalTerminalLayoutRepository(null),
        ),
        localSessionRecordingRepositoryProvider.overrideWithValue(
          _EmptyLocalSessionRecordingRepository(),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionControllerProvider);
    await tester.pump(const Duration(milliseconds: 50));
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;
    bindings.enqueueEvent(sessionId, {
      'kind': 'session_notification',
      'payload': <String, Object?>{
        'source': 'osc99',
        'action': 'show',
        'id': 'short',
        'title': 'Short lived',
        'message': '',
        'expiresAfterMs': 20,
        'reportClose': true,
      },
    });
    container.read(terminalRuntimeControllerProvider).refreshSession(sessionId);
    await tester.pump();
    expect(
      container
          .read(sessionControllerProvider)
          .tabs
          .single
          .activePane
          .recentNotifications,
      hasLength(1),
    );

    await tester.pump(const Duration(milliseconds: 25));
    expect(
      container
          .read(sessionControllerProvider)
          .tabs
          .single
          .activePane
          .recentNotifications,
      isEmpty,
    );
    expect(
      backend.writes.map(utf8.decode),
      contains('\x1b]99;i=short:p=close;\x1b\\'),
    );
    expect(
      backend.jsonRequests.any(
        (request) =>
            request['kind'] == 'terminal.dismiss_osc99_notification' &&
            request['id'] == 'short',
      ),
      isTrue,
    );
  });

  testWidgets('RIS clears protocol session state and restores profile baseline', (
    tester,
  ) async {
    final localProfile = defaultTerminalProfile().copyWith(
      id: 'local',
      name: 'Local Profile',
    );
    final remoteProfile = defaultTerminalProfile().copyWith(
      id: 'remote',
      name: 'Remote Profile',
      switchRules: const <TerminalProfileSwitchRule>[
        TerminalProfileSwitchRule(
          kind: TerminalProfileSwitchRuleKind.hostname,
          pattern: 'remote.example',
        ),
      ],
    );
    final bindings = _EventfulPtyBackend(FakePtyBackend());
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(bindings),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            TerminalProfilesDocument(profiles: [localProfile, remoteProfile]),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          _TestLocalTerminalConfigRepository(null),
        ),
        localTerminalLayoutRepositoryProvider.overrideWithValue(
          _TestLocalTerminalLayoutRepository(null),
        ),
        localSessionRecordingRepositoryProvider.overrideWithValue(
          _EmptyLocalSessionRecordingRepository(),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionControllerProvider);
    await tester.pump(const Duration(milliseconds: 50));
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    void enqueue(String kind, [Map<String, Object?>? payload]) {
      bindings.enqueueEvent(sessionId, {'kind': kind, 'payload': ?payload});
    }

    Map<String, Object?> frameWithTitle(String? title) => <String, Object?>{
      'rows': <Map<String, Object?>>[
        <String, Object?>{
          'index': 0,
          'text': 'ready',
          'style_runs': const <Object?>[],
        },
      ],
      'cursor': <String, Object?>{'row': 0, 'col': 0, 'visible': true},
      'selection': null,
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': <Map<String, Object?>>[
        <String, Object?>{'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'window_title': title,
      'window_icon_name': null,
    };

    Future<void> flush() async {
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(sessionId);
      await tester.pump();
    }

    bindings.setFrame(sessionId, frameWithTitle('Remote build'));
    enqueue('shell_hook', const <String, Object?>{
      'hook': 'command_finished',
      'command': 'dart test',
      'pwd': '/srv/project',
      'hostname': 'remote.example',
      'username': 'deploy',
      'shell': '/bin/zsh',
      'exitCode': 0,
    });
    enqueue('shell_command', const <String, Object?>{
      'source': 'osc133',
      'eventType': 'prompt_start',
      'cursorLine': 12,
    });
    enqueue('shell_user_var', const <String, Object?>{
      'name': 'IANVS_ENV',
      'value': 'staging',
    });
    enqueue('session_badge', const <String, Object?>{'text': 'Deploy'});
    enqueue('session_tab_status', const <String, Object?>{
      'source': 'osc21337',
      'indicatorPresent': true,
      'indicator': '#ff9500',
      'statusPresent': true,
      'status': 'Working',
      'statusColorPresent': true,
      'statusColor': '#5f87ff',
    });
    enqueue('session_progress', const <String, Object?>{
      'source': 'osc9;4',
      'action': 'set',
      'state': 'normal',
      'percent': 30,
    });
    enqueue('session_progress', const <String, Object?>{
      'source': 'ianvs_osc934',
      'named': true,
      'action': 'set',
      'id': 'build',
      'state': 'normal',
      'percent': 80,
    });
    enqueue('session_notification', const <String, Object?>{
      'source': 'osc777',
      'title': 'Deploy',
      'message': 'Done',
    });
    await flush();
    // Profile switching can intentionally set its own title in the same batch;
    // a subsequent OSC 2 frame remains authoritative until RIS.
    await flush();

    var pane = container.read(sessionControllerProvider).tabs.single.activePane;
    expect(pane.profileId, 'remote');
    expect(pane.title, 'Remote build');
    expect(pane.shellIntegration.currentDirectory, '/srv/project');
    expect(pane.shellIntegration.hostname, 'remote.example');
    expect(pane.shellIntegration.username, 'deploy');
    expect(pane.shellIntegration.shell, '/bin/zsh');
    expect(pane.shellIntegration.lastCommand, 'dart test');
    expect(pane.shellIntegration.recentCommands, isNotEmpty);
    expect(pane.shellIntegration.recentDirectories, isNotEmpty);
    expect(pane.shellIntegration.promptMarks, isNotEmpty);
    expect(pane.shellIntegration.userVariables['IANVS_ENV'], 'staging');
    expect(pane.oscBadge, 'Deploy');
    expect(pane.progress, isNotNull);
    expect(pane.namedProgress, contains('build'));
    expect(pane.recentNotifications, isNotEmpty);

    enqueue('session_tab_status', const <String, Object?>{
      'source': 'osc21337',
      'indicatorPresent': false,
      'statusPresent': false,
      'statusColorPresent': true,
      'statusColor': null,
    });
    await flush();
    pane = container.read(sessionControllerProvider).tabs.single.activePane;
    expect(pane.tabStatus.indicator, '#ff9500');
    expect(pane.tabStatus.status, 'Working');
    expect(pane.tabStatus.statusColor, isNull);

    // Create live grace timers, then prove RIS cancels them and also discards a
    // same-batch progress update queued before the reset event.
    enqueue('session_progress', const <String, Object?>{
      'source': 'osc9;4',
      'action': 'clear',
      'state': 'hidden',
    });
    enqueue('session_progress', const <String, Object?>{
      'source': 'ianvs_osc934',
      'named': true,
      'action': 'remove',
      'id': 'build',
    });
    await flush();

    bindings.setFrame(sessionId, frameWithTitle(null));
    enqueue('session_progress', const <String, Object?>{
      'source': 'osc9;4',
      'action': 'set',
      'state': 'normal',
      'percent': 99,
    });
    enqueue('session_reset');
    await flush();
    await tester.pump(const Duration(milliseconds: 1500));

    pane = container.read(sessionControllerProvider).tabs.single.activePane;
    expect(pane.profileId, 'local');
    expect(pane.profileSnapshot?.id, 'local');
    expect(pane.title, 'Local Profile');
    expect(pane.shellIntegration.currentDirectory, isNull);
    expect(pane.shellIntegration.hostname, isNull);
    expect(pane.shellIntegration.username, isNull);
    expect(pane.shellIntegration.shell, '/bin/zsh');
    expect(pane.shellIntegration.lastCommand, isNull);
    expect(pane.shellIntegration.lastExitCode, isNull);
    expect(pane.shellIntegration.recentCommands, isEmpty);
    expect(pane.shellIntegration.recentDirectories, isEmpty);
    expect(pane.shellIntegration.promptMarks, isEmpty);
    expect(pane.shellIntegration.userVariables, isEmpty);
    expect(pane.oscBadge, isNull);
    expect(pane.tabStatus.isEmpty, isTrue);
    expect(pane.progress, isNull);
    expect(pane.namedProgress, isEmpty);
    expect(pane.recentNotifications, isEmpty);
  });

  testWidgets('OSC progress and badge metadata update pane state', (
    tester,
  ) async {
    final bindings = _EventfulPtyBackend(FakePtyBackend());
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(bindings),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          _TestLocalTerminalConfigRepository(null),
        ),
        localTerminalLayoutRepositoryProvider.overrideWithValue(
          _TestLocalTerminalLayoutRepository(null),
        ),
        localSessionRecordingRepositoryProvider.overrideWithValue(
          _EmptyLocalSessionRecordingRepository(),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionControllerProvider);
    await tester.pump(const Duration(milliseconds: 50));
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    void enqueue(String kind, Map<String, Object?> payload) {
      bindings.enqueueEvent(sessionId, {'kind': kind, 'payload': payload});
    }

    Future<void> flush() async {
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(sessionId);
      await tester.pump();
    }

    enqueue('session_progress', const <String, Object?>{
      'source': 'osc9;4',
      'action': 'set',
      'state': 'normal',
      'percent': 150,
      'label': 'Primary',
    });
    enqueue('session_progress', const <String, Object?>{
      'source': 'osc934',
      'named': true,
      'action': 'set',
      'id': 'build',
      'state': 'normal',
      'percent': 80,
      'label': 'Compile',
    });
    enqueue('session_badge', <String, Object?>{
      'text': '${List.filled(120, 'B').join()}\u0007',
    });
    await flush();

    var pane = container.read(sessionControllerProvider).tabs.single.activePane;
    expect(pane.progress!.percent, 100);
    expect(pane.namedProgress.keys, <String>['build']);
    expect(pane.namedProgress['build']!.label, 'Compile');
    expect(pane.oscBadge!.runes, hasLength(80));
    expect(pane.oscBadge, isNot(contains('\u0007')));

    final sharedPrefix = List.filled(80, 'x').join();
    final firstLongId = '${sharedPrefix}first';
    final secondLongId = '${sharedPrefix}second';
    enqueue('session_progress', <String, Object?>{
      'source': 'ianvs_osc934',
      'named': true,
      'action': 'set',
      'id': firstLongId,
      'state': 'normal',
      'percent': 10,
    });
    enqueue('session_progress', <String, Object?>{
      'source': 'ianvs_osc934',
      'named': true,
      'action': 'set',
      'id': secondLongId,
      'state': 'normal',
      'percent': 20,
    });
    await flush();

    pane = container.read(sessionControllerProvider).tabs.single.activePane;
    expect(pane.namedProgress[firstLongId]?.percent, 10);
    expect(pane.namedProgress[secondLongId]?.percent, 20);

    enqueue('session_progress', <String, Object?>{
      'source': 'ianvs_osc934',
      'named': true,
      'action': 'remove',
      'id': firstLongId,
    });
    await flush();

    pane = container.read(sessionControllerProvider).tabs.single.activePane;
    expect(pane.namedProgress[firstLongId]?.action, 'complete');
    expect(pane.namedProgress[secondLongId]?.percent, 20);

    enqueue('session_progress', const <String, Object?>{
      'source': 'osc934',
      'named': true,
      'action': 'remove',
      'id': 'build',
    });
    enqueue('session_badge', const <String, Object?>{'text': ''});
    await flush();

    pane = container.read(sessionControllerProvider).tabs.single.activePane;
    expect(pane.namedProgress['build']?.action, 'complete');
    expect(pane.namedProgress['build']?.state, 'complete');
    expect(pane.namedProgress['build']?.percent, 100);
    expect(pane.oscBadge, isNull);

    enqueue('session_progress', const <String, Object?>{
      'source': 'osc934',
      'named': true,
      'action': 'set',
      'id': 'test',
      'state': 'normal',
      'percent': 50,
    });
    enqueue('session_progress', const <String, Object?>{
      'source': 'osc934',
      'named': true,
      'action': 'remove_all',
    });
    enqueue('session_progress', const <String, Object?>{
      'source': 'osc9;4',
      'action': 'clear',
      'state': 'hidden',
    });
    await flush();

    pane = container.read(sessionControllerProvider).tabs.single.activePane;
    expect(pane.namedProgress['test']?.action, 'complete');
    expect(pane.namedProgress['test']?.state, 'complete');
    expect(pane.progress?.action, 'complete');
    expect(pane.progress?.state, 'complete');

    await tester.pump(const Duration(milliseconds: 1500));

    pane = container.read(sessionControllerProvider).tabs.single.activePane;
    expect(pane.progress, isNull);
    expect(pane.namedProgress, isEmpty);
  });

  testWidgets(
    'OSC indeterminate progress displays state instead of zero percent',
    (tester) async {
      final bindings = _EventfulPtyBackend(FakePtyBackend());
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(bindings),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            _TestLocalTerminalConfigRepository(null),
          ),
          localTerminalLayoutRepositoryProvider.overrideWithValue(
            _TestLocalTerminalLayoutRepository(null),
          ),
          localSessionRecordingRepositoryProvider.overrideWithValue(
            _EmptyLocalSessionRecordingRepository(),
          ),
          sessionPollingEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionControllerProvider);
      await tester.pump(const Duration(milliseconds: 50));
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;

      bindings.enqueueEvent(sessionId, {
        'kind': 'session_progress',
        'payload': const <String, Object?>{
          'source': 'osc9;4',
          'action': 'set',
          'state': 'indeterminate',
        },
      });
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(sessionId);
      await tester.pump();

      final pane = container
          .read(sessionControllerProvider)
          .tabs
          .single
          .activePane;
      expect(pane.progress?.percent, isNull);
      expect(pane.progress?.displayLabel, 'PROGRESS INDETERMINATE');
    },
  );

  test(
    'resize events update the terminal session before resizing the macOS window',
    () async {
      final bindings = _EventfulPtyBackend(FakePtyBackend());
      final coreClient = bindings;
      double? windowWidthDelta;
      double? windowHeightDelta;

      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          sessionWindowResizeProvider.overrideWithValue(({
            required heightDelta,
            required widthDelta,
          }) async {
            windowWidthDelta = widthDelta;
            windowHeightDelta = heightDelta;
          }),
          sessionControllerProvider.overrideWith(_TestSessionController.new),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              const TerminalProfilesDocument(profiles: []),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          sessionPollingEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(sessionControllerProvider.notifier);
      controller.createSession(
        defaultTerminalProfile().copyWith(id: 'shell-1'),
      );
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;
      bindings.enqueueEvent(sessionId, {
        'kind': 'resize',
        'session_id': int.parse(sessionId),
        'payload': {'rows': 30, 'cols': 100},
      });

      controller.resizeActiveSession(const Size(640, 480), 1.0);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bindings._delegate.resizeCalls, hasLength(2));
      expect(bindings._delegate.resizeCalls.last, [
        int.parse(sessionId),
        100,
        30,
        900,
        540,
      ]);
      expect(windowWidthDelta, 260.0);
      expect(windowHeightDelta, 60.0);
    },
  );

  test(
    'resize events honor measured cell size before resizing the macOS window',
    () async {
      final bindings = _EventfulPtyBackend(FakePtyBackend());
      final coreClient = bindings;
      double? windowWidthDelta;
      double? windowHeightDelta;

      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          sessionWindowResizeProvider.overrideWithValue(({
            required heightDelta,
            required widthDelta,
          }) async {
            windowWidthDelta = widthDelta;
            windowHeightDelta = heightDelta;
          }),
          sessionControllerProvider.overrideWith(_TestSessionController.new),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              const TerminalProfilesDocument(profiles: []),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          sessionPollingEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(sessionControllerProvider.notifier);
      controller.createSession(
        defaultTerminalProfile().copyWith(id: 'shell-1'),
      );
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;
      controller
          .viewportFor(sessionId)
          .updateMeasuredCellSize(const Size(10, 20));
      bindings.enqueueEvent(sessionId, {
        'kind': 'resize',
        'session_id': int.parse(sessionId),
        'payload': {'rows': 30, 'cols': 100},
      });

      controller.resizeActiveSession(const Size(640, 480), 1.0);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bindings._delegate.resizeCalls, hasLength(2));
      expect(bindings._delegate.resizeCalls.last, [
        int.parse(sessionId),
        100,
        30,
        1000,
        600,
      ]);
      expect(windowWidthDelta, 360.0);
      expect(windowHeightDelta, 120.0);
    },
  );

  test('OSC 52 copy events decode UTF-8 clipboard text', () async {
    final bindings = _EventfulPtyBackend(FakePtyBackend());
    final coreClient = bindings;
    String copied = '';

    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionClipboardCopyProvider.overrideWithValue((text) async {
          copied = text;
        }),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          _TestLocalTerminalConfigRepository(
            const LocalTerminalConfigDocument(
              clipboard: LocalTerminalClipboardConfig(
                osc52: LocalTerminalOsc52Policy.allow,
              ),
            ),
          ),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-1'));
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;
    bindings.enqueueEvent(sessionId, {
      'kind': 'clipboard_copy',
      'session_id': int.parse(sessionId),
      'payload': {
        'selection': 'c',
        'data': base64.encode(utf8.encode('复制内容🌟')),
      },
    });

    controller.resizeActiveSession(const Size(640, 480), 1.0);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(copied, '复制内容🌟');
  });

  test('OSC 52 copy events respect disabled local clipboard policy', () async {
    final bindings = _EventfulPtyBackend(FakePtyBackend());
    final coreClient = bindings;
    String copied = '';

    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionClipboardCopyProvider.overrideWithValue((text) async {
          copied = text;
        }),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          _TestLocalTerminalConfigRepository(
            const LocalTerminalConfigDocument(
              clipboard: LocalTerminalClipboardConfig(
                osc52: LocalTerminalOsc52Policy.disabled,
              ),
            ),
          ),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-1'));
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;
    bindings.enqueueEvent(sessionId, {
      'kind': 'clipboard_copy',
      'session_id': int.parse(sessionId),
      'payload': {
        'selection': 'c',
        'data': base64.encode(utf8.encode('blocked')),
      },
    });

    controller.resizeActiveSession(const Size(640, 480), 1.0);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(copied, isEmpty);
  });

  test(
    'OSC 52 copy events fail closed when local config loading fails',
    () async {
      final bindings = _EventfulPtyBackend(FakePtyBackend());
      final coreClient = bindings;
      String copied = '';

      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          sessionClipboardCopyProvider.overrideWithValue((text) async {
            copied = text;
          }),
          sessionControllerProvider.overrideWith(_TestSessionController.new),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              const TerminalProfilesDocument(profiles: []),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            _ThrowingLocalTerminalConfigRepository(),
          ),
          sessionPollingEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      final clipboardEvents = <terminal.TerminalSessionClipboardEvent>[];
      final subscription = container
          .read(terminalRuntimeControllerProvider)
          .runtimeSignals
          .map((signal) => signal.payload)
          .where((event) => event is terminal.TerminalSessionClipboardEvent)
          .cast<terminal.TerminalSessionClipboardEvent>()
          .listen(clipboardEvents.add);
      addTearDown(subscription.cancel);

      final controller = container.read(sessionControllerProvider.notifier);
      controller.createSession(
        defaultTerminalProfile().copyWith(id: 'shell-1'),
      );
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;
      bindings.enqueueEvent(sessionId, {
        'kind': 'clipboard_copy',
        'session_id': int.parse(sessionId),
        'payload': {
          'selection': 'c',
          'data': base64.encode(utf8.encode('blocked by config failure')),
        },
      });

      controller.resizeActiveSession(const Size(640, 480), 1.0);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(copied, isEmpty);
      expect(
        clipboardEvents.single.decision,
        terminal.TerminalClipboardDecision.blocked,
      );
    },
  );

  test('OSC 52 paste requests reply with UTF-8 clipboard content', () async {
    final fakeBindings = FakePtyBackend();
    final bindings = _EventfulPtyBackend(fakeBindings);
    final coreClient = bindings;

    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionClipboardPasteProvider.overrideWithValue(() async => '你好, 世界🌟'),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          _TestLocalTerminalConfigRepository(
            const LocalTerminalConfigDocument(
              clipboard: LocalTerminalClipboardConfig(
                osc52: LocalTerminalOsc52Policy.allow,
              ),
            ),
          ),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-1'));
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;
    bindings.enqueueEvent(sessionId, {
      'kind': 'clipboard_paste_request',
      'session_id': int.parse(sessionId),
      'payload': {'selection': 'c'},
    });

    controller.resizeActiveSession(const Size(640, 480), 1.0);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final expectedPayload = base64.encode(utf8.encode('你好, 世界🌟'));
    expect(
      fakeBindings.writes.last,
      utf8.encode('\x1B]52;c;$expectedPayload\x07'),
    );
  });

  test('OSC 52 profile policy prompts before paste requests', () async {
    final fakeBindings = FakePtyBackend();
    final bindings = _EventfulPtyBackend(fakeBindings);
    final coreClient = bindings;
    final promptRequests = <SessionOsc52PromptRequest>[];

    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionClipboardPasteProvider.overrideWithValue(() async {
          return 'profile paste';
        }),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          _TestLocalTerminalConfigRepository(
            const LocalTerminalConfigDocument(),
          ),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);
    container.read(sessionOsc52PromptControllerProvider).setHandler((
      request,
    ) async {
      promptRequests.add(request);
      return false;
    });

    final controller = container.read(sessionControllerProvider.notifier);
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-1'));
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;
    bindings.enqueueEvent(sessionId, {
      'kind': 'clipboard_paste_request',
      'session_id': int.parse(sessionId),
      'payload': {'selection': 'c'},
    });

    controller.resizeActiveSession(const Size(640, 480), 1.0);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(promptRequests, hasLength(1));
    expect(
      promptRequests.single.operation,
      terminal.TerminalClipboardOperation.pasteRequest,
    );
    expect(promptRequests.single.textPreview, 'profile paste');
    expect(fakeBindings.writes, isEmpty);
  });

  test(
    'OSC 52 paste requests respect disabled local clipboard policy',
    () async {
      final fakeBindings = FakePtyBackend();
      final bindings = _EventfulPtyBackend(fakeBindings);
      final coreClient = bindings;
      var pasteReadCount = 0;

      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          sessionClipboardPasteProvider.overrideWithValue(() async {
            pasteReadCount += 1;
            return 'blocked paste';
          }),
          sessionControllerProvider.overrideWith(_TestSessionController.new),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              const TerminalProfilesDocument(profiles: []),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            _TestLocalTerminalConfigRepository(
              const LocalTerminalConfigDocument(
                clipboard: LocalTerminalClipboardConfig(
                  osc52: LocalTerminalOsc52Policy.disabled,
                ),
              ),
            ),
          ),
          sessionPollingEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(sessionControllerProvider.notifier);
      controller.createSession(
        defaultTerminalProfile().copyWith(id: 'shell-1'),
      );
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;
      bindings.enqueueEvent(sessionId, {
        'kind': 'clipboard_paste_request',
        'session_id': int.parse(sessionId),
        'payload': {'selection': 'c'},
      });

      controller.resizeActiveSession(const Size(640, 480), 1.0);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(pasteReadCount, 0);
      expect(fakeBindings.writes, isEmpty);
    },
  );

  test('OSC 52 ask policy prompts before clipboard access', () async {
    final fakeBindings = FakePtyBackend();
    final bindings = _EventfulPtyBackend(fakeBindings);
    final coreClient = bindings;
    final promptRequests = <SessionOsc52PromptRequest>[];
    String copied = '';
    var pasteReadCount = 0;

    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionClipboardCopyProvider.overrideWithValue((text) async {
          copied = text;
        }),
        sessionClipboardPasteProvider.overrideWithValue(() async {
          pasteReadCount += 1;
          return 'denied paste';
        }),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(const TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          _TestLocalTerminalConfigRepository(
            const LocalTerminalConfigDocument(
              clipboard: LocalTerminalClipboardConfig(
                osc52: LocalTerminalOsc52Policy.ask,
              ),
            ),
          ),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);
    container.read(sessionOsc52PromptControllerProvider).setHandler((
      request,
    ) async {
      promptRequests.add(request);
      return request.operation == terminal.TerminalClipboardOperation.copy;
    });

    final controller = container.read(sessionControllerProvider.notifier);
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-1'));
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;
    bindings.enqueueEvent(sessionId, {
      'kind': 'clipboard_copy',
      'session_id': int.parse(sessionId),
      'payload': {
        'selection': 'c',
        'data': base64.encode(utf8.encode('prompted copy')),
      },
    });
    bindings.enqueueEvent(sessionId, {
      'kind': 'clipboard_paste_request',
      'session_id': int.parse(sessionId),
      'payload': {'selection': 'c'},
    });

    controller.resizeActiveSession(const Size(640, 480), 1.0);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(
      promptRequests.map((request) => request.operation),
      <terminal.TerminalClipboardOperation>[
        terminal.TerminalClipboardOperation.copy,
        terminal.TerminalClipboardOperation.pasteRequest,
      ],
    );
    expect(promptRequests[0].sessionId, sessionId);
    expect(promptRequests[0].selection, 'c');
    expect(promptRequests[0].textPreview, 'prompted copy');
    expect(promptRequests[0].characterCount, 13);
    expect(promptRequests[0].byteCount, 13);
    expect(promptRequests[1].sessionId, sessionId);
    expect(promptRequests[1].selection, 'c');
    expect(promptRequests[1].textPreview, 'denied paste');
    expect(promptRequests[1].characterCount, 12);
    expect(promptRequests[1].byteCount, 12);
    expect(copied, 'prompted copy');
    expect(pasteReadCount, 1);
    expect(fakeBindings.writes, isEmpty);
  });

  test(
    'OSC 5522 multi-MIME clipboard uses product providers and allow policy',
    () async {
      final fakeBindings = FakePtyBackend();
      final bindings = _EventfulPtyBackend(fakeBindings);
      final written = <terminal.TerminalClipboardMimeItem>[];
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(bindings),
          sessionClipboardMimeWriteProvider.overrideWithValue((items) async {
            written.addAll(items);
          }),
          sessionClipboardMimeReadProvider.overrideWithValue((types) async {
            return <terminal.TerminalClipboardMimeItem>[
              terminal.TerminalClipboardMimeItem(
                mimeType: 'image/png',
                bytes: Uint8List.fromList(<int>[9, 8, 7]),
              ),
            ];
          }),
          sessionClipboardMimeTypeListProvider.overrideWithValue(
            () async => <String>['image/png', 'text/plain'],
          ),
          sessionControllerProvider.overrideWith(_TestSessionController.new),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              const TerminalProfilesDocument(profiles: []),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            _TestLocalTerminalConfigRepository(
              const LocalTerminalConfigDocument(
                clipboard: LocalTerminalClipboardConfig(
                  osc52: LocalTerminalOsc52Policy.allow,
                ),
              ),
            ),
          ),
          sessionPollingEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(sessionControllerProvider.notifier);
      controller.createSession(
        defaultTerminalProfile().copyWith(id: 'shell-1'),
      );
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;
      bindings.enqueueEvent(sessionId, {
        'kind': 'clipboard_mime_write',
        'session_id': int.parse(sessionId),
        'payload': {
          'location': 'clipboard',
          'id': 'write-product',
          'items': <Object?>[
            <String, Object?>{
              'mime': 'image/png',
              'data': base64.encode(<int>[1, 2, 3]),
            },
          ],
        },
      });
      controller.resizeActiveSession(const Size(640, 480), 1.0);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(written.single.mimeType, 'image/png');
      expect(written.single.bytes, <int>[1, 2, 3]);
      expect(
        ascii.decode(fakeBindings.writes.last),
        '\u001b]5522;type=write:status=DONE:id=write-product\u001b\\',
      );

      bindings.enqueueEvent(sessionId, {
        'kind': 'clipboard_mime_read_request',
        'session_id': int.parse(sessionId),
        'payload': {
          'location': 'clipboard',
          'id': 'read-product',
          'mimeTypes': <String>['image/*'],
          'listOnly': false,
        },
      });
      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(sessionId);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        fakeBindings.writes.map(ascii.decode).join(),
        contains(
          'type=read:status=DATA:mime=aW1hZ2UvcG5n:id=read-product;CQgH',
        ),
      );
    },
  );

  test(
    'bootstrap prefers explicit override over current config defaults',
    () async {
      final coreClient = FakePtyBackend();
      final profileRepository = _TestProfileRepository(
        TerminalProfilesDocument(profiles: [defaultProfile, sshProfile]),
      );
      final localConfigRepository = _TestLocalTerminalConfigRepository(
        const LocalTerminalConfigDocument(defaultProfileId: 'default'),
      );
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(profileRepository),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            localConfigRepository,
          ),
          sessionControllerProvider.overrideWith(
            () => _BootstrapOverrideSessionController('ssh'),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(sessionControllerProvider);
      expect(state.defaultProfileId, 'ssh');
      expect(state.tabs.single.profileId, 'ssh');
      expect(localConfigRepository.savedDocuments, isEmpty);
    },
  );

  test(
    'bootstrap MissingPlugin fallback is restricted to the concrete local adapter',
    () async {
      final profiles = _TestProfileRepository(
        TerminalProfilesDocument(profiles: [defaultProfile]),
      );
      final apiContainer = ProviderContainer(
        overrides: [
          profileRepositoryProvider.overrideWithValue(profiles),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            _MissingPluginApiTerminalConfigRepository(),
          ),
        ],
      );
      addTearDown(apiContainer.dispose);

      await expectLater(
        apiContainer.read(sessionBootstrapServiceProvider).prepare(),
        throwsA(isA<MissingPluginException>()),
      );

      final localContainer = ProviderContainer(
        overrides: [
          profileRepositoryProvider.overrideWithValue(profiles),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            _MissingPluginLocalTerminalConfigRepository(),
          ),
        ],
      );
      addTearDown(localContainer.dispose);

      await expectLater(
        localContainer.read(sessionBootstrapServiceProvider).prepare(),
        throwsA(isA<MissingPluginException>()),
      );
    },
  );

  test('bootstrap publishes ready state with the initial session', () async {
    final coreClient = FakePtyBackend();
    final profileRepository = _TestProfileRepository(
      TerminalProfilesDocument(profiles: [defaultProfile]),
    );
    final container = ProviderContainer(
      overrides: [
        localSessionRecordingRepositoryProvider.overrideWithValue(
          _EmptyLocalSessionRecordingRepository(),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          _TestLocalTerminalConfigRepository(null),
        ),
        ptySessionBackendProvider.overrideWithValue(coreClient),
        profileRepositoryProvider.overrideWithValue(profileRepository),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final states = <SessionState>[];
    container.listen<SessionState>(
      sessionControllerProvider,
      (_, next) => states.add(next),
    );
    container.read(sessionControllerProvider.notifier);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(states.any((state) => state.isReady), isTrue);
    expect(
      states.where((state) => state.isReady),
      everyElement(
        isA<SessionState>()
            .having((state) => state.tabs, 'tabs', isNotEmpty)
            .having(
              (state) => state.activeSessionId,
              'activeSessionId',
              isNotNull,
            ),
      ),
    );
  });

  test(
    'bootstrap relaunches configured terminal layout with new sessions',
    () async {
      final coreClient = FakePtyBackend();
      final profileRepository = _TestProfileRepository(
        TerminalProfilesDocument(profiles: [defaultProfile, sshProfile]),
      );
      final workspaceRepository = _TestLocalTerminalLayoutRepository(
        TerminalLayout(
          activeTabId: 'old-tab',
          tabs: [
            TerminalLayoutTab(
              id: 'old-tab',
              activePaneId: 'old-pane-2',
              root: TerminalPaneNode.split(
                id: 'old-split',
                direction: TerminalPaneSplitDirection.down,
                ratio: 0.64,
                first: TerminalPaneNode.leaf(
                  id: 'old-pane-1',
                  relaunchSpec: const TerminalRelaunchSpec(
                    profileId: 'default',
                    command: TerminalRelaunchCommand(
                      program: '/bin/sh',
                      arguments: ['-l'],
                    ),
                    cwd: '/workspace/one',
                  ),
                ),
                second: TerminalPaneNode.leaf(
                  id: 'old-pane-2',
                  relaunchSpec: const TerminalRelaunchSpec(
                    profileId: 'ssh',
                    command: TerminalRelaunchCommand(
                      program: '/bin/echo',
                      arguments: ['restored'],
                    ),
                    cwd: '/workspace/two',
                  ),
                ),
              ),
            ),
          ],
        ),
      );
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(profileRepository),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            _TestLocalTerminalConfigRepository(
              const LocalTerminalConfigDocument(
                layout: LocalTerminalLayoutConfig(restoreLayout: true),
              ),
            ),
          ),
          localTerminalLayoutRepositoryProvider.overrideWithValue(
            workspaceRepository,
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionControllerProvider.notifier);
      await _waitForCondition(
        condition: () => container.read(sessionControllerProvider).isReady,
        description: 'terminal layout restore bootstrap',
      );

      final state = container.read(sessionControllerProvider);
      expect(workspaceRepository.loadAttempts, 1);
      expect(state.tabs, hasLength(1));
      expect(state.tabs.single.effectivePanes, hasLength(2));
      expect(
        state.tabs.single.effectivePaneLayout.splitAxis,
        TerminalSplitAxis.vertical,
      );
      expect(state.tabs.single.effectivePaneLayout.ratio, 0.64);
      expect(state.tabs.single.effectivePanes.map((pane) => pane.profileId), [
        'default',
        'ssh',
      ]);
      expect(
        state.tabs.single.effectivePanes.map(
          (pane) => pane.profileSnapshot!.cwd,
        ),
        ['/workspace/one', '/workspace/two'],
      );
      expect(
        state.activeSessionId,
        state.tabs.single.effectivePanes.last.sessionId,
      );
      expect(state.activeSessionId, isNot('old-pane-2'));
      expect(
        state.tabs.single.effectivePanes.map(
          (pane) => pane.relaunchSpec!.profileId,
        ),
        ['default', 'ssh'],
      );
      expect(coreClient.lastCreatedSessionPayload!['launch'], {
        'program': '/usr/bin/ssh',
        'args': <String>[],
        'env': {'TERM': 'xterm-256color', 'COLORTERM': 'truecolor'},
        'cwd': '/workspace/two',
      });
      expect(state.lastError, isNull);
    },
  );

  test(
    'terminal layout relaunch failure is retained as a visible state error',
    () async {
      final workspaceRepository = _TestLocalTerminalLayoutRepository(
        TerminalLayout(
          activeTabId: 'old-tab',
          tabs: [
            TerminalLayoutTab(
              id: 'old-tab',
              activePaneId: 'old-pane',
              root: TerminalPaneNode.leaf(
                id: 'old-pane',
                sessionIntent: const TerminalRelaunchSpec(
                  profileId: 'removed-profile',
                  cwd: '/workspace',
                ),
              ),
            ),
          ],
        ),
      );
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              TerminalProfilesDocument(profiles: [defaultProfile]),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            _TestLocalTerminalConfigRepository(
              const LocalTerminalConfigDocument(
                layout: LocalTerminalLayoutConfig(restoreLayout: true),
              ),
            ),
          ),
          localTerminalLayoutRepositoryProvider.overrideWithValue(
            workspaceRepository,
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionControllerProvider.notifier);
      await _waitForCondition(
        condition: () => container.read(sessionControllerProvider).isReady,
        description: 'fallback after terminal layout relaunch failure',
      );

      final state = container.read(sessionControllerProvider);
      expect(state.tabs, hasLength(1));
      expect(state.tabs.single.profileId, defaultProfile.id);
      expect(
        state.lastError,
        contains('Terminal layout restore skipped 1 pane'),
      );
      expect(state.lastError, contains('removed-profile'));
      expect(workspaceRepository.savedDocuments, isEmpty);
    },
  );

  test(
    'corrupt terminal layout cannot be overwritten by fallback runtime state',
    () async {
      final layoutRepository = _CorruptLocalTerminalLayoutRepository();
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              TerminalProfilesDocument(profiles: [defaultProfile]),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            _TestLocalTerminalConfigRepository(
              const LocalTerminalConfigDocument(
                layout: LocalTerminalLayoutConfig(restoreLayout: true),
              ),
            ),
          ),
          localTerminalLayoutRepositoryProvider.overrideWithValue(
            layoutRepository,
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(sessionControllerProvider.notifier);
      await _waitForCondition(
        condition: () => container.read(sessionControllerProvider).isReady,
        description: 'fallback after corrupt terminal layout',
      );
      final state = container.read(sessionControllerProvider);

      expect(state.tabs, hasLength(1));
      expect(state.lastError, contains('corrupt terminal layout'));
      controller.splitActiveSession(
        defaultProfile,
        TerminalSplitAxis.horizontal,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await controller.flushLayoutPersistence();
      expect(layoutRepository.saveAttempts, 0);
    },
  );

  test('layout-enabled session mutations persist relaunch intent', () async {
    final workspaceRepository = _TestLocalTerminalLayoutRepository(
      const TerminalLayout(),
    );
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            TerminalProfilesDocument(profiles: [defaultProfile, sshProfile]),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          _TestLocalTerminalConfigRepository(
            const LocalTerminalConfigDocument(
              layout: LocalTerminalLayoutConfig(restoreLayout: true),
            ),
          ),
        ),
        localTerminalLayoutRepositoryProvider.overrideWithValue(
          workspaceRepository,
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    await _waitForCondition(
      condition: () => container.read(sessionControllerProvider).isReady,
      description: 'terminal layout persistence bootstrap',
    );
    controller.splitActiveSession(sshProfile, TerminalSplitAxis.horizontal);
    await _waitForCondition(
      condition: () => workspaceRepository.savedDocuments.isNotEmpty,
      description: 'terminal layout persistence',
    );

    final saved = workspaceRepository.savedDocuments.last;
    expect(saved.tabs, hasLength(1));
    expect(saved.tabs.single.root.direction, TerminalPaneSplitDirection.right);
    expect(saved.tabs.single.root.children, hasLength(2));
    expect(
      saved.tabs.single.root.children.map(
        (pane) => pane.sessionIntent!.profileId,
      ),
      ['default', 'ssh'],
    );
  });

  test(
    'default config observes the missing Data API layout revision before save',
    () async {
      final layoutRepository = _RevisionedTestTerminalLayoutRepository();
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              TerminalProfilesDocument(profiles: [defaultProfile, sshProfile]),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            _TestLocalTerminalConfigRepository(null),
          ),
          localTerminalLayoutRepositoryProvider.overrideWithValue(
            layoutRepository,
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(sessionControllerProvider.notifier);
      await _waitForCondition(
        condition: () => container.read(sessionControllerProvider).isReady,
        description: 'default configuration layout bootstrap',
      );
      controller.splitActiveSession(sshProfile, TerminalSplitAxis.horizontal);
      await _waitForCondition(
        condition: () => layoutRepository.savedDocuments.isNotEmpty,
        description: 'versioned Data API layout save',
      );

      expect(layoutRepository.savedDocuments.single.revision, 0);
      expect(layoutRepository.document.revision, 1);
    },
  );

  test('openTerminalAtFolder adds a terminal without project state', () async {
    final backend = FakePtyBackend();
    final layoutRepository = _TestLocalTerminalLayoutRepository(null);
    final container = ProviderContainer(
      overrides: [
        localSessionRecordingRepositoryProvider.overrideWithValue(
          _EmptyLocalSessionRecordingRepository(),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          _TestLocalTerminalConfigRepository(null),
        ),
        ptySessionBackendProvider.overrideWithValue(backend),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            TerminalProfilesDocument(
              profiles: <TerminalProfile>[defaultProfile],
            ),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        localTerminalLayoutRepositoryProvider.overrideWithValue(
          layoutRepository,
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    await _waitForCondition(
      condition: () => container.read(sessionControllerProvider).isReady,
      description: 'initial terminal bootstrap',
    );
    final initialSessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    expect(
      await controller.openTerminalAtFolder('/workspace/new-folder'),
      isTrue,
    );

    final state = container.read(sessionControllerProvider);
    expect(state.tabs, hasLength(2));
    expect(state.activeSessionId, isNot(initialSessionId));
    expect(
      backend.lastCreatedSessionPayload!['launch'],
      containsPair('cwd', '/workspace/new-folder'),
    );
    expect(
      container
          .read(terminalRuntimeControllerProvider)
          .hasSession(initialSessionId),
      isTrue,
    );
  });

  test('bootstrap publishes an error and succeeds when retried', () async {
    final profileRepository = _FailingOnceProfileRepository(
      TerminalProfilesDocument(profiles: [defaultProfile]),
    );
    final container = ProviderContainer(
      overrides: [
        localSessionRecordingRepositoryProvider.overrideWithValue(
          _EmptyLocalSessionRecordingRepository(),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          _TestLocalTerminalConfigRepository(null),
        ),
        ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
        profileRepositoryProvider.overrideWithValue(profileRepository),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    await _waitForCondition(
      condition: () =>
          container.read(sessionControllerProvider).lastError != null,
      description: 'bootstrap error',
    );

    final failedState = container.read(sessionControllerProvider);
    expect(failedState.isReady, isFalse);
    expect(failedState.lastError, contains('Terminal startup failed'));
    expect(profileRepository.loadAttempts, 1);

    await controller.retryBootstrap();

    final recoveredState = container.read(sessionControllerProvider);
    expect(recoveredState.isReady, isTrue);
    expect(recoveredState.lastError, isNull);
    expect(recoveredState.tabs, hasLength(1));
    expect(profileRepository.loadAttempts, 2);
  });

  test('bootstrap surfaces local config I/O failures', () async {
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            TerminalProfilesDocument(profiles: [defaultProfile]),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(
            const TerminalAppPreferencesDocument(
              defaults: TerminalAppDefaults(defaultProfileId: 'default'),
            ),
          ),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          _ThrowingLocalTerminalConfigRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionControllerProvider.notifier);
    await _waitForCondition(
      condition: () =>
          container.read(sessionControllerProvider).lastError != null,
      description: 'local config bootstrap error',
    );

    final state = container.read(sessionControllerProvider);
    expect(state.isReady, isFalse);
    expect(state.tabs, isEmpty);
    expect(state.lastError, contains('local config unavailable'));
  });

  test(
    'bootstrap surfaces configuration warnings and starts sessions from recovered values',
    () async {
      final coreBindings = FakePtyBackend();
      final coreClient = coreBindings;
      final recoveredDocument = TerminalProfilesDocument(
        profiles: [
          defaultProfile.copyWith(
            args: const ['-l'],
            env: const {
              'TERM': 'xterm-256color',
              'COLORTERM': 'truecolor',
              'TERM_PROGRAM': 'ianvs terminal',
            },
          ),
        ],
        loadWarnings: const [
          TerminalProfileLoadWarning(
            profileId: 'default',
            profileName: 'Local Shell',
            path: 'terminal.scrollbackLines',
            rawValueSummary: '-1',
            fallbackSummary: 'used default value 8000',
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          localSessionRecordingRepositoryProvider.overrideWithValue(
            _EmptyLocalSessionRecordingRepository(),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            _TestLocalTerminalConfigRepository(null),
          ),
          ptySessionBackendProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(recoveredDocument),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final state = container.read(sessionControllerProvider);
      expect(state.configurationWarnings, isNotEmpty);
      expect(
        state.configurationWarnings.map((warning) => warning.path),
        contains('terminal.scrollbackLines'),
      );
      expect(coreBindings.lastCreatedSessionPayload, isNotNull);
      expect(coreBindings.lastCreatedSessionPayload!['launch'], {
        'program': defaultTerminalProfile().shell,
        'args': const ['-l'],
        'env': const {
          'TERM': 'xterm-256color',
          'COLORTERM': 'truecolor',
          'TERM_PROGRAM': 'ianvs terminal',
        },
        'cwd': null,
      });
      expect(coreBindings.lastCreatedSessionPayload!['terminal'], {
        'emulation': 'xterm256',
        'scrollbackLines': 8000,
        'graphics': {
          'enabled': true,
          'advertise': 'kitty',
          'maxImageBytes': terminal.defaultTerminalGraphicMaxImageBytes,
          'maxTotalBytes': terminal.defaultTerminalGraphicMaxTotalBytes,
        },
        'dragDropEnabled': true,
      });
    },
  );

  test('driver-friendly mode avoids the periodic session polling loop', () async {
    final coreBindings = _CountingPtyBackend();
    final coreClient = coreBindings;
    final container = ProviderContainer(
      overrides: [
        localSessionRecordingRepositoryProvider.overrideWithValue(
          _EmptyLocalSessionRecordingRepository(),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          _TestLocalTerminalConfigRepository(null),
        ),
        ptySessionBackendProvider.overrideWithValue(coreClient),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            TerminalProfilesDocument(profiles: [defaultProfile]),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionControllerProvider.notifier);
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(container.read(sessionControllerProvider).tabs, hasLength(1));
    expect(
      coreBindings.takeFrameDiffCalls,
      lessThanOrEqualTo(1),
      reason:
          'driver mode should not keep scheduling frame-sync-hostile polling',
    );
    expect(
      coreBindings.pollEventsCalls,
      lessThanOrEqualTo(1),
      reason:
          'driver mode should not keep polling terminal events in the background',
    );
  });

  test(
    'driver-friendly mode performs a limited warm-up refresh until content appears',
    () async {
      final coreBindings = _DelayedFramePtyBackend(revealOnRead: 3);
      final coreClient = coreBindings;
      final container = ProviderContainer(
        overrides: [
          localSessionRecordingRepositoryProvider.overrideWithValue(
            _EmptyLocalSessionRecordingRepository(),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            _TestLocalTerminalConfigRepository(null),
          ),
          ptySessionBackendProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              TerminalProfilesDocument(profiles: [defaultProfile]),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          sessionPollingEnabledProvider.overrideWithValue(false),
          driverWarmUpRefreshEnabledProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 450));

      final state = container.read(sessionControllerProvider);
      expect(state.tabs, hasLength(1));
      expect(coreBindings.takeFrameDiffCalls, greaterThan(1));
      expect(coreBindings.takeFrameDiffCalls, lessThanOrEqualTo(4));
      expect(coreBindings.pollEventsCalls, lessThanOrEqualTo(4));
      expect(
        container
            .read(sessionControllerProvider.notifier)
            .viewportFor(state.activeSessionId!)
            .frame
            .rows
            .first
            .text,
        isNotEmpty,
      );
    },
  );

  test(
    'driver-friendly mode still avoids background polling when content is already ready',
    () async {
      final coreBindings = _CountingPtyBackend();
      final coreClient = coreBindings;
      final container = ProviderContainer(
        overrides: [
          localSessionRecordingRepositoryProvider.overrideWithValue(
            _EmptyLocalSessionRecordingRepository(),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            _TestLocalTerminalConfigRepository(null),
          ),
          ptySessionBackendProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              TerminalProfilesDocument(profiles: [defaultProfile]),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          sessionPollingEnabledProvider.overrideWithValue(false),
          driverWarmUpRefreshEnabledProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 450));

      expect(coreBindings.takeFrameDiffCalls, lessThanOrEqualTo(2));
      expect(coreBindings.pollEventsCalls, lessThanOrEqualTo(2));
    },
  );

  test(
    'driver-friendly mode applies terminal environment overrides to new sessions',
    () async {
      final coreBindings = FakePtyBackend();
      final coreClient = coreBindings;
      final container = ProviderContainer(
        overrides: [
          localSessionRecordingRepositoryProvider.overrideWithValue(
            _EmptyLocalSessionRecordingRepository(),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            _TestLocalTerminalConfigRepository(null),
          ),
          ptySessionBackendProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              TerminalProfilesDocument(profiles: [defaultProfile]),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          sessionEnvironmentOverridesProvider.overrideWithValue(
            const <String, String>{
              'TERM': 'xterm-256color',
              'COLORTERM': 'truecolor',
            },
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final state = container.read(sessionControllerProvider);
      expect(coreBindings.lastCreatedSessionPayload, isNotNull);
      expect(coreBindings.lastCreatedSessionPayload!['launch'], {
        'program': defaultProfile.shell,
        'args': defaultProfile.args,
        'env': {'TERM': 'xterm-256color', 'COLORTERM': 'truecolor'},
        'cwd': defaultProfile.cwd,
      });
      expect(state.tabs.single.profileSnapshot, isNotNull);
      expect(state.tabs.single.profileSnapshot!.env, {
        'TERM': 'xterm-256color',
        'COLORTERM': 'truecolor',
      });
    },
  );

  test('bootstrap uses local config as the startup authority', () async {
    final coreClient = FakePtyBackend();
    final profileRepository = _TestProfileRepository(
      TerminalProfilesDocument(profiles: [defaultProfile, sshProfile]),
    );
    final localConfigRepository = _TestLocalTerminalConfigRepository(
      const LocalTerminalConfigDocument(
        defaultProfileId: 'ssh',
        appearance: TerminalAppAppearance(
          themeMode: TerminalThemeMode.dark,
          terminalViewportPadding: 18,
        ),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        profileRepositoryProvider.overrideWithValue(profileRepository),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          localConfigRepository,
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionControllerProvider.notifier);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = container.read(sessionControllerProvider);
    expect(state.defaultProfileId, 'ssh');
    expect(state.configuredDefaultProfileId, 'ssh');
    expect(state.tabs.single.profileId, 'ssh');
    expect(state.themeMode, TerminalThemeMode.dark);
    expect(state.terminalViewportPadding, 18);
  });

  test('local config can globally disable shell integration', () async {
    final coreClient = FakePtyBackend();
    final profileRepository = _TestProfileRepository(
      TerminalProfilesDocument(profiles: [defaultProfile]),
    );
    final localConfigRepository = _TestLocalTerminalConfigRepository(
      const LocalTerminalConfigDocument(
        shellIntegration: LocalTerminalShellIntegrationConfig(enabled: false),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        profileRepositoryProvider.overrideWithValue(profileRepository),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          localConfigRepository,
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionControllerProvider.notifier);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final launchConfig = terminal.TerminalSessionConfig.fromJson(
      coreClient.lastCreatedSessionPayload!,
    );
    final state = container.read(sessionControllerProvider);
    expect(launchConfig.shellIntegration.enabled, isFalse);
    expect(
      state.tabs.single.profileSnapshot!.sessionConfig.shellIntegration.enabled,
      isFalse,
    );
  });

  test(
    'setDefaultProfile persists to local config when it supplied bootstrap',
    () async {
      final profileRepository = _TestProfileRepository(
        TerminalProfilesDocument(profiles: [defaultProfile, sshProfile]),
      );
      final localConfigRepository = _TestLocalTerminalConfigRepository(
        const LocalTerminalConfigDocument(
          defaultProfileId: 'default',
          layout: LocalTerminalLayoutConfig(restoreLayout: true),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
          profileRepositoryProvider.overrideWithValue(profileRepository),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            localConfigRepository,
          ),
          localTerminalLayoutRepositoryProvider.overrideWithValue(
            _TestLocalTerminalLayoutRepository(null),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await container
          .read(sessionControllerProvider.notifier)
          .setDefaultProfile('ssh');

      expect(localConfigRepository.savedDocuments, hasLength(1));
      expect(
        localConfigRepository.savedDocuments.single.defaultProfileId,
        'ssh',
      );
      expect(
        localConfigRepository.savedDocuments.single.layout.restoreLayout,
        isTrue,
      );
      final state = container.read(sessionControllerProvider);
      expect(state.configuredDefaultProfileId, 'ssh');
      expect(state.defaultProfileId, 'ssh');
    },
  );

  test(
    'setDefaultProfile merges the latest local config before saving',
    () async {
      final profileRepository = _TestProfileRepository(
        TerminalProfilesDocument(profiles: [defaultProfile, sshProfile]),
      );
      final localConfigRepository = _TestLocalTerminalConfigRepository(
        const LocalTerminalConfigDocument(
          defaultProfileId: 'default',
          notifications: LocalTerminalNotificationsConfig(enabled: true),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
          profileRepositoryProvider.overrideWithValue(profileRepository),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            localConfigRepository,
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await localConfigRepository.save(
        const LocalTerminalConfigDocument(
          defaultProfileId: 'default',
          notifications: LocalTerminalNotificationsConfig(
            enabled: true,
            commandFinished: false,
            bell: true,
            activity: false,
          ),
          paste: LocalTerminalPasteConfig(confirmMultilinePaste: false),
        ),
      );
      localConfigRepository.savedDocuments.clear();

      await container
          .read(sessionControllerProvider.notifier)
          .setDefaultProfile('ssh');

      expect(localConfigRepository.savedDocuments, hasLength(1));
      final saved = localConfigRepository.savedDocuments.single;
      expect(saved.defaultProfileId, 'ssh');
      expect(saved.notifications.enabled, isTrue);
      expect(saved.notifications.commandFinished, isFalse);
      expect(saved.notifications.bell, isTrue);
      expect(saved.notifications.activity, isFalse);
      expect(saved.paste.confirmMultilinePaste, isFalse);
    },
  );

  test('enabling layout restore persists and immediately snapshots', () async {
    final localConfigRepository = _TestLocalTerminalConfigRepository(
      const LocalTerminalConfigDocument(
        layout: LocalTerminalLayoutConfig(restoreLayout: false),
      ),
    );
    final layoutRepository = _TestLocalTerminalLayoutRepository(null);
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            TerminalProfilesDocument(profiles: [defaultProfile]),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          localConfigRepository,
        ),
        localTerminalLayoutRepositoryProvider.overrideWithValue(
          layoutRepository,
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    await _waitForCondition(
      condition: () => container.read(sessionControllerProvider).isReady,
      description: 'layout preference bootstrap',
    );
    await controller.setRestoreLayout(true);

    expect(
      localConfigRepository.savedDocuments.last.layout.restoreLayout,
      isTrue,
    );
    expect(layoutRepository.savedDocuments, hasLength(1));
    expect(layoutRepository.savedDocuments.single.tabs, hasLength(1));

    await controller.setRestoreLayout(false);
    expect(
      localConfigRepository.savedDocuments.last.layout.restoreLayout,
      isFalse,
    );
    await controller.flushLayoutPersistence();
    expect(layoutRepository.savedDocuments, hasLength(1));
  });

  test('keybinding settings persist without replacing other config', () async {
    final localConfigRepository = _TestLocalTerminalConfigRepository(
      const LocalTerminalConfigDocument(
        layout: LocalTerminalLayoutConfig(restoreLayout: true),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            TerminalProfilesDocument(profiles: [defaultProfile]),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          localConfigRepository,
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    await _waitForCondition(
      condition: () => container.read(sessionControllerProvider).isReady,
      description: 'keybinding preference bootstrap',
    );
    const keybindings = LocalTerminalKeybindingsConfig(
      overrides: {
        TerminalActionId.newTab: LocalTerminalKeyBindingOverride(
          binding: LocalTerminalKeyBinding(
            scope: TerminalKeyBindingScope.focusedApp,
            key: 'Key N',
            meta: true,
          ),
        ),
      },
    );

    await controller.setKeybindings(keybindings);

    final saved = localConfigRepository.savedDocuments.last;
    expect(saved.keybindings, keybindings);
    expect(saved.layout.restoreLayout, isTrue);
  });

  test(
    'appearance settings persist to local config when it supplied bootstrap',
    () async {
      final localConfigRepository = _TestLocalTerminalConfigRepository(
        const LocalTerminalConfigDocument(
          appearance: TerminalAppAppearance(
            themeMode: TerminalThemeMode.light,
            terminalViewportPadding: 12,
          ),
          notifications: LocalTerminalNotificationsConfig(enabled: false),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              TerminalProfilesDocument(profiles: [defaultProfile, sshProfile]),
            ),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            localConfigRepository,
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await container
          .read(sessionControllerProvider.notifier)
          .setThemeMode(TerminalThemeMode.dark);
      await container
          .read(sessionControllerProvider.notifier)
          .setTerminalViewportPadding(22);

      expect(localConfigRepository.savedDocuments, hasLength(2));
      expect(
        localConfigRepository.savedDocuments.last.appearance.themeMode,
        TerminalThemeMode.dark,
      );
      expect(
        localConfigRepository
            .savedDocuments
            .last
            .appearance
            .terminalViewportPadding,
        22,
      );
      expect(
        localConfigRepository.savedDocuments.last.notifications.enabled,
        isFalse,
      );
      final state = container.read(sessionControllerProvider);
      expect(state.themeMode, TerminalThemeMode.dark);
      expect(state.terminalViewportPadding, 22);
    },
  );

  test(
    'bootstrap repairs invalid local config default id in local config',
    () async {
      final localConfigRepository = _TestLocalTerminalConfigRepository(
        const LocalTerminalConfigDocument(defaultProfileId: 'missing'),
      );
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              TerminalProfilesDocument(profiles: [defaultProfile, sshProfile]),
            ),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            localConfigRepository,
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(localConfigRepository.savedDocuments, hasLength(1));
      expect(
        localConfigRepository.savedDocuments.single.defaultProfileId,
        isNull,
      );
      final state = container.read(sessionControllerProvider);
      expect(state.configuredDefaultProfileId, isNull);
      expect(state.defaultProfileId, 'default');
    },
  );

  test(
    'saveProfile clears configuration warnings for the saved profile',
    () async {
      final coreClient = FakePtyBackend();
      final profileRepository = _TestProfileRepository(
        TerminalProfilesDocument(
          profiles: [defaultProfile, sshProfile],
          loadWarnings: const [
            TerminalProfileLoadWarning(
              profileId: 'ssh',
              profileName: 'SSH',
              path: 'terminal.scrollbackLines',
              rawValueSummary: '-1',
              fallbackSummary: 'used default value 8000',
            ),
          ],
        ),
      );
      final container = ProviderContainer(
        overrides: [
          localSessionRecordingRepositoryProvider.overrideWithValue(
            _EmptyLocalSessionRecordingRepository(),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            _TestLocalTerminalConfigRepository(null),
          ),
          ptySessionBackendProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(profileRepository),
          customSshProfileConfigurationEnabledProvider.overrideWithValue(true),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
        ],
      );
      addTearDown(container.dispose);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      final controller = container.read(sessionControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(
        container.read(sessionControllerProvider).configurationWarnings,
        hasLength(1),
      );

      await controller.saveProfile(
        sshProfile.copyWith(
          scrollbackLines: 4096,
          appearance: sshProfile.appearance.copyWith(
            colors: const terminal.TerminalColorPalette(
              special: terminal.TerminalSpecialColors(foreground: '#112233'),
            ),
          ),
        ),
      );

      final state = container.read(sessionControllerProvider);
      expect(state.configurationWarnings, isEmpty);
      expect(profileRepository.savedDocuments.last.loadWarnings, isEmpty);
    },
  );

  test('saveProfile forwards field-scoped secret clear intents', () async {
    final coreClient = FakePtyBackend();
    final profileRepository = _TestProfileRepository(
      TerminalProfilesDocument(profiles: [defaultProfile, sshProfile]),
    );
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        profileRepositoryProvider.overrideWithValue(profileRepository),
        customSshProfileConfigurationEnabledProvider.overrideWithValue(true),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    await Future<void>.delayed(const Duration(milliseconds: 10));
    final controller = container.read(sessionControllerProvider.notifier);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await controller.saveProfile(
      sshProfile,
      clearSecrets: const <ProfileSecretField>{
        ProfileSecretField.password,
        ProfileSecretField.x11AuthCookie,
      },
    );

    expect(
      profileRepository.savedDocuments.last.secretClearIntents,
      const <String, Set<ProfileSecretField>>{
        'ssh': <ProfileSecretField>{
          ProfileSecretField.password,
          ProfileSecretField.x11AuthCookie,
        },
      },
    );
  });

  test('custom SSH save fails closed without a Data API runtime', () async {
    final profileRepository = _TestProfileRepository(
      TerminalProfilesDocument(profiles: [defaultProfile]),
    );
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
        profileRepositoryProvider.overrideWithValue(profileRepository),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          _TestLocalTerminalConfigRepository(null),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final customSshProfile = defaultProfile.copyWith(
      id: 'custom-ssh',
      connection: const terminal.TerminalConnectionConfig.ssh(
        host: 'ssh.example.test',
        user: 'developer',
      ),
    );

    await expectLater(
      controller.saveProfile(customSshProfile),
      throwsA(isA<CustomSshProfileConfigurationUnavailableException>()),
    );
    expect(profileRepository.savedDocuments, isEmpty);
  });

  test(
    'shell exit closes an inactive tab without changing the active tab',
    () async {
      final bindings = _EventfulPtyBackend(FakePtyBackend());
      final coreClient = bindings;
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              const TerminalProfilesDocument(profiles: []),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(sessionControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      for (var attempt = 0; attempt < 5; attempt += 1) {
        final bootSessionId = container
            .read(sessionControllerProvider)
            .activeSessionId;
        if (bootSessionId == null) {
          break;
        }
        unawaited(controller.closeSession(bootSessionId));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      controller.createSession(
        defaultTerminalProfile().copyWith(id: 'shell-1'),
      );
      final first = container.read(sessionControllerProvider).activeSessionId!;
      controller.createSession(
        defaultTerminalProfile().copyWith(id: 'shell-2'),
      );
      final second = container.read(sessionControllerProvider).activeSessionId!;
      expect(second, isNot(first));

      bindings.enqueueExit(first, code: 0);
      await _waitForCondition(
        description: 'inactive tab exit polling',
        condition: () => !container
            .read(sessionControllerProvider)
            .tabs
            .any((tab) => tab.sessionId == first),
      );

      final state = container.read(sessionControllerProvider);
      expect(state.tabs.map((tab) => tab.sessionId), isNot(contains(first)));
      expect(state.activeSessionId, second);
    },
  );

  test(
    'shell exit closes the active tab and focuses the remaining tab',
    () async {
      final bindings = _EventfulPtyBackend(FakePtyBackend());
      final coreClient = bindings;
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              const TerminalProfilesDocument(profiles: []),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(sessionControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final bootSessionId = container
          .read(sessionControllerProvider)
          .activeSessionId;
      if (bootSessionId != null) {
        unawaited(controller.closeSession(bootSessionId));
      }

      controller.createSession(
        defaultTerminalProfile().copyWith(id: 'shell-1'),
      );
      final first = container.read(sessionControllerProvider).activeSessionId!;
      controller.createSession(
        defaultTerminalProfile().copyWith(id: 'shell-2'),
      );
      final second = container.read(sessionControllerProvider).activeSessionId!;

      bindings.enqueueExit(second, code: 0);
      await _waitForCondition(
        description: 'active tab exit polling',
        condition: () => container
            .read(sessionControllerProvider)
            .tabs
            .every((tab) => tab.sessionId != second),
      );

      final state = container.read(sessionControllerProvider);
      expect(state.tabs.map((tab) => tab.sessionId), equals([first]));
      expect(state.activeSessionId, first);
    },
  );

  test(
    'shell exit closes the last tab and returns to the empty state',
    () async {
      final bindings = _EventfulPtyBackend(FakePtyBackend());
      final coreClient = bindings;
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              const TerminalProfilesDocument(profiles: []),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(sessionControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      for (var attempt = 0; attempt < 5; attempt += 1) {
        final bootSessionId = container
            .read(sessionControllerProvider)
            .activeSessionId;
        if (bootSessionId == null) {
          break;
        }
        unawaited(controller.closeSession(bootSessionId));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      controller.createSession(
        defaultTerminalProfile().copyWith(id: 'shell-1'),
      );
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;

      bindings.enqueueExit(sessionId, code: 0);
      await _waitForCondition(
        description: 'last tab exit polling',
        condition: () => container.read(sessionControllerProvider).tabs.isEmpty,
      );

      final state = container.read(sessionControllerProvider);
      expect(state.tabs, isEmpty);
      expect(state.activeSessionId, isNull);
    },
  );

  test(
    'SSH transport failure preserves final details after its tab closes',
    () async {
      final bindings = _SshEventfulPtyBackend(FakePtyBackend());
      final sshProfile = TerminalProfile(
        id: 'ssh-client',
        name: 'client',
        shell: '/usr/bin/ssh',
        connection: const terminal.TerminalConnectionConfig.ssh(
          host: 'client.example.test',
          user: 'root',
          port: 36000,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(bindings),
          sessionControllerProvider.overrideWith(_TestSessionController.new),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              TerminalProfilesDocument(profiles: [sshProfile]),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(
              const TerminalAppPreferencesDocument(
                defaults: TerminalAppDefaults(defaultProfileId: 'ssh-client'),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(sessionControllerProvider.notifier);
      controller.createSession(sshProfile);
      final failedSessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;
      bindings.setFrame(failedSessionId, {
        'rows': [
          {
            'index': 0,
            'text': 'Ianvs SSH: ProxyCommand could not connect to ',
            'wrapped': true,
            'style_runs': const <Object?>[],
          },
          {
            'index': 1,
            'text': '127.0.0.1:2080',
            'style_runs': const <Object?>[],
          },
        ],
        'cursor': {'row': 1, 'col': 14, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': [
          {'start': 0, 'end': 2},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
      });
      bindings.enqueueExit(failedSessionId, code: 255);
      await _waitForCondition(
        description: 'SSH transport failure exit polling',
        condition: () => container.read(sessionControllerProvider).tabs.isEmpty,
      );

      expect(
        container.read(sessionControllerProvider).lastError,
        'SSH connection “client” to root@client.example.test:36000 failed '
        '(exit code 255): ProxyCommand could not connect to 127.0.0.1:2080',
      );

      controller.dismissLastError();
      controller.createSession(sshProfile);
      final ordinaryExitSessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;
      bindings.enqueueExit(ordinaryExitSessionId, code: 1);
      await _waitForCondition(
        description: 'ordinary SSH exit polling',
        condition: () => container.read(sessionControllerProvider).tabs.isEmpty,
      );

      expect(container.read(sessionControllerProvider).lastError, isNull);
    },
  );
}
