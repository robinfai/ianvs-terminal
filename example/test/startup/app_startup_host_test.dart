import 'dart:async';
import 'dart:io';

import 'package:app/data/configuration/data_api_configuration.dart';
import 'package:app/data/configuration/data_api_configuration_repository.dart';
import 'package:app/data/services/data_api_remote_session_store.dart';
import 'package:app/features/recording/local_session_recording_repository.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/persistence_repository_composition.dart';
import 'package:app/platform/app_shutdown_coordinator.dart';
import 'package:app/startup/app_startup_coordinator.dart';
import 'package:app/startup/app_startup_host.dart';
import 'package:app/startup/app_startup_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';

void main() {
  testWidgets('ancestor GlobalKey reparent keeps the Ready graph alive', (
    tester,
  ) async {
    final harness = _HostHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    final ownerKey = GlobalKey();

    Widget tree({required bool placeOnLeft}) {
      final ownedHost = KeyedSubtree(
        key: ownerKey,
        child: harness.host(disposeCoordinator: true),
      );
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: <Widget>[
            Expanded(child: placeOnLeft ? ownedHost : const SizedBox.shrink()),
            Expanded(child: placeOnLeft ? const SizedBox.shrink() : ownedHost),
          ],
        ),
      );
    }

    await tester.pumpWidget(tree(placeOnLeft: true));
    if (harness.coordinator.state is AppStartupLoading) {
      await harness.coordinator.start();
    }
    await tester.pump();
    final graph = (harness.coordinator.state as AppStartupReady).graph;

    await tester.pumpWidget(tree(placeOnLeft: false));
    await tester.pump();

    expect(harness.coordinator.state, isA<AppStartupReady>());
    expect((harness.coordinator.state as AppStartupReady).graph, same(graph));
    expect(harness.coordinator.shutdownHasStarted, isFalse);
    expect(graph.closeHasStarted, isFalse);
  });

  testWidgets('shows loading before starting the asynchronous pipeline', (
    tester,
  ) async {
    final pathGate = Completer<void>();
    final harness = _HostHarness.create(pathGate: pathGate.future);
    addTearDown(() => _disposeHarness(tester, harness));

    await tester.pumpWidget(harness.host());

    expect(find.text('Preparing terminal runtime…'), findsOneWidget);
    expect(harness.pathResolveCount, 1);
    pathGate.complete();
    await harness.coordinator.start();
    expect(harness.coordinator.state, isA<AppStartupReady>());
    await tester.pump();
    expect(find.byType(ProviderScope), findsOneWidget);
    expect(
      tester.widget<ProviderScope>(find.byType(ProviderScope)).key,
      const ValueKey<int>(1),
    );
  });

  testWidgets('macOS initial data setup can be skipped and is persisted', (
    tester,
  ) async {
    final harness = _HostHarness.create(
      initialSetupRequirement: AppStartupDataSetupRequirement.optional,
    );
    addTearDown(() => _disposeHarness(tester, harness));

    await tester.pumpWidget(harness.host());
    await harness.coordinator.start();
    await tester.pump();

    expect(harness.coordinator.state, isA<AppStartupDataSetupRequired>());
    expect(harness.composeCount, 0);
    expect(find.text('Choose your data mode'), findsOneWidget);
    expect(find.byKey(const Key('app-startup-skip-data-api')), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('app-startup-skip-data-api')),
    );
    await tester.tap(find.byKey(const Key('app-startup-skip-data-api')));
    await tester.pumpAndSettle();

    expect(harness.settings.disableCount, 1);
    expect(harness.coordinator.state, isA<AppStartupReady>());
    expect(harness.composeCount, 1);
  });

  testWidgets('macOS initial setup can select the bundled local API', (
    tester,
  ) async {
    final harness = _HostHarness.create(
      initialSetupRequirement: AppStartupDataSetupRequirement.optional,
    );
    addTearDown(() => _disposeHarness(tester, harness));

    await tester.pumpWidget(harness.host());
    await harness.coordinator.start();
    await tester.pump();

    expect(find.byKey(const Key('app-startup-use-local-api')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('app-startup-use-local-api')),
    );
    await tester.tap(find.byKey(const Key('app-startup-use-local-api')));
    await tester.pumpAndSettle();

    expect(harness.settings.localCount, 1);
    expect(harness.settings.disableCount, 0);
    expect(harness.coordinator.state, isA<AppStartupReady>());
  });

  testWidgets(
    'iOS optional setup offers one-time SSH without a bundled API claim',
    (tester) async {
      final harness = _HostHarness.create(
        initialSetupRequirement: AppStartupDataSetupRequirement.optional,
        localDataApiAvailable: false,
      );
      addTearDown(() => _disposeHarness(tester, harness));

      await tester.pumpWidget(harness.host());
      await harness.coordinator.start();
      await tester.pump();

      expect(find.textContaining('one-time SSH connections'), findsOneWidget);
      expect(find.byKey(const Key('app-startup-use-local-api')), findsNothing);
      expect(find.text('Use bundled local API'), findsNothing);
      expect(find.text('Use local terminal only'), findsNothing);
      expect(find.text('Continue without data service'), findsOneWidget);

      await tester.tap(find.byKey(const Key('app-startup-skip-data-api')));
      await tester.pumpAndSettle();

      expect(harness.settings.disableCount, 1);
      expect(harness.coordinator.state, isA<AppStartupReady>());
    },
  );

  testWidgets('required data setup blocks use until remote login succeeds', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 667);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final harness = _HostHarness.create(
      initialSetupRequirement: AppStartupDataSetupRequirement.required,
    );
    addTearDown(() => _disposeHarness(tester, harness));

    await tester.pumpWidget(harness.host());
    await harness.coordinator.start();
    await tester.pump();

    expect(find.byKey(const Key('app-startup-skip-data-api')), findsNothing);
    expect(find.byKey(const Key('app-startup-use-local-api')), findsNothing);
    expect(harness.composeCount, 0);

    await tester.enterText(
      find.byKey(const Key('app-startup-initial-data-api-url')),
      'http://sync.example.com/',
    );
    await tester.enterText(
      find.byKey(const Key('app-startup-initial-data-api-username')),
      'operator',
    );
    await tester.enterText(
      find.byKey(const Key('app-startup-initial-data-api-password')),
      'correct horse battery',
    );
    await tester.enterText(
      find.byKey(const Key('app-startup-initial-data-api-encryption-key')),
      'sixteen-byte-key!',
    );
    await tester.pump();
    final connect = find.byKey(const Key('app-startup-connect-data-api'));
    await tester.ensureVisible(connect);
    expect(tester.widget<FilledButton>(connect).onPressed, isNotNull);
    await tester.tap(connect);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('app-startup-initial-data-api-error')),
      findsOneWidget,
    );
    expect(harness.settings.reconnectCount, 0);
    expect(harness.coordinator.state, isA<AppStartupDataSetupRequired>());

    await tester.enterText(
      find.byKey(const Key('app-startup-initial-data-api-url')),
      'https://sync.example.com/',
    );
    await tester.ensureVisible(connect);
    await tester.tap(connect);
    await tester.pumpAndSettle();

    expect(harness.settings.reconnectCount, 1);
    expect(
      harness.settings.lastReconnect?.baseUri,
      Uri.parse('https://sync.example.com/'),
    );
    expect(harness.coordinator.state, isA<AppStartupReady>());
    expect(harness.composeCount, 1);
  });

  testWidgets('retry replaces the complete keyed ProviderScope graph', (
    tester,
  ) async {
    final harness = _HostHarness.create();
    addTearDown(() => _disposeHarness(tester, harness));
    await tester.pumpWidget(harness.host());
    if (harness.coordinator.state is AppStartupLoading) {
      await harness.coordinator.start();
    }
    await tester.pump();
    expect(_hasRuntimeGeneration(tester, 1), isTrue);
    final firstScope = tester.widget<ProviderScope>(find.byType(ProviderScope));

    await harness.coordinator.retry();
    await tester.pump();
    expect(_hasRuntimeGeneration(tester, 2), isTrue);

    final secondScope = tester.widget<ProviderScope>(
      find.byType(ProviderScope),
    );
    expect(identical(firstScope, secondScope), isFalse);
    expect(harness.composeCount, 2);
  });

  testWidgets(
    'retry keeps the old ProviderScope mounted until graph shutdown settles',
    (tester) async {
      final closeGate = Completer<void>();
      final closeStarted = Completer<void>();
      final ptyShutdown = Completer<void>();
      final harness = _HostHarness.create(
        graphCloseGate: closeGate.future,
        graphCloseStarted: closeStarted,
        graphPtyShutdown: ptyShutdown,
      );
      addTearDown(() => _disposeHarness(tester, harness));
      await tester.pumpWidget(
        harness.host(
          runtimeBuilder: (graph) => ProviderScope(
            key: ValueKey<int>(graph.generation),
            child: const MaterialApp(home: SizedBox.shrink()),
          ),
        ),
      );
      if (harness.coordinator.state is AppStartupLoading) {
        await harness.coordinator.start();
      }
      await tester.pump();
      final oldScopeFinder = find.byKey(const ValueKey<int>(1));
      final oldScopeElement = tester.element(oldScopeFinder);

      final retry = harness.coordinator.retry();
      await closeStarted.future;
      await tester.pump();

      expect(oldScopeElement.mounted, isTrue);
      expect(oldScopeFinder, findsOneWidget);
      expect(harness.coordinator.state, isA<AppStartupReady>());
      expect(harness.ptyShutdownCount, 0);

      closeGate.complete();
      await tester.pump();
      await ptyShutdown.future;
      await retry;
      await tester.pump();
      expect(oldScopeElement.mounted, isFalse);
      expect(_hasRuntimeGeneration(tester, 2), isTrue);
      expect(harness.ptyShutdownCount, 1);
      final replacement = (harness.coordinator.state as AppStartupReady).graph;
      await replacement.close();
      await harness.coordinator.close();
    },
  );

  testWidgets(
    'direct Ready Host unmount starts ordered shutdown before child disposal',
    (tester) async {
      final closeGate = Completer<void>();
      final closeStarted = Completer<void>();
      final ptyShutdown = Completer<void>();
      final order = <String>[];
      final harness = _HostHarness.create(
        graphCloseGate: closeGate.future,
        graphCloseStarted: closeStarted,
        graphPtyShutdown: ptyShutdown,
        graphShutdownOrder: order,
      );
      addTearDown(harness.dispose);
      await tester.pumpWidget(
        harness.host(
          disposeCoordinator: true,
          runtimeBuilder: (graph) => ProviderScope(
            key: ValueKey<int>(graph.generation),
            overrides: [
              appShutdownCoordinatorProvider.overrideWithValue(
                graph.shutdownCoordinator,
              ),
              ptySessionBackendProvider.overrideWithValue(
                graph.ptySessionBackend,
              ),
              sessionPollingEnabledProvider.overrideWithValue(false),
              driverWarmUpRefreshEnabledProvider.overrideWithValue(false),
            ],
            child: MaterialApp(
              home: Consumer(
                builder: (context, ref, child) {
                  ref.watch(terminalRuntimeControllerProvider);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      if (harness.coordinator.state is AppStartupLoading) {
        await harness.coordinator.start();
      }
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(closeStarted.isCompleted, isTrue);
      expect(order, <String>['recording-layout-start']);
      expect(harness.ptyShutdownCount, 0);

      closeGate.complete();
      await ptyShutdown.future;
      final settled = await harness.coordinator.settleClose();
      expect(settled.failures, isEmpty);
      expect(order, <String>['recording-layout-start', 'pty-close']);
    },
  );

  testWidgets('remote recovery settings reconnect the same URL then retry', (
    tester,
  ) async {
    final harness = _HostHarness.create(
      failingStage: AppStartupStage.configuration,
      recoveryConfiguration: DataApiConfiguration.remote(
        'https://sync.example.com/',
      ),
    );
    addTearDown(() => _disposeHarness(tester, harness));
    await tester.pumpWidget(harness.host());
    await harness.coordinator.start();
    await tester.pump();
    expect(
      find.byKey(const Key('app-startup-open-data-settings')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('app-startup-open-data-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app-startup-remote-origin')), findsOneWidget);
    expect(find.text('https://sync.example.com/'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('app-startup-remote-username')),
      'operator',
    );
    await tester.enterText(
      find.byKey(const Key('app-startup-remote-password')),
      'correct horse battery',
    );
    await tester.enterText(
      find.byKey(const Key('app-startup-remote-encryption-key')),
      'sixteen-byte-key!',
    );
    await tester.tap(find.byKey(const Key('app-startup-reconnect')));
    await tester.pumpAndSettle();
    expect(_hasRuntimeGeneration(tester, 1), isTrue);

    expect(harness.settings.reconnectCount, 1);
    expect(
      harness.settings.lastReconnect?.baseUri,
      Uri.parse('https://sync.example.com/'),
    );
  });

  testWidgets('explicit Disabled recovery works when recovery load fails', (
    tester,
  ) async {
    final harness = _HostHarness.create(
      failingStage: AppStartupStage.configuration,
      settingsLoadError: StateError('corrupt configuration'),
    );
    addTearDown(() => _disposeHarness(tester, harness));
    await tester.pumpWidget(harness.host());
    await harness.coordinator.start();
    await tester.pump();
    expect(
      find.byKey(const Key('app-startup-open-data-settings')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('app-startup-open-data-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app-startup-save-disabled')), findsOneWidget);
    await tester.tap(find.byKey(const Key('app-startup-save-disabled')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('app-startup-confirm-disabled')));
    await tester.pumpAndSettle();
    expect(_hasRuntimeGeneration(tester, 1), isTrue);

    expect(harness.settings.disableCount, 1);
  });

  testWidgets(
    'stable shutdown channel survives keyed runtime graph replacement',
    (tester) async {
      const channel = MethodChannel('test/startup/stable-shutdown');
      final harness = _HostHarness.create();
      addTearDown(() => _disposeHarness(tester, harness));
      await tester.pumpWidget(harness.host(shutdownChannel: channel));
      if (harness.coordinator.state is AppStartupLoading) {
        await harness.coordinator.start();
      }
      await tester.pump();
      final priorGeneration =
          (harness.coordinator.state as AppStartupReady).graph.generation;
      await harness.coordinator.retry();
      await tester.pump();
      final retryState = harness.coordinator.state;
      expect(
        retryState,
        isA<AppStartupReady>(),
        reason: switch (retryState) {
          AppStartupRecoverableFailure(:final failure) =>
            '${failure.stage}: ${failure.error}',
          _ => retryState.runtimeType.toString(),
        },
      );
      expect(_hasRuntimeGeneration(tester, priorGeneration + 1), isTrue);

      final status = _invokeMethod(tester, channel, 'getShutdownStatus');
      await tester.pump();
      final message = await status;
      expect(message['available'], isTrue);
      expect(message['shutdownStarted'], isFalse);
    },
  );

  testWidgets('loading state exposes the same bounded shutdown channel', (
    tester,
  ) async {
    const channel = MethodChannel('test/startup/loading-shutdown');
    final reportedErrors = <FlutterErrorDetails>[];
    final previousErrorHandler = FlutterError.onError;
    FlutterError.onError = reportedErrors.add;
    addTearDown(() => FlutterError.onError = previousErrorHandler);
    final pathGate = Completer<void>();
    final harness = _HostHarness.create(
      pathGate: pathGate.future,
      rollbackTimeout: const Duration(milliseconds: 1),
    );
    addTearDown(() {
      if (!pathGate.isCompleted) {
        pathGate.complete();
      }
      return _disposeHarness(tester, harness);
    });
    await tester.pumpWidget(harness.host(shutdownChannel: channel));
    await tester.pump();
    final activeAttempt = harness.coordinator.start();

    final response = _invokeShutdown(tester, channel);
    await tester.pump(const Duration(milliseconds: 2));
    final message = await response;

    expect(message['timedOut'], isTrue);
    expect(message['safeToTerminate'], isFalse);
    expect(message['unsafeToTerminate'], isTrue);
    expect(harness.coordinator.shutdownHasStarted, isTrue);
    expect(
      reportedErrors.map((details) => details.exception),
      contains(isA<TimeoutException>()),
    );
    expect(harness.coordinator.state, isA<AppStartupLoading>());
    pathGate.complete();
    await tester.pump();
    expect(harness.composeCount, 0);
    await activeAttempt;
    await harness.coordinator.settleClose();

    final retryResponse = _invokeShutdown(tester, channel);
    await tester.pump();
    final retryMessage = await retryResponse;
    expect(retryMessage['timedOut'], isFalse);
    expect(retryMessage['safeToTerminate'], isTrue);
    expect(retryMessage['unsafeToTerminate'], isFalse);
  });

  testWidgets(
    'native shutdown and dispose share the same runtime close completion',
    (tester) async {
      const channel = MethodChannel('test/startup/shared-shutdown');
      final pathGate = Completer<void>();
      final harness = _HostHarness.create(pathGate: pathGate.future);
      addTearDown(() {
        if (!pathGate.isCompleted) {
          pathGate.complete();
        }
        return _disposeHarness(tester, harness);
      });
      await tester.pumpWidget(
        harness.host(shutdownChannel: channel, disposeCoordinator: true),
      );
      await tester.pump();

      final response = _invokeShutdown(tester, channel);
      var nativeCompleted = false;
      unawaited(response.then((_) => nativeCompleted = true));
      await tester.pump();
      final firstClose = harness.coordinator.close();
      final repeatedClose = harness.coordinator.close();
      expect(identical(firstClose, repeatedClose), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(nativeCompleted, isFalse);

      pathGate.complete();
      await tester.pump();
      final message = await response;
      expect(message['completed'], isTrue);
    },
  );
}

final class _HostHarness {
  _HostHarness._({
    required this.directory,
    required this.failingStage,
    required this.settings,
    required this.pathGate,
    required this.rollbackTimeout,
    required this.graphCloseGate,
    required this.graphCloseStarted,
    required this.graphPtyShutdown,
    required this.graphShutdownOrder,
  }) {
    coordinator = AppStartupCoordinator(pipeline: _pipeline());
  }

  static _HostHarness create({
    AppStartupStage? failingStage,
    DataApiConfiguration recoveryConfiguration =
        const DataApiConfiguration.disabled(),
    AppStartupDataSetupRequirement? initialSetupRequirement,
    Object? settingsLoadError,
    Future<void>? pathGate,
    Duration rollbackTimeout = const Duration(seconds: 8),
    Future<void>? graphCloseGate,
    Completer<void>? graphCloseStarted,
    Completer<void>? graphPtyShutdown,
    List<String>? graphShutdownOrder,
    bool localDataApiAvailable = true,
  }) {
    final directory = Directory.systemTemp.createTempSync(
      'ianvs-startup-host-',
    );
    late final _HostHarness harness;
    final settings = _HostSettings(
      configuration: recoveryConfiguration,
      initialSetupRequirement: initialSetupRequirement,
      loadError: settingsLoadError,
      onSaved: () => harness.failingStage = null,
      localDataApiAvailable: localDataApiAvailable,
    );
    return harness = _HostHarness._(
      directory: directory,
      failingStage: failingStage,
      settings: settings,
      pathGate: pathGate,
      rollbackTimeout: rollbackTimeout,
      graphCloseGate: graphCloseGate,
      graphCloseStarted: graphCloseStarted,
      graphPtyShutdown: graphPtyShutdown,
      graphShutdownOrder: graphShutdownOrder,
    );
  }

  final Directory directory;
  AppStartupStage? failingStage;
  final _HostSettings settings;
  final Future<void>? pathGate;
  final Duration rollbackTimeout;
  final Future<void>? graphCloseGate;
  final Completer<void>? graphCloseStarted;
  final Completer<void>? graphPtyShutdown;
  final List<String>? graphShutdownOrder;
  final _MemoryConfigurationRepository configurationRepository =
      _MemoryConfigurationRepository();
  final _MemoryRemoteSessionStore remoteSessionStore =
      _MemoryRemoteSessionStore();
  late final AppStartupCoordinator coordinator;
  int pathResolveCount = 0;
  int composeCount = 0;
  int ptyShutdownCount = 0;

  AppStartupHost host({
    MethodChannel shutdownChannel = const MethodChannel('app/shutdown'),
    bool disposeCoordinator = false,
    AppStartupRuntimeBuilder? runtimeBuilder,
  }) {
    return AppStartupHost(
      coordinator: coordinator,
      disposeCoordinator: disposeCoordinator,
      enableSessionPolling: false,
      enableShellAnimations: false,
      enableReferenceDemoMode: true,
      shutdownChannel: shutdownChannel,
      runtimeBuilder: runtimeBuilder ?? _runtimeShell,
    );
  }

  Widget _runtimeShell(AppRuntimeGraph graph) {
    return ProviderScope(
      key: ValueKey<int>(graph.generation),
      child: const MaterialApp(home: SizedBox.shrink()),
    );
  }

  AppStartupPipeline _pipeline() {
    return AppStartupPipeline(
      resolvePaths: () async {
        pathResolveCount += 1;
        if (pathGate case final gate?) {
          await gate;
        }
        _fail(AppStartupStage.paths);
        return AppStartupPaths(appSupportDirectory: directory);
      },
      createConfigurationAccess: (paths) async {
        return AppStartupConfigurationAccess(
          repository: configurationRepository,
          remoteSessionStore: remoteSessionStore,
          settings: settings,
        );
      },
      loadConfiguration: (access) async {
        _fail(AppStartupStage.configuration);
        return _snapshot(const DataApiConfiguration.disabled());
      },
      validateConfiguration: (access, snapshot) async {
        _fail(AppStartupStage.configurationValidation);
      },
      recoverSecureConfiguration: (access) async {
        _fail(AppStartupStage.secureRecovery);
        return null;
      },
      bootstrapData: (paths, access, configurationSnapshot) async {
        _fail(AppStartupStage.dataBootstrap);
        return null;
      },
      preparePlatform: (paths) async {
        _fail(AppStartupStage.platform);
        return const AppStartupPlatformPreparation(usesIosSandboxShell: false);
      },
      loadPty: (platform) async {
        _fail(AppStartupStage.pty);
        return _HostPtyBackend(composeCount + 1);
      },
      composeGraph:
          ({
            required generation,
            required paths,
            required configurationAccess,
            required configurationSnapshot,
            required dataApiRuntime,
            required dataApiStartupWarning,
            required ptySessionBackend,
          }) async {
            _fail(AppStartupStage.runtimeComposition);
            composeCount += 1;
            final shutdownCoordinator = AppShutdownCoordinator(
              timeout: rollbackTimeout,
            );
            if (graphCloseGate case final gate?) {
              shutdownCoordinator.registerTask('host-application', () async {
                graphShutdownOrder?.add('recording-layout-start');
                final started = graphCloseStarted;
                if (started != null && !started.isCompleted) {
                  started.complete();
                }
                await gate;
              });
              shutdownCoordinator.registerTask('host-pty', () async {
                ptyShutdownCount += 1;
                graphShutdownOrder?.add('pty-close');
                final shutdown = graphPtyShutdown;
                if (shutdown != null && !shutdown.isCompleted) {
                  shutdown.complete();
                }
              }, phase: AppShutdownPhase.infrastructure);
            }
            return AppRuntimeGraph(
              generation: generation,
              paths: paths,
              dataApiConfiguration: configurationSnapshot.configuration,
              dataApiConfigurationRepository: configurationAccess.repository,
              dataApiRuntime: null,
              dataApiStartupWarning: null,
              ptySessionBackend: ptySessionBackend,
              persistenceRepositories:
                  PersistenceRepositoryComposition.forRuntime(
                    null,
                    profileExportDirectoryResolver: () async => directory,
                  ),
              recordingRepository: LocalSessionRecordingRepository(
                directoryResolver: () async => directory,
              ),
              shutdownCoordinator: shutdownCoordinator,
            );
          },
      rollbackTimeout: rollbackTimeout,
    );
  }

  void _fail(AppStartupStage stage) {
    if (failingStage == stage) {
      throw StateError('Injected ${stage.name} failure.');
    }
  }

  Future<void> dispose() async {
    if (!coordinator.shutdownHasStarted) {
      await coordinator.close();
    }
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  }
}

AppStartupConfigurationSnapshot _snapshot(DataApiConfiguration configuration) {
  return AppStartupConfigurationSnapshot(
    configuration: configuration,
    generation: configuration.generation,
    digest: configuration.toJson().toString(),
  );
}

final class _HostSettings
    implements
        AppStartupDataSettingsCapability,
        AppStartupInitialDataSetupCapability {
  _HostSettings({
    required this.configuration,
    required AppStartupDataSetupRequirement? initialSetupRequirement,
    required this.loadError,
    required this.onSaved,
    required this.localDataApiAvailable,
  }) : _initialSetupRequirement = initialSetupRequirement;

  final DataApiConfiguration configuration;
  AppStartupDataSetupRequirement? _initialSetupRequirement;
  final Object? loadError;
  final void Function() onSaved;
  @override
  final bool localDataApiAvailable;
  int disableCount = 0;
  int localCount = 0;
  int reconnectCount = 0;
  DataApiRemoteLoginRequest? lastReconnect;

  @override
  Future<AppStartupDataSetupRequirement?> initialSetupRequirement(
    DataApiConfiguration configuration,
  ) async {
    return _initialSetupRequirement;
  }

  @override
  Future<DataApiConfiguration> loadForRecovery() async {
    if (loadError case final error?) {
      if (error is Error) {
        throw error;
      }
      if (error is Exception) {
        throw error;
      }
      throw StateError(error.toString());
    }
    return configuration;
  }

  @override
  Future<void> reconnect(DataApiRemoteLoginRequest request) async {
    reconnectCount += 1;
    lastReconnect = request;
    _initialSetupRequirement = null;
    onSaved();
  }

  @override
  Future<void> saveDisabled() async {
    disableCount += 1;
    _initialSetupRequirement = null;
    onSaved();
  }

  @override
  Future<void> saveLocal() async {
    localCount += 1;
    _initialSetupRequirement = null;
    onSaved();
  }
}

final class _MemoryConfigurationRepository
    implements DataApiConfigurationRepository {
  @override
  Future<DataApiConfiguration> load() async {
    return const DataApiConfiguration.disabled();
  }

  @override
  Future<void> save(DataApiConfiguration configuration) async {}
}

final class _MemoryRemoteSessionStore implements DataApiRemoteSessionSlotStore {
  @override
  Future<void> deleteSlot(String slotRef) async {}

  @override
  Future<Set<String>> listSlotRefs() async => const <String>{};

  @override
  Future<DataApiRemoteSession?> readSlot(String slotRef) async => null;

  @override
  Future<void> writeSlot(String slotRef, DataApiRemoteSession session) async {}
}

final class _HostPtyBackend
    implements
        PtySessionBackend,
        PtySessionConfigV1Backend,
        PtySessionFramePacketV1Backend {
  _HostPtyBackend(this.generation);

  final int generation;
  var _nextSession = 0;

  @override
  void closeSession(String sessionId) {}

  @override
  String createSessionV1(String sessionConfigV1Json) {
    _nextSession += 1;
    return 'host-$generation-$_nextSession';
  }

  @override
  int ping() => 1;

  @override
  List<PtyEvent> pollEvents(String sessionId) => const <PtyEvent>[];

  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
    int cellWidth = 0,
    int cellHeight = 0,
  }) {}

  @override
  void scrollViewport(String sessionId, int deltaLines) {}

  @override
  void scrollViewportTo(String sessionId, int offset) {}

  @override
  Uint8List? takeFramePacketV1Protobuf(
    String sessionId, {
    required int? afterSequence,
  }) => null;

  @override
  void writeInput(String sessionId, List<int> bytes) {}
}

bool _hasRuntimeGeneration(WidgetTester tester, int generation) {
  final scopes = find.byType(ProviderScope);
  if (scopes.evaluate().isEmpty) {
    return false;
  }
  return tester.widget<ProviderScope>(scopes).key == ValueKey<int>(generation);
}

Future<void> _disposeHarness(WidgetTester tester, _HostHarness harness) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await harness.dispose();
}

Future<Map<Object?, Object?>> _invokeShutdown(
  WidgetTester tester,
  MethodChannel channel,
) => _invokeMethod(tester, channel, 'requestShutdown');

Future<Map<Object?, Object?>> _invokeMethod(
  WidgetTester tester,
  MethodChannel channel,
  String method,
) {
  const codec = StandardMethodCodec();
  final response = Completer<Map<Object?, Object?>>();
  unawaited(
    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(MethodCall(method)),
      (data) {
        try {
          response.complete(
            codec.decodeEnvelope(data!)! as Map<Object?, Object?>,
          );
        } on Object catch (error, stackTrace) {
          response.completeError(error, stackTrace);
        }
      },
    ),
  );
  return response.future;
}
