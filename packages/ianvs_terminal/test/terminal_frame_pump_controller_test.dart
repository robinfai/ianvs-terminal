import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/src/runtime/terminal_frame_pump_controller.dart';
import 'package:ianvs_terminal/src/runtime/terminal_refresh_policy.dart';
import 'package:ianvs_terminal/src/terminal/terminal_models.dart';

void main() {
  group(TerminalFramePumpController, () {
    late TerminalFramePumpController controller;

    setUp(() {
      controller = TerminalFramePumpController.standard();
    });

    test('requests an overdue deadline', () {
      final decision = controller.decisionForTick(
        'session-1',
        now: const Duration(seconds: 1),
        hintReady: null,
      );

      expect(decision.shouldRequestFullPoll, isTrue);
      expect(decision.requestReason, 'idle_deadline');
    });

    test('unknown sessions default active without becoming interactive', () {
      final snapshot = controller.snapshot(
        'unknown',
        now: const Duration(seconds: 1),
      );

      expect(snapshot.refreshClass, TerminalRefreshClass.idle);
      expect(snapshot.pumpMetrics.currentDelay, Duration.zero);
      expect(snapshot.hintPollCount, 0);
      expect(snapshot.fullPollCount, 0);
    });

    test('activation requires active and rejects without mutating state', () {
      const sessionId = 'session-1';
      controller.decisionForTick(
        sessionId,
        now: Duration.zero,
        hintReady: false,
      );
      controller.recordFullPollRequest(sessionId);
      final before = controller.snapshot(sessionId, now: Duration.zero);

      expect(
        () => controller.reset(
          sessionId,
          now: const Duration(milliseconds: 1),
          reason: TerminalFramePumpResetReason.activation,
        ),
        throwsArgumentError,
      );

      final after = controller.snapshot(
        sessionId,
        now: const Duration(milliseconds: 1),
      );
      expect(after.refreshClass, before.refreshClass);
      expect(after.pumpMetrics.currentDelay, before.pumpMetrics.currentDelay);
      expect(after.hintPollCount, before.hintPollCount);
      expect(after.fullPollCount, before.fullPollCount);
    });

    test('ready hint bypasses a bounded deadline', () {
      const sessionId = 'session-1';
      controller.reset(
        sessionId,
        now: Duration.zero,
        reason: TerminalFramePumpResetReason.activation,
        active: false,
      );

      final decision = controller.decisionForTick(
        sessionId,
        now: const Duration(milliseconds: 1),
        hintReady: true,
      );

      expect(decision.shouldRequestFullPoll, isTrue);
      expect(decision.requestReason, 'native_hint');
      expect(decision.snapshot.refreshClass, TerminalRefreshClass.background);
    });

    test('unknown hint preserves the bounded deadline fallback', () {
      const sessionId = 'session-1';
      controller.reset(
        sessionId,
        now: Duration.zero,
        reason: TerminalFramePumpResetReason.activation,
        active: false,
      );

      final early = controller.decisionForTick(
        sessionId,
        now: const Duration(milliseconds: 1),
        hintReady: null,
      );
      final due = controller.decisionForTick(
        sessionId,
        now: const Duration(milliseconds: 33),
        hintReady: null,
      );

      expect(early.shouldRequestFullPoll, isFalse);
      expect(early.requestReason, isNull);
      expect(early.snapshot.refreshClass, TerminalRefreshClass.background);
      expect(early.snapshot.hintPollCount, 0);
      expect(due.shouldRequestFullPoll, isTrue);
      expect(due.requestReason, 'deadline');
      expect(due.snapshot.refreshClass, TerminalRefreshClass.background);
      expect(due.snapshot.hintPollCount, 0);
    });

    test('false hint preserves the bounded deadline fallback', () {
      const sessionId = 'session-1';
      controller.reset(
        sessionId,
        now: Duration.zero,
        reason: TerminalFramePumpResetReason.activation,
        active: false,
      );

      final early = controller.decisionForTick(
        sessionId,
        now: const Duration(milliseconds: 1),
        hintReady: false,
      );
      final due = controller.decisionForTick(
        sessionId,
        now: const Duration(milliseconds: 33),
        hintReady: false,
      );

      expect(early.shouldRequestFullPoll, isFalse);
      expect(due.shouldRequestFullPoll, isTrue);
      expect(due.requestReason, 'deadline');
      expect(due.snapshot.refreshClass, TerminalRefreshClass.background);
    });

    test('preserves interactive and streaming refresh classes', () {
      const sessionId = 'session-1';
      controller.reset(
        sessionId,
        now: Duration.zero,
        reason: TerminalFramePumpResetReason.focusGain,
      );
      expect(
        controller
            .snapshot(sessionId, now: const Duration(milliseconds: 1))
            .refreshClass,
        TerminalRefreshClass.interactive,
      );

      controller.recordFocusLoss(
        sessionId,
        now: const Duration(milliseconds: 501),
      );
      controller.recordRefreshResult(
        sessionId,
        now: const Duration(milliseconds: 600),
        receivedFrame: true,
        eventCount: 0,
        modes: const TerminalFrameModes(),
      );
      controller.recordRefreshResult(
        sessionId,
        now: const Duration(milliseconds: 650),
        receivedFrame: true,
        eventCount: 0,
        modes: const TerminalFrameModes(),
      );

      expect(
        controller
            .snapshot(sessionId, now: const Duration(milliseconds: 651))
            .refreshClass,
        TerminalRefreshClass.streaming,
      );
    });

    test('snapshots exact hint and full poll counters', () {
      const sessionId = 'session-1';
      controller.decisionForTick(
        sessionId,
        now: Duration.zero,
        hintReady: false,
      );
      controller.decisionForTick(
        sessionId,
        now: Duration.zero,
        hintReady: true,
      );
      controller.recordFullPollRequest(sessionId);

      final snapshot = controller.snapshot(sessionId, now: Duration.zero);
      expect(snapshot.hintPollCount, 2);
      expect(snapshot.fullPollCount, 1);
    });

    test('reset restores pump state and remove clears all session state', () {
      const sessionId = 'session-1';
      controller.recordRefreshResult(
        sessionId,
        now: Duration.zero,
        receivedFrame: false,
        eventCount: 0,
        modes: const TerminalFrameModes(),
      );
      controller.recordRefreshResult(
        sessionId,
        now: const Duration(milliseconds: 33),
        receivedFrame: false,
        eventCount: 0,
        modes: const TerminalFrameModes(),
      );
      controller.reset(
        sessionId,
        now: const Duration(milliseconds: 40),
        reason: TerminalFramePumpResetReason.resize,
      );
      final reset = controller.snapshot(
        sessionId,
        now: const Duration(milliseconds: 40),
      );
      expect(reset.refreshClass, TerminalRefreshClass.interactive);
      expect(reset.pumpMetrics.emptyRefreshCount, 0);
      expect(reset.pumpMetrics.backoffSkipTicks, 0);
      expect(reset.pumpMetrics.currentDelay, const Duration(milliseconds: 33));
      expect(reset.hintPollCount, 0);
      expect(reset.fullPollCount, 0);

      controller.decisionForTick(
        sessionId,
        now: const Duration(milliseconds: 40),
        hintReady: false,
      );
      controller.recordFullPollRequest(sessionId);
      controller.remove(sessionId);

      final removed = controller.snapshot(
        sessionId,
        now: const Duration(milliseconds: 40),
      );
      expect(removed.refreshClass, TerminalRefreshClass.idle);
      expect(removed.pumpMetrics.currentDelay, Duration.zero);
      expect(removed.hintPollCount, 0);
      expect(removed.fullPollCount, 0);
    });
  });
}
