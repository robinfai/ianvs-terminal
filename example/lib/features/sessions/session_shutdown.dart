import 'dart:async';

enum SessionShutdownResource { bootstrap, runtime, recording, layout }

final class SessionShutdownResourceFailure {
  const SessionShutdownResourceFailure({
    required this.resource,
    required this.error,
    required this.stackTrace,
  });

  final SessionShutdownResource resource;
  final Object error;
  final StackTrace stackTrace;
}

final class SessionShutdownAggregateException implements Exception {
  SessionShutdownAggregateException(
    Iterable<SessionShutdownResourceFailure> failures,
  ) : failures = List<SessionShutdownResourceFailure>.unmodifiable(failures);

  final List<SessionShutdownResourceFailure> failures;

  @override
  String toString() {
    final resources = failures
        .map((failure) => failure.resource.name)
        .join(', ');
    return 'Session shutdown failed for ${failures.length} resource(s): '
        '$resources.';
  }
}

typedef SessionShutdownOperation = Future<void> Function();

final class SessionShutdownSettler {
  const SessionShutdownSettler();

  Future<void> settle({
    required Map<SessionShutdownResource, Future<void>> startedOperations,
    Map<SessionShutdownResource, SessionShutdownOperation> deferredOperations =
        const <SessionShutdownResource, SessionShutdownOperation>{},
  }) async {
    final failures = <SessionShutdownResourceFailure>[];
    final observedOperations =
        <
          ({
            SessionShutdownResource resource,
            Future<SessionShutdownResourceFailure?> outcome,
          })
        >[
          for (final entry in startedOperations.entries)
            (resource: entry.key, outcome: _observe(entry.key, entry.value)),
        ];
    for (final operation in observedOperations) {
      final failure = await operation.outcome;
      if (failure != null) {
        failures.add(failure);
      }
    }
    for (final entry in deferredOperations.entries) {
      try {
        await entry.value();
      } on Object catch (error, stackTrace) {
        failures.add(
          SessionShutdownResourceFailure(
            resource: entry.key,
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
    }
    if (failures.isNotEmpty) {
      Error.throwWithStackTrace(
        SessionShutdownAggregateException(failures),
        failures.first.stackTrace,
      );
    }
  }

  Future<SessionShutdownResourceFailure?> _observe(
    SessionShutdownResource resource,
    Future<void> operation,
  ) {
    return operation.then<SessionShutdownResourceFailure?>(
      (_) => null,
      onError: (Object error, StackTrace stackTrace) =>
          SessionShutdownResourceFailure(
            resource: resource,
            error: error,
            stackTrace: stackTrace,
          ),
    );
  }
}
