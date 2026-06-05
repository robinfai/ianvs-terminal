part of 'shell_screen.dart';

class ShellCommandBlocksOverlay extends StatelessWidget {
  const ShellCommandBlocksOverlay({
    super.key,
    required this.viewModel,
    required this.rowHeight,
    this.contentPadding = EdgeInsets.zero,
  });

  final ShellCommandBlocksOverlayViewModel viewModel;
  final double rowHeight;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    if (viewModel.isEmpty) {
      return const SizedBox.shrink();
    }

    final effectiveRowHeight = rowHeight.isFinite && rowHeight > 0
        ? rowHeight
        : 1.0;

    return IgnorePointer(
      child: Padding(
        padding: contentPadding,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            for (final block in viewModel.blocks)
              Positioned(
                key: Key('shell-command-block-${block.id}'),
                top: math.max(0, block.rowOffset) * effectiveRowHeight,
                left: 8,
                right: 8,
                child: SizedBox(
                  height: math.max(1, block.rowSpan) * effectiveRowHeight,
                  child: _ShellCommandBlockChrome(
                    block: block,
                    rowHeight: effectiveRowHeight,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ShellCommandBlockChrome extends StatelessWidget {
  const _ShellCommandBlockChrome({
    required this.block,
    required this.rowHeight,
  });

  final ShellCommandBlockOverlayItem block;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette =
        theme.extension<AppThemeTokens>() ??
        AppThemeTokens.fallbackFor(theme.brightness);
    final statusColor = _statusColor(palette, block.status);
    final background = block.active
        ? palette.overlay.withValues(alpha: 0.92)
        : palette.terminalSurface.withValues(alpha: 0.52);
    final borderColor = block.active
        ? statusColor.withValues(alpha: 0.76)
        : palette.border.withValues(alpha: 0.58);
    final blockHeight = math.max(1, block.rowSpan) * rowHeight;
    final showActions = block.active && blockHeight >= 44;
    final compact = blockHeight < 32;
    final dense = blockHeight < 64;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(palette.radius.md),
        border: Border.all(color: borderColor, width: block.active ? 1.5 : 1),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? palette.spacing.sm : palette.spacing.md,
          compact
              ? 0
              : dense
              ? palette.spacing.xs
              : block.active
              ? palette.spacing.md
              : palette.spacing.sm,
          compact ? palette.spacing.sm : palette.spacing.md,
          compact
              ? 0
              : dense
              ? palette.spacing.xs
              : block.active
              ? palette.spacing.md
              : palette.spacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: showActions
              ? MainAxisAlignment.start
              : MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                _ShellCommandBlockStatusDot(color: statusColor),
                SizedBox(width: palette.spacing.sm),
                Expanded(
                  flex: 3,
                  child: Text(
                    block.command,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SizedBox(width: palette.spacing.md),
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      block.statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (showActions) ...[
              SizedBox(height: dense ? palette.spacing.xs : palette.spacing.sm),
              _ShellCommandBlockStatusHints(block: block, palette: palette),
            ],
          ],
        ),
      ),
    );
  }

  Color _statusColor(AppThemeTokens palette, ShellCommandBlockStatus status) {
    return switch (status) {
      ShellCommandBlockStatus.failed => palette.danger,
      ShellCommandBlockStatus.succeeded => palette.success,
      ShellCommandBlockStatus.running => palette.warning,
      ShellCommandBlockStatus.unknown => palette.textSubtle,
    };
  }
}

class _ShellCommandBlockStatusHints extends StatelessWidget {
  const _ShellCommandBlockStatusHints({
    required this.block,
    required this.palette,
  });

  final ShellCommandBlockOverlayItem block;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    final hints = <String>[
      'Output captured',
      if (block.showReplayAction) 'Replay context',
      if (block.showFailureSnapshotAction) 'Failure snapshot',
      if (block.showDiffAction) 'Previous run',
    ];

    return ClipRect(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Row(
          children: [
            for (var index = 0; index < hints.length; index++) ...[
              if (index > 0) SizedBox(width: palette.spacing.sm),
              _ShellCommandBlockStatusChip(
                label: hints[index],
                palette: palette,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ShellCommandBlockStatusChip extends StatelessWidget {
  const _ShellCommandBlockStatusChip({
    required this.label,
    required this.palette,
  });

  final String label;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.selected.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(palette.radius.sm),
        border: Border.all(color: palette.borderStrong),
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
            color: palette.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
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
