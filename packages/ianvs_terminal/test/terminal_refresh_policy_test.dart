import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/src/runtime/terminal_frame_pump.dart';
import 'package:ianvs_terminal/src/runtime/terminal_refresh_policy.dart';
import 'package:ianvs_terminal/src/terminal/terminal_models.dart';

void main() {
  group(TerminalRefreshPolicy, () {
    late TerminalRefreshPolicy policy;

    setUp(() {
      policy = _newPolicy();
    });

    test('uses the exact four classes and grace durations', () {
      expect(TerminalRefreshClass.values.map((value) => value.name), <String>[
        'interactive',
        'streaming',
        'background',
        'idle',
      ]);

      policy.recordActivation('session', now: Duration.zero, active: true);
      expect(
        policy
            .snapshot('session', now: const Duration(microseconds: 499999))
            .refreshClass,
        TerminalRefreshClass.interactive,
      );
      expect(
        policy
            .snapshot('session', now: const Duration(milliseconds: 500))
            .refreshClass,
        TerminalRefreshClass.idle,
      );

      expect(
        policy
            .snapshot('unknown', now: const Duration(seconds: 1))
            .refreshClass,
        TerminalRefreshClass.idle,
        reason: 'unknown activation defaults active, never background',
      );
    });

    test('input resize and activation reset exact interactive grace', () {
      const at = Duration(seconds: 1);
      final signals = <void Function()>[
        () => policy.recordInput('session', now: at),
        () => policy.recordResize('session', now: at),
        () => policy.recordActivation('session', now: at, active: true),
      ];

      for (final signal in signals) {
        policy.remove('session');
        signal();
        final fresh = policy.snapshot('session', now: at);
        expect(fresh.refreshClass, TerminalRefreshClass.interactive);
        expect(fresh.pumpMetrics.emptyRefreshCount, 0);
        expect(
          fresh.pumpMetrics.currentDelay,
          const Duration(milliseconds: 33),
        );
        expect(fresh.pumpMetrics.backoffSkipTicks, 0);
        expect(
          policy
              .snapshot(
                'session',
                now: at + const Duration(microseconds: 499999),
              )
              .refreshClass,
          TerminalRefreshClass.interactive,
        );
        expect(
          policy
              .snapshot('session', now: at + const Duration(milliseconds: 500))
              .refreshClass,
          TerminalRefreshClass.idle,
        );
      }
    });

    test('focus loss after the original grace expires is immediately idle', () {
      policy.recordFocus('session', now: Duration.zero, focused: true);
      expect(
        policy
            .snapshot('session', now: const Duration(milliseconds: 900))
            .refreshClass,
        TerminalRefreshClass.interactive,
        reason: 'focus itself keeps the active session interactive',
      );

      policy.recordFocus(
        'session',
        now: const Duration(milliseconds: 900),
        focused: false,
      );

      expect(
        policy
            .snapshot('session', now: const Duration(milliseconds: 900))
            .refreshClass,
        TerminalRefreshClass.idle,
        reason: 'focus loss must not start a new 500ms grace period',
      );
    });

    test('focus loss preserves but does not extend unexpired grace', () {
      policy.recordFocus('session', now: Duration.zero, focused: true);
      policy.recordFocus(
        'session',
        now: const Duration(milliseconds: 300),
        focused: false,
      );

      expect(
        policy
            .snapshot('session', now: const Duration(microseconds: 499999))
            .refreshClass,
        TerminalRefreshClass.interactive,
      );
      expect(
        policy
            .snapshot('session', now: const Duration(milliseconds: 500))
            .refreshClass,
        TerminalRefreshClass.idle,
        reason: 'the exact deadline remains anchored to focus gain at t=0',
      );
    });

    test('interactive requests a full poll every 33ms after empty results', () {
      policy.recordFocus('session', now: Duration.zero, focused: true);

      for (var tick = 1; tick <= 8; tick += 1) {
        final now = Duration(milliseconds: 33 * tick);
        final decision = policy.decisionForTick(
          'session',
          now: now,
          hintReady: null,
        );
        expect(decision.shouldRequestFullPoll, isTrue, reason: 'tick $tick');
        expect(decision.requestReason, 'deadline');
        policy.recordFullPollRequest('session');
        policy.recordRefreshResult(
          'session',
          now: now,
          receivedFrame: false,
          eventCount: 0,
          modes: TerminalFrameModes.empty,
        );
        final snapshot = policy.snapshot('session', now: now);
        expect(snapshot.refreshClass, TerminalRefreshClass.interactive);
        expect(
          snapshot.pumpMetrics.currentDelay,
          const Duration(milliseconds: 33),
        );
        expect(snapshot.pumpMetrics.backoffSkipTicks, 0);
        expect(snapshot.pumpMetrics.emptyRefreshCount, 0);
        expect(snapshot.fullPollCount, tick);
      }
    });

    test('active alternate and mouse modes stay interactive at 33ms', () {
      for (final modes in <TerminalFrameModes>[
        const TerminalFrameModes(alternateScreen: true),
        const TerminalFrameModes(mouseMode: 'any_event'),
      ]) {
        policy.remove('session');
        policy.recordActivation('session', now: Duration.zero, active: true);
        policy.recordRefreshResult(
          'session',
          now: const Duration(milliseconds: 33),
          receivedFrame: true,
          eventCount: 0,
          modes: modes,
        );
        for (var tick = 2; tick <= 6; tick += 1) {
          final now = Duration(milliseconds: 33 * tick);
          final decision = policy.decisionForTick(
            'session',
            now: now,
            hintReady: null,
          );
          expect(decision.shouldRequestFullPoll, isTrue);
          policy.recordRefreshResult(
            'session',
            now: now,
            receivedFrame: false,
            eventCount: 0,
            modes: modes,
          );
          final snapshot = policy.snapshot('session', now: now);
          expect(snapshot.refreshClass, TerminalRefreshClass.interactive);
          expect(snapshot.pumpMetrics.currentDelay.inMicroseconds, 33000);
          expect(snapshot.pumpMetrics.backoffSkipTicks, 0);
        }
      }
    });

    test('streaming requires two frames within 100ms and polls every 33ms', () {
      const first = Duration(seconds: 1);
      policy.recordRefreshResult(
        'session',
        now: first,
        receivedFrame: true,
        eventCount: 0,
        modes: TerminalFrameModes.empty,
      );
      policy.recordRefreshResult(
        'session',
        now: first + const Duration(milliseconds: 100),
        receivedFrame: true,
        eventCount: 0,
        modes: TerminalFrameModes.empty,
      );

      var now = first + const Duration(milliseconds: 133);
      for (var tick = 0; tick < 4; tick += 1) {
        final snapshot = policy.snapshot('session', now: now);
        expect(snapshot.refreshClass, TerminalRefreshClass.streaming);
        expect(snapshot.pumpMetrics.currentDelay.inMicroseconds, 33000);
        expect(snapshot.pumpMetrics.backoffSkipTicks, 0);
        expect(
          policy
              .decisionForTick('session', now: now, hintReady: null)
              .shouldRequestFullPoll,
          isTrue,
        );
        policy.recordRefreshResult(
          'session',
          now: now,
          receivedFrame: false,
          eventCount: 0,
          modes: TerminalFrameModes.empty,
        );
        now += const Duration(milliseconds: 33);
      }
      expect(
        policy
            .snapshot('session', now: first + const Duration(milliseconds: 349))
            .refreshClass,
        TerminalRefreshClass.streaming,
      );
      expect(
        policy
            .snapshot('session', now: first + const Duration(milliseconds: 350))
            .refreshClass,
        TerminalRefreshClass.idle,
      );
    });

    test('frame gap above 100ms restarts the streaming streak', () {
      const first = Duration(seconds: 1);
      _recordFrame(policy, first);
      _recordFrame(policy, first + const Duration(milliseconds: 80));
      expect(
        policy
            .snapshot('session', now: first + const Duration(milliseconds: 80))
            .refreshClass,
        TerminalRefreshClass.streaming,
      );

      _recordFrame(policy, first + const Duration(milliseconds: 181));
      expect(
        policy
            .snapshot('session', now: first + const Duration(milliseconds: 181))
            .refreshClass,
        TerminalRefreshClass.idle,
      );
      _recordFrame(policy, first + const Duration(milliseconds: 281));
      expect(
        policy
            .snapshot('session', now: first + const Duration(milliseconds: 281))
            .refreshClass,
        TerminalRefreshClass.streaming,
      );
    });

    test('background stream becomes streaming then returns to background', () {
      const at = Duration(seconds: 1);
      policy.recordActivation('session', now: Duration.zero, active: false);
      _recordFrame(policy, at);
      _recordFrame(policy, at + const Duration(milliseconds: 100));
      expect(
        policy
            .snapshot('session', now: at + const Duration(milliseconds: 100))
            .refreshClass,
        TerminalRefreshClass.streaming,
      );
      expect(
        policy
            .snapshot('session', now: at + const Duration(milliseconds: 350))
            .refreshClass,
        TerminalRefreshClass.background,
      );
    });

    test('event-only refreshes never accumulate a frame streak', () {
      const at = Duration(seconds: 1);
      for (var index = 0; index < 4; index += 1) {
        policy.recordRefreshResult(
          'session',
          now: at + Duration(milliseconds: index * 33),
          receivedFrame: false,
          eventCount: 2,
          modes: TerminalFrameModes.empty,
        );
      }
      expect(
        policy
            .snapshot('session', now: at + const Duration(milliseconds: 100))
            .refreshClass,
        TerminalRefreshClass.idle,
      );
    });

    test(
      'background modes remain background unless frames qualify streaming',
      () {
        policy.recordActivation('session', now: Duration.zero, active: false);
        policy.recordRefreshResult(
          'session',
          now: const Duration(seconds: 1),
          receivedFrame: false,
          eventCount: 0,
          modes: const TerminalFrameModes(
            alternateScreen: true,
            mouseMode: 'button_event',
          ),
        );
        expect(
          policy
              .snapshot('session', now: const Duration(seconds: 1))
              .refreshClass,
          TerminalRefreshClass.background,
        );
      },
    );

    test('background and idle delegate exact 132 264 396 fallback', () {
      for (final active in <bool>[false, true]) {
        policy.remove('session');
        policy.recordActivation('session', now: Duration.zero, active: active);
        var now = const Duration(milliseconds: 533);
        for (var empty = 1; empty <= 4; empty += 1) {
          final decision = policy.decisionForTick(
            'session',
            now: now,
            hintReady: null,
          );
          expect(decision.shouldRequestFullPoll, isTrue);
          expect(decision.requestReason, active ? 'idle_deadline' : 'deadline');
          policy.recordRefreshResult(
            'session',
            now: now,
            receivedFrame: false,
            eventCount: 0,
            modes: TerminalFrameModes.empty,
          );
          now += policy.snapshot('session', now: now).pumpMetrics.currentDelay;
        }
        final metrics = policy.snapshot('session', now: now).pumpMetrics;
        expect(metrics.currentDelay, const Duration(milliseconds: 396));
        expect(metrics.backoffSkipTicks, 11);
        expect(metrics.emptyRefreshCount, 4);
        expect(
          policy.snapshot('session', now: now).refreshClass,
          active ? TerminalRefreshClass.idle : TerminalRefreshClass.background,
        );
      }
    });

    test('hint samples and full polls use exact independent counters', () {
      policy.recordActivation('session', now: Duration.zero, active: false);

      final unsupported = policy.decisionForTick(
        'session',
        now: const Duration(milliseconds: 1),
        hintReady: null,
      );
      expect(unsupported.shouldRequestFullPoll, isFalse);
      expect(unsupported.snapshot.hintPollCount, 0);
      expect(unsupported.snapshot.fullPollCount, 0);

      final clean = policy.decisionForTick(
        'session',
        now: const Duration(milliseconds: 2),
        hintReady: false,
      );
      expect(clean.shouldRequestFullPoll, isFalse);
      expect(clean.snapshot.hintPollCount, 1);
      expect(clean.snapshot.fullPollCount, 0);

      final ready = policy.decisionForTick(
        'session',
        now: const Duration(milliseconds: 3),
        hintReady: true,
      );
      expect(ready.shouldRequestFullPoll, isTrue);
      expect(ready.requestReason, 'native_hint');
      expect(ready.snapshot.hintPollCount, 2);
      expect(ready.snapshot.fullPollCount, 0);
      expect(ready.snapshot.refreshClass, TerminalRefreshClass.background);

      policy.recordFullPollRequest('session');
      expect(
        policy
            .snapshot('session', now: const Duration(milliseconds: 3))
            .fullPollCount,
        1,
      );
    });

    test('remove clears classification fallback and counters', () {
      policy.recordActivation('session', now: Duration.zero, active: false);
      policy.decisionForTick(
        'session',
        now: const Duration(milliseconds: 33),
        hintReady: true,
      );
      policy.recordFullPollRequest('session');
      policy.remove('session');

      final snapshot = policy.snapshot(
        'session',
        now: const Duration(seconds: 1),
      );
      expect(snapshot.refreshClass, TerminalRefreshClass.idle);
      expect(snapshot.hintPollCount, 0);
      expect(snapshot.fullPollCount, 0);
      expect(snapshot.pumpMetrics.currentDelay, Duration.zero);
    });
  });
}

TerminalRefreshPolicy _newPolicy() {
  return TerminalRefreshPolicy(
    pollInterval: const Duration(milliseconds: 33),
    interactiveGrace: const Duration(milliseconds: 500),
    streamingGap: const Duration(milliseconds: 100),
    streamingGrace: const Duration(milliseconds: 250),
    fallbackPolicy: TerminalFramePumpPolicy(
      activeInterval: const Duration(milliseconds: 33),
      emptyRefreshesBeforeBackoff: 2,
      idleIntervals: const <Duration>[
        Duration(milliseconds: 132),
        Duration(milliseconds: 264),
        Duration(milliseconds: 396),
      ],
    ),
  );
}

void _recordFrame(TerminalRefreshPolicy policy, Duration now) {
  policy.recordRefreshResult(
    'session',
    now: now,
    receivedFrame: true,
    eventCount: 0,
    modes: TerminalFrameModes.empty,
  );
}
