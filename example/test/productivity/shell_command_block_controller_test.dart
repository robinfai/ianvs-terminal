import 'package:app/features/productivity/command_blocks_history_feature_flags.dart';
import 'package:app/features/productivity/shell_command_block_controller.dart';
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/productivity/shell_productivity_reducer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShellCommandBlockController', () {
    test('does not build blocks or state when flags are disabled', () {
      var snapshot = const ShellCommandBlockSnapshot();

      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellPromptMarkEvent(id: 'p1', row: 1, cwd: '/repo'),
        flags: CommandBlocksHistoryFeatureFlags.disabled,
      );
      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellCommandOutputRangeEvent(
          commandId: 'cmd-1',
          startRow: 2,
          endRow: 8,
        ),
        flags: CommandBlocksHistoryFeatureFlags.disabled,
      );
      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellCommandFinishedEvent(
          command: 'flutter test',
          cwd: '/repo',
          exitCode: 1,
        ),
        flags: CommandBlocksHistoryFeatureFlags.disabled,
      );

      expect(snapshot.blocks, isEmpty);
      expect(snapshot.lastPrompt, isNull);
      expect(snapshot.pendingRange, isNull);
    });

    test('builds failed command block from prompt range and finish event', () {
      var snapshot = const ShellCommandBlockSnapshot();
      const flags = CommandBlocksHistoryFeatureFlags(
        enabled: true,
        commandBlocks: true,
        historyPeek: false,
        failureSnapshots: true,
        reviewWorkspaceEntrypoints: false,
        outputDiff: false,
      );

      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellPromptMarkEvent(id: 'p1', row: 10, cwd: '/repo'),
        flags: flags,
      );
      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellCommandOutputRangeEvent(
          commandId: 'cmd-1',
          startRow: 11,
          endRow: 18,
        ),
        flags: flags,
      );
      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellCommandFinishedEvent(
          command: 'flutter test',
          cwd: '/repo',
          exitCode: 1,
        ),
        flags: flags,
      );

      expect(snapshot.blocks, hasLength(1));
      final block = snapshot.blocks.single;
      expect(block.id, 'cmd-1');
      expect(block.command, 'flutter test');
      expect(block.cwd, '/repo');
      expect(block.status, ShellCommandBlockStatus.failed);
      expect(block.outputRange.startRow, 11);
      expect(block.outputRange.endRow, 18);
      expect(block.failureSnapshot, isNotNull);
      expect(block.failureSnapshot!.exitCode, 1);
    });

    test('finds previous run with same cwd and command', () {
      final previous = ShellCommandBlock(
        id: 'old',
        command: 'flutter test',
        cwd: '/repo',
        outputRange: const ShellCommandBlockRange(
          commandRow: 1,
          outputStartRow: 2,
          outputEndRow: 8,
        ),
        status: ShellCommandBlockStatus.succeeded,
      );
      final current = ShellCommandBlock(
        id: 'new',
        command: 'flutter test',
        cwd: '/repo',
        outputRange: const ShellCommandBlockRange(
          commandRow: 12,
          outputStartRow: 13,
          outputEndRow: 20,
        ),
        status: ShellCommandBlockStatus.failed,
      );

      final snapshot = ShellCommandBlockSnapshot(blocks: [previous, current]);

      expect(snapshot.previousRunFor(current)!.id, 'old');
    });
  });
}
