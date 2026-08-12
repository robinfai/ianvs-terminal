import 'package:app/features/sessions/session_shutdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'settles every resource and exposes bootstrap plus layout failures',
    () async {
      final settledResources = <SessionShutdownResource>[];
      final bootstrapError = StateError('bootstrap failed');
      final layoutError = StateError('layout failed');
      SessionShutdownAggregateException? aggregate;

      try {
        await const SessionShutdownSettler().settle(
          startedOperations: <SessionShutdownResource, Future<void>>{
            SessionShutdownResource.bootstrap: Future<void>.sync(() {
              settledResources.add(SessionShutdownResource.bootstrap);
              throw bootstrapError;
            }),
            SessionShutdownResource.runtime: Future<void>.sync(() {
              settledResources.add(SessionShutdownResource.runtime);
            }),
            SessionShutdownResource.recording: Future<void>.sync(() {
              settledResources.add(SessionShutdownResource.recording);
            }),
          },
          deferredOperations:
              <SessionShutdownResource, SessionShutdownOperation>{
                SessionShutdownResource.layout: () async {
                  settledResources.add(SessionShutdownResource.layout);
                  throw layoutError;
                },
              },
        );
      } on SessionShutdownAggregateException catch (error) {
        aggregate = error;
      }

      expect(settledResources, SessionShutdownResource.values);
      expect(aggregate, isNotNull);
      expect(
        aggregate!.failures.map((failure) => failure.resource),
        <SessionShutdownResource>[
          SessionShutdownResource.bootstrap,
          SessionShutdownResource.layout,
        ],
      );
      expect(aggregate.failures[0].error, same(bootstrapError));
      expect(aggregate.failures[1].error, same(layoutError));
      expect(aggregate.failures[0].stackTrace.toString(), isNotEmpty);
      expect(aggregate.failures[1].stackTrace.toString(), isNotEmpty);
    },
  );
}
