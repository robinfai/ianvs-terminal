import 'dart:async';
import 'dart:io';

import 'package:app/data/services/data_api_client.dart';
import 'package:app/data/sync/json_three_way_merge.dart';
import 'package:app/data/sync/local_first_sync.dart';
import 'package:app/features/profiles/profile_secret_cipher.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_data_api_resource_client.dart';

void main() {
  const key = 'profile/default';

  test('first sync creates the union of local and remote fields', () async {
    final local = _LocalDocument(<String, Object?>{'local': 1});
    final remote = MemoryDataApiResourceClient()
      ..resources[key] = dataApiTestResource(
        kind: 'profile',
        id: 'default',
        data: <String, Object?>{'remote': 2},
      );
    final checkpoints = _MemoryCheckpointStore();
    final coordinator = _coordinator(local, remote, checkpoints);

    await coordinator.synchronize();

    expect(local.value, <String, Object?>{'local': 1, 'remote': 2});
    expect(remote.resources[key]!.data, local.value);
    expect(await checkpoints.read(key), local.value);
    expect(coordinator.phase, LocalFirstSyncPhase.idle);
  });

  test('unresolved same-field conflict performs no writes', () async {
    final local = _LocalDocument(<String, Object?>{'name': 'local'});
    final remote = MemoryDataApiResourceClient()
      ..resources[key] = dataApiTestResource(
        kind: 'profile',
        id: 'default',
        data: <String, Object?>{'name': 'remote'},
      );
    final checkpoints = _MemoryCheckpointStore()
      ..values[key] = <String, Object?>{'name': 'base'};
    final coordinator = _coordinator(local, remote, checkpoints);

    await coordinator.synchronize();

    expect(coordinator.phase, LocalFirstSyncPhase.conflict);
    expect(coordinator.conflicts[key], <String>['/name']);
    expect(local.writeCount, 0);
    expect(remote.putCount, 0);
    expect(await checkpoints.read(key), <String, Object?>{'name': 'base'});
  });

  for (final resolution in <JsonConflictResolution>[
    JsonConflictResolution.preferLocal,
    JsonConflictResolution.preferRemote,
  ]) {
    test('$resolution resolves a same-field conflict', () async {
      final local = _LocalDocument(<String, Object?>{'name': 'local'});
      final remote = MemoryDataApiResourceClient()
        ..resources[key] = dataApiTestResource(
          kind: 'profile',
          id: 'default',
          data: <String, Object?>{'name': 'remote'},
        );
      final checkpoints = _MemoryCheckpointStore()
        ..values[key] = <String, Object?>{'name': 'base'};

      await _coordinator(
        local,
        remote,
        checkpoints,
      ).synchronize(resolution: resolution);

      final expected = <String, Object?>{
        'name': resolution == JsonConflictResolution.preferLocal
            ? 'local'
            : 'remote',
      };
      expect(local.value, expected);
      expect(remote.resources[key]!.data, expected);
      expect(await checkpoints.read(key), expected);
    });
  }

  test(
    'offline edits survive restart and sync when service recovers',
    () async {
      final local = _LocalDocument(<String, Object?>{'name': 'offline edit'});
      final checkpoints = _MemoryCheckpointStore()
        ..values[key] = <String, Object?>{'name': 'before'};
      final offline = MemoryDataApiResourceClient(canAccessResources: false);

      await _coordinator(local, offline, checkpoints).synchronize();

      expect(local.value, <String, Object?>{'name': 'offline edit'});
      expect(await checkpoints.read(key), <String, Object?>{'name': 'before'});

      final recovered = MemoryDataApiResourceClient()
        ..resources[key] = dataApiTestResource(
          kind: 'profile',
          id: 'default',
          data: <String, Object?>{'name': 'before'},
        );
      final restarted = _coordinator(local, recovered, checkpoints);
      await restarted.synchronize();

      expect(recovered.resources[key]!.data, local.value);
      expect(restarted.phase, LocalFirstSyncPhase.idle);
    },
  );

  test(
    'CAS conflict re-reads remote and retries against its revision',
    () async {
      final local = _LocalDocument(<String, Object?>{'local': 1});
      final remote = MemoryDataApiResourceClient()
        ..resources[key] = dataApiTestResource(
          kind: 'profile',
          id: 'default',
          data: <String, Object?>{'remote': 1},
        );
      remote.beforePut = (client, kind, id) {
        client.resources[key] = dataApiTestResource(
          kind: kind,
          id: id,
          revision: 2,
          data: <String, Object?>{'remote': 2},
        );
      };
      final coordinator = _coordinator(local, remote, _MemoryCheckpointStore());

      await coordinator.synchronize();

      expect(remote.getCount, 2);
      expect(remote.resources[key]!.data, <String, Object?>{
        'local': 1,
        'remote': 2,
      });
      expect(local.value, remote.resources[key]!.data);
    },
  );

  test('lost write acknowledgement retries idempotently', () async {
    final local = _LocalDocument(<String, Object?>{'name': 'local'});
    final delegate = MemoryDataApiResourceClient();
    final remote = _LostAckClient(delegate);
    final coordinator = _coordinator(local, remote, _MemoryCheckpointStore());

    await coordinator.synchronize();

    expect(delegate.putCount, 1);
    expect(delegate.getCount, 2);
    expect(delegate.resources[key]!.data, local.value);
    expect(coordinator.phase, LocalFirstSyncPhase.idle);
  });

  test('a local edit made during network IO is never overwritten', () async {
    final local = _LocalDocument(<String, Object?>{'name': 'first'});
    final delegate = MemoryDataApiResourceClient();
    final getStarted = Completer<void>();
    final releaseGet = Completer<void>();
    final remote = _GatedGetClient(delegate, getStarted, releaseGet);
    final coordinator = _coordinator(local, remote, _MemoryCheckpointStore());

    final sync = coordinator.synchronize();
    await getStarted.future;
    local.value = <String, Object?>{'name': 'edited during sync'};
    releaseGet.complete();
    await sync;

    expect(local.value, <String, Object?>{'name': 'edited during sync'});
    expect(local.writeCount, 0);
    expect(delegate.putCount, 2);
    expect(delegate.resources[key]!.data, local.value);
    expect(coordinator.conflicts, isEmpty);
    expect(coordinator.phase, LocalFirstSyncPhase.idle);
  });

  test(
    'a locally deleted document is deleted remotely and not revived',
    () async {
      final local = _LocalDocument(null);
      final remote = MemoryDataApiResourceClient()
        ..resources[key] = dataApiTestResource(
          kind: 'profile',
          id: 'default',
          data: <String, Object?>{'name': 'old'},
        );
      final checkpoints = _MemoryCheckpointStore()
        ..values[key] = <String, Object?>{'name': 'old'};
      final coordinator = _coordinator(local, remote, checkpoints);

      await coordinator.synchronize();
      await coordinator.synchronize();

      expect(local.value, isNull);
      expect(remote.deletedResourceKeys, contains(key));
      expect(remote.deleteCount, 1);
      expect(await checkpoints.read(key), isNull);
    },
  );

  test('pause during a pending read prevents a later remote write', () async {
    final local = _LocalDocument(<String, Object?>{'name': 'local'});
    final delegate = MemoryDataApiResourceClient();
    final getStarted = Completer<void>();
    final releaseGet = Completer<void>();
    final remote = _GatedGetClient(delegate, getStarted, releaseGet);
    final coordinator = _coordinator(local, remote, _MemoryCheckpointStore());

    final synchronize = coordinator.synchronize();
    await getStarted.future;
    final pause = coordinator.pause();
    releaseGet.complete();
    await Future.wait([synchronize, pause]);

    expect(delegate.putCount, 0);
    expect(delegate.deleteCount, 0);
    expect(coordinator.phase, LocalFirstSyncPhase.disabled);
  });

  test(
    'transport replacement preserves local data and resumes pending pushes',
    () async {
      final local = _LocalDocument(<String, Object?>{'name': 'original'});
      final oldRemote = MemoryDataApiResourceClient();
      final oldCheckpoints = _MemoryCheckpointStore();
      final coordinator = _coordinator(local, oldRemote, oldCheckpoints);
      final replacement = MemoryDataApiResourceClient();
      final replacementCheckpoints = _MemoryCheckpointStore();

      await coordinator.setTransport(
        nextClient: replacement,
        nextCheckpoints: replacementCheckpoints,
      );
      await coordinator.synchronize();

      expect(oldRemote.getCount, 0);
      expect(oldRemote.putCount, 0);
      expect(replacement.resources[key]!.data, local.value);
      expect(await replacementCheckpoints.read(key), local.value);

      await coordinator.setTransport();
      await coordinator.documents.single.local(() async {
        local.value = <String, Object?>{'name': 'edited while disabled'};
      });
      coordinator.changed();

      expect(coordinator.phase, LocalFirstSyncPhase.disabled);
      expect(replacement.getCount, 1);
      expect(replacement.putCount, 1);
      expect(local.value, <String, Object?>{'name': 'edited while disabled'});

      await coordinator.setTransport(
        nextClient: replacement,
        nextCheckpoints: replacementCheckpoints,
      );
      await coordinator.synchronize();

      expect(replacement.resources[key]!.data, local.value);
      expect(replacement.putCount, 2);
      expect(await replacementCheckpoints.read(key), local.value);
      await coordinator.close();
    },
  );

  test(
    'missing whole remote document conflicts and preferLocal restores it',
    () async {
      final original = <String, Object?>{'name': 'preserve me'};
      final local = _LocalDocument(Map<String, Object?>.from(original));
      final remote = MemoryDataApiResourceClient();
      final checkpoints = _MemoryCheckpointStore()
        ..values[key] = Map<String, Object?>.from(original);
      final coordinator = _coordinator(local, remote, checkpoints);

      await coordinator.synchronize();

      expect(coordinator.phase, LocalFirstSyncPhase.conflict);
      expect(coordinator.conflicts[key], <String>['/']);
      expect(remote.putCount, 0);
      expect(local.value, original);

      await coordinator.synchronize(
        resolution: JsonConflictResolution.preferLocal,
      );

      expect(remote.resources[key]!.data, original);
      expect(local.value, original);
      expect(await checkpoints.read(key), original);
      expect(coordinator.phase, LocalFirstSyncPhase.idle);
    },
  );

  test('checkpoints are isolated between destination stores', () async {
    final first = _MemoryCheckpointStore();
    final second = _MemoryCheckpointStore();
    await first.write(key, <String, Object?>{'destination': 'one'});
    await second.write(key, <String, Object?>{'destination': 'two'});

    expect(await first.read(key), <String, Object?>{'destination': 'one'});
    expect(await second.read(key), <String, Object?>{'destination': 'two'});
  });

  test(
    'file checkpoint is destination-scoped and contains no plaintext',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs-sync-checkpoint-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final keyStore = _MemoryProfileSecretKeyStore();
      final first = FileSyncCheckpointStore(
        directory: () async => directory,
        destination: 'https://one.example/',
        cipher: ProfileSecretCipher(keyStore: keyStore),
      );
      final second = FileSyncCheckpointStore(
        directory: () async => directory,
        destination: 'https://two.example/',
        cipher: ProfileSecretCipher(keyStore: keyStore),
      );
      const secret = 'private-key-plaintext-marker';

      await first.write(key, <String, Object?>{'privateKey': secret});
      await second.write(key, <String, Object?>{'privateKey': 'other'});

      final files = await Directory(
        '${directory.path}/sync-checkpoints',
      ).list().where((entry) => entry is File).cast<File>().toList();
      expect(files, hasLength(2));
      for (final file in files) {
        expect(await file.readAsString(), isNot(contains(secret)));
      }
      expect(await first.read(key), <String, Object?>{'privateKey': secret});
      expect(await second.read(key), <String, Object?>{'privateKey': 'other'});
    },
  );
}

LocalFirstSyncCoordinator _coordinator(
  _LocalDocument local,
  DataApiResourceClient client,
  SyncCheckpointStore checkpoints,
) {
  return LocalFirstSyncCoordinator(
    documents: <SyncDocumentBinding>[
      SyncDocumentBinding(
        kind: 'profile',
        id: 'default',
        readLocal: () async => local.value,
        writeLocal: (value) async {
          local.writeCount++;
          local.value = value;
        },
        decodeRemote: (resource) =>
            Map<String, Object?>.from(resource.data! as Map),
        encodeRemote: (value) => (data: value, sensitive: null),
        validate: (value) {},
      ),
    ],
    client: client,
    checkpoints: checkpoints,
  );
}

final class _LocalDocument {
  _LocalDocument(this.value);
  Map<String, Object?>? value;
  int writeCount = 0;
}

final class _MemoryCheckpointStore implements SyncCheckpointStore {
  final Map<String, Map<String, Object?>?> values = {};

  @override
  Future<Map<String, Object?>?> read(String resource) async => values[resource];

  @override
  Future<void> write(String resource, Map<String, Object?>? value) async {
    values[resource] = value;
  }
}

final class _LostAckClient extends _DelegatingClient {
  _LostAckClient(super.delegate);
  bool _lost = false;

  @override
  Future<DataApiResource> putResource({
    required String kind,
    required String id,
    required Object? data,
    Object? sensitive,
    bool clearSensitive = false,
    int? expectedRevision,
  }) async {
    final saved = await delegate.putResource(
      kind: kind,
      id: id,
      data: data,
      sensitive: sensitive,
      clearSensitive: clearSensitive,
      expectedRevision: expectedRevision,
    );
    if (!_lost) {
      _lost = true;
      throw const DataApiRevisionConflictException(message: 'lost ACK');
    }
    return saved;
  }
}

final class _GatedGetClient extends _DelegatingClient {
  _GatedGetClient(super.delegate, this.started, this.release);
  final Completer<void> started;
  final Completer<void> release;
  bool _gated = false;

  @override
  Future<DataApiResource?> getResource({
    required String kind,
    required String id,
    bool includeSensitive = false,
  }) async {
    if (!_gated) {
      _gated = true;
      started.complete();
      await release.future;
    }
    return super.getResource(
      kind: kind,
      id: id,
      includeSensitive: includeSensitive,
    );
  }
}

class _DelegatingClient implements DataApiResourceClient {
  _DelegatingClient(this.delegate);
  final MemoryDataApiResourceClient delegate;

  @override
  bool get canAccessResources => delegate.canAccessResources;

  @override
  Future<bool> deleteResource({
    required String kind,
    required String id,
    int? expectedRevision,
  }) => delegate.deleteResource(
    kind: kind,
    id: id,
    expectedRevision: expectedRevision,
  );

  @override
  Future<DataApiResource?> getResource({
    required String kind,
    required String id,
    bool includeSensitive = false,
  }) => delegate.getResource(
    kind: kind,
    id: id,
    includeSensitive: includeSensitive,
  );

  @override
  Future<DataApiResourcePage> listResourcePage({
    String? kind,
    bool includeSensitive = false,
    int limit = DataApiClient.maximumPageSize,
    String? cursor,
  }) => delegate.listResourcePage(
    kind: kind,
    includeSensitive: includeSensitive,
    limit: limit,
    cursor: cursor,
  );

  @override
  Future<DataApiMigrationMergeReport> mergeResources({
    required String sourceId,
    required List<DataApiMigrationResource> resources,
    DataApiMigrationConflictPolicy conflictPolicy =
        DataApiMigrationConflictPolicy.preserveDestination,
  }) => delegate.mergeResources(
    sourceId: sourceId,
    resources: resources,
    conflictPolicy: conflictPolicy,
  );

  @override
  Future<DataApiResource> putResource({
    required String kind,
    required String id,
    required Object? data,
    Object? sensitive,
    bool clearSensitive = false,
    int? expectedRevision,
  }) => delegate.putResource(
    kind: kind,
    id: id,
    data: data,
    sensitive: sensitive,
    clearSensitive: clearSensitive,
    expectedRevision: expectedRevision,
  );
}

final class _MemoryProfileSecretKeyStore implements ProfileSecretKeyStore {
  String? value;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}
