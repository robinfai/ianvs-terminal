import 'package:app/features/command_center/command_center_runtime.dart';
import 'package:app/features/command_center/command_history_persistence_wiring.dart';
import 'package:app/features/command_center/global_command_history_repository.dart';
import 'package:app/features/command_center/shell_hook_lifecycle_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandHistoryPersistenceWiring', () {
    const wiring = CommandHistoryPersistenceWiring();

    test('merges runtime session history into global history', () {
      const reducer = CommandCenterRuntimeReducer();
      final finishedAt = DateTime.utc(2026, 6, 15, 10);
      final state = reducer.apply(
        const CommandCenterRuntimeState(),
        CommandLifecycleFinishedEvent(
          sessionId: 'session-a',
          receivedAt: finishedAt,
          command: 'flutter test',
          cwd: '/repo',
          exitCode: 0,
        ),
      );
      final global = GlobalCommandHistoryDocument(
        entries: [
          GlobalCommandHistoryEntry(
            command: 'git status',
            cwd: '/repo',
            exitCode: 0,
            finishedAt: finishedAt.subtract(const Duration(minutes: 1)),
          ),
        ],
      );

      final merged = wiring.documentAfterSessionSync(
        globalHistory: global,
        runtimeState: state,
        sessionId: 'session-a',
      );

      expect(merged.entries.map((entry) => entry.command), [
        'flutter test',
        'git status',
      ]);
      expect(merged.entries.first.cwd, '/repo');
      expect(merged.entries.first.exitCode, 0);
      expect(merged.entries.first.invocationId, isNotNull);
    });

    test('does not copy unrelated session history', () {
      const reducer = CommandCenterRuntimeReducer();
      final finishedAt = DateTime.utc(2026, 6, 15, 10);
      final state = reducer.apply(
        const CommandCenterRuntimeState(),
        CommandLifecycleFinishedEvent(
          sessionId: 'session-b',
          receivedAt: finishedAt,
          command: 'pwd',
          cwd: '/tmp',
          exitCode: 0,
        ),
      );

      final merged = wiring.documentAfterSessionSync(
        globalHistory: const GlobalCommandHistoryDocument(),
        runtimeState: state,
        sessionId: 'session-a',
      );

      expect(merged.entries, isEmpty);
    });
  });
}
