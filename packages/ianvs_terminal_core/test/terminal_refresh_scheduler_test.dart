import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/src/runtime/terminal_refresh_scheduler.dart';

void main() {
  group('TerminalRefreshScheduler', () {
    test('queues refresh requests while a refresh is active', () {
      final scheduler = TerminalRefreshScheduler();

      scheduler.markRefreshing('session-a');
      scheduler.queueRefresh('session-a');

      expect(scheduler.isRefreshing('session-a'), isTrue);
      expect(scheduler.hasQueuedRefresh('session-a'), isTrue);
      expect(scheduler.consumeQueuedRefresh('session-a'), isTrue);
      expect(scheduler.consumeQueuedRefresh('session-a'), isFalse);

      scheduler.clearRefreshing('session-a');
      expect(scheduler.isRefreshing('session-a'), isFalse);
    });

    test('deduplicates deferred refresh microtasks per session', () async {
      final callbacks = <String>[];
      final scheduler = TerminalRefreshScheduler();

      expect(
        scheduler.scheduleDeferredRefresh('session-a', () {
          callbacks.add('session-a');
        }),
        isTrue,
      );
      expect(
        scheduler.scheduleDeferredRefresh('session-a', () {
          callbacks.add('duplicate');
        }),
        isFalse,
      );

      await Future<void>.delayed(Duration.zero);

      expect(callbacks, <String>['session-a']);
    });

    test('stale deferred microtask cannot clear a replacement token', () async {
      final callbacks = <String>[];
      final scheduler = TerminalRefreshScheduler();
      var duplicateScheduled = false;

      expect(
        scheduler.scheduleDeferredRefresh(
          'session-a',
          () => callbacks.add('stale'),
        ),
        isTrue,
      );
      scheduler.remove('session-a');
      scheduleMicrotask(() {
        duplicateScheduled = scheduler.scheduleDeferredRefresh(
          'session-a',
          () => callbacks.add('duplicate'),
        );
      });
      expect(
        scheduler.scheduleDeferredRefresh(
          'session-a',
          () => callbacks.add('replacement'),
        ),
        isTrue,
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        <Object?>[duplicateScheduled, callbacks],
        <Object?>[
          false,
          <String>['replacement'],
        ],
      );
    });

    testWidgets('runs one queued refresh after cooldown expires', (
      tester,
    ) async {
      final callbacks = <String>[];
      final scheduler = TerminalRefreshScheduler();

      scheduler.queueRefresh('session-a');
      scheduler.startCooldown(
        'session-a',
        const Duration(milliseconds: 33),
        () => callbacks.add('session-a'),
      );

      await tester.pump(const Duration(milliseconds: 32));
      expect(callbacks, isEmpty);
      expect(scheduler.hasQueuedRefresh('session-a'), isTrue);

      await tester.pump(const Duration(milliseconds: 1));
      expect(callbacks, <String>['session-a']);
      expect(scheduler.hasQueuedRefresh('session-a'), isFalse);

      scheduler.dispose();
    });

    testWidgets('deduplicates input probes and permits callback rescheduling', (
      tester,
    ) async {
      final callbacks = <String>[];
      final scheduler = TerminalRefreshScheduler();

      expect(
        scheduler.scheduleInputProbe(
          'session-a',
          const Duration(milliseconds: 4),
          () {
            callbacks.add('first');
            expectSync(
              scheduler.scheduleInputProbe(
                'session-a',
                const Duration(milliseconds: 4),
                () => callbacks.add('second'),
              ),
              isTrue,
            );
          },
        ),
        isTrue,
      );
      expect(
        scheduler.scheduleInputProbe(
          'session-a',
          const Duration(milliseconds: 4),
          () => callbacks.add('duplicate'),
        ),
        isFalse,
      );

      await tester.pump(const Duration(milliseconds: 4));
      expect(callbacks, <String>['first']);

      await tester.pump(const Duration(milliseconds: 4));
      expect(callbacks, <String>['first', 'second']);
      scheduler.dispose();
    });

    testWidgets('remove clears queued and cooldown state', (tester) async {
      final callbacks = <String>[];
      final scheduler = TerminalRefreshScheduler();

      scheduler
        ..markRefreshing('session-a')
        ..queueRefresh('session-a')
        ..startCooldown(
          'session-a',
          const Duration(milliseconds: 33),
          () => callbacks.add('session-a'),
        )
        ..scheduleInputProbe(
          'session-a',
          const Duration(milliseconds: 4),
          () => callbacks.add('input-probe'),
        )
        ..remove('session-a');

      expect(scheduler.isRefreshing('session-a'), isFalse);
      expect(scheduler.hasQueuedRefresh('session-a'), isFalse);

      await tester.pump(const Duration(milliseconds: 33));

      expect(callbacks, isEmpty);
      scheduler.dispose();
    });
  });
}
