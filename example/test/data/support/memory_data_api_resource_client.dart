import 'dart:convert';

import 'package:app/data/services/data_api_client.dart';

typedef MemoryDataApiBeforePut =
    void Function(MemoryDataApiResourceClient client, String kind, String id);
typedef MemoryDataApiBeforeMerge =
    Future<void> Function(MemoryDataApiResourceClient client, int mergeCount);
typedef MemoryDataApiPutResponse =
    DataApiResource Function(DataApiResource resource);

final DateTime _testResourceTimestamp = DateTime.utc(2026);

DataApiResource dataApiTestResource({
  required String id,
  required String kind,
  required Object? data,
  Object? sensitive,
  bool? hasSensitive,
  int revision = 1,
  String sourceId = '',
  int sourceRevision = 1,
  DateTime? sourceUpdatedAt,
  bool deleted = false,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  return DataApiResource(
    id: id,
    kind: kind,
    data: data,
    sensitive: sensitive,
    hasSensitive: hasSensitive ?? sensitive != null,
    revision: revision,
    sourceId: sourceId,
    sourceRevision: sourceRevision,
    sourceUpdatedAt: sourceUpdatedAt ?? _testResourceTimestamp,
    deleted: deleted,
    createdAt: createdAt ?? _testResourceTimestamp,
    updatedAt: updatedAt ?? _testResourceTimestamp,
  );
}

final class MemoryDataApiResourceClient implements DataApiResourceClient {
  MemoryDataApiResourceClient({this.canAccessResources = true});

  @override
  final bool canAccessResources;

  final Map<String, DataApiResource> resources = <String, DataApiResource>{};
  final Set<String> deletedResourceKeys = <String>{};
  final Map<String, String> migrationSourceIds = <String, String>{};
  final Map<String, int> migrationSourceRevisions = <String, int>{};
  final Set<String> failNextPutKeys = <String>{};
  int putCount = 0;
  int getCount = 0;
  int deleteCount = 0;
  int mergeCount = 0;
  int mergeFailuresRemaining = 0;
  final Set<int> failMergeCalls = <int>{};
  final Set<String> forceSkippedMergeKeys = <String>{};
  MemoryDataApiBeforePut? beforePut;
  MemoryDataApiBeforeMerge? beforeMerge;
  MemoryDataApiPutResponse? putResponse;

  String key(String kind, String id) => '$kind/$id';

  @override
  Future<bool> deleteResource({
    required String kind,
    required String id,
    int? expectedRevision,
  }) async {
    _ensureAuthenticated();
    deleteCount += 1;
    final resourceKey = key(kind, id);
    final existing = resources[resourceKey];
    if (existing == null || deletedResourceKeys.contains(resourceKey)) {
      return false;
    }
    final conflicts = switch (expectedRevision) {
      null => false,
      0 => true,
      final revision => existing.revision != revision,
    };
    if (conflicts) {
      throw const DataApiRevisionConflictException(
        message: 'Expected revision did not match.',
      );
    }
    final now = DateTime.now().toUtc();
    resources[resourceKey] = DataApiResource(
      id: existing.id,
      kind: existing.kind,
      data: const <String, Object?>{},
      sensitive: null,
      hasSensitive: false,
      revision: existing.revision + 1,
      sourceId: existing.sourceId,
      sourceRevision: existing.sourceRevision,
      sourceUpdatedAt: existing.sourceUpdatedAt,
      deleted: true,
      createdAt: existing.createdAt,
      updatedAt: now,
    );
    deletedResourceKeys.add(resourceKey);
    return true;
  }

  @override
  Future<DataApiResource?> getResource({
    required String kind,
    required String id,
    bool includeSensitive = false,
  }) async {
    _ensureAuthenticated();
    getCount += 1;
    final resource = resources[key(kind, id)];
    if (resource == null || deletedResourceKeys.contains(key(kind, id))) {
      return null;
    }
    if (includeSensitive) {
      return resource;
    }
    return DataApiResource(
      id: resource.id,
      kind: resource.kind,
      data: resource.data,
      sensitive: null,
      hasSensitive: resource.hasSensitive,
      revision: resource.revision,
      sourceId: resource.sourceId,
      sourceRevision: resource.sourceRevision,
      sourceUpdatedAt: resource.sourceUpdatedAt,
      deleted: resource.deleted,
      createdAt: resource.createdAt,
      updatedAt: resource.updatedAt,
    );
  }

  @override
  Future<DataApiResourcePage> listResourcePage({
    String? kind,
    bool includeSensitive = false,
    int limit = DataApiClient.maximumPageSize,
    String? cursor,
  }) async {
    _ensureAuthenticated();
    if (limit < 1 || limit > DataApiClient.maximumPageSize) {
      throw RangeError.range(limit, 1, DataApiClient.maximumPageSize, 'limit');
    }
    final all =
        resources.values
            .where((resource) => kind == null || resource.kind == kind)
            .where(
              (resource) => !deletedResourceKeys.contains(
                key(resource.kind, resource.id),
              ),
            )
            .map(
              (resource) => includeSensitive
                  ? resource
                  : DataApiResource(
                      id: resource.id,
                      kind: resource.kind,
                      data: resource.data,
                      sensitive: null,
                      hasSensitive: resource.hasSensitive,
                      revision: resource.revision,
                      sourceId: resource.sourceId,
                      sourceRevision: resource.sourceRevision,
                      sourceUpdatedAt: resource.sourceUpdatedAt,
                      deleted: resource.deleted,
                      createdAt: resource.createdAt,
                      updatedAt: resource.updatedAt,
                    ),
            )
            .toList(growable: false)
          ..sort((left, right) {
            final kindOrder = left.kind.compareTo(right.kind);
            return kindOrder == 0 ? left.id.compareTo(right.id) : kindOrder;
          });
    final start = cursor == null ? 0 : int.tryParse(cursor);
    if (start == null || start < 0 || start > all.length) {
      throw const DataApiProtocolException('invalid memory page cursor.');
    }
    final end = (start + limit).clamp(0, all.length);
    return DataApiResourcePage(
      resources: all.sublist(start, end),
      nextCursor: end < all.length ? end.toString() : null,
    );
  }

  @override
  Future<DataApiMigrationMergeReport> mergeResources({
    required String sourceId,
    required List<DataApiMigrationResource> resources,
    DataApiMigrationConflictPolicy conflictPolicy =
        DataApiMigrationConflictPolicy.preserveDestination,
  }) async {
    _ensureAuthenticated();
    mergeCount += 1;
    if (mergeFailuresRemaining > 0) {
      mergeFailuresRemaining -= 1;
      throw const DataApiRequestException(
        statusCode: 503,
        code: 'test_failure',
        message: 'Injected migration failure.',
      );
    }
    if (failMergeCalls.remove(mergeCount)) {
      throw const DataApiRequestException(
        statusCode: 503,
        code: 'test_failure',
        message: 'Injected migration failure.',
      );
    }
    final mergeHook = beforeMerge;
    if (mergeHook != null) {
      await mergeHook(this, mergeCount);
    }
    final results = <DataApiMigrationMergeItem>[];
    for (final incoming in resources) {
      final resourceKey = key(incoming.kind, incoming.id);
      final existing = this.resources[resourceKey];
      if (forceSkippedMergeKeys.contains(resourceKey)) {
        results.add(
          DataApiMigrationMergeItem(
            kind: incoming.kind,
            id: incoming.id,
            status: 'skipped',
            reason: 'injected unverified skip',
          ),
        );
        continue;
      }
      if (existing != null) {
        final priorSourceRevision = migrationSourceRevisions[resourceKey] ?? 0;
        if (migrationSourceIds[resourceKey] == sourceId) {
          if (priorSourceRevision > incoming.sourceRevision) {
            results.add(
              DataApiMigrationMergeItem(
                kind: incoming.kind,
                id: incoming.id,
                status: 'skipped',
                reason: 'a newer source revision was already applied',
              ),
            );
            continue;
          }
          final samePlain =
              jsonEncode(existing.data) == jsonEncode(incoming.data);
          final sameSuppliedSensitive =
              incoming.sensitive == null ||
              jsonEncode(existing.sensitive) == jsonEncode(incoming.sensitive);
          if (priorSourceRevision == incoming.sourceRevision) {
            if (samePlain && sameSuppliedSensitive) {
              results.add(
                DataApiMigrationMergeItem(
                  kind: incoming.kind,
                  id: incoming.id,
                  status: 'skipped',
                  reason: 'source revision and content were already applied',
                ),
              );
            } else {
              results.add(
                DataApiMigrationMergeItem(
                  kind: incoming.kind,
                  id: incoming.id,
                  status: 'conflict',
                  reason: 'equal source revision has different content',
                ),
              );
            }
            continue;
          }
          final nextSensitive = incoming.sensitive ?? existing.sensitive;
          final now = DateTime.now().toUtc();
          this.resources[resourceKey] = DataApiResource(
            id: incoming.id,
            kind: incoming.kind,
            data: incoming.data,
            sensitive: nextSensitive,
            hasSensitive: nextSensitive != null,
            revision: existing.revision + 1,
            sourceId: sourceId,
            sourceRevision: incoming.sourceRevision,
            sourceUpdatedAt: incoming.sourceUpdatedAt,
            deleted: false,
            createdAt: existing.createdAt,
            updatedAt: now,
          );
          migrationSourceRevisions[resourceKey] = incoming.sourceRevision;
          results.add(
            DataApiMigrationMergeItem(
              kind: incoming.kind,
              id: incoming.id,
              status: 'updated',
            ),
          );
          continue;
        }
        results.add(
          DataApiMigrationMergeItem(
            kind: incoming.kind,
            id: incoming.id,
            status: 'conflict',
          ),
        );
        continue;
      }
      final now = DateTime.now().toUtc();
      this.resources[resourceKey] = DataApiResource(
        id: incoming.id,
        kind: incoming.kind,
        data: incoming.data,
        sensitive: incoming.sensitive,
        hasSensitive: incoming.sensitive != null,
        revision: 1,
        sourceId: sourceId,
        sourceRevision: incoming.sourceRevision,
        sourceUpdatedAt: incoming.sourceUpdatedAt,
        deleted: false,
        createdAt: now,
        updatedAt: now,
      );
      migrationSourceIds[resourceKey] = sourceId;
      migrationSourceRevisions[resourceKey] = incoming.sourceRevision;
      results.add(
        DataApiMigrationMergeItem(
          kind: incoming.kind,
          id: incoming.id,
          status: 'created',
        ),
      );
    }
    return DataApiMigrationMergeReport(results: results);
  }

  @override
  Future<DataApiResource> putResource({
    required String kind,
    required String id,
    required Object? data,
    Object? sensitive,
    bool clearSensitive = false,
    int? expectedRevision,
  }) async {
    _ensureAuthenticated();
    final resourceKey = key(kind, id);
    final hook = beforePut;
    if (hook != null) {
      beforePut = null;
      hook(this, kind, id);
    }
    final existing = resources[resourceKey];
    if (failNextPutKeys.remove(resourceKey)) {
      throw const DataApiRequestException(
        statusCode: 503,
        code: 'test_failure',
        message: 'Injected put failure.',
      );
    }
    final conflicts = switch (expectedRevision) {
      null => false,
      0 => existing != null,
      final revision => existing?.revision != revision,
    };
    if (conflicts) {
      throw const DataApiRevisionConflictException(
        message: 'Expected revision did not match.',
      );
    }
    putCount += 1;
    final nextSensitive = clearSensitive
        ? null
        : sensitive ?? existing?.sensitive;
    final now = DateTime.now().toUtc();
    final saved = DataApiResource(
      id: id,
      kind: kind,
      data: data,
      sensitive: nextSensitive,
      hasSensitive: nextSensitive != null,
      revision: (existing?.revision ?? 0) + 1,
      sourceId: existing?.sourceId ?? '',
      sourceRevision: (existing?.sourceRevision ?? 0) + 1,
      sourceUpdatedAt: now,
      deleted: false,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    resources[resourceKey] = saved;
    deletedResourceKeys.remove(resourceKey);
    migrationSourceIds.remove(resourceKey);
    migrationSourceRevisions.remove(resourceKey);
    return putResponse?.call(saved) ?? saved;
  }

  void _ensureAuthenticated() {
    if (!canAccessResources) {
      throw const DataApiAuthenticationRequiredException();
    }
  }
}
