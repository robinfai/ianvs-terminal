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
}
