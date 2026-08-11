import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../../features/config/data_api_terminal_config_repository.dart';
import '../../features/config/local_terminal_config_repository.dart';
import '../../features/layout/data_api_terminal_layout_repository.dart';
import '../../features/layout/local_terminal_layout_repository.dart';
import '../../features/preferences/app_preferences_repository.dart';
import '../../features/preferences/data_api_app_preferences_repository.dart';
import '../../features/profiles/data_api_profile_repository.dart';
import '../../features/profiles/profile_repository.dart';
import '../../features/shell/data_api_paste_history_repository.dart';
import '../../features/shell/paste_history_repository.dart';
import '../../platform/local_json_file.dart';
import '../services/data_api_client.dart';
import 'data_api_installation_identity_repository.dart';

enum DataApiLegacyResourceMigrationStatus {
  migrated,
  noLocalSource,
  destinationAlreadyExists,
}

final class DataApiLegacyJsonMigrationReport {
  const DataApiLegacyJsonMigrationReport({
    required this.alreadyCompleted,
    required this.resources,
  });

  final bool alreadyCompleted;
  final Map<String, DataApiLegacyResourceMigrationStatus> resources;
}

final class DataApiLegacyJsonMigrationConflictException implements Exception {
  DataApiLegacyJsonMigrationConflictException({
    required Map<String, DataApiLegacyResourceMigrationStatus> resources,
  }) : resources = Map.unmodifiable(resources);

  final Map<String, DataApiLegacyResourceMigrationStatus> resources;

  @override
  String toString() {
    final conflicts = resources.entries
        .where(
          (entry) =>
              entry.value ==
              DataApiLegacyResourceMigrationStatus.destinationAlreadyExists,
        )
        .map((entry) => entry.key)
        .join(', ');
    return 'Local Data API migration conflicts require review: $conflicts. '
        'No completion marker was written and API persistence remains locked.';
  }
}

final class DataApiLegacyJsonMigrationSourceChangedException
    implements Exception {
  DataApiLegacyJsonMigrationSourceChangedException(Iterable<String> paths)
    : paths = List<String>.unmodifiable(paths);

  final List<String> paths;

  @override
  String toString() {
    return 'Local migration source changed while it was being imported: '
        '${paths.join(', ')}. No completion marker was written; retry after '
        'local writes have stopped.';
  }
}

final class DataApiLegacyJsonMigrationBusyException implements Exception {
  const DataApiLegacyJsonMigrationBusyException(this.lockPath);

  final String lockPath;

  @override
  String toString() {
    return 'Another migration for this installation is already running '
        '($lockPath). No completion marker was written.';
  }
}

final class DataApiLegacyJsonMigrationSourceTooLargeException
    implements Exception {
  const DataApiLegacyJsonMigrationSourceTooLargeException({
    required this.path,
    required this.maximumBytes,
  });

  final String path;
  final int maximumBytes;

  @override
  String toString() {
    return 'Local migration source $path exceeds the $maximumBytes-byte '
        'migration limit. No completion marker was written.';
  }
}

final class DataApiLegacyJsonMigrationJournalRecoveryRequiredException
    implements Exception {
  const DataApiLegacyJsonMigrationJournalRecoveryRequiredException({
    required this.path,
    required this.cause,
    this.recoveryId,
  });

  final String path;
  final Object cause;
  final String? recoveryId;

  @override
  String toString() {
    return 'The migration revision journal is corrupt ($path): $cause. '
        'Persistence remains locked; reset the journal explicitly or keep '
        'remote data.';
  }
}

final class DataApiLegacyJsonMigrationSkippedMismatchException
    implements Exception {
  const DataApiLegacyJsonMigrationSkippedMismatchException({
    required this.kind,
    required this.id,
  });

  final String kind;
  final String id;

  @override
  String toString() {
    return 'The server skipped migration resource $kind/$id without an '
        'equivalent stored source revision and payload. No completion marker '
        'was written.';
  }
}

/// Imports only repositories that have production consumers and API provider
/// overrides: profiles, preferences, terminal config, layout and paste history.
/// Theme/template/recent-item files remain explicitly local until those
/// dormant repositories acquire production providers and consumers.
///
/// All incoming resources are submitted to the backend's transactional merge
/// endpoint with `preserve_destination`. A failed merge writes no marker and
/// can be retried; an existing remote resource is reported as a conflict and
/// is never overwritten by the legacy source.
final class DataApiLegacyJsonMigration {
  DataApiLegacyJsonMigration({
    required Directory appSupportDirectory,
    required DataApiResourceClient client,
    required DataApiInstallationIdentity installationIdentity,
  }) : _appSupportDirectory = appSupportDirectory,
       _client = client,
       _installationIdentity = installationIdentity;

  static const markerKind = 'config';
  static const _legacySourceFileNames = <String>[
    'ianvs_profiles.json',
    'ianvs_preferences.json',
    'ianvs_config.json',
    'ianvs_terminal_layout.json',
    'ianvs_paste_history.json',
  ];

  final Directory _appSupportDirectory;
  final DataApiResourceClient _client;
  final DataApiInstallationIdentity _installationIdentity;

  String get markerId => _installationIdentity.migrationMarkerId;
  String get sourceId => _installationIdentity.migrationSourceId;

  Future<void> acknowledgeKeepRemote(
    DataApiLegacyJsonMigrationConflictException conflict,
  ) {
    return _withInstallationLock(() => _acknowledgeKeepRemoteLocked(conflict));
  }

  Future<void> acknowledgeResetRevisionJournal(
    DataApiLegacyJsonMigrationJournalRecoveryRequiredException error,
  ) {
    return _withInstallationLock(() async {
      final journalFile = _revisionJournalFile();
      if (File(error.path).absolute.path != journalFile.absolute.path) {
        throw ArgumentError.value(
          error,
          'error',
          'The recovery error does not match this installation journal.',
        );
      }
      final recoveryId = error.recoveryId;
      if (recoveryId != null) {
        final quarantineFile = File('${journalFile.path}.reset-$recoveryId');
        if (await quarantineFile.exists()) {
          return;
        }
        if (!await journalFile.exists() ||
            await _sha256FileContents(journalFile) != recoveryId) {
          throw ArgumentError.value(
            error,
            'error',
            'The recovery error no longer matches this installation journal.',
          );
        }
        try {
          await journalFile.rename(quarantineFile.path);
        } on FileSystemException {
          if (await quarantineFile.exists()) {
            return;
          }
          rethrow;
        }
        return;
      }
      if (!await journalFile.exists()) {
        throw ArgumentError.value(
          error,
          'error',
          'The recovery error does not match this installation journal.',
        );
      }
      final quarantineFile = File(
        '${journalFile.path}.reset-${DateTime.now().toUtc().microsecondsSinceEpoch}',
      );
      await journalFile.rename(quarantineFile.path);
    });
  }

  Future<void> _acknowledgeKeepRemoteLocked(
    DataApiLegacyJsonMigrationConflictException conflict,
  ) async {
    final conflicts =
        conflict.resources.entries
            .where(
              (entry) =>
                  entry.value ==
                  DataApiLegacyResourceMigrationStatus.destinationAlreadyExists,
            )
            .map((entry) => entry.key)
            .toList(growable: false)
          ..sort();
    if (conflicts.isEmpty) {
      throw ArgumentError.value(
        conflict,
        'conflict',
        'At least one migration conflict is required.',
      );
    }
    final sourceSnapshot = await _captureCompleteSourceSnapshot();
    await _verifyCompleteSourceSnapshot(sourceSnapshot);
    try {
      await _client.putResource(
        kind: markerKind,
        id: markerId,
        data: <String, Object?>{
          'version': 1,
          'decision': 'keep_remote',
          'source_id': sourceId,
          'conflicts': conflicts,
          'source_snapshot': sourceSnapshot.toJson(),
          'acknowledged_at': DateTime.now().toUtc().toIso8601String(),
        },
        expectedRevision: 0,
      );
    } on DataApiRevisionConflictException {
      final concurrentMarker = await _client.getResource(
        kind: markerKind,
        id: markerId,
      );
      if (concurrentMarker == null) {
        rethrow;
      }
      await _validateCompletedMarker(concurrentMarker);
    }
    await _verifyCompleteSourceSnapshot(sourceSnapshot);
  }

  Future<DataApiLegacyJsonMigrationReport> run() {
    return _withInstallationLock(_runLocked);
  }

  Future<DataApiLegacyJsonMigrationReport> _runLocked() async {
    final marker = await _client.getResource(kind: markerKind, id: markerId);
    if (marker != null) {
      await _validateCompletedMarker(marker);
      return const DataApiLegacyJsonMigrationReport(
        alreadyCompleted: true,
        resources: <String, DataApiLegacyResourceMigrationStatus>{},
      );
    }

    Future<Directory> resolveDirectory() async => _appSupportDirectory;
    final statuses = <String, DataApiLegacyResourceMigrationStatus>{};
    final resourceGroups = <String, List<String>>{};
    final incoming = <DataApiMigrationResource>[];
    final sourceSnapshots = <String, _LegacySourceSnapshot>{};
    final absentSourcePaths = <String>{};
    final revisionJournal = await _LegacyMigrationRevisionJournal.load(
      _revisionJournalFile(),
    );

    final profilesFile = _sourceFile('ianvs_profiles.json');
    final profilesSnapshot = await _existingSnapshot(profilesFile);
    if (profilesSnapshot == null) {
      absentSourcePaths.add(profilesFile.path);
      statuses['profiles'] = DataApiLegacyResourceMigrationStatus.noLocalSource;
    } else {
      sourceSnapshots[profilesFile.path] = profilesSnapshot;
      final document = await ProfileRepository(
        directoryResolver: resolveDirectory,
      ).load();
      final payload = encodeDataApiProfilesDocument(document);
      final resourceKey = _resourceKey(
        DataApiProfileRepository.resourceKind,
        DataApiProfileRepository.resourceId,
      );
      incoming.add(
        _migrationResource(
          snapshot: profilesSnapshot,
          sourceRevision: revisionJournal.revisionFor(
            resourceKey: resourceKey,
            snapshot: profilesSnapshot,
          ),
          kind: DataApiProfileRepository.resourceKind,
          id: DataApiProfileRepository.resourceId,
          data: payload.data,
          sensitive: payload.sensitive,
        ),
      );
      resourceGroups['profiles'] = <String>[resourceKey];
      statuses['profiles'] = DataApiLegacyResourceMigrationStatus.migrated;
    }

    await _collectDocument(
      statusName: 'preferences',
      fileName: 'ianvs_preferences.json',
      kind: DataApiAppPreferencesRepository.resourceKind,
      id: DataApiAppPreferencesRepository.resourceId,
      statuses: statuses,
      resourceGroups: resourceGroups,
      incoming: incoming,
      sourceSnapshots: sourceSnapshots,
      absentSourcePaths: absentSourcePaths,
      revisionJournal: revisionJournal,
      load: () async => (await AppPreferencesRepository(
        directoryResolver: resolveDirectory,
      ).load())?.toJson(),
    );
    await _collectDocument(
      statusName: 'terminalConfig',
      fileName: 'ianvs_config.json',
      kind: DataApiTerminalConfigRepository.resourceKind,
      id: DataApiTerminalConfigRepository.resourceId,
      statuses: statuses,
      resourceGroups: resourceGroups,
      incoming: incoming,
      sourceSnapshots: sourceSnapshots,
      absentSourcePaths: absentSourcePaths,
      revisionJournal: revisionJournal,
      load: () async => (await LocalTerminalConfigRepository(
        directoryResolver: resolveDirectory,
      ).load())?.toJson(),
    );
    await _collectDocument(
      statusName: 'terminalLayout',
      fileName: 'ianvs_terminal_layout.json',
      kind: DataApiTerminalLayoutRepository.resourceKind,
      id: DataApiTerminalLayoutRepository.resourceId,
      statuses: statuses,
      resourceGroups: resourceGroups,
      incoming: incoming,
      sourceSnapshots: sourceSnapshots,
      absentSourcePaths: absentSourcePaths,
      revisionJournal: revisionJournal,
      sensitive: true,
      metadata: const <String, Object?>{'format': 'ianvs-terminal-layout-v1'},
      load: () async => (await LocalTerminalLayoutRepository(
        directoryResolver: resolveDirectory,
      ).load())?.toJson(),
    );
    await _collectDocument(
      statusName: 'pasteHistory',
      fileName: 'ianvs_paste_history.json',
      kind: DataApiPasteHistoryRepository.resourceKind,
      id: DataApiPasteHistoryRepository.resourceId,
      statuses: statuses,
      resourceGroups: resourceGroups,
      incoming: incoming,
      sourceSnapshots: sourceSnapshots,
      absentSourcePaths: absentSourcePaths,
      revisionJournal: revisionJournal,
      sensitive: true,
      metadata: const <String, Object?>{'format': 'ianvs-paste-history-v1'},
      load: () async => (await PasteHistoryRepository(
        directoryResolver: resolveDirectory,
      ).load())?.toJson(),
    );

    if (incoming.isNotEmpty) {
      await revisionJournal.save();
      final results = <String, String>{};
      // Each application-generated legacy document fits the backend's single
      // resource envelope, while their combined JSON may exceed the 12 MiB
      // merge limit. Per-resource merge transactions remain restart-safe
      // because sourceId/sourceRevision make already-applied batches skip.
      for (final resource in incoming) {
        final merge = await _client.mergeResources(
          sourceId: sourceId,
          resources: <DataApiMigrationResource>[resource],
        );
        if (merge.results.length != 1 ||
            merge.results.single.kind != resource.kind ||
            merge.results.single.id != resource.id) {
          throw const DataApiProtocolException(
            'migration report did not match its single-resource request.',
          );
        }
        if (merge.results.single.status == 'skipped') {
          await _verifySkippedResource(resource);
        }
        for (final result in merge.results) {
          results[_resourceKey(result.kind, result.id)] = result.status;
        }
      }
      for (final entry in resourceGroups.entries) {
        if (entry.value.any((key) => results[key] == 'conflict')) {
          statuses[entry.key] =
              DataApiLegacyResourceMigrationStatus.destinationAlreadyExists;
        } else if (entry.value.any((key) => results[key] == null)) {
          throw const DataApiProtocolException(
            'migration report omitted an imported resource.',
          );
        }
      }
    }

    if (statuses.values.contains(
      DataApiLegacyResourceMigrationStatus.destinationAlreadyExists,
    )) {
      throw DataApiLegacyJsonMigrationConflictException(resources: statuses);
    }

    await _verifySourceSnapshots(
      sourceSnapshots.values,
      absentSourcePaths: absentSourcePaths,
    );
    final completeSourceSnapshot = _CompleteLegacySourceSnapshot.fromCaptured(
      appSupportDirectory: _appSupportDirectory,
      presentSnapshots: sourceSnapshots.values,
      absentSourcePaths: absentSourcePaths,
      expectedFileNames: _legacySourceFileNames,
    );

    try {
      await _client.putResource(
        kind: markerKind,
        id: markerId,
        data: <String, Object?>{
          'version': 1,
          'decision': 'migrated',
          'source_id': sourceId,
          'source_snapshot': completeSourceSnapshot.toJson(),
          'completed_at': DateTime.now().toUtc().toIso8601String(),
        },
        expectedRevision: 0,
      );
    } on DataApiRevisionConflictException {
      final concurrentMarker = await _client.getResource(
        kind: markerKind,
        id: markerId,
      );
      if (concurrentMarker == null) {
        rethrow;
      }
      await _validateCompletedMarker(concurrentMarker);
    }
    // The marker intentionally remains on the server if this detects a
    // concurrent local write. This launch stays locked, and every later
    // startup rejects the now-stale marker until the user resolves migration.
    await _verifyCompleteSourceSnapshot(completeSourceSnapshot);
    return DataApiLegacyJsonMigrationReport(
      alreadyCompleted: false,
      resources: Map.unmodifiable(statuses),
    );
  }

  Future<void> _collectDocument({
    required String statusName,
    required String fileName,
    required String kind,
    required String id,
    required Map<String, DataApiLegacyResourceMigrationStatus> statuses,
    required Map<String, List<String>> resourceGroups,
    required List<DataApiMigrationResource> incoming,
    required Map<String, _LegacySourceSnapshot> sourceSnapshots,
    required Set<String> absentSourcePaths,
    required _LegacyMigrationRevisionJournal revisionJournal,
    required Future<Map<String, Object?>?> Function() load,
    bool sensitive = false,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final file = _sourceFile(fileName);
    final snapshot = await _existingSnapshot(file);
    if (snapshot == null) {
      absentSourcePaths.add(file.path);
      statuses[statusName] = DataApiLegacyResourceMigrationStatus.noLocalSource;
      return;
    }
    sourceSnapshots[file.path] = snapshot;
    final document = await load();
    if (document == null) {
      statuses[statusName] = DataApiLegacyResourceMigrationStatus.noLocalSource;
      return;
    }
    final resourceKey = _resourceKey(kind, id);
    incoming.add(
      _migrationResource(
        snapshot: snapshot,
        sourceRevision: revisionJournal.revisionFor(
          resourceKey: resourceKey,
          snapshot: snapshot,
        ),
        kind: kind,
        id: id,
        data: sensitive ? metadata : document,
        sensitive: sensitive ? document : null,
      ),
    );
    resourceGroups[statusName] = <String>[resourceKey];
    statuses[statusName] = DataApiLegacyResourceMigrationStatus.migrated;
  }

  DataApiMigrationResource _migrationResource({
    required _LegacySourceSnapshot snapshot,
    required int sourceRevision,
    required String kind,
    required String id,
    required Object? data,
    Object? sensitive,
  }) {
    return DataApiMigrationResource(
      id: id,
      kind: kind,
      data: data,
      sensitive: sensitive,
      sourceRevision: sourceRevision,
      sourceUpdatedAt: snapshot.stat.modified.toUtc(),
    );
  }

  Future<_LegacySourceSnapshot?> _existingSnapshot(File file) async {
    if (!await file.exists()) {
      return null;
    }
    final before = await file.stat();
    if (before.type != FileSystemEntityType.file ||
        before.size > DataApiClient.maximumJsonResponseBytes) {
      throw DataApiLegacyJsonMigrationSourceTooLargeException(
        path: file.path,
        maximumBytes: DataApiClient.maximumJsonResponseBytes,
      );
    }
    final sink = Sha256().toSync().newHashSink();
    var byteCount = 0;
    await for (final chunk in file.openRead()) {
      byteCount += chunk.length;
      if (byteCount > DataApiClient.maximumJsonResponseBytes) {
        throw DataApiLegacyJsonMigrationSourceTooLargeException(
          path: file.path,
          maximumBytes: DataApiClient.maximumJsonResponseBytes,
        );
      }
      sink.add(chunk);
    }
    sink.close();
    final after = await file.stat();
    final snapshot = _LegacySourceSnapshot(
      path: file.path,
      stat: after,
      sha256: _hex(await sink.hash()),
    );
    if (!_LegacySourceSnapshot(
      path: file.path,
      stat: before,
      sha256: '',
    ).matchesStat(after)) {
      throw DataApiLegacyJsonMigrationSourceChangedException(<String>[
        file.path,
      ]);
    }
    return snapshot;
  }

  File _sourceFile(String name) {
    return File('${_appSupportDirectory.path}${Platform.pathSeparator}$name');
  }

  File _revisionJournalFile() {
    return File(
      '${_appSupportDirectory.path}${Platform.pathSeparator}'
      'data-api${Platform.pathSeparator}'
      'migration-revisions-${_installationIdentity.id}.json',
    );
  }

  Future<void> _verifySourceSnapshots(
    Iterable<_LegacySourceSnapshot> snapshots, {
    required Iterable<String> absentSourcePaths,
  }) async {
    final changed = <String>[];
    for (final snapshot in snapshots) {
      final file = File(snapshot.path);
      if (!await file.exists()) {
        changed.add(snapshot.path);
        continue;
      }
      final current = await _existingSnapshot(file);
      if (current == null || !snapshot.matches(current)) {
        changed.add(snapshot.path);
      }
    }
    for (final path in absentSourcePaths) {
      if (await File(path).exists()) {
        changed.add(path);
      }
    }
    if (changed.isNotEmpty) {
      throw DataApiLegacyJsonMigrationSourceChangedException(changed);
    }
  }

  Future<_CompleteLegacySourceSnapshot> _captureCompleteSourceSnapshot() async {
    final present = <_LegacySourceSnapshot>[];
    final absent = <String>[];
    for (final fileName in _legacySourceFileNames) {
      final file = _sourceFile(fileName);
      final snapshot = await _existingSnapshot(file);
      if (snapshot == null) {
        absent.add(file.path);
      } else {
        present.add(snapshot);
      }
    }
    return _CompleteLegacySourceSnapshot.fromCaptured(
      appSupportDirectory: _appSupportDirectory,
      presentSnapshots: present,
      absentSourcePaths: absent,
      expectedFileNames: _legacySourceFileNames,
    );
  }

  Future<void> _verifyCompleteSourceSnapshot(
    _CompleteLegacySourceSnapshot snapshot,
  ) async {
    final current = await _captureCompleteSourceSnapshot();
    final changedFileNames = snapshot.changedFileNames(current);
    if (changedFileNames.isNotEmpty) {
      throw DataApiLegacyJsonMigrationSourceChangedException(
        changedFileNames.map((name) => _sourceFile(name).path),
      );
    }
  }

  Future<void> _validateCompletedMarker(DataApiResource marker) async {
    if (marker.kind != markerKind ||
        marker.id != markerId ||
        marker.deleted ||
        marker.hasSensitive ||
        marker.sensitive != null) {
      throw const DataApiProtocolException(
        'migration marker resource envelope is invalid.',
      );
    }
    final data = marker.data;
    if (data is! Map) {
      throw const DataApiProtocolException(
        'migration marker must contain an object.',
      );
    }
    final root = data.map(
      (key, value) => MapEntry(key.toString(), value as Object?),
    );
    final rawSnapshot = root['source_snapshot'];
    final decision = root['decision'];
    if (root['version'] != 1 ||
        root['source_id'] != sourceId ||
        rawSnapshot is! Map ||
        decision != 'migrated' && decision != 'keep_remote') {
      throw const DataApiProtocolException(
        'migration marker identity, decision, or source snapshot is invalid.',
      );
    }
    switch (decision) {
      case 'migrated':
        if (!_hasExactKeys(root, const <String>{
              'version',
              'decision',
              'source_id',
              'source_snapshot',
              'completed_at',
            }) ||
            !_isUtcTimestamp(root['completed_at'])) {
          throw const DataApiProtocolException(
            'migrated marker is missing required completion fields.',
          );
        }
      case 'keep_remote':
        final conflicts = root['conflicts'];
        if (!_hasExactKeys(root, const <String>{
              'version',
              'decision',
              'source_id',
              'conflicts',
              'source_snapshot',
              'acknowledged_at',
            }) ||
            !_isNonEmptyUniqueStringList(conflicts) ||
            !_isUtcTimestamp(root['acknowledged_at'])) {
          throw const DataApiProtocolException(
            'keep-remote marker is missing acknowledgement or conflicts.',
          );
        }
    }
    final snapshot = _CompleteLegacySourceSnapshot.fromJson(
      rawSnapshot.map(
        (key, value) => MapEntry(key.toString(), value as Object?),
      ),
      expectedFileNames: _legacySourceFileNames,
    );
    await _verifyCompleteSourceSnapshot(snapshot);
    // A second sample closes the verification window itself; a source that
    // changes during the first pass cannot be accepted merely because it had
    // not yet been visited.
    await _verifyCompleteSourceSnapshot(snapshot);
  }

  Future<void> _verifySkippedResource(DataApiMigrationResource incoming) async {
    final stored = await _client.getResource(
      kind: incoming.kind,
      id: incoming.id,
      includeSensitive: true,
    );
    final sensitiveMatches = incoming.sensitive == null
        ? stored?.hasSensitive == false && stored?.sensitive == null
        : stored?.hasSensitive == true &&
              _jsonEquivalent(stored?.sensitive, incoming.sensitive);
    if (stored == null ||
        stored.deleted ||
        stored.sourceId != sourceId ||
        stored.sourceRevision != incoming.sourceRevision ||
        !_jsonEquivalent(stored.data, incoming.data) ||
        !sensitiveMatches) {
      throw DataApiLegacyJsonMigrationSkippedMismatchException(
        kind: incoming.kind,
        id: incoming.id,
      );
    }
  }

  Future<T> _withInstallationLock<T>(Future<T> Function() operation) async {
    final lockFile = File(
      '${_appSupportDirectory.path}${Platform.pathSeparator}'
      'data-api${Platform.pathSeparator}migration-${_installationIdentity.id}.lock',
    );
    if (!_heldMigrationLockPaths.add(lockFile.path)) {
      throw DataApiLegacyJsonMigrationBusyException(lockFile.path);
    }
    RandomAccessFile? handle;
    var locked = false;
    try {
      await lockFile.parent.create(recursive: true);
      handle = await lockFile.open(mode: FileMode.append);
      try {
        await handle.lock(FileLock.exclusive);
        locked = true;
      } on FileSystemException catch (_, stackTrace) {
        Error.throwWithStackTrace(
          DataApiLegacyJsonMigrationBusyException(lockFile.path),
          stackTrace,
        );
      }
      return await operation();
    } finally {
      try {
        if (locked) {
          await handle?.unlock();
        }
      } finally {
        try {
          await handle?.close();
        } finally {
          _heldMigrationLockPaths.remove(lockFile.path);
        }
      }
    }
  }
}

String _resourceKey(String kind, String id) => '$kind/$id';

final Set<String> _heldMigrationLockPaths = <String>{};

final class _LegacySourceSnapshot {
  const _LegacySourceSnapshot({
    required this.path,
    required this.stat,
    required this.sha256,
  });

  final String path;
  final FileStat stat;
  final String sha256;

  bool matches(_LegacySourceSnapshot current) {
    return sha256 == current.sha256 && matchesStat(current.stat);
  }

  bool matchesStat(FileStat current) {
    return current.type == stat.type && current.size == stat.size;
  }
}

final class _CompleteLegacySourceSnapshot {
  _CompleteLegacySourceSnapshot._(Map<String, _BoundLegacySource> files)
    : files = Map<String, _BoundLegacySource>.unmodifiable(files);

  static const _version = 1;

  final Map<String, _BoundLegacySource> files;

  factory _CompleteLegacySourceSnapshot.fromCaptured({
    required Directory appSupportDirectory,
    required Iterable<_LegacySourceSnapshot> presentSnapshots,
    required Iterable<String> absentSourcePaths,
    required Iterable<String> expectedFileNames,
  }) {
    final expected = expectedFileNames.toSet();
    final captured = <String, _BoundLegacySource>{};
    String fileNameFor(String path) {
      final relative = File(path).absolute.uri.pathSegments.last;
      if (!expected.contains(relative)) {
        throw StateError('Unexpected legacy migration source: $path.');
      }
      final expectedPath = File(
        '${appSupportDirectory.path}${Platform.pathSeparator}$relative',
      ).absolute.path;
      if (File(path).absolute.path != expectedPath) {
        throw StateError('Legacy migration source escaped app support: $path.');
      }
      return relative;
    }

    for (final snapshot in presentSnapshots) {
      final name = fileNameFor(snapshot.path);
      if (captured.containsKey(name)) {
        throw StateError('Duplicate legacy migration source: $name.');
      }
      captured[name] = _BoundLegacySource.present(
        sha256: snapshot.sha256,
        size: snapshot.stat.size,
      );
    }
    for (final path in absentSourcePaths) {
      final name = fileNameFor(path);
      if (captured.containsKey(name)) {
        throw StateError('Duplicate legacy migration source: $name.');
      }
      captured[name] = const _BoundLegacySource.absent();
    }
    if (!captured.keys.toSet().containsAll(expected) ||
        !expected.containsAll(captured.keys)) {
      throw StateError('Incomplete legacy migration source snapshot.');
    }
    return _CompleteLegacySourceSnapshot._(captured);
  }

  factory _CompleteLegacySourceSnapshot.fromJson(
    Map<String, Object?> json, {
    required Iterable<String> expectedFileNames,
  }) {
    final rawFiles = json['files'];
    if (!_hasExactKeys(json, const <String>{'version', 'files'}) ||
        json['version'] != _version ||
        rawFiles is! Map) {
      throw const DataApiProtocolException(
        'migration marker has an invalid source snapshot.',
      );
    }
    final expected = expectedFileNames.toSet();
    final decoded = <String, _BoundLegacySource>{};
    for (final MapEntry(:key, :value) in rawFiles.entries) {
      if (key is! String || !expected.contains(key) || value is! Map) {
        throw const DataApiProtocolException(
          'migration marker has an invalid source snapshot entry.',
        );
      }
      final entry = value.map(
        (entryKey, entryValue) =>
            MapEntry(entryKey.toString(), entryValue as Object?),
      );
      final present = entry['present'];
      if (present == false) {
        if (entry.keys.length != 1) {
          throw const DataApiProtocolException(
            'absent migration source snapshot contains extra fields.',
          );
        }
        decoded[key] = const _BoundLegacySource.absent();
        continue;
      }
      final sha256 = entry['sha256'];
      final size = entry['size'];
      if (present != true ||
          sha256 is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256) ||
          size is! int ||
          size < 0 ||
          size > DataApiClient.maximumJsonResponseBytes ||
          entry.keys.length != 3) {
        throw const DataApiProtocolException(
          'present migration source snapshot is invalid.',
        );
      }
      decoded[key] = _BoundLegacySource.present(sha256: sha256, size: size);
    }
    if (!decoded.keys.toSet().containsAll(expected) ||
        !expected.containsAll(decoded.keys)) {
      throw const DataApiProtocolException(
        'migration marker source snapshot is incomplete.',
      );
    }
    return _CompleteLegacySourceSnapshot._(decoded);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'version': _version,
    'files': <String, Object?>{
      for (final name in files.keys.toList(growable: false)..sort())
        name: files[name]!.toJson(),
    },
  };

  List<String> changedFileNames(_CompleteLegacySourceSnapshot current) {
    return files.keys
        .where((name) => files[name] != current.files[name])
        .toList(growable: false);
  }
}

final class _BoundLegacySource {
  const _BoundLegacySource.present({required this.sha256, required this.size})
    : present = true;

  const _BoundLegacySource.absent()
    : present = false,
      sha256 = null,
      size = null;

  final bool present;
  final String? sha256;
  final int? size;

  Map<String, Object?> toJson() => <String, Object?>{
    'present': present,
    if (present) ...<String, Object?>{'sha256': sha256, 'size': size},
  };

  @override
  bool operator ==(Object other) {
    return other is _BoundLegacySource &&
        other.present == present &&
        other.sha256 == sha256 &&
        other.size == size;
  }

  @override
  int get hashCode => Object.hash(present, sha256, size);
}

final class _LegacyMigrationRevisionJournal {
  _LegacyMigrationRevisionJournal._({
    required this.file,
    required Map<String, _LegacyMigrationRevisionEntry> entries,
  }) : _entries = entries;

  static const _maximumRevision = 0x7fffffffffffffff;

  final File file;
  final Map<String, _LegacyMigrationRevisionEntry> _entries;
  var _dirty = false;

  static Future<_LegacyMigrationRevisionJournal> load(File file) async {
    if (!await file.exists()) {
      return _LegacyMigrationRevisionJournal._(
        file: file,
        entries: <String, _LegacyMigrationRevisionEntry>{},
      );
    }
    late final String contents;
    try {
      contents = await file.readAsString();
      final root = decodeJsonObject(
        contents,
        documentName: 'Data API migration revision journal',
      );
      final rawEntries = root['resources'];
      if (root['version'] != 1 || rawEntries is! Map) {
        throw const FormatException(
          'Invalid Data API migration revision journal.',
        );
      }
      final entries = <String, _LegacyMigrationRevisionEntry>{};
      for (final MapEntry(:key, :value) in rawEntries.entries) {
        if (key is! String || value is! Map) {
          throw const FormatException(
            'Invalid Data API migration revision entry.',
          );
        }
        final hash = value['sha256'];
        final revision = value['revision'];
        if (hash is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
            revision is! int ||
            revision <= 0 ||
            revision > _maximumRevision) {
          throw const FormatException(
            'Invalid Data API migration revision entry.',
          );
        }
        entries[key] = _LegacyMigrationRevisionEntry(
          sha256: hash,
          revision: revision,
        );
      }
      return _LegacyMigrationRevisionJournal._(file: file, entries: entries);
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        DataApiLegacyJsonMigrationJournalRecoveryRequiredException(
          path: file.path,
          cause: error,
          recoveryId: await _sha256String(contents),
        ),
        stackTrace,
      );
    }
  }

  int revisionFor({
    required String resourceKey,
    required _LegacySourceSnapshot snapshot,
  }) {
    final previous = _entries[resourceKey];
    if (previous?.sha256 == snapshot.sha256) {
      return previous!.revision;
    }
    final modifiedRevision = snapshot.stat.modified.microsecondsSinceEpoch;
    final minimumNext = previous == null ? 1 : previous.revision + 1;
    final revision = max(minimumNext, max(1, modifiedRevision));
    if (revision > _maximumRevision) {
      throw StateError('Data API migration source revision overflow.');
    }
    _entries[resourceKey] = _LegacyMigrationRevisionEntry(
      sha256: snapshot.sha256,
      revision: revision,
    );
    _dirty = true;
    return revision;
  }

  Future<void> save() async {
    if (!_dirty) {
      return;
    }
    await writeStringAtomically(
      file,
      '${jsonEncode(<String, Object?>{
        'version': 1,
        'resources': <String, Object?>{
          for (final MapEntry(:key, :value) in _entries.entries) key: <String, Object?>{'sha256': value.sha256, 'revision': value.revision},
        },
      })}\n',
    );
    _dirty = false;
  }
}

final class _LegacyMigrationRevisionEntry {
  const _LegacyMigrationRevisionEntry({
    required this.sha256,
    required this.revision,
  });

  final String sha256;
  final int revision;
}

String _hex(Hash hash) {
  return hash.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

Future<String> _sha256String(String contents) async {
  final sink = Sha256().toSync().newHashSink();
  sink.add(utf8.encode(contents));
  sink.close();
  return _hex(await sink.hash());
}

Future<String> _sha256FileContents(File file) async {
  final sink = Sha256().toSync().newHashSink();
  await for (final chunk in file.openRead()) {
    sink.add(chunk);
  }
  sink.close();
  return _hex(await sink.hash());
}

bool _jsonEquivalent(Object? left, Object? right) {
  return jsonEncode(_canonicalJson(left)) == jsonEncode(_canonicalJson(right));
}

bool _hasExactKeys(Map<String, Object?> value, Set<String> expected) {
  final actual = value.keys.toSet();
  return actual.length == expected.length && actual.containsAll(expected);
}

bool _isUtcTimestamp(Object? value) {
  final parsed = value is String ? DateTime.tryParse(value) : null;
  return parsed != null && parsed.isUtc;
}

bool _isNonEmptyUniqueStringList(Object? value) {
  if (value is! List || value.isEmpty) {
    return false;
  }
  final seen = <String>{};
  for (final entry in value) {
    if (entry is! String || entry.isEmpty || !seen.add(entry)) {
      return false;
    }
  }
  return true;
}

Object? _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalJson(value[key]),
    };
  }
  if (value is List) {
    return value.map(_canonicalJson).toList(growable: false);
  }
  return value;
}
