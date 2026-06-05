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
      expect(viewModel.blocks.single.statusLabel, 'exit 1');
      expect(viewModel.blocks.single.showFailureSnapshotAction, isTrue);
      expect(viewModel.blocks.single.showReplayAction, isTrue);
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

    test('outputDiff flag drives showDiffAction', () {
      final viewModel = ShellCommandBlockViewModelBuilder.build(
        blocks: [_commandBlock(startRow: 1, endRow: 4)],
        viewportStartRow: 0,
        viewportEndRow: 10,
        flags: _enabledFlags(outputDiff: true),
      );

      expect(viewModel.blocks.single.showDiffAction, isTrue);
    });
  });
}

CommandBlocksHistoryFeatureFlags _enabledFlags({bool outputDiff = false}) {
  return CommandBlocksHistoryFeatureFlags(
    enabled: true,
    commandBlocks: true,
    historyPeek: false,
    failureSnapshots: true,
    reviewWorkspaceEntrypoints: true,
    outputDiff: outputDiff,
  );
}

ShellCommandBlock _commandBlock({
  required int startRow,
  required int endRow,
  ShellCommandBlockStatus status = ShellCommandBlockStatus.succeeded,
}) {
  return ShellCommandBlock(
    id: 'cmd-$startRow-$endRow',
    command: 'flutter test',
    outputRange: ShellCommandBlockRange(
      commandRow: startRow,
      outputStartRow: startRow + 1,
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
