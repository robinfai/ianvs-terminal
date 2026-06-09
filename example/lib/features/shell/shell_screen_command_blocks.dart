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

    final palette = AppThemeTokens.of(context);

    return IgnorePointer(
      child: Padding(
        padding: contentPadding,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth.isFinite
                ? math.min(860.0, constraints.maxWidth - 16)
                : 860.0;
            final maxHeight = constraints.maxHeight.isFinite
                ? math.max(96.0, constraints.maxHeight * 0.48)
                : 360.0;
            return Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxWidth,
                  maxHeight: maxHeight,
                ),
                child: ClipRect(
                  child: SingleChildScrollView(
                    reverse: true,
                    physics: const NeverScrollableScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final block in viewModel.blocks.reversed)
                          Padding(
                            key: Key('shell-command-block-${block.id}'),
                            padding: EdgeInsets.only(top: palette.spacing.sm),
                            child: _ShellCommandBlockChrome(block: block),
                          ),
                      ],
                    ),
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
    final background = Color.alphaBlend(
      statusColor.withValues(alpha: block.active ? 0.14 : 0.08),
      palette.panelElevated,
    );
    final borderColor = block.active
        ? statusColor.withValues(alpha: 0.78)
        : palette.border.withValues(alpha: 0.58);
    final hasOutputPreview = block.outputPreview.trim().isNotEmpty;
    final metadata = <String>[
      if (block.cwd?.trim().isNotEmpty == true) block.cwd!.trim(),
      block.durationLabel,
      if (block.outputRangeLabel.trim().isNotEmpty) block.outputRangeLabel,
    ];

    return DecoratedBox(
      key: Key('shell-command-block-card-${block.id}'),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(palette.radius.md),
        border: Border.all(color: borderColor),
        boxShadow: block.active ? palette.elevation.floating : const [],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: block.active ? 4 : 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(palette.radius.md),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(palette.spacing.lg),
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
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: palette.textPrimary,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SizedBox(width: palette.spacing.md),
                        _ShellCommandBlockMetaPill(
                          label: block.statusLabel,
                          foreground: statusColor,
                          palette: palette,
                        ),
                      ],
                    ),
                    if (metadata.isNotEmpty) ...[
                      SizedBox(height: palette.spacing.sm),
                      Wrap(
                        spacing: palette.spacing.sm,
                        runSpacing: palette.spacing.xs,
                        children: [
                          for (final label in metadata)
                            _ShellCommandBlockMetaPill(
                              label: label,
                              foreground: palette.textMuted,
                              palette: palette,
                            ),
                        ],
                      ),
                    ],
                    if (hasOutputPreview) ...[
                      SizedBox(height: palette.spacing.sm),
                      _ShellCommandBlockOutputPreview(
                        text: block.outputPreview,
                        palette: palette,
                      ),
                    ],
                    SizedBox(height: palette.spacing.sm),
                    _ShellCommandBlockStatusHints(
                      block: block,
                      palette: palette,
                    ),
                  ],
                ),
              ),
            ),
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

class _ShellCommandBlockMetaPill extends StatelessWidget {
  const _ShellCommandBlockMetaPill({
    required this.label,
    required this.foreground,
    required this.palette,
  });

  final String label;
  final Color foreground;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.terminalSurface,
        borderRadius: BorderRadius.circular(palette.radius.sm),
        border: Border.all(color: palette.border.withValues(alpha: 0.62)),
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
            color: foreground,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ShellCommandBlockOutputPreview extends StatelessWidget {
  const _ShellCommandBlockOutputPreview({
    required this.text,
    required this.palette,
  });

  final String text;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.terminalSurface,
        borderRadius: BorderRadius.circular(palette.radius.sm),
        border: Border.all(color: palette.border.withValues(alpha: 0.52)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: palette.spacing.md,
            vertical: palette.spacing.sm,
          ),
          child: Text(
            text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: palette.textMuted,
              fontFamily: 'monospace',
              height: 1.22,
            ),
          ),
        ),
      ),
    );
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
        color: palette.terminalSurface.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(palette.radius.sm),
        border: Border.all(color: palette.border.withValues(alpha: 0.34)),
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
            color: palette.textSubtle,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class ShellCommandInputBar extends StatelessWidget {
  const ShellCommandInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onSubmitted,
    this.cwd,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final String? cwd;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeTokens.of(context);
    final theme = Theme.of(context);
    final cwdLabel = cwd?.trim();

    return DecoratedBox(
      key: const Key('shell-command-input-bar'),
      decoration: BoxDecoration(
        color: palette.chrome,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: palette.spacing.lg,
          vertical: palette.spacing.sm,
        ),
        child: Row(
          children: [
            Icon(Icons.terminal, size: 16, color: palette.textSubtle),
            if (cwdLabel != null && cwdLabel.isNotEmpty) ...[
              SizedBox(width: palette.spacing.md),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  cwdLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: palette.textSubtle,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
            SizedBox(width: palette.spacing.md),
            Expanded(
              child: TextField(
                key: const Key('shell-command-input-field'),
                controller: controller,
                focusNode: focusNode,
                enabled: enabled,
                autofocus: enabled,
                textInputAction: TextInputAction.done,
                onSubmitted: _submit,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: palette.textPrimary,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'Command',
                  isDense: true,
                  filled: true,
                  fillColor: palette.terminalSurface,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: palette.spacing.md,
                    vertical: palette.spacing.sm,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(palette.radius.md),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(palette.radius.md),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(palette.radius.md),
                    borderSide: BorderSide(
                      color: palette.focusRing,
                      width: 1.4,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: palette.spacing.sm),
            Tooltip(
              message: 'Run command',
              child: IconButton(
                onPressed: enabled ? () => _submit(controller.text) : null,
                icon: const Icon(Icons.keyboard_return),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submit(String value) {
    final command = value.trim();
    if (command.isEmpty) {
      return;
    }
    onSubmitted(command);
    controller.clear();
    focusNode.requestFocus();
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
