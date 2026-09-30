part of 'command_blocks_view.dart';

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
    required this.onSaveRow,
    this.initialRow,
    this.onOpenLinkTarget,
  });
  final CommandBlockController controller;
  final String id;
  final TerminalFontConfig font;
  final bool chinese;
  final bool followTail;
  final double? initialRow;
  final ValueChanged<double> onSaveRow;
  final ValueChanged<TerminalLinkTarget>? onOpenLinkTarget;
  @override
  State<_CommandBlockReader> createState() => _CommandBlockReaderState();
}

class _CommandBlockReaderState extends State<_CommandBlockReader> {
  static const _pageRows = 128;
  final _scroll = ScrollController();
  final _horizontal = ScrollController();
  final _pages = <int, CommandBlock?>{};
  CommandBlock? _block;
  Size? _cell;
  double _rowHeight = 1;
  late bool _followTail;
  bool _hasMoreBelow = false;
  String t(String en, String zh) => widget.chinese ? zh : en;
  CommandBlockController get c => widget.controller;
  bool get _filtered => c.filtering.contains(widget.id);
  int get _lineCount =>
      _filtered ? _block?.matchingLines ?? 0 : _block?.totalLines ?? 0;
  bool get _showLatest =>
      !_followTail &&
      _lineCount > 0 &&
      (_hasMoreBelow || _block?.running == true);
  int? _sourceBase(CommandBlock? block) {
    final first = block?.lines.firstOrNull;
    return first?.sourceRow == null ? null : first!.sourceRow! - first.index;
  }

  @override
  void initState() {
    super.initState();
    _followTail = widget.followTail;
    _readMetadata();
    _scroll.addListener(() {
      widget.onSaveRow(_scroll.offset / _rowHeight);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _updateScrollStatus(),
      );
    });
    c.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_followTail) {
        _tail();
      } else if (widget.initialRow case final double row) {
        _restoreRow(row);
      }
    });
  }

  void _readMetadata() {
    final source = c.blocks.where((b) => b.id == widget.id).firstOrNull;
    _block = source == null ? null : c.displayBlock(source);
  }

  void _changed() {
    if (!mounted) return;
    final old = _block;
    _readMetadata();
    _pages.clear();
    final previousBase = _sourceBase(old);
    final nextBase = _sourceBase(_block);
    final row =
        !_filtered &&
            !_followTail &&
            _scroll.hasClients &&
            previousBase != null &&
            nextBase != null &&
            previousBase != nextBase
        ? _scroll.offset / _rowHeight + previousBase - nextBase
        : null;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_followTail) {
        _tail();
      } else if (row != null) {
        _restoreRow(row);
      }
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
    final more = _scroll.position.extentAfter > .1;
    if (more != _hasMoreBelow) setState(() => _hasMoreBelow = more);
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
      final row = _scroll.hasClients
          ? _scroll.offset / _rowHeight
          : widget.initialRow ?? 0;
      setState(() => _cell = cell);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_followTail) {
          _tail();
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
      c.toggleFilter(widget.id);
      return;
    }
    try {
      final text = action == 'command'
          ? block.command
          : await c.outputText(widget.id);
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

  @override
  void dispose() {
    if (_scroll.hasClients) widget.onSaveRow(_scroll.offset / _rowHeight);
    c.removeListener(_changed);
    _scroll.dispose();
    _horizontal.dispose();
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
    final textSize = tokens.resultStyle.fontSize ?? 14;
    // The full header and filter reserve several lines of UI text. Include
    // their growth in the height budget; fixed control heights alone miss
    // short windows at accessibility text sizes.
    final textGrowth = (scale.scale(textSize) - textSize).clamp(
      0,
      double.infinity,
    );
    return Scaffold(
      key: const Key('block-reader'),
      backgroundColor: tokens.surface,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => _body(
            tokens,
            block,
            width,
            compact:
                constraints.maxHeight <
                tokens.controlHeight * 7 + textGrowth * 6,
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
  }) {
    final failed = block?.exitCode != null && block?.exitCode != 0;
    final status = block?.running == true
        ? t('Running', '运行中')
        : t('Exit ${block?.exitCode ?? "?"}', '退出码 ${block?.exitCode ?? "?"}');
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
                  vertical: compact ? 4 : 8,
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
                        child: Text(
                          block?.command ?? t('Command output', '命令输出'),
                          maxLines: compact ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: tokens.resultStyle.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
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
                    PopupMenuButton<String>(
                      key: const Key('block-reader-actions'),
                      tooltip: t('Block actions', '命令块操作'),
                      icon: Icon(Icons.more_horiz, color: tokens.muted),
                      onSelected: _action,
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'command',
                          child: Text(t('Copy command', '复制命令')),
                        ),
                        PopupMenuItem(
                          value: 'output',
                          child: Text(t('Copy output', '复制输出')),
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
                    ],
                  ),
                ),
            ],
          ),
        ),
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
          child: block == null || _lineCount == 0
              ? Center(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      block == null
                          ? t('Output is no longer available', '输出已不可用')
                          : block.running
                          ? t('Waiting for output…', '等待输出…')
                          : _filtered && block.totalLines > 0
                          ? t('No matches', '无匹配结果')
                          : t('No output', '无输出'),
                      style: tokens.metadataStyle,
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
                              width: (block.columns * width + 32).clamp(
                                constraints.maxWidth,
                                double.infinity,
                              ),
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
                                        : CommandBlockTerminal(
                                            key: ValueKey(page.id),
                                            block: page,
                                            font: widget.font,
                                            scrollOutput: false,
                                            scrollHorizontally: false,
                                            requestLiveFocus: false,
                                            onMeasuredCellSizeChanged:
                                                _measured,
                                            onOpenLinkTarget:
                                                widget.onOpenLinkTarget,
                                          );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                ),
        ),
      ],
    );
  }
}
