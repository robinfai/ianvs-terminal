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

const _flagsWithoutFailureSnapshots = CommandBlocksHistoryFeatureFlags(
  enabled: true,
  commandBlocks: true,
  historyPeek: false,
  failureSnapshots: false,
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

    test('uses current cwd when prompt and finish do not provide cwd', () {
      var snapshot = const ShellCommandBlockSnapshot();

      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellCwdChangedEvent('/repo'),
        flags: _enabledFlags,
      );
      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellPromptMarkEvent(id: 'p1', row: 10),
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
          cwd: null,
          exitCode: 1,
        ),
        flags: _enabledFlags,
      );

      final block = snapshot.blocks.single;
      expect(block.cwd, '/repo');
      expect(block.failureSnapshot!.cwd, '/repo');
    });

    test('prompt cwd updates current cwd for later finish events', () {
      var snapshot = const ShellCommandBlockSnapshot();

      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellPromptMarkEvent(id: 'p1', row: 10, cwd: '  /repo  '),
        flags: _enabledFlags,
      );

      expect(snapshot.currentCwd, '/repo');
      expect(snapshot.lastPrompt!.cwd, '/repo');

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
          cwd: null,
          exitCode: 0,
        ),
        flags: _enabledFlags,
      );

      expect(snapshot.blocks.single.cwd, '/repo');
      expect(snapshot.currentCwd, '/repo');
    });

    test('finish cwd updates current cwd without a pending range', () {
      final snapshot = ShellCommandBlockController.reduce(
        const ShellCommandBlockSnapshot(),
        const ShellCommandFinishedEvent(
          command: 'flutter test',
          cwd: '  /repo  ',
          exitCode: 0,
        ),
        flags: _enabledFlags,
      );

      expect(snapshot.blocks, isEmpty);
      expect(snapshot.pendingRange, isNull);
      expect(snapshot.currentCwd, '/repo');
    });

    test('finish cwd takes precedence over prompt and current cwd', () {
      var snapshot = const ShellCommandBlockSnapshot();

      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellCwdChangedEvent('/current'),
        flags: _enabledFlags,
      );
      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellPromptMarkEvent(id: 'p1', row: 10, cwd: '/prompt'),
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
          cwd: '  /finish  ',
          exitCode: 1,
        ),
        flags: _enabledFlags,
      );

      final block = snapshot.blocks.single;
      expect(block.cwd, '/finish');
      expect(block.failureSnapshot!.cwd, '/finish');
      expect(snapshot.currentCwd, '/finish');
    });

    test('does not create failure snapshot when snapshots are disabled', () {
      var snapshot = const ShellCommandBlockSnapshot();

      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellPromptMarkEvent(id: 'p1', row: 10, cwd: '/repo'),
        flags: _flagsWithoutFailureSnapshots,
      );
      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellCommandOutputRangeEvent(
          commandId: 'cmd-1',
          startRow: 11,
          endRow: 18,
        ),
        flags: _flagsWithoutFailureSnapshots,
      );
      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellCommandFinishedEvent(
          command: 'flutter test',
          cwd: '/repo',
          exitCode: 1,
        ),
        flags: _flagsWithoutFailureSnapshots,
      );

      final block = snapshot.blocks.single;
      expect(block.status, ShellCommandBlockStatus.failed);
      expect(block.failureSnapshot, isNull);
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

      final snapshot = ShellCommandBlockSnapshot.withBlocks(
        blocks: [previous, current],
      );

      expect(snapshot.previousRunFor(current)!.id, 'old');
    });

    test('finds previous run before a block in the snapshot', () {
      final old = ShellCommandBlock(
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
      final mid = ShellCommandBlock(
        id: 'mid',
        command: 'flutter test',
        cwd: '/repo',
        outputRange: const ShellCommandBlockRange(
          commandRow: 10,
          outputStartRow: 11,
          outputEndRow: 18,
        ),
        status: ShellCommandBlockStatus.failed,
      );
      final latest = ShellCommandBlock(
        id: 'latest',
        command: 'flutter test',
        cwd: '/repo',
        outputRange: const ShellCommandBlockRange(
          commandRow: 20,
          outputStartRow: 21,
          outputEndRow: 28,
        ),
        status: ShellCommandBlockStatus.succeeded,
      );
      final snapshot = ShellCommandBlockSnapshot.withBlocks(
        blocks: [old, mid, latest],
      );

      expect(snapshot.previousRunFor(mid)!.id, 'old');
    });

    test('finds latest matching run when block is not in the snapshot', () {
      final old = ShellCommandBlock(
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
      final latest = ShellCommandBlock(
        id: 'latest',
        command: 'flutter test',
        cwd: '/repo',
        outputRange: const ShellCommandBlockRange(
          commandRow: 10,
          outputStartRow: 11,
          outputEndRow: 18,
        ),
        status: ShellCommandBlockStatus.failed,
      );
      const unsaved = ShellCommandBlock(
        id: 'unsaved',
        command: 'flutter test',
        cwd: '/repo',
        outputRange: ShellCommandBlockRange(
          commandRow: 20,
          outputStartRow: 21,
          outputEndRow: 28,
        ),
      );
      final snapshot = ShellCommandBlockSnapshot.withBlocks(
        blocks: [old, latest],
      );

      expect(snapshot.previousRunFor(unsaved)!.id, 'latest');
    });

    test('clears stale pending range for blank command id output ranges', () {
      var snapshot = const ShellCommandBlockSnapshot();

      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellCommandOutputRangeEvent(
          commandId: 'cmd-old',
          startRow: 2,
          endRow: 8,
        ),
        flags: _enabledFlags,
      );
      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellCommandOutputRangeEvent(
          commandId: '   ',
          startRow: 9,
          endRow: 12,
        ),
        flags: _enabledFlags,
      );
      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellCommandFinishedEvent(
          command: 'flutter test',
          cwd: '/repo',
          exitCode: 0,
        ),
        flags: _enabledFlags,
      );

      expect(snapshot.pendingRange, isNull);
      expect(snapshot.blocks, isEmpty);
    });

    test('clears stale pending range for invalid output range rows', () {
      var snapshot = const ShellCommandBlockSnapshot();

      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellCommandOutputRangeEvent(
          commandId: 'cmd-old',
          startRow: 2,
          endRow: 8,
        ),
        flags: _enabledFlags,
      );
      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellCommandOutputRangeEvent(
          commandId: 'cmd-bad',
          startRow: 12,
          endRow: 9,
        ),
        flags: _enabledFlags,
      );
      snapshot = ShellCommandBlockController.reduce(
        snapshot,
        const ShellCommandFinishedEvent(
          command: 'flutter test',
          cwd: '/repo',
          exitCode: 0,
        ),
        flags: _enabledFlags,
      );

      expect(snapshot.pendingRange, isNull);
      expect(snapshot.blocks, isEmpty);
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
      final failureSnapshot = ShellFailureSnapshot.withKeyErrorLines(
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
      final snapshot = ShellCommandBlockSnapshot.withBlocks(blocks: [block]);
      final markedBlock = ShellCommandBlock.withMarkers(
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

    test('freezes mutable list inputs at construction time', () {
      const firstBlock = ShellCommandBlock(
        id: 'cmd-1',
        command: 'flutter test',
        outputRange: ShellCommandBlockRange(
          commandRow: 1,
          outputStartRow: 2,
          outputEndRow: 8,
        ),
      );
      const secondBlock = ShellCommandBlock(
        id: 'cmd-2',
        command: 'dart analyze',
        outputRange: ShellCommandBlockRange(
          commandRow: 10,
          outputStartRow: 11,
          outputEndRow: 14,
        ),
      );
      const firstMarker = ShellHistoryMarker(
        id: 'm1',
        row: 3,
        kind: ShellHistoryMarkerKind.manual,
      );
      const secondMarker = ShellHistoryMarker(
        id: 'm2',
        row: 4,
        kind: ShellHistoryMarkerKind.failure,
      );

      final blocks = <ShellCommandBlock>[firstBlock];
      final snapshot = ShellCommandBlockSnapshot.withBlocks(blocks: blocks);
      blocks.add(secondBlock);

      final markers = <ShellHistoryMarker>[firstMarker];
      final block = ShellCommandBlock.withMarkers(
        id: 'cmd-3',
        command: 'dart test',
        outputRange: const ShellCommandBlockRange(
          commandRow: 20,
          outputStartRow: 21,
          outputEndRow: 25,
        ),
        markers: markers,
      );
      markers.add(secondMarker);

      final keyErrorLines = <String>['Expected:'];
      final failureSnapshot = ShellFailureSnapshot.withKeyErrorLines(
        commandBlockId: 'cmd-4',
        command: 'flutter test',
        cwd: '/repo',
        exitCode: 1,
        outputRange: const ShellCommandBlockRange(
          commandRow: 30,
          outputStartRow: 31,
          outputEndRow: 40,
        ),
        keyErrorLines: keyErrorLines,
      );
      keyErrorLines.add('Actual:');

      expect(snapshot.blocks, hasLength(1));
      expect(snapshot.blocks.single.id, 'cmd-1');
      expect(block.markers, hasLength(1));
      expect(block.markers.single.id, 'm1');
      expect(failureSnapshot.keyErrorLines, ['Expected:']);
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
