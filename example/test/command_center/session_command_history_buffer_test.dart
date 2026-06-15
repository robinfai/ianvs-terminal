import 'package:app/features/command_center/session_command_history_buffer.dart';
import 'package:app/features/command_center/shell_hook_lifecycle_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionCommandHistoryBuffer', () {
    final firstFinishedAt = DateTime.utc(2026, 6, 15, 10);
    final secondFinishedAt = DateTime.utc(2026, 6, 15, 10, 0, 1);
    final thirdFinishedAt = DateTime.utc(2026, 6, 15, 10, 0, 2);

    test('records command finished events for immediate session lookup', () {
      final buffer = const SessionCommandHistoryBuffer().recordFinished(
        CommandLifecycleFinishedEvent(
          sessionId: 'session-a',
          receivedAt: firstFinishedAt,
          command: ' flutter test ',
          cwd: ' /repo ',
          exitCode: 0,
        ),
      );

      final entries = buffer.entriesForSession('session-a');

      expect(entries, hasLength(1));
      expect(entries.single.command, 'flutter test');
      expect(entries.single.cwd, '/repo');
      expect(entries.single.exitCode, 0);
      expect(entries.single.succeeded, isTrue);
      expect(entries.single.finishedAt, firstFinishedAt);
    });

    test('returns session entries newest first', () {
      final buffer = const SessionCommandHistoryBuffer()
          .recordFinished(
            _finished(command: 'flutter test', finishedAt: firstFinishedAt),
          )
          .recordFinished(
            _finished(command: 'dart analyze', finishedAt: secondFinishedAt),
          );

      expect(
        buffer.entriesForSession('session-a').map((entry) => entry.command),
        ['dart analyze', 'flutter test'],
      );
    });

    test('skips blank commands', () {
      final buffer = const SessionCommandHistoryBuffer()
          .recordFinished(
            _finished(command: '   ', finishedAt: firstFinishedAt),
          )
          .recordFinished(
            _finished(command: 'pwd', finishedAt: secondFinishedAt),
          );

      expect(buffer.entriesForSession('session-a'), hasLength(1));
      expect(buffer.entriesForSession('session-a').single.command, 'pwd');
    });

    test('merges duplicate command and cwd with the latest metadata', () {
      final buffer = const SessionCommandHistoryBuffer()
          .recordFinished(
            _finished(
              command: 'flutter test',
              cwd: '/repo',
              exitCode: 1,
              finishedAt: firstFinishedAt,
            ),
          )
          .recordFinished(
            _finished(
              command: 'dart analyze',
              cwd: '/repo',
              exitCode: 0,
              finishedAt: secondFinishedAt,
            ),
          )
          .recordFinished(
            _finished(
              command: ' flutter test ',
              cwd: ' /repo ',
              exitCode: 0,
              finishedAt: thirdFinishedAt,
            ),
          );

      final entries = buffer.entriesForSession('session-a');

      expect(entries.map((entry) => entry.command), [
        'flutter test',
        'dart analyze',
      ]);
      expect(entries.first.exitCode, 0);
      expect(entries.first.finishedAt, thirdFinishedAt);
    });

    test('trims entries to the configured per-session limit', () {
      final buffer = const SessionCommandHistoryBuffer(limit: 2)
          .recordFinished(
            _finished(command: 'first', finishedAt: firstFinishedAt),
          )
          .recordFinished(
            _finished(command: 'second', finishedAt: secondFinishedAt),
          )
          .recordFinished(
            _finished(command: 'third', finishedAt: thirdFinishedAt),
          );

      expect(
        buffer.entriesForSession('session-a').map((entry) => entry.command),
        ['third', 'second'],
      );
    });

    test('keeps histories isolated by session', () {
      final buffer = const SessionCommandHistoryBuffer()
          .recordFinished(
            _finished(
              sessionId: 'session-a',
              command: 'flutter test',
              finishedAt: firstFinishedAt,
            ),
          )
          .recordFinished(
            _finished(
              sessionId: 'session-b',
              command: 'flutter test',
              finishedAt: secondFinishedAt,
            ),
          )
          .recordFinished(
            _finished(
              sessionId: 'session-a',
              command: 'dart analyze',
              finishedAt: thirdFinishedAt,
            ),
          );

      expect(
        buffer.entriesForSession('session-a').map((entry) => entry.command),
        ['dart analyze', 'flutter test'],
      );
      expect(
        buffer.entriesForSession('session-b').map((entry) => entry.command),
        ['flutter test'],
      );
    });
  });
}

CommandLifecycleFinishedEvent _finished({
  String sessionId = 'session-a',
  required String command,
  String? cwd = '/repo',
  int? exitCode = 0,
  required DateTime finishedAt,
}) {
  return CommandLifecycleFinishedEvent(
    sessionId: sessionId,
    receivedAt: finishedAt,
    command: command,
    cwd: cwd,
    exitCode: exitCode,
  );
}
