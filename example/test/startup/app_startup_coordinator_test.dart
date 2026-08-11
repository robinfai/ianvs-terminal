import 'dart:async';
import 'dart:io';

import 'package:app/data/configuration/data_api_configuration.dart';
import 'package:app/data/configuration/data_api_configuration_repository.dart';
import 'package:app/data/repositories/data_api_legacy_json_migration.dart';
import 'package:app/data/services/data_api_remote_session_store.dart';
import 'package:app/data/services/data_api_runtime.dart';
import 'package:app/data/services/local_data_api_sidecar.dart';
import 'package:app/features/recording/local_session_recording_repository.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/persistence_repository_composition.dart';
import 'package:app/platform/app_shutdown_coordinator.dart';
import 'package:app/startup/app_startup_coordinator.dart';
import 'package:app/startup/app_startup_models.dart';
import 'package:app/startup/production_app_startup.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';

void main() {
  group(AppStartupCoordinator, () {
    for (final stage in <AppStartupStage>[
      AppStartupStage.paths,
      AppStartupStage.configuration,
      AppStartupStage.secureRecovery,
      AppStartupStage.dataBootstrap,
      AppStartupStage.migration,
      AppStartupStage.platform,
      AppStartupStage.pty,
      AppStartupStage.configurationValidation,
      AppStartupStage.runtimeComposition,
    ]) {
      test('reports a typed recoverable failure for ${stage.name}', () async {
        final harness = _StartupHarness(failingStage: stage);
        final coordinator = AppStartupCoordinator(pipeline: harness.pipeline);

        await coordinator.start();

        final failure = coordinator.state as AppStartupRecoverableFailure;
        expect(failure.failure.stage, stage);
        expect(failure.failure.canRetry, isTrue);
        expect(failure.failure.canOpenSettings, stage != AppStartupStage.paths);
        expect(
          failure.failure.migrationRecoveries,
          stage == AppStartupStage.migration ? hasLength(1) : isEmpty,
        );
        if (<AppStartupStage>{
          AppStartupStage.migration,
          AppStartupStage.platform,
          AppStartupStage.pty,
          AppStartupStage.configurationValidation,
          AppStartupStage.runtimeComposition,
        }.contains(stage)) {
          expect(harness.runtimeCloseCount, 1);
        }
      });
    }

    test(
      'retry closes the old graph before installing a new generation',
      () async {
        final harness = _StartupHarness();
        final coordinator = AppStartupCoordinator(pipeline: harness.pipeline);
        await coordinator.start();
        final first = (coordinator.state as AppStartupReady).graph;

        await coordinator.retry();

        final second = (coordinator.state as AppStartupReady).graph;
        expect(second.generation, first.generation + 1);
        expect(harness.closeOrder, <String>['runtime-1']);
        expect(harness.composeOrder, <String>['graph-1', 'graph-2']);
      },
    );

    test(
      'graph timeout waits for final settlement before retry rebuilds',
      () async {
        final closeGate = Completer<void>();
        final harness = _StartupHarness(
          runtimeCloseGate: closeGate.future,
          rollbackTimeout: const Duration(milliseconds: 1),
        );
        final coordinator = AppStartupCoordinator(pipeline: harness.pipeline);
        await coordinator.start();

        await coordinator.retry();
        expect(coordinator.state, isA<AppStartupReady>());
        expect(harness.bootstrapCount, 1);

        closeGate.complete();
        await coordinator.retry();
        expect(coordinator.state, isA<AppStartupReady>());
        expect(harness.bootstrapCount, 2);
        expect(harness.runtimeCloseCount, 1);
      },
    );

    test('close exposes one shared bounded future', () async {
      final harness = _StartupHarness();
      final coordinator = AppStartupCoordinator(pipeline: harness.pipeline);
      await coordinator.start();

      final first = coordinator.close();
      final second = coordinator.close();

      expect(identical(first, second), isTrue);
      final result = await first;
      expect(result.timedOut, isFalse);
      expect(harness.runtimeCloseCount, 1);
    });

    test(
      'secure recovery precedes the final snapshot used by bootstrap and validation',
      () async {
        final harness = _StartupHarness();
        final coordinator = AppStartupCoordinator(pipeline: harness.pipeline);

        await coordinator.start();

        expect(harness.startupOrder, <String>[
          'secure-recovery',
          'configuration-snapshot',
          'bootstrap',
          'compose',
          'configuration-validation',
        ]);
        expect(
          identical(harness.bootstrapSnapshot, harness.validationSnapshot),
          isTrue,
        );
      },
    );

    test('migration recovery is one coordinator-owned flight', () async {
      final recoveryGate = Completer<void>();
      final recoveryStarted = Completer<void>();
      final harness = _StartupHarness(
        failingStage: AppStartupStage.migration,
        recoveryOperationGate: recoveryGate.future,
        recoveryStarted: recoveryStarted,
      );
      final coordinator = AppStartupCoordinator(pipeline: harness.pipeline);
      await coordinator.start();
      final recovery = (coordinator.state as AppStartupRecoverableFailure)
          .failure
          .migrationRecoveries
          .single;

      final first = recovery.run();
      await recoveryStarted.future;
      final second = recovery.run();

      expect(identical(first, second), isTrue);
      expect(harness.bootstrapCount, 2);
      expect(harness.recoveryRunCount, 1);
      recoveryGate.complete();
      await Future.wait(<Future<void>>[first, second]);
      expect(harness.runtimeCloseCount, 2);
      await coordinator.close();
    });

    test(
      'timed-out recovery close blocks another runtime until settlement',
      () async {
        final closeGate = Completer<void>();
        final recoveryStarted = Completer<void>();
        final harness = _StartupHarness(
          failingStage: AppStartupStage.migration,
          recoveryRuntimeCloseGate: closeGate.future,
          recoveryStarted: recoveryStarted,
          rollbackTimeout: const Duration(milliseconds: 1),
        );
        final coordinator = AppStartupCoordinator(pipeline: harness.pipeline);
        await coordinator.start();
        final recovery = (coordinator.state as AppStartupRecoverableFailure)
            .failure
            .migrationRecoveries
            .single;

        await expectLater(recovery.run(), throwsA(isA<TimeoutException>()));
        await recoveryStarted.future;
        expect(harness.bootstrapCount, 2);
        expect(harness.recoveryRunCount, 1);

        await expectLater(recovery.run(), throwsA(isA<TimeoutException>()));
        expect(harness.bootstrapCount, 2);
        expect(harness.recoveryRunCount, 1);

        closeGate.complete();
        await recovery.run();
        expect(harness.bootstrapCount, 3);
        expect(harness.recoveryRunCount, 2);
        expect(harness.runtimeCloseCount, 3);
        await coordinator.close();
      },
    );

    test('shutdown awaits an active migration recovery flight', () async {
      final recoveryGate = Completer<void>();
      final recoveryStarted = Completer<void>();
      final harness = _StartupHarness(
        failingStage: AppStartupStage.migration,
        recoveryOperationGate: recoveryGate.future,
        recoveryStarted: recoveryStarted,
      );
      final coordinator = AppStartupCoordinator(pipeline: harness.pipeline);
      await coordinator.start();
      final recovery = (coordinator.state as AppStartupRecoverableFailure)
          .failure
          .migrationRecoveries
          .single;
      final recoveryFuture = recovery.run();
      await recoveryStarted.future;

      var shutdownCompleted = false;
      final shutdown = coordinator.close();
      unawaited(shutdown.then((_) => shutdownCompleted = true));
      await Future<void>.delayed(Duration.zero);
      expect(shutdownCompleted, isFalse);

      recoveryGate.complete();
      await recoveryFuture;
      final result = await shutdown;
      expect(result.timedOut, isFalse);
      expect(harness.runtimeCloseCount, 2);
    });

    test(
      'shutdown continues to an eventual rollback after active recovery fails',
      () async {
        final reportedErrors = <FlutterErrorDetails>[];
        final previousOnError = FlutterError.onError;
        FlutterError.onError = reportedErrors.add;
        addTearDown(() => FlutterError.onError = previousOnError);
        final operationGate = Completer<void>();
        final operationStarted = Completer<void>();
        final closeGate = Completer<void>();
        final harness = _StartupHarness(
          failingStage: AppStartupStage.migration,
          recoveryOperationGate: operationGate.future,
          recoveryStarted: operationStarted,
          recoveryOperationError: StateError('injected recovery failure'),
          recoveryRuntimeCloseGate: closeGate.future,
          rollbackTimeout: const Duration(milliseconds: 1),
        );
        final coordinator = AppStartupCoordinator(pipeline: harness.pipeline);
        await coordinator.start();
        final recovery = (coordinator.state as AppStartupRecoverableFailure)
            .failure
            .migrationRecoveries
            .single;
        final recoveryFuture = recovery.run();
        unawaited(recoveryFuture.catchError((_) {}));
        await operationStarted.future;

        final bounded = await coordinator.close();
        expect(bounded.timedOut, isTrue);
        operationGate.complete();
        await Future<void>.delayed(Duration.zero);

        var settlementCompleted = false;
        final settlement = coordinator.settleClose();
        unawaited(settlement.then((_) => settlementCompleted = true));
        await Future<void>.delayed(Duration.zero);
        expect(settlementCompleted, isFalse);

        closeGate.complete();
        final settled = await settlement;
        expect(settled.timedOut, isFalse);
        expect(settled.failures, hasLength(1));
        expect(
          settled.failures.single.error,
          isA<AppStartupSettlementException>(),
        );
        expect(
          reportedErrors.where(
            (details) => details.exception is TimeoutException,
          ),
          hasLength(1),
        );
        expect(
          reportedErrors.where(
            (details) => details.exception is AppStartupSettlementException,
          ),
          hasLength(1),
        );
        await coordinator.settleClose();
        expect(reportedErrors, hasLength(2));
        expect(harness.runtimeCloseCount, 2);
      },
    );

    test(
      'active startup failure cannot skip eventual pending runtime settlement',
      () async {
        final reportedErrors = <FlutterErrorDetails>[];
        final previousOnError = FlutterError.onError;
        FlutterError.onError = reportedErrors.add;
        addTearDown(() => FlutterError.onError = previousOnError);
        final ptyGate = Completer<void>();
        final ptyStarted = Completer<void>();
        final runtimeCloseGate = Completer<void>();
        final runtimeCloseStarted = Completer<void>();
        final harness = _StartupHarness(
          failingStage: AppStartupStage.pty,
          ptyGate: ptyGate.future,
          ptyStarted: ptyStarted,
          runtimeCloseGate: runtimeCloseGate.future,
          runtimeCloseStarted: runtimeCloseStarted,
          rollbackTimeout: const Duration(milliseconds: 1),
        );
        final coordinator = AppStartupCoordinator(pipeline: harness.pipeline);
        final startup = coordinator.start();
        unawaited(startup.catchError((_) {}));
        await ptyStarted.future;

        final bounded = await coordinator.close();
        expect(bounded.timedOut, isTrue);
        ptyGate.complete();
        await runtimeCloseStarted.future;

        var settlementCompleted = false;
        final settlement = coordinator.settleClose();
        unawaited(settlement.then((_) => settlementCompleted = true));
        await Future<void>.delayed(Duration.zero);
        expect(settlementCompleted, isFalse);

        runtimeCloseGate.complete();
        final settled = await settlement;
        expect(settled.timedOut, isFalse);
        expect(settled.failures, hasLength(1));
        final error = settled.failures.single.error;
        expect(error, isA<AppStartupSettlementException>());
        expect(
          (error as AppStartupSettlementException).failures.map(
            (failure) => failure.resource,
          ),
          contains('active startup attempt'),
        );
        expect(
          reportedErrors.where(
            (details) => details.exception is TimeoutException,
          ),
          hasLength(1),
        );
        expect(
          reportedErrors.where(
            (details) => details.exception is AppStartupSettlementException,
          ),
          hasLength(1),
        );
        await coordinator.settleClose();
        expect(reportedErrors, hasLength(2));
        expect(harness.runtimeCloseCount, 1);
      },
    );

    test(
      'recovery validates its configuration snapshot before the operation',
      () async {
        final bootstrapGate = Completer<void>();
        final bootstrapStarted = Completer<void>();
        final harness = _StartupHarness(
          failingStage: AppStartupStage.migration,
          recoveryBootstrapGate: bootstrapGate.future,
          recoveryBootstrapStarted: bootstrapStarted,
        );
        final coordinator = AppStartupCoordinator(pipeline: harness.pipeline);
        await coordinator.start();
        final recovery = (coordinator.state as AppStartupRecoverableFailure)
            .failure
            .migrationRecoveries
            .single;

        final recoveryFuture = recovery.run();
        await bootstrapStarted.future;
        harness.configurationRevision += 1;
        bootstrapGate.complete();

        await expectLater(
          recoveryFuture,
          throwsA(isA<AppStartupConfigurationSnapshotConflictException>()),
        );
        expect(harness.recoveryRunCount, 0);
        expect(harness.bootstrapCount, 2);
        expect(harness.runtimeCloseCount, 2);
        await coordinator.close();
      },
    );

    test(
      'sidecar termination carrier poisons retry and recovery bootstrap',
      () async {
        final reportedErrors = <FlutterErrorDetails>[];
        final previousOnError = FlutterError.onError;
        FlutterError.onError = reportedErrors.add;
        addTearDown(() => FlutterError.onError = previousOnError);
        final harness = _StartupHarness(
          failingStage: AppStartupStage.migration,
          runtimeCloseError: const LocalDataApiSidecarStartException(
            cause: 'injected sidecar startup failure',
            sanitizedStderrTail: '',
            terminationFailure: _TerminationUnknownTestException(),
          ),
        );
        final coordinator = AppStartupCoordinator(pipeline: harness.pipeline);
        await coordinator.start();
        final failure = coordinator.state as AppStartupRecoverableFailure;
        final recovery = failure.failure.migrationRecoveries.single;

        expect(failure.failure.error, isA<AppStartupRollbackException>());
        await expectLater(
          recovery.run(),
          throwsA(isA<AppStartupRollbackException>()),
        );
        harness.failingStage = null;
        await coordinator.retry();

        final poisoned = coordinator.state as AppStartupRecoverableFailure;
        expect(poisoned.failure.stage, AppStartupStage.runtimeShutdown);
        expect(harness.bootstrapCount, 1);
        expect(harness.recoveryRunCount, 0);

        final result = await coordinator.close();
        expect(result.failures, hasLength(1));
        expect(
          result.failures.single.error,
          isA<AppStartupSettlementException>(),
        );
        expect(reportedErrors, hasLength(1));
      },
    );

    test(
      'configuration changed during composition closes the candidate before failure',
      () async {
        final composeGate = Completer<void>();
        final composeStarted = Completer<void>();
        final harness = _StartupHarness(
          composeGate: composeGate.future,
          composeStarted: composeStarted,
        );
        final coordinator = AppStartupCoordinator(pipeline: harness.pipeline);

        final startup = coordinator.start();
        await composeStarted.future;
        harness.configurationRevision += 1;
        composeGate.complete();
        await startup;

        final failure = coordinator.state as AppStartupRecoverableFailure;
        expect(failure.failure.stage, AppStartupStage.configurationValidation);
        expect(
          failure.failure.error,
          isA<AppStartupConfigurationSnapshotConflictException>(),
        );
        expect(harness.composeOrder, <String>['graph-1']);
        expect(harness.runtimeCloseCount, 1);
        await coordinator.close();
      },
    );

    test('concurrent start and retry share one in-flight pipeline', () async {
      final pathGate = Completer<void>();
      final harness = _StartupHarness(pathGate: pathGate.future);
      final coordinator = AppStartupCoordinator(pipeline: harness.pipeline);

      final first = coordinator.start();
      final second = coordinator.retry();
      await Future<void>.delayed(Duration.zero);

      expect(harness.pathResolveCount, 1);
      pathGate.complete();
      await Future.wait(<Future<void>>[first, second]);
      expect(harness.pathResolveCount, 1);
      expect(coordinator.state, isA<AppStartupReady>());
    });

    test('failed candidate runtime is rolled back before retry', () async {
      final harness = _StartupHarness(failingStage: AppStartupStage.pty);
      final coordinator = AppStartupCoordinator(pipeline: harness.pipeline);
      await coordinator.start();
      expect(harness.closeOrder, <String>['runtime-1']);

      harness.failingStage = null;
      await coordinator.retry();

      expect(coordinator.state, isA<AppStartupReady>());
      expect(harness.bootstrapCount, 2);
      expect(harness.closeOrder, <String>['runtime-1']);
    });

    test('retry cannot rebuild until a timed-out rollback settles', () async {
      final closeGate = Completer<void>();
      final harness = _StartupHarness(
        failingStage: AppStartupStage.pty,
        runtimeCloseGate: closeGate.future,
        rollbackTimeout: const Duration(milliseconds: 1),
      );
      final coordinator = AppStartupCoordinator(pipeline: harness.pipeline);

      await coordinator.start();
      expect(
        (coordinator.state as AppStartupRecoverableFailure).failure.error,
        isA<AppStartupRollbackException>(),
      );
      expect(harness.bootstrapCount, 1);

      harness.failingStage = null;
      await coordinator.retry();
      expect(
        (coordinator.state as AppStartupRecoverableFailure).failure.stage,
        AppStartupStage.runtimeShutdown,
      );
      expect(harness.bootstrapCount, 1);

      closeGate.complete();
      await coordinator.retry();
      expect(coordinator.state, isA<AppStartupReady>());
      expect(harness.bootstrapCount, 2);
    });

    test(
      'disabled data configuration builds a ready graph without runtime',
      () async {
        final harness = _StartupHarness(
          configuration: const DataApiConfiguration.disabled(),
        );
        final coordinator = AppStartupCoordinator(pipeline: harness.pipeline);

        await coordinator.start();

        final graph = (coordinator.state as AppStartupReady).graph;
        expect(graph.dataApiRuntime, isNull);
        expect(graph.persistenceRepositories.usesDataApi, isFalse);
      },
    );

    test('iOS platform preparation reaches the typed PTY stage', () async {
      final harness = _StartupHarness(usesIosSandbox: true);
      final coordinator = AppStartupCoordinator(pipeline: harness.pipeline);

      await coordinator.start();

      expect(harness.loadedIosSandbox, isTrue);
      expect(coordinator.state, isA<AppStartupReady>());
    });

    test('graph close has one idempotent shutdown owner', () async {
      final harness = _StartupHarness();
      final coordinator = AppStartupCoordinator(pipeline: harness.pipeline);
      await coordinator.start();
      final graph = (coordinator.state as AppStartupReady).graph;

      await Future.wait(<Future<void>>[graph.close(), graph.close()]);

      expect(harness.runtimeCloseCount, 1);
    });

    test('migration failures retain both explicit recovery contracts', () {
      final paths = AppStartupPaths(appSupportDirectory: Directory.systemTemp);

      final keepRemote = buildProductionMigrationRecoveryCapabilities(
        error: DataApiPersistencePreparationException(
          DataApiLegacyJsonMigrationConflictException(
            resources: const <String, DataApiLegacyResourceMigrationStatus>{
              'profiles':
                  DataApiLegacyResourceMigrationStatus.destinationAlreadyExists,
            },
          ),
        ),
        paths: paths,
      );
      final resetJournal = buildProductionMigrationRecoveryCapabilities(
        error: const DataApiLegacyJsonMigrationJournalRecoveryRequiredException(
          path: '/tmp/revision.json',
          cause: FormatException('corrupt'),
        ),
        paths: paths,
      );

      expect(
        keepRemote.single.kind,
        AppStartupMigrationRecoveryKind.keepRemote,
      );
      expect(
        resetJournal.single.kind,
        AppStartupMigrationRecoveryKind.resetJournal,
      );
    });

    test('session PTY provider fails closed without a ready graph', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        () => container.read(ptySessionBackendProvider),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains(
              'PTY backend must be supplied by the ready application runtime',
            ),
          ),
        ),
      );
    });

    test(
      'production pipeline rejects a configuration changed before publication',
      () async {
        final directory = Directory.systemTemp.createTempSync(
          'ianvs-startup-snapshot-',
        );
        addTearDown(() {
          if (directory.existsSync()) {
            directory.deleteSync(recursive: true);
          }
        });
        final repository = _MemoryConfigurationRepository();
        final remoteSessionStore = _MemoryRemoteSessionStore();
        final settings = _MemorySettingsCapability();
        final coordinator = createProductionAppStartupCoordinator(
          platform: TargetPlatform.macOS,
          appSupportDirectoryResolver: () async => directory,
          appDocumentsDirectoryResolver: () async => directory,
          configurationAccessFactory: (paths) async {
            return AppStartupConfigurationAccess(
              repository: repository,
              remoteSessionStore: remoteSessionStore,
              settings: settings,
            );
          },
          secureRecovery: (access) async => null,
          nativePtyLoader: () async {
            repository.configuration = const DataApiConfiguration.local()
                .withPersistenceState(
                  generation: 1,
                  remoteCredentialRef: null,
                  lastTransactionId: null,
                );
            return _FakePtyBackend();
          },
        );

        await coordinator.start();

        final failure = coordinator.state as AppStartupRecoverableFailure;
        expect(failure.failure.stage, AppStartupStage.configurationValidation);
        expect(
          failure.failure.error,
          isA<AppStartupConfigurationSnapshotConflictException>(),
        );
        expect(repository.loadCount, 2);
      },
    );
  });
}

final class _StartupHarness {
  _StartupHarness({
    this.failingStage,
    this.pathGate,
    this.configuration = const DataApiConfiguration.local(),
    this.usesIosSandbox = false,
    this.runtimeCloseGate,
    this.runtimeCloseStarted,
    this.runtimeCloseError,
    this.recoveryRuntimeCloseGate,
    this.recoveryBootstrapGate,
    this.recoveryBootstrapStarted,
    this.composeGate,
    this.composeStarted,
    this.recoveryOperationGate,
    this.recoveryStarted,
    this.recoveryOperationError,
    this.ptyGate,
    this.ptyStarted,
    this.rollbackTimeout = const Duration(seconds: 8),
  });

  AppStartupStage? failingStage;
  final Future<void>? pathGate;
  final DataApiConfiguration configuration;
  final bool usesIosSandbox;
  final Future<void>? runtimeCloseGate;
  final Completer<void>? runtimeCloseStarted;
  final Object? runtimeCloseError;
  final Future<void>? recoveryRuntimeCloseGate;
  final Future<void>? recoveryBootstrapGate;
  final Completer<void>? recoveryBootstrapStarted;
  final Future<void>? composeGate;
  final Completer<void>? composeStarted;
  final Future<void>? recoveryOperationGate;
  final Completer<void>? recoveryStarted;
  final Error? recoveryOperationError;
  final Future<void>? ptyGate;
  final Completer<void>? ptyStarted;
  final Duration rollbackTimeout;
  int pathResolveCount = 0;
  int bootstrapCount = 0;
  int runtimeCloseCount = 0;
  int recoveryRunCount = 0;
  int configurationRevision = 0;
  bool loadedIosSandbox = false;
  final closeOrder = <String>[];
  final composeOrder = <String>[];
  final startupOrder = <String>[];
  AppStartupConfigurationSnapshot? bootstrapSnapshot;
  AppStartupConfigurationSnapshot? validationSnapshot;
  final _configurationRepository = _MemoryConfigurationRepository();
  final _remoteSessionStore = _MemoryRemoteSessionStore();
  final _settings = _MemorySettingsCapability();

  late final AppStartupPipeline pipeline = AppStartupPipeline(
    resolvePaths: () async {
      pathResolveCount += 1;
      if (pathGate case final gate?) {
        await gate;
      }
      _fail(AppStartupStage.paths);
      return AppStartupPaths(
        appSupportDirectory: Directory.systemTemp,
        appDocumentsDirectory: Directory.systemTemp,
      );
    },
    createConfigurationAccess: (paths) async {
      return AppStartupConfigurationAccess(
        repository: _configurationRepository,
        remoteSessionStore: _remoteSessionStore,
        settings: _settings,
      );
    },
    loadConfiguration: (access) async {
      startupOrder.add('configuration-snapshot');
      _fail(AppStartupStage.configuration);
      return AppStartupConfigurationSnapshot(
        configuration: configuration,
        generation: configuration.generation,
        digest: 'revision-$configurationRevision',
      );
    },
    validateConfiguration: (access, snapshot) async {
      startupOrder.add('configuration-validation');
      validationSnapshot = snapshot;
      if (snapshot.digest != 'revision-$configurationRevision') {
        throw AppStartupConfigurationSnapshotConflictException(
          expectedGeneration: snapshot.generation,
          actualGeneration: configuration.generation,
          expectedDigest: snapshot.digest,
          actualDigest: 'revision-$configurationRevision',
        );
      }
      _fail(AppStartupStage.configurationValidation);
    },
    recoverSecureConfiguration: (access) async {
      startupOrder.add('secure-recovery');
      _fail(AppStartupStage.secureRecovery);
      return null;
    },
    bootstrapData: (paths, access, configurationSnapshot) async {
      startupOrder.add('bootstrap');
      bootstrapSnapshot = configurationSnapshot;
      bootstrapCount += 1;
      if (bootstrapCount == 2) {
        if (recoveryBootstrapGate case final gate?) {
          final started = recoveryBootstrapStarted;
          if (started != null && !started.isCompleted) {
            started.complete();
          }
          await gate;
        }
      }
      _fail(AppStartupStage.dataBootstrap);
      if (configurationSnapshot.configuration.deployment ==
          DataApiDeployment.disabled) {
        return null;
      }
      final runtimeNumber = bootstrapCount;
      return DataApiRuntime.local(
        baseUri: Uri.parse('http://127.0.0.1:$runtimeNumber/'),
        localAccessToken: 'token',
        encryptionKey: 'key',
        closeLocalSidecar: () async {
          runtimeCloseCount += 1;
          closeOrder.add('runtime-$runtimeNumber');
          final started = runtimeCloseStarted;
          if (started != null && !started.isCompleted) {
            started.complete();
          }
          final gate = runtimeNumber == 2 && recoveryRuntimeCloseGate != null
              ? recoveryRuntimeCloseGate
              : runtimeCloseGate;
          if (gate != null) {
            await gate;
          }
          if (runtimeCloseError case final error?) {
            Error.throwWithStackTrace(error, StackTrace.current);
          }
        },
      );
    },
    prepareMigration: (paths, access, configurationSnapshot, runtime) async {
      _fail(AppStartupStage.migration);
    },
    preparePlatform: (paths) async {
      _fail(AppStartupStage.platform);
      return AppStartupPlatformPreparation(
        usesIosSandboxShell: usesIosSandbox,
        iosSandboxRoot: usesIosSandbox ? Directory.systemTemp : null,
      );
    },
    loadPty: (platform) async {
      loadedIosSandbox = platform.usesIosSandboxShell;
      final started = ptyStarted;
      if (started != null && !started.isCompleted) {
        started.complete();
      }
      if (ptyGate case final gate?) {
        await gate;
      }
      _fail(AppStartupStage.pty);
      return _FakePtyBackend();
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
          startupOrder.add('compose');
          composeOrder.add('graph-$generation');
          final started = composeStarted;
          if (started != null && !started.isCompleted) {
            started.complete();
          }
          if (composeGate case final gate?) {
            await gate;
          }
          return AppRuntimeGraph(
            generation: generation,
            paths: paths,
            dataApiConfiguration: configurationSnapshot.configuration,
            dataApiConfigurationRepository: configurationAccess.repository,
            dataApiRuntime: dataApiRuntime,
            dataApiStartupWarning: dataApiStartupWarning,
            ptySessionBackend: ptySessionBackend,
            persistenceRepositories:
                PersistenceRepositoryComposition.forRuntime(
                  dataApiRuntime,
                  profileExportDirectoryResolver: () async =>
                      paths.appSupportDirectory,
                ),
            recordingRepository: LocalSessionRecordingRepository(
              directoryResolver: () async => paths.appSupportDirectory,
            ),
            shutdownCoordinator: AppShutdownCoordinator(
              timeout: rollbackTimeout,
            ),
          );
        },
    migrationRecoveries:
        ({
          required error,
          required paths,
          required configurationAccess,
          required configurationSnapshot,
        }) => <AppStartupMigrationRecoveryOperation>[
          AppStartupMigrationRecoveryOperation(
            kind: AppStartupMigrationRecoveryKind.keepRemote,
            run: (runtime) async {
              recoveryRunCount += 1;
              final started = recoveryStarted;
              if (started != null && !started.isCompleted) {
                started.complete();
              }
              if (recoveryOperationGate case final gate?) {
                await gate;
              }
              if (recoveryOperationError case final error?) {
                throw error;
              }
            },
          ),
        ],
    rollbackTimeout: rollbackTimeout,
  );

  void _fail(AppStartupStage stage) {
    if (failingStage == stage) {
      throw StateError('Injected ${stage.name} failure.');
    }
  }
}

final class _MemoryConfigurationRepository
    implements DataApiConfigurationRepository {
  _MemoryConfigurationRepository()
    : configuration = const DataApiConfiguration.disabled();

  DataApiConfiguration configuration;
  int loadCount = 0;

  @override
  Future<DataApiConfiguration> load() async {
    loadCount += 1;
    return configuration;
  }

  @override
  Future<void> save(DataApiConfiguration configuration) async {
    this.configuration = configuration;
  }
}

final class _TerminationUnknownTestException
    implements DataApiRuntimeTerminationUnknownFailure {
  const _TerminationUnknownTestException();
}

final class _MemoryRemoteSessionStore implements DataApiRemoteSessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<DataApiRemoteSession?> read() async => null;

  @override
  Future<void> write(DataApiRemoteSession session) async {}
}

final class _MemorySettingsCapability
    implements AppStartupDataSettingsCapability {
  @override
  bool get localDataApiAvailable => true;

  @override
  Future<DataApiConfiguration> loadForRecovery() async {
    return const DataApiConfiguration.disabled();
  }

  @override
  Future<void> reconnect(DataApiRemoteLoginRequest request) async {}

  @override
  Future<void> saveDisabled() async {}
}

final class _FakePtyBackend implements PtySessionBackend {
  @override
  void closeSession(String sessionId) {}

  @override
  String createSession(String sessionConfigJson) => 'session';

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
  String? takeFrameDiffJson(String sessionId) => null;

  @override
  void writeInput(String sessionId, List<int> bytes) {}
}
