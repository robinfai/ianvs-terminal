part of 'shell_screen.dart';

class ShellCommandBlocksOverlay extends StatelessWidget {
  const ShellCommandBlocksOverlay({
    super.key,
    required this.viewModel,
    required this.rowHeight,
  });

  final ShellCommandBlocksOverlayViewModel viewModel;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    if (viewModel.isEmpty) {
      return const SizedBox.shrink();
    }

    final effectiveRowHeight = rowHeight.isFinite && rowHeight > 0
        ? rowHeight
        : 1.0;

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        for (final block in viewModel.blocks)
          Positioned(
            key: Key('shell-command-block-${block.id}'),
            top: math.max(0, block.rowOffset) * effectiveRowHeight,
            left: 8,
            right: 8,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: math.max(1, block.rowSpan) * effectiveRowHeight,
              ),
              child: _ShellCommandBlockChrome(block: block),
            ),
          ),
      ],
    );
  }
}

class _ShellCommandBlockChrome extends StatelessWidget {
  const _ShellCommandBlockChrome({required this.block});

  final ShellCommandBlockOverlayItem block;

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

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(palette.radius.md),
        border: Border.all(color: borderColor, width: block.active ? 1.5 : 1),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          palette.spacing.md,
          block.active ? palette.spacing.md : palette.spacing.sm,
          palette.spacing.md,
          block.active ? palette.spacing.md : palette.spacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _ShellCommandBlockStatusDot(color: statusColor),
                SizedBox(width: palette.spacing.sm),
                Expanded(
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
                Text(
                  block.statusLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (block.active) ...[
              SizedBox(height: palette.spacing.sm),
              _ShellCommandBlockActions(block: block, palette: palette),
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

class _ShellCommandBlockActions extends StatelessWidget {
  const _ShellCommandBlockActions({required this.block, required this.palette});

  final ShellCommandBlockOverlayItem block;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    final actions = <String>[
      'Copy output',
      if (block.showReplayAction) 'Replay from here',
      if (block.showFailureSnapshotAction) 'Save failure snapshot',
      if (block.showDiffAction) 'Compare last run',
    ];

    return Wrap(
      spacing: palette.spacing.sm,
      runSpacing: palette.spacing.xs,
      children: [
        for (final action in actions)
          _ShellCommandBlockActionChip(label: action, palette: palette),
      ],
    );
  }
}

class _ShellCommandBlockActionChip extends StatelessWidget {
  const _ShellCommandBlockActionChip({
    required this.label,
    required this.palette,
  });

  final String label;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.selected.withValues(alpha: 0.64),
            borderRadius: BorderRadius.circular(palette.radius.sm),
            border: Border.all(color: palette.borderStrong),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: palette.spacing.md,
              vertical: palette.spacing.xs,
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
