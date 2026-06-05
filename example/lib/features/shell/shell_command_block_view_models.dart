import '../productivity/command_blocks_history_feature_flags.dart';
import '../productivity/shell_productivity_models.dart';

class ShellCommandBlocksOverlayViewModel {
  const ShellCommandBlocksOverlayViewModel({this.blocks = const []});

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
    if (!flags.enabled || !flags.commandBlocks) {
      return const ShellCommandBlocksOverlayViewModel();
    }
    final visible = <ShellCommandBlockOverlayItem>[];
    for (final block in blocks) {
      if (!block.isValid) {
        continue;
      }
      if (block.endRow < viewportStartRow || block.startRow > viewportEndRow) {
        continue;
      }
      visible.add(
        ShellCommandBlockOverlayItem(
          id: block.id,
          command: block.command,
          rowOffset: (block.startRow - viewportStartRow).clamp(
            0,
            viewportEndRow - viewportStartRow,
          ),
          rowSpan: (block.endRow - block.startRow + 1).clamp(1, 100000),
          status: block.status,
          statusLabel: _statusLabel(block),
          active: block.id == activeBlockId,
          showFailureSnapshotAction:
              flags.failureSnapshots &&
              block.status == ShellCommandBlockStatus.failed,
          showReplayAction: flags.reviewWorkspaceEntrypoints,
          showDiffAction: flags.outputDiff,
        ),
      );
    }
    return ShellCommandBlocksOverlayViewModel(blocks: visible);
  }
}

String _statusLabel(ShellCommandBlock block) {
  return switch (block.status) {
    ShellCommandBlockStatus.succeeded => 'exit 0',
    ShellCommandBlockStatus.failed => 'exit ${block.exitCode ?? 1}',
    ShellCommandBlockStatus.running => 'running',
    ShellCommandBlockStatus.unknown => 'unknown',
  };
}
