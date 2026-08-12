import 'data_api_client.dart';
import 'data_api_runtime.dart';

final class DataApiMigrationSummary {
  const DataApiMigrationSummary({
    required this.created,
    required this.updated,
    required this.skipped,
    required this.resourceCount,
  });

  final int created;
  final int updated;
  final int skipped;
  final int resourceCount;
}

final class DataApiMigrationIncompleteException implements Exception {
  const DataApiMigrationIncompleteException({required this.conflicts});

  final List<DataApiMigrationMergeItem> conflicts;

  @override
  String toString() {
    return 'Destination merge reported ${conflicts.length} conflict(s); the '
        'source remains active and its data was not removed.';
  }
}

final class DataApiExplicitMigrationRequiredException implements Exception {
  const DataApiExplicitMigrationRequiredException();

  @override
  String toString() {
    return 'Bundled local API data must be migrated from the running app '
        'before switching to a remote API.';
  }
}

final class DataApiMigrationRuntimeCleanupException implements Exception {
  const DataApiMigrationRuntimeCleanupException({
    required this.operationError,
    required this.cleanupError,
  });

  final Object operationError;
  final Object cleanupError;

  @override
  String toString() {
    return 'Data API migration failed ($operationError), and the temporary '
        'local API did not close cleanly ($cleanupError).';
  }
}

/// Runs one migration operation against a temporary local runtime and retains
/// both the operation and cleanup evidence if they fail together.
Future<T> withTemporaryDataApiRuntime<T>({
  required Future<DataApiRuntime> Function() startRuntime,
  required Future<T> Function(DataApiRuntime runtime) operation,
}) async {
  final runtime = await startRuntime();
  Object? operationError;
  StackTrace? operationStackTrace;
  late T result;
  try {
    result = await operation(runtime);
  } on Object catch (error, stackTrace) {
    operationError = error;
    operationStackTrace = stackTrace;
  }
  try {
    await runtime.close();
  } on Object catch (cleanupError, cleanupStackTrace) {
    if (operationError != null) {
      Error.throwWithStackTrace(
        DataApiMigrationRuntimeCleanupException(
          operationError: operationError,
          cleanupError: cleanupError,
        ),
        operationStackTrace!,
      );
    }
    Error.throwWithStackTrace(cleanupError, cleanupStackTrace);
  }
  if (operationError != null) {
    Error.throwWithStackTrace(operationError, operationStackTrace!);
  }
  return result;
}

/// Copies a bounded, current migration export between two Data API runtimes.
///
/// The source remains untouched. Pages are merged idempotently under the
/// source server identity, so a failed attempt can be retried safely before
/// the deployment configuration is switched.
final class DataApiMigrationService {
  const DataApiMigrationService({
    required this.source,
    required this.destination,
    this.conflictPolicy = DataApiMigrationConflictPolicy.preserveDestination,
  });

  static const int _maximumPages = 1024;

  final DataApiMigrationClient source;
  final DataApiMigrationClient destination;
  final DataApiMigrationConflictPolicy conflictPolicy;

  Future<DataApiMigrationSummary> migrate() async {
    String? cursor;
    String? sourceId;
    final observedCursors = <String>{};
    var pageCount = 0;
    var created = 0;
    var updated = 0;
    var skipped = 0;
    var resourceCount = 0;
    final conflicts = <DataApiMigrationMergeItem>[];

    do {
      pageCount += 1;
      if (pageCount > _maximumPages) {
        throw const FormatException(
          'Data API migration exceeded the bounded page limit.',
        );
      }
      final page = await source.exportMigrationPage(cursor: cursor);
      sourceId ??= page.sourceId;
      if (page.sourceId != sourceId) {
        throw const FormatException(
          'Data API migration source changed during export.',
        );
      }
      if (page.resources.isNotEmpty) {
        final report = await destination.mergeResources(
          sourceId: sourceId,
          resources: page.resources,
          conflictPolicy: conflictPolicy,
        );
        final expectedResults = {
          for (final resource in page.resources)
            '${resource.kind}\u0000${resource.id}',
        };
        final observedResults = <String>{};
        for (final result in report.results) {
          final identity = '${result.kind}\u0000${result.id}';
          if (!expectedResults.contains(identity) ||
              !observedResults.add(identity)) {
            throw const FormatException(
              'Data API migration report contains an invalid identity.',
            );
          }
        }
        if (observedResults.length != expectedResults.length) {
          throw const FormatException(
            'Data API migration report omitted a resource result.',
          );
        }
        resourceCount += page.resources.length;
        for (final result in report.results) {
          switch (result.status) {
            case 'created':
              created += 1;
            case 'updated':
              updated += 1;
            case 'skipped':
              skipped += 1;
            case 'conflict':
              conflicts.add(result);
            case 'deleted':
              throw const FormatException(
                'Non-destructive migration unexpectedly deleted a resource.',
              );
          }
        }
      }
      cursor = page.nextCursor;
      if (cursor != null && !observedCursors.add(cursor)) {
        throw const FormatException(
          'Data API migration export repeated a cursor.',
        );
      }
    } while (cursor != null);

    if (conflicts.isNotEmpty) {
      throw DataApiMigrationIncompleteException(
        conflicts: List.unmodifiable(conflicts),
      );
    }
    return DataApiMigrationSummary(
      created: created,
      updated: updated,
      skipped: skipped,
      resourceCount: resourceCount,
    );
  }
}
