import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/src/runtime/terminal_frame_pump.dart';

void main() {
  group(TerminalFramePumpPolicy, () {
    late TerminalFramePumpPolicy policy;

    setUp(() {
      policy = TerminalFramePumpPolicy(
        activeInterval: const Duration(milliseconds: 33),
        emptyRefreshesBeforeBackoff: 2,
        idleIntervals: const <Duration>[
          Duration(milliseconds: 132),
          Duration(milliseconds: 264),
          Duration(milliseconds: 396),
        ],
      );
    });

    test('uses exact monotonic deadlines and caps the idle delay', () {
      const sessionId = 'session-1';
      const start = Duration(seconds: 1);

      expect(policy.shouldSkipPollingRefresh(sessionId, now: start), isFalse);

      policy.recordRefreshResult(sessionId, now: start, hadActivity: false);
      _expectMetrics(
        policy.metricsFor(sessionId),
        emptyRefreshCount: 1,
        backoffSkipTicks: 0,
        currentDelay: const Duration(milliseconds: 33),
      );
      expect(
        policy.shouldSkipPollingRefresh(
          sessionId,
          now: start + const Duration(microseconds: 32999),
        ),
        isTrue,
      );
      expect(
        policy.shouldSkipPollingRefresh(
          sessionId,
          now: start + const Duration(milliseconds: 33),
        ),
        isFalse,
      );

      final secondResultAt = start + const Duration(milliseconds: 33);
      policy.recordRefreshResult(
        sessionId,
        now: secondResultAt,
        hadActivity: false,
      );
      _expectMetrics(
        policy.metricsFor(sessionId),
        emptyRefreshCount: 2,
        backoffSkipTicks: 3,
        currentDelay: const Duration(milliseconds: 132),
      );
      expect(
        policy.shouldSkipPollingRefresh(
          sessionId,
          now: secondResultAt + const Duration(microseconds: 131999),
        ),
        isTrue,
      );
      expect(
        policy.shouldSkipPollingRefresh(
          sessionId,
          now: secondResultAt + const Duration(milliseconds: 132),
        ),
        isFalse,
      );

      final thirdResultAt = secondResultAt + const Duration(milliseconds: 132);
      policy.recordRefreshResult(
        sessionId,
        now: thirdResultAt,
        hadActivity: false,
      );
      _expectMetrics(
        policy.metricsFor(sessionId),
        emptyRefreshCount: 3,
        backoffSkipTicks: 7,
        currentDelay: const Duration(milliseconds: 264),
      );
      expect(
        policy.shouldSkipPollingRefresh(
          sessionId,
          now: thirdResultAt + const Duration(microseconds: 263999),
        ),
        isTrue,
      );
      expect(
        policy.shouldSkipPollingRefresh(
          sessionId,
          now: thirdResultAt + const Duration(milliseconds: 264),
        ),
        isFalse,
      );

      final fourthResultAt = thirdResultAt + const Duration(milliseconds: 264);
      policy.recordRefreshResult(
        sessionId,
        now: fourthResultAt,
        hadActivity: false,
      );
      _expectMetrics(
        policy.metricsFor(sessionId),
        emptyRefreshCount: 4,
        backoffSkipTicks: 11,
        currentDelay: const Duration(milliseconds: 396),
      );
      expect(
        policy.shouldSkipPollingRefresh(
          sessionId,
          now: fourthResultAt + const Duration(microseconds: 395999),
        ),
        isTrue,
      );
      expect(
        policy.shouldSkipPollingRefresh(
          sessionId,
          now: fourthResultAt + const Duration(milliseconds: 396),
        ),
        isFalse,
      );

      final fifthResultAt = fourthResultAt + const Duration(milliseconds: 396);
      policy.recordRefreshResult(
        sessionId,
        now: fifthResultAt,
        hadActivity: false,
      );
      _expectMetrics(
        policy.metricsFor(sessionId),
        emptyRefreshCount: 5,
        backoffSkipTicks: 11,
        currentDelay: const Duration(milliseconds: 396),
      );
      expect(
        policy.shouldSkipPollingRefresh(
          sessionId,
          now: fifthResultAt + const Duration(microseconds: 395999),
        ),
        isTrue,
      );
      expect(
        policy.shouldSkipPollingRefresh(
          sessionId,
          now: fifthResultAt + const Duration(milliseconds: 396),
        ),
        isFalse,
      );
    });

    test('requests immediately after a caller jumps past the deadline', () {
      const sessionId = 'session-1';
      const start = Duration(seconds: 1);

      policy.recordRefreshResult(sessionId, now: start, hadActivity: false);
      policy.recordRefreshResult(
        sessionId,
        now: start + const Duration(milliseconds: 33),
        hadActivity: false,
      );

      expect(
        policy.shouldSkipPollingRefresh(
          sessionId,
          now: start + const Duration(seconds: 2),
        ),
        isFalse,
      );
      _expectMetrics(
        policy.metricsFor(sessionId),
        emptyRefreshCount: 2,
        backoffSkipTicks: 3,
        currentDelay: const Duration(milliseconds: 132),
      );
    });

    test('activity and reset restore the active interval', () {
      const sessionId = 'session-1';
      const start = Duration(seconds: 1);

      policy.recordRefreshResult(sessionId, now: start, hadActivity: false);
      policy.recordRefreshResult(
        sessionId,
        now: start + const Duration(milliseconds: 33),
        hadActivity: false,
      );
      policy.recordRefreshResult(
        sessionId,
        now: start + const Duration(milliseconds: 165),
        hadActivity: true,
      );

      _expectMetrics(
        policy.metricsFor(sessionId),
        emptyRefreshCount: 0,
        backoffSkipTicks: 0,
        currentDelay: const Duration(milliseconds: 33),
      );
      const activityAt = Duration(milliseconds: 1165);
      expect(
        policy.shouldSkipPollingRefresh(
          sessionId,
          now: activityAt + const Duration(microseconds: 32999),
        ),
        isTrue,
      );
      expect(
        policy.shouldSkipPollingRefresh(
          sessionId,
          now: activityAt + const Duration(milliseconds: 33),
        ),
        isFalse,
      );

      policy.recordRefreshResult(
        sessionId,
        now: start + const Duration(milliseconds: 198),
        hadActivity: false,
      );
      policy.reset(sessionId, now: start + const Duration(milliseconds: 200));

      _expectMetrics(
        policy.metricsFor(sessionId),
        emptyRefreshCount: 0,
        backoffSkipTicks: 0,
        currentDelay: const Duration(milliseconds: 33),
      );
      const resetAt = Duration(milliseconds: 1200);
      expect(
        policy.shouldSkipPollingRefresh(
          sessionId,
          now: resetAt + const Duration(microseconds: 32999),
        ),
        isTrue,
      );
      expect(
        policy.shouldSkipPollingRefresh(
          sessionId,
          now: resetAt + const Duration(milliseconds: 33),
        ),
        isFalse,
      );
    });

    test('remove clears state without affecting another session', () {
      const firstSessionId = 'session-1';
      const secondSessionId = 'session-2';
      const start = Duration(seconds: 1);

      policy.recordRefreshResult(
        firstSessionId,
        now: start,
        hadActivity: false,
      );
      policy.recordRefreshResult(
        firstSessionId,
        now: start + const Duration(milliseconds: 33),
        hadActivity: false,
      );
      policy.recordRefreshResult(
        secondSessionId,
        now: start,
        hadActivity: false,
      );

      policy.remove(firstSessionId);

      _expectMetrics(
        policy.metricsFor(firstSessionId),
        emptyRefreshCount: 0,
        backoffSkipTicks: 0,
        currentDelay: Duration.zero,
      );
      _expectMetrics(
        policy.metricsFor('unknown'),
        emptyRefreshCount: 0,
        backoffSkipTicks: 0,
        currentDelay: Duration.zero,
      );
      _expectMetrics(
        policy.metricsFor(secondSessionId),
        emptyRefreshCount: 1,
        backoffSkipTicks: 0,
        currentDelay: const Duration(milliseconds: 33),
      );
      expect(
        policy.shouldSkipPollingRefresh(firstSessionId, now: start),
        isFalse,
      );
      expect(
        policy.shouldSkipPollingRefresh(
          secondSessionId,
          now: start + const Duration(microseconds: 32999),
        ),
        isTrue,
      );
      expect(
        policy.shouldSkipPollingRefresh(
          secondSessionId,
          now: start + const Duration(milliseconds: 33),
        ),
        isFalse,
      );
    });
  });
}

void _expectMetrics(
  TerminalFramePumpMetrics actual, {
  required int emptyRefreshCount,
  required int backoffSkipTicks,
  required Duration currentDelay,
}) {
  expect(actual.emptyRefreshCount, emptyRefreshCount);
  expect(actual.backoffSkipTicks, backoffSkipTicks);
  expect(actual.currentDelay, currentDelay);
}
