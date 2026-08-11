import 'dart:async';

import 'package:app/platform/app_shutdown_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rejects a non-positive shutdown timeout', () {
    expect(
      () => AppShutdownCoordinator(timeout: Duration.zero),
      throwsArgumentError,
    );
  });

  test(
    'runs all shutdown tasks once and shares the in-flight result',
    () async {
      final coordinator = AppShutdownCoordinator();
      final firstTaskGate = Completer<void>();
      var firstTaskCount = 0;
      var secondTaskCount = 0;
      coordinator
        ..registerTask('first', () async {
          firstTaskCount += 1;
          await firstTaskGate.future;
        })
        ..registerTask('second', () async {
          secondTaskCount += 1;
        });

      final firstShutdown = coordinator.shutdown();
      final repeatedShutdown = coordinator.shutdown();

      expect(identical(firstShutdown, repeatedShutdown), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(firstTaskCount, 1);
      expect(secondTaskCount, 1);

      firstTaskGate.complete();
      final result = await firstShutdown;

      expect(result.timedOut, isFalse);
      expect(result.totalTaskCount, 2);
      expect(result.settledTaskCount, 2);
      expect(result.failures, isEmpty);
    },
  );

  test('captures task failures without skipping other cleanup', () async {
    final coordinator = AppShutdownCoordinator();
    var successfulTaskRan = false;
    coordinator
      ..registerTask('failing', () async {
        throw StateError('cleanup failed');
      })
      ..registerTask('successful', () async {
        successfulTaskRan = true;
      });

    final result = await coordinator.shutdown();

    expect(successfulTaskRan, isTrue);
    expect(result.timedOut, isFalse);
    expect(result.settledTaskCount, 2);
    expect(result.failures, hasLength(1));
    expect(result.failures.single.taskName, 'failing');
    expect(result.failures.single.error, isA<StateError>());
    expect(result.toPlatformMessage(), containsPair('failureCount', 1));
  });

  test('settles application work before infrastructure cleanup', () async {
    final coordinator = AppShutdownCoordinator();
    final applicationGate = Completer<void>();
    final timeline = <String>[];
    coordinator
      ..registerTask('application', () async {
        timeline.add('application-start');
        await applicationGate.future;
        timeline.add('application-complete');
      })
      ..registerTask('infrastructure', () async {
        timeline.add('infrastructure');
      }, phase: AppShutdownPhase.infrastructure);

    final shutdown = coordinator.shutdown();
    await Future<void>.delayed(Duration.zero);

    expect(timeline, <String>['application-start']);
    applicationGate.complete();
    await shutdown;
    expect(timeline, <String>[
      'application-start',
      'application-complete',
      'infrastructure',
    ]);
  });

  test('returns at the global timeout when a task never settles', () async {
    final coordinator = AppShutdownCoordinator(
      timeout: const Duration(milliseconds: 20),
    );
    final stalledTask = Completer<void>();
    coordinator.registerTask('stalled', () => stalledTask.future);

    final result = await coordinator.shutdown();

    expect(result.timedOut, isTrue);
    expect(result.totalTaskCount, 1);
    expect(result.settledTaskCount, 0);
    expect(result.toPlatformMessage(), containsPair('completed', false));

    stalledTask.complete();
    final settled = await coordinator.settle();
    expect(settled.timedOut, isFalse);
    expect(settled.settledTaskCount, 1);
  });

  test(
    'an unbounded teardown start preserves a later bounded response',
    () async {
      final coordinator = AppShutdownCoordinator(
        timeout: const Duration(milliseconds: 1),
      );
      final gate = Completer<void>();
      var runCount = 0;
      coordinator.registerTask('application', () async {
        runCount += 1;
        await gate.future;
      });

      final settlement = coordinator.shutdown(bounded: false);
      expect(coordinator.hasStarted, isTrue);
      expect(runCount, 1);

      final bounded = await coordinator.shutdown();
      expect(bounded.timedOut, isTrue);
      expect(runCount, 1);

      gate.complete();
      expect((await settlement).timedOut, isFalse);
      expect((await coordinator.settle()).settledTaskCount, 1);
    },
  );

  test('a timed-out task settles once before the next phase starts', () async {
    final coordinator = AppShutdownCoordinator(
      timeout: const Duration(milliseconds: 1),
    );
    final gate = Completer<void>();
    final timeline = <String>[];
    var applicationRunCount = 0;
    coordinator
      ..registerTask('application', () async {
        applicationRunCount += 1;
        timeline.add('application-start');
        await gate.future;
        timeline.add('application-settled');
      })
      ..registerTask('infrastructure', () async {
        timeline.add('infrastructure');
      }, phase: AppShutdownPhase.infrastructure);

    final bounded = await coordinator.shutdown();
    expect(bounded.timedOut, isTrue);
    expect(timeline, <String>['application-start']);

    gate.complete();
    final settled = await coordinator.settle();
    expect(settled.timedOut, isFalse);
    expect(settled.settledTaskCount, 2);
    expect(applicationRunCount, 1);
    expect(timeline, <String>[
      'application-start',
      'application-settled',
      'infrastructure',
    ]);
  });

  test('rejects task registration after shutdown starts', () async {
    final coordinator = AppShutdownCoordinator();

    final shutdown = coordinator.shutdown();

    expect(
      () => coordinator.registerTask('too-late', () async {}),
      throwsStateError,
    );
    await shutdown;
  });

  test(
    'marks shutdown started before invoking synchronous task bodies',
    () async {
      final coordinator = AppShutdownCoordinator();
      late Future<AppShutdownResult> reentrant;
      coordinator.registerTask('application', () async {
        expect(coordinator.hasStarted, isTrue);
        expect(
          () => coordinator.registerTask('too-late', () async {}),
          throwsStateError,
        );
        reentrant = coordinator.shutdown(bounded: false);
      });

      final shutdown = coordinator.shutdown(bounded: false);
      final result = await shutdown;

      expect(identical(shutdown, reentrant), isTrue);
      expect(result.settledTaskCount, 1);
    },
  );
}
