import 'package:app/features/productivity/command_blocks_history_feature_flags.dart';
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/shell/shell_command_block_view_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShellCommandBlockViewModels', () {
    test('returns no overlays when commandBlocks flag is off', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [
          ShellCommandBlock(
            id: 'cmd',
            command: 'flutter test',
            outputRange: const ShellCommandBlockRange(
              commandRow: 1,
              outputStartRow: 2,
              outputEndRow: 4,
            ),
            status: ShellCommandBlockStatus.failed,
          ),
        ],
        viewportStartRow: 0,
        viewportEndRow: 10,
        flags: CommandBlocksHistoryFeatureFlags.disabled,
      );

      expect(viewModel.blocks, isEmpty);
    });

    test('maps visible failed block into overlay state', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [
          ShellCommandBlock(
            id: 'cmd',
            command: 'flutter test',
            cwd: '/repo',
            exitCode: 1,
            outputRange: const ShellCommandBlockRange(
              commandRow: 10,
              outputStartRow: 11,
              outputEndRow: 20,
            ),
            status: ShellCommandBlockStatus.failed,
          ),
        ],
        viewportStartRow: 8,
        viewportEndRow: 24,
        activeBlockId: 'cmd',
        flags: _enabledFlags(),
      );

      expect(viewModel.blocks, hasLength(1));
      expect(viewModel.blocks.single.id, 'cmd');
      expect(viewModel.blocks.single.active, isTrue);
      expect(viewModel.blocks.single.statusLabel, 'exit 1');
      expect(viewModel.blocks.single.showFailureSnapshotAction, isTrue);
      expect(viewModel.blocks.single.showReplayAction, isTrue);
    });

    test('reviewWorkspaceEntrypoints flag drives replay action', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [_commandBlock(startRow: 1, endRow: 4)],
        viewportStartRow: 0,
        viewportEndRow: 10,
        flags: _enabledFlags(reviewWorkspaceEntrypoints: false),
      );

      expect(viewModel.blocks.single.showReplayAction, isFalse);
    });

    test('invalid viewport returns empty and does not throw', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [_commandBlock(startRow: 5, endRow: 10)],
        viewportStartRow: 20,
        viewportEndRow: 10,
        flags: _enabledFlags(),
      );

      expect(viewModel.blocks, isEmpty);
    });

    test('block crossing viewport is clipped', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [_commandBlock(startRow: 5, endRow: 20)],
        viewportStartRow: 10,
        viewportEndRow: 12,
        flags: _enabledFlags(),
      );

      expect(viewModel.blocks, hasLength(1));
      expect(viewModel.blocks.single.rowOffset, 0);
      expect(viewModel.blocks.single.rowSpan, 3);
    });

    test('block completely outside viewport is skipped', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [_commandBlock(startRow: 1, endRow: 4)],
        viewportStartRow: 10,
        viewportEndRow: 12,
        flags: _enabledFlags(),
      );

      expect(viewModel.blocks, isEmpty);
    });

    test('invalid block is skipped', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [
          const ShellCommandBlock(
            id: '',
            command: 'flutter test',
            outputRange: ShellCommandBlockRange(
              commandRow: 1,
              outputStartRow: 2,
              outputEndRow: 4,
            ),
          ),
        ],
        viewportStartRow: 0,
        viewportEndRow: 10,
        flags: _enabledFlags(),
      );

      expect(viewModel.blocks, isEmpty);
    });

    test('view model freezes blocks list against external mutation', () {
      final blocks = [_overlayItem(id: 'first')];
      final viewModel = ShellCommandBlocksOverlayViewModel.withBlocks(blocks);

      blocks.add(_overlayItem(id: 'second'));

      expect(viewModel.blocks, hasLength(1));
      expect(viewModel.blocks.single.id, 'first');
      expect(
        () => viewModel.blocks.add(_overlayItem(id: 'third')),
        throwsA(anything),
      );
    });

    test('failed without exitCode status label is failed', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [
          _commandBlock(
            startRow: 1,
            endRow: 4,
            status: ShellCommandBlockStatus.failed,
          ),
        ],
        viewportStartRow: 0,
        viewportEndRow: 10,
        flags: _enabledFlags(),
      );

      expect(viewModel.blocks.single.statusLabel, 'failed');
    });

    test('single block with outputDiff flag does not show diff action', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [_commandBlock(startRow: 1, endRow: 4)],
        viewportStartRow: 0,
        viewportEndRow: 10,
        flags: _enabledFlags(outputDiff: true),
      );

      expect(viewModel.blocks.single.showDiffAction, isFalse);
    });

    test('previous matching command and cwd enables diff action', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [
          _commandBlock(startRow: 1, endRow: 4, cwd: '/repo'),
          _commandBlock(startRow: 10, endRow: 12, cwd: '/repo'),
        ],
        viewportStartRow: 10,
        viewportEndRow: 12,
        flags: _enabledFlags(outputDiff: true),
      );

      expect(viewModel.blocks.single.showDiffAction, isTrue);
    });

    test('future matching command and cwd does not enable diff action', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [
          _commandBlock(startRow: 10, endRow: 12, cwd: '/repo'),
          _commandBlock(startRow: 20, endRow: 24, cwd: '/repo'),
        ],
        viewportStartRow: 10,
        viewportEndRow: 12,
        flags: _enabledFlags(outputDiff: true),
      );

      expect(viewModel.blocks.single.showDiffAction, isFalse);
    });

    test('previous command mismatch does not enable diff action', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [
          _commandBlock(
            startRow: 1,
            endRow: 4,
            command: 'dart test',
            cwd: '/repo',
          ),
          _commandBlock(startRow: 10, endRow: 12, cwd: '/repo'),
        ],
        viewportStartRow: 10,
        viewportEndRow: 12,
        flags: _enabledFlags(outputDiff: true),
      );

      expect(viewModel.blocks.single.showDiffAction, isFalse);
    });

    test('previous cwd mismatch does not enable diff action', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [
          _commandBlock(startRow: 1, endRow: 4, cwd: '/other'),
          _commandBlock(startRow: 10, endRow: 12, cwd: '/repo'),
        ],
        viewportStartRow: 10,
        viewportEndRow: 12,
        flags: _enabledFlags(outputDiff: true),
      );

      expect(viewModel.blocks.single.showDiffAction, isFalse);
    });

    test('succeeded block does not show failure snapshot action', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [_commandBlock(startRow: 1, endRow: 4)],
        viewportStartRow: 0,
        viewportEndRow: 10,
        flags: _enabledFlags(failureSnapshots: true),
      );

      expect(viewModel.blocks.single.showFailureSnapshotAction, isFalse);
    });

    test(
      'failed block without failureSnapshots flag hides snapshot action',
      () {
        final viewModel = ShellCommandBlockViewModelBuilder.build(
          blocks: [
            _commandBlock(
              startRow: 1,
              endRow: 4,
              status: ShellCommandBlockStatus.failed,
            ),
          ],
          viewportStartRow: 0,
          viewportEndRow: 10,
          flags: _enabledFlags(failureSnapshots: false),
        );

        expect(viewModel.blocks.single.showFailureSnapshotAction, isFalse);
      },
    );

    test('block ending on viewport start is visible', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [_commandBlock(startRow: 5, endRow: 10)],
        viewportStartRow: 10,
        viewportEndRow: 12,
        flags: _enabledFlags(),
      );

      expect(viewModel.blocks, hasLength(1));
      expect(viewModel.blocks.single.rowOffset, 0);
      expect(viewModel.blocks.single.rowSpan, 1);
    });

    test('block starting on viewport end is visible', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [_commandBlock(startRow: 12, endRow: 12)],
        viewportStartRow: 10,
        viewportEndRow: 12,
        flags: _enabledFlags(),
      );

      expect(viewModel.blocks, hasLength(1));
      expect(viewModel.blocks.single.rowOffset, 2);
      expect(viewModel.blocks.single.rowSpan, 1);
    });
  });
}

CommandBlocksHistoryFeatureFlags _enabledFlags({
  bool failureSnapshots = true,
  bool reviewWorkspaceEntrypoints = true,
  bool outputDiff = false,
}) {
  return CommandBlocksHistoryFeatureFlags(
    enabled: true,
    commandBlocks: true,
    historyPeek: false,
    failureSnapshots: failureSnapshots,
    reviewWorkspaceEntrypoints: reviewWorkspaceEntrypoints,
    outputDiff: outputDiff,
  );
}

ShellCommandBlock _commandBlock({
  required int startRow,
  required int endRow,
  String command = 'flutter test',
  String? cwd,
  ShellCommandBlockStatus status = ShellCommandBlockStatus.succeeded,
}) {
  return ShellCommandBlock(
    id: 'cmd-$startRow-$endRow',
    command: command,
    cwd: cwd,
    outputRange: ShellCommandBlockRange(
      commandRow: startRow,
      outputStartRow: startRow == endRow ? startRow : startRow + 1,
      outputEndRow: endRow,
    ),
    status: status,
  );
}

ShellCommandBlockOverlayItem _overlayItem({required String id}) {
  return ShellCommandBlockOverlayItem(
    id: id,
    command: 'flutter test',
    rowOffset: 0,
    rowSpan: 1,
    status: ShellCommandBlockStatus.succeeded,
    statusLabel: 'exit 0',
    active: false,
    showFailureSnapshotAction: false,
    showReplayAction: false,
    showDiffAction: false,
  );
}
