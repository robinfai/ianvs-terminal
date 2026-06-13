import 'dart:math';

import '../productivity/command_blocks_history_feature_flags.dart';
import '../productivity/shell_productivity_models.dart';
import '../terminal/terminal.dart' as terminal;

const int shellCommandBlockStackVisibleLimit = 5;
const int shellCommandBlockOutputPreviewLineLimit = 3;

final RegExp _promptTimePattern = RegExp(r'\b\d{1,2}:\d{2}\b');
final RegExp _homeSegmentPattern = RegExp(r'(^|\s)~(\s|$)');
final RegExp _promptCuePattern = RegExp(
  '(^|\\s)(?:[\\\$#>%]|\\u2192|\\u279c)(\\s|\$)',
);
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
    this.inputLine = '',
    this.terminalRows = const <terminal.TerminalRow>[],
    this.terminalViewportCols = 0,
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
  final String inputLine;
  final List<terminal.TerminalRow> terminalRows;
  final int terminalViewportCols;
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

  bool get outputUsesLiveTerminal => status == ShellCommandBlockStatus.running;
}

class ShellCommandBlockViewModelBuilder {
  const ShellCommandBlockViewModelBuilder._();

  static ShellCommandBlocksOverlayViewModel build({
    required List<ShellCommandBlock> blocks,
    required int viewportStartRow,
    required int viewportEndRow,
    required CommandBlocksHistoryFeatureFlags flags,
    List<terminal.TerminalRow> visibleRows = const <terminal.TerminalRow>[],
    Map<String, List<terminal.TerminalRow>> capturedRowsByBlockId =
        const <String, List<terminal.TerminalRow>>{},
    int viewportCols = 0,
    String? activeBlockId,
    int visibleLimit = shellCommandBlockStackVisibleLimit,
  }) {
    // viewportEndRow is inclusive.
    if (viewportEndRow < viewportStartRow ||
        !flags.enabled ||
        !flags.commandBlocks) {
      return const ShellCommandBlocksOverlayViewModel();
    }
    final rowsByIndex = _rowsByCommandBlockIndex(
      visibleRows,
      viewportStartRow: viewportStartRow,
      viewportEndRow: viewportEndRow,
    );
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
      final capturedRows =
          capturedRowsByBlockId[block.id] ?? const <terminal.TerminalRow>[];
      final preferCapturedRows = capturedRows.isNotEmpty;
      final terminalRows = _terminalRows(
        block,
        rowsByIndex,
        fallbackRows: capturedRows,
        preferFallbackRows: preferCapturedRows,
      );
      visible.add(
        ShellCommandBlockOverlayItem(
          id: block.id,
          command: block.command,
          inputLine: _inputLine(block, rowsByIndex),
          terminalRows: terminalRows,
          terminalViewportCols: _terminalViewportCols(
            viewportCols,
            terminalRows.isNotEmpty ? terminalRows : visibleRows,
          ),
          rowOffset: max(0, visibleStart - viewportStartRow),
          rowSpan: max(1, visibleEnd - visibleStart + 1),
          status: block.status,
          statusLabel: _statusLabel(block),
          active: block.id == activeBlockId,
          cwd: block.cwd,
          durationLabel: _durationLabel(block, rowsByIndex),
          outputPreview: _outputPreview(
            block,
            rowsByIndex,
            fallbackRows: capturedRows,
            preferFallbackRows: preferCapturedRows,
          ),
          outputRangeLabel: _outputRangeLabel(block, terminalRows),
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

Map<int, terminal.TerminalRow> _rowsByCommandBlockIndex(
  List<terminal.TerminalRow> rows, {
  required int viewportStartRow,
  required int viewportEndRow,
}) {
  final byIndex = <int, terminal.TerminalRow>{};
  final viewportRows = viewportEndRow - viewportStartRow + 1;
  for (final row in rows) {
    if (viewportStartRow >= 0) {
      if (row.index >= 0 && row.index < viewportRows) {
        byIndex[viewportStartRow + row.index] = row;
      }
      if (row.index >= viewportStartRow && row.index <= viewportEndRow) {
        byIndex.putIfAbsent(row.index, () => row);
      }
    } else {
      byIndex[row.index] = row;
    }
  }
  return byIndex;
}

List<terminal.TerminalRow> _terminalRows(
  ShellCommandBlock block,
  Map<int, terminal.TerminalRow> rowsByIndex, {
  List<terminal.TerminalRow> fallbackRows = const <terminal.TerminalRow>[],
  bool preferFallbackRows = false,
}) {
  return _terminalRowsForRange(
    block,
    rowsByIndex,
    fallbackRows: fallbackRows,
    preferFallbackRows: preferFallbackRows,
  );
}

List<terminal.TerminalRow> _terminalRowsForRange(
  ShellCommandBlock block,
  Map<int, terminal.TerminalRow> rowsByIndex, {
  List<terminal.TerminalRow> fallbackRows = const <terminal.TerminalRow>[],
  bool preferFallbackRows = false,
}) {
  if (preferFallbackRows && fallbackRows.isNotEmpty) {
    final fallback = shellCommandBlockOutputRowsFrom(block, fallbackRows);
    if (_terminalRowsHaveVisibleText(fallback)) {
      return fallback;
    }
  }
  final rows = shellCommandBlockOutputRowsFrom(
    block,
    _sourceRowsForRange(block.outputRange, rowsByIndex),
  );
  if (!_terminalRowsHaveVisibleText(rows) && fallbackRows.isNotEmpty) {
    final fallback = shellCommandBlockOutputRowsFrom(block, fallbackRows);
    if (_terminalRowsHaveVisibleText(fallback) || rows.isEmpty) {
      return fallback;
    }
  }
  return rows;
}

Iterable<terminal.TerminalRow> _sourceRowsForRange(
  ShellCommandBlockRange range,
  Map<int, terminal.TerminalRow> rowsByIndex,
) sync* {
  for (var row = range.outputStartRow; row <= range.outputEndRow; row += 1) {
    final source = rowsByIndex[row];
    if (source == null) {
      continue;
    }
    yield source;
  }
}

class ShellCommandBlockOutputCapture {
  const ShellCommandBlockOutputCapture({
    required this.rows,
    required this.reachedPromptBoundary,
  });

  final List<terminal.TerminalRow> rows;
  final bool reachedPromptBoundary;
}

List<terminal.TerminalRow> shellCommandBlockOutputRowsFrom(
  ShellCommandBlock block,
  Iterable<terminal.TerminalRow> sourceRows,
) {
  return shellCommandBlockOutputCaptureFrom(block, sourceRows).rows;
}

ShellCommandBlockOutputCapture shellCommandBlockOutputCaptureFrom(
  ShellCommandBlock block,
  Iterable<terminal.TerminalRow> sourceRows,
) {
  final sourceList = sourceRows.toList(growable: false);
  final rows = <terminal.TerminalRow>[];
  var skippedLeadingPrompt = false;
  var reachedPromptBoundary = false;
  for (var sourceIndex = 0; sourceIndex < sourceList.length; sourceIndex += 1) {
    final source = sourceList[sourceIndex];
    final text = source.text.trimRight();
    if (rows.isEmpty &&
        sourceIndex < sourceList.length - 1 &&
        _looksLikeWrappedCommandContinuation(text, block)) {
      skippedLeadingPrompt = true;
      continue;
    }
    if (_looksLikePromptOrReadlineLine(text, block)) {
      if (rows.isEmpty && !skippedLeadingPrompt) {
        skippedLeadingPrompt = true;
        continue;
      }
      reachedPromptBoundary = true;
      break;
    }
    rows.add(
      terminal.TerminalRow(
        index: rows.length,
        text: source.text,
        wrapped: source.wrapped,
        modifiedAt: source.modifiedAt,
        styleRuns: source.styleRuns,
      ),
    );
  }
  return ShellCommandBlockOutputCapture(
    rows: List<terminal.TerminalRow>.unmodifiable(_trimTrailingBlankRows(rows)),
    reachedPromptBoundary: reachedPromptBoundary,
  );
}

bool _looksLikeWrappedCommandContinuation(
  String text,
  ShellCommandBlock block,
) {
  if (text.isEmpty || text == text.trimLeft()) {
    return false;
  }
  final command = _normalizePromptDetectionText(block.command);
  final line = _normalizePromptDetectionText(text);
  if (command.isEmpty || line.isEmpty) {
    return false;
  }
  final commandParts = command.split(' ');
  if (commandParts.length < 2) {
    return false;
  }
  for (var index = 1; index < commandParts.length; index += 1) {
    if (line == commandParts.sublist(index).join(' ')) {
      return true;
    }
  }
  return false;
}

List<terminal.TerminalRow> _trimTrailingBlankRows(
  List<terminal.TerminalRow> rows,
) {
  var end = rows.length;
  while (end > 0 && rows[end - 1].text.trim().isEmpty) {
    end -= 1;
  }
  return rows.sublist(0, end);
}

bool _terminalRowsHaveVisibleText(List<terminal.TerminalRow> rows) {
  return rows.any((row) => row.text.trim().isNotEmpty);
}

int _terminalViewportCols(int viewportCols, List<terminal.TerminalRow> rows) {
  if (viewportCols > 0) {
    return viewportCols;
  }
  var widest = 1;
  for (final row in rows) {
    widest = max(
      widest,
      terminal.TerminalTextCells.fromText(row.text).cellCount,
    );
  }
  return widest;
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

String _outputRangeLabel(
  ShellCommandBlock block,
  List<terminal.TerminalRow> terminalRows,
) {
  if (terminalRows.isNotEmpty) {
    final count = terminalRows.length;
    return count == 1 ? '1 row' : '$count rows';
  }
  final range = block.outputRange;
  return range.outputStartRow == range.outputEndRow
      ? 'row ${range.outputStartRow}'
      : 'rows ${range.outputStartRow}-${range.outputEndRow}';
}

String _outputPreview(
  ShellCommandBlock block,
  Map<int, terminal.TerminalRow> rowsByIndex, {
  List<terminal.TerminalRow> fallbackRows = const <terminal.TerminalRow>[],
  bool preferFallbackRows = false,
}) {
  final lines = <String>[];
  if (preferFallbackRows && fallbackRows.isNotEmpty) {
    _addOutputPreviewLinesFromRows(block, fallbackRows, lines);
    if (lines.isNotEmpty) {
      return lines.join('\n');
    }
  }
  final range = block.outputRange;
  for (var row = range.outputStartRow; row <= range.outputEndRow; row += 1) {
    final text = rowsByIndex[row]?.text.trimRight();
    if (text == null || text.trim().isEmpty) {
      continue;
    }
    if (!_addOutputPreviewLine(block, text, lines)) {
      break;
    }
    if (lines.length == shellCommandBlockOutputPreviewLineLimit) break;
  }
  if (lines.isEmpty && fallbackRows.isNotEmpty) {
    _addOutputPreviewLinesFromRows(block, fallbackRows, lines);
  }
  return lines.join('\n');
}

void _addOutputPreviewLinesFromRows(
  ShellCommandBlock block,
  Iterable<terminal.TerminalRow> rows,
  List<String> lines,
) {
  for (final row in rows) {
    final text = row.text.trimRight();
    if (text.trim().isEmpty) {
      continue;
    }
    if (!_addOutputPreviewLine(block, text, lines)) {
      break;
    }
    if (lines.length == shellCommandBlockOutputPreviewLineLimit) {
      break;
    }
  }
}

bool _addOutputPreviewLine(
  ShellCommandBlock block,
  String text,
  List<String> lines,
) {
  if (_looksLikePromptOrReadlineLine(text, block)) {
    return lines.isEmpty;
  }
  lines.add(text);
  return true;
}

String _inputLine(
  ShellCommandBlock block,
  Map<int, terminal.TerminalRow> rowsByIndex,
) {
  final command = block.command.trim();
  final rawInputLine = rowsByIndex[block.outputRange.commandRow]?.text
      .trimRight();
  if (rawInputLine != null && rawInputLine.trim().isNotEmpty) {
    if (_looksLikePromptOrReadlineLine(rawInputLine, block)) {
      return command;
    }
    final normalizedInputLine = _normalizePromptDetectionText(rawInputLine);
    if (command.isEmpty || normalizedInputLine.contains(command)) {
      return rawInputLine;
    }
  }
  return command;
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
  final containsStrongLocationCue = _containsStrongPromptLocationCue(
    line,
    block.cwd,
  );

  if (containsCommand && (containsPromptCue || containsStrongLocationCue)) {
    return true;
  }
  if (!containsCommand && containsPromptTime && containsStrongLocationCue) {
    return true;
  }
  return !containsCommand && containsPromptCue && containsLocationCue;
}

bool _containsStrongPromptLocationCue(String line, String? cwd) {
  if (_homeSegmentPattern.hasMatch(line)) {
    return true;
  }
  final trimmedCwd = cwd?.trim();
  return trimmedCwd != null &&
      trimmedCwd.isNotEmpty &&
      line.contains(trimmedCwd);
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
