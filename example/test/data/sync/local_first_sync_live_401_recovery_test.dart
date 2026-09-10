import 'dart:io';

import 'package:app/data/services/data_api_client.dart';
import 'package:app/data/sync/local_first_sync.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_data_api_resource_client.dart';

const _resourceKey = 'profile/default';

void main() {
  test(
    'live 401 keeps the local edit and a renewed transport resumes from the checkpoint',
    () async {
      final baseline = <String, Object?>{'name': 'baseline'};
      final local = <String, Object?>{'name': 'edited while token was revoked'};
      final checkpoints = _MemoryCheckpointStore()
        ..values[_resourceKey] = baseline;
      final remote = MemoryDataApiResourceClient()
        ..resources[_resourceKey] = dataApiTestResource(
          kind: 'profile',
          id: 'default',
          data: baseline,
        );
      final coordinator = LocalFirstSyncCoordinator(
        documents: <SyncDocumentBinding>[
          SyncDocumentBinding(
            kind: 'profile',
            id: 'default',
            readLocal: () async => local,
            writeLocal: (_) async =>
                fail('A failed 401 sync must not rewrite local data.'),
            decodeRemote: (resource) =>
                Map<String, Object?>.from(resource.data! as Map),
            encodeRemote: (value) => (data: value, sensitive: null),
            validate: (_) {},
          ),
        ],
        client: const _FailingClient(
          DataApiRequestException(
            statusCode: 401,
            code: 'unauthorized',
            message: 'a valid bearer token is required',
          ),
        ),
        checkpoints: checkpoints,
      );
      addTearDown(coordinator.close);

      await coordinator.synchronize();

      expect(coordinator.phase, LocalFirstSyncPhase.unavailable);
      expect(
        coordinator.failureReason,
        LocalFirstSyncFailureReason.authenticationRequired,
      );
      expect(local, <String, Object?>{
        'name': 'edited while token was revoked',
      });
      expect(await checkpoints.read(_resourceKey), baseline);
      expect(remote.resources[_resourceKey]!.data, baseline);

      await coordinator.setTransport(
        nextClient: remote,
        nextCheckpoints: checkpoints,
      );
      await coordinator.synchronize();

      expect(coordinator.phase, LocalFirstSyncPhase.idle);
      expect(coordinator.failureReason, isNull);
      expect(remote.resources[_resourceKey]!.data, local);
      expect(await checkpoints.read(_resourceKey), local);
    },
  );

  test('ordinary transport failure remains generic unavailable', () async {
    final coordinator = LocalFirstSyncCoordinator(
      documents: <SyncDocumentBinding>[
        SyncDocumentBinding(
          kind: 'profile',
          id: 'default',
          readLocal: () async => <String, Object?>{'name': 'local'},
          writeLocal: (_) async {},
          decodeRemote: (resource) =>
              Map<String, Object?>.from(resource.data! as Map),
          encodeRemote: (value) => (data: value, sensitive: null),
          validate: (_) {},
        ),
      ],
      client: const _FailingClient(SocketException('API connection refused')),
      checkpoints: _MemoryCheckpointStore(),
    );
    addTearDown(coordinator.close);

    await coordinator.synchronize();

    expect(coordinator.phase, LocalFirstSyncPhase.unavailable);
    expect(coordinator.failureReason, LocalFirstSyncFailureReason.unavailable);
  });
}

final class _MemoryCheckpointStore implements SyncCheckpointStore {
  final Map<String, Map<String, Object?>?> values =
      <String, Map<String, Object?>?>{};

  @override
  Future<Map<String, Object?>?> read(String resource) async => values[resource];

  @override
  Future<void> write(String resource, Map<String, Object?>? value) async {
    values[resource] = value;
  }
}

final class _FailingClient implements DataApiResourceClient {
  const _FailingClient(this.error);

  final Exception error;

  @override
  bool get canAccessResources => true;

  Never _unauthorized() => throw error;

  @override
  Future<bool> deleteResource({
    required String kind,
    required String id,
    int? expectedRevision,
  }) async => _unauthorized();

  @override
  Future<DataApiResource?> getResource({
    required String kind,
    required String id,
    bool includeSensitive = false,
  }) async => _unauthorized();

  @override
  Future<DataApiResourcePage> listResourcePage({
    String? kind,
    bool includeSensitive = false,
    int limit = DataApiClient.maximumPageSize,
    String? cursor,
  }) async => _unauthorized();

  @override
  Future<DataApiMigrationMergeReport> mergeResources({
    required String sourceId,
    required List<DataApiMigrationResource> resources,
    DataApiMigrationConflictPolicy conflictPolicy =
        DataApiMigrationConflictPolicy.preserveDestination,
  }) async => _unauthorized();

  @override
  Future<DataApiResource> putResource({
    required String kind,
    required String id,
    required Object? data,
    Object? sensitive,
    bool clearSensitive = false,
    int? expectedRevision,
  }) async => _unauthorized();
}
