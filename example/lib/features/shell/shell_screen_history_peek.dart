part of 'shell_screen.dart';

const double _shellHistoryPeekPreferredWidth = 320;
const double _shellHistoryPeekMinimumTerminalWidth = 280;
const double _shellHistoryPeekMinimumSheetWidth = 160;
const int _shellHistoryPeekRecentLimit = 8;
const int _shellHistoryPeekTimelineLimit = 24;

double shellHistoryPeekWidthForAvailableWidth(double availableWidth) {
  if (!availableWidth.isFinite) {
    return _shellHistoryPeekPreferredWidth;
  }
  if (availableWidth <= 0) {
    return 0;
  }
  return math.min(_shellHistoryPeekPreferredWidth, availableWidth);
}

double shellHistoryPeekSidePaneWidthForAvailableWidth(double availableWidth) {
  if (!availableWidth.isFinite) {
    return _shellHistoryPeekPreferredWidth;
  }
  final remainingWidth = availableWidth - _shellHistoryPeekMinimumTerminalWidth;
  if (remainingWidth < _shellHistoryPeekMinimumSheetWidth) {
    return 0;
  }
  return math.min(_shellHistoryPeekPreferredWidth, remainingWidth);
}

bool shellHistoryPeekShowsBlock(ShellCommandBlock block) {
  return block.failed || block.markers.isNotEmpty;
}

bool shellHistoryPeekHasVisibleBlocks(Iterable<ShellCommandBlock> blocks) {
  return blocks.any(shellHistoryPeekShowsBlock);
}

List<ShellCommandBlock> shellHistoryPeekVisibleBlocks(
  Iterable<ShellCommandBlock> blocks,
) {
  return blocks.where(shellHistoryPeekShowsBlock).toList(growable: false);
}

enum _ShellHistoryPeekFilter { all, failed, marked, recent }

extension on _ShellHistoryPeekFilter {
  String get label {
    return switch (this) {
      _ShellHistoryPeekFilter.all => 'All',
      _ShellHistoryPeekFilter.failed => 'Failed',
      _ShellHistoryPeekFilter.marked => 'Marked',
      _ShellHistoryPeekFilter.recent => 'Recent',
    };
  }
}

class ShellHistoryPeekSheet extends StatefulWidget {
  const ShellHistoryPeekSheet({
    super.key,
    required this.blocks,
    this.onClose,
    this.maxWidth,
  });

  final List<ShellCommandBlock> blocks;
  final VoidCallback? onClose;
  final double? maxWidth;

  @override
  State<ShellHistoryPeekSheet> createState() => _ShellHistoryPeekSheetState();
}

class _ShellHistoryPeekSheetState extends State<ShellHistoryPeekSheet> {
  final TextEditingController _searchController = TextEditingController();
  _ShellHistoryPeekFilter _selectedFilter = _ShellHistoryPeekFilter.all;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette =
        theme.extension<AppThemeTokens>() ??
        AppThemeTokens.fallbackFor(theme.brightness);
    final visibleBlocks = _visibleBlocks();
    final preferredWidth = math.min(
      widget.maxWidth ?? _shellHistoryPeekPreferredWidth,
      MediaQuery.sizeOf(context).width,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final sheetWidth = constraints.maxWidth.isFinite
            ? math.min(preferredWidth, constraints.maxWidth)
            : preferredWidth;
        return SizedBox(
          key: const Key('shell-history-peek-sheet'),
          width: sheetWidth,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.chromeElevated,
              border: Border(left: BorderSide(color: palette.borderStrong)),
              boxShadow: palette.elevation.floating,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    palette.spacing.lg,
                    palette.spacing.lg,
                    palette.spacing.lg,
                    palette.spacing.xl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ShellHistoryPeekHeader(
                        count: widget.blocks.length,
                        palette: palette,
                        onClose: widget.onClose,
                      ),
                      SizedBox(height: palette.spacing.sm),
                      _ShellHistoryPeekSearchField(
                        controller: _searchController,
                        palette: palette,
                      ),
                      SizedBox(height: palette.spacing.sm),
                      _ShellHistoryPeekFilterBar(
                        selectedFilter: _selectedFilter,
                        counts: _filterCounts(widget.blocks),
                        palette: palette,
                        onChanged: (filter) {
                          setState(() {
                            _selectedFilter = filter;
                          });
                        },
                      ),
                      SizedBox(height: palette.spacing.md),
                      _ShellHistoryPeekTimeline(
                        blocks: visibleBlocks,
                        palette: palette,
                      ),
                      SizedBox(height: palette.spacing.sm),
                      Expanded(
                        child: visibleBlocks.isEmpty
                            ? _ShellHistoryPeekEmptyState(
                                query: _searchController.text,
                                hasBlocks: widget.blocks.isNotEmpty,
                                palette: palette,
                              )
                            : ListView.separated(
                                itemCount: visibleBlocks.length,
                                separatorBuilder: (_, _) =>
                                    SizedBox(height: palette.spacing.sm),
                                itemBuilder: (context, index) {
                                  return _ShellHistoryPeekBlockTile(
                                    block: visibleBlocks[index],
                                    palette: palette,
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<ShellCommandBlock> _visibleBlocks() {
    Iterable<ShellCommandBlock> filtered = switch (_selectedFilter) {
      _ShellHistoryPeekFilter.all => widget.blocks,
      _ShellHistoryPeekFilter.failed => widget.blocks.where(
        (block) => block.failed,
      ),
      _ShellHistoryPeekFilter.marked => widget.blocks.where(
        (block) => block.markers.isNotEmpty,
      ),
      _ShellHistoryPeekFilter.recent => _recentBlocks(widget.blocks),
    };

    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      filtered = filtered.where((block) => _matchesBlock(block, query));
    }

    return filtered.toList(growable: false);
  }

  Iterable<ShellCommandBlock> _recentBlocks(List<ShellCommandBlock> blocks) {
    final start = math.max(0, blocks.length - _shellHistoryPeekRecentLimit);
    return blocks.skip(start);
  }

  bool _matchesBlock(ShellCommandBlock block, String query) {
    final fields = <String>[
      block.command,
      block.cwd ?? '',
      _statusLabel(block),
      for (final marker in block.markers) _markerLabel(marker),
    ];
    return fields.any((field) => field.toLowerCase().contains(query));
  }
}

class _ShellHistoryPeekHeader extends StatelessWidget {
  const _ShellHistoryPeekHeader({
    required this.count,
    required this.palette,
    this.onClose,
  });

  final int count;
  final AppThemeTokens palette;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            'History Peek',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Text(
          '$count',
          maxLines: 1,
          style: theme.textTheme.labelSmall?.copyWith(
            color: palette.textSubtle,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (onClose != null) ...[
          SizedBox(width: palette.spacing.sm),
          _buildSheetCloseButton(
            tooltip: 'Close History Peek',
            buttonKey: const Key('shell-history-peek-close'),
            onPressed: onClose!,
          ),
        ],
      ],
    );
  }
}

class _ShellHistoryPeekSearchField extends StatelessWidget {
  const _ShellHistoryPeekSearchField({
    required this.controller,
    required this.palette,
  });

  final TextEditingController controller;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 34,
      child: TextField(
        key: const Key('shell-history-peek-search'),
        controller: controller,
        maxLines: 1,
        textInputAction: TextInputAction.search,
        style: theme.textTheme.labelMedium?.copyWith(
          color: palette.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search command or cwd',
          hintStyle: theme.textTheme.labelMedium?.copyWith(
            color: palette.textSubtle,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 16,
            color: palette.textSubtle,
          ),
          prefixIconConstraints: const BoxConstraints.tightFor(width: 30),
          contentPadding: EdgeInsets.symmetric(
            horizontal: palette.spacing.sm,
            vertical: palette.spacing.xs,
          ),
          filled: true,
          fillColor: palette.panel.withValues(alpha: 0.72),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(palette.radius.md),
            borderSide: BorderSide(color: palette.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(palette.radius.md),
            borderSide: BorderSide(
              color: palette.border.withValues(alpha: 0.74),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(palette.radius.md),
            borderSide: BorderSide(color: palette.focus, width: 1.2),
          ),
        ),
      ),
    );
  }
}

class _ShellHistoryPeekFilterBar extends StatelessWidget {
  const _ShellHistoryPeekFilterBar({
    required this.selectedFilter,
    required this.counts,
    required this.palette,
    required this.onChanged,
  });

  final _ShellHistoryPeekFilter selectedFilter;
  final Map<_ShellHistoryPeekFilter, int> counts;
  final AppThemeTokens palette;
  final ValueChanged<_ShellHistoryPeekFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: palette.spacing.xs,
      runSpacing: palette.spacing.xs,
      children: [
        for (final filter in _ShellHistoryPeekFilter.values)
          _ShellHistoryPeekFilterChip(
            key: Key('shell-history-peek-filter-${filter.label}'),
            label: '${filter.label} ${counts[filter] ?? 0}',
            selected: filter == selectedFilter,
            palette: palette,
            onTap: () => onChanged(filter),
          ),
      ],
    );
  }
}

class _ShellHistoryPeekFilterChip extends StatelessWidget {
  const _ShellHistoryPeekFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final AppThemeTokens palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? palette.accent : palette.textSubtle;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(palette.radius.sm),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? palette.selected.withValues(alpha: 0.64)
                : palette.panel.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(palette.radius.sm),
            border: Border.all(
              color: selected
                  ? palette.accent.withValues(alpha: 0.42)
                  : palette.border.withValues(alpha: 0.56),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: palette.spacing.sm,
              vertical: 3,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellHistoryPeekTimeline extends StatelessWidget {
  const _ShellHistoryPeekTimeline({
    required this.blocks,
    required this.palette,
  });

  final List<ShellCommandBlock> blocks;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    if (blocks.isEmpty) {
      return const SizedBox.shrink();
    }
    final timelineBlocks = blocks.length > _shellHistoryPeekTimelineLimit
        ? blocks.skip(blocks.length - _shellHistoryPeekTimelineLimit).toList()
        : blocks;
    return SizedBox(
      height: 10,
      child: Row(
        children: [
          for (var index = 0; index < timelineBlocks.length; index++) ...[
            if (index > 0) SizedBox(width: 2),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _statusColor(
                    timelineBlocks[index],
                    palette,
                  ).withValues(alpha: 0.58),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: const SizedBox(height: 3),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShellHistoryPeekEmptyState extends StatelessWidget {
  const _ShellHistoryPeekEmptyState({
    required this.query,
    required this.hasBlocks,
    required this.palette,
  });

  final String query;
  final bool hasBlocks;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    final message = !hasBlocks
        ? 'No commands captured yet.'
        : query.trim().isEmpty
        ? 'No commands in this filter.'
        : 'No matching commands.';
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: palette.textSubtle),
      ),
    );
  }
}

class _ShellHistoryPeekBlockTile extends StatelessWidget {
  const _ShellHistoryPeekBlockTile({
    required this.block,
    required this.palette,
  });

  final ShellCommandBlock block;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final markerLabels = _markerLabels(block.markers);
    final statusColor = _statusColor(block, palette);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.panel.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(palette.radius.md),
        border: Border.all(color: _borderColor(block, palette)),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: SizedBox(
              width: block.failed ? 3 : 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: statusColor.withValues(
                    alpha: block.failed ? 0.9 : 0.66,
                  ),
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(palette.radius.md),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              palette.spacing.sm,
              palette.spacing.sm,
              palette.spacing.sm,
              palette.spacing.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _ShellHistoryPeekStatusDot(color: statusColor),
                    SizedBox(width: palette.spacing.sm),
                    Expanded(
                      child: Text(
                        _commandLabel(block),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    SizedBox(width: palette.spacing.sm),
                    _ShellHistoryPeekMetaPill(
                      label: _statusLabel(block),
                      color: statusColor,
                      palette: palette,
                    ),
                  ],
                ),
                SizedBox(height: palette.spacing.xs),
                Wrap(
                  spacing: palette.spacing.sm,
                  runSpacing: palette.spacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _ShellHistoryPeekMetaText(
                      label: _rangeLabel(block),
                      palette: palette,
                    ),
                    if (block.cwd != null && block.cwd!.trim().isNotEmpty)
                      _ShellHistoryPeekMetaText(
                        label: block.cwd!.trim(),
                        palette: palette,
                      ),
                    for (final markerLabel in markerLabels)
                      _ShellHistoryPeekMetaPill(
                        label: markerLabel,
                        color: palette.accent,
                        palette: palette,
                      ),
                  ],
                ),
                SizedBox(height: palette.spacing.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: block.failed ? 0.86 : 0.54,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.42),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: const SizedBox(height: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShellHistoryPeekMetaText extends StatelessWidget {
  const _ShellHistoryPeekMetaText({required this.label, required this.palette});

  final String label;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: palette.textSubtle,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _ShellHistoryPeekMetaPill extends StatelessWidget {
  const _ShellHistoryPeekMetaPill({
    required this.label,
    required this.color,
    required this.palette,
  });

  final String label;
  final Color color;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(palette.radius.sm),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: palette.spacing.sm,
          vertical: 2,
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ShellHistoryPeekStatusDot extends StatelessWidget {
  const _ShellHistoryPeekStatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 7,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

Map<_ShellHistoryPeekFilter, int> _filterCounts(
  List<ShellCommandBlock> blocks,
) {
  return {
    _ShellHistoryPeekFilter.all: blocks.length,
    _ShellHistoryPeekFilter.failed: blocks
        .where((block) => block.failed)
        .length,
    _ShellHistoryPeekFilter.marked: blocks
        .where((block) => block.markers.isNotEmpty)
        .length,
    _ShellHistoryPeekFilter.recent: math.min(
      blocks.length,
      _shellHistoryPeekRecentLimit,
    ),
  };
}

Color _statusColor(ShellCommandBlock block, AppThemeTokens palette) {
  return switch (block.status) {
    ShellCommandBlockStatus.failed => palette.danger,
    ShellCommandBlockStatus.succeeded => palette.success,
    ShellCommandBlockStatus.running => palette.warning,
    ShellCommandBlockStatus.unknown => palette.textSubtle,
  };
}

Color _borderColor(ShellCommandBlock block, AppThemeTokens palette) {
  return block.failed
      ? palette.danger.withValues(alpha: 0.42)
      : palette.border.withValues(alpha: 0.58);
}

String _commandLabel(ShellCommandBlock block) {
  final command = block.command.trim();
  return command.isEmpty ? 'Unknown command' : command;
}

String _rangeLabel(ShellCommandBlock block) {
  if (!block.isValid) {
    return 'captured output';
  }
  final start = block.outputRange.commandRow;
  final end = block.outputRange.outputEndRow;
  if (start == end) {
    return 'row $start';
  }
  return 'rows $start-$end';
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

List<String> _markerLabels(List<ShellHistoryMarker> markers) {
  return markers.map(_markerLabel).toList(growable: false);
}

String _markerLabel(ShellHistoryMarker marker) {
  final label = marker.label?.trim();
  if (label != null && label.isNotEmpty) {
    return label;
  }
  return switch (marker.kind) {
    ShellHistoryMarkerKind.manual => 'Marked',
    ShellHistoryMarkerKind.failure => 'Failure',
    ShellHistoryMarkerKind.idleGap => 'Idle gap',
    ShellHistoryMarkerKind.replayFrame => 'Replay frame',
  };
}
