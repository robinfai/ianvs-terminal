import 'dart:math';

import '../productivity/command_blocks_history_feature_flags.dart';
import '../productivity/shell_productivity_models.dart';
import '../terminal/terminal.dart' as terminal;

const int shellCommandBlockStackVisibleLimit = 5;
const int shellCommandBlockOutputPreviewLineLimit = 3;

final RegExp _promptTimePattern = RegExp(r'\b\d{1,2}:\d{2}\b');
final RegExp _homeSegmentPattern = RegExp(r'(^|\s)~(\s|$)');
final RegExp _promptCuePattern = RegExp(r'(^|\s)[$#>%](\s|$)');
final RegExp _shellDiagnosticPattern = RegExp(r'^(zsh|bash|sh|fish|sudo):\s');

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
    this.cwd,
    this.durationLabel = '--',
    this.outputPreview = '',
    this.outputRangeLabel = '',
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
  final String? cwd;
  final String durationLabel;
  final String outputPreview;
  final String outputRangeLabel;

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
    List<terminal.TerminalRow> visibleRows = const <terminal.TerminalRow>[],
    String? activeBlockId,
    int visibleLimit = shellCommandBlockStackVisibleLimit,
  }) {
    // viewportEndRow is inclusive.
    if (viewportEndRow < viewportStartRow ||
        !flags.enabled ||
        !flags.commandBlocks) {
      return const ShellCommandBlocksOverlayViewModel();
    }
    final rowsByIndex = <int, terminal.TerminalRow>{
      for (final row in visibleRows) row.index: row,
    };
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
      final visibleStart = max(block.startRow, viewportStartRow);
      final visibleEnd = min(block.endRow, viewportEndRow);
      visible.add(
        ShellCommandBlockOverlayItem(
          id: block.id,
          command: block.command,
          rowOffset: max(0, visibleStart - viewportStartRow),
          rowSpan: max(1, visibleEnd - visibleStart + 1),
          status: block.status,
          statusLabel: _statusLabel(block),
          active: block.id == activeBlockId,
          cwd: block.cwd,
          durationLabel: _durationLabel(block, rowsByIndex),
          outputPreview: _outputPreview(block, rowsByIndex),
          outputRangeLabel: _outputRangeLabel(block),
          showFailureSnapshotAction:
              flags.failureSnapshots &&
              block.status == ShellCommandBlockStatus.failed,
          showReplayAction: flags.reviewWorkspaceEntrypoints,
          showDiffAction: flags.outputDiff && hasPreviousSameCommandAndCwd,
        ),
      );
      previousValidBlocks.add(block);
    }
    return ShellCommandBlocksOverlayViewModel.withBlocks(
      visible.reversed.take(max(0, visibleLimit)).toList(growable: false),
    );
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

String _outputRangeLabel(ShellCommandBlock block) {
  final range = block.outputRange;
  return range.outputStartRow == range.outputEndRow
      ? 'row ${range.outputStartRow}'
      : 'rows ${range.outputStartRow}-${range.outputEndRow}';
}

String _outputPreview(
  ShellCommandBlock block,
  Map<int, terminal.TerminalRow> rowsByIndex,
) {
  final lines = <String>[];
  final range = block.outputRange;
  for (var row = range.outputStartRow; row <= range.outputEndRow; row += 1) {
    final text = rowsByIndex[row]?.text.trimRight();
    if (text == null || text.trim().isEmpty) {
      continue;
    }
    if (_looksLikePromptOrReadlineLine(text, block)) {
      continue;
    }
    lines.add(text);
    if (lines.length == shellCommandBlockOutputPreviewLineLimit) {
      break;
    }
  }
  return lines.join('\n');
}

bool _looksLikePromptOrReadlineLine(String text, ShellCommandBlock block) {
  final line = _normalizePromptDetectionText(text);
  if (line.isEmpty || _shellDiagnosticPattern.hasMatch(line)) {
    return false;
  }

  final command = block.command.trim();
  final containsCommand = command.isNotEmpty && line.contains(command);
  if (command.isNotEmpty && line == command) {
    return true;
  }

  final containsPromptTime = _promptTimePattern.hasMatch(line);
  final containsPromptCue = _promptCuePattern.hasMatch(line);
  final containsLocationCue = _containsPromptLocationCue(line, block.cwd);

  if (containsCommand &&
      (containsPromptTime || containsPromptCue || containsLocationCue)) {
    return true;
  }
  if (!containsCommand && containsPromptTime && containsLocationCue) {
    return true;
  }
  return !containsCommand && containsPromptCue && containsLocationCue;
}

bool _containsPromptLocationCue(String line, String? cwd) {
  if (_homeSegmentPattern.hasMatch(line)) {
    return true;
  }
  final trimmedCwd = cwd?.trim();
  if (trimmedCwd == null || trimmedCwd.isEmpty) {
    return false;
  }
  if (line.contains(trimmedCwd)) {
    return true;
  }
  final leaf = _lastPathComponent(trimmedCwd);
  return leaf != null && leaf.length > 1 && line.contains(leaf);
}

String _normalizePromptDetectionText(String text) {
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String? _lastPathComponent(String path) {
  final parts = path
      .split('/')
      .where((part) => part.trim().isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) {
    return null;
  }
  return parts.last;
}

String _durationLabel(
  ShellCommandBlock block,
  Map<int, terminal.TerminalRow> rowsByIndex,
) {
  final range = block.outputRange;
  DateTime? startedAt;
  DateTime? finishedAt;
  for (var row = range.commandRow; row <= range.outputEndRow; row += 1) {
    final modifiedAt = rowsByIndex[row]?.modifiedAt;
    if (modifiedAt == null) {
      continue;
    }
    if (startedAt == null || modifiedAt.isBefore(startedAt)) {
      startedAt = modifiedAt;
    }
    if (finishedAt == null || modifiedAt.isAfter(finishedAt)) {
      finishedAt = modifiedAt;
    }
  }
  if (startedAt == null || finishedAt == null) {
    return '--';
  }
  return _formatDuration(finishedAt.difference(startedAt));
}

String _formatDuration(Duration duration) {
  if (duration.isNegative) {
    return '--';
  }
  if (duration.inMilliseconds < 1000) {
    return '${duration.inMilliseconds}ms';
  }
  if (duration.inSeconds < 10) {
    return '${(duration.inMilliseconds / 1000).toStringAsFixed(1)}s';
  }
  if (duration.inMinutes < 1) {
    return '${duration.inSeconds}s';
  }
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  return seconds == 0 ? '${minutes}m' : '${minutes}m ${seconds}s';
}
