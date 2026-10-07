import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'command_block.dart';
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
  CommandBlockController({required this.request, this.maximumBlocks = 128})
    : assert(
        maximumBlocks == null || maximumBlocks > 0,
        'maximumBlocks must be positive, or null for a host-bounded list',
      );
  final CommandBlockRequest request;

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
    final signature = jsonEncode(result);
    if (_signature == signature) return;
    _signature = signature;
    available = result != null && result['alternateScreen'] != true;
    _blocks = List.unmodifiable([
      if (raw is List)
        for (final entry in raw.take(maximumBlocks ?? raw.length))
          if (CommandBlock.fromJson(entry) case final CommandBlock block) block,
    ]);
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

  void reveal(String id, {bool bottom = false}) {
    activeId = id;
    revealBottom = bottom;
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
    while (offset >= 0) {
      final result = request({
        'id': id,
        'offset': offset,
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
