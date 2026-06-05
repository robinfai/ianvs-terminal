import 'package:app/features/productivity/command_blocks_history_feature_flags.dart';
import 'package:app/features/productivity/shell_command_block_controller.dart';
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/productivity/shell_productivity_reducer.dart';
import 'package:flutter_test/flutter_test.dart';

const _enabledFlags = CommandBlocksHistoryFeatureFlags(
  enabled: true,
  commandBlocks: true,
  historyPeek: false,
  failureSnapshots: true,
  reviewWorkspaceEntrypoints: false,
  outputDiff: false,
);

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

      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellPromptMarkEvent(id: 'p1', row: 10, cwd: '/repo'),
        flags: _enabledFlags,
      );
      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellCommandOutputRangeEvent(
          commandId: 'cmd-1',
          startRow: 11,
          endRow: 18,
        ),
        flags: _enabledFlags,
      );
      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellCommandFinishedEvent(
          command: 'flutter test',
          cwd: '/repo',
          exitCode: 1,
        ),
        flags: _enabledFlags,
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

    test('rejects blank command id output ranges', () {
      final snapshot = ShellCommandBlockController.reduce(
        const ShellCommandBlockSnapshot(),
        const ShellCommandOutputRangeEvent(
          commandId: '   ',
          startRow: 2,
          endRow: 8,
        ),
        flags: _enabledFlags,
      );

      expect(snapshot.pendingRange, isNull);
    });

    test('clears pending range when finished command is blank', () {
      var snapshot = const ShellCommandBlockSnapshot();
      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellCommandOutputRangeEvent(
          commandId: 'cmd-blank',
          startRow: 2,
          endRow: 8,
        ),
        flags: _enabledFlags,
      );

      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellCommandFinishedEvent(
          command: '   ',
          cwd: '/repo',
          exitCode: 0,
        ),
        flags: _enabledFlags,
      );

      expect(snapshot.blocks, isEmpty);
      expect(snapshot.pendingRange, isNull);
    });

    test('clears pending range when prompt makes output range invalid', () {
      var snapshot = const ShellCommandBlockSnapshot();
      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellPromptMarkEvent(id: 'p-late', row: 10, cwd: '/repo'),
        flags: _enabledFlags,
      );
      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellCommandOutputRangeEvent(
          commandId: 'cmd-invalid',
          startRow: 2,
          endRow: 8,
        ),
        flags: _enabledFlags,
      );

      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellCommandFinishedEvent(
          command: 'flutter test',
          cwd: '/repo',
          exitCode: 1,
        ),
        flags: _enabledFlags,
      );

      expect(snapshot.blocks, isEmpty);
      expect(snapshot.pendingRange, isNull);
    });
  });

  group('Shell command block models', () {
    test('treats omitted range as invalid', () {
      const block = ShellCommandBlock(
        id: 'missing-range',
        command: 'flutter test',
      );

      expect(block.isValid, isFalse);
      expect(block.containsRow(0), isFalse);
    });

    test('exposes immutable lists', () {
      const block = ShellCommandBlock(
        id: 'cmd-1',
        command: 'flutter test',
        outputRange: ShellCommandBlockRange(
          commandRow: 1,
          outputStartRow: 2,
          outputEndRow: 8,
        ),
      );
      const marker = ShellHistoryMarker(
        id: 'm1',
        row: 4,
        kind: ShellHistoryMarkerKind.failure,
      );
      const failureSnapshot = ShellFailureSnapshot(
        commandBlockId: 'cmd-1',
        command: 'flutter test',
        cwd: '/repo',
        exitCode: 1,
        outputRange: ShellCommandBlockRange(
          commandRow: 1,
          outputStartRow: 2,
          outputEndRow: 8,
        ),
        keyErrorLines: ['Expected:'],
      );
      final snapshot = ShellCommandBlockSnapshot(blocks: [block]);
      final markedBlock = ShellCommandBlock(
        id: 'cmd-2',
        command: 'dart analyze',
        outputRange: const ShellCommandBlockRange(
          commandRow: 10,
          outputStartRow: 11,
          outputEndRow: 14,
        ),
        markers: [marker],
      );

      expect(() => snapshot.blocks.add(block), throwsUnsupportedError);
      expect(() => markedBlock.markers.add(marker), throwsUnsupportedError);
      expect(
        () => failureSnapshot.keyErrorLines.add('Actual:'),
        throwsUnsupportedError,
      );
    });

    test('copyWith can clear nullable fields', () {
      const failureSnapshot = ShellFailureSnapshot(
        commandBlockId: 'cmd-1',
        command: 'flutter test',
        cwd: '/repo',
        exitCode: 1,
        outputRange: ShellCommandBlockRange(
          commandRow: 1,
          outputStartRow: 2,
          outputEndRow: 8,
        ),
      );
      const block = ShellCommandBlock(
        id: 'cmd-1',
        command: 'flutter test',
        cwd: '/repo',
        exitCode: 1,
        outputRange: ShellCommandBlockRange(
          commandRow: 1,
          outputStartRow: 2,
          outputEndRow: 8,
        ),
        failureSnapshot: failureSnapshot,
      );

      final cleared = block.copyWith(
        cwd: null,
        exitCode: null,
        failureSnapshot: null,
      );

      expect(cleared.cwd, isNull);
      expect(cleared.exitCode, isNull);
      expect(cleared.failureSnapshot, isNull);
    });
  });
}
