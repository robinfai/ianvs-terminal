import 'package:app/features/command_center/shell_hook_lifecycle_adapter.dart';
import 'package:app/features/terminal/terminal.dart' as terminal;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShellHookLifecycleAdapter', () {
    const adapter = ShellHookLifecycleAdapter();
    final receivedAt = DateTime.utc(2026, 6, 15, 10);

    test('maps preexec to command started event', () {
      final result = adapter.adapt(
        terminal.TerminalSessionShellHookEvent(
          'session-a',
          rawPayload: const {
            'hook': 'preexec',
            'command': ' flutter test ',
            'cwd': ' /repo ',
          },
        ),
        receivedAt: receivedAt,
      );

      final event = result.event as CommandLifecycleStartedEvent;

      expect(result.isIgnored, isFalse);
      expect(event.sessionId, 'session-a');
      expect(event.command, 'flutter test');
      expect(event.cwd, '/repo');
      expect(event.receivedAt, receivedAt);
    });

    test('maps command finished to command finished event', () {
      final result = adapter.adapt(
        terminal.TerminalSessionShellHookEvent(
          'session-a',
          rawPayload: const {
            'hook': 'command_finished',
            'command': 'false',
            'pwd': '/repo',
            'exit_code': 1,
          },
        ),
        receivedAt: receivedAt,
      );

      final event = result.event as CommandLifecycleFinishedEvent;

      expect(event.sessionId, 'session-a');
      expect(event.command, 'false');
      expect(event.cwd, '/repo');
      expect(event.exitCode, 1);
      expect(event.receivedAt, receivedAt);
    });

    test('maps precmd pwd to cwd changed event', () {
      final result = adapter.adapt(
        terminal.TerminalSessionShellHookEvent(
          'session-a',
          rawPayload: const {'hook': 'precmd.pwd', 'pwd': ' /repo/packages '},
        ),
        receivedAt: receivedAt,
      );

      final event = result.event as CommandLifecycleCwdChangedEvent;

      expect(event.sessionId, 'session-a');
      expect(event.cwd, '/repo/packages');
      expect(event.receivedAt, receivedAt);
    });

    test('ignores unknown hook with reason', () {
      final result = adapter.adapt(
        terminal.TerminalSessionShellHookEvent(
          'session-a',
          rawPayload: const {'hook': 'prompt'},
        ),
        receivedAt: receivedAt,
      );

      expect(result.event, isNull);
      expect(result.ignoredReason, ShellHookLifecycleIgnoredReason.unknownHook);
    });

    test('ignores preexec without command with reason', () {
      final result = adapter.adapt(
        terminal.TerminalSessionShellHookEvent(
          'session-a',
          rawPayload: const {'hook': 'preexec', 'command': '   '},
        ),
        receivedAt: receivedAt,
      );

      expect(result.event, isNull);
      expect(
        result.ignoredReason,
        ShellHookLifecycleIgnoredReason.missingCommand,
      );
    });
  });
}
