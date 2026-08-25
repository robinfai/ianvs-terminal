import 'dart:convert';
import 'dart:io';

import '../../platform/local_json_file.dart';
import '../configuration/data_api_configuration.dart';
import '../configuration/data_api_configuration_repository.dart';
import 'data_api_client.dart';
import 'data_api_migration_service.dart';
import 'data_api_runtime.dart';

typedef DataApiRemoteFallbackMigrationFactory =
    DataApiMigrationService Function(
      DataApiRuntime sourceRuntime,
      DataApiRuntime destinationRuntime,
    );

typedef DataApiRemoteFallbackRuntimeStarter = Future<DataApiRuntime> Function();
typedef DataApiRemoteFallbackSnapshotCommitter = Future<void> Function();
typedef DataApiRemoteFallbackSnapshotActivator = Future<void> Function();

Future<void> _noOpRemoteFallbackAction() async {}

DataApiMigrationService _defaultRemoteFallbackMigration(
  DataApiRuntime sourceRuntime,
  DataApiRuntime destinationRuntime,
) {
  return DataApiMigrationService(
    source: DataApiClient.fromRuntime(sourceRuntime),
    destination: DataApiClient.fromRuntime(destinationRuntime),
    conflictPolicy: DataApiMigrationConflictPolicy.sourceWins,
  );
}

final class DataApiRemoteFallbackSnapshot {
  factory DataApiRemoteFallbackSnapshot({
    required Uri remoteBaseUri,
    required DateTime capturedAt,
    required DataApiMigrationSummary summary,
  }) {
    final normalizedBaseUri = DataApiConfiguration.remote(
      remoteBaseUri.toString(),
    ).remoteBaseUri!;
    if (summary.created < 0 ||
        summary.updated < 0 ||
        summary.skipped < 0 ||
        summary.resourceCount < 0) {
      throw ArgumentError('Remote fallback snapshot counts must be positive.');
    }
    return DataApiRemoteFallbackSnapshot._(
      remoteBaseUri: normalizedBaseUri,
      capturedAt: capturedAt.toUtc(),
      summary: summary,
    );
  }

  const DataApiRemoteFallbackSnapshot._({
    required this.remoteBaseUri,
    required this.capturedAt,
    required this.summary,
  });

  final Uri remoteBaseUri;
  final DateTime capturedAt;
  final DataApiMigrationSummary summary;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': FileDataApiRemoteFallbackSnapshotStore.currentVersion,
    'remote_base_url': remoteBaseUri.toString(),
    'captured_at': capturedAt.toIso8601String(),
    'resource_count': summary.resourceCount,
    'created': summary.created,
    'updated': summary.updated,
    'skipped': summary.skipped,
  };

  factory DataApiRemoteFallbackSnapshot.fromJson(Map<String, Object?> json) {
    const allowedKeys = <String>{
      'version',
      'remote_base_url',
      'captured_at',
      'resource_count',
      'created',
      'updated',
      'skipped',
    };
    if (json.keys.any((key) => !allowedKeys.contains(key)) ||
        json['version'] !=
            FileDataApiRemoteFallbackSnapshotStore.currentVersion) {
      throw const FormatException(
        'Unsupported remote fallback snapshot document.',
      );
    }
    final remoteBaseUrl = json['remote_base_url'];
    final capturedAt = switch (json['captured_at']) {
      final String value => DateTime.tryParse(value)?.toUtc(),
      _ => null,
    };
    final resourceCount = json['resource_count'];
    final created = json['created'];
    final updated = json['updated'];
    final skipped = json['skipped'];
    if (remoteBaseUrl is! String ||
        capturedAt == null ||
        resourceCount is! int ||
        created is! int ||
        updated is! int ||
        skipped is! int ||
        resourceCount < 0 ||
        created < 0 ||
        updated < 0 ||
        skipped < 0) {
      throw const FormatException('Invalid remote fallback snapshot.');
    }
    return DataApiRemoteFallbackSnapshot(
      remoteBaseUri: Uri.parse(remoteBaseUrl),
      capturedAt: capturedAt,
      summary: DataApiMigrationSummary(
        created: created,
        updated: updated,
        skipped: skipped,
        resourceCount: resourceCount,
      ),
    );
  }
}

abstract interface class DataApiRemoteFallbackSnapshotStore {
  Future<DataApiRemoteFallbackSnapshot?> load();

  Future<void> save(DataApiRemoteFallbackSnapshot snapshot);

  Future<void> clear();
}

final class FileDataApiRemoteFallbackSnapshotStore
    implements DataApiRemoteFallbackSnapshotStore {
  const FileDataApiRemoteFallbackSnapshotStore({required this.file});

  static const int currentVersion = 1;
  static const int _maximumDocumentBytes = 64 * 1024;
  static const String fileName = 'remote-fallback-snapshot.json';

  final File file;

  @override
  Future<DataApiRemoteFallbackSnapshot?> load() async {
    if (!await file.exists()) {
      return null;
    }
    if (await file.length() > _maximumDocumentBytes) {
      throw const FormatException(
        'Remote fallback snapshot document is too large.',
      );
    }
    final root = decodeJsonObject(
      await file.readAsString(),
      documentName: 'Remote fallback snapshot',
    );
    return DataApiRemoteFallbackSnapshot.fromJson(root);
  }

  @override
  Future<void> save(DataApiRemoteFallbackSnapshot snapshot) {
    return writeStringAtomically(file, jsonEncode(snapshot.toJson()));
  }

  @override
  Future<void> clear() async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}

/// Owns the isolated SQLite files used by the last-known-good remote mirror.
///
/// A refresh always writes a fresh staging database. Only a fully migrated,
/// cleanly closed database replaces the prior mirror, so a failed refresh can
/// never corrupt the snapshot used by an offline fallback.
final class FileDataApiRemoteFallbackLocalMirror {
  const FileDataApiRemoteFallbackLocalMirror({
    required this.dataApiDirectory,
    required this.startDatabaseRuntime,
  });

  static const String databaseFileName = 'remote-fallback.db';
  static const String stagingDatabaseFileName = 'remote-fallback.staging.db';
  static const String previousDatabaseFileName = 'remote-fallback.previous.db';
  static const String activeMarkerFileName = 'remote-fallback-active.v1';

  final Directory dataApiDirectory;
  final Future<DataApiRuntime> Function(File database) startDatabaseRuntime;

  File get database => File(
    '${dataApiDirectory.path}${Platform.pathSeparator}$databaseFileName',
  );

  File get stagingDatabase => File(
    '${dataApiDirectory.path}${Platform.pathSeparator}'
    '$stagingDatabaseFileName',
  );

  File get _previousDatabase => File(
    '${dataApiDirectory.path}${Platform.pathSeparator}'
    '$previousDatabaseFileName',
  );

  File get activeMarker => File(
    '${dataApiDirectory.path}${Platform.pathSeparator}$activeMarkerFileName',
  );

  Future<DataApiRuntime> startStagingRuntime() async {
    await dataApiDirectory.create(recursive: true);
    await _deleteDatabaseFiles(stagingDatabase);
    return startDatabaseRuntime(stagingDatabase);
  }

  Future<void> commitStaging() async {
    if (!await stagingDatabase.exists()) {
      throw StateError('The remote fallback staging database is missing.');
    }
    await _requireClosedDatabase(stagingDatabase);
    await _deleteDatabaseFiles(_previousDatabase);
    final hadPriorMirror = await database.exists();
    if (hadPriorMirror) {
      await _requireClosedDatabase(database);
      await database.rename(_previousDatabase.path);
    }
    try {
      await stagingDatabase.rename(database.path);
    } on Object catch (error, stackTrace) {
      if (hadPriorMirror && await _previousDatabase.exists()) {
        await _previousDatabase.rename(database.path);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    await _deleteDatabaseFiles(_previousDatabase);
  }

  Future<void> activate() {
    return writeStringAtomically(activeMarker, 'version=1\n');
  }

  static File databaseFor(Directory appSupportDirectory) {
    return File(
      '${appSupportDirectory.path}${Platform.pathSeparator}data-api'
      '${Platform.pathSeparator}$databaseFileName',
    );
  }

  static File activeMarkerFor(Directory appSupportDirectory) {
    return File(
      '${appSupportDirectory.path}${Platform.pathSeparator}data-api'
      '${Platform.pathSeparator}$activeMarkerFileName',
    );
  }

  Future<void> _requireClosedDatabase(File file) async {
    for (final suffix in const <String>['-wal', '-shm']) {
      if (await File('${file.path}$suffix').exists()) {
        throw StateError(
          'The remote fallback database still has an open SQLite $suffix '
          'sidecar.',
        );
      }
    }
  }

  Future<void> _deleteDatabaseFiles(File file) async {
    for (final path in <String>[
      file.path,
      '${file.path}-wal',
      '${file.path}-shm',
    ]) {
      final candidate = File(path);
      if (await candidate.exists()) {
        await candidate.delete();
      }
    }
  }
}

final class DataApiRemoteFallbackResult {
  const DataApiRemoteFallbackResult({
    required this.snapshot,
    this.cleanupWarning,
  });

  final DataApiRemoteFallbackSnapshot snapshot;
  final Object? cleanupWarning;
}

/// Maintains a last-known-good remote mirror in the bundled local API.
///
/// Refreshes never switch the active deployment. The checkpoint is written
/// only after every exported remote page has merged successfully, so a failed
/// refresh leaves the prior local mirror authoritative for manual fallback.
final class DataApiRemoteFallbackController {
  DataApiRemoteFallbackController({
    required this.remoteRuntime,
    required this.startLocalRuntime,
    required this.configurationRepository,
    required this.snapshotStore,
    DataApiRemoteFallbackMigrationFactory? migrationFactory,
    DataApiRemoteFallbackSnapshotCommitter? commitSnapshot,
    DataApiRemoteFallbackSnapshotActivator? activateLocalSnapshot,
    DateTime Function()? clock,
  }) : _migrationFactory = migrationFactory ?? _defaultRemoteFallbackMigration,
       _commitSnapshot = commitSnapshot ?? _noOpRemoteFallbackAction,
       _activateLocalSnapshot =
           activateLocalSnapshot ?? _noOpRemoteFallbackAction,
       _clock = clock ?? DateTime.now {
    if (remoteRuntime.deployment != DataApiDeployment.remote ||
        !remoteRuntime.canAccessResources) {
      throw ArgumentError(
        'Remote fallback requires an authenticated remote runtime.',
      );
    }
  }

  final DataApiRuntime remoteRuntime;
  final Future<DataApiRuntime> Function() startLocalRuntime;
  final DataApiConfigurationRepository configurationRepository;
  final DataApiRemoteFallbackSnapshotStore snapshotStore;
  final DataApiRemoteFallbackMigrationFactory _migrationFactory;
  final DataApiRemoteFallbackSnapshotCommitter _commitSnapshot;
  final DataApiRemoteFallbackSnapshotActivator _activateLocalSnapshot;
  final DateTime Function() _clock;

  Future<DataApiRemoteFallbackSnapshot>? _refreshFuture;

  Future<DataApiRemoteFallbackSnapshot?> loadSnapshot() async {
    final snapshot = await snapshotStore.load();
    if (snapshot == null || snapshot.remoteBaseUri != remoteRuntime.baseUri) {
      return null;
    }
    return snapshot;
  }

  Future<DataApiRemoteFallbackSnapshot> refreshSnapshot() {
    return _refreshFuture ??= _refreshSnapshot().whenComplete(() {
      _refreshFuture = null;
    });
  }

  Future<DataApiRemoteFallbackSnapshot> _refreshSnapshot() async {
    final summary = await withTemporaryDataApiRuntime<DataApiMigrationSummary>(
      startRuntime: startLocalRuntime,
      operation: (destinationRuntime) {
        if (!destinationRuntime.isLocal ||
            !destinationRuntime.canAccessResources) {
          throw StateError(
            'Remote fallback mirror requires the bundled local API.',
          );
        }
        return _migrationFactory(remoteRuntime, destinationRuntime).migrate();
      },
    );
    await _commitSnapshot();
    final snapshot = DataApiRemoteFallbackSnapshot(
      remoteBaseUri: remoteRuntime.baseUri,
      capturedAt: _clock(),
      summary: summary,
    );
    await snapshotStore.save(snapshot);
    return snapshot;
  }

  Future<DataApiRemoteFallbackResult> fallbackToLocal() async {
    final snapshot = await loadSnapshot();
    if (snapshot == null) {
      throw StateError(
        'No last-known-good remote snapshot is available for this server.',
      );
    }
    final current = await configurationRepository.load();
    if (current.deployment != DataApiDeployment.remote ||
        current.remoteBaseUri != remoteRuntime.baseUri) {
      throw StateError(
        'The active remote configuration changed before fallback.',
      );
    }
    await _activateLocalSnapshot();
    Object? cleanupWarning;
    try {
      await configurationRepository.save(const DataApiConfiguration.local());
    } on DataApiRemoteRevocationPendingWarning catch (warning) {
      // The configuration commit precedes best-effort remote logout. An
      // unavailable remote therefore produces a warning, not a failed local
      // fallback.
      cleanupWarning = warning;
    }
    await snapshotStore.clear();
    return DataApiRemoteFallbackResult(
      snapshot: snapshot,
      cleanupWarning: cleanupWarning,
    );
  }
}
