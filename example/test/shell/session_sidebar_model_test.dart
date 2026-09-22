import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/shell/session_sidebar_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 15);
  test(
    'elapsed time uses readable units at minute, hour and day boundaries',
    () {
      final cases = <Duration, String>{
        Duration.zero: '0s',
        const Duration(seconds: 59): '59s',
        const Duration(minutes: 1): '1min',
        const Duration(minutes: 59, seconds: 59): '59min',
        const Duration(hours: 1): '1h',
        const Duration(minutes: 405, seconds: 55): '6h 45min',
        const Duration(minutes: 357, seconds: 25): '5h 57min',
        const Duration(minutes: 1369, seconds: 28): '22h 49min',
        const Duration(hours: 23, minutes: 59, seconds: 59): '23h 59min',
        const Duration(days: 1): '1d',
        const Duration(days: 1, hours: 3, minutes: 59): '1d 3h',
        const Duration(days: 8, hours: 2): '8d 2h',
      };
      for (final entry in cases.entries) {
        expect(sessionSidebarElapsed(now, now.add(entry.key)), entry.value);
      }
      expect(
        sessionSidebarElapsed(
          now,
          now.add(const Duration(minutes: 1369, seconds: 28)),
          languageCode: 'zh',
        ),
        '22小时 49分',
      );
      expect(sessionSidebarElapsed(now, now, languageCode: 'unknown'), '0s');
    },
  );
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
      '0s',
    );
    expect(
      sessionSidebarElapsed(
        now,
        now.add(const Duration(minutes: 12, seconds: 34)),
      ),
      '12min',
    );
  });
}
