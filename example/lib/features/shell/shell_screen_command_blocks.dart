part of 'shell_screen.dart';

const int shellCommandBlockPreviewMaxRows = 8;
const int shellCommandBlockLiveTerminalMaxRows = 60;
const int shellCommandBlockLiveTerminalPaddingRows = 3;

typedef ShellCommandBlockLiveTerminalBuilder =
    Widget Function(BuildContext context, ShellCommandBlockOverlayItem block);
typedef ShellCommandBlockActionCallback =
    void Function(ShellCommandBlockOverlayItem block, Rect anchorRect);
typedef ShellCommandBlockCallback =
    void Function(ShellCommandBlockOverlayItem block);

@visibleForTesting
int shellCommandBlockLiveTerminalDisplayRows(int actualRows) {
  final normalizedRows = math.max(1, actualRows);
  if (normalizedRows >= shellCommandBlockLiveTerminalMaxRows) {
    return shellCommandBlockLiveTerminalMaxRows;
  }
  return math.min(
    shellCommandBlockLiveTerminalMaxRows,
    normalizedRows + shellCommandBlockLiveTerminalPaddingRows,
  );
}

class ShellCommandBlocksOverlay extends StatefulWidget {
  const ShellCommandBlocksOverlay({
    super.key,
    required this.viewModel,
    required this.rowHeight,
    this.colors = terminal.TerminalViewportColors.light,
    this.font = const terminal.TerminalFontConfig(),
    this.cursor = const terminal.TerminalCursorConfig(),
    this.contentPadding = EdgeInsets.zero,
    this.liveTerminalRows = 0,
    this.liveTerminalBuilder,
    this.onOpenBlockActions,
    this.onSelectBlock,
    this.onToggleBlockBookmark,
  });

  final ShellCommandBlocksOverlayViewModel viewModel;
  final double rowHeight;
  final terminal.TerminalViewportColors colors;
  final terminal.TerminalFontConfig font;
  final terminal.TerminalCursorConfig cursor;
  final EdgeInsetsGeometry contentPadding;
  final int liveTerminalRows;
  final ShellCommandBlockLiveTerminalBuilder? liveTerminalBuilder;
  final ShellCommandBlockActionCallback? onOpenBlockActions;
  final ShellCommandBlockCallback? onSelectBlock;
  final ShellCommandBlockCallback? onToggleBlockBookmark;

  @override
  State<ShellCommandBlocksOverlay> createState() =>
      _ShellCommandBlocksOverlayState();
}

class _ShellCommandBlocksOverlayState extends State<ShellCommandBlocksOverlay> {
  late final ScrollController _scrollController;
  final Map<String, _ShellCommandBlockFilterState> _filtersByBlockId = {};
  final Set<String> _editingFilterBlockIds = <String>{};

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleFilterEditor(String blockId) {
    setState(() {
      if (!_editingFilterBlockIds.remove(blockId)) {
        _editingFilterBlockIds.add(blockId);
      }
      _filtersByBlockId.putIfAbsent(
        blockId,
        () => const _ShellCommandBlockFilterState(),
      );
    });
  }

  void _updateFilter(String blockId, _ShellCommandBlockFilterState filter) {
    setState(() {
      _filtersByBlockId[blockId] = filter;
      if (filter.isActive) {
        _editingFilterBlockIds.add(blockId);
      }
    });
  }

  void _clearFilter(String blockId) {
    setState(() {
      _filtersByBlockId.remove(blockId);
      _editingFilterBlockIds.remove(blockId);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.viewModel.isEmpty) {
      return const SizedBox.shrink();
    }

    final palette = AppThemeTokens.of(context);
    final blocks = widget.viewModel.blocks.reversed.toList(growable: false);

    return Padding(
      padding: widget.contentPadding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 860.0;
          final maxHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 360.0;
          return Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                maxHeight: maxHeight,
              ),
              child: ClipRect(
                child: Scrollbar(
                  controller: _scrollController,
                  child: SingleChildScrollView(
                    key: const Key('shell-command-blocks-scroll-view'),
                    controller: _scrollController,
                    reverse: true,
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (
                          var index = 0;
                          index < blocks.length;
                          index += 1
                        ) ...[
                          if (index > 0) SizedBox(height: palette.spacing.xs),
                          _ShellCommandBlockChrome(
                            key: Key('shell-command-block-${blocks[index].id}'),
                            block: blocks[index],
                            filter:
                                _filtersByBlockId[blocks[index].id] ??
                                const _ShellCommandBlockFilterState(),
                            filterEditorVisible: _editingFilterBlockIds
                                .contains(blocks[index].id),
                            rowHeight: widget.rowHeight,
                            colors: widget.colors,
                            font: widget.font,
                            cursor: widget.cursor,
                            liveTerminalRows: widget.liveTerminalRows,
                            liveTerminalBuilder: widget.liveTerminalBuilder,
                            onOpenBlockActions: widget.onOpenBlockActions,
                            onSelectBlock: widget.onSelectBlock,
                            onToggleBlockBookmark: widget.onToggleBlockBookmark,
                            onToggleFilterEditor: _toggleFilterEditor,
                            onFilterChanged: _updateFilter,
                            onClearFilter: _clearFilter,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ShellCommandBlockChrome extends StatelessWidget {
  const _ShellCommandBlockChrome({
    super.key,
    required this.block,
    required this.filter,
    required this.filterEditorVisible,
    required this.rowHeight,
    required this.colors,
    required this.font,
    required this.cursor,
    required this.liveTerminalRows,
    required this.liveTerminalBuilder,
    required this.onOpenBlockActions,
    required this.onSelectBlock,
    required this.onToggleBlockBookmark,
    required this.onToggleFilterEditor,
    required this.onFilterChanged,
    required this.onClearFilter,
  });

  final ShellCommandBlockOverlayItem block;
  final _ShellCommandBlockFilterState filter;
  final bool filterEditorVisible;
  final double rowHeight;
  final terminal.TerminalViewportColors colors;
  final terminal.TerminalFontConfig font;
  final terminal.TerminalCursorConfig cursor;
  final int liveTerminalRows;
  final ShellCommandBlockLiveTerminalBuilder? liveTerminalBuilder;
  final ShellCommandBlockActionCallback? onOpenBlockActions;
  final ShellCommandBlockCallback? onSelectBlock;
  final ShellCommandBlockCallback? onToggleBlockBookmark;
  final ValueChanged<String> onToggleFilterEditor;
  final void Function(String blockId, _ShellCommandBlockFilterState filter)
  onFilterChanged;
  final ValueChanged<String> onClearFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette =
        theme.extension<AppThemeTokens>() ??
        AppThemeTokens.fallbackFor(theme.brightness);
    final statusColor = _statusColor(palette, block.status);
    final background = Color.alphaBlend(
      statusColor.withValues(alpha: block.active ? 0.14 : 0.08),
      palette.panelElevated,
    );
    final borderColor = block.active
        ? statusColor.withValues(alpha: 0.78)
        : palette.border.withValues(alpha: 0.58);
    final hasTerminalOutput = block.terminalRows.isNotEmpty;
    final inputLine = block.inputLine.trim().isEmpty
        ? block.command
        : block.inputLine;
    final metadata = <String>[
      if (block.cwd?.trim().isNotEmpty == true) block.cwd!.trim(),
      block.durationLabel,
      if (block.outputRangeLabel.trim().isNotEmpty) block.outputRangeLabel,
    ];
    final outputUsesLiveTerminal = block.outputUsesLiveTerminal;
    final showLiveTerminal =
        outputUsesLiveTerminal && liveTerminalBuilder != null;
    final hasTerminalSurface =
        showLiveTerminal || (hasTerminalOutput && !outputUsesLiveTerminal);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onSelectBlock == null ? null : () => onSelectBlock!(block),
      onSecondaryTapDown: onOpenBlockActions == null
          ? null
          : (details) => onOpenBlockActions!(
              block,
              details.globalPosition & const Size(1, 1),
            ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(palette.radius.sm),
        child: DecoratedBox(
          key: Key('shell-command-block-card-${block.id}'),
          decoration: BoxDecoration(
            color: background,
            border: Border.all(color: borderColor),
            boxShadow: block.active ? palette.elevation.floating : const [],
          ),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                width: block.active ? 4 : 3,
                child: ColoredBox(color: statusColor),
              ),
              Padding(
                padding: EdgeInsets.only(left: block.active ? 4 : 3),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        palette.spacing.lg,
                        palette.spacing.lg,
                        palette.spacing.lg,
                        palette.spacing.sm,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LayoutBuilder(
                            builder: (context, headerConstraints) {
                              final compactActions =
                                  headerConstraints.maxWidth < 300;
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  _ShellCommandBlockStatusDot(
                                    color: statusColor,
                                  ),
                                  SizedBox(width: palette.spacing.sm),
                                  Expanded(
                                    flex: 3,
                                    child: SizedBox(
                                      height: 44,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          inputLine,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          softWrap: false,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: palette.textPrimary,
                                                fontFamily: 'monospace',
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (!compactActions &&
                                      metadata.isNotEmpty) ...[
                                    SizedBox(width: palette.spacing.md),
                                    Flexible(
                                      flex: 2,
                                      child: _ShellCommandBlockInlineMetadata(
                                        labels: metadata,
                                        palette: palette,
                                      ),
                                    ),
                                  ],
                                  SizedBox(width: palette.spacing.sm),
                                  if (!compactActions &&
                                      onToggleBlockBookmark != null)
                                    _ShellCommandBlockToolbarButton(
                                      key: Key(
                                        'shell-command-block-bookmark-${block.id}',
                                      ),
                                      tooltip: block.bookmarked
                                          ? 'Remove bookmark'
                                          : 'Toggle bookmark',
                                      foregroundColor: block.bookmarked
                                          ? statusColor
                                          : palette.textMuted,
                                      onPressed: () =>
                                          onToggleBlockBookmark!(block),
                                      icon: Icon(
                                        block.bookmarked
                                            ? Icons.bookmark
                                            : Icons.bookmark_border,
                                        semanticLabel: 'Toggle bookmark',
                                      ),
                                    ),
                                  if (!compactActions)
                                    _ShellCommandBlockToolbarButton(
                                      key: Key(
                                        'shell-command-block-filter-${block.id}',
                                      ),
                                      tooltip: filter.isActive
                                          ? 'Edit block filter'
                                          : 'Filter block output',
                                      foregroundColor: filter.isActive
                                          ? statusColor
                                          : palette.textMuted,
                                      onPressed: () =>
                                          onToggleFilterEditor(block.id),
                                      icon: const Icon(
                                        Icons.filter_alt_outlined,
                                        semanticLabel: 'Filter block output',
                                      ),
                                    ),
                                  _ShellCommandBlockInfoButton(
                                    block: block,
                                    palette: palette,
                                    statusColor: statusColor,
                                  ),
                                  if (onOpenBlockActions != null) ...[
                                    SizedBox(width: palette.spacing.xs),
                                    Builder(
                                      builder: (buttonContext) {
                                        return _ShellCommandBlockToolbarButton(
                                          key: Key(
                                            'shell-command-block-actions-${block.id}',
                                          ),
                                          tooltip: 'Block actions',
                                          onPressed: () => onOpenBlockActions!(
                                            block,
                                            _globalRectForContext(
                                              buttonContext,
                                            ),
                                          ),
                                          foregroundColor: palette.textPrimary,
                                          icon: const Icon(
                                            Icons.more_vert,
                                            semanticLabel: 'Block actions',
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    if (filterEditorVisible)
                      _ShellCommandBlockFilterEditor(
                        blockId: block.id,
                        filter: filter,
                        statusColor: statusColor,
                        palette: palette,
                        onChanged: (updated) =>
                            onFilterChanged(block.id, updated),
                        onClear: () => onClearFilter(block.id),
                      ),
                    if (hasTerminalOutput && !outputUsesLiveTerminal)
                      _ShellCommandBlockTerminalOutput(
                        key: Key(
                          'shell-command-block-terminal-output-${block.id}',
                        ),
                        block: block,
                        rowHeight: rowHeight,
                        colors: colors,
                        font: font,
                        cursor: cursor,
                        filter: filter,
                      ),
                    if (showLiveTerminal)
                      _ShellCommandBlockLiveTerminalOutput(
                        key: Key(
                          'shell-command-block-live-terminal-output-${block.id}',
                        ),
                        block: block,
                        rowHeight: rowHeight,
                        liveTerminalRows: liveTerminalRows,
                        builder: liveTerminalBuilder!,
                      ),
                    if (hasTerminalSurface)
                      SizedBox(height: palette.spacing.sm),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(AppThemeTokens palette, ShellCommandBlockStatus status) {
    return switch (status) {
      ShellCommandBlockStatus.failed => palette.danger,
      ShellCommandBlockStatus.succeeded => palette.success,
      ShellCommandBlockStatus.running => palette.accent,
      ShellCommandBlockStatus.unknown => palette.textSubtle,
    };
  }
}

class _ShellCommandBlockToolbarButton extends StatelessWidget {
  const _ShellCommandBlockToolbarButton({
    super.key,
    required this.tooltip,
    required this.foregroundColor,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final Color foregroundColor;
  final VoidCallback? onPressed;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: foregroundColor,
        fixedSize: const Size.square(44),
        minimumSize: const Size.square(44),
        maximumSize: const Size.square(44),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      icon: icon,
    );
  }
}

class _ShellCommandBlockFilterEditor extends StatelessWidget {
  const _ShellCommandBlockFilterEditor({
    required this.blockId,
    required this.filter,
    required this.statusColor,
    required this.palette,
    required this.onChanged,
    required this.onClear,
  });

  final String blockId;
  final _ShellCommandBlockFilterState filter;
  final Color statusColor;
  final AppThemeTokens palette;
  final ValueChanged<_ShellCommandBlockFilterState> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = filter.isActive
        ? statusColor.withValues(alpha: 0.62)
        : palette.border.withValues(alpha: 0.58);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        palette.spacing.lg,
        0,
        palette.spacing.lg,
        palette.spacing.sm,
      ),
      child: DecoratedBox(
        key: Key('shell-command-block-filter-editor-$blockId'),
        decoration: BoxDecoration(
          color: palette.panel.withValues(alpha: 0.92),
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(palette.radius.sm),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: palette.spacing.sm,
            vertical: palette.spacing.xs,
          ),
          child: Row(
            children: [
              _ShellCommandBlockFilterToggle(
                tooltip: 'Regex',
                selected: filter.regex,
                icon: Icons.code,
                onPressed: () =>
                    onChanged(filter.copyWith(regex: !filter.regex)),
              ),
              _ShellCommandBlockFilterToggle(
                tooltip: 'Case sensitive',
                selected: filter.caseSensitive,
                icon: Icons.text_fields,
                onPressed: () => onChanged(
                  filter.copyWith(caseSensitive: !filter.caseSensitive),
                ),
              ),
              Expanded(
                child: TextFormField(
                  key: Key('shell-command-block-filter-query-$blockId'),
                  initialValue: filter.query,
                  maxLines: 1,
                  textInputAction: TextInputAction.search,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.textPrimary,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Filter output',
                    hintStyle: theme.textTheme.bodySmall?.copyWith(
                      color: palette.textSubtle,
                    ),
                  ),
                  onChanged: (value) =>
                      onChanged(filter.copyWith(query: value)),
                ),
              ),
              SizedBox(width: palette.spacing.xs),
              SizedBox(
                width: 56,
                child: TextFormField(
                  key: Key('shell-command-block-filter-context-$blockId'),
                  initialValue: filter.contextLines == 0
                      ? ''
                      : filter.contextLines.toString(),
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.textPrimary,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'ctx',
                    hintStyle: theme.textTheme.bodySmall?.copyWith(
                      color: palette.textSubtle,
                    ),
                  ),
                  onChanged: (value) => onChanged(
                    filter.copyWith(
                      contextLines: (int.tryParse(value) ?? 0)
                          .clamp(0, 99)
                          .toInt(),
                    ),
                  ),
                ),
              ),
              _ShellCommandBlockFilterToggle(
                tooltip: 'Invert',
                selected: filter.invert,
                icon: Icons.swap_vert,
                onPressed: () =>
                    onChanged(filter.copyWith(invert: !filter.invert)),
              ),
              IconButton(
                key: Key('shell-command-block-filter-clear-$blockId'),
                tooltip: 'Clear block filter',
                onPressed: onClear,
                icon: Icon(
                  Icons.close,
                  size: 18,
                  color: palette.textMuted,
                  semanticLabel: 'Clear block filter',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShellCommandBlockFilterToggle extends StatelessWidget {
  const _ShellCommandBlockFilterToggle({
    required this.tooltip,
    required this.selected,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final bool selected;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette =
        Theme.of(context).extension<AppThemeTokens>() ??
        AppThemeTokens.fallbackFor(Theme.of(context).brightness);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: selected ? palette.accent : palette.textMuted,
        fixedSize: const Size.square(36),
        minimumSize: const Size.square(36),
        maximumSize: const Size.square(36),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon, size: 18, semanticLabel: tooltip),
    );
  }
}

class _ShellCommandBlockLiveTerminalOutput extends StatelessWidget {
  const _ShellCommandBlockLiveTerminalOutput({
    super.key,
    required this.block,
    required this.rowHeight,
    required this.liveTerminalRows,
    required this.builder,
  });

  final ShellCommandBlockOverlayItem block;
  final double rowHeight;
  final int liveTerminalRows;
  final ShellCommandBlockLiveTerminalBuilder builder;

  @override
  Widget build(BuildContext context) {
    final viewportHeight =
        rowHeight *
        shellCommandBlockLiveTerminalDisplayRows(block.liveTerminalRows);
    final fullViewportHeight = rowHeight * math.max(1, liveTerminalRows);
    final verticalOffset = rowHeight * block.liveTerminalViewportRowOffset;

    return ClipRect(
      child: SizedBox(
        width: double.infinity,
        height: viewportHeight,
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: fullViewportHeight,
          maxHeight: fullViewportHeight,
          child: Transform.translate(
            offset: Offset(0, -verticalOffset),
            child: SizedBox(
              width: double.infinity,
              height: fullViewportHeight,
              child: builder(context, block),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellCommandBlockTerminalOutput extends StatefulWidget {
  const _ShellCommandBlockTerminalOutput({
    super.key,
    required this.block,
    required this.rowHeight,
    required this.colors,
    required this.font,
    required this.cursor,
    required this.filter,
  });

  final ShellCommandBlockOverlayItem block;
  final double rowHeight;
  final terminal.TerminalViewportColors colors;
  final terminal.TerminalFontConfig font;
  final terminal.TerminalCursorConfig cursor;
  final _ShellCommandBlockFilterState filter;

  @override
  State<_ShellCommandBlockTerminalOutput> createState() =>
      _ShellCommandBlockTerminalOutputState();
}

class _ShellCommandBlockTerminalOutputState
    extends State<_ShellCommandBlockTerminalOutput> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.filter.apply(widget.block.terminalRows);
    if (widget.filter.isActive && rows.isEmpty) {
      return _ShellCommandBlockFilterEmptyState(
        blockId: widget.block.id,
        rowHeight: widget.rowHeight,
      );
    }
    final rowCount = rows.length;
    final frame = terminal.TerminalFrameDiff(
      rows: rows,
      cursor: const terminal.TerminalCursor(row: 0, col: 0, visible: false),
      viewportRows: rowCount,
      viewportCols: math.max(1, widget.block.terminalViewportCols),
      dirtyRanges: [terminal.TerminalDirtyRange(start: 0, end: rowCount)],
      scrollbackOffset: 0,
      scrollbackMaxOffset: 0,
    );
    final contentHeight = math.max(
      widget.rowHeight,
      widget.rowHeight * rowCount,
    );
    final viewportHeight = math.min(
      contentHeight,
      widget.rowHeight * shellCommandBlockPreviewMaxRows,
    );

    return ClipRect(
      child: SizedBox(
        width: double.infinity,
        height: viewportHeight,
        child: Scrollbar(
          controller: _scrollController,
          child: SingleChildScrollView(
            key: Key(
              'shell-command-block-terminal-output-scroll-${widget.block.id}',
            ),
            controller: _scrollController,
            physics: const ClampingScrollPhysics(),
            child: SizedBox(
              width: double.infinity,
              height: contentHeight,
              child: terminal.TerminalFramePreview(
                frame: frame,
                colors: widget.colors,
                font: widget.font,
                cursor: widget.cursor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellCommandBlockFilterEmptyState extends StatelessWidget {
  const _ShellCommandBlockFilterEmptyState({
    required this.blockId,
    required this.rowHeight,
  });

  final String blockId;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    final palette =
        Theme.of(context).extension<AppThemeTokens>() ??
        AppThemeTokens.fallbackFor(Theme.of(context).brightness);
    return SizedBox(
      key: Key('shell-command-block-filter-empty-$blockId'),
      height: math.max(rowHeight * 2, 40),
      child: Center(
        child: Text(
          'No matching output',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: palette.textMuted,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}

class _ShellCommandBlockFilterState {
  const _ShellCommandBlockFilterState({
    this.query = '',
    this.regex = false,
    this.caseSensitive = false,
    this.invert = false,
    this.contextLines = 0,
  });

  final String query;
  final bool regex;
  final bool caseSensitive;
  final bool invert;
  final int contextLines;

  bool get isActive => query.trim().isNotEmpty;

  _ShellCommandBlockFilterState copyWith({
    String? query,
    bool? regex,
    bool? caseSensitive,
    bool? invert,
    int? contextLines,
  }) {
    return _ShellCommandBlockFilterState(
      query: query ?? this.query,
      regex: regex ?? this.regex,
      caseSensitive: caseSensitive ?? this.caseSensitive,
      invert: invert ?? this.invert,
      contextLines: contextLines ?? this.contextLines,
    );
  }

  List<terminal.TerminalRow> apply(List<terminal.TerminalRow> rows) {
    if (!isActive || rows.isEmpty) {
      return rows;
    }
    final matchedIndexes = <int>{};
    for (var index = 0; index < rows.length; index += 1) {
      final baseMatch = _matches(rows[index].text);
      final effectiveMatch = invert ? !baseMatch : baseMatch;
      if (!effectiveMatch) {
        continue;
      }
      if (invert || contextLines == 0) {
        matchedIndexes.add(index);
        continue;
      }
      final start = math.max(0, index - contextLines);
      final end = math.min(rows.length - 1, index + contextLines);
      for (var contextIndex = start; contextIndex <= end; contextIndex += 1) {
        matchedIndexes.add(contextIndex);
      }
    }
    final sortedIndexes = matchedIndexes.toList()..sort();
    return [
      for (
        var outputIndex = 0;
        outputIndex < sortedIndexes.length;
        outputIndex += 1
      )
        _reindexedRow(rows[sortedIndexes[outputIndex]], outputIndex),
    ];
  }

  bool _matches(String text) {
    final needle = query.trim();
    if (needle.isEmpty) {
      return true;
    }
    if (regex) {
      try {
        return RegExp(needle, caseSensitive: caseSensitive).hasMatch(text);
      } on FormatException {
        return false;
      }
    }
    if (caseSensitive) {
      return text.contains(needle);
    }
    return text.toLowerCase().contains(needle.toLowerCase());
  }

  terminal.TerminalRow _reindexedRow(terminal.TerminalRow row, int index) {
    return terminal.TerminalRow(
      index: index,
      text: row.text,
      wrapped: row.wrapped,
      modifiedAt: row.modifiedAt,
      styleRuns: row.styleRuns,
    );
  }
}

class _ShellCommandBlockInlineMetadata extends StatelessWidget {
  const _ShellCommandBlockInlineMetadata({
    required this.labels,
    required this.palette,
  });

  final List<String> labels;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          labels.join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: palette.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ShellCommandBlockInfoButton extends StatelessWidget {
  const _ShellCommandBlockInfoButton({
    required this.block,
    required this.palette,
    required this.statusColor,
  });

  final ShellCommandBlockOverlayItem block;
  final AppThemeTokens palette;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (buttonContext) {
        return IconButton(
          key: Key('shell-command-block-info-${block.id}'),
          tooltip: 'Block info',
          onPressed: () => showMenu<void>(
            context: buttonContext,
            position: _relativeRectForContext(buttonContext),
            items: [
              PopupMenuItem<void>(
                key: Key('shell-command-block-info-popover-${block.id}'),
                enabled: false,
                padding: EdgeInsets.zero,
                child: _ShellCommandBlockInfoPopover(
                  block: block,
                  palette: palette,
                  statusColor: statusColor,
                ),
              ),
            ],
          ),
          style: IconButton.styleFrom(
            foregroundColor: palette.textMuted,
            fixedSize: const Size.square(44),
            minimumSize: const Size.square(44),
            maximumSize: const Size.square(44),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          icon: const Icon(
            Icons.info_outline,
            size: 20,
            semanticLabel: 'Block info',
          ),
        );
      },
    );
  }
}

class _ShellCommandBlockInfoPopover extends StatelessWidget {
  const _ShellCommandBlockInfoPopover({
    required this.block,
    required this.palette,
    required this.statusColor,
  });

  final ShellCommandBlockOverlayItem block;
  final AppThemeTokens palette;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final rows = <_ShellCommandBlockInfoRow>[
      _ShellCommandBlockInfoRow(
        label: 'Status',
        value: block.statusLabel,
        color: statusColor,
      ),
      _ShellCommandBlockInfoRow(
        label: 'Output',
        value: block.outputUsesLiveTerminal
            ? 'Live terminal'
            : 'Output captured',
      ),
      if (block.showReplayAction)
        const _ShellCommandBlockInfoRow(
          label: 'Review',
          value: 'Replay context',
        ),
      if (block.showFailureSnapshotAction)
        const _ShellCommandBlockInfoRow(
          label: 'Failure',
          value: 'Failure snapshot',
        ),
      if (block.showDiffAction)
        const _ShellCommandBlockInfoRow(
          label: 'Compare',
          value: 'Previous run',
        ),
    ];

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
      child: Padding(
        padding: EdgeInsets.all(palette.spacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Block info',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: palette.spacing.sm),
            for (var index = 0; index < rows.length; index++) ...[
              if (index > 0) SizedBox(height: palette.spacing.xs),
              _ShellCommandBlockInfoLine(row: rows[index], palette: palette),
            ],
          ],
        ),
      ),
    );
  }
}

class _ShellCommandBlockInfoLine extends StatelessWidget {
  const _ShellCommandBlockInfoLine({required this.row, required this.palette});

  final _ShellCommandBlockInfoRow row;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            row.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: palette.textSubtle,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(width: palette.spacing.sm),
        Flexible(
          child: Text(
            row.value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: row.color ?? palette.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _ShellCommandBlockInfoRow {
  const _ShellCommandBlockInfoRow({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;
}

RelativeRect _relativeRectForContext(BuildContext context) {
  final overlay = Overlay.of(context).context.findRenderObject();
  final overlaySize = overlay is RenderBox
      ? overlay.size
      : MediaQuery.sizeOf(context);
  final overlayBounds = Offset.zero & overlaySize;
  if (overlay is! RenderBox) {
    return RelativeRect.fromRect(
      const Rect.fromLTWH(16, 16, 1, 1),
      overlayBounds,
    );
  }
  final anchorRect = _globalRectForContext(context);
  final topLeft = overlay.globalToLocal(anchorRect.topLeft);
  final bottomRight = overlay.globalToLocal(anchorRect.bottomRight);
  return RelativeRect.fromRect(
    Rect.fromPoints(topLeft, bottomRight),
    overlayBounds,
  );
}

class _ShellCommandCorrectionPanel extends StatelessWidget {
  const _ShellCommandCorrectionPanel({
    required this.correction,
    required this.palette,
    required this.onAccept,
    required this.onDismiss,
  });

  final CommandCorrection correction;
  final AppThemeTokens palette;
  final VoidCallback? onAccept;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final riskColor = _correctionRiskColor(palette, correction.riskLevel);
    return Material(
      key: const Key('shell-command-correction-panel'),
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.overlay.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(palette.radius.md),
          border: Border.all(color: riskColor.withValues(alpha: 0.44)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.auto_fix_high_rounded,
                  size: 18,
                  color: riskColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Suggested fix',
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(width: 8),
                        _CorrectionChip(
                          label: correction.source.label,
                          palette: palette,
                        ),
                        const SizedBox(width: 5),
                        _CorrectionChip(
                          label: correction.riskLevel.label,
                          palette: palette,
                          color: riskColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    SelectableText(
                      correction.command,
                      key: const Key('shell-command-correction-command'),
                      maxLines: 2,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.textPrimary,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      correction.reason,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: palette.textSubtle,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildCompactActionButton(
                key: const Key('shell-command-correction-accept'),
                tooltip: 'Insert correction',
                onPressed: onAccept,
                splashRadius: 17,
                iconSize: 18,
                icon: const Icon(Icons.keyboard_tab_rounded),
              ),
              _buildCompactActionButton(
                key: const Key('shell-command-correction-dismiss'),
                tooltip: 'Dismiss correction',
                onPressed: onDismiss,
                splashRadius: 17,
                iconSize: 18,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CorrectionChip extends StatelessWidget {
  const _CorrectionChip({
    required this.label,
    required this.palette,
    this.color,
  });

  final String label;
  final AppThemeTokens palette;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? palette.accent;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(palette.radius.sm),
        border: Border.all(color: chipColor.withValues(alpha: 0.26)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: chipColor,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

Color _correctionRiskColor(AppThemeTokens palette, CommandRiskLevel riskLevel) {
  return switch (riskLevel) {
    CommandRiskLevel.safe => palette.success,
    CommandRiskLevel.caution => palette.warning,
    CommandRiskLevel.destructive => palette.danger,
  };
}

class ShellCommandInputBar extends StatefulWidget {
  const ShellCommandInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onSubmitted,
    this.inputMode = UniversalInputMode.terminal,
    this.classifyInput,
    this.suggestionsForInput,
    this.suggestionDetailsForInput,
    this.suggestionsLoadingForInput,
    this.onGenerateCommandDrafts,
    this.commandCorrection,
    this.naturalLanguageUnavailableMessage =
        'Set DEEPSEEK_API_KEY to generate commands from natural language.',
    this.contextChips = const <String>[],
    this.contextOptions = const <UniversalInputToolOption>[],
    this.modelLabel = 'Local heuristic',
    this.availableModes = const <UniversalInputMode>{
      UniversalInputMode.auto,
      UniversalInputMode.terminal,
      UniversalInputMode.agent,
    },
    this.modelOptions = _universalInputModelOptions,
    this.agentRuntimeAdapter,
    this.agentContextSnapshot,
    this.agentPromptAction,
    this.readOnly = false,
    this.onModeChanged,
    this.onChanged,
    this.onContextSelected,
    this.onModelSelected,
    this.onOpenCommandSearch,
    this.onAcceptCommandCorrection,
    this.onDismissCommandCorrection,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final Future<bool> Function(String command) onSubmitted;
  final UniversalInputMode inputMode;
  final UniversalInputClassification Function(String text)? classifyInput;
  final List<String> Function(
    String text,
    UniversalInputClassification classification,
  )?
  suggestionsForInput;
  final Map<String, CommandDraft> Function(
    String text,
    UniversalInputClassification classification,
  )?
  suggestionDetailsForInput;
  final bool Function(String text, UniversalInputClassification classification)?
  suggestionsLoadingForInput;
  final Future<List<CommandDraft>> Function(
    String text,
    UniversalInputClassification classification,
  )?
  onGenerateCommandDrafts;
  final CommandCorrection? commandCorrection;
  final String naturalLanguageUnavailableMessage;
  final List<String> contextChips;
  final List<UniversalInputToolOption> contextOptions;
  final String modelLabel;
  final Set<UniversalInputMode> availableModes;
  final List<UniversalInputToolOption> modelOptions;
  final AgentRuntimeAdapter? agentRuntimeAdapter;
  final AgentContextSnapshot? agentContextSnapshot;
  final ShellAgentPromptAction? agentPromptAction;
  final bool readOnly;
  final ValueChanged<UniversalInputMode>? onModeChanged;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onContextSelected;
  final ValueChanged<String>? onModelSelected;
  final VoidCallback? onOpenCommandSearch;
  final ValueChanged<CommandCorrection>? onAcceptCommandCorrection;
  final VoidCallback? onDismissCommandCorrection;

  @override
  State<ShellCommandInputBar> createState() => _ShellCommandInputBarState();
}

class ShellAgentPromptAction {
  const ShellAgentPromptAction({required this.id, required this.prompt});

  final int id;
  final String prompt;
}

class _ShellCommandInputBarState extends State<ShellCommandInputBar> {
  static const _agentConversationId = 'shell-command-agent-conversation';

  int _activeSuggestionIndex = 0;
  final GlobalKey<PopupMenuButtonState<String>> _contextMenuKey =
      GlobalKey<PopupMenuButtonState<String>>();
  final GlobalKey<PopupMenuButtonState<String>> _slashMenuKey =
      GlobalKey<PopupMenuButtonState<String>>();
  late AgentRuntimeAdapter _agentRuntimeAdapter;
  late AgentConversation _agentConversation;
  StreamSubscription<AgentResponseEvent>? _agentResponseSubscription;
  String? _activeAgentRequestId;
  String? _activeAssistantMessageId;
  int _agentMessageSerial = 0;
  int _agentRequestSerial = 0;

  @override
  void initState() {
    super.initState();
    _agentRuntimeAdapter = widget.agentRuntimeAdapter ?? _defaultAgentRuntime();
    _agentConversation = AgentConversation.empty(
      id: _agentConversationId,
      title: 'Agent conversation',
      now: DateTime.now(),
    );
  }

  @override
  void didUpdateWidget(covariant ShellCommandInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.agentRuntimeAdapter != widget.agentRuntimeAdapter &&
        widget.agentRuntimeAdapter != null) {
      _agentRuntimeAdapter = widget.agentRuntimeAdapter!;
    }
    final nextAction = widget.agentPromptAction;
    if (nextAction != null &&
        oldWidget.agentPromptAction?.id != nextAction.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            widget.inputMode != UniversalInputMode.agent ||
            widget.agentPromptAction?.id != nextAction.id) {
          return;
        }
        _sendAgentMessage(nextAction.prompt);
      });
    }
  }

  @override
  void dispose() {
    unawaited(_agentResponseSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeTokens.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.commandCorrection != null) ...[
          _ShellCommandCorrectionPanel(
            correction: widget.commandCorrection!,
            palette: palette,
            onAccept: () => widget.onAcceptCommandCorrection?.call(
              widget.commandCorrection!,
            ),
            onDismiss: widget.onDismissCommandCorrection,
          ),
          const SizedBox(height: 8),
        ],
        DecoratedBox(
          key: const Key('shell-command-input-bar'),
          decoration: BoxDecoration(
            color: palette.overlay.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(palette.radius.lg),
            border: Border.all(color: palette.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              builder: (context, value, _) {
                final text = value.text;
                final classification = _classificationFor(text);
                final isAgentMode =
                    widget.inputMode == UniversalInputMode.agent;
                final suggestions = isAgentMode
                    ? const <String>[]
                    : _suggestionsFor(text, classification);
                final suggestionDetails = isAgentMode
                    ? const <String, CommandDraft>{}
                    : _suggestionDetailsFor(text, classification);
                final suggestionsLoading = isAgentMode
                    ? false
                    : _suggestionsLoadingFor(text, classification);
                final accent = _universalInputAccentColor(
                  palette,
                  classification,
                );
                final fieldHint = _universalInputFieldHint(
                  widget.inputMode,
                  classification,
                );
                final canSend = widget.enabled && text.trimRight().isNotEmpty;
                final effectiveActiveIndex = suggestions.isEmpty
                    ? -1
                    : _activeSuggestionIndex.clamp(0, suggestions.length - 1);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.contextChips.isNotEmpty) ...[
                      SizedBox(
                        height: 30,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final chip in widget.contextChips) ...[
                                _UniversalInputContextChip(
                                  label: _redactedAgentContextChipText(chip),
                                  palette: palette,
                                ),
                                const SizedBox(width: 5),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (isAgentMode) ...[
                      SizedBox(
                        key: const Key('shell-command-agent-conversation-pane'),
                        height: _agentConversationPaneHeight(),
                        child: AgentConversationPane(
                          conversation: _agentConversation,
                          contextChips: _agentConversationContextChips(),
                          compact: true,
                          onCancelStreaming: _activeAgentRequestId == null
                              ? null
                              : _cancelAgentResponse,
                          onReviewProposal: _reviewAgentProposal,
                          onInsertProposal: _insertAgentProposal,
                        ),
                      ),
                      if (_hasAgentContextActions()) ...[
                        const SizedBox(height: 8),
                        _buildAgentContextActionRow(palette),
                      ],
                      const SizedBox(height: 8),
                    ],
                    CallbackShortcuts(
                      bindings: {
                        const SingleActivator(
                          LogicalKeyboardKey.keyR,
                          meta: true,
                        ): _openCommandSearch,
                        const SingleActivator(
                          LogicalKeyboardKey.keyR,
                          control: true,
                        ): _openCommandSearch,
                      },
                      child: _UniversalInputAutocompleteField(
                        fieldKey: const Key('shell-command-input-field'),
                        controller: widget.controller,
                        focusNode: widget.focusNode,
                        enabled: widget.enabled,
                        autofocus: widget.enabled,
                        semanticLabel: isAgentMode
                            ? 'Agent message composer'
                            : 'Command input',
                        hintText: fieldHint,
                        suggestions: suggestions,
                        suggestionDetails: suggestionDetails,
                        suggestionsLoading: suggestionsLoading,
                        activeIndex: effectiveActiveIndex,
                        palette: palette,
                        maxLines: null,
                        maxHeight: 168,
                        suggestionLimit: 4,
                        suggestionKeyPrefix: 'shell-command-input',
                        textStyle: Theme.of(context).textTheme.bodyLarge
                            ?.copyWith(
                              color: palette.textPrimary,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w500,
                            ),
                        decoration: InputDecoration(
                          hintText: fieldHint,
                          isDense: true,
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                        onChanged: _handleTextChanged,
                        onPrevious: () =>
                            _moveSuggestion(-1, suggestions.length),
                        onNext: () => _moveSuggestion(1, suggestions.length),
                        onAcceptSuggestion: (suggestion) =>
                            _acceptSuggestion(suggestion, classification),
                        onSend: () => unawaited(
                          _submit(
                            context,
                            widget.controller.text,
                            classification,
                            _prioritizedSuggestions(
                              suggestions,
                              effectiveActiveIndex,
                            ),
                          ),
                        ),
                        onContextTrigger: () =>
                            _contextMenuKey.currentState?.showButtonMenu(),
                        onSlashTrigger: () =>
                            _slashMenuKey.currentState?.showButtonMenu(),
                        onAcceptCorrection: widget.commandCorrection == null
                            ? null
                            : _acceptCommandCorrection,
                        onDismissCorrection: widget.commandCorrection == null
                            ? null
                            : widget.onDismissCommandCorrection,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _UniversalInputModeSwitcher(
                          keyPrefix: 'shell-command-input',
                          mode: widget.inputMode,
                          availableModes: widget.availableModes,
                          palette: palette,
                          onModeChanged: _handleModeChanged,
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 24,
                          child: VerticalDivider(
                            color: palette.border,
                            width: 1,
                            thickness: 1,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _UniversalInputToolMenuButton(
                          key: const Key('shell-command-input-context'),
                          menuButtonKey: _contextMenuKey,
                          tooltip: 'Add context',
                          icon: Icons.alternate_email_rounded,
                          options: widget.contextOptions,
                          palette: palette,
                          onSelected: _handleContextSelected,
                        ),
                        _UniversalInputToolMenuButton(
                          key: const Key('shell-command-input-slash'),
                          menuButtonKey: _slashMenuKey,
                          tooltip: 'Slash commands',
                          icon: Icons.bolt_rounded,
                          options: _universalInputSlashCommandOptions,
                          palette: palette,
                          onSelected: _handleSlashCommandSelected,
                        ),
                        _buildCompactActionButton(
                          key: const Key('shell-command-input-previous'),
                          tooltip: 'Previous completion',
                          onPressed: suggestions.length < 2
                              ? null
                              : () => _moveSuggestion(-1, suggestions.length),
                          splashRadius: 16,
                          iconSize: 18,
                          icon: const Icon(Icons.keyboard_arrow_up_rounded),
                        ),
                        _buildCompactActionButton(
                          key: const Key('shell-command-input-next'),
                          tooltip: 'Next completion',
                          onPressed: suggestions.length < 2
                              ? null
                              : () => _moveSuggestion(1, suggestions.length),
                          splashRadius: 16,
                          iconSize: 18,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        ),
                        const Spacer(),
                        Flexible(
                          child: _UniversalInputStatusPill(
                            key: const Key(
                              'shell-command-input-detection-label',
                            ),
                            label: _universalInputStatusLabel(
                              widget.inputMode,
                              classification,
                            ),
                            accent: accent,
                            palette: palette,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: _UniversalInputModelMenuChip(
                            key: const Key('shell-command-input-model'),
                            keyPrefix: 'shell-command-input',
                            label: widget.modelLabel,
                            options: widget.modelOptions,
                            palette: palette,
                            onSelected: _handleModelSelected,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _buildCompactActionButton(
                          key: const Key('shell-command-run-button'),
                          tooltip: _universalInputSendTooltip(
                            widget.inputMode,
                            classification,
                          ),
                          onPressed: canSend
                              ? () => unawaited(
                                  _submit(
                                    context,
                                    text,
                                    classification,
                                    _prioritizedSuggestions(
                                      suggestions,
                                      effectiveActiveIndex,
                                    ),
                                  ),
                                )
                              : null,
                          splashRadius: 18,
                          iconSize: 19,
                          icon: Icon(
                            classification.isNaturalLanguage
                                ? Icons.auto_fix_high_rounded
                                : Icons.keyboard_return_rounded,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 44,
                            minHeight: 44,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  UniversalInputClassification _classificationFor(String text) {
    return widget.classifyInput?.call(text) ??
        UniversalInputClassifier().classify(text, mode: widget.inputMode);
  }

  List<String> _suggestionsFor(
    String text,
    UniversalInputClassification classification,
  ) {
    return widget.suggestionsForInput?.call(text, classification) ??
        const <String>[];
  }

  Map<String, CommandDraft> _suggestionDetailsFor(
    String text,
    UniversalInputClassification classification,
  ) {
    return widget.suggestionDetailsForInput?.call(text, classification) ??
        const <String, CommandDraft>{};
  }

  bool _suggestionsLoadingFor(
    String text,
    UniversalInputClassification classification,
  ) {
    return widget.suggestionsLoadingForInput?.call(text, classification) ??
        false;
  }

  List<String> _prioritizedSuggestions(List<String> suggestions, int index) {
    if (suggestions.isEmpty || index < 0 || index >= suggestions.length) {
      return suggestions;
    }
    return [
      suggestions[index],
      for (
        var candidateIndex = 0;
        candidateIndex < suggestions.length;
        candidateIndex++
      )
        if (candidateIndex != index) suggestions[candidateIndex],
    ];
  }

  Future<void> _submit(
    BuildContext context,
    String value,
    UniversalInputClassification classification,
    List<String> suggestions,
  ) async {
    if (value.trim().isEmpty) {
      return;
    }
    if (widget.inputMode == UniversalInputMode.agent) {
      _sendAgentMessage(value);
      return;
    }
    if (classification.isNaturalLanguage) {
      if (suggestions.isNotEmpty) {
        _acceptSuggestion(suggestions.first, classification);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Suggested command inserted. Press Enter to run it.'),
          ),
        );
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      final drafts = await widget.onGenerateCommandDrafts?.call(
        value,
        classification,
      );
      if (!mounted) {
        return;
      }
      if (drafts != null && drafts.isNotEmpty) {
        _acceptSuggestion(drafts.first.command, classification);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Suggested command inserted. Press Enter to run it.'),
          ),
        );
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(widget.naturalLanguageUnavailableMessage)),
      );
      _restoreTextInputFocus();
      return;
    }
    final didSubmit = await widget.onSubmitted(value);
    if (didSubmit) {
      widget.controller.clear();
    }
    _restoreTextInputFocus();
  }

  void _handleTextChanged(String text) {
    if (text.trim().isNotEmpty && widget.commandCorrection != null) {
      widget.onDismissCommandCorrection?.call();
    }
    final prefix = _universalInputModePrefixForText(text);
    if (prefix != null &&
        widget.onModeChanged != null &&
        widget.availableModes.contains(prefix.mode)) {
      widget.controller.value = TextEditingValue(
        text: prefix.text,
        selection: TextSelection.collapsed(offset: prefix.text.length),
        composing: TextRange.empty,
      );
      widget.onModeChanged!(prefix.mode);
      widget.onChanged?.call(prefix.text);
      _restoreTextInputFocus();
      setState(() {
        _activeSuggestionIndex = 0;
      });
      return;
    }
    if (widget.inputMode != UniversalInputMode.agent) {
      widget.onChanged?.call(text);
    }
    setState(() {
      _activeSuggestionIndex = 0;
    });
  }

  void _handleModeChanged(UniversalInputMode mode) {
    if (!widget.enabled || !widget.availableModes.contains(mode)) {
      return;
    }
    widget.onModeChanged?.call(mode);
    setState(() {
      _activeSuggestionIndex = 0;
    });
    _restoreTextInputFocus();
  }

  void _handleContextSelected(String value) {
    if (_removeUniversalInputInlineTrigger(widget.controller, '@')) {
      widget.onChanged?.call(widget.controller.text);
      setState(() {
        _activeSuggestionIndex = 0;
      });
    }
    widget.onContextSelected?.call(value);
    _restoreTextInputFocus();
  }

  void _handleSlashCommandSelected(String value) {
    if (_removeUniversalInputInlineTrigger(widget.controller, '/')) {
      widget.onChanged?.call(widget.controller.text);
    }
    _insertSnippet(value);
  }

  void _handleModelSelected(String value) {
    if (!widget.modelOptions.any((option) => option.value == value)) {
      return;
    }
    widget.onModelSelected?.call(value);
    _restoreTextInputFocus();
  }

  void _insertSnippet(String snippet) {
    final currentText = widget.controller.text;
    final separator = currentText.trimRight().isEmpty || snippet.startsWith(' ')
        ? ''
        : ' ';
    final nextText = '${currentText.trimRight()}$separator$snippet';
    widget.controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
      composing: TextRange.empty,
    );
    widget.onChanged?.call(nextText);
    setState(() {
      _activeSuggestionIndex = 0;
    });
    _restoreTextInputFocus();
  }

  void _sendAgentMessage(String value) {
    final text = value.trimRight();
    if (text.trim().isEmpty) {
      return;
    }
    unawaited(_agentResponseSubscription?.cancel());

    final now = DateTime.now();
    final requestId = 'shell-agent-request-${++_agentRequestSerial}';
    final assistantMessageId = _nextAgentMessageId('assistant');
    final userMessage = AgentMessage.userText(
      id: _nextAgentMessageId('user'),
      conversationId: _agentConversation.id,
      text: text,
      createdAt: now,
    );
    final assistantMessage = AgentMessage.assistantText(
      id: assistantMessageId,
      conversationId: _agentConversation.id,
      text: '',
      status: AgentMessageStatus.streaming,
      createdAt: now,
    );
    final nextConversation = _agentConversation
        .appendMessage(userMessage)
        .appendMessage(assistantMessage)
        .markStreaming(now);

    setState(() {
      _agentConversation = nextConversation;
      _activeAgentRequestId = requestId;
      _activeAssistantMessageId = assistantMessageId;
      widget.controller.clear();
    });

    final providerConfig = AgentProviderCatalog.defaults.byLabel(
      widget.modelLabel,
    );
    final request = AgentRequest(
      id: requestId,
      conversationId: _agentConversation.id,
      messages: nextConversation.messages,
      context: _agentRequestContext(),
      modelConfig: providerConfig.toModelConfig(),
    );
    _agentResponseSubscription = _agentRuntimeAdapter
        .send(request)
        .listen(_handleAgentResponseEvent);
    _restoreTextInputFocus();
  }

  bool _hasAgentContextActions() {
    final snapshot = widget.agentContextSnapshot;
    return snapshot?.selectedBlock != null ||
        snapshot?.lastFailedBlock != null ||
        snapshot?.sessionSummary != null;
  }

  Widget _buildAgentContextActionRow(AppThemeTokens palette) {
    final snapshot = widget.agentContextSnapshot;
    final selectedBlock = snapshot?.selectedBlock;
    final lastFailedBlock = snapshot?.lastFailedBlock;
    final sessionSummary = snapshot?.sessionSummary;
    return Wrap(
      spacing: palette.spacing.sm,
      runSpacing: palette.spacing.xs,
      children: [
        if (sessionSummary != null)
          OutlinedButton.icon(
            key: const Key('agent-remember-session-summary'),
            onPressed: widget.enabled
                ? () => _sendAgentMessage(
                    _rememberSessionSummaryPrompt(sessionSummary),
                  )
                : null,
            icon: const Icon(Icons.memory_rounded),
            label: const Text('Remember session'),
          ),
        if (selectedBlock != null)
          OutlinedButton.icon(
            key: const Key('agent-explain-selected-block'),
            onPressed: widget.enabled
                ? () => _sendAgentMessage(
                    _explainSelectedBlockPrompt(selectedBlock),
                  )
                : null,
            icon: const Icon(Icons.segment_rounded),
            label: const Text('Explain selected block'),
          ),
        if (lastFailedBlock != null)
          OutlinedButton.icon(
            key: const Key('agent-debug-last-failed-block'),
            onPressed: widget.enabled
                ? () => _sendAgentMessage(
                    _debugLastFailedBlockPrompt(lastFailedBlock),
                  )
                : null,
            icon: const Icon(Icons.bug_report_rounded),
            label: const Text('Debug last failed'),
          ),
      ],
    );
  }

  AgentRequestContext _agentRequestContext() {
    final snapshot = widget.agentContextSnapshot;
    return AgentRequestContext(
      terminalSessionId: snapshot?.terminalSessionId,
      cwd: snapshot?.cwd,
      readOnly: snapshot?.readOnly ?? widget.readOnly,
      snapshot: snapshot,
    );
  }

  void _handleAgentResponseEvent(AgentResponseEvent event) {
    if (!mounted || event.requestId != _activeAgentRequestId) {
      return;
    }
    final now = DateTime.now();
    switch (event) {
      case AgentResponseStarted():
        setState(() {
          _agentConversation = _agentConversation.markStreaming(now);
        });
      case AgentResponseTextDelta(:final delta):
        _replaceActiveAssistantMessage(
          (message) {
            final text = _agentResponseTextFor(message) + delta;
            return message.copyWith(
              parts: _agentPartsWithResponseText(message, text),
              status: AgentMessageStatus.streaming,
              createdAt: now,
            );
          },
          status: AgentConversationStatus.streaming,
          updatedAt: now,
        );
      case AgentResponseCommandProposal(:final proposal):
        _replaceActiveAssistantMessage(
          (message) {
            return message.copyWith(
              parts: <AgentMessagePart>[
                ...message.parts,
                AgentMessagePart.commandProposal(proposal),
              ],
              status: AgentMessageStatus.streaming,
              createdAt: now,
            );
          },
          status: AgentConversationStatus.streaming,
          updatedAt: now,
        );
      case AgentResponseCompleted():
        _replaceActiveAssistantMessage(
          (message) {
            return message.copyWith(
              status: AgentMessageStatus.completed,
              createdAt: now,
            );
          },
          status: AgentConversationStatus.completed,
          updatedAt: now,
        );
        _clearActiveAgentRequest();
      case AgentResponseCancelled():
        _replaceActiveAssistantMessage(
          (message) {
            return message.copyWith(
              status: AgentMessageStatus.cancelled,
              createdAt: now,
            );
          },
          status: AgentConversationStatus.cancelled,
          updatedAt: now,
        );
        _clearActiveAgentRequest();
      case AgentResponseFailed(:final error):
        _replaceActiveAssistantMessage(
          (message) {
            return message.copyWith(
              parts: <AgentMessagePart>[
                ...message.parts,
                AgentMessagePart.diagnostic(error.toString()),
              ],
              status: AgentMessageStatus.failed,
              createdAt: now,
            );
          },
          status: AgentConversationStatus.failed,
          updatedAt: now,
        );
        _clearActiveAgentRequest();
    }
  }

  void _replaceActiveAssistantMessage(
    AgentMessage Function(AgentMessage message) update, {
    required AgentConversationStatus status,
    required DateTime updatedAt,
  }) {
    final messageId = _activeAssistantMessageId;
    final message = messageId == null
        ? null
        : _agentConversation.messageById(messageId);
    if (message == null) {
      return;
    }
    setState(() {
      _agentConversation = _agentConversation
          .replaceMessage(update(message))
          .copyWith(status: status, updatedAt: updatedAt);
    });
  }

  Future<void> _cancelAgentResponse() async {
    final requestId = _activeAgentRequestId;
    if (requestId == null) {
      return;
    }
    await _agentRuntimeAdapter.cancel(requestId);
  }

  Future<void> _reviewAgentProposal(AgentCommandProposal proposal) async {
    if (!mounted) {
      return;
    }

    final action = await showDialog<_AgentCommandProposalReviewAction>(
      context: context,
      builder: (dialogContext) {
        return _AgentCommandProposalReviewDialog(
          key: const Key('agent-command-proposal-review-dialog'),
          proposal: proposal,
          readOnly: widget.readOnly,
          onClose: () => Navigator.of(dialogContext).pop(),
          onInsert: () => Navigator.of(
            dialogContext,
          ).pop(_AgentCommandProposalReviewAction.insert),
          onRun: () => Navigator.of(
            dialogContext,
          ).pop(_AgentCommandProposalReviewAction.run),
        );
      },
    );

    if (!mounted) {
      return;
    }
    switch (action) {
      case _AgentCommandProposalReviewAction.insert:
        _insertAgentProposal(proposal);
      case _AgentCommandProposalReviewAction.run:
        await _runAgentProposal(proposal);
      case null:
        break;
    }

    if (mounted) {
      _restoreTextInputFocus();
    }
  }

  void _insertAgentProposal(AgentCommandProposal proposal) {
    widget.controller.value = TextEditingValue(
      text: proposal.command,
      selection: TextSelection.collapsed(offset: proposal.command.length),
      composing: TextRange.empty,
    );
    widget.onModeChanged?.call(UniversalInputMode.terminal);
    widget.onChanged?.call(proposal.command);
    _restoreTextInputFocus();
  }

  Future<void> _runAgentProposal(AgentCommandProposal proposal) async {
    final decision = const AgentCommandSafetyPipeline().evaluate(
      AgentCommandSafetyRequest(
        proposal: proposal,
        readOnly: widget.readOnly,
        userConfirmed: true,
      ),
    );
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!decision.canExecute) {
      messenger?.showSnackBar(SnackBar(content: Text(decision.message)));
      return;
    }

    widget.controller.value = TextEditingValue(
      text: proposal.command,
      selection: TextSelection.collapsed(offset: proposal.command.length),
      composing: TextRange.empty,
    );
    widget.onModeChanged?.call(UniversalInputMode.terminal);
    widget.onChanged?.call(proposal.command);

    final didSubmit = await widget.onSubmitted(proposal.command);
    if (!mounted) {
      return;
    }
    if (didSubmit) {
      widget.controller.clear();
      widget.onChanged?.call('');
      messenger?.showSnackBar(
        const SnackBar(content: Text('Agent command sent to terminal.')),
      );
    } else {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Agent command was not sent.')),
      );
    }
  }

  void _clearActiveAgentRequest() {
    _activeAgentRequestId = null;
    _activeAssistantMessageId = null;
  }

  String _nextAgentMessageId(String role) {
    return 'shell-agent-$role-${++_agentMessageSerial}';
  }

  String _agentResponseTextFor(AgentMessage message) {
    for (final part in message.parts) {
      if (part.kind == AgentMessagePartKind.text ||
          part.kind == AgentMessagePartKind.markdown) {
        return part.text;
      }
    }
    return '';
  }

  List<AgentMessagePart> _agentPartsWithResponseText(
    AgentMessage message,
    String text,
  ) {
    final nonTextParts = message.parts.where(
      (part) =>
          part.kind != AgentMessagePartKind.text &&
          part.kind != AgentMessagePartKind.markdown,
    );
    return <AgentMessagePart>[
      if (text.isNotEmpty) AgentMessagePart.text(text),
      ...nonTextParts,
    ];
  }

  List<AgentContextChipModel> _agentConversationContextChips() {
    final snapshot = widget.agentContextSnapshot;
    if (snapshot != null) {
      final state = AgentContextChipState.fromSnapshot(snapshot);
      return <AgentContextChipModel>[
        ...state.chips,
        ..._manualAgentContextChips(),
      ];
    }
    return _manualAgentContextChips();
  }

  List<AgentContextChipModel> _manualAgentContextChips() {
    return widget.contextChips
        .map((chip) {
          final redacted = _redactedAgentContextChipText(chip);
          return AgentContextChipModel(
            attachmentId: chip,
            kind: AgentContextAttachmentKind.manualText,
            label: redacted,
            preview: redacted,
            semanticLabel: 'Agent context: $redacted',
            tone: AgentContextChipTone.normal,
          );
        })
        .toList(growable: false);
  }

  double _agentConversationPaneHeight() {
    if (_agentConversation.messages.isEmpty) {
      return 118;
    }
    final hasCommandProposal = _agentConversation.messages.any(
      (message) => message.parts.any((part) => part.commandProposal != null),
    );
    return hasCommandProposal ? 292 : 196;
  }

  String _explainSelectedBlockPrompt(AgentCommandBlockSnapshot block) {
    return 'Explain selected terminal block: ${block.command}';
  }

  String _debugLastFailedBlockPrompt(AgentCommandBlockSnapshot block) {
    final exit = block.exitCode == null ? '' : ' (exit ${block.exitCode})';
    return 'Debug last failed terminal block$exit: ${block.command}';
  }

  String _rememberSessionSummaryPrompt(AgentSessionSummary summary) {
    return 'Remember this terminal session summary for this Agent conversation:\n'
        '${summary.toMemoryText()}';
  }

  AgentRuntimeAdapter _defaultAgentRuntime() {
    return MockAgentRuntimeAdapter(
      steps: <MockAgentResponseStep>[
        MockAgentResponseStep.text('Mock Agent response for this terminal. '),
        MockAgentResponseStep.text('Here is a safe read-only proposal.'),
        MockAgentResponseStep.commandProposal(
          AgentCommandProposal(
            id: 'mock-proposal-pwd',
            conversationId: _agentConversationId,
            command: 'pwd',
            explanation:
                'Print the current working directory without modifying files.',
            riskLevel: AgentCommandRiskLevel.low,
            warnings: const <String>['Read-only command.'],
            detectedEffects: const <String>[
              'Prints the active terminal working directory.',
            ],
            requiresConfirmation: false,
            source: AgentCommandProposalSource.mock,
            createdAt: DateTime.now(),
          ),
        ),
      ],
      stepDelay: const Duration(milliseconds: 5000),
    );
  }

  void _moveSuggestion(int delta, int length) {
    if (length < 2) {
      return;
    }
    final nextIndex = (_activeSuggestionIndex + delta) % length;
    setState(() {
      _activeSuggestionIndex = nextIndex < 0 ? nextIndex + length : nextIndex;
    });
    _restoreTextInputFocus();
  }

  void _acceptSuggestion(
    String suggestion,
    UniversalInputClassification classification,
  ) {
    final currentText = widget.controller.text;
    final prefix =
        RegExp(r'[A-Za-z0-9_./:-]+$').firstMatch(currentText)?.group(0) ?? '';
    final replaceWholeInput = classification.isNaturalLanguage;
    final nextText = replaceWholeInput || prefix.isEmpty
        ? suggestion
        : '${currentText.substring(0, currentText.length - prefix.length)}'
              '$suggestion';
    widget.controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
      composing: TextRange.empty,
    );
    if (replaceWholeInput) {
      widget.onModeChanged?.call(UniversalInputMode.auto);
    }
    widget.onChanged?.call(nextText);
    setState(() {
      _activeSuggestionIndex = 0;
    });
    _restoreTextInputFocus();
  }

  void _acceptCommandCorrection() {
    final correction = widget.commandCorrection;
    if (correction == null) {
      return;
    }
    widget.onAcceptCommandCorrection?.call(correction);
    _restoreTextInputFocus();
  }

  void _openCommandSearch() {
    widget.onOpenCommandSearch?.call();
  }

  void _restoreTextInputFocus() {
    if (!widget.enabled) {
      return;
    }
    widget.focusNode.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestTextInputFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _requestTextInputFocus();
      });
    });
  }

  void _requestTextInputFocus() {
    final focusContext = widget.focusNode.context;
    if (focusContext == null ||
        !focusContext.mounted ||
        !widget.focusNode.canRequestFocus) {
      return;
    }
    FocusScope.of(focusContext).requestFocus(widget.focusNode);
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.show'));
  }
}

enum _AgentCommandProposalReviewAction { insert, run }

class _AgentCommandProposalReviewDialog extends StatefulWidget {
  const _AgentCommandProposalReviewDialog({
    super.key,
    required this.proposal,
    required this.readOnly,
    required this.onClose,
    required this.onInsert,
    required this.onRun,
  });

  final AgentCommandProposal proposal;
  final bool readOnly;
  final VoidCallback onClose;
  final VoidCallback onInsert;
  final VoidCallback onRun;

  @override
  State<_AgentCommandProposalReviewDialog> createState() =>
      _AgentCommandProposalReviewDialogState();
}

class _AgentCommandProposalReviewDialogState
    extends State<_AgentCommandProposalReviewDialog> {
  bool _executionConfirmed = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final safetyPipeline = const AgentCommandSafetyPipeline();
    final decision = safetyPipeline.evaluate(
      AgentCommandSafetyRequest(
        proposal: widget.proposal,
        readOnly: widget.readOnly,
        userConfirmed: _executionConfirmed,
      ),
    );
    final needsConfirmation =
        !decision.blocked &&
        safetyPipeline.requiresExplicitConfirmation(widget.proposal);
    return AppDialogScaffold(
      title: 'Review command proposal',
      subtitle: 'Inspect the Agent proposal before inserting or running it.',
      onClose: widget.onClose,
      constraints: const BoxConstraints(maxWidth: 560),
      body: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Command',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: theme.textSubtle,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: theme.spacing.xs),
            DecoratedBox(
              key: const Key('agent-command-proposal-review-command'),
              decoration: BoxDecoration(
                color: theme.terminalSurface,
                borderRadius: BorderRadius.circular(theme.radius.sm),
                border: Border.all(color: theme.border),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: theme.spacing.md,
                  vertical: theme.spacing.sm,
                ),
                child: SelectableText(
                  widget.proposal.command,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: theme.textPrimary,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            SizedBox(height: theme.spacing.md),
            Wrap(
              spacing: theme.spacing.sm,
              runSpacing: theme.spacing.xs,
              children: [
                _AgentProposalReviewPill(
                  label: _agentProposalRiskLabel(widget.proposal.riskLevel),
                  icon: Icons.shield_outlined,
                ),
                _AgentProposalReviewPill(
                  label: widget.proposal.requiresConfirmation
                      ? 'Confirmation required'
                      : 'Direct run eligible',
                  icon: widget.proposal.requiresConfirmation
                      ? Icons.verified_user_outlined
                      : Icons.play_arrow_rounded,
                ),
              ],
            ),
            SizedBox(height: theme.spacing.lg),
            Text(
              widget.proposal.explanation,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: theme.textPrimary,
                height: 1.34,
              ),
            ),
            SizedBox(height: theme.spacing.md),
            _AgentProposalReviewDetail(
              icon: decision.canExecute
                  ? Icons.verified_rounded
                  : decision.blocked
                  ? Icons.lock_rounded
                  : Icons.fact_check_rounded,
              text: decision.message,
              color: decision.canExecute
                  ? theme.success
                  : decision.blocked
                  ? theme.danger
                  : theme.warning,
            ),
            if (needsConfirmation) ...[
              SizedBox(height: theme.spacing.md),
              CheckboxListTile(
                key: const Key('agent-command-proposal-run-confirmation'),
                value: _executionConfirmed,
                onChanged: (value) {
                  setState(() {
                    _executionConfirmed = value ?? false;
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'I reviewed this command and want to run it.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: theme.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            if (widget.proposal.cwd != null) ...[
              SizedBox(height: theme.spacing.md),
              _AgentProposalReviewDetail(
                icon: Icons.folder_rounded,
                text: widget.proposal.cwd!,
              ),
            ],
            if (widget.proposal.warnings.isNotEmpty) ...[
              SizedBox(height: theme.spacing.md),
              for (final warning in widget.proposal.warnings)
                _AgentProposalReviewDetail(
                  icon: Icons.warning_amber_rounded,
                  text: warning,
                  color: theme.warning,
                ),
            ],
            if (widget.proposal.detectedEffects.isNotEmpty) ...[
              SizedBox(height: theme.spacing.md),
              for (final effect in widget.proposal.detectedEffects)
                _AgentProposalReviewDetail(
                  icon: Icons.info_outline_rounded,
                  text: effect,
                ),
            ],
          ],
        ),
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            key: const Key('agent-command-proposal-review-close'),
            onPressed: widget.onClose,
            child: const Text('Close'),
          ),
          SizedBox(width: theme.spacing.sm),
          OutlinedButton.icon(
            key: const Key('agent-command-proposal-review-insert'),
            onPressed: widget.onInsert,
            icon: const Icon(Icons.input_rounded),
            label: const Text('Insert'),
          ),
          SizedBox(width: theme.spacing.sm),
          FilledButton.icon(
            key: const Key('agent-command-proposal-review-run'),
            onPressed: decision.canExecute ? widget.onRun : null,
            icon: Icon(
              decision.blocked ? Icons.lock_rounded : Icons.play_arrow_rounded,
            ),
            label: Text(decision.blocked ? 'Blocked' : 'Run'),
          ),
        ],
      ),
    );
  }
}

class _AgentProposalReviewPill extends StatelessWidget {
  const _AgentProposalReviewPill({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.chrome,
        borderRadius: BorderRadius.circular(theme.radius.sm),
        border: Border.all(color: theme.border),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: theme.spacing.sm,
          vertical: theme.spacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: theme.textMuted),
            SizedBox(width: theme.spacing.xs),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: theme.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentProposalReviewDetail extends StatelessWidget {
  const _AgentProposalReviewDetail({
    required this.icon,
    required this.text,
    this.color,
  });

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Padding(
      padding: EdgeInsets.only(top: theme.spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color ?? theme.textMuted),
          SizedBox(width: theme.spacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: theme.textMuted,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _agentProposalRiskLabel(AgentCommandRiskLevel riskLevel) {
  return switch (riskLevel) {
    AgentCommandRiskLevel.low => 'Low risk',
    AgentCommandRiskLevel.medium => 'Medium risk',
    AgentCommandRiskLevel.high => 'High risk',
    AgentCommandRiskLevel.destructive => 'Destructive',
    AgentCommandRiskLevel.unknown => 'Unknown risk',
  };
}

class _UniversalInputModelMenuChip extends StatelessWidget {
  const _UniversalInputModelMenuChip({
    super.key,
    required this.keyPrefix,
    required this.label,
    required this.options,
    required this.palette,
    required this.onSelected,
  });

  final String keyPrefix;
  final String label;
  final List<UniversalInputToolOption> options;
  final AppThemeTokens palette;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Model picker',
      child: PopupMenuButton<String>(
        tooltip: 'Model picker',
        color: palette.overlay,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(palette.radius.md),
          side: BorderSide(color: palette.border),
        ),
        onSelected: onSelected,
        itemBuilder: (context) {
          return [
            for (final option in options)
              PopupMenuItem<String>(
                value: option.value,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(option.icon, size: 18, color: palette.accent),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            option.label,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: palette.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          if (option.detail != null)
                            Text(
                              option.detail!,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: palette.textSubtle),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ];
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = math.min(260.0, constraints.maxWidth);
            if (maxWidth < 24) {
              return SizedBox(width: math.max(0.0, maxWidth), height: 28);
            }
            final iconOnly = maxWidth < 80;
            return SizedBox(
              width: maxWidth.isFinite ? maxWidth : null,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.chrome.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(palette.radius.sm),
                  border: Border.all(color: palette.border),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: iconOnly ? 5 : 8,
                    vertical: 5,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.psychology_alt_rounded,
                        size: 16,
                        color: palette.accent,
                      ),
                      if (!iconOnly) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            label,
                            key: Key('$keyPrefix-model-label'),
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: palette.textSubtle,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: palette.textMuted,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

String _redactedAgentContextChipText(String chip) {
  return const AgentContextPrivacyFilter().redactText(chip);
}

Rect _globalRectForContext(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.hasSize) {
    final fallback = renderObject is RenderBox
        ? renderObject.localToGlobal(Offset.zero)
        : Offset.zero;
    return fallback & const Size(1, 1);
  }
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

class _ShellCommandBlockStatusDot extends StatelessWidget {
  const _ShellCommandBlockStatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 8,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
