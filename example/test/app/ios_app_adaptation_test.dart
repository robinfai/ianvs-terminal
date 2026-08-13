import 'dart:io';

import 'package:app/app.dart';
import 'package:app/data/configuration/data_api_configuration.dart';
import 'package:app/data/configuration/data_api_configuration_repository.dart';
import 'package:app/data/services/data_api_remote_session_store.dart';
import 'package:app/features/layout/local_terminal_layout_models.dart';
import 'package:app/features/layout/local_terminal_layout_repository.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/pty/pty.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_ports.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/ssh/ssh_feature_access.dart';
import 'package:app/features/terminal/terminal.dart' as terminal;
import 'package:app/features/terminal/terminal_viewport.dart';
import 'package:app/startup/app_startup_models.dart';
import 'package:app/startup/production_app_startup.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';

import '../support/fake_pty_backend.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_local_terminal_config_repository.dart';
import '../support/memory_paste_history_repository.dart';
import '../support/memory_profile_repository.dart';
import '../support/no_io_local_session_recording_repository.dart';

void main() {
  test(
    'production iOS backend rejects local sessions and delegates SSH',
    () async {
      final support = Directory.systemTemp.createTempSync('ianvs-ios-startup-');
      final documents = Directory.systemTemp.createTempSync('ianvs-ios-docs-');
      addTearDown(() {
        for (final directory in <Directory>[support, documents]) {
          if (directory.existsSync()) {
            directory.deleteSync(recursive: true);
          }
        }
      });
      final repository = _DisabledConfigurationRepository();
      final remoteSessionStore = _EmptyRemoteSessionStore();
      final nativeBackend = _IosSshFakePtyBackend();
      final coordinator = createProductionAppStartupCoordinator(
        platform: TargetPlatform.iOS,
        appSupportDirectoryResolver: () async => support,
        appDocumentsDirectoryResolver: () async => documents,
        configurationAccessFactory: (paths) async {
          return AppStartupConfigurationAccess(
            repository: repository,
            remoteSessionStore: remoteSessionStore,
            settings: _DisabledStartupSettings(),
          );
        },
        secureRecovery: (access) async => null,
        nativePtyLoader: () async => nativeBackend,
      );

      await coordinator.start();

      final graph = (coordinator.state as AppStartupReady).graph;
      final backend = graph.ptySessionBackend as IosSandboxShellBackend;
      expect(backend.localSessionsEnabled, isFalse);
      expect(
        () => backend.createSessionV1(_localSessionConfigV1),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains('Local terminal sessions are disabled on iOS'),
          ),
        ),
      );
      expect(backend.createSessionV1(_sshSessionConfigV1), '1');
      expect(
        nativeBackend.lastCreatedSessionPayload?['connection'],
        isA<Map<Object?, Object?>>().having(
          (connection) => connection['type'],
          'type',
          'ssh',
        ),
      );
      await coordinator.close();
    },
  );

  testWidgets(
    'iPhone starts empty, lists only SSH profiles, and opens the selected profile',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('ianvs-ios-widget-');
      final nativeBackend = _IosSshFakePtyBackend();
      addTearDown(() {
        if (root.existsSync()) {
          root.deleteSync(recursive: true);
        }
      });
      _configureIphoneTestSurface(tester);
      addTearDown(() => _resetIphoneTestSurface(tester));

      await tester.pumpWidget(
        _buildIosApp(
          root: root,
          nativeBackend: nativeBackend,
          profiles: <TerminalProfile>[defaultTerminalProfile(), _sshProfile],
        ),
      );
      await _pumpUntilReady(tester);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(IanvsTerminalApp)),
      );
      final initialState = container.read(sessionControllerProvider);
      expect(initialState.tabs, isEmpty);
      expect(initialState.activeSessionId, isNull);
      expect(initialState.profiles.map((profile) => profile.id), <String>[
        _sshProfile.id,
      ]);
      expect(find.byKey(const Key('ios-ssh-profile-empty-state')), findsOne);
      expect(
        find.byKey(Key('ios-ssh-empty-profile-${_sshProfile.id}')),
        findsOne,
      );
      expect(find.text('Local Shell'), findsNothing);
      expect(find.byType(TerminalViewport), findsNothing);
      expect(find.byKey(const Key('ios-sandbox-shell-notice')), findsNothing);

      final controller = container.read(sessionControllerProvider.notifier);
      controller.createSession(defaultTerminalProfile());
      await tester.pump();
      expect(container.read(sessionControllerProvider).tabs, isEmpty);
      expect(
        container.read(sessionControllerProvider).lastError,
        contains('Local terminal sessions are unavailable on iOS'),
      );
      controller.dismissLastError();
      await tester.pump();

      await tester.tap(
        find.byKey(Key('ios-ssh-empty-profile-${_sshProfile.id}')),
      );
      await tester.pumpAndSettle();

      final connectedState = container.read(sessionControllerProvider);
      expect(connectedState.tabs, hasLength(1));
      expect(connectedState.tabs.single.profileId, _sshProfile.id);
      expect(find.byType(TerminalViewport), findsOne);
      expect(find.byKey(const Key('ios-terminal-input-bar')), findsOne);
      expect(
        nativeBackend.lastCreatedSessionPayload?['connection'],
        isA<Map<Object?, Object?>>().having(
          (connection) => connection['host'],
          'host',
          'ssh.example.test',
        ),
      );

      controller.createSession(_sshProfile);
      await tester.pumpAndSettle();
      final twoTabState = container.read(sessionControllerProvider);
      expect(twoTabState.tabs, hasLength(2));
      expect(
        find.byKey(Key('shell-tab-close-${connectedState.activeSessionId}')),
        findsNothing,
      );

      final mobileCloseButton = find.byKey(
        Key('shell-tab-close-${twoTabState.activeSessionId}'),
      );
      final activeTabButton = find.byKey(
        Key('shell-tab-${twoTabState.activeSessionId}'),
      );
      final mobileCloseSurface = find.byKey(
        Key('shell-tab-close-surface-${twoTabState.activeSessionId}'),
      );
      expect(mobileCloseButton, findsOne);
      expect(tester.getSize(mobileCloseButton), const Size(44, 44));
      expect(mobileCloseSurface, findsOne);
      expect(tester.getSize(mobileCloseSurface), const Size(28, 28));
      expect(
        tester.getTopRight(mobileCloseButton).dx,
        tester.getTopRight(activeTabButton).dx,
      );
      final closeSurfaceDecoration =
          tester.widget<DecoratedBox>(mobileCloseSurface).decoration
              as BoxDecoration;
      expect(closeSurfaceDecoration.color, isNotNull);
      expect(find.bySemanticsLabel(RegExp(r'^Close .+ tab$')), findsOne);

      await tester.tap(mobileCloseButton);
      await tester.pumpAndSettle();
      expect(container.read(sessionControllerProvider).tabs, hasLength(1));

      final remainingCloseButton = find.byKey(
        Key('shell-tab-close-${connectedState.activeSessionId}'),
      );
      expect(remainingCloseButton, findsOne);
      expect(tester.getSize(remainingCloseButton), const Size(44, 44));
      await tester.tap(remainingCloseButton);
      await tester.pumpAndSettle();
      expect(container.read(sessionControllerProvider).tabs, isEmpty);
      expect(find.byKey(const Key('ios-ssh-profile-empty-state')), findsOne);
      _resetIphoneTestSurface(tester);
    },
  );

  testWidgets(
    'iPhone empty state creates an SSH profile directly without a local option',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('ianvs-ios-create-');
      addTearDown(() {
        if (root.existsSync()) {
          root.deleteSync(recursive: true);
        }
      });
      _configureIphoneTestSurface(tester);
      addTearDown(() => _resetIphoneTestSurface(tester));

      await tester.pumpWidget(
        _buildIosApp(
          root: root,
          nativeBackend: _IosSshFakePtyBackend(),
          profiles: <TerminalProfile>[defaultTerminalProfile()],
        ),
      );
      await _pumpUntilReady(tester);

      expect(find.byKey(const Key('ios-ssh-empty-profile-list')), findsOne);
      expect(find.byKey(const Key('ios-ssh-create-profile')), findsOne);
      await tester.tap(find.byKey(const Key('ios-ssh-create-profile')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ssh-host')), findsOne);
      expect(find.byKey(const Key('ssh-user')), findsOne);
      expect(find.byKey(const Key('new-session-type')), findsNothing);
      expect(find.text('Local shell'), findsNothing);
      _resetIphoneTestSurface(tester);
    },
  );
}

String get _localSessionConfigV1 => const terminal.TerminalSessionConfigV1(
  sessionId: 'local',
  displayName: 'Local',
  config: terminal.TerminalSessionConfig(
    launch: terminal.TerminalLaunchConfig(program: '/bin/zsh'),
  ),
).toJsonString();

String get _sshSessionConfigV1 => const terminal.TerminalSessionConfigV1(
  sessionId: 'ssh',
  displayName: 'SSH',
  config: terminal.TerminalSessionConfig(
    launch: terminal.TerminalLaunchConfig(program: ''),
    connection: terminal.TerminalConnectionConfig.ssh(
      host: 'ssh.example.test',
      user: 'operator',
    ),
  ),
).toJsonString();

final _sshProfile = TerminalProfile(
  id: 'ssh-test',
  name: 'Test SSH',
  shell: '',
  connection: const terminal.TerminalConnectionConfig.ssh(
    host: 'ssh.example.test',
    user: 'operator',
  ),
);

Widget _buildIosApp({
  required Directory root,
  required _IosSshFakePtyBackend nativeBackend,
  required List<TerminalProfile> profiles,
}) {
  return ProviderScope(
    overrides: [
      ptySessionBackendProvider.overrideWithValue(
        IosSandboxShellBackend(
          rootDirectory: root,
          terminalBackend: nativeBackend,
          localSessionsEnabled: false,
        ),
      ),
      profileRepositoryProvider.overrideWithValue(
        MemoryProfileRepository(TerminalProfilesDocument(profiles: profiles)),
      ),
      customSshProfileConfigurationEnabledProvider.overrideWithValue(true),
      pasteHistoryRepositoryProvider.overrideWithValue(
        MemoryPasteHistoryRepository(),
      ),
      appPreferencesRepositoryProvider.overrideWithValue(
        MemoryAppPreferencesRepository(null),
      ),
      localTerminalConfigRepositoryProvider.overrideWithValue(
        MemoryLocalTerminalConfigRepository(null),
      ),
      localTerminalLayoutRepositoryProvider.overrideWithValue(
        _NoLayoutRepository(),
      ),
      localSessionRecordingRepositoryProvider.overrideWithValue(
        noIoLocalSessionRecordingRepository(),
      ),
      sessionPollingEnabledProvider.overrideWithValue(false),
      sessionDemoFixtureProvider.overrideWithValue(null),
    ],
    child: const IanvsTerminalApp(),
  );
}

void _configureIphoneTestSurface(WidgetTester tester) {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
}

void _resetIphoneTestSurface(WidgetTester tester) {
  debugDefaultTargetPlatformOverride = null;
  tester.view.resetDevicePixelRatio();
  tester.view.resetPhysicalSize();
}

Future<void> _pumpUntilReady(WidgetTester tester) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(IanvsTerminalApp)),
  );
  for (
    var pump = 0;
    pump < 100 && !container.read(sessionControllerProvider).isReady;
    pump += 1
  ) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  await tester.pumpAndSettle();
  expect(container.read(sessionControllerProvider).isReady, isTrue);
}

final class _IosSshFakePtyBackend extends FakePtyBackend
    implements PtyReplaySessionBackend, PtyReplaySessionConfigV1Backend {
  static final PtyRuntimeCapabilities _sshRuntimeCapabilities =
      PtyRuntimeCapabilities.fromJson(<String, Object?>{
        'schema_version': 1,
        'runtime_contract': 'ianvs-runtime-contract-v1',
        'frame_schema_versions': <Object?>['terminal-frame-diff-v1'],
        'recording_schema_versions': <Object?>[],
        'features': <Object?>[
          'session-config.json.v1',
          'replay-session-config.json.v1',
          'ssh-session.v1',
        ],
      });

  @override
  PtyRuntimeCapabilities get runtimeCapabilities => _sshRuntimeCapabilities;

  @override
  String createReplaySessionV1(String sessionConfigV1Json) {
    return createSessionV1(sessionConfigV1Json);
  }

  @override
  void replayExit(String sessionId, {int? exitCode}) {}

  @override
  void replayOutput(String sessionId, List<int> bytes) {}
}

final class _DisabledConfigurationRepository
    implements DataApiConfigurationRepository {
  @override
  Future<DataApiConfiguration> load() async {
    return const DataApiConfiguration.disabled();
  }

  @override
  Future<void> save(DataApiConfiguration configuration) async {}
}

final class _NoLayoutRepository extends LocalTerminalLayoutRepository {
  @override
  Future<void> save(TerminalLayout layout) async {}

  @override
  Future<TerminalLayout?> load() async => null;
}

final class _EmptyRemoteSessionStore implements DataApiRemoteSessionSlotStore {
  @override
  Future<void> deleteSlot(String slotRef) async {}

  @override
  Future<Set<String>> listSlotRefs() async => const <String>{};

  @override
  Future<DataApiRemoteSession?> readSlot(String slotRef) async => null;

  @override
  Future<void> writeSlot(String slotRef, DataApiRemoteSession session) async {}
}

final class _DisabledStartupSettings
    implements AppStartupDataSettingsCapability {
  @override
  bool get localDataApiAvailable => false;

  @override
  Future<DataApiConfiguration> loadForRecovery() async {
    return const DataApiConfiguration.disabled();
  }

  @override
  Future<void> reconnect(DataApiRemoteLoginRequest request) async {}

  @override
  Future<void> saveDisabled() async {}

  @override
  Future<void> saveLocal() async {}
}
