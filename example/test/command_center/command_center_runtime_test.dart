import 'package:app/features/command_center/command_block_models.dart';
import 'package:app/features/command_center/command_center_runtime.dart';
import 'package:app/features/command_center/command_invocation_models.dart';
import 'package:app/features/command_center/command_search_query_parser.dart';
import 'package:app/features/command_center/shell_hook_lifecycle_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandCenterRuntimeReducer', () {
    test('tracks started and finished commands into lifecycle and history', () {
      const reducer = CommandCenterRuntimeReducer();
      final startedAt = DateTime.utc(2026, 6, 15, 10);
      final finishedAt = startedAt.add(const Duration(seconds: 3));

      final running = reducer.apply(
        const CommandCenterRuntimeState(),
        CommandLifecycleStartedEvent(
          sessionId: 'session-a',
          receivedAt: startedAt,
          command: 'flutter test',
          cwd: '/repo',
        ),
      );
      final finished = reducer.apply(
        running,
        CommandLifecycleFinishedEvent(
          sessionId: 'session-a',
          receivedAt: finishedAt,
          command: 'flutter test',
          cwd: '/repo',
          exitCode: 0,
        ),
      );

      final invocation = finished.lifecycle.invocations.single;
      expect(invocation.command, 'flutter test');
      expect(invocation.cwd, '/repo');
      expect(invocation.startedAt, startedAt);
      expect(invocation.finishedAt, finishedAt);
      expect(invocation.duration, const Duration(seconds: 3));
      expect(invocation.status, CommandInvocationStatus.succeeded);
      expect(finished.runningInvocationForSession('session-a'), isNull);

      final history = finished.history.entriesForSession('session-a');
      expect(history, hasLength(1));
      expect(history.single.command, 'flutter test');
      expect(history.single.cwd, '/repo');
      expect(history.single.exitCode, 0);
    });

    test('uses latest cwd event when command events omit cwd', () {
      const reducer = CommandCenterRuntimeReducer();
      final cwdAt = DateTime.utc(2026, 6, 15, 10);
      final startedAt = cwdAt.add(const Duration(seconds: 1));
      final finishedAt = cwdAt.add(const Duration(seconds: 2));

      final withCwd = reducer.apply(
        const CommandCenterRuntimeState(),
        CommandLifecycleCwdChangedEvent(
          sessionId: 'session-a',
          receivedAt: cwdAt,
          cwd: '/repo/packages',
        ),
      );
      final running = reducer.apply(
        withCwd,
        CommandLifecycleStartedEvent(
          sessionId: 'session-a',
          receivedAt: startedAt,
          command: 'dart test',
        ),
      );
      final finished = reducer.apply(
        running,
        CommandLifecycleFinishedEvent(
          sessionId: 'session-a',
          receivedAt: finishedAt,
          command: 'dart test',
          exitCode: 1,
        ),
      );

      expect(finished.cwdForSession('session-a'), '/repo/packages');
      expect(finished.lifecycle.invocations.single.cwd, '/repo/packages');
      expect(
        finished.lifecycle.invocations.single.status,
        CommandInvocationStatus.failed,
      );
      expect(
        finished.history.entriesForSession('session-a').single.cwd,
        '/repo/packages',
      );
    });

    test(
      'keeps sessions isolated and tolerates out-of-order finish events',
      () {
        const reducer = CommandCenterRuntimeReducer();
        final finishedAt = DateTime.utc(2026, 6, 15, 10);

        final state = reducer.apply(
          const CommandCenterRuntimeState(),
          CommandLifecycleFinishedEvent(
            sessionId: 'session-b',
            receivedAt: finishedAt,
            command: 'false',
            cwd: '/tmp',
            exitCode: 1,
          ),
        );

        expect(state.lifecycle.invocations, hasLength(1));
        expect(state.lifecycle.invocations.single.sessionId, 'session-b');
        expect(
          state.lifecycle.invocations.single.status,
          CommandInvocationStatus.failed,
        );
        expect(state.runningInvocationForSession('session-b'), isNull);
        expect(state.history.entriesForSession('session-a'), isEmpty);
        expect(
          state.history.entriesForSession('session-b').single.command,
          'false',
        );
      },
    );

    test(
      'builds search index and block range state from current runtime state',
      () {
        const reducer = CommandCenterRuntimeReducer();
        final startedAt = DateTime.utc(2026, 6, 15, 10);
        final finishedAt = startedAt.add(const Duration(seconds: 1));
        final state = reducer.apply(
          reducer.apply(
            const CommandCenterRuntimeState(),
            CommandLifecycleStartedEvent(
              sessionId: 'session-a',
              receivedAt: startedAt,
              command: 'flutter test',
              cwd: '/repo',
            ),
          ),
          CommandLifecycleFinishedEvent(
            sessionId: 'session-a',
            receivedAt: finishedAt,
            command: 'flutter test',
            cwd: '/repo',
            exitCode: 0,
          ),
        );
        final invocationId = state.lifecycle.invocations.single.id;

        final results = state.searchIndex().search(
          const CommandSearchQueryParser().parse('flutter'),
          currentCwd: '/repo',
        );
        final blocks = state
            .blockRangeState(
              rangesByInvocationId: {
                invocationId: const CommandBlockTerminalRanges(
                  inputRange: CommandBlockRowRange(
                    startRow: 10,
                    endRowExclusive: 11,
                  ),
                  outputRange: CommandBlockRowRange(
                    startRow: 11,
                    endRowExclusive: 20,
                  ),
                ),
              },
            )
            .blocksForScope(const CommandBlockScope('session-a'));

        expect(results.single.entry.command, 'flutter test');
        expect(blocks.single.command, 'flutter test');
        expect(blocks.single.outputRange?.startRow, 11);
      },
    );
  });
}
