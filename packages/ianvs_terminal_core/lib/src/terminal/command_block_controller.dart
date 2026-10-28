import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'command_block.dart';
import 'command_occurrence.dart';
import 'terminal_models.dart';

/// A reader's position belongs to the session, so closing a route or switching
/// task views cannot discard it. Native row identity survives history eviction.
@immutable
class CommandBlockReadingState {
  const CommandBlockReadingState({
    required this.lineIndex,
    required this.sourceRow,
    required this.pixelOffset,
    required this.horizontalOffset,
    required this.selection,
    required this.selectionSourceBase,
    required this.blockSelection,
  });
  final int lineIndex;
  final int? sourceRow;
  final double pixelOffset;
  final double horizontalOffset;
  final TerminalSelection? selection;
  final int? selectionSourceBase;
  final bool blockSelection;
}

typedef CommandBlockRequest =
    Map<String, Object?>? Function(Map<String, Object?> request);

/// Session-local presentation state. All requests are read-only; re-input is
/// delegated to the host and never executes a command from a block.
class CommandBlockController extends ChangeNotifier {
  CommandBlockController({
    required this.request,
    this.maximumBlocks = 128,
    this.occurrenceScope,
    this.occurrenceScopeForBlock,
    this.maximumOccurrences = 256,
  }) : assert(
         maximumBlocks == null || maximumBlocks > 0,
         'maximumBlocks must be positive, or null for a host-bounded list',
       );
  final CommandBlockRequest request;
  final CommandOccurrenceScope? occurrenceScope;
  final CommandOccurrenceScope? Function(CommandBlock)? occurrenceScopeForBlock;
  final int maximumOccurrences;
  final Map<String, CommandOccurrence> _occurrences = {};
  final Map<String, String?> _blockScopeIds = {};

  /// Bounded metadata only; source blocks remain the output authority.
  List<CommandOccurrence> get occurrences =>
      List.unmodifiable(_occurrences.values);

  CommandOccurrenceScope? _scopeFor(CommandBlock block) =>
      occurrenceScopeForBlock != null
      ? occurrenceScopeForBlock!(block)
      : occurrenceScope;

  bool _isCurrentOccurrence(CommandOccurrence occurrence) {
    final scope = _scopeFor(
      CommandBlock(
        id: occurrence.presentationBlockId,
        sourceBlockId: occurrence.blockId,
        command: occurrence.command,
        cwd: occurrence.cwd,
        contextId: occurrence.contextId,
        sftpContextId: occurrence.sftpContextId,
        shellHostname: occurrence.shellHostname,
        shellUsername: occurrence.shellUsername,
      ),
    );
    return scope != null &&
        scope.sessionId == occurrence.scope.sessionId &&
        scope.sessionEpoch == occurrence.scope.sessionEpoch;
  }

  CommandOccurrence? occurrenceFor(String blockId) {
    final block = _blocks.where((b) => b.id == blockId).firstOrNull;
    if (block != null) {
      final scope = _scopeFor(block);
      if (scope == null) return null;
      return _occurrences[CommandOccurrence.fromBlock(block, scope).id];
    }
    final matches = _occurrences.values
        .where(
          (o) => o.presentationBlockId == blockId && _isCurrentOccurrence(o),
        )
        .take(2)
        .toList();
    return matches.length == 1 ? matches.single : null;
  }

  CommandOccurrence? occurrenceForId(String id) {
    final occurrence = _occurrences[id];
    return occurrence != null &&
            occurrenceFor(occurrence.presentationBlockId)?.id == id
        ? occurrence
        : null;
  }

  CommandOccurrence? occurrenceForSubmission(
    String submissionId, {
    String? contextId,
  }) {
    final matches = _occurrences.values
        .where(
          (o) =>
              o.submissionId == submissionId &&
              _isCurrentOccurrence(o) &&
              (contextId == null || o.contextId == contextId),
        )
        .take(2)
        .toList();
    return matches.length == 1 ? matches.single : null;
  }

  /// Only exact loaded source rows qualify. A shared parent/child row is
  /// ambiguous; a broad source span must never assign the child's cwd to it.
  /// This is a best-effort metadata lookup, not proof that an independent
  /// terminal frame has the same revision. Even matching [expectedRow] text
  /// cannot establish that identity; do not use this for file authorization.
  CommandOccurrence? occurrenceForSourceRow(
    int sourceRow, {
    TerminalRow? expectedRow,
  }) {
    final owners = <String>{};
    CommandOccurrence? result;
    for (final block in _blocks) {
      final snapshots = [block, ?_pages[block.id]];
      if (!snapshots.any(
        (snapshot) => snapshot.lines.any((line) => line.sourceRow == sourceRow),
      )) {
        continue;
      }
      // Segmented commands can share physical cells with a child outside the
      // current preview/filter window. Source-row-only lookup cannot prove ownership.
      if (snapshots.any((snapshot) => snapshot.segmented)) return null;
      if (expectedRow != null &&
          !snapshots.any(
            (snapshot) => snapshot.lines.any(
              (line) =>
                  line.sourceRow == sourceRow &&
                  line.sourceEndRow == expectedRow.sourceEndRow &&
                  line.text == expectedRow.text &&
                  line.wrapped == expectedRow.wrapped,
            ),
          )) {
        return null;
      }
      owners.add(block.id);
      final occurrence = occurrenceFor(block.id);
      if (occurrence == null) return null;
      result = occurrence;
    }
    return owners.length == 1 ? result : null;
  }

  /// Resolve an unlisted occurrence without scanning all historical output.
  /// Missing is affirmative evidence; errors/alternate-screen responses are not.
  CommandOccurrence? refreshOccurrenceOutput(String blockId) {
    final previous = occurrenceFor(blockId);
    if (previous == null) return null;
    final result = request({'id': blockId, 'offset': 0, 'limit': 1});
    final block = CommandBlock.fromJson(result?['block']);
    if (block != null) {
      final scope = _scopeFor(block);
      if (scope == null) return null;
      final next = CommandOccurrence.fromBlock(block, scope);
      _occurrences[next.id] = next;
      _trimOccurrences();
      notifyListeners();
      return next;
    }
    if (result?['missing'] == true) {
      final next = previous.withoutCurrentOutput(unavailable: true);
      _occurrences[next.id] = next;
      _trimOccurrences();
      notifyListeners();
      return next;
    }
    return previous;
  }

  void _updateOccurrences() {
    final current = <String>{};
    for (final block in _blocks) {
      final scope = _scopeFor(block);
      if (scope == null) continue;
      final occurrence = CommandOccurrence.fromBlock(block, scope);
      current.add(occurrence.id);
      _occurrences[occurrence.id] = occurrence;
    }
    for (final id in _occurrences.keys.toList()) {
      if (!current.contains(id)) {
        _occurrences[id] = _occurrences[id]!.withoutCurrentOutput();
      }
    }
    _trimOccurrences();
  }

  void _trimOccurrences() {
    while (_occurrences.length > maximumOccurrences.clamp(1, 4096)) {
      _occurrences.remove(_occurrences.keys.first);
    }
  }

  /// Defaults to one native session's history budget. A host that combines
  /// independently bounded sources may pass null, enforcing the budget on
  /// each source before returning the combined list.
  final int? maximumBlocks;
  List<CommandBlock> _blocks = const [];
  List<CommandBlock> get blocks => _blocks;
  final selected = <String>{};
  final bookmarks = <String>{};
  final collapsed = <String>{};
  final expandedOutput = <String>{};
  final filters = <String, CommandBlockFilter>{};
  final filtering = <String>{};
  final readingStates = <String, CommandBlockReadingState>{};
  final errors = <String, String>{};
  final _pages = <String, CommandBlock>{};
  final _appliedFilters = <String, CommandBlockFilter>{};
  String? activeId;
  String? _anchor;
  String? _signature;
  bool available = false;
  bool compact = false;
  bool dividers = true;
  bool stickyHeader = true;
  int revealRevision = 0;
  bool revealBottom = false;
  bool revealFocus = true;

  CommandBlock displayBlock(CommandBlock block) =>
      block.running ? block : _pages[block.id] ?? block;

  /// The condition behind the last successful result, even if the current
  /// draft is invalid or its reader has been closed and opened again.
  CommandBlockFilter? appliedFilter(String id) => _appliedFilters[id];
  CommandBlock? get active =>
      _blocks.where((b) => b.id == activeId).firstOrNull;

  void refresh() {
    final result = request(const {});
    final raw = result?['blocks'];
    final nextBlocks = List<CommandBlock>.unmodifiable([
      if (raw is List)
        for (final entry in raw.take(maximumBlocks ?? raw.length))
          if (CommandBlock.fromJson(entry) case final CommandBlock block) block,
    ]);
    final signature = jsonEncode([
      result,
      for (final block in nextBlocks)
        if (_scopeFor(block) case final scope?)
          [scope.sessionId, scope.sessionEpoch]
        else
          null,
    ]);
    if (_signature == signature) return;
    _signature = signature;
    final nextScopeIds = <String, String?>{
      for (final block in nextBlocks)
        block.id: switch (_scopeFor(block)) {
          final scope? => CommandOccurrence.fromBlock(block, scope).id,
          null => null,
        },
    };
    for (final id in nextScopeIds.keys) {
      if (_blockScopeIds.containsKey(id) &&
          _blockScopeIds[id] != nextScopeIds[id]) {
        // A reused presentation id does not inherit another session's output
        // page, filter, selection, or reading position.
        _pages.remove(id);
        _appliedFilters.remove(id);
        filters.remove(id);
        filtering.remove(id);
        readingStates.remove(id);
        selected.remove(id);
        bookmarks.remove(id);
        collapsed.remove(id);
        expandedOutput.remove(id);
        errors.remove(id);
        if (activeId == id) activeId = null;
        if (_anchor == id) _anchor = null;
      }
    }
    _blockScopeIds
      ..clear()
      ..addAll(nextScopeIds);
    available = result != null && result['alternateScreen'] != true;
    _blocks = nextBlocks;
    if (available) _updateOccurrences();
    final retained = _blocks.map((b) => b.id).toSet();
    selected.removeWhere((id) => !retained.contains(id));
    bookmarks.removeWhere((id) => !retained.contains(id));
    collapsed.removeWhere((id) => !retained.contains(id));
    expandedOutput.removeWhere((id) => !retained.contains(id));
    filtering.removeWhere((id) => !retained.contains(id));
    filters.removeWhere((id, _) => !retained.contains(id));
    readingStates.removeWhere((id, _) => !retained.contains(id));
    errors.removeWhere((id, _) => !retained.contains(id));
    _pages.removeWhere((id, _) => !retained.contains(id));
    _appliedFilters.removeWhere((id, _) => !retained.contains(id));
    if (!retained.contains(activeId)) activeId = null;
    if (!retained.contains(_anchor)) _anchor = null;
    for (final block in _blocks) {
      if (_pages[block.id] case final CommandBlock page
          when page.running ||
              block.running ||
              page.columns != block.columns ||
              page.totalLines != block.totalLines ||
              page.sourceLineCount != block.sourceLineCount ||
              page.segmented != block.segmented ||
              page.sourceLineBase != block.sourceLineBase ||
              page.evicted != block.evicted) {
        _load(block.id, offset: page.offset, notify: false);
      }
    }
    notifyListeners();
  }

  void select(
    String id, {
    bool extend = false,
    bool toggle = false,
    bool reveal = false,
    List<String>? orderedIds,
  }) {
    final candidates = _orderedBlocks(orderedIds);
    final index = candidates.indexWhere((b) => b.id == id);
    if (index < 0) return;
    if (orderedIds != null) selected.retainAll(orderedIds);
    final anchor = candidates.indexWhere((b) => b.id == _anchor);
    if (extend && anchor >= 0) {
      selected.clear();
      final a = index < anchor ? index : anchor;
      final b = index > anchor ? index : anchor;
      selected.addAll(candidates.sublist(a, b + 1).map((b) => b.id));
    } else {
      if (!toggle) selected.clear();
      if (!toggle || !selected.remove(id)) selected.add(id);
      _anchor = id;
    }
    activeId = id;
    if (reveal) {
      revealRevision++;
      revealBottom = false;
      revealFocus = true;
    }
    notifyListeners();
  }

  List<CommandBlock> _orderedBlocks(List<String>? ids) => ids == null
      ? _blocks
      : [for (final id in ids) ..._blocks.where((b) => b.id == id)];

  void move(
    int delta, {
    bool extend = false,
    bool bookmarked = false,
    List<String>? orderedIds,
  }) {
    final ordered = _orderedBlocks(orderedIds);
    final candidates = bookmarked
        ? ordered.where((b) => bookmarks.contains(b.id)).toList()
        : ordered;
    if (candidates.isEmpty) return;
    final index = candidates.indexWhere((b) => b.id == activeId);
    final next = index < 0
        ? (delta < 0 ? candidates.length - 1 : 0)
        : (index + delta).clamp(0, candidates.length - 1);
    select(
      candidates[next].id,
      extend: extend,
      reveal: true,
      orderedIds: orderedIds,
    );
  }

  void clearSelection() {
    selected.clear();
    activeId = null;
    _anchor = null;
    notifyListeners();
  }

  void toggleBookmark(String id) {
    if (!bookmarks.remove(id)) bookmarks.add(id);
    notifyListeners();
  }

  void toggleCollapsed(String id) {
    if (!collapsed.remove(id)) collapsed.add(id);
    notifyListeners();
  }

  void toggleExpandedOutput(String id) {
    if (!expandedOutput.remove(id)) expandedOutput.add(id);
    notifyListeners();
  }

  void setAppearance({bool? compact, bool? dividers, bool? stickyHeader}) {
    this.compact = compact ?? this.compact;
    this.dividers = dividers ?? this.dividers;
    this.stickyHeader = stickyHeader ?? this.stickyHeader;
    notifyListeners();
  }

  void reveal(String id, {bool bottom = false, bool focus = true}) {
    activeId = id;
    revealBottom = bottom;
    revealFocus = focus;
    revealRevision++;
    notifyListeners();
  }

  void toggleFilter(String id) {
    if (filtering.remove(id)) {
      _pages.remove(id);
      _appliedFilters.remove(id);
      errors.remove(id);
    } else {
      filtering.add(id);
      expandedOutput.add(id);
      _load(id, notify: false);
    }
    notifyListeners();
  }

  void filter(String id, CommandBlockFilter value) {
    filters[id] = value;
    filtering.add(id);
    expandedOutput.add(id);
    _load(id);
  }

  void page(String id, int offset) => _load(id, offset: offset);

  /// Opens an unfiltered range using its source identity. The native retained
  /// floor can move between metadata and page requests, so validate the actual
  /// page before publishing it and retry only a bounded number of times.
  bool pageRange(String id, CommandBlockReadRange range) {
    final page = readRange(id, range);
    if (page != null) {
      _pages[id] = page;
      filtering.remove(id);
      _appliedFilters.remove(id);
      errors.remove(id);
      notifyListeners();
      return true;
    }
    errors[id] = 'Output is no longer available';
    notifyListeners();
    return false;
  }

  /// Reads a source range without changing presentation state. Native offsets
  /// count owned output rows; source indices may skip a nested command's rows.
  CommandBlock? readRange(
    String id,
    CommandBlockReadRange range, {
    int? limit,
  }) {
    var current = CommandBlock.fromJson(
      request({'id': id, 'offset': 0, 'limit': 1})?['block'],
    );
    for (var attempt = 0; attempt < 3; attempt++) {
      final offset = range.resolveStart(current);
      if (offset == null) break;
      final page = CommandBlock.fromJson(
        request({
          'id': id,
          'offset': offset,
          if (current!.segmented) 'sourceLine': offset,
          'limit': ?limit,
        })?['block'],
      );
      if (page == null) {
        current = CommandBlock.fromJson(
          request({'id': id, 'offset': 0, 'limit': 1})?['block'],
        );
        continue;
      }
      if (range.resolveStart(page) == offset &&
          page.lines.firstOrNull?.index == offset) {
        return page;
      }
      current = page;
    }
    return null;
  }

  void _load(String id, {int offset = 0, bool notify = true}) {
    final result = request({
      'id': id,
      'offset': offset,
      if (filtering.contains(id)) ...?filters[id]?.toJson(),
    });
    if (result?['error'] case final String error) {
      errors[id] = error;
    } else if (CommandBlock.fromJson(result?['block'])
        case final CommandBlock block) {
      errors.remove(id);
      _pages[id] = block;
      if (filtering.contains(id)) {
        _appliedFilters[id] = filters[id] ?? const CommandBlockFilter();
      } else {
        _appliedFilters.remove(id);
      }
    } else {
      errors[id] = 'Output is no longer available';
    }
    if (notify) notifyListeners();
  }

  /// Copy traverses retained source output. Filters and selections must be
  /// explicitly requested; a preview window or fold never limits default copy.
  Future<String> outputText(
    String id, {
    CommandBlockFilter? filter,
    TerminalSelection? selection,
    bool blockSelection = false,
    int? expectedSourceBase,
  }) async {
    final buffer = StringBuffer();
    var offset = filter == null ? selection?.startRow ?? 0 : 0;
    var joinNext = false;
    var previousLine = -1;
    var sourceBase = expectedSourceBase;
    int? columns;
    var foundStart = selection == null;
    var foundEnd = selection == null;
    var firstPage = true;
    while (offset >= 0) {
      final result = request({
        'id': id,
        'offset': offset,
        if (firstPage && selection != null && filter == null)
          'sourceLine': selection.startRow,
        ...?filter?.toJson(),
      });
      final block = CommandBlock.fromJson(result?['block']);
      if (block == null) throw StateError('Output is no longer available');
      final first = block.lines.firstOrNull;
      final base = first?.sourceRow == null
          ? null
          : first!.sourceRow! - first.index;
      if ((columns != null && columns != block.columns) ||
          (sourceBase != null && base != sourceBase)) {
        throw StateError('Output changed while copying; try again');
      }
      columns = block.columns;
      sourceBase = base;
      if (firstPage && selection != null && filter == null && block.segmented) {
        offset = block.offset;
      }
      firstPage = false;
      for (final row in block.lines) {
        if (selection != null &&
            (row.index < selection.startRow || row.index > selection.endRow)) {
          continue;
        }
        foundStart |= selection == null || row.index == selection.startRow;
        foundEnd |= selection == null || row.index == selection.endRow;
        if (previousLine >= 0 && (!joinNext || row.index != previousLine + 1)) {
          buffer.writeln();
        }
        if (selection == null) {
          buffer.write(row.text);
        } else {
          final cells = TerminalTextCells.fromText(row.text);
          final start = blockSelection || row.index == selection.startRow
              ? selection.startCol
              : 0;
          final end = blockSelection || row.index == selection.endRow
              ? selection.endCol
              : cells.cellCount;
          buffer.write(cells.sliceColumns(start, end));
        }
        joinNext = row.wrapped && !(selection != null && blockSelection);
        previousLine = row.index;
      }
      if (buffer.length > 16 * 1024 * 1024) {
        throw StateError('Output exceeds the 16 MiB clipboard limit');
      }
      if (selection != null && foundEnd) break;
      final next = block.nextOffset;
      if (next == null) break;
      if (next <= offset) throw StateError('Output changed while copying');
      offset = next;
      await Future<void>.delayed(Duration.zero);
    }
    if (!foundStart || !foundEnd) {
      throw StateError('The selected range is no longer available');
    }
    return buffer.toString();
  }
}
