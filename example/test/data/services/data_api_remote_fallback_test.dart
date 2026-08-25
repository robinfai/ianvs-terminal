import 'dart:io';

import 'package:app/data/configuration/data_api_configuration.dart';
import 'package:app/data/configuration/data_api_configuration_repository.dart';
import 'package:app/data/services/data_api_client.dart';
import 'package:app/data/services/data_api_migration_service.dart';
import 'package:app/data/services/data_api_remote_fallback.dart';
import 'package:app/data/services/data_api_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;
  late FileDataApiRemoteFallbackSnapshotStore snapshotStore;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'ianvs-remote-fallback-test-',
    );
    snapshotStore = FileDataApiRemoteFallbackSnapshotStore(
      file: File(
        '${temporaryDirectory.path}${Platform.pathSeparator}'
        '${FileDataApiRemoteFallbackSnapshotStore.fileName}',
      ),
    );
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'successful refresh checkpoints the local mirror and fallback consumes it',
    () async {
      final remoteBaseUri = Uri.parse('https://sync.example.com/');
      final configurationRepository = _MemoryConfigurationRepository(
        DataApiConfiguration.remote(remoteBaseUri.toString()),
      );
      final source = _FakeMigrationClient(
        exportPage: DataApiMigrationExportPage(
          sourceId: 'remote-server',
          resources: <DataApiMigrationResource>[
            DataApiMigrationResource(
              id: 'default',
              kind: 'profile',
              data: const <String, Object?>{'name': 'Remote profile'},
              sourceRevision: 7,
              sourceUpdatedAt: DateTime.utc(2026, 8, 25),
            ),
          ],
          nextCursor: null,
        ),
      );
      final destination = _FakeMigrationClient();
      var localRuntimeCloseCalls = 0;
      var commitCalls = 0;
      var activationCalls = 0;
      final controller = DataApiRemoteFallbackController(
        remoteRuntime: DataApiRuntime.remote(
          baseUri: remoteBaseUri,
          remoteAccessToken: 'remote-token',
          encryptionKey: 'master-key-material',
        ),
        startLocalRuntime: () async => DataApiRuntime.local(
          baseUri: Uri.parse('http://127.0.0.1:42000/'),
          localAccessToken: 'local-token',
          encryptionKey: 'master-key-material',
          closeLocalSidecar: () async {
            localRuntimeCloseCalls += 1;
          },
        ),
        configurationRepository: configurationRepository,
        snapshotStore: snapshotStore,
        migrationFactory: (_, _) => DataApiMigrationService(
          source: source,
          destination: destination,
          conflictPolicy: DataApiMigrationConflictPolicy.sourceWins,
        ),
        commitSnapshot: () async {
          commitCalls += 1;
        },
        activateLocalSnapshot: () async {
          activationCalls += 1;
        },
        clock: () => DateTime.utc(2026, 8, 25, 1, 2, 3),
      );

      final snapshot = await controller.refreshSnapshot();

      expect(snapshot.remoteBaseUri, remoteBaseUri);
      expect(snapshot.capturedAt, DateTime.utc(2026, 8, 25, 1, 2, 3));
      expect(snapshot.summary.resourceCount, 1);
      expect(destination.mergeCalls, 1);
      expect(destination.conflictPolicies, <DataApiMigrationConflictPolicy>[
        DataApiMigrationConflictPolicy.sourceWins,
      ]);
      expect(localRuntimeCloseCalls, 1);
      expect(commitCalls, 1);
      expect(activationCalls, 0);
      expect(
        (await configurationRepository.load()).deployment,
        DataApiDeployment.remote,
      );
      expect((await snapshotStore.load())?.remoteBaseUri, remoteBaseUri);

      final result = await controller.fallbackToLocal();

      expect(result.snapshot.capturedAt, snapshot.capturedAt);
      expect(
        (await configurationRepository.load()).deployment,
        DataApiDeployment.local,
      );
      expect(activationCalls, 1);
      expect(await snapshotStore.load(), isNull);
    },
  );

  test(
    'failed refresh preserves the prior last-known-good checkpoint',
    () async {
      final remoteBaseUri = Uri.parse('https://sync.example.com/');
      final prior = DataApiRemoteFallbackSnapshot(
        remoteBaseUri: remoteBaseUri,
        capturedAt: DateTime.utc(2026, 8, 24),
        summary: const DataApiMigrationSummary(
          created: 1,
          updated: 2,
          skipped: 3,
          resourceCount: 6,
        ),
      );
      await snapshotStore.save(prior);
      final controller = DataApiRemoteFallbackController(
        remoteRuntime: DataApiRuntime.remote(
          baseUri: remoteBaseUri,
          remoteAccessToken: 'remote-token',
          encryptionKey: 'master-key-material',
        ),
        startLocalRuntime: () async => DataApiRuntime.local(
          baseUri: Uri.parse('http://127.0.0.1:42000/'),
          localAccessToken: 'local-token',
          encryptionKey: 'master-key-material',
          closeLocalSidecar: () async {},
        ),
        configurationRepository: _MemoryConfigurationRepository(
          DataApiConfiguration.remote(remoteBaseUri.toString()),
        ),
        snapshotStore: snapshotStore,
        migrationFactory: (_, _) => DataApiMigrationService(
          source: _FakeMigrationClient(
            exportError: const SocketException('remote unavailable'),
          ),
          destination: _FakeMigrationClient(),
        ),
      );

      await expectLater(
        controller.refreshSnapshot(),
        throwsA(isA<SocketException>()),
      );

      final retained = await snapshotStore.load();
      expect(retained?.capturedAt, prior.capturedAt);
      expect(retained?.summary.resourceCount, 6);
    },
  );

  test(
    'fallback rejects a checkpoint captured from another remote origin',
    () async {
      await snapshotStore.save(
        DataApiRemoteFallbackSnapshot(
          remoteBaseUri: Uri.parse('https://other.example.com/'),
          capturedAt: DateTime.utc(2026, 8, 24),
          summary: const DataApiMigrationSummary(
            created: 1,
            updated: 0,
            skipped: 0,
            resourceCount: 1,
          ),
        ),
      );
      final configurationRepository = _MemoryConfigurationRepository(
        DataApiConfiguration.remote('https://sync.example.com/'),
      );
      final controller = DataApiRemoteFallbackController(
        remoteRuntime: DataApiRuntime.remote(
          baseUri: Uri.parse('https://sync.example.com/'),
          remoteAccessToken: 'remote-token',
          encryptionKey: 'master-key-material',
        ),
        startLocalRuntime: () => throw UnimplementedError(),
        configurationRepository: configurationRepository,
        snapshotStore: snapshotStore,
      );

      expect(await controller.loadSnapshot(), isNull);
      await expectLater(controller.fallbackToLocal(), throwsStateError);
      expect(
        (await configurationRepository.load()).deployment,
        DataApiDeployment.remote,
      );
    },
  );

  test(
    'file mirror promotes staging without replacing the existing local database',
    () async {
      final dataApiDirectory = Directory(
        '${temporaryDirectory.path}${Platform.pathSeparator}data-api',
      );
      final existingLocalDatabase = File(
        '${dataApiDirectory.path}${Platform.pathSeparator}ianvs.db',
      );
      await dataApiDirectory.create(recursive: true);
      await existingLocalDatabase.writeAsString('existing-local-data');
      late File stagingDatabase;
      final mirror = FileDataApiRemoteFallbackLocalMirror(
        dataApiDirectory: dataApiDirectory,
        startDatabaseRuntime: (database) async {
          stagingDatabase = database;
          await database.writeAsString('last-remote-data');
          return DataApiRuntime.local(
            baseUri: Uri.parse('http://127.0.0.1:42000/'),
            localAccessToken: 'local-token',
            encryptionKey: 'master-key-material',
            closeLocalSidecar: () async {},
          );
        },
      );

      final runtime = await mirror.startStagingRuntime();
      await runtime.close();
      await mirror.commitStaging();
      await mirror.activate();

      expect(await mirror.database.readAsString(), 'last-remote-data');
      expect(await mirror.activeMarker.exists(), isTrue);
      expect(await stagingDatabase.exists(), isFalse);
      expect(await existingLocalDatabase.readAsString(), 'existing-local-data');
    },
  );
}

final class _MemoryConfigurationRepository
    implements DataApiConfigurationRepository {
  _MemoryConfigurationRepository(this.configuration);

  DataApiConfiguration configuration;

  @override
  Future<DataApiConfiguration> load() async => configuration;

  @override
  Future<void> save(DataApiConfiguration configuration) async {
    this.configuration = configuration;
  }
}

final class _FakeMigrationClient implements DataApiMigrationClient {
  _FakeMigrationClient({this.exportPage, this.exportError});

  final DataApiMigrationExportPage? exportPage;
  final Exception? exportError;
  int mergeCalls = 0;
  final List<DataApiMigrationConflictPolicy> conflictPolicies =
      <DataApiMigrationConflictPolicy>[];

  @override
  Future<DataApiMigrationExportPage> exportMigrationPage({
    String? cursor,
  }) async {
    final error = exportError;
    if (error != null) {
      throw error;
    }
    return exportPage ??
        const DataApiMigrationExportPage(
          sourceId: 'unused',
          resources: <DataApiMigrationResource>[],
          nextCursor: null,
        );
  }

  @override
  Future<DataApiMigrationMergeReport> mergeResources({
    required String sourceId,
    required List<DataApiMigrationResource> resources,
    DataApiMigrationConflictPolicy conflictPolicy =
        DataApiMigrationConflictPolicy.preserveDestination,
  }) async {
    mergeCalls += 1;
    conflictPolicies.add(conflictPolicy);
    return DataApiMigrationMergeReport(
      results: resources
          .map(
            (resource) => DataApiMigrationMergeItem(
              kind: resource.kind,
              id: resource.id,
              status: 'created',
            ),
          )
          .toList(growable: false),
    );
  }
}
