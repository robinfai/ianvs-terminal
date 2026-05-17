import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/productivity/shell_productivity_reducer.dart';
import 'package:app/features/productivity/shell_productivity_runtime_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shell productivity runtime controller', () {
    test('applies productivity event and persists recent items', () async {
      final controller = ShellProductivityRuntimeController();
      final persisted = <ShellRecentItemsState>[];

      final snapshot = await controller.apply(
        event: const ShellCommandFinishedEvent(
          command: 'flutter test',
          cwd: '/repo',
          exitCode: 0,
        ),
        persistRecentItems: (recentItems) async => persisted.add(recentItems),
      );

      expect(snapshot.recentItems.commands.single.command, 'flutter test');
      expect(persisted.single.commands.single.cwd, '/repo');
    });

    test('keeps current snapshot after multiple events', () async {
      final controller = ShellProductivityRuntimeController();

      await controller.apply(event: const ShellCwdChangedEvent('/repo'));
      await controller.apply(
        event: const ShellPromptMarkEvent(id: 'p1', row: 4),
      );

      expect(controller.snapshot.currentCwd, '/repo');
      expect(controller.snapshot.state.promptMarks.single.id, 'p1');
    });
  });
}
