import 'dart:async';
import 'dart:io';

import 'package:app/data/configuration/data_api_configuration.dart';
import 'package:app/data/configuration/data_api_configuration_repository.dart';
import 'package:app/data/services/data_api_runtime.dart';
import 'package:app/data/services/portable_master_key.dart';
import 'package:app/features/recording/local_session_recording_repository.dart';
import 'package:app/persistence_repository_composition.dart';
import 'package:app/platform/app_shutdown_coordinator.dart';
import 'package:app/startup/app_startup_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'ianvs-runtime-sync-shutdown-',
    );
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('graph closes the startup sync transport exactly once', () async {
    var closeCount = 0;
    final runtime = _runtime(() async => closeCount++);
    final composition = _composition(directory, runtime);
    final graph = _graph(directory, composition, runtime: runtime);

    await Future.wait(<Future<void>>[graph.close(), graph.close()]);
    await composition.sync.close();

    expect(closeCount, 1);
  });

  test(
    'graph closes a transport restored after startup exactly once',
    () async {
      var closeCount = 0;
      final composition = _composition(directory, null);
      final graph = _graph(directory, composition);
      await composition.sync.setTransport(nextClose: () async => closeCount++);

      await Future.wait(<Future<void>>[graph.close(), graph.close()]);
      await composition.sync.close();

      expect(closeCount, 1);
    },
  );

  test(
    'graph shutdown waits for and closes a late restored transport',
    () async {
      final restoreGate = Completer<void>();
      var closeCount = 0;
      final composition = _composition(directory, null);
      final graph = _graph(directory, composition);
      final restoration = composition.sync.retry(
        restoreTransport: () async {
          await restoreGate.future;
          await composition.sync.setTransport(
            nextClose: () async => closeCount++,
          );
        },
      );

      var shutdownCompleted = false;
      final shutdown = graph.close().then<void>((_) {
        shutdownCompleted = true;
      });
      await Future<void>.delayed(Duration.zero);

      expect(shutdownCompleted, isFalse);
      expect(closeCount, 0);

      restoreGate.complete();
      await Future.wait(<Future<void>>[restoration, shutdown]);

      expect(shutdownCompleted, isTrue);
      expect(closeCount, 1);
    },
  );

  test('late restored transport close failures fail graph shutdown', () async {
    final restoreGate = Completer<void>();
    final composition = _composition(directory, null);
    final graph = _graph(directory, composition);
    final restoration = composition.sync.retry(
      restoreTransport: () async {
        await restoreGate.future;
        await composition.sync.setTransport(
          nextClose: () async => throw StateError('late close failed'),
        );
      },
    );

    final shutdown = graph.close();
    restoreGate.complete();

    await expectLater(
      shutdown,
      throwsA(
        isA<AppRuntimeGraphCloseException>().having(
          (error) => error.result.failures.single.taskName,
          'failed task',
          'data-api-runtime',
        ),
      ),
    );
    await restoration;
  });

  test(
    'dispose keeps a late restoration failure out of its public future',
    () async {
      final restoreGate = Completer<void>();
      final composition = _composition(directory, null);
      final restoration = composition.sync.retry(
        restoreTransport: () async {
          await restoreGate.future;
          throw StateError('late restore failed');
        },
      );

      composition.sync.dispose();
      restoreGate.complete();

      await restoration;
    },
  );
}

PersistenceRepositoryComposition _composition(
  Directory directory,
  DataApiRuntime? runtime,
) {
  return PersistenceRepositoryComposition.forRuntime(
    runtime,
    profileExportDirectoryResolver: () async => directory,
    dataApiPersistenceRequired: runtime == null,
  );
}

AppRuntimeGraph _graph(
  Directory directory,
  PersistenceRepositoryComposition composition, {
  DataApiRuntime? runtime,
}) {
  return AppRuntimeGraph(
    generation: 1,
    paths: AppStartupPaths(appSupportDirectory: directory),
    dataApiConfiguration: runtime == null
        ? DataApiConfiguration.remote('https://sync.example.com/')
        : const DataApiConfiguration.local(),
    dataApiConfigurationRepository: _MemoryConfigurationRepository(),
    masterKeyRepository: PortableMasterKeyRepository(),
    dataApiRuntime: runtime,
    dataApiStartupWarning: null,
    ptySessionBackend: _FakePtyBackend(),
    persistenceRepositories: composition,
    recordingRepository: LocalSessionRecordingRepository(
      directoryResolver: () async => directory,
    ),
    shutdownCoordinator: AppShutdownCoordinator(),
  );
}

DataApiRuntime _runtime(Future<void> Function() close) {
  return DataApiRuntime.local(
    baseUri: Uri.parse('http://127.0.0.1:1/'),
    localAccessToken: 'local-access-token',
    encryptionKey: 'local-encryption-key',
    closeLocalSidecar: close,
  );
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

final class _FakePtyBackend implements PtySessionBackend {
  @override
  void closeSession(String sessionId) {}

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
  void writeInput(String sessionId, List<int> bytes) {}
}
