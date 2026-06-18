import 'package:app/features/command_center/command_invocation_models.dart';
import 'package:app/features/command_center/context_chip_models.dart';
import 'package:app/features/command_center/shell_command_block_command_center_adapter.dart';
import 'package:app/features/productivity/shell_command_block_controller.dart';
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShellCommandBlockCommandCenterAdapter', () {
    const adapter = ShellCommandBlockCommandCenterAdapter();

    test('uses selected block when it exists in the snapshot', () {
      final snapshot = ShellCommandBlockSnapshot.withBlocks(
        blocks: const [
          ShellCommandBlock(
            id: 'old',
            command: 'false',
            status: ShellCommandBlockStatus.failed,
            exitCode: 2,
            outputRange: ShellCommandBlockRange(
              commandRow: 10,
              outputStartRow: 11,
              outputEndRow: 12,
            ),
          ),
          ShellCommandBlock(
            id: 'new',
            command: 'echo ok',
            status: ShellCommandBlockStatus.succeeded,
            exitCode: 0,
            outputRange: ShellCommandBlockRange(
              commandRow: 20,
              outputStartRow: 21,
              outputEndRow: 22,
            ),
          ),
        ],
      );

      final block = adapter.activeCompatibleBlockFor(
        snapshot: snapshot,
        sessionId: 'session-a',
        selectedBlockId: 'old',
      );

      expect(block?.id, 'old');
      expect(block?.sessionId, 'session-a');
      expect(block?.status, CommandInvocationStatus.failed);
      expect(block?.inputRange?.startRow, 10);
      expect(block?.inputRange?.endRowExclusive, 11);
      expect(block?.outputRange?.startRow, 11);
      expect(block?.outputRange?.endRowExclusive, 13);
    });

    test('preserves shell command block timestamps', () {
      final startedAt = DateTime.utc(2026, 6, 18, 10);
      final finishedAt = startedAt.add(const Duration(seconds: 1));
      final snapshot = ShellCommandBlockSnapshot.withBlocks(
        blocks: [
          ShellCommandBlock(
            id: 'sleep',
            command: 'sleep 1 && echo 1',
            status: ShellCommandBlockStatus.succeeded,
            exitCode: 0,
            startedAt: startedAt,
            finishedAt: finishedAt,
            outputRange: const ShellCommandBlockRange(
              commandRow: 20,
              outputStartRow: 21,
              outputEndRow: 21,
            ),
          ),
        ],
      );

      final block = adapter.activeCompatibleBlockFor(
        snapshot: snapshot,
        sessionId: 'session-a',
      );

      expect(block?.startedAt, startedAt);
      expect(block?.finishedAt, finishedAt);
      expect(
        block?.finishedAt?.difference(block.startedAt),
        const Duration(seconds: 1),
      );
    });

    test('falls back to newest valid block when selected block is missing', () {
      final snapshot = ShellCommandBlockSnapshot.withBlocks(
        blocks: const [
          ShellCommandBlock(
            id: 'old',
            command: 'false',
            status: ShellCommandBlockStatus.failed,
            exitCode: 2,
            outputRange: ShellCommandBlockRange(
              commandRow: 10,
              outputStartRow: 11,
              outputEndRow: 11,
            ),
          ),
          ShellCommandBlock(
            id: 'new',
            command: 'echo ok',
            status: ShellCommandBlockStatus.succeeded,
            exitCode: 0,
            outputRange: ShellCommandBlockRange(
              commandRow: 20,
              outputStartRow: 21,
              outputEndRow: 21,
            ),
          ),
        ],
      );

      final block = adapter.activeCompatibleBlockFor(
        snapshot: snapshot,
        sessionId: 'session-a',
        selectedBlockId: 'missing',
      );

      expect(block?.id, 'new');
    });

    test(
      'exposes last failed block and selected block chips from snapshot',
      () {
        final snapshot = ShellCommandBlockSnapshot.withBlocks(
          blocks: const [
            ShellCommandBlock(
              id: 'failed',
              command: 'flutter test',
              status: ShellCommandBlockStatus.failed,
              exitCode: 1,
              outputRange: ShellCommandBlockRange(
                commandRow: 30,
                outputStartRow: 31,
                outputEndRow: 33,
              ),
            ),
            ShellCommandBlock(
              id: 'newest',
              command: 'echo ok',
              status: ShellCommandBlockStatus.succeeded,
              exitCode: 0,
              outputRange: ShellCommandBlockRange(
                commandRow: 40,
                outputStartRow: 41,
                outputEndRow: 41,
              ),
            ),
          ],
        );

        final chips = adapter.contextChipsForSession(
          snapshot: snapshot,
          sessionId: 'session-a',
          cwd: '/repo',
          profileId: 'default',
          profileName: 'Default',
          selectedBlockId: 'failed',
        );

        expect(
          chips.byKind(ContextChipKind.lastExit)?.intent.blockId,
          'failed',
        );
        expect(
          chips.byKind(ContextChipKind.selectedBlock)?.intent.blockId,
          'failed',
        );
        expect(chips.byKind(ContextChipKind.cwd)?.value, '/repo');
      },
    );
  });
}
