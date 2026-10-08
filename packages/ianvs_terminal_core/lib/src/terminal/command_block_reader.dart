part of 'command_blocks_view.dart';

/// Opens retained native output without creating a second execution record.
Future<String?> showCommandBlockReader(
  BuildContext context, {
  required CommandBlockController controller,
  required String id,
  TerminalFontConfig font = const TerminalFontConfig(),
  bool chinese = false,
  double? initialRow,
  CommandBlockReadRange? initialRange,
  ValueChanged<CommandBlock>? onAttachRange,
  ValueChanged<TerminalLinkTarget>? onOpenLinkTarget,
}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  if (!context.mounted) return null;
  return Navigator.of(context).push<String>(
    _CommandBlockReaderRoute(
      allowBackGesture: Theme.of(context).platform != TargetPlatform.macOS,
      builder: (_) => _CommandBlockReader(
        controller: controller,
        id: id,
        font: font,
        chinese: chinese,
        initialRow: initialRow,
        initialRange: initialRange,
        followTail: false,
        onAttachRange: onAttachRange,
        onOpenLinkTarget: onOpenLinkTarget,
      ),
    ),
  );
}

class _CommandBlockReaderRoute extends MaterialPageRoute<String> {
  _CommandBlockReaderRoute({
    required super.builder,
    required this.allowBackGesture,
  });
  final bool allowBackGesture;

  // Cupertino transitions are also used on macOS. Their edge swipe competes
  // with first-column mouse selection and releases the reader's keyboard focus.
  @override
  bool get popGestureEnabled => allowBackGesture && super.popGestureEnabled;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => MediaQuery.disableAnimationsOf(context)
      ? child
      : super.buildTransitions(context, animation, secondaryAnimation, child);
}

/// A single scroll position for a block's retained output. Native pages are
/// loaded by row on demand; reaching a page boundary never replaces the page
/// the user is reading or resets the gesture.
class _CommandBlockReader extends StatefulWidget {
  const _CommandBlockReader({
    required this.controller,
    required this.id,
    required this.font,
    required this.chinese,
    required this.followTail,
    this.initialRow,
    this.initialRange,
    this.onOpenLinkTarget,
    this.onAttachRange,
  });
  final CommandBlockController controller;
  final String id;
  final TerminalFontConfig font;
  final bool chinese;
  final bool followTail;
  final double? initialRow;
  final CommandBlockReadRange? initialRange;
  final ValueChanged<TerminalLinkTarget>? onOpenLinkTarget;
  final ValueChanged<CommandBlock>? onAttachRange;
  @override
  State<_CommandBlockReader> createState() => _CommandBlockReaderState();
}

class _CommandBlockReaderState extends State<_CommandBlockReader> {
  static const _pageRows = 128;
  final _scroll = _ReaderScrollController();
  final _horizontal = ScrollController();
  final _selection = SelectionController();
  final GlobalKey _outputKey = GlobalKey();
  final _pages = <int, CommandBlock?>{};
  CommandBlock? _block;
  Size? _cell;
  double _rowHeight = 1;
  late bool _followTail;
  bool _hasMoreBelow = false;
  String? _displayFilter;
  String t(String en, String zh) => widget.chinese ? zh : en;
  CommandBlockController get c => widget.controller;
  bool get _filtered => _displayFilter != null;
  int get _lineCount =>
      _filtered ? _block?.matchingLines ?? 0 : _block?.totalLines ?? 0;
  bool get _showLatest =>
      !_rangeUnavailable &&
      !_followTail &&
      _lineCount > 0 &&
      (_hasMoreBelow || _block?.running == true);
  int? _sourceBase(CommandBlock? block) => block?.sourceLineBase;
  bool _restoringPosition = false;
  bool _selectionRebuildScheduled = false;
  late final _ReaderFind _find = _ReaderFind(c.request);
  final _findFocus = FocusNode();
  bool _finding = false;
  bool _jumpOnFind = false;
  double _gutterWidth = 48;
  (int, int)? _visibleRange;
  late bool _useSavedFilter = widget.initialRange == null;
  CommandBlock? _rangeBlock;
  bool get _rangeUnavailable =>
      widget.initialRange != null &&
      widget.initialRange!.resolveStart(_rangeBlock) == null;
  double? get _initialRow => widget.initialRange == null
      ? widget.initialRow
      : widget.initialRange!.resolveStart(_rangeBlock)?.toDouble();
  int get _lineNumberOffset =>
      widget.initialRange?.sourceLineBase != null &&
          _rangeBlock?.sourceLineBase != null
      ? _rangeBlock!.sourceLineBase! - widget.initialRange!.sourceLineBase!
      : 0;

  void _scanFind({bool jump = false, int? retainIndex}) {
    _jumpOnFind = jump;
    unawaited(
      _find.scan(
        id: widget.id,
        count: _lineCount,
        sourceBase: _sourceBase(_block),
        filter: _filtered ? c.appliedFilter(widget.id) : null,
        retainIndex: retainIndex,
      ),
    );
  }

  void _findChanged() {
    if (!mounted) return;
    setState(() {});
    if (_jumpOnFind && !_find.busy) {
      _jumpOnFind = false;
      _moveFind(1);
    }
  }

  void _moveFind(int delta) {
    if (_find.busy || _find.rows.isEmpty) return;
    setState(() {
      _followTail = false;
      _find.active = _find.active < 0
          ? (delta < 0 ? _find.rows.length - 1 : 0)
          : (_find.active + delta) % _find.rows.length;
    });
    _restoreRow(_find.rows[_find.active].ordinal.toDouble());
  }

  void _openFind() {
    setState(() => _finding = true);
    _findFocus.requestFocus();
  }

  void _closeFind() {
    _findFocus.unfocus();
    _jumpOnFind = false;
    _find.clear();
    setState(() => _finding = false);
  }

  int get _selectedCount {
    final selection = _selection.selection;
    if (selection == null ||
        (selection.startRow == selection.endRow &&
            selection.startCol == selection.endCol)) {
      return 0;
    }
    return _filtered
        ? _matchingOffset(selection.endRow + 1) -
              _matchingOffset(selection.startRow)
        : selection.endRow - selection.startRow + 1;
  }

  CommandBlockReadingState? _captureReadingState() {
    if (!_scroll.hasClients || _lineCount == 0) return null;
    final row = ((_scroll.offset - 8) / _rowHeight).clamp(0, _lineCount - 1);
    final index = row.floor();
    final page = _pages[index ~/ _pageRows];
    final line = page?.lines.elementAtOrNull(index % _pageRows);
    if (line == null) return null;
    return CommandBlockReadingState(
      lineIndex: line.index,
      sourceRow: line.sourceRow,
      pixelOffset: _scroll.offset - 8 - index * _rowHeight,
      horizontalOffset: _horizontal.hasClients ? _horizontal.offset : 0,
      selection: _selection.selection,
      selectionSourceBase: _sourceBase(_block),
      blockSelection: _selection.isBlockSelection,
    );
  }

  void _saveReadingState() {
    if (_restoringPosition) return;
    final state = _captureReadingState();
    if (state != null) c.readingStates[widget.id] = state;
  }

  int _displayIndex(CommandBlockReadingState saved) {
    final base = _sourceBase(_block);
    final nativeIndex = saved.sourceRow != null && base != null
        ? saved.sourceRow! - base
        : saved.lineIndex;
    if (!_filtered) {
      return nativeIndex.clamp(0, (_lineCount - 1).clamp(0, 1 << 53));
    }
    return _matchingOffset(
      nativeIndex,
    ).clamp(0, (_lineCount - 1).clamp(0, 1 << 53));
  }

  int _matchingOffset(int nativeIndex) {
    // Selection endpoints usually belong to an already painted page. Resolve
    // there before asking native filtering to scan history during a drag.
    for (final entry in _pages.entries) {
      final rows = entry.value?.lines;
      if (rows == null ||
          rows.isEmpty ||
          nativeIndex < rows.first.index ||
          nativeIndex > rows.last.index + 1) {
        continue;
      }
      final offset = rows.indexWhere((row) => row.index >= nativeIndex);
      return entry.key * _pageRows + (offset < 0 ? rows.length : offset);
    }
    // Filter offsets address matching rows; source indices address original
    // rows. Locate the original line (or the next retained match) without
    // loading the entire output or treating the filtered ordinal as evidence.
    var low = 0;
    var high = _lineCount;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      final result = CommandBlock.fromJson(
        c.request({
          'id': widget.id,
          'offset': middle,
          'limit': 1,
          ...?c.appliedFilter(widget.id)?.toJson(),
        })?['block'],
      );
      final line = result?.lines.firstOrNull;
      if (line == null) break;
      if (line.index < nativeIndex) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  void _restoreSelection(CommandBlockReadingState saved) {
    final selection = saved.selection;
    final base = _sourceBase(_block);
    final delta = base != null && saved.selectionSourceBase != null
        ? saved.selectionSourceBase! - base
        : 0;
    if (selection == null ||
        selection.startRow + delta < 0 ||
        selection.endRow + delta >= (_block?.totalLines ?? 0)) {
      _selection.clear();
      return;
    }
    _selection.setSelection(
      TerminalSelection(
        startRow: selection.startRow + delta,
        startCol: selection.startCol,
        endRow: selection.endRow + delta,
        endCol: selection.endCol,
      ),
      mode: saved.blockSelection ? SelectionMode.block : SelectionMode.linear,
    );
  }

  void _restoreReadingState(CommandBlockReadingState saved) {
    if (!mounted || !_scroll.hasClients || _lineCount == 0) return;
    _restoringPosition = true;
    _scroll.jumpTo(
      (8 + _displayIndex(saved) * _rowHeight + saved.pixelOffset).clamp(
        0,
        _scroll.position.maxScrollExtent,
      ),
    );
    if (_horizontal.hasClients) {
      _horizontal.jumpTo(
        saved.horizontalOffset.clamp(0, _horizontal.position.maxScrollExtent),
      );
    }
    _restoreSelection(saved);
    _restoringPosition = false;
  }

  @override
  void initState() {
    super.initState();
    _followTail = widget.followTail;
    _readMetadata();
    final saved = c.readingStates[widget.id];
    _selection.addListener(_selectionChanged);
    _scroll.addListener(() {
      _saveReadingState();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _updateScrollStatus(),
      );
    });
    c.addListener(_changed);
    _find.addListener(_findChanged);
    _horizontal.addListener(_horizontalChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_followTail) {
        _tail();
      } else if (_initialRow case final double row) {
        _restoreRow(
          widget.initialRange != null && _filtered
              ? _matchingOffset(row.toInt()).toDouble()
              : row,
        );
      } else if (saved != null) {
        _restoreReadingState(saved);
      }
    });
  }

  void _selectionChanged() {
    final selection = _selection.selection;
    if (!_restoringPosition &&
        selection != null &&
        (selection.startRow != selection.endRow ||
            selection.startCol != selection.endCol)) {
      _followTail = false;
    }
    _saveReadingState();
    if (!mounted) return;
    // A refreshed child frame can update an active drag while the list is
    // building. Keep selection immediate but defer rebuilding its ancestor.
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_selectionRebuildScheduled) return;
      _selectionRebuildScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _selectionRebuildScheduled = false;
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  void _horizontalChanged() {
    if (mounted) setState(() {});
  }

  void _attachSelection() {
    final selection = _selection.selection;
    if (selection == null ||
        (selection.startRow == selection.endRow &&
            selection.startCol == selection.endCol)) {
      return;
    }
    final rows = <TerminalRow>[];
    final base = _sourceBase(_block);
    var offset = _filtered
        ? _matchingOffset(selection.startRow)
        : selection.startRow;
    CommandBlock? source;
    var available = true;
    while (rows.length <= 500) {
      final page = CommandBlock.fromJson(
        c.request({
          'id': widget.id,
          'offset': offset,
          'limit':
              (_filtered ? 501 - rows.length : selection.endRow - offset + 1)
                  .clamp(1, _pageRows),
          if (_filtered) ...?c.appliedFilter(widget.id)?.toJson(),
        })?['block'],
      );
      if (page == null || _sourceBase(page) != base || page.offset != offset) {
        available = false;
        break;
      }
      source ??= page;
      if (page.lines.isEmpty) break;
      for (final row in page.lines) {
        if (row.index > selection.endRow) break;
        if (row.index >= selection.startRow) rows.add(row);
      }
      if (page.lines.last.index >= selection.endRow) break;
      offset += page.lines.length;
      if (offset >= (_filtered ? page.matchingLines : page.totalLines)) break;
    }
    if (rows.length > 500) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('Select at most 500 lines.', '一次最多附加 500 行。')),
        ),
      );
      return;
    }
    if (!available ||
        source == null ||
        rows.isEmpty ||
        (!_filtered &&
            rows.length != selection.endRow - selection.startRow + 1)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('The selected range is no longer available.', '所选范围已不可用，请重新选择。'),
          ),
        ),
      );
      return;
    }
    // The native filter uses original row cells. Preserve their indices and
    // source identities; never fill gaps with output the user could not see.
    widget.onAttachRange?.call(
      CommandBlock(
        id: source.id,
        command: source.command,
        cwd: source.cwd,
        exitCode: source.exitCode,
        submissionId: source.submissionId,
        contextId: source.contextId,
        startedAt: source.startedAt,
        finishedAt: source.finishedAt,
        running: source.running,
        evicted: source.evicted,
        lines: List.unmodifiable(rows),
        totalLines: source.totalLines,
        matchingLines: rows.length,
        offset: rows.first.index,
        columns: source.columns,
      ),
    );
    Navigator.of(context).pop();
  }

  void _readMetadata() {
    if (widget.initialRange != null) {
      // Resolve the quote after the route opens, not before the asynchronous
      // keyboard dismissal. A saved display filter must not hide its target.
      _rangeBlock = CommandBlock.fromJson(
        c.request({'id': widget.id, 'offset': 0, 'limit': 1})?['block'],
      );
      _displayFilter = _useSavedFilter && c.filtering.contains(widget.id)
          ? c.appliedFilter(widget.id)?.toJson().toString() ?? ''
          : null;
      _block = _filtered
          ? CommandBlock.fromJson(
              c.request({
                'id': widget.id,
                'offset': 0,
                'limit': 1,
                ...?c.appliedFilter(widget.id)?.toJson(),
              })?['block'],
            )
          : _rangeBlock;
      return;
    }
    final source = c.blocks.where((b) => b.id == widget.id).firstOrNull;
    _block = source == null ? null : c.displayBlock(source);
    _displayFilter = c.filtering.contains(widget.id)
        ? c.appliedFilter(widget.id)?.toJson().toString() ?? ''
        : null;
  }

  void _changed() {
    if (!mounted) return;
    final old = _block;
    final oldFilter = _displayFilter;
    final saved = _captureReadingState();
    _readMetadata();
    _pages.clear();
    final previousBase = _sourceBase(old);
    final nextBase = _sourceBase(_block);
    final oldFindIndex = _find.activeRow;
    if (saved != null &&
        (previousBase != nextBase || oldFilter != _displayFilter)) {
      _restoringPosition = true;
      if (!_followTail && _scroll.hasClients && _lineCount > 0) {
        _scroll.correctBy(
          8 +
              _displayIndex(saved) * _rowHeight +
              saved.pixelOffset -
              _scroll.offset,
        );
      }
      _restoreSelection(saved);
      _restoringPosition = false;
    }
    setState(() {});
    if (_finding &&
        (previousBase != nextBase ||
            oldFilter != _displayFilter ||
            old?.totalLines != _block?.totalLines ||
            old?.visibleOutput != _block?.visibleOutput)) {
      _scanFind(
        retainIndex: oldFindIndex == null
            ? null
            : oldFindIndex + (previousBase ?? 0) - (nextBase ?? 0),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_followTail) {
        _tail();
      } else if (saved == null &&
          widget.initialRange != null &&
          !_rangeUnavailable) {
        final row = _initialRow;
        if (row != null) {
          _restoreRow(
            _filtered ? _matchingOffset(row.toInt()).toDouble() : row,
          );
        }
      }
      _saveReadingState();
    });
  }

  void _restoreRow(double row) {
    if (!mounted || !_scroll.hasClients) return;
    _scroll.jumpTo(
      (row * _rowHeight).clamp(0, _scroll.position.maxScrollExtent),
    );
  }

  void _tail() {
    if (!mounted || !_followTail || !_scroll.hasClients) return;
    final end = _scroll.position.maxScrollExtent;
    if ((_scroll.offset - end).abs() > .1) _scroll.jumpTo(end);
  }

  void _updateScrollStatus() {
    if (!mounted || !_scroll.hasClients) return;
    _saveReadingState();
    final more = _scroll.position.extentAfter > .1;
    final first = ((_scroll.offset - 8) / _rowHeight).floor().clamp(
      0,
      (_lineCount - 1).clamp(0, 1 << 53),
    );
    final last =
        ((_scroll.offset + _scroll.position.viewportDimension - 8) / _rowHeight)
            .ceil()
            .clamp(0, _lineCount) -
        1;
    final range = (first, last);
    if (more != _hasMoreBelow || range != _visibleRange) {
      setState(() {
        _hasMoreBelow = more;
        _visibleRange = range;
      });
    }
  }

  bool _metricsChanged(ScrollMetricsNotification notification) {
    // The vertical list is inside the horizontal viewport, so its metrics
    // notification has already crossed a viewport by the time it arrives here.
    if (notification.metrics.axis == Axis.vertical) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tail();
        _updateScrollStatus();
      });
    }
    return false;
  }

  bool _scrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis == Axis.vertical &&
        _followTail &&
        (notification is ScrollStartNotification &&
                notification.dragDetails != null ||
            notification is UserScrollNotification &&
                notification.direction != ScrollDirection.idle)) {
      setState(() => _followTail = false);
    }
    return false;
  }

  void _measured(Size cell) {
    if (_cell == cell) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _cell == cell) return;
      final saved = _captureReadingState();
      final row = _scroll.hasClients
          ? _scroll.offset / _rowHeight
          : _initialRow ?? 0;
      setState(() => _cell = cell);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_followTail) {
          _tail();
        } else if (saved != null) {
          _restoreReadingState(saved);
        } else {
          _restoreRow(row);
        }
      });
    });
  }

  CommandBlock? _page(int index) {
    if (_pages.containsKey(index)) return _pages[index];
    final start = index * _pageRows;
    final end = (start + _pageRows).clamp(0, _lineCount);
    final rows = <TerminalRow>[];
    final links = <TerminalHyperlinkRange>[];
    var offset = start;
    CommandBlock? source;
    // Native replies have both a row and a byte budget. A wide ANSI page may
    // need more than one bounded reply to fill this fixed-height list item.
    while (offset < end) {
      final result = c.request({
        'id': widget.id,
        'offset': offset,
        'limit': end - offset,
        if (_filtered) ...?c.appliedFilter(widget.id)?.toJson(),
      });
      source = CommandBlock.fromJson(result?['block']);
      if (source == null || source.lines.isEmpty) break;
      if (widget.initialRange != null &&
          source.sourceLineBase != _rangeBlock?.sourceLineBase) {
        return _pages[index] = null;
      }
      final incoming = source.lines
          .skip((offset - source.offset).clamp(0, source.lines.length))
          .take(end - offset)
          .toList();
      if (incoming.isEmpty) break;
      final skip = (offset - source.offset).clamp(0, source.lines.length);
      for (final link in source.hyperlinks) {
        if (link.row >= skip && link.row < skip + incoming.length) {
          links.add(
            TerminalHyperlinkRange(
              row: rows.length + link.row - skip,
              startCol: link.startCol,
              endCol: link.endCol,
              uri: link.uri,
              protocolId: link.protocolId,
            ),
          );
        }
      }
      rows.addAll(incoming);
      offset += incoming.length;
      if (source.nextOffset == null && offset < end) break;
    }
    // Bound cached native text independently of the length of scrollback.
    if (_pages.length >= 24) _pages.remove(_pages.keys.first);
    return _pages[index] = source == null || rows.isEmpty
        ? null
        : CommandBlock(
            id: '${widget.id}-reader-$index',
            command: source.command,
            cwd: source.cwd,
            columns: source.columns,
            lines: rows,
            hyperlinks: links,
            totalLines: rows.length,
            matchingLines: rows.length,
          );
  }

  Future<void> _action(String action) async {
    final block = _block;
    if (block == null) return;
    if (action == 'reinput') {
      Navigator.of(context).pop(block.command);
      return;
    }
    if (action == 'filter') {
      if (!_useSavedFilter) {
        _useSavedFilter = true;
        if (c.filtering.contains(widget.id)) {
          _changed();
          return;
        }
      }
      c.toggleFilter(widget.id);
      return;
    }
    final selection = action == 'selection' ? _selection.selection : null;
    if (action == 'selection' &&
        (selection == null ||
            (selection.startRow == selection.endRow &&
                selection.startCol == selection.endCol))) {
      return;
    }
    try {
      final text = action == 'command'
          ? block.command
          : await c.outputText(
              widget.id,
              filter:
                  _filtered && (action == 'filtered' || action == 'selection')
                  ? c.appliedFilter(widget.id)
                  : null,
              selection: selection,
              blockSelection: _selection.isBlockSelection,
              expectedSourceBase: selection == null ? null : _sourceBase(block),
            );
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t('Copied', '已复制'))));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('Output is no longer available', '输出已不可用'))),
        );
      }
    }
  }

  Future<void> _copySelection() => _action('selection');

  bool _canScrollSelection(int deltaLines) {
    if (!_scroll.hasClients || _lineCount == 0) return false;
    return deltaLines > 0
        ? _scroll.offset > _scroll.position.minScrollExtent
        : deltaLines < 0 && _scroll.offset < _scroll.position.maxScrollExtent;
  }

  void _scrollSelectionLines(int deltaLines) {
    if (!_canScrollSelection(deltaLines)) return;
    _followTail = false;
    _scroll.jumpTo(
      (_scroll.offset - deltaLines * _rowHeight).clamp(
        _scroll.position.minScrollExtent,
        _scroll.position.maxScrollExtent,
      ),
    );
  }

  Future<String> _captureSelectionText() async {
    final selection = _selection.selection;
    if (selection == null || _block == null) return '';
    try {
      return await c.outputText(
        widget.id,
        filter: _filtered ? c.appliedFilter(widget.id) : null,
        selection: selection,
        blockSelection: _selection.isBlockSelection,
        expectedSourceBase: _sourceBase(_block),
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('Output is no longer available', '输出已不可用'))),
        );
      }
      return '';
    }
  }

  TerminalSelectionTarget? _selectionHitTest(Offset globalPosition) {
    final box = _outputKey.currentContext?.findRenderObject();
    final cell = _cell;
    if (box is! RenderBox ||
        !box.hasSize ||
        box.size.height <= 0 ||
        cell == null ||
        !_scroll.hasClients ||
        _lineCount == 0) {
      return null;
    }
    final local = box.globalToLocal(globalPosition);
    final ordinal =
        ((local.dy.clamp(0, box.size.height - .001) + _scroll.offset - 8) /
                _rowHeight)
            .floor()
            .clamp(0, _lineCount - 1);
    final page = _page(ordinal ~/ _pageRows);
    final row = ordinal % _pageRows;
    if (page == null || row >= page.lines.length) return null;
    // The selection's end column is exclusive. Allow the right edge to include
    // the final cell even when the output fills the entire terminal width.
    final col = ((local.dx - 16 - _gutterWidth) / cell.width).floor().clamp(
      0,
      page.columns,
    );
    final origin = box.localToGlobal(Offset.zero);
    // The pointer remains owned by its starting page during a drag. Resolve
    // against the enclosing reader, preserving original indices after filters.
    return (
      cell: TerminalCellPosition(row, col),
      globalBounds: origin & box.size,
      globalCaretRect: Rect.fromLTWH(
        origin.dx + 16 + _gutterWidth + col * cell.width,
        origin.dy + 8 + ordinal * _rowHeight - _scroll.offset,
        1,
        _rowHeight,
      ),
      frame: TerminalFrameDiff(
        rows: [
          for (var i = 0; i < page.lines.length; i++)
            TerminalRow(
              index: i,
              text: page.lines[i].text,
              wrapped: page.lines[i].wrapped,
              sourceRow: page.lines[i].index,
              sourceEndRow: page.lines[i].index,
            ),
        ],
        cursor: const TerminalCursor(row: 0, col: 0, visible: false),
        viewportRows: page.lines.length,
        viewportCols: page.columns,
        dirtyRanges: const [],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
      ),
    );
  }

  @override
  void dispose() {
    _saveReadingState();
    c.removeListener(_changed);
    _scroll.dispose();
    _horizontal.dispose();
    _selection.removeListener(_selectionChanged);
    _selection.dispose();
    _find.removeListener(_findChanged);
    _find.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ComposerTheme.of(context);
    final block = _block;
    final scale = MediaQuery.textScalerOf(context);
    _rowHeight =
        _cell?.height ?? scale.scale(widget.font.size) * widget.font.lineHeight;
    final width = _cell?.width ?? scale.scale(widget.font.size) * .61;
    _gutterWidth =
        ((_block?.totalLines ?? 0) + _lineNumberOffset).toString().length *
            width +
        24;
    final textSize = tokens.resultStyle.fontSize ?? 14;
    // The full header and filter reserve several lines of UI text. Include
    // their growth in the height budget; fixed control heights alone miss
    // short windows at accessibility text sizes.
    final textGrowth = (scale.scale(textSize) - textSize).clamp(
      0,
      double.infinity,
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openFind,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openFind,
        if (_finding)
          const SingleActivator(LogicalKeyboardKey.escape): _closeFind,
      },
      child: Scaffold(
        key: const Key('block-reader'),
        backgroundColor: tokens.surface,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          minimum: EdgeInsets.only(top: tokens.readerTopInset),
          child: LayoutBuilder(
            builder: (context, constraints) => _body(
              tokens,
              block,
              width,
              showActionLabels: constraints.maxWidth >= 720,
              compact:
                  constraints.maxHeight <
                  tokens.controlHeight * 7 + textGrowth * 6,
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(
    ComposerTheme tokens,
    CommandBlock? block,
    double width, {
    required bool compact,
    required bool showActionLabels,
  }) {
    final failed = block?.exitCode != null && block?.exitCode != 0;
    final status = block == null
        ? t('Output unavailable', '输出已不可用')
        : block.running
        ? t('Running', '运行中')
        : t('Exit ${block.exitCode ?? "?"}', '退出码 ${block.exitCode ?? "?"}');
    final historyNotice = t(
      'Earlier output has left scrollback',
      '较早的输出已超出滚动历史保留范围',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: tokens.divider)),
          ),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: compact ? 0 : 8,
                ),
                child: Row(
                  children: [
                    BackButton(
                      key: const Key('block-reader-close'),
                      color: tokens.foreground,
                    ),
                    Expanded(
                      child: Tooltip(
                        message: compact
                            ? '${block?.command ?? ""}\n${block?.cwd ?? ""}\n$status'
                            : block?.command ?? '',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              block?.command ?? t('Command output', '命令输出'),
                              maxLines: compact ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: tokens.resultStyle.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (compact && block != null)
                              _CommandBlockElapsed(
                                block: block,
                                style: tokens.metadataStyle,
                                chinese: widget.chinese,
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (compact && block?.evicted == true)
                      Tooltip(
                        key: const Key('block-reader-history-notice'),
                        message: '$status\n$historyNotice',
                        triggerMode: TooltipTriggerMode.tap,
                        child: SizedBox.square(
                          dimension: tokens.controlHeight,
                          child: Icon(
                            failed ? Icons.error_outline : Icons.info_outline,
                            size: 18,
                            color: failed ? tokens.error : tokens.muted,
                          ),
                        ),
                      )
                    else if (compact && block != null) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: status,
                        child: Icon(
                          block.running
                              ? Icons.schedule
                              : failed
                              ? Icons.error_outline
                              : Icons.check,
                          size: 16,
                          color: failed ? tokens.error : tokens.muted,
                        ),
                      ),
                    ],
                    if (block != null && _lineCount > 0)
                      // Keep the title width stable when scrolling toggles the
                      // action, so revealing it cannot reflow the command.
                      SizedBox.square(
                        dimension: tokens.controlHeight,
                        child: _showLatest
                            ? IconButton(
                                key: const Key('block-reader-latest'),
                                tooltip: block.running
                                    ? t('Resume following output', '继续跟随输出')
                                    : t('Latest output', '回到最新'),
                                onPressed: () {
                                  setState(() => _followTail = true);
                                  WidgetsBinding.instance.addPostFrameCallback(
                                    (_) => _tail(),
                                  );
                                },
                                icon: Icon(
                                  Icons.vertical_align_bottom,
                                  size: 20,
                                  color: tokens.muted,
                                ),
                              )
                            : null,
                      ),
                    if (showActionLabels)
                      TextButton.icon(
                        key: const Key('block-reader-find'),
                        onPressed: _rangeUnavailable ? null : _openFind,
                        icon: const Icon(Icons.search, size: 18),
                        label: Text(t('Find', '查找')),
                        style: TextButton.styleFrom(
                          foregroundColor: tokens.muted,
                        ),
                      )
                    else
                      IconButton(
                        key: const Key('block-reader-find'),
                        tooltip: t('Find in output', '查找输出'),
                        onPressed: _rangeUnavailable ? null : _openFind,
                        icon: Icon(Icons.search, color: tokens.muted),
                      ),
                    PopupMenuButton<String>(
                      popUpAnimationStyle: ComposerTheme.overlayAnimation(
                        context,
                      ),
                      key: const Key('block-reader-actions'),
                      enabled: block != null,
                      tooltip: t('Block actions', '命令块操作'),
                      icon: showActionLabels
                          ? null
                          : Icon(Icons.more_horiz, color: tokens.muted),
                      onSelected: _action,
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'command',
                          child: Text(t('Copy command', '复制命令')),
                        ),
                        PopupMenuItem(
                          key: const Key('block-reader-copy-output'),
                          value: 'output',
                          child: Text(
                            t('Copy all retained output', '复制全部保留输出'),
                          ),
                        ),
                        if (_filtered)
                          PopupMenuItem(
                            key: const Key('block-reader-copy-filtered'),
                            value: 'filtered',
                            child: Text(t('Copy filtered output', '复制过滤结果')),
                          ),
                        if (_selection.selection case final selection?
                            when selection.startRow != selection.endRow ||
                                selection.startCol != selection.endCol)
                          PopupMenuItem(
                            key: const Key('block-reader-copy-selection'),
                            value: 'selection',
                            child: Text(t('Copy selected text', '复制所选文本')),
                          ),
                        PopupMenuItem(
                          value: 'reinput',
                          child: Text(
                            t('Insert into Composer', '放入 Composer 编辑'),
                          ),
                        ),
                        CheckedPopupMenuItem(
                          value: 'filter',
                          checked: _filtered,
                          enabled: block?.running == false,
                          child: Text(t('Filter output', '过滤输出')),
                        ),
                      ],
                      child: showActionLabels
                          ? Padding(
                              padding: const EdgeInsets.all(8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.more_horiz,
                                    color: tokens.muted,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    t('More', '更多'),
                                    style: tokens.actionStyle.copyWith(
                                      color: tokens.muted,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
              if (!compact)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          block?.cwd ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tokens.metadataStyle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        status,
                        style: tokens.metadataStyle.copyWith(
                          color: failed ? tokens.error : tokens.muted,
                        ),
                      ),
                      if (block != null) ...[
                        const SizedBox(width: 8),
                        _CommandBlockElapsed(
                          block: block,
                          style: tokens.metadataStyle,
                          chinese: widget.chinese,
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (_finding) _findBar(tokens, compact: compact),
        if (_filtered)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _BlockFilterEditor(
              value: c.filters[widget.id] ?? const CommandBlockFilter(),
              chinese: widget.chinese,
              error: c.errors[widget.id],
              compact: compact,
              onChanged: (value) => c.filter(widget.id, value),
              onClose: () => c.toggleFilter(widget.id),
            ),
          ),
        if (!compact && block?.evicted == true)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(historyNotice, style: tokens.metadataStyle),
          ),
        Expanded(
          child: block == null || _lineCount == 0 || _rangeUnavailable
              ? Center(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _rangeUnavailable
                          ? t(
                              'The cited output range is no longer available',
                              '引用的输出范围已不可读取',
                            )
                          : block == null
                          ? t('Output is no longer available', '输出已不可用')
                          : block.running
                          ? t('Waiting for output…', '等待输出…')
                          : _filtered && block.totalLines > 0
                          ? t('No matches', '无匹配结果')
                          : t('No output', '无输出'),
                      style: tokens.metadataStyle,
                      key: _rangeUnavailable
                          ? const Key('block-reader-evidence-unavailable')
                          : null,
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) =>
                      NotificationListener<ScrollMetricsNotification>(
                        onNotification: _metricsChanged,
                        child: NotificationListener<ScrollNotification>(
                          onNotification: _scrollNotification,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            controller: _horizontal,
                            child: SizedBox(
                              key: _outputKey,
                              width: (block.columns * width + 32 + _gutterWidth)
                                  .clamp(constraints.maxWidth, double.infinity),
                              height: constraints.maxHeight,
                              child: Scrollbar(
                                controller: _scroll,
                                child: ListView.builder(
                                  key: const Key('block-reader-scroll'),
                                  controller: _scroll,
                                  primary: false,
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    8,
                                    16,
                                    12,
                                  ),
                                  itemCount: (_lineCount / _pageRows).ceil(),
                                  itemExtentBuilder: (index, _) =>
                                      (_lineCount - index * _pageRows).clamp(
                                        0,
                                        _pageRows,
                                      ) *
                                      _rowHeight,
                                  itemBuilder: (context, index) {
                                    final page = _page(index);
                                    return page == null
                                        ? Text(
                                            t(
                                              'Output is no longer available',
                                              '输出已不可用',
                                            ),
                                            style: tokens.metadataStyle,
                                          )
                                        : _readerPage(page, index, tokens);
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                ),
        ),
        if (!_rangeUnavailable) _rangeBar(tokens, compact: compact),
      ],
    );
  }

  Widget _readerPage(CommandBlock page, int index, ComposerTheme tokens) =>
      Stack(
        children: [
          Positioned.fill(
            left: _gutterWidth,
            child: CommandBlockTerminal(
              key: ValueKey(page.id),
              block: page,
              font: widget.font,
              scrollOutput: false,
              scrollHorizontally: false,
              requestLiveFocus: false,
              selectionController: _selection,
              highlightedRow: _finding ? _find.activeRow : null,
              onCopySelection: _copySelection,
              selectionHitTest: _selectionHitTest,
              canScrollSelection: _canScrollSelection,
              onScrollLines: _scrollSelectionLines,
              captureSelectionText: _captureSelectionText,
              onMeasuredCellSizeChanged: _measured,
              onOpenLinkTarget: widget.onOpenLinkTarget,
            ),
          ),
          Positioned(
            // Counter the shared horizontal viewport's offset. The gutter stays
            // visible without introducing a second vertical scroll controller.
            left: (_horizontal.hasClients ? _horizontal.offset : 0) - 16,
            top: 0,
            bottom: 0,
            width: _gutterWidth + 16,
            child: ExcludeSemantics(
              child: AbsorbPointer(
                child: ColoredBox(
                  key: ValueKey('reader-line-number-background-$index'),
                  color: tokens.surface,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: CustomPaint(
                      key: ValueKey('reader-line-numbers-$index'),
                      painter: _ReaderLineNumbers(
                        rows: page.lines,
                        lineNumberOffset: _lineNumberOffset,
                        rowHeight: _rowHeight,
                        style: tokens.metadataStyle.copyWith(
                          fontFamily: widget.font.family,
                        ),
                        scaler: MediaQuery.textScalerOf(context),
                        divider: tokens.divider,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );

  Widget _findBar(ComposerTheme tokens, {required bool compact}) {
    final count = _find.rows.length;
    final summary = _find.busy
        ? t('Searching…', '正在查找…')
        : _find.unavailable
        ? t('Output changed; search again', '输出已变化，请重新查找')
        : _find.editor.text.isEmpty
        ? t('Find in displayed output', '在当前显示的输出中查找')
        : t(
            'Matching lines ${_find.active + 1}/$count',
            '匹配行 ${_find.active + 1}/$count',
          );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('block-reader-find-query'),
                  controller: _find.editor,
                  focusNode: _findFocus,
                  style: tokens.actionStyle,
                  decoration: InputDecoration(
                    hintText: t('Find text', '查找文字'),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    suffixIconConstraints: BoxConstraints.tightFor(
                      width: tokens.controlHeight,
                      height: tokens.controlHeight,
                    ),
                    suffixIcon: _find.editor.text.isEmpty
                        ? null
                        : IconButton(
                            key: const Key('block-reader-find-clear'),
                            tooltip: t('Clear search', '清空查找文字'),
                            onPressed: () {
                              _jumpOnFind = false;
                              _find.clear();
                              _findFocus.requestFocus();
                            },
                            icon: const Icon(Icons.cancel_outlined, size: 18),
                          ),
                  ),
                  onChanged: (_) => _scanFind(jump: true),
                  onSubmitted: (_) => _moveFind(1),
                ),
              ),
              IconButton(
                key: const Key('block-reader-find-previous'),
                tooltip: t('Previous matching line', '上一匹配行'),
                onPressed: count == 0 || _find.busy
                    ? null
                    : () => _moveFind(-1),
                icon: const Icon(Icons.keyboard_arrow_up),
              ),
              IconButton(
                key: const Key('block-reader-find-next'),
                tooltip: t('Next matching line', '下一匹配行'),
                onPressed: count == 0 || _find.busy ? null : () => _moveFind(1),
                icon: const Icon(Icons.keyboard_arrow_down),
              ),
              IconButton(
                key: const Key('block-reader-find-close'),
                tooltip: t('Close find', '关闭查找'),
                onPressed: _closeFind,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (!compact)
            Semantics(
              liveRegion: !_find.busy,
              child: Text(
                summary,
                key: const Key('block-reader-find-count'),
                style: tokens.metadataStyle,
              ),
            ),
        ],
      ),
    );
  }

  Widget _rangeBar(ComposerTheme tokens, {required bool compact}) {
    TerminalRow? row(int ordinal) => ordinal < 0 || ordinal >= _lineCount
        ? null
        : _page(
            ordinal ~/ _pageRows,
          )?.lines.elementAtOrNull(ordinal % _pageRows);
    final start = row(_visibleRange?.$1 ?? 0)?.index;
    final end = row(_visibleRange?.$2 ?? 0)?.index;
    final count = _selectedCount;
    final total = _block?.totalLines ?? 0;
    final summary = start == null || end == null
        ? t('$total retained lines', '保留 $total 行')
        : t(
            'Lines ${start + 1 + _lineNumberOffset}–${end + 1 + _lineNumberOffset} · $total retained',
            '第 ${start + 1 + _lineNumberOffset}–${end + 1 + _lineNumberOffset} 行 · 保留 $total 行',
          );
    final findStatus = _find.unavailable
        ? t('Output changed', '输出已变化')
        : _find.busy
        ? t('Searching…', '查找中…')
        : t(
            'Matches ${_find.active + 1}/${_find.rows.length}',
            '匹配 ${_find.active + 1}/${_find.rows.length}',
          );
    final rangeText = Text(
      '${_filtered ? '$summary · ${t('Filtered', '已过滤')}' : summary}'
      '${compact && _finding ? ' · $findStatus' : ''}',
      key: const Key('block-reader-range'),
      maxLines: compact ? 2 : null,
      overflow: compact ? TextOverflow.ellipsis : null,
      style: tokens.metadataStyle,
    );
    final selectionControl = count > 0 && widget.onAttachRange != null
        ? TextButton.icon(
            key: const Key('block-reader-attach'),
            onPressed: _attachSelection,
            style: TextButton.styleFrom(
              minimumSize: Size(0, tokens.controlHeight),
            ),
            icon: const Icon(Icons.attach_file, size: 18),
            label: Text(
              compact
                  ? t('Attach $count lines', '附加 $count 行')
                  : t(
                      'Attach $count selected lines to AI',
                      '将所选 $count 行附给 AI',
                    ),
            ),
          )
        : count > 0
        ? Text(
            t('$count selected lines', '已选 $count 行'),
            style: tokens.metadataStyle,
          )
        : null;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.divider)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: compact ? 0 : 4,
        ),
        child: compact
            ? Row(
                children: [
                  Expanded(child: rangeText),
                  if (selectionControl != null) ...[
                    const SizedBox(width: 12),
                    selectionControl,
                  ],
                ],
              )
            : Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [rangeText, ?selectionControl],
              ),
      ),
    );
  }
}

class _ReaderScrollController extends ScrollController {
  void correctBy(double delta) {
    if (hasClients) (position as _ReaderScrollPosition).correction += delta;
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _ReaderScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  );
}

class _ReaderScrollPosition extends ScrollPositionWithSingleContext {
  _ReaderScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
  });
  double correction = 0;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final delta = correction;
    correction = 0;
    final corrected = (pixels + delta).clamp(minScrollExtent, maxScrollExtent);
    if (delta.abs() > .1 && (corrected - pixels).abs() > .1) {
      // Correct in layout instead of jumping after the frame: a retained-line
      // shift must not cancel the user's current drag or ballistic activity.
      correctPixels(corrected);
      return false;
    }
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }
}
