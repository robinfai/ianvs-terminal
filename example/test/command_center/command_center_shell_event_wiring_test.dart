import 'package:app/features/command_center/command_center_runtime.dart';
import 'package:app/features/command_center/command_center_shell_event_wiring.dart';
import 'package:app/features/command_center/command_invocation_models.dart';
import 'package:app/features/command_center/shell_hook_lifecycle_adapter.dart';
import 'package:app/features/terminal/terminal.dart' as terminal;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandCenterShellEventWiring', () {
    const wiring = CommandCenterShellEventWiring();

    test('applies preexec shell hook into runtime state', () {
      final receivedAt = DateTime.utc(2026, 6, 15, 10);

      final result = wiring.applyShellHook(
        const CommandCenterRuntimeState(),
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

      expect(result.applied, isTrue);
      expect(result.ignoredReason, isNull);
      expect(result.event, isA<CommandLifecycleStartedEvent>());
      final invocation = result.state.runningInvocationForSession('session-a')!;
      expect(invocation.command, 'flutter test');
      expect(invocation.cwd, '/repo');
      expect(invocation.startedAt, receivedAt);
      expect(invocation.status, CommandInvocationStatus.running);
    });

    test('applies finish shell hook into lifecycle and history', () {
      final startedAt = DateTime.utc(2026, 6, 15, 10);
      final finishedAt = startedAt.add(const Duration(seconds: 2));
      final running = wiring.applyShellHook(
        const CommandCenterRuntimeState(),
        terminal.TerminalSessionShellHookEvent(
          'session-a',
          rawPayload: const {
            'hook': 'preexec',
            'command': 'dart test',
            'cwd': '/repo',
          },
        ),
        receivedAt: startedAt,
      );

      final result = wiring.applyShellHook(
        running.state,
        terminal.TerminalSessionShellHookEvent(
          'session-a',
          rawPayload: const {
            'hook': 'command_finished',
            'command': 'dart test',
            'pwd': '/repo',
            'exit_code': 1,
          },
        ),
        receivedAt: finishedAt,
      );

      final invocation = result.state.lifecycle.invocations.single;
      expect(result.applied, isTrue);
      expect(invocation.status, CommandInvocationStatus.failed);
      expect(invocation.duration, const Duration(seconds: 2));
      expect(result.state.runningInvocationForSession('session-a'), isNull);
      expect(
        result.state.history.entriesForSession('session-a').single.command,
        'dart test',
      );
    });

    test('applies cwd shell hook into runtime cwd map', () {
      final result = wiring.applyShellHook(
        const CommandCenterRuntimeState(),
        terminal.TerminalSessionShellHookEvent(
          'session-a',
          rawPayload: const {'hook': 'precmd.pwd', 'pwd': '/repo/packages'},
        ),
        receivedAt: DateTime.utc(2026, 6, 15, 10),
      );

      expect(result.applied, isTrue);
      expect(result.state.cwdForSession('session-a'), '/repo/packages');
    });

    test('keeps runtime state unchanged for ignored shell hook', () {
      const state = CommandCenterRuntimeState();

      final result = wiring.applyShellHook(
        state,
        terminal.TerminalSessionShellHookEvent(
          'session-a',
          rawPayload: const {'hook': 'future_hook'},
        ),
        receivedAt: DateTime.utc(2026, 6, 15, 10),
      );

      expect(result.applied, isFalse);
      expect(result.state, same(state));
      expect(result.event, isNull);
      expect(result.ignoredReason, ShellHookLifecycleIgnoredReason.unknownHook);
    });
  });
}
