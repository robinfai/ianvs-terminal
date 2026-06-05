part of 'shell_screen.dart';

const double _shellHistoryPeekPreferredWidth = 320;
const double _shellHistoryPeekMinimumTerminalWidth = 280;
const double _shellHistoryPeekMinimumSheetWidth = 160;

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

class ShellHistoryPeekSheet extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette =
        theme.extension<AppThemeTokens>() ??
        AppThemeTokens.fallbackFor(theme.brightness);
    final visibleBlocks = shellHistoryPeekVisibleBlocks(blocks);

    final preferredWidth = math.min(
      maxWidth ?? _shellHistoryPeekPreferredWidth,
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
                      Row(
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
                          if (onClose != null)
                            _buildSheetCloseButton(
                              tooltip: 'Close History Peek',
                              buttonKey: const Key('shell-history-peek-close'),
                              onPressed: onClose!,
                            ),
                        ],
                      ),
                      SizedBox(height: palette.spacing.sm),
                      Expanded(
                        child: visibleBlocks.isEmpty
                            ? _ShellHistoryPeekEmptyState(palette: palette)
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
}

class _ShellHistoryPeekEmptyState extends StatelessWidget {
  const _ShellHistoryPeekEmptyState({required this.palette});

  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No failed or marked commands yet.',
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

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(palette.radius.md),
        border: Border.all(color: _borderColor),
      ),
      child: Padding(
        padding: EdgeInsets.all(palette.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: palette.spacing.xs),
                  child: _ShellHistoryPeekStatusDot(color: _statusColor),
                ),
                SizedBox(width: palette.spacing.sm),
                Expanded(
                  child: Text(
                    block.command.trim().isEmpty
                        ? 'Unknown command'
                        : block.command.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: palette.spacing.sm),
            Wrap(
              spacing: palette.spacing.sm,
              runSpacing: palette.spacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _ShellHistoryPeekMetaPill(
                  label: _statusLabel(block),
                  color: _statusColor,
                  palette: palette,
                ),
                if (block.cwd != null && block.cwd!.trim().isNotEmpty)
                  _ShellHistoryPeekMetaText(
                    label: block.cwd!.trim(),
                    palette: palette,
                  ),
              ],
            ),
            if (markerLabels.isNotEmpty) ...[
              SizedBox(height: palette.spacing.sm),
              Wrap(
                spacing: palette.spacing.sm,
                runSpacing: palette.spacing.xs,
                children: [
                  for (final markerLabel in markerLabels)
                    _ShellHistoryPeekMetaPill(
                      label: markerLabel,
                      color: palette.accent,
                      palette: palette,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color get _statusColor {
    return switch (block.status) {
      ShellCommandBlockStatus.failed => palette.danger,
      ShellCommandBlockStatus.succeeded => palette.success,
      ShellCommandBlockStatus.running => palette.warning,
      ShellCommandBlockStatus.unknown => palette.textSubtle,
    };
  }

  Color get _borderColor {
    return block.failed
        ? palette.danger.withValues(alpha: 0.62)
        : palette.borderStrong;
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
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: palette.textSubtle),
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
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(palette.radius.sm),
        border: Border.all(color: color.withValues(alpha: 0.48)),
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
            fontWeight: FontWeight.w800,
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
      dimension: 8,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
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
