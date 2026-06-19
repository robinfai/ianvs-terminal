part of 'shell_screen.dart';

final RegExp _shellHookPromptTimePattern = RegExp(r'\b\d{1,2}:\d{2}\b');
final RegExp _shellHookPromptHomePattern = RegExp(r'(^|\s)~(\s|$)');
final RegExp _shellHookPromptCuePattern = RegExp(
  r'(^|\s)(?:[$#>%]|->|=>|\u2192|\u279c|\u276f)(\s|$)',
);
final RegExp _shellHookPromptNoisePattern = RegExp(r'(?:\?{2,}|\uFFFD)');

int? shellCommandBlockVisibleViewportEndRow({
  required int viewportStartRow,
  required int viewportRows,
}) {
  if (viewportStartRow < 0 || viewportRows <= 0) {
    return null;
  }
  return viewportStartRow + viewportRows - 1;
}

int? shellCommandBlockCommandEndRowForFrame(terminal.TerminalFrameDiff frame) {
  if (frame.viewportStartRow < 0 || frame.cursor.row < 0) {
    return null;
  }
  final cursorRow = frame.viewportStartRow + frame.cursor.row;
  if (frame.cursor.col > 0) {
    return cursorRow;
  }
  return cursorRow - 1;
}

int? shellCommandBlockPromptRowForFrame(terminal.TerminalFrameDiff frame) {
  if (frame.viewportStartRow < 0 || frame.cursor.row < 0) {
    return null;
  }
  return frame.viewportStartRow + frame.cursor.row;
}

int? shellCommandBlockCommandStartRowForFrame(
  terminal.TerminalFrameDiff frame, {
  String? command,
}) {
  if (frame.viewportStartRow < 0 || frame.rows.isEmpty) {
    return null;
  }
  final commandRow = _shellCommandBlockCommandRowForFrame(frame, command);
  if (commandRow != null) {
    return frame.viewportStartRow + commandRow.index;
  }
  final anchorRow = _shellCommandBlockAnchorRowForFrame(frame);
  if (anchorRow == null) {
    return null;
  }
  return frame.viewportStartRow + anchorRow.index;
}

terminal.TerminalRow? _shellCommandBlockCommandRowForFrame(
  terminal.TerminalFrameDiff frame,
  String? command,
) {
  final normalizedCommand = _normalizedShellCommandText(command);
  if (normalizedCommand == null) {
    return null;
  }
  for (final logicalRow in _shellCommandBlockLogicalRows(frame.rows).reversed) {
    if (_logicalRowLooksLikeShellCommandLine(logicalRow, normalizedCommand)) {
      return logicalRow.endRow;
    }
  }
  return null;
}

bool _logicalRowLooksLikeShellCommandLine(
  _LogicalTerminalRow logicalRow,
  String normalizedCommand,
) {
  final line = logicalRow.text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (line.isEmpty || !line.contains(normalizedCommand)) {
    return false;
  }
  if (line == normalizedCommand || line.endsWith(' $normalizedCommand')) {
    return true;
  }
  return _shellHookPromptCuePattern.hasMatch(line) ||
      _shellHookPromptNoisePattern.hasMatch(line);
}

String? _normalizedShellCommandText(String? command) {
  final text = command?.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text == null || text.isEmpty ? null : text;
}

terminal.TerminalRow? _shellCommandBlockAnchorRowForFrame(
  terminal.TerminalFrameDiff frame,
) {
  final rowAtCursor = _shellCommandBlockRowAtCursor(frame);
  if (rowAtCursor != null && rowAtCursor.text.trimRight().isNotEmpty) {
    return rowAtCursor;
  }
  for (final logicalRow in _shellCommandBlockLogicalRows(frame.rows).reversed) {
    if (logicalRow.text.trimRight().isEmpty) {
      continue;
    }
    return logicalRow.endRow;
  }
  return null;
}

terminal.TerminalRow? _shellCommandBlockRowAtCursor(
  terminal.TerminalFrameDiff frame,
) {
  for (final row in frame.rows) {
    if (row.index == frame.cursor.row) {
      return row;
    }
  }
  if (frame.cursor.row >= 0 && frame.cursor.row < frame.rows.length) {
    return frame.rows[frame.cursor.row];
  }
  return null;
}

List<_LogicalTerminalRow> _shellCommandBlockLogicalRows(
  List<terminal.TerminalRow> rows,
) {
  final logicalRows = <_LogicalTerminalRow>[];
  var start = 0;
  while (start < rows.length) {
    final buffer = StringBuffer(rows[start].text);
    var end = start;
    while (end < rows.length - 1 && rows[end].wrapped) {
      end += 1;
      buffer.write(rows[end].text);
    }
    logicalRows.add(
      _LogicalTerminalRow(
        startRow: rows[start],
        endRow: rows[end],
        text: buffer.toString(),
      ),
    );
    start = end + 1;
  }
  return logicalRows;
}

class ShellCommandBlockShellHookReducer {
  const ShellCommandBlockShellHookReducer._();

  static bool supportsHook(String? hook) {
    return switch (normalizeHook(hook)) {
      'bootstrapped' ||
      'precmd' ||
      'prompt_started' ||
      'precmd.pwd' ||
      'cwd' ||
      'preexec' ||
      'command_finished' => true,
      _ => false,
    };
  }

  static String? normalizeHook(String? hook) {
    final text = hook?.trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    final normalized = text.replaceAll('-', '_').toLowerCase();
    return switch (normalized) {
      'bootstrapped' => 'bootstrapped',
      'precmd' || 'prompt_started' || 'promptstarted' => 'precmd',
      'precmd.pwd' || 'precmdpwd' => 'precmd.pwd',
      'cwd' || 'pwd' => 'cwd',
      'preexec' => 'preexec',
      'commandfinished' || 'command_finished' => 'command_finished',
      _ => text,
    };
  }

  static ShellCommandBlockSnapshot reduce({
    required ShellCommandBlockSnapshot snapshot,
    required CommandBlocksHistoryFeatureFlags flags,
    required String sessionId,
    required String? hook,
    String? command,
    String? cwd,
    int? exitCode,
    int? promptScrollbackOffset,
    int? commandStartRow,
    List<TerminalShellPromptMark> promptMarks =
        const <TerminalShellPromptMark>[],
    int? viewportEndRow,
    DateTime? occurredAt,
  }) {
    if (!flags.enabled || !flags.commandBlocks) {
      return const ShellCommandBlockSnapshot();
    }
    final eventAt = occurredAt ?? DateTime.now();
    return switch (normalizeHook(hook)) {
      'bootstrapped' => _bootstrapped(snapshot),
      'precmd' => _precmd(
        snapshot: snapshot,
        flags: flags,
        sessionId: sessionId,
        cwd: cwd,
        promptScrollbackOffset: promptScrollbackOffset,
        promptMarks: promptMarks,
      ),
      'precmd.pwd' ||
      'cwd' => _cwdChanged(snapshot: snapshot, flags: flags, cwd: cwd),
      'preexec' => _preexec(
        snapshot: snapshot,
        flags: flags,
        sessionId: sessionId,
        command: command,
        cwd: cwd,
        promptScrollbackOffset: promptScrollbackOffset,
        commandStartRow: commandStartRow,
        promptMarks: promptMarks,
        occurredAt: eventAt,
      ),
      'command_finished' => _commandFinished(
        snapshot: snapshot,
        flags: flags,
        sessionId: sessionId,
        command: command,
        cwd: cwd,
        exitCode: exitCode,
        promptScrollbackOffset: promptScrollbackOffset,
        promptMarks: promptMarks,
        viewportEndRow: viewportEndRow,
        occurredAt: eventAt,
      ),
      _ => snapshot,
    };
  }

  static ShellCommandBlockSnapshot _bootstrapped(
    ShellCommandBlockSnapshot snapshot,
  ) {
    if (snapshot.lastPrompt == null && snapshot.pendingRange == null) {
      return snapshot;
    }
    return ShellCommandBlockSnapshot.withBlocks(
      blocks: snapshot.blocks,
      currentCwd: snapshot.currentCwd,
    );
  }

  static ShellCommandBlockSnapshot _cwdChanged({
    required ShellCommandBlockSnapshot snapshot,
    required CommandBlocksHistoryFeatureFlags flags,
    required String? cwd,
  }) {
    final currentCwd = _trimmedShellHookText(cwd);
    if (currentCwd == null) {
      return snapshot;
    }
    if (snapshot.currentCwd == currentCwd) {
      return snapshot;
    }
    return ShellCommandBlockController.reduce(
      snapshot,
      ShellCwdChangedEvent(currentCwd),
      flags: flags,
    );
  }

  static ShellCommandBlockSnapshot _precmd({
    required ShellCommandBlockSnapshot snapshot,
    required CommandBlocksHistoryFeatureFlags flags,
    required String sessionId,
    required String? cwd,
    required int? promptScrollbackOffset,
    required List<TerminalShellPromptMark> promptMarks,
  }) {
    final promptRow = _validShellHookRow(promptScrollbackOffset);
    if (promptRow == null) {
      return snapshot;
    }
    final promptMark = _promptMarkAt(_validPromptMarks(promptMarks), promptRow);
    final promptCwd =
        _trimmedShellHookText(cwd) ?? _trimmedShellHookText(promptMark?.cwd);
    final resized = _resizeLastFinishedBlockBeforePrompt(
      snapshot: snapshot,
      sessionId: sessionId,
      nextCommandStartRow: promptRow,
    );
    if (resized.lastPrompt?.row == promptRow &&
        (promptCwd == null || resized.lastPrompt?.cwd == promptCwd)) {
      return resized;
    }
    return ShellCommandBlockController.reduce(
      resized,
      ShellPromptMarkEvent(
        id: _promptMarkId(sessionId, promptRow),
        row: promptRow,
        cwd: promptCwd,
      ),
      flags: flags,
    );
  }

  static ShellCommandBlockSnapshot _preexec({
    required ShellCommandBlockSnapshot snapshot,
    required CommandBlocksHistoryFeatureFlags flags,
    required String sessionId,
    required String? command,
    required String? cwd,
    required int? promptScrollbackOffset,
    required int? commandStartRow,
    required List<TerminalShellPromptMark> promptMarks,
    required DateTime occurredAt,
  }) {
    final commandText = _trimmedShellCommandText(command);
    if (commandText == null) {
      return snapshot;
    }
    final marks = _validPromptMarks(promptMarks);
    final promptMark = _lastPromptMark(marks);
    final startRow =
        _validShellHookRow(promptScrollbackOffset) ??
        _validShellHookRow(commandStartRow);
    if (startRow == null) {
      return snapshot;
    }
    final baseSnapshot = _resizeLastFinishedBlockBeforePrompt(
      snapshot: snapshot,
      sessionId: sessionId,
      nextCommandStartRow: startRow,
    );
    final commandCwd =
        _trimmedShellHookText(cwd) ?? _trimmedShellHookText(promptMark?.cwd);
    final promptSnapshot = ShellCommandBlockController.reduce(
      baseSnapshot,
      ShellPromptMarkEvent(
        id: _promptMarkId(sessionId, startRow),
        row: startRow,
        cwd: commandCwd,
      ),
      flags: flags,
    );
    return ShellCommandBlockController.reduce(
      promptSnapshot,
      ShellCommandStartedEvent(
        commandId: _commandBlockId(sessionId, startRow),
        command: commandText,
        commandRow: startRow,
        cwd: commandCwd,
        startedAt: occurredAt,
      ),
      flags: flags,
    );
  }

  static ShellCommandBlockSnapshot _resizeLastFinishedBlockBeforePrompt({
    required ShellCommandBlockSnapshot snapshot,
    required String sessionId,
    required int nextCommandStartRow,
  }) {
    if (snapshot.blocks.isEmpty) {
      return snapshot;
    }
    final lastBlock = snapshot.blocks.last;
    if (!lastBlock.isValid ||
        lastBlock.status == ShellCommandBlockStatus.running ||
        nextCommandStartRow <= lastBlock.outputRange.commandRow) {
      return snapshot;
    }
    final outputEndRow = math.max(
      lastBlock.outputRange.outputStartRow,
      nextCommandStartRow - 1,
    );
    if (outputEndRow == lastBlock.outputRange.outputEndRow) {
      return snapshot;
    }
    final outputRange = ShellCommandBlockRange(
      commandRow: lastBlock.outputRange.commandRow,
      outputStartRow: lastBlock.outputRange.outputStartRow,
      outputEndRow: outputEndRow,
    );
    final commandBlockId = _commandBlockId(sessionId, outputRange.commandRow);
    final failureSnapshot = lastBlock.failureSnapshot == null
        ? null
        : ShellFailureSnapshot.withKeyErrorLines(
            commandBlockId: commandBlockId,
            command: lastBlock.command,
            cwd: lastBlock.cwd,
            exitCode: lastBlock.exitCode,
            outputRange: outputRange,
            keyErrorLines: lastBlock.failureSnapshot!.keyErrorLines,
          );
    final resizedBlock = lastBlock.copyWith(
      id: commandBlockId,
      outputRange: outputRange,
      failureSnapshot: failureSnapshot,
    );
    return ShellCommandBlockSnapshot.withBlocks(
      blocks: [
        ...snapshot.blocks.take(snapshot.blocks.length - 1),
        resizedBlock,
      ],
      lastPrompt: snapshot.lastPrompt,
      pendingRange: snapshot.pendingRange,
      currentCwd: snapshot.currentCwd,
    );
  }

  static ShellCommandBlockSnapshot _commandFinished({
    required ShellCommandBlockSnapshot snapshot,
    required CommandBlocksHistoryFeatureFlags flags,
    required String sessionId,
    required String? command,
    required String? cwd,
    required int? exitCode,
    required int? promptScrollbackOffset,
    required List<TerminalShellPromptMark> promptMarks,
    required int? viewportEndRow,
    required DateTime occurredAt,
  }) {
    final commandText = _trimmedShellCommandText(command);
    if (commandText == null) {
      return snapshot;
    }

    final plan = _finishPlan(
      snapshot: snapshot,
      promptMarks: promptMarks,
      promptScrollbackOffset: promptScrollbackOffset,
      viewportEndRow: viewportEndRow,
      commandText: commandText,
    );
    if (plan == null) {
      return snapshot;
    }

    final commandId = _commandBlockId(sessionId, plan.startRow);
    var next = _resizeLastFinishedBlockBeforePrompt(
      snapshot: snapshot,
      sessionId: sessionId,
      nextCommandStartRow: plan.startRow,
    );
    if (next.lastPrompt?.row != plan.startRow) {
      next = ShellCommandBlockController.reduce(
        next,
        ShellPromptMarkEvent(
          id: _promptMarkId(sessionId, plan.startRow),
          row: plan.startRow,
          cwd: plan.startCwd,
        ),
        flags: flags,
      );
    }
    next = ShellCommandBlockController.reduce(
      next,
      ShellCommandOutputRangeEvent(
        commandId: commandId,
        startRow: plan.startRow + 1,
        endRow: plan.outputEndRow,
      ),
      flags: flags,
    );
    next = ShellCommandBlockController.reduce(
      next,
      ShellCommandFinishedEvent(
        command: commandText,
        cwd: _trimmedShellHookText(cwd),
        exitCode: exitCode,
        finishedAt: occurredAt,
      ),
      flags: flags,
    );
    return _recordEndPromptIfNeeded(
      snapshot: next,
      flags: flags,
      sessionId: sessionId,
      endPromptRow: plan.endPromptRow,
      endCwd: plan.endCwd,
    );
  }

  static ShellCommandBlockSnapshot _recordEndPromptIfNeeded({
    required ShellCommandBlockSnapshot snapshot,
    required CommandBlocksHistoryFeatureFlags flags,
    required String sessionId,
    required int? endPromptRow,
    required String? endCwd,
  }) {
    if (endPromptRow != null) {
      if (snapshot.lastPrompt?.row == endPromptRow) {
        return snapshot;
      }
      return ShellCommandBlockController.reduce(
        snapshot,
        ShellPromptMarkEvent(
          id: _promptMarkId(sessionId, endPromptRow),
          row: endPromptRow,
          cwd: endCwd,
        ),
        flags: flags,
      );
    }
    return _clearPendingPrompt(snapshot);
  }

  static ShellCommandBlockSnapshot _clearPendingPrompt(
    ShellCommandBlockSnapshot snapshot,
  ) {
    if (snapshot.lastPrompt == null && snapshot.pendingRange == null) {
      return snapshot;
    }
    return ShellCommandBlockSnapshot.withBlocks(
      blocks: snapshot.blocks,
      currentCwd: snapshot.currentCwd,
    );
  }

  static _ShellCommandBlockFinishPlan? _finishPlan({
    required ShellCommandBlockSnapshot snapshot,
    required List<TerminalShellPromptMark> promptMarks,
    required int? promptScrollbackOffset,
    required int? viewportEndRow,
    required String commandText,
  }) {
    final marks = _validPromptMarks(promptMarks);
    final explicitEndRow = _validShellHookRow(promptScrollbackOffset);
    final viewportEnd = _validShellHookRow(viewportEndRow);
    final snapshotStart = snapshot.lastPrompt;

    if (snapshotStart != null && snapshotStart.row >= 0) {
      if (explicitEndRow != null && explicitEndRow <= snapshotStart.row) {
        return null;
      }
      final matchingEndMark = _nextPromptMarkAfter(marks, snapshotStart.row);
      final endPromptRow =
          explicitEndRow != null && explicitEndRow > snapshotStart.row
          ? explicitEndRow
          : matchingEndMark?.scrollbackOffset;
      return _finishPlanIfValid(
        startRow: snapshotStart.row,
        startCwd: snapshotStart.cwd,
        outputEndRow: endPromptRow == null
            ? _fallbackOutputEndRow(viewportEnd, snapshotStart.row)
            : endPromptRow - 1,
        endPromptRow: endPromptRow,
        endCwd: matchingEndMark?.cwd,
      );
    }

    if (explicitEndRow != null) {
      final startMark = _lastPromptMarkBefore(
        marks,
        explicitEndRow,
        commandText: commandText,
      );
      if (startMark != null) {
        return _finishPlanIfValid(
          startRow: startMark.scrollbackOffset,
          startCwd: startMark.cwd,
          outputEndRow: explicitEndRow - 1,
          endPromptRow: explicitEndRow,
          endCwd: null,
        );
      }
    }

    return null;
  }

  static int? _fallbackOutputEndRow(int? viewportEndRow, int startRow) {
    if (viewportEndRow == null) {
      return null;
    }
    return math.max(viewportEndRow, startRow + 1);
  }

  static _ShellCommandBlockFinishPlan? _finishPlanIfValid({
    required int startRow,
    required String? startCwd,
    required int? outputEndRow,
    int? endPromptRow,
    String? endCwd,
  }) {
    if (startRow < 0 || outputEndRow == null || outputEndRow < startRow + 1) {
      return null;
    }
    return _ShellCommandBlockFinishPlan(
      startRow: startRow,
      startCwd: startCwd,
      outputEndRow: outputEndRow,
      endPromptRow: endPromptRow,
      endCwd: endCwd,
    );
  }

  static List<TerminalShellPromptMark> _validPromptMarks(
    List<TerminalShellPromptMark> promptMarks,
  ) {
    final marks = promptMarks
        .where((mark) => mark.scrollbackOffset >= 0)
        .toList(growable: false);
    marks.sort((a, b) => a.scrollbackOffset.compareTo(b.scrollbackOffset));
    return marks;
  }

  static TerminalShellPromptMark? _lastPromptMark(
    List<TerminalShellPromptMark> marks,
  ) {
    return marks.isEmpty ? null : marks.last;
  }

  static TerminalShellPromptMark? _promptMarkAt(
    List<TerminalShellPromptMark> marks,
    int row,
  ) {
    for (final mark in marks) {
      if (mark.scrollbackOffset == row) {
        return mark;
      }
    }
    return null;
  }

  static TerminalShellPromptMark? _lastPromptMarkBefore(
    List<TerminalShellPromptMark> marks,
    int row, {
    required String commandText,
  }) {
    for (final mark in marks.reversed) {
      if (mark.scrollbackOffset < row &&
          _trimmedShellCommandText(mark.command) == commandText) {
        return mark;
      }
    }
    return null;
  }

  static TerminalShellPromptMark? _nextPromptMarkAfter(
    List<TerminalShellPromptMark> marks,
    int row,
  ) {
    for (final mark in marks) {
      if (mark.scrollbackOffset > row) {
        return mark;
      }
    }
    return null;
  }

  static int? _validShellHookRow(int? value) {
    if (value == null || value < 0) {
      return null;
    }
    return value;
  }

  static String _commandBlockId(String sessionId, int commandRow) {
    return '$sessionId:command:$commandRow';
  }

  static String _promptMarkId(String sessionId, int row) {
    return '$sessionId:prompt:$row';
  }

  static String? _trimmedShellHookText(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }

  static String? _trimmedShellCommandText(String? value) {
    final text = _trimmedShellHookText(value);
    if (text == null || _shellHookCommandLooksLikePromptLine(text)) {
      return null;
    }
    return text;
  }

  static bool _shellHookCommandLooksLikePromptLine(String text) {
    final line = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (!_shellHookPromptTimePattern.hasMatch(line) ||
        !_shellHookPromptHomePattern.hasMatch(line)) {
      return false;
    }
    return _shellHookPromptCuePattern.hasMatch(line) ||
        _shellHookPromptNoisePattern.hasMatch(line);
  }
}

ShellCommandBlockSnapshot shellCommandBlockSnapshotAfterScrollbackClear(
  ShellCommandBlockSnapshot snapshot,
) {
  if (!_commandBlockSnapshotHasState(snapshot)) {
    return snapshot;
  }
  return const ShellCommandBlockSnapshot();
}

bool _commandBlockSnapshotHasState(ShellCommandBlockSnapshot snapshot) {
  return snapshot.blocks.isNotEmpty ||
      snapshot.lastPrompt != null ||
      snapshot.pendingRange != null ||
      snapshot.currentCwd != null;
}

Map<String, List<terminal.TerminalRow>> _commandBlockPreviewRowsForFrame(
  ShellCommandBlockSnapshot snapshot,
  terminal.TerminalFrameDiff frame,
) {
  if (frame.modes.alternateScreen) {
    return const <String, List<terminal.TerminalRow>>{};
  }
  final rowsByIndex = _terminalRowsByScrollbackIndex(frame);
  final capturedRows = <String, List<terminal.TerminalRow>>{};
  final latestBlock = snapshot.blocks.isEmpty ? null : snapshot.blocks.last;
  if (latestBlock == null) {
    return capturedRows;
  }
  final blocks = [latestBlock];
  for (var index = 0; index < blocks.length; index += 1) {
    final block = blocks[index];
    final nextCommandStartRow = index < blocks.length - 1
        ? blocks[index + 1].outputRange.commandRow
        : null;
    final rows = _terminalRowsForCommandBlockPreview(
      block,
      frame,
      rowsByIndex,
      nextCommandStartRow: nextCommandStartRow,
    );
    if (rows.isNotEmpty) {
      capturedRows[block.id] = rows;
    }
  }
  return capturedRows;
}

@visibleForTesting
Map<String, List<terminal.TerminalRow>> shellCommandBlockPreviewRowsForFrame({
  required ShellCommandBlockSnapshot snapshot,
  required terminal.TerminalFrameDiff frame,
}) {
  return _commandBlockPreviewRowsForFrame(snapshot, frame);
}

@visibleForTesting
bool shellCommandBlockShouldReplacePreviewRows({
  required List<terminal.TerminalRow>? existingRows,
  required List<terminal.TerminalRow> nextRows,
}) {
  if (nextRows.isEmpty) {
    return false;
  }
  final existing = existingRows;
  if (existing == null) {
    return true;
  }
  if (nextRows.length > existing.length) {
    return true;
  }
  return nextRows.length == existing.length &&
      !shellCommandBlockPreviewRowsHaveSameContent(existing, nextRows);
}

@visibleForTesting
List<terminal.TerminalRow> shellCommandBlockMergedPreviewRows({
  required List<terminal.TerminalRow>? existingRows,
  required List<terminal.TerminalRow> nextRows,
}) {
  if (nextRows.isEmpty) {
    return existingRows == null
        ? const <terminal.TerminalRow>[]
        : List<terminal.TerminalRow>.unmodifiable(existingRows);
  }
  final existing = existingRows;
  final normalizedNext = _renumberTerminalRows(nextRows);
  if (existing == null || existing.isEmpty) {
    return List<terminal.TerminalRow>.unmodifiable(normalizedNext);
  }
  if (shellCommandBlockPreviewRowsHaveSameContent(existing, normalizedNext)) {
    return List<terminal.TerminalRow>.unmodifiable(existing);
  }

  final overlap = _shellCommandBlockPreviewRowOverlap(existing, normalizedNext);
  if (overlap >= normalizedNext.length) {
    return List<terminal.TerminalRow>.unmodifiable(existing);
  }
  if (overlap > 0 ||
      _looksLikeLaterCommandBlockPreviewSlice(existing, normalizedNext)) {
    return List<terminal.TerminalRow>.unmodifiable(
      _renumberTerminalRows([...existing, ...normalizedNext.skip(overlap)]),
    );
  }

  if (shellCommandBlockShouldReplacePreviewRows(
    existingRows: existing,
    nextRows: normalizedNext,
  )) {
    return List<terminal.TerminalRow>.unmodifiable(normalizedNext);
  }
  return List<terminal.TerminalRow>.unmodifiable(existing);
}

@visibleForTesting
bool shellCommandBlockPreviewRowsWouldChange({
  required List<terminal.TerminalRow>? existingRows,
  required List<terminal.TerminalRow> nextRows,
}) {
  if (nextRows.isEmpty) {
    return false;
  }
  final existing = existingRows;
  final mergedRows = shellCommandBlockMergedPreviewRows(
    existingRows: existing,
    nextRows: nextRows,
  );
  return existing == null ||
      !shellCommandBlockPreviewRowsHaveSameContent(existing, mergedRows);
}

int _shellCommandBlockPreviewRowOverlap(
  List<terminal.TerminalRow> existingRows,
  List<terminal.TerminalRow> nextRows,
) {
  final maxOverlap = math.min(existingRows.length, nextRows.length);
  for (var count = maxOverlap; count > 0; count -= 1) {
    if (shellCommandBlockPreviewRowsHaveSameContent(
      existingRows.sublist(existingRows.length - count),
      nextRows.sublist(0, count),
    )) {
      return count;
    }
  }
  return 0;
}

bool _looksLikeLaterCommandBlockPreviewSlice(
  List<terminal.TerminalRow> existingRows,
  List<terminal.TerminalRow> nextRows,
) {
  final existingFinishedAt = _latestTerminalRowModifiedAt(existingRows);
  final nextStartedAt = _earliestTerminalRowModifiedAt(nextRows);
  return existingFinishedAt != null &&
      nextStartedAt != null &&
      nextStartedAt.isAfter(existingFinishedAt);
}

DateTime? _earliestTerminalRowModifiedAt(List<terminal.TerminalRow> rows) {
  DateTime? earliest;
  for (final row in rows) {
    final modifiedAt = row.modifiedAt;
    if (modifiedAt == null) {
      continue;
    }
    if (earliest == null || modifiedAt.isBefore(earliest)) {
      earliest = modifiedAt;
    }
  }
  return earliest;
}

DateTime? _latestTerminalRowModifiedAt(List<terminal.TerminalRow> rows) {
  DateTime? latest;
  for (final row in rows) {
    final modifiedAt = row.modifiedAt;
    if (modifiedAt == null) {
      continue;
    }
    if (latest == null || modifiedAt.isAfter(latest)) {
      latest = modifiedAt;
    }
  }
  return latest;
}

@visibleForTesting
bool shellCommandBlockPreviewRowsHaveSameContent(
  List<terminal.TerminalRow> left,
  List<terminal.TerminalRow> right,
) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    final leftRow = left[index];
    final rightRow = right[index];
    if (leftRow.text != rightRow.text || leftRow.wrapped != rightRow.wrapped) {
      return false;
    }
    if (!_terminalStyleRunsHaveSamePreviewContent(
      leftRow.styleRuns,
      rightRow.styleRuns,
    )) {
      return false;
    }
  }
  return true;
}

class ShellCommandBlockFinishedPreviewCapture {
  const ShellCommandBlockFinishedPreviewCapture({
    required this.rows,
    required this.removeTarget,
  });

  final List<terminal.TerminalRow> rows;
  final bool removeTarget;
}

@visibleForTesting
ShellCommandBlockFinishedPreviewCapture
shellCommandBlockFinishedPreviewCaptureForRows({
  required ShellCommandBlock block,
  required List<terminal.TerminalRow> rows,
  required bool isLatestBlock,
}) {
  if (!isLatestBlock) {
    return const ShellCommandBlockFinishedPreviewCapture(
      rows: <terminal.TerminalRow>[],
      removeTarget: true,
    );
  }
  final capture = shellCommandBlockOutputCaptureFrom(block, rows);
  return ShellCommandBlockFinishedPreviewCapture(
    rows: _shellCommandBlockRowsHaveVisibleText(capture.rows)
        ? capture.rows
        : const <terminal.TerminalRow>[],
    removeTarget: capture.reachedPromptBoundary,
  );
}

@visibleForTesting
Map<String, List<terminal.TerminalRow>>
shellCommandBlockFinishedPreviewRowsForCurrentFrame({
  required ShellCommandBlockSnapshot snapshot,
  required terminal.TerminalFrameDiff frame,
  DateTime? submittedAt,
  int? endPromptRow,
}) {
  if (frame.modes.alternateScreen) {
    return const <String, List<terminal.TerminalRow>>{};
  }
  if (snapshot.blocks.isEmpty) {
    return const <String, List<terminal.TerminalRow>>{};
  }
  final block = snapshot.blocks.last;
  if (!block.isValid) {
    return const <String, List<terminal.TerminalRow>>{};
  }
  final rows = _terminalRowsForFinishedCommandBlockPreview(
    block: block,
    frame: frame,
    submittedAt: submittedAt,
    endPromptRow: endPromptRow,
  );
  final capture = shellCommandBlockFinishedPreviewCaptureForRows(
    block: block,
    rows: rows,
    isLatestBlock: true,
  );
  return capture.rows.isEmpty
      ? const <String, List<terminal.TerminalRow>>{}
      : <String, List<terminal.TerminalRow>>{block.id: capture.rows};
}

bool _shellCommandBlockRowsHaveVisibleText(List<terminal.TerminalRow> rows) {
  return rows.any((row) => row.text.trim().isNotEmpty);
}

@visibleForTesting
List<terminal.TerminalRow> shellCommandBlockSubmittedPreviewRowsForFrame({
  required String command,
  required int commandRow,
  required DateTime submittedAt,
  required terminal.TerminalFrameDiff frame,
}) {
  if (frame.modes.alternateScreen) {
    return const <terminal.TerminalRow>[];
  }
  final rows = _dropLeadingSubmittedCommandRows(
    command: command,
    allowLeadingContinuation: true,
    rows: _terminalRowsForPendingCommandBlockPreview(
      commandRow: commandRow,
      frame: frame,
    ),
  );
  final probeBlock = ShellCommandBlock(
    id: 'submitted-preview',
    command: command,
    outputRange: ShellCommandBlockRange(
      commandRow: commandRow,
      outputStartRow: commandRow + 1,
      outputEndRow: commandRow + rows.length,
    ),
  );
  if (_shellCommandBlockRowsHaveVisibleText(
        shellCommandBlockOutputRowsFrom(probeBlock, rows),
      ) &&
      !_terminalRowsHaveStaleVisibleText(rows, submittedAt)) {
    return rows;
  }
  final freshRows = _terminalRowsModifiedSinceSubmittedCommand(
    command: command,
    commandRow: commandRow,
    submittedAt: submittedAt,
    frame: frame,
  );
  return freshRows.isEmpty ? rows : freshRows;
}

bool _terminalRowsHaveStaleVisibleText(
  List<terminal.TerminalRow> rows,
  DateTime submittedAt,
) {
  for (final row in rows) {
    if (row.text.trim().isEmpty) {
      continue;
    }
    final modifiedAt = row.modifiedAt;
    if (modifiedAt != null && modifiedAt.isBefore(submittedAt)) {
      return true;
    }
  }
  return false;
}

List<terminal.TerminalRow> _freshOrPendingRowsForCommandBlock({
  required String command,
  required int commandRow,
  required DateTime? submittedAt,
  required terminal.TerminalFrameDiff frame,
  int? endPromptRow,
}) {
  final rows = _dropLeadingSubmittedCommandRows(
    command: command,
    allowLeadingContinuation: true,
    rows: _terminalRowsForPendingCommandBlockPreview(
      commandRow: commandRow,
      frame: frame,
      endPromptRow: endPromptRow,
    ),
  );
  if (submittedAt == null ||
      !_terminalRowsHaveStaleVisibleText(rows, submittedAt)) {
    return rows;
  }
  final freshRows = _terminalRowsModifiedSinceSubmittedCommand(
    command: command,
    commandRow: commandRow,
    submittedAt: submittedAt,
    frame: frame,
    endPromptRow: endPromptRow,
  );
  return freshRows.isEmpty ? rows : freshRows;
}

bool _terminalStyleRunsHaveSamePreviewContent(
  List<terminal.TerminalStyleRun> left,
  List<terminal.TerminalStyleRun> right,
) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    final leftRun = left[index];
    final rightRun = right[index];
    if (leftRun.start != rightRun.start ||
        leftRun.end != rightRun.end ||
        leftRun.foreground != rightRun.foreground ||
        leftRun.background != rightRun.background ||
        leftRun.bold != rightRun.bold ||
        leftRun.dim != rightRun.dim ||
        leftRun.italic != rightRun.italic ||
        leftRun.underline != rightRun.underline ||
        leftRun.blink != rightRun.blink ||
        leftRun.inverse != rightRun.inverse) {
      return false;
    }
  }
  return true;
}

Map<int, terminal.TerminalRow> _terminalRowsByScrollbackIndex(
  terminal.TerminalFrameDiff frame,
) {
  final byIndex = <int, terminal.TerminalRow>{};
  for (final row in frame.rows) {
    if (frame.viewportStartRow >= 0) {
      if (row.index >= 0 && row.index < frame.viewportRows) {
        byIndex[frame.viewportStartRow + row.index] = row;
      }
      if (row.index >= frame.viewportStartRow) {
        byIndex.putIfAbsent(row.index, () => row);
      }
    } else {
      byIndex[row.index] = row;
    }
  }
  return byIndex;
}

List<terminal.TerminalRow> _terminalRowsForCommandBlockPreview(
  ShellCommandBlock block,
  terminal.TerminalFrameDiff frame,
  Map<int, terminal.TerminalRow> rowsByIndex, {
  int? nextCommandStartRow,
}) {
  final scannedRows = _terminalRowsAfterCommandLineForCommandBlockPreview(
    block,
    frame,
    nextCommandStartRow: nextCommandStartRow,
  );
  if (scannedRows.isNotEmpty) {
    return scannedRows;
  }
  return _terminalRowsForCommandBlockRangePreview(block, rowsByIndex);
}

List<terminal.TerminalRow> _terminalRowsForCommandBlockRangePreview(
  ShellCommandBlock block,
  Map<int, terminal.TerminalRow> rowsByIndex,
) {
  final range = block.outputRange;
  final sourceRows = <terminal.TerminalRow>[];
  for (var row = range.outputStartRow; row <= range.outputEndRow; row += 1) {
    final source = rowsByIndex[row];
    if (source == null) {
      continue;
    }
    sourceRows.add(source);
  }
  return shellCommandBlockOutputRowsFrom(
    block,
    _dropLeadingSubmittedCommandRows(
      command: block.command,
      allowLeadingContinuation: true,
      rows: sourceRows,
    ),
  );
}

List<terminal.TerminalRow> _terminalRowsAfterCommandLineForCommandBlockPreview(
  ShellCommandBlock block,
  terminal.TerminalFrameDiff frame, {
  int? nextCommandStartRow,
}) {
  final command = block.command.trim();
  if (command.isEmpty || frame.rows.isEmpty || frame.viewportStartRow < 0) {
    return const <terminal.TerminalRow>[];
  }
  final frameRows = [
    for (final row in frame.rows)
      _FrameRow(absoluteRow: frame.viewportStartRow + row.index, row: row),
  ]..sort((a, b) => a.absoluteRow.compareTo(b.absoluteRow));

  final commandRowIndex = _commandLineFrameRowIndex(
    block: block,
    rows: frameRows,
  );
  if (commandRowIndex == null || commandRowIndex >= frameRows.length - 1) {
    return const <terminal.TerminalRow>[];
  }

  final sourceRows = <terminal.TerminalRow>[];
  for (final frameRow in frameRows.skip(commandRowIndex + 1)) {
    if (nextCommandStartRow != null &&
        frameRow.absoluteRow >= nextCommandStartRow) {
      break;
    }
    sourceRows.add(frameRow.row);
  }
  return shellCommandBlockOutputRowsFrom(
    block,
    _dropLeadingSubmittedCommandRows(
      command: block.command,
      allowLeadingContinuation: true,
      rows: sourceRows,
    ),
  );
}

List<terminal.TerminalRow> _terminalRowsForPendingCommandBlockPreview({
  required int commandRow,
  required terminal.TerminalFrameDiff frame,
  int? endPromptRow,
}) {
  if (commandRow < 0 || frame.rows.isEmpty || frame.viewportStartRow < 0) {
    return const <terminal.TerminalRow>[];
  }
  final frameRows = [
    for (final row in frame.rows)
      _FrameRow(absoluteRow: frame.viewportStartRow + row.index, row: row),
  ]..sort((a, b) => a.absoluteRow.compareTo(b.absoluteRow));

  final rows = <terminal.TerminalRow>[];
  for (final frameRow in frameRows) {
    if (frameRow.absoluteRow <= commandRow) {
      continue;
    }
    if (endPromptRow != null && frameRow.absoluteRow >= endPromptRow) {
      break;
    }
    rows.add(
      terminal.TerminalRow(
        index: rows.length,
        text: frameRow.row.text,
        wrapped: frameRow.row.wrapped,
        modifiedAt: frameRow.row.modifiedAt,
        styleRuns: frameRow.row.styleRuns,
      ),
    );
  }
  return List<terminal.TerminalRow>.unmodifiable(rows);
}

List<terminal.TerminalRow> _terminalRowsForFinishedCommandBlockPreview({
  required ShellCommandBlock block,
  required terminal.TerminalFrameDiff frame,
  DateTime? submittedAt,
  int? endPromptRow,
}) {
  final rows = _freshOrPendingRowsForCommandBlock(
    command: block.command,
    commandRow: block.outputRange.commandRow,
    submittedAt: submittedAt,
    frame: frame,
    endPromptRow: _finishedPreviewEndPromptRow(
      commandRow: block.outputRange.commandRow,
      endPromptRow: endPromptRow,
    ),
  );
  if (_shellCommandBlockRowsHaveVisibleText(
    shellCommandBlockOutputRowsFrom(block, rows),
  )) {
    return rows;
  }
  return rows;
}

List<terminal.TerminalRow> _terminalRowsModifiedSinceSubmittedCommand({
  required String command,
  required int commandRow,
  required DateTime submittedAt,
  required terminal.TerminalFrameDiff frame,
  int? endPromptRow,
}) {
  if (frame.rows.isEmpty) {
    return const <terminal.TerminalRow>[];
  }
  final rows = <terminal.TerminalRow>[];
  for (final row in frame.rows) {
    final absoluteRow = frame.viewportStartRow >= 0
        ? frame.viewportStartRow + row.index
        : row.index;
    if (frame.viewportStartRow >= 0 && absoluteRow <= commandRow) {
      continue;
    }
    if (endPromptRow != null && absoluteRow >= endPromptRow) {
      continue;
    }
    final modifiedAt = row.modifiedAt;
    if (modifiedAt == null || modifiedAt.isBefore(submittedAt)) {
      continue;
    }
    rows.add(
      terminal.TerminalRow(
        index: rows.length,
        text: row.text,
        wrapped: row.wrapped,
        modifiedAt: modifiedAt,
        styleRuns: row.styleRuns,
      ),
    );
  }
  return _dropLeadingSubmittedCommandRows(
    command: command,
    allowLeadingContinuation: true,
    rows: rows,
  );
}

int? _finishedPreviewEndPromptRow({
  required int commandRow,
  required int? endPromptRow,
}) {
  if (endPromptRow == null || endPromptRow <= commandRow) {
    return null;
  }
  return endPromptRow;
}

@visibleForTesting
bool shellCommandBlockFrameReachedPromptBoundary({
  required terminal.TerminalFrameDiff frame,
  required int? endPromptRow,
}) {
  if (endPromptRow == null || endPromptRow < 0) {
    return false;
  }
  final cursorRow = shellCommandBlockPromptRowForFrame(frame);
  if (cursorRow != null && cursorRow >= endPromptRow) {
    return true;
  }
  for (final row in frame.rows) {
    final absoluteRow = frame.viewportStartRow >= 0
        ? frame.viewportStartRow + row.index
        : row.index;
    if (absoluteRow >= endPromptRow) {
      return true;
    }
  }
  return false;
}

List<terminal.TerminalRow> _dropLeadingSubmittedCommandRows({
  required String command,
  required List<terminal.TerminalRow> rows,
  bool allowLeadingContinuation = false,
}) {
  if (rows.isEmpty) {
    return const <terminal.TerminalRow>[];
  }
  final normalizedCommand = _normalizedCommandLineText(command);
  if (normalizedCommand.isEmpty) {
    return List<terminal.TerminalRow>.unmodifiable(rows);
  }
  final commandParts = normalizedCommand.split(' ');
  var sawCommandStart = false;
  var start = 0;
  while (start < rows.length) {
    final line = _normalizedCommandLineText(rows[start].text);
    if (line.isEmpty) {
      start += 1;
      continue;
    }
    if (_looksLikeSubmittedCommandStart(
      line: line,
      command: normalizedCommand,
      commandParts: commandParts,
    )) {
      sawCommandStart = true;
      start += 1;
      continue;
    }
    if ((sawCommandStart ||
            (allowLeadingContinuation && start == 0 && rows.length > 1)) &&
        _looksLikeSubmittedCommandContinuation(
          line: line,
          commandParts: commandParts,
        )) {
      start += 1;
      continue;
    }
    break;
  }
  if (start == 0) {
    return List<terminal.TerminalRow>.unmodifiable(rows);
  }
  return List<terminal.TerminalRow>.unmodifiable(
    _renumberTerminalRows(rows.skip(start)),
  );
}

bool _looksLikeSubmittedCommandStart({
  required String line,
  required String command,
  required List<String> commandParts,
}) {
  if (line == command || line.contains(command)) {
    return true;
  }
  if (commandParts.isEmpty) {
    return false;
  }
  final firstPart = commandParts.first;
  return line == firstPart || line.endsWith(' $firstPart');
}

bool _looksLikeSubmittedCommandContinuation({
  required String line,
  required List<String> commandParts,
}) {
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

String _normalizedCommandLineText(String text) {
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

List<terminal.TerminalRow> _renumberTerminalRows(
  Iterable<terminal.TerminalRow> rows,
) {
  var index = 0;
  return [
    for (final row in rows)
      terminal.TerminalRow(
        index: index++,
        text: row.text,
        wrapped: row.wrapped,
        modifiedAt: row.modifiedAt,
        styleRuns: row.styleRuns,
      ),
  ];
}

int? _submittedCommandBlockCommandRowForFrame(
  terminal.TerminalFrameDiff frame,
) {
  if (frame.viewportStartRow < 0 || frame.cursor.row < 0) {
    return null;
  }
  return frame.viewportStartRow + frame.cursor.row;
}

_SubmittedCommandBlockPreviewCapture? _firstSubmittedCommandCaptureFor(
  List<_SubmittedCommandBlockPreviewCapture> captures,
  String command,
) {
  for (final capture in captures) {
    if (capture.command == command) {
      return capture;
    }
  }
  return null;
}

ShellCommandBlock? _commandBlockById(
  ShellCommandBlockSnapshot snapshot,
  String id,
) {
  for (final block in snapshot.blocks) {
    if (block.id == id) {
      return block;
    }
  }
  return null;
}

int? _commandLineFrameRowIndex({
  required ShellCommandBlock block,
  required List<_FrameRow> rows,
}) {
  for (var index = 0; index < rows.length; index += 1) {
    final frameRow = rows[index];
    if (frameRow.absoluteRow == block.outputRange.commandRow &&
        _frameRowContainsCommand(frameRow.row, block.command)) {
      return index;
    }
  }
  return null;
}

bool _frameRowContainsCommand(terminal.TerminalRow row, String command) {
  final normalizedCommand = command.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalizedCommand.isEmpty) {
    return false;
  }
  final normalizedRow = row.text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return normalizedRow.contains(normalizedCommand);
}

class _FrameRow {
  const _FrameRow({required this.absoluteRow, required this.row});

  final int absoluteRow;
  final terminal.TerminalRow row;
}

class _PendingCommandBlockPreviewRows {
  const _PendingCommandBlockPreviewRows({
    required this.commandRow,
    required this.rows,
  });

  final int commandRow;
  final List<terminal.TerminalRow> rows;
}

class _SubmittedCommandBlockPreviewCapture {
  const _SubmittedCommandBlockPreviewCapture({
    required this.command,
    required this.commandRow,
    required this.submittedAt,
    this.rows = const <terminal.TerminalRow>[],
  });

  final String command;
  final int commandRow;
  final DateTime? submittedAt;
  final List<terminal.TerminalRow> rows;

  _SubmittedCommandBlockPreviewCapture copyWith({
    List<terminal.TerminalRow>? rows,
  }) {
    return _SubmittedCommandBlockPreviewCapture(
      command: command,
      commandRow: commandRow,
      submittedAt: submittedAt,
      rows: rows ?? this.rows,
    );
  }
}

class _FinishedCommandBlockPreviewCaptureTarget {
  const _FinishedCommandBlockPreviewCaptureTarget({
    required this.blockId,
    required this.commandRow,
    this.submittedAt,
  });

  final String blockId;
  final int commandRow;
  final DateTime? submittedAt;
}

class _ShellCommandBlockFinishPlan {
  const _ShellCommandBlockFinishPlan({
    required this.startRow,
    required this.startCwd,
    required this.outputEndRow,
    this.endPromptRow,
    this.endCwd,
  });

  final int startRow;
  final String? startCwd;
  final int outputEndRow;
  final int? endPromptRow;
  final String? endCwd;
}

extension _ShellScreenStateEvents on _ShellScreenState {
  Future<void> _handleNativePasteMenu() async {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId == null) {
      return;
    }
    if (_commandInputVisibleForSession(activeSessionId) &&
        (_commandInputFocusNodes[activeSessionId]?.hasFocus ?? false)) {
      final text = await ClipboardBridge.paste();
      _insertTextIntoCommandInput(activeSessionId, text);
      return;
    }
    await _pasteToSession(activeSessionId);
  }

  Future<void> _handleNativeFindMenu(NativeFindAction action) async {
    if (!mounted) {
      return;
    }
    switch (action) {
      case NativeFindAction.next:
        if (!_isSearchOpen) {
          _openSearch();
          return;
        }
        _moveSearchMatch(1);
        return;
      case NativeFindAction.previous:
        if (!_isSearchOpen) {
          _openSearch();
          return;
        }
        _moveSearchMatch(-1);
        return;
      case NativeFindAction.show:
      case NativeFindAction.replace:
      case NativeFindAction.useSelection:
      case NativeFindAction.jumpToSelection:
        _openSearch();
        return;
    }
  }

  void _handleTerminalSessionEvent(terminal.TerminalSessionEvent event) {
    switch (event) {
      case terminal.TerminalSessionFrameEvent(:final sessionId, :final frame):
        final frameSequence =
            (_terminalFrameSequenceBySession[sessionId] ?? 0) + 1;
        _terminalFrameSequenceBySession[sessionId] = frameSequence;
        final commandBlockFrame = ref
            .read(sessionControllerProvider.notifier)
            .viewportFor(sessionId)
            .frame;
        _recordInstantReplayFrame(sessionId, frame);
        _captureSubmittedCommandBlockPreviewRowsFromFrame(
          sessionId,
          commandBlockFrame,
        );
        _capturePendingCommandBlockPreviewRowsFromFrame(
          sessionId,
          commandBlockFrame,
        );
        _captureFinishedCommandBlockPreviewRowsFromFrame(
          sessionId,
          commandBlockFrame,
        );
        _captureCommandBlockPreviewRowsFromFrame(sessionId, commandBlockFrame);
        _markNewOutputBadge(sessionId, frame);
        _feedCoprocess(sessionId, frame, frameSequence: frameSequence);
        _runProfileTriggers(sessionId, frame, frameSequence: frameSequence);
        _notifyInactiveActivity(sessionId, frame);
        _refreshSearchMatchesAfterFrame(sessionId, frame);
        _scheduleRenderableSessionSwap(sessionId);
      case terminal.TerminalSessionExitEvent():
        _terminalFrameSequenceBySession.remove(event.sessionId);
        _lastNewOutputFramePreviews.remove(event.sessionId);
        _searchRefreshFrameSignatures.remove(event.sessionId);
        _sessionsSeenForNewOutputBadges.remove(event.sessionId);
        _sessionsWithNewOutput.remove(event.sessionId);
        _triggerMatchesBySession.remove(event.sessionId);
        _bookmarkedCommandBlockIdsBySession.remove(event.sessionId);
        _commandBlockSnapshotsBySession.remove(event.sessionId);
        _commandBlockPreviewRowsBySession.remove(event.sessionId);
        _pendingCommandBlockPreviewRowsBySession.remove(event.sessionId);
        _submittedCommandBlockPreviewCapturesBySession.remove(event.sessionId);
        _submittedCommandBlockPreviewBlockIdsBySession.remove(event.sessionId);
        _finishedCommandBlockPreviewTargetsBySession.remove(event.sessionId);
        _nativeTerminalCommandBlockIdsBySession.remove(event.sessionId);
        _nativeTerminalCommandBlockIdsSeenBySession.remove(event.sessionId);
        _commandInputDraftsBySession.remove(event.sessionId);
        _commandInputDraftTextBySession.remove(event.sessionId);
        _commandInputDraftLoadingSessionIds.remove(event.sessionId);
        if (_activeCommandCorrectionSessionId == event.sessionId) {
          _activeCommandCorrection = null;
          _activeCommandCorrectionSessionId = null;
        }
        _stopCoprocess(event.sessionId);
        _clearCapturedOutput(event.sessionId);
        _notifySessionExit(event.sessionId, event.exitCode);
      case terminal.TerminalSessionBellEvent():
        _notifyBell(event.sessionId);
      case terminal.TerminalSessionShellHookEvent():
        _applyCommandCenterShellHook(event);
        _recordCommandBlockShellHook(event);
        _notifyShellHook(event);
    }
  }

  void _applyCommandCenterShellHook(
    terminal.TerminalSessionShellHookEvent event,
  ) {
    final result = _commandCenterShellEventWiring.applyShellHook(
      _commandCenterRuntime,
      event,
    );
    if (!result.applied) {
      return;
    }
    _commandCenterRuntime = result.state;
    if (event.hook == 'command_finished') {
      _scheduleGlobalCommandHistorySave(event.sessionId);
    }
  }

  void _recordCommandBlockShellHook(
    terminal.TerminalSessionShellHookEvent event,
  ) {
    if (!_commandBlocksHistoryFeatureFlags.enabled ||
        !_commandBlocksHistoryFeatureFlags.commandBlocks) {
      if (_commandBlockSnapshotsBySession.containsKey(event.sessionId) &&
          mounted) {
        _mutateState(() {
          _commandBlockSnapshotsBySession.remove(event.sessionId);
          _commandBlockPreviewRowsBySession.remove(event.sessionId);
          _pendingCommandBlockPreviewRowsBySession.remove(event.sessionId);
          _submittedCommandBlockPreviewCapturesBySession.remove(
            event.sessionId,
          );
          _submittedCommandBlockPreviewBlockIdsBySession.remove(
            event.sessionId,
          );
          _finishedCommandBlockPreviewTargetsBySession.remove(event.sessionId);
          _nativeTerminalCommandBlockIdsBySession.remove(event.sessionId);
          _nativeTerminalCommandBlockIdsSeenBySession.remove(event.sessionId);
        });
      }
      return;
    }
    if (!ShellCommandBlockShellHookReducer.supportsHook(event.hook)) {
      return;
    }
    final normalizedHook = ShellCommandBlockShellHookReducer.normalizeHook(
      event.hook,
    );
    final commandText = event.command?.trim();

    final sessionController = ref.read(sessionControllerProvider.notifier);
    final sessionState = ref.read(sessionControllerProvider);
    final frame = sessionController.viewportFor(event.sessionId).frame;
    final promptMarks =
        _paneForSession(
          sessionState,
          event.sessionId,
        )?.shellIntegration.promptMarks ??
        const <TerminalShellPromptMark>[];
    final previousSnapshot = _commandBlockSnapshotsBySession[event.sessionId];
    final previewCapturePaused = _commandBlockPreviewCapturePausedForFrame(
      event.sessionId,
      frame,
    );
    final hookPendingPreviewRows = previewCapturePaused
        ? null
        : _pendingCommandBlockPreviewRowsFromFrame(
            event.sessionId,
            previousSnapshot,
            frame,
          );
    final submittedCapture = _submittedCommandBlockPreviewCaptureFor(
      event.sessionId,
      commandText,
    );
    final submittedCaptureForMerge =
        normalizedHook == 'command_finished' &&
            submittedCapture != null &&
            !previewCapturePaused
        ? _submittedCommandBlockPreviewCaptureWithFrameRows(
            submittedCapture,
            frame,
          )
        : submittedCapture;
    final preexecSubmittedCommandRow = normalizedHook == 'preexec'
        ? submittedCapture?.commandRow
        : null;
    final shellHookPromptScrollbackOffset = normalizedHook == 'precmd'
        ? event.promptScrollbackOffset ??
              shellCommandBlockPromptRowForFrame(frame)
        : event.promptScrollbackOffset;
    final snapshot = ShellCommandBlockShellHookReducer.reduce(
      snapshot: previousSnapshot ?? const ShellCommandBlockSnapshot(),
      flags: _commandBlocksHistoryFeatureFlags,
      sessionId: event.sessionId,
      hook: normalizedHook,
      command: commandText,
      cwd: event.cwd,
      exitCode: event.exitCode,
      promptScrollbackOffset:
          preexecSubmittedCommandRow ?? shellHookPromptScrollbackOffset,
      commandStartRow:
          submittedCaptureForMerge?.commandRow ??
          shellCommandBlockCommandStartRowForFrame(frame, command: commandText),
      promptMarks: promptMarks,
      viewportEndRow: shellCommandBlockVisibleViewportEndRow(
        viewportStartRow: frame.viewportStartRow,
        viewportRows: frame.viewportRows,
      ),
    );

    if (!mounted) {
      return;
    }
    final capturedPreviewRows = previewCapturePaused
        ? <String, List<terminal.TerminalRow>>{}
        : _commandBlockPreviewRowsForFrame(snapshot, frame);
    if (!previewCapturePaused) {
      capturedPreviewRows.addAll(
        _pendingCommandBlockPreviewRowsForSnapshot(event.sessionId, snapshot),
      );
      capturedPreviewRows.addAll(
        _pendingCommandBlockPreviewRowsForBlocks(
          hookPendingPreviewRows,
          snapshot,
        ),
      );
    }
    final submittedPreviewRows =
        normalizedHook == 'command_finished' && !previewCapturePaused
        ? _submittedCommandBlockPreviewRowsForFinishedCommand(
            sessionId: event.sessionId,
            snapshot: snapshot,
            command: commandText,
            capture: submittedCaptureForMerge,
          )
        : const <String, List<terminal.TerminalRow>>{};
    capturedPreviewRows.addAll(submittedPreviewRows);
    if (normalizedHook == 'command_finished' && !previewCapturePaused) {
      final currentFrameFinishedRows =
          shellCommandBlockFinishedPreviewRowsForCurrentFrame(
            snapshot: snapshot,
            frame: frame,
            submittedAt: submittedCaptureForMerge?.submittedAt,
            endPromptRow: snapshot.lastPrompt?.row,
          );
      for (final entry in currentFrameFinishedRows.entries) {
        final existing = capturedPreviewRows[entry.key];
        if (shellCommandBlockPreviewRowsWouldChange(
          existingRows: existing,
          nextRows: entry.value,
        )) {
          capturedPreviewRows[entry.key] = shellCommandBlockMergedPreviewRows(
            existingRows: existing,
            nextRows: entry.value,
          );
        }
      }
    }
    if (identical(snapshot, previousSnapshot) ||
        (previousSnapshot == null &&
            !_commandBlockSnapshotHasState(snapshot))) {
      return;
    }
    _mutateState(() {
      _commandBlockSnapshotsBySession[event.sessionId] = snapshot;
      _mergeCommandBlockPreviewRows(
        sessionId: event.sessionId,
        snapshot: snapshot,
        capturedRows: capturedPreviewRows,
        protectedUpdateBlockIds: submittedPreviewRows.keys.toSet(),
      );
      if (normalizedHook == 'command_finished') {
        _recordFinishedCommandBlockPreviewTarget(
          event.sessionId,
          snapshot,
          submittedAt: submittedCaptureForMerge?.submittedAt,
        );
        _removeSubmittedCommandBlockPreviewCapture(
          event.sessionId,
          commandText,
        );
      }
      _removeMatchedPendingCommandBlockPreviewRows(event.sessionId, snapshot);
    });
    if (normalizedHook == 'command_finished') {
      _maybeRequestCommandCorrectionForFinishedHook(
        event: event,
        snapshot: snapshot,
        capturedPreviewRows: capturedPreviewRows,
      );
    }
  }

  void _maybeRequestCommandCorrectionForFinishedHook({
    required terminal.TerminalSessionShellHookEvent event,
    required ShellCommandBlockSnapshot snapshot,
    required Map<String, List<terminal.TerminalRow>> capturedPreviewRows,
  }) {
    final command = event.command?.trim();
    final exitCode = event.exitCode;
    if (!_suggestCorrectedCommands ||
        command == null ||
        command.isEmpty ||
        exitCode == null ||
        exitCode == 0) {
      return;
    }
    ShellCommandBlock? block;
    for (final candidate in snapshot.blocks.reversed) {
      if (candidate.command == command) {
        block = candidate;
        break;
      }
    }
    if (block == null) {
      return;
    }
    final existingRows =
        _commandBlockPreviewRowsBySession[event.sessionId]?[block.id] ??
        const <terminal.TerminalRow>[];
    final rows = capturedPreviewRows[block.id] ?? existingRows;
    final outputTail = rows.map((row) => row.text).join('\n');
    final state = ref.read(sessionControllerProvider);
    final pane = _paneForSession(state, event.sessionId);
    final profile = pane == null ? null : _profileForPane(pane, state.profiles);
    final requestSerial = ++_commandCorrectionRequestSerial;
    unawaited(() async {
      final correction = await _commandIntelligenceService.correctCommand(
        CommandCorrectionRequest(
          command: command,
          cwd:
              event.cwd ??
              block?.cwd ??
              pane?.shellIntegration.currentDirectory,
          exitCode: exitCode,
          outputTail: outputTail,
          recentCommands: pane?.shellIntegration.recentCommands ?? const [],
          recentDirectories:
              pane?.shellIntegration.recentDirectories ?? const [],
          apiBaseUrl: profile?.commandIntelligence.baseUrl,
          apiKey: profile?.commandIntelligence.apiKey,
          apiModel: profile?.commandIntelligence.model,
          allowRemote: _agentProviderDraftEnabled,
          preferRemote: _agentProviderDraftRequested,
        ),
      );
      if (!mounted ||
          requestSerial != _commandCorrectionRequestSerial ||
          correction == null ||
          correction.command.trim() == command) {
        return;
      }
      _mutateState(() {
        _activeCommandCorrection = correction;
        _activeCommandCorrectionSessionId = event.sessionId;
      });
    }());
  }

  _SubmittedCommandBlockPreviewCapture
  _submittedCommandBlockPreviewCaptureWithFrameRows(
    _SubmittedCommandBlockPreviewCapture capture,
    terminal.TerminalFrameDiff frame,
  ) {
    final submittedAt = capture.submittedAt;
    if (submittedAt == null) {
      return capture;
    }
    final rows = shellCommandBlockSubmittedPreviewRowsForFrame(
      command: capture.command,
      commandRow: capture.commandRow,
      submittedAt: submittedAt,
      frame: frame,
    );
    if (!shellCommandBlockShouldReplacePreviewRows(
      existingRows: capture.rows,
      nextRows: rows,
    )) {
      return capture;
    }
    return capture.copyWith(rows: rows);
  }

  void _recordSubmittedCommandBlockPreviewCapture(
    String sessionId,
    String command,
  ) {
    if (!_commandBlocksHistoryFeatureFlags.enabled ||
        !_commandBlocksHistoryFeatureFlags.commandBlocks) {
      return;
    }
    final text = command.trim();
    if (text.isEmpty) {
      return;
    }
    final frame = ref
        .read(sessionControllerProvider.notifier)
        .viewportFor(sessionId)
        .frame;
    final commandRow = _submittedCommandBlockCommandRowForFrame(frame);
    if (commandRow == null) {
      return;
    }
    _finishedCommandBlockPreviewTargetsBySession.remove(sessionId);
    final captures = _submittedCommandBlockPreviewCapturesBySession.putIfAbsent(
      sessionId,
      () => <_SubmittedCommandBlockPreviewCapture>[],
    );
    captures.add(
      _SubmittedCommandBlockPreviewCapture(
        command: text,
        commandRow: commandRow,
        submittedAt: DateTime.now(),
      ),
    );
    if (captures.length > 12) {
      captures.removeRange(0, captures.length - 12);
    }
  }

  void _captureSubmittedCommandBlockPreviewRowsFromFrame(
    String sessionId,
    terminal.TerminalFrameDiff frame,
  ) {
    if (!_commandBlocksHistoryFeatureFlags.enabled ||
        !_commandBlocksHistoryFeatureFlags.commandBlocks) {
      return;
    }
    if (_commandBlockPreviewCapturePausedForFrame(sessionId, frame)) {
      return;
    }
    final captures = _submittedCommandBlockPreviewCapturesBySession[sessionId];
    if (captures == null || captures.isEmpty || !mounted) {
      return;
    }
    var changed = false;
    final nextCaptures = <_SubmittedCommandBlockPreviewCapture>[];
    for (final capture in captures) {
      final rows = capture.submittedAt == null
          ? _terminalRowsForPendingCommandBlockPreview(
              commandRow: capture.commandRow,
              frame: frame,
            )
          : shellCommandBlockSubmittedPreviewRowsForFrame(
              command: capture.command,
              commandRow: capture.commandRow,
              submittedAt: capture.submittedAt!,
              frame: frame,
            );
      if (rows.isEmpty) {
        nextCaptures.add(capture);
        continue;
      }
      if (capture.rows.isEmpty ||
          rows.length > capture.rows.length ||
          (rows.length == capture.rows.length &&
              !shellCommandBlockPreviewRowsHaveSameContent(
                capture.rows,
                rows,
              ))) {
        nextCaptures.add(capture.copyWith(rows: rows));
        changed = true;
      } else {
        nextCaptures.add(capture);
      }
    }
    if (!changed) {
      return;
    }
    _mutateState(() {
      _submittedCommandBlockPreviewCapturesBySession[sessionId] = nextCaptures;
    });
  }

  _SubmittedCommandBlockPreviewCapture? _submittedCommandBlockPreviewCaptureFor(
    String sessionId,
    String? command,
  ) {
    final commandText = command?.trim();
    if (commandText == null || commandText.isEmpty) {
      return null;
    }
    final captures = _submittedCommandBlockPreviewCapturesBySession[sessionId];
    if (captures == null || captures.isEmpty) {
      return null;
    }
    return _firstSubmittedCommandCaptureFor(captures, commandText);
  }

  Map<String, List<terminal.TerminalRow>>
  _submittedCommandBlockPreviewRowsForFinishedCommand({
    required String sessionId,
    required ShellCommandBlockSnapshot snapshot,
    required String? command,
    _SubmittedCommandBlockPreviewCapture? capture,
  }) {
    final commandText = command?.trim();
    if (commandText == null || commandText.isEmpty) {
      return const <String, List<terminal.TerminalRow>>{};
    }
    final submittedCapture =
        capture ??
        _submittedCommandBlockPreviewCaptureFor(sessionId, commandText);
    if (submittedCapture == null || submittedCapture.rows.isEmpty) {
      return const <String, List<terminal.TerminalRow>>{};
    }
    for (final block in snapshot.blocks.reversed) {
      if (block.command == commandText) {
        final rows = shellCommandBlockOutputRowsFrom(
          block,
          submittedCapture.rows,
        );
        return rows.isEmpty
            ? const <String, List<terminal.TerminalRow>>{}
            : {block.id: rows};
      }
    }
    return const <String, List<terminal.TerminalRow>>{};
  }

  void _removeSubmittedCommandBlockPreviewCapture(
    String sessionId,
    String? command,
  ) {
    final commandText = command?.trim();
    if (commandText == null || commandText.isEmpty) {
      return;
    }
    final captures = _submittedCommandBlockPreviewCapturesBySession[sessionId];
    if (captures == null || captures.isEmpty) {
      return;
    }
    final index = captures.indexWhere(
      (capture) => capture.command == commandText,
    );
    if (index == -1) {
      return;
    }
    captures.removeAt(index);
    if (captures.isEmpty) {
      _submittedCommandBlockPreviewCapturesBySession.remove(sessionId);
    }
  }

  void _recordFinishedCommandBlockPreviewTarget(
    String sessionId,
    ShellCommandBlockSnapshot snapshot, {
    DateTime? submittedAt,
  }) {
    if (snapshot.blocks.isEmpty) {
      return;
    }
    final block = snapshot.blocks.last;
    if (!block.isValid) {
      return;
    }
    final targets = _finishedCommandBlockPreviewTargetsBySession.putIfAbsent(
      sessionId,
      () => <_FinishedCommandBlockPreviewCaptureTarget>[],
    );
    if (targets.any((target) => target.blockId == block.id)) {
      return;
    }
    targets.add(
      _FinishedCommandBlockPreviewCaptureTarget(
        blockId: block.id,
        commandRow: block.outputRange.commandRow,
        submittedAt: submittedAt,
      ),
    );
    if (targets.length > 8) {
      targets.removeRange(0, targets.length - 8);
    }
  }

  void _capturePendingCommandBlockPreviewRowsFromFrame(
    String sessionId,
    terminal.TerminalFrameDiff frame,
  ) {
    if (!_commandBlocksHistoryFeatureFlags.enabled ||
        !_commandBlocksHistoryFeatureFlags.commandBlocks) {
      return;
    }
    if (_commandBlockPreviewCapturePausedForFrame(sessionId, frame)) {
      return;
    }
    final snapshot = _commandBlockSnapshotsBySession[sessionId];
    final prompt = snapshot?.lastPrompt;
    if (prompt == null || !mounted) {
      return;
    }
    final rows = _terminalRowsForPendingCommandBlockPreview(
      commandRow: prompt.row,
      frame: frame,
    );
    if (rows.isEmpty) {
      return;
    }
    final existing = _pendingCommandBlockPreviewRowsBySession[sessionId];
    if (existing != null && existing.commandRow == prompt.row) {
      if (rows.length < existing.rows.length) {
        return;
      }
      if (rows.length == existing.rows.length &&
          shellCommandBlockPreviewRowsHaveSameContent(existing.rows, rows)) {
        return;
      }
    }
    _mutateState(() {
      _pendingCommandBlockPreviewRowsBySession[sessionId] =
          _PendingCommandBlockPreviewRows(commandRow: prompt.row, rows: rows);
    });
  }

  Map<String, List<terminal.TerminalRow>>
  _pendingCommandBlockPreviewRowsForSnapshot(
    String sessionId,
    ShellCommandBlockSnapshot snapshot,
  ) {
    final pending = _pendingCommandBlockPreviewRowsBySession[sessionId];
    if (pending == null || pending.rows.isEmpty) {
      return const <String, List<terminal.TerminalRow>>{};
    }
    for (final block in snapshot.blocks.reversed) {
      if (block.outputRange.commandRow == pending.commandRow) {
        final rows = shellCommandBlockOutputRowsFrom(block, pending.rows);
        return rows.isEmpty
            ? const <String, List<terminal.TerminalRow>>{}
            : {block.id: rows};
      }
    }
    return const <String, List<terminal.TerminalRow>>{};
  }

  void _removeMatchedPendingCommandBlockPreviewRows(
    String sessionId,
    ShellCommandBlockSnapshot snapshot,
  ) {
    final pending = _pendingCommandBlockPreviewRowsBySession[sessionId];
    if (pending == null) {
      return;
    }
    final matched = snapshot.blocks.any(
      (block) => block.outputRange.commandRow == pending.commandRow,
    );
    if (matched) {
      _pendingCommandBlockPreviewRowsBySession.remove(sessionId);
    }
  }

  _PendingCommandBlockPreviewRows? _pendingCommandBlockPreviewRowsFromFrame(
    String sessionId,
    ShellCommandBlockSnapshot? snapshot,
    terminal.TerminalFrameDiff frame,
  ) {
    if (_commandBlockPreviewCapturePausedForFrame(sessionId, frame)) {
      return null;
    }
    final prompt = snapshot?.lastPrompt;
    if (prompt == null) {
      return null;
    }
    final rows = _terminalRowsForPendingCommandBlockPreview(
      commandRow: prompt.row,
      frame: frame,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _PendingCommandBlockPreviewRows(commandRow: prompt.row, rows: rows);
  }

  Map<String, List<terminal.TerminalRow>>
  _pendingCommandBlockPreviewRowsForBlocks(
    _PendingCommandBlockPreviewRows? pending,
    ShellCommandBlockSnapshot snapshot,
  ) {
    if (pending == null || pending.rows.isEmpty) {
      return const <String, List<terminal.TerminalRow>>{};
    }
    for (final block in snapshot.blocks.reversed) {
      if (block.outputRange.commandRow == pending.commandRow) {
        final rows = shellCommandBlockOutputRowsFrom(block, pending.rows);
        return rows.isEmpty
            ? const <String, List<terminal.TerminalRow>>{}
            : {block.id: rows};
      }
    }
    return const <String, List<terminal.TerminalRow>>{};
  }

  void _captureCommandBlockPreviewRowsFromFrame(
    String sessionId,
    terminal.TerminalFrameDiff frame,
  ) {
    if (!_commandBlocksHistoryFeatureFlags.enabled ||
        !_commandBlocksHistoryFeatureFlags.commandBlocks) {
      return;
    }
    if (_commandBlockPreviewCapturePausedForFrame(sessionId, frame)) {
      return;
    }
    final snapshot = _commandBlockSnapshotsBySession[sessionId];
    if (snapshot == null || snapshot.blocks.isEmpty || !mounted) {
      return;
    }
    if (_hasSubmittedCommandBlockPreviewCapture(sessionId)) {
      return;
    }
    final capturedRows = _commandBlockPreviewRowsForFrame(snapshot, frame);
    if (!_hasCommandBlockPreviewRowUpdates(
      sessionId: sessionId,
      capturedRows: capturedRows,
    )) {
      return;
    }
    _mutateState(() {
      _mergeCommandBlockPreviewRows(
        sessionId: sessionId,
        snapshot: snapshot,
        capturedRows: capturedRows,
      );
    });
  }

  bool _hasSubmittedCommandBlockPreviewCapture(String sessionId) {
    final captures = _submittedCommandBlockPreviewCapturesBySession[sessionId];
    return captures != null && captures.isNotEmpty;
  }

  bool _commandBlockPreviewCapturePausedForFrame(
    String sessionId,
    terminal.TerminalFrameDiff frame,
  ) {
    if (frame.modes.alternateScreen) {
      final snapshot = _commandBlockSnapshotsBySession[sessionId];
      final blockId = _runningCommandBlockIdForSnapshot(snapshot);
      if (blockId != null) {
        _removeCommandBlockPreviewRows(sessionId, blockId);
      }
      return true;
    }
    final nativeBlockId = _nativeTerminalCommandBlockIdsBySession[sessionId];
    if (nativeBlockId == null) {
      return false;
    }
    _removeCommandBlockPreviewRows(sessionId, nativeBlockId);
    return true;
  }

  String? _runningCommandBlockIdForSnapshot(
    ShellCommandBlockSnapshot? snapshot,
  ) {
    final blocks = snapshot?.blocks;
    if (blocks == null) {
      return null;
    }
    for (final block in blocks.reversed) {
      if (block.status == ShellCommandBlockStatus.running) {
        return block.id;
      }
    }
    return null;
  }

  void _removeCommandBlockPreviewRows(String sessionId, String blockId) {
    final rows = _commandBlockPreviewRowsBySession[sessionId];
    if (rows == null || !rows.containsKey(blockId)) {
      return;
    }
    rows.remove(blockId);
    if (rows.isEmpty) {
      _commandBlockPreviewRowsBySession.remove(sessionId);
    }
  }

  void _captureFinishedCommandBlockPreviewRowsFromFrame(
    String sessionId,
    terminal.TerminalFrameDiff frame,
  ) {
    if (!_commandBlocksHistoryFeatureFlags.enabled ||
        !_commandBlocksHistoryFeatureFlags.commandBlocks) {
      return;
    }
    if (_commandBlockPreviewCapturePausedForFrame(sessionId, frame)) {
      return;
    }
    final snapshot = _commandBlockSnapshotsBySession[sessionId];
    final targets = _finishedCommandBlockPreviewTargetsBySession[sessionId];
    if (snapshot == null || targets == null || targets.isEmpty || !mounted) {
      return;
    }
    if (_hasSubmittedCommandBlockPreviewCapture(sessionId)) {
      return;
    }
    final capturedRows = <String, List<terminal.TerminalRow>>{};
    final capturedTargetIds = <String>{};
    final latestBlockId = snapshot.blocks.isEmpty
        ? null
        : snapshot.blocks.last.id;
    for (final target in targets) {
      final block = _commandBlockById(snapshot, target.blockId);
      if (block == null) {
        continue;
      }
      final endPromptRow = _finishedPreviewEndPromptRow(
        commandRow: target.commandRow,
        endPromptRow: snapshot.lastPrompt?.row,
      );
      final rows = _terminalRowsForFinishedCommandBlockPreview(
        block: block,
        frame: frame,
        submittedAt: target.submittedAt,
        endPromptRow: endPromptRow,
      );
      final capture = shellCommandBlockFinishedPreviewCaptureForRows(
        block: block,
        rows: rows,
        isLatestBlock: target.blockId == latestBlockId,
      );
      if (capture.removeTarget ||
          shellCommandBlockFrameReachedPromptBoundary(
            frame: frame,
            endPromptRow: endPromptRow,
          )) {
        capturedTargetIds.add(target.blockId);
      }
      if (capture.rows.isEmpty) {
        continue;
      }
      capturedRows[target.blockId] = capture.rows;
    }
    if (capturedRows.isEmpty && capturedTargetIds.isEmpty) {
      return;
    }
    _mutateState(() {
      if (capturedRows.isNotEmpty) {
        _mergeCommandBlockPreviewRows(
          sessionId: sessionId,
          snapshot: snapshot,
          capturedRows: capturedRows,
        );
      }
      targets.removeWhere(
        (target) => capturedTargetIds.contains(target.blockId),
      );
      if (targets.isEmpty) {
        _finishedCommandBlockPreviewTargetsBySession.remove(sessionId);
      }
    });
  }

  bool _hasCommandBlockPreviewRowUpdates({
    required String sessionId,
    required Map<String, List<terminal.TerminalRow>> capturedRows,
  }) {
    if (capturedRows.isEmpty) {
      return false;
    }
    final existingRows =
        _commandBlockPreviewRowsBySession[sessionId] ??
        const <String, List<terminal.TerminalRow>>{};
    for (final entry in capturedRows.entries) {
      if (entry.value.isEmpty) {
        continue;
      }
      if (_commandBlockPreviewSuppressed(sessionId, entry.key)) {
        continue;
      }
      final existing = existingRows[entry.key];
      if (shellCommandBlockPreviewRowsWouldChange(
        existingRows: existing,
        nextRows: entry.value,
      )) {
        return true;
      }
    }
    return false;
  }

  void _mergeCommandBlockPreviewRows({
    required String sessionId,
    required ShellCommandBlockSnapshot snapshot,
    required Map<String, List<terminal.TerminalRow>> capturedRows,
    Set<String> protectedUpdateBlockIds = const <String>{},
  }) {
    final retainedBlockIds = {for (final block in snapshot.blocks) block.id};
    if (retainedBlockIds.isEmpty) {
      _commandBlockPreviewRowsBySession.remove(sessionId);
      _submittedCommandBlockPreviewBlockIdsBySession.remove(sessionId);
      _nativeTerminalCommandBlockIdsSeenBySession.remove(sessionId);
      return;
    }
    final nativeBlockIds =
        _nativeTerminalCommandBlockIdsSeenBySession[sessionId];
    nativeBlockIds?.removeWhere(
      (blockId) => !retainedBlockIds.contains(blockId),
    );
    if (nativeBlockIds != null && nativeBlockIds.isEmpty) {
      _nativeTerminalCommandBlockIdsSeenBySession.remove(sessionId);
    }
    final sessionRows = _commandBlockPreviewRowsBySession.putIfAbsent(
      sessionId,
      () => <String, List<terminal.TerminalRow>>{},
    );
    sessionRows.removeWhere(
      (blockId, _) => !retainedBlockIds.contains(blockId),
    );
    final submittedBlockIds =
        _submittedCommandBlockPreviewBlockIdsBySession[sessionId];
    submittedBlockIds?.removeWhere(
      (blockId) => !retainedBlockIds.contains(blockId),
    );
    for (final entry in capturedRows.entries) {
      if (entry.value.isEmpty) {
        continue;
      }
      if (_commandBlockPreviewSuppressed(sessionId, entry.key)) {
        continue;
      }
      final existing = sessionRows[entry.key];
      final isSubmittedProtected =
          submittedBlockIds?.contains(entry.key) ?? false;
      if (existing != null &&
          isSubmittedProtected &&
          !protectedUpdateBlockIds.contains(entry.key)) {
        continue;
      }
      if (shellCommandBlockPreviewRowsWouldChange(
        existingRows: existing,
        nextRows: entry.value,
      )) {
        sessionRows[entry.key] = shellCommandBlockMergedPreviewRows(
          existingRows: existing,
          nextRows: entry.value,
        );
      }
    }
    if (protectedUpdateBlockIds.isNotEmpty) {
      final protectedIds = _submittedCommandBlockPreviewBlockIdsBySession
          .putIfAbsent(sessionId, () => <String>{});
      protectedIds.addAll(protectedUpdateBlockIds);
    }
    if (sessionRows.isEmpty) {
      _commandBlockPreviewRowsBySession.remove(sessionId);
    }
  }

  bool _commandBlockPreviewSuppressed(String sessionId, String blockId) {
    return _nativeTerminalCommandBlockIdsSeenBySession[sessionId]?.contains(
          blockId,
        ) ??
        false;
  }

  void _notifyInactiveActivity(
    String sessionId,
    terminal.TerminalFrameDiff frame,
  ) {
    if (!_activityNotificationsEnabled) {
      return;
    }
    final preview = _framePreview(frame);
    final hasSeenSession = !_sessionsSeenForActivityNotifications.add(
      sessionId,
    );
    final previousPreview = _lastActivityFramePreviews[sessionId];
    _lastActivityFramePreviews[sessionId] = preview;
    if (hasSeenSession &&
        previousPreview != preview &&
        _notificationSessionIsInactive(sessionId) &&
        preview != null &&
        _activityNotificationAllowed(sessionId)) {
      _sendShellNotification(
        title: 'Activity in ${_sessionTitleForNotification(sessionId)}',
        body: preview,
        identifier: 'ianvs-terminal.activity.$sessionId',
      );
    }
  }

  void _markNewOutputBadge(String sessionId, terminal.TerminalFrameDiff frame) {
    final preview = _framePreview(frame);
    final hasSeenSession = !_sessionsSeenForNewOutputBadges.add(sessionId);
    final previousPreview = _lastNewOutputFramePreviews[sessionId];
    _lastNewOutputFramePreviews[sessionId] = preview;
    if (!hasSeenSession ||
        previousPreview == preview ||
        preview == null ||
        !_sessionTabIsInactive(sessionId)) {
      return;
    }
    if (_sessionsWithNewOutput.contains(sessionId)) {
      return;
    }
    if (!mounted) {
      return;
    }
    _mutateState(() {
      _sessionsWithNewOutput.add(sessionId);
    });
  }

  void _notifySessionExit(String sessionId, int? exitCode) {
    _sendShellNotification(
      title: 'Session ended',
      body:
          '${_sessionTitleForNotification(sessionId)} exited${exitCode == null ? '' : ' with code $exitCode'}.',
      identifier:
          'ianvs-terminal.exit.$sessionId.${DateTime.now().microsecondsSinceEpoch}',
    );
  }

  void _notifyBell(String sessionId) {
    if (!_bellNotificationsEnabled) {
      return;
    }
    _sendShellNotification(
      title: 'Bell in ${_sessionTitleForNotification(sessionId)}',
      body: 'The terminal requested attention.',
      identifier: 'ianvs-terminal.bell.$sessionId',
    );
  }

  void _notifyShellHook(terminal.TerminalSessionShellHookEvent event) {
    if (event.hook != 'command_finished') {
      return;
    }
    if (!_commandFinishedNotificationsEnabled) {
      return;
    }
    final command = switch (event.command?.trim()) {
      final text? when text.isNotEmpty => text,
      _ => null,
    };
    final exitCode = event.exitCode;
    _sendShellNotification(
      title: 'Command finished',
      body: [?command, if (exitCode != null) 'Exit code $exitCode'].join('\n'),
      identifier:
          'ianvs-terminal.command.${event.sessionId}.${DateTime.now().microsecondsSinceEpoch}',
    );
  }

  Future<void> _loadNotificationPreferences() async {
    final configBootstrap = await _loadNotificationConfig();
    final preferences = LocalTerminalConfigPreferencesAdapter.toAppPreferences(
      configBootstrap.config,
    );
    if (!mounted) {
      return;
    }
    _mutateState(() {
      _notificationConfigSource = configBootstrap.source;
      _notificationLocalConfig = configBootstrap.config;
      _keybindingsConfig = configBootstrap.config.keybindings;
      _clipboardConfig = configBootstrap.config.clipboard;
      _bracketedPastePolicy = configBootstrap.config.paste.bracketedPaste;
      _pastePolicy = _pastePolicyFromConfig(configBootstrap.config.paste);
      _pasteHistoryPolicy = _pasteHistoryPolicyFromConfig(
        configBootstrap.config.paste,
      );
      _pasteHistoryEntries = _pasteHistoryEntries
          .take(_effectivePasteHistoryLimit)
          .toList();
      _commandBlocksHistoryFeatureFlags =
          CommandBlocksHistoryFeatureFlags.fromConfig(
            configBootstrap.config.commandBlocksHistory,
          );
      _commandCenterFeatureFlags = CommandCenterFeatureFlags.fromConfig(
        configBootstrap.config.commandCenter,
      );
      _suggestCorrectedCommands =
          configBootstrap.config.universalInput.suggestCorrectedCommands;
      if (!_commandCenterFeatureFlags.agentConversation) {
        _universalInputMode = _fallbackUniversalInputModeForAgentDisabled(
          _universalInputMode,
        );
      }
      if (!_commandCenterFeatureFlags.agentProviderDraft &&
          _universalInputModelLabel == 'Agent draft') {
        _universalInputModelLabel = 'Local heuristic';
      }
      if (!_commandCenterFeatureFlags.agentCommandSearchActions) {
        _agentPromptActionsBySession.clear();
      }
      _commandFinishedNotificationsEnabled =
          preferences.notifications.commandFinished;
      _bellNotificationsEnabled = preferences.notifications.bell;
      _activityNotificationsEnabled = preferences.notifications.activity;
      if (!_commandBlocksHistoryFeatureFlags.enabled ||
          !_commandBlocksHistoryFeatureFlags.commandBlocks) {
        _commandBlockSnapshotsBySession.clear();
        _commandBlockPreviewRowsBySession.clear();
        _bookmarkedCommandBlockIdsBySession.clear();
        _pendingCommandBlockPreviewRowsBySession.clear();
        _submittedCommandBlockPreviewCapturesBySession.clear();
        _submittedCommandBlockPreviewBlockIdsBySession.clear();
        _finishedCommandBlockPreviewTargetsBySession.clear();
        _nativeTerminalCommandBlockIdsBySession.clear();
        _nativeTerminalCommandBlockIdsSeenBySession.clear();
      }
    });
  }

  Future<LocalTerminalConfigBootstrapResult> _loadNotificationConfig() async {
    try {
      return await ref.read(localTerminalConfigLoaderProvider).load();
    } on Object {
      final legacyPreferences = await ref
          .read(appPreferencesRepositoryProvider)
          .load();
      return LocalTerminalConfigBootstrap.resolve(
        localConfig: null,
        legacyAppPreferences: legacyPreferences,
      );
    }
  }

  Future<void> _saveNotificationPreferences() async {
    final notifications = TerminalAppNotifications(
      commandFinished: _commandFinishedNotificationsEnabled,
      bell: _bellNotificationsEnabled,
      activity: _activityNotificationsEnabled,
    );
    final localConfig = await _loadLocalNotificationConfigForSave();
    if (localConfig != null) {
      final nextConfig = localConfig.copyWith(
        notifications: LocalTerminalNotificationsConfig(
          enabled:
              notifications.commandFinished ||
              notifications.bell ||
              notifications.activity,
          commandFinished: notifications.commandFinished,
          bell: notifications.bell,
          activity: notifications.activity,
        ),
      );
      _notificationConfigSource =
          LocalTerminalConfigBootstrapSource.localConfig;
      _notificationLocalConfig = nextConfig;
      await ref.read(localTerminalConfigRepositoryProvider).save(nextConfig);
      return;
    }

    final repository = ref.read(appPreferencesRepositoryProvider);
    final preferences =
        await repository.load() ?? const TerminalAppPreferencesDocument();
    await repository.save(preferences.copyWith(notifications: notifications));
  }

  Future<LocalTerminalConfigDocument?>
  _loadLocalNotificationConfigForSave() async {
    final repository = ref.read(localTerminalConfigRepositoryProvider);
    if (_notificationConfigSource ==
        LocalTerminalConfigBootstrapSource.localConfig) {
      return await repository.load() ?? _notificationLocalConfig;
    }
    return repository.load();
  }

  LocalTerminalPastePolicy _pastePolicyFromConfig(
    LocalTerminalPasteConfig config,
  ) {
    return LocalTerminalPastePolicy(
      confirmLargePaste: config.confirmLargePaste,
      confirmMultilinePaste: config.confirmMultilinePaste,
      historySize: config.historySize,
    );
  }

  LocalTerminalPasteHistoryPolicy _pasteHistoryPolicyFromConfig(
    LocalTerminalPasteConfig config,
  ) {
    return LocalTerminalPasteHistoryPolicy(
      enabled: config.historySize > 0,
      maxEntries: config.historySize,
    );
  }

  terminal.TerminalFrameModes _pasteModesFor(
    terminal.TerminalFrameModes frameModes,
  ) {
    return switch (_bracketedPastePolicy) {
      LocalTerminalBracketedPastePolicy.auto => frameModes,
      LocalTerminalBracketedPastePolicy.force =>
        const terminal.TerminalFrameModes(bracketedPaste: true),
      LocalTerminalBracketedPastePolicy.plain =>
        terminal.TerminalFrameModes.empty,
    };
  }

  Future<bool> _toggleHotkeyWindowWithFeedback() async {
    final status = await WindowBridge.hotkeyStatus();
    if (status != null && !status.registered) {
      _showHotkeyWindowFailure(status);
      return false;
    }
    try {
      await WindowBridge.toggleHotkeyWindow();
      return true;
    } on PlatformException catch (error) {
      _showHotkeyWindowFailure(status, error: error);
      return false;
    }
  }

  void _showHotkeyWindowFailure(
    HotkeyWindowStatus? status, {
    PlatformException? error,
  }) {
    if (!mounted) {
      return;
    }
    final details = <String>[
      'Hotkey window unavailable',
      if (status != null) 'shortcut: ${status.shortcut}',
      if (status?.errorCode != null) 'error: ${status!.errorCode}',
      if (error?.message != null && error!.message!.trim().isNotEmpty)
        error.message!.trim(),
    ].join(' - ');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(details)));
  }
}
