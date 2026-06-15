import 'package:app/features/command_center/command_invocation_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandInvocation', () {
    final startedAt = DateTime.utc(2026, 6, 15, 10);
    final finishedAt = DateTime.utc(2026, 6, 15, 10, 0, 4, 250);

    test('creates a running invocation without finish metadata', () {
      final invocation = CommandInvocation.running(
        id: 'cmd-1',
        sessionId: 'session-a',
        command: 'flutter test',
        cwd: '/repo',
        startedAt: startedAt,
        paneId: 'pane-a',
        profileId: 'default',
      );

      expect(invocation.id, 'cmd-1');
      expect(invocation.sessionId, 'session-a');
      expect(invocation.command, 'flutter test');
      expect(invocation.cwd, '/repo');
      expect(invocation.paneId, 'pane-a');
      expect(invocation.profileId, 'default');
      expect(invocation.startedAt, startedAt);
      expect(invocation.finishedAt, isNull);
      expect(invocation.exitCode, isNull);
      expect(invocation.duration, isNull);
      expect(invocation.status, CommandInvocationStatus.running);
    });

    test('derives success and duration for completed zero exit code', () {
      final invocation = CommandInvocation.completed(
        id: 'cmd-2',
        sessionId: 'session-a',
        command: 'git status',
        startedAt: startedAt,
        finishedAt: finishedAt,
        exitCode: 0,
      );

      expect(invocation.status, CommandInvocationStatus.succeeded);
      expect(invocation.duration, const Duration(milliseconds: 4250));
    });

    test('derives failure for completed non-zero exit code', () {
      final invocation = CommandInvocation.completed(
        id: 'cmd-3',
        sessionId: 'session-a',
        command: 'false',
        startedAt: startedAt,
        finishedAt: finishedAt,
        exitCode: 1,
      );

      expect(invocation.status, CommandInvocationStatus.failed);
      expect(invocation.exitCode, 1);
    });

    test('keeps unknown status for incomplete metadata', () {
      final invocation = CommandInvocation.unknown(
        id: 'cmd-4',
        sessionId: 'session-a',
        command: 'unknown',
        startedAt: startedAt,
      );

      expect(invocation.status, CommandInvocationStatus.unknown);
      expect(invocation.duration, isNull);
    });
  });

  group('CommandLifecycleState', () {
    test('keeps command invocations isolated by session', () {
      final startedAt = DateTime.utc(2026, 6, 15, 10);
      final state = const CommandLifecycleState()
          .addInvocation(
            CommandInvocation.running(
              id: 'cmd-a',
              sessionId: 'session-a',
              command: 'pwd',
              startedAt: startedAt,
            ),
          )
          .addInvocation(
            CommandInvocation.running(
              id: 'cmd-b',
              sessionId: 'session-b',
              command: 'ls',
              startedAt: startedAt,
            ),
          );

      expect(
        state.invocationsForSession('session-a').map((entry) => entry.id),
        ['cmd-a'],
      );
      expect(
        state.invocationsForSession('session-b').map((entry) => entry.id),
        ['cmd-b'],
      );
      expect(state.invocationById('cmd-a')!.sessionId, 'session-a');
    });
  });
}
