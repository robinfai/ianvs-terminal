import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/shell/session_sidebar_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 15);
  test(
    'typing is not execution, duplicate execution markers keep start time',
    () {
      const empty = TerminalShellIntegrationSnapshot.empty;
      expect(
        empty
            .observeExecution(
              phase: 'command_start',
              command: 'sleep 60',
              now: now,
            )
            .commandStartedAt,
        isNull,
      );
      final started = empty.observeExecution(
        phase: 'preexec',
        command: 'sleep 60',
        now: now,
      );
      final duplicate = started.observeExecution(
        phase: 'command_executed',
        command: 'sleep 60',
        now: now.add(const Duration(seconds: 2)),
      );
      expect(duplicate.commandStartedAt, now);
      expect(duplicate.runningCommand, 'sleep 60');
      final next = now.add(const Duration(seconds: 5));
      expect(
        duplicate
            .observeExecution(phase: 'preexec', command: 'sleep 90', now: next)
            .commandStartedAt,
        next,
      );
      for (final phase in ['command_finished', 'prompt_start', 'precmd']) {
        final finished = duplicate.observeExecution(
          phase: phase,
          command: null,
          now: now,
        );
        expect(finished.commandStartedAt, isNull);
        expect(finished.runningCommand, isNull);
      }
    },
  );
  test('classification priority and long-running threshold are exclusive', () {
    final tab = TerminalTab(
      sessionId: 'one',
      title: 'shell',
      profileId: 'default',
      shellIntegration: TerminalShellIntegrationSnapshot(
        commandStartedAt: now,
        runningCommand: 'sleep 60',
      ),
    );
    expect(
      sessionSidebarCategory(
        tab,
        alternateScreen: false,
        now: now.add(const Duration(seconds: 9)),
      ),
      SessionSidebarCategory.directory,
    );
    expect(
      sessionSidebarCategory(
        tab,
        alternateScreen: false,
        now: now.add(const Duration(seconds: 10)),
      ),
      SessionSidebarCategory.running,
    );
    expect(
      sessionSidebarCategory(tab, alternateScreen: true, now: now),
      SessionSidebarCategory.interactive,
    );
    expect(
      sessionSidebarCategory(
        tab.copyWith(isExited: true),
        alternateScreen: true,
        now: now,
      ),
      SessionSidebarCategory.directory,
    );
    expect(
      sessionSidebarElapsed(now, now.subtract(const Duration(seconds: 1))),
      '00:00',
    );
    expect(
      sessionSidebarElapsed(
        now,
        now.add(const Duration(minutes: 12, seconds: 34)),
      ),
      '12:34',
    );
  });
}
