import 'dart:math';

import '../productivity/command_blocks_history_feature_flags.dart';
import '../productivity/shell_productivity_models.dart';

class ShellCommandBlocksOverlayViewModel {
  const ShellCommandBlocksOverlayViewModel() : blocks = const [];

  ShellCommandBlocksOverlayViewModel.withBlocks(
    List<ShellCommandBlockOverlayItem> blocks,
  ) : blocks = List.unmodifiable(blocks);

  final List<ShellCommandBlockOverlayItem> blocks;

  bool get isEmpty => blocks.isEmpty;
}

class ShellCommandBlockOverlayItem {
  const ShellCommandBlockOverlayItem({
    required this.id,
    required this.command,
    required this.rowOffset,
    required this.rowSpan,
    required this.status,
    required this.statusLabel,
    required this.active,
    required this.showFailureSnapshotAction,
    required this.showReplayAction,
    required this.showDiffAction,
  });

  final String id;
  final String command;
  final int rowOffset;
  final int rowSpan;
  final ShellCommandBlockStatus status;
  final String statusLabel;
  final bool active;

  /// Failed-only failure snapshot action.
  final bool showFailureSnapshotAction;
  final bool showReplayAction;
  final bool showDiffAction;
}

class ShellCommandBlockViewModelBuilder {
  const ShellCommandBlockViewModelBuilder._();

  static ShellCommandBlocksOverlayViewModel build({
    required List<ShellCommandBlock> blocks,
    required int viewportStartRow,
    required int viewportEndRow,
    required CommandBlocksHistoryFeatureFlags flags,
    String? activeBlockId,
  }) {
    // viewportEndRow is inclusive.
    if (viewportEndRow < viewportStartRow ||
        !flags.enabled ||
        !flags.commandBlocks) {
      return const ShellCommandBlocksOverlayViewModel();
    }
    final visible = <ShellCommandBlockOverlayItem>[];
    final previousValidBlocks = <ShellCommandBlock>[];
    for (final block in blocks) {
      if (!block.isValid) {
        continue;
      }
      final hasPreviousSameCommandAndCwd = previousValidBlocks.any(
        (previous) =>
            previous.command == block.command && previous.cwd == block.cwd,
      );
      if (block.endRow < viewportStartRow || block.startRow > viewportEndRow) {
        previousValidBlocks.add(block);
        continue;
      }
      final visibleStart = max(block.startRow, viewportStartRow);
      final visibleEnd = min(block.endRow, viewportEndRow);
      visible.add(
        ShellCommandBlockOverlayItem(
          id: block.id,
          command: block.command,
          rowOffset: visibleStart - viewportStartRow,
          rowSpan: visibleEnd - visibleStart + 1,
          status: block.status,
          statusLabel: _statusLabel(block),
          active: block.id == activeBlockId,
          showFailureSnapshotAction:
              flags.failureSnapshots &&
              block.status == ShellCommandBlockStatus.failed,
          showReplayAction: flags.reviewWorkspaceEntrypoints,
          showDiffAction: flags.outputDiff && hasPreviousSameCommandAndCwd,
        ),
      );
      previousValidBlocks.add(block);
    }
    return ShellCommandBlocksOverlayViewModel.withBlocks(visible);
  }
}

String _statusLabel(ShellCommandBlock block) {
  return switch (block.status) {
    ShellCommandBlockStatus.succeeded => 'exit 0',
    ShellCommandBlockStatus.failed =>
      block.exitCode == null ? 'failed' : 'exit ${block.exitCode}',
    ShellCommandBlockStatus.running => 'running',
    ShellCommandBlockStatus.unknown => 'unknown',
  };
}
