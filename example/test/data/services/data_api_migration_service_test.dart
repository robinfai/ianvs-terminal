import 'package:app/data/services/data_api_client.dart';
import 'package:app/data/services/data_api_migration_service.dart';
import 'package:app/data/services/data_api_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exports every page and aggregates a non-destructive merge', () async {
    final first = _resource('profiles', 'default', revision: 1);
    final second = _resource('config', 'local-terminal', revision: 2);
    final source = _FakeMigrationClient(
      exportPages: <DataApiMigrationExportPage>[
        DataApiMigrationExportPage(
          sourceId: 'local-api-instance',
          resources: <DataApiMigrationResource>[first],
          nextCursor: 'page-2',
        ),
        DataApiMigrationExportPage(
          sourceId: 'local-api-instance',
          resources: <DataApiMigrationResource>[second],
          nextCursor: null,
        ),
      ],
    );
    final destination = _FakeMigrationClient(
      mergeReports: <DataApiMigrationMergeReport>[
        const DataApiMigrationMergeReport(
          results: <DataApiMigrationMergeItem>[
            DataApiMigrationMergeItem(
              kind: 'profiles',
              id: 'default',
              status: 'created',
            ),
          ],
        ),
        const DataApiMigrationMergeReport(
          results: <DataApiMigrationMergeItem>[
            DataApiMigrationMergeItem(
              kind: 'config',
              id: 'local-terminal',
              status: 'updated',
            ),
          ],
        ),
      ],
    );

    final summary = await DataApiMigrationService(
      source: source,
      destination: destination,
    ).migrate();

    expect(source.exportCursors, <String?>[null, 'page-2']);
    expect(destination.mergedSourceIds, <String>[
      'local-api-instance',
      'local-api-instance',
    ]);
    expect(destination.conflictPolicies, <DataApiMigrationConflictPolicy>[
      DataApiMigrationConflictPolicy.preserveDestination,
      DataApiMigrationConflictPolicy.preserveDestination,
    ]);
    expect(summary.resourceCount, 2);
    expect(summary.created, 1);
    expect(summary.updated, 1);
    expect(summary.skipped, 0);
  });

  test('conflict fails migration without mutating the source export', () async {
    final resource = _resource('profiles', 'default', revision: 3);
    final source = _FakeMigrationClient(
      exportPages: <DataApiMigrationExportPage>[
        DataApiMigrationExportPage(
          sourceId: 'local-api-instance',
          resources: <DataApiMigrationResource>[resource],
          nextCursor: null,
        ),
      ],
    );
    final destination = _FakeMigrationClient(
      mergeReports: const <DataApiMigrationMergeReport>[
        DataApiMigrationMergeReport(
          results: <DataApiMigrationMergeItem>[
            DataApiMigrationMergeItem(
              kind: 'profiles',
              id: 'default',
              status: 'conflict',
              reason: 'destination changed',
            ),
          ],
        ),
      ],
    );

    await expectLater(
      DataApiMigrationService(
        source: source,
        destination: destination,
      ).migrate(),
      throwsA(
        isA<DataApiMigrationIncompleteException>().having(
          (error) => error.conflicts.single.reason,
          'conflict reason',
          'destination changed',
        ),
      ),
    );

    expect(source.exportPages.single.resources.single, same(resource));
  });

  test(
    'forwards source-wins policy for an explicit reverse migration',
    () async {
      final source = _FakeMigrationClient(
        exportPages: <DataApiMigrationExportPage>[
          DataApiMigrationExportPage(
            sourceId: 'remote-api-instance',
            resources: <DataApiMigrationResource>[
              _resource('profiles', 'cloud', revision: 4),
            ],
            nextCursor: null,
          ),
        ],
      );
      final destination = _FakeMigrationClient(
        mergeReports: const <DataApiMigrationMergeReport>[
          DataApiMigrationMergeReport(
            results: <DataApiMigrationMergeItem>[
              DataApiMigrationMergeItem(
                kind: 'profiles',
                id: 'cloud',
                status: 'updated',
              ),
            ],
          ),
        ],
      );

      await DataApiMigrationService(
        source: source,
        destination: destination,
        conflictPolicy: DataApiMigrationConflictPolicy.sourceWins,
      ).migrate();

      expect(destination.conflictPolicies, <DataApiMigrationConflictPolicy>[
        DataApiMigrationConflictPolicy.sourceWins,
      ]);
    },
  );

  test('temporary migration runtime closes after success', () async {
    var closeCount = 0;
    final runtime = DataApiRuntime.local(
      baseUri: Uri.parse('http://127.0.0.1:47832/'),
      localAccessToken: 'local-token',
      encryptionKey: 'local-key',
      closeLocalSidecar: () async {
        closeCount += 1;
      },
    );

    final value = await withTemporaryDataApiRuntime<int>(
      startRuntime: () async => runtime,
      operation: (observed) async {
        expect(observed, same(runtime));
        return 7;
      },
    );

    expect(value, 7);
    expect(closeCount, 1);
  });

  test('temporary runtime closes when migration fails', () async {
    var closeCount = 0;
    final runtime = DataApiRuntime.local(
      baseUri: Uri.parse('http://127.0.0.1:47832/'),
      localAccessToken: 'local-token',
      encryptionKey: 'local-key',
      closeLocalSidecar: () async {
        closeCount += 1;
      },
    );

    await expectLater(
      withTemporaryDataApiRuntime<void>(
        startRuntime: () async => runtime,
        operation: (_) async => throw StateError('merge failed'),
      ),
      throwsA(isA<StateError>()),
    );
    expect(closeCount, 1);
  });

  test(
    'temporary runtime reports migration and cleanup failures together',
    () async {
      final operationError = StateError('merge failed');
      final cleanupError = StateError('close failed');
      final runtime = DataApiRuntime.local(
        baseUri: Uri.parse('http://127.0.0.1:47832/'),
        localAccessToken: 'local-token',
        encryptionKey: 'local-key',
        closeLocalSidecar: () async => throw cleanupError,
      );

      await expectLater(
        withTemporaryDataApiRuntime<void>(
          startRuntime: () async => runtime,
          operation: (_) async => throw operationError,
        ),
        throwsA(
          isA<DataApiMigrationRuntimeCleanupException>()
              .having(
                (error) => error.operationError,
                'operation error',
                same(operationError),
              )
              .having(
                (error) => error.cleanupError,
                'cleanup error',
                same(cleanupError),
              ),
        ),
      );
    },
  );
}

DataApiMigrationResource _resource(
  String kind,
  String id, {
  required int revision,
}) {
  return DataApiMigrationResource(
    id: id,
    kind: kind,
    data: <String, Object?>{'value': id},
    sourceRevision: revision,
    sourceUpdatedAt: DateTime.utc(2026, 1, revision),
  );
}

final class _FakeMigrationClient implements DataApiMigrationClient {
  _FakeMigrationClient({
    this.exportPages = const <DataApiMigrationExportPage>[],
    this.mergeReports = const <DataApiMigrationMergeReport>[],
  });

  final List<DataApiMigrationExportPage> exportPages;
  final List<DataApiMigrationMergeReport> mergeReports;
  final List<String?> exportCursors = <String?>[];
  final List<String> mergedSourceIds = <String>[];
  final List<DataApiMigrationConflictPolicy> conflictPolicies =
      <DataApiMigrationConflictPolicy>[];
  var _exportIndex = 0;
  var _mergeIndex = 0;

  @override
  Future<DataApiMigrationExportPage> exportMigrationPage({
    String? cursor,
  }) async {
    exportCursors.add(cursor);
    return exportPages[_exportIndex++];
  }

  @override
  Future<DataApiMigrationMergeReport> mergeResources({
    required String sourceId,
    required List<DataApiMigrationResource> resources,
    DataApiMigrationConflictPolicy conflictPolicy =
        DataApiMigrationConflictPolicy.preserveDestination,
  }) async {
    mergedSourceIds.add(sourceId);
    conflictPolicies.add(conflictPolicy);
    return mergeReports[_mergeIndex++];
  }
}
