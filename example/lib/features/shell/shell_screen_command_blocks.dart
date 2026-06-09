part of 'shell_screen.dart';

const int shellCommandBlockPreviewMaxRows = 8;

class ShellCommandBlocksOverlay extends StatefulWidget {
  const ShellCommandBlocksOverlay({
    super.key,
    required this.viewModel,
    required this.rowHeight,
    this.colors = terminal.TerminalViewportColors.light,
    this.font = const terminal.TerminalFontConfig(),
    this.cursor = const terminal.TerminalCursorConfig(),
    this.contentPadding = EdgeInsets.zero,
  });

  final ShellCommandBlocksOverlayViewModel viewModel;
  final double rowHeight;
  final terminal.TerminalViewportColors colors;
  final terminal.TerminalFontConfig font;
  final terminal.TerminalCursorConfig cursor;
  final EdgeInsetsGeometry contentPadding;

  @override
  State<ShellCommandBlocksOverlay> createState() =>
      _ShellCommandBlocksOverlayState();
}

class _ShellCommandBlocksOverlayState extends State<ShellCommandBlocksOverlay> {
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
                            rowHeight: widget.rowHeight,
                            colors: widget.colors,
                            font: widget.font,
                            cursor: widget.cursor,
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
    required this.rowHeight,
    required this.colors,
    required this.font,
    required this.cursor,
  });

  final ShellCommandBlockOverlayItem block;
  final double rowHeight;
  final terminal.TerminalViewportColors colors;
  final terminal.TerminalFontConfig font;
  final terminal.TerminalCursorConfig cursor;

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

    return ClipRRect(
      borderRadius: BorderRadius.circular(palette.radius.md),
      child: DecoratedBox(
        key: Key('shell-command-block-card-${block.id}'),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: borderColor),
          boxShadow: block.active ? palette.elevation.floating : const [],
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: block.active ? 4 : 3,
                child: ColoredBox(color: statusColor),
              ),
              Expanded(
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
                          Row(
                            children: [
                              _ShellCommandBlockStatusDot(color: statusColor),
                              SizedBox(width: palette.spacing.sm),
                              Expanded(
                                child: Text(
                                  inputLine,
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
                        ],
                      ),
                    ),
                    if (hasTerminalOutput)
                      _ShellCommandBlockTerminalOutput(
                        key: Key(
                          'shell-command-block-terminal-output-${block.id}',
                        ),
                        block: block,
                        rowHeight: rowHeight,
                        colors: colors,
                        font: font,
                        cursor: cursor,
                      ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        palette.spacing.lg,
                        hasTerminalOutput ? palette.spacing.sm : 0,
                        palette.spacing.lg,
                        palette.spacing.lg,
                      ),
                      child: _ShellCommandBlockStatusHints(
                        block: block,
                        palette: palette,
                      ),
                    ),
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
      ShellCommandBlockStatus.running => palette.warning,
      ShellCommandBlockStatus.unknown => palette.textSubtle,
    };
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
  });

  final ShellCommandBlockOverlayItem block;
  final double rowHeight;
  final terminal.TerminalViewportColors colors;
  final terminal.TerminalFontConfig font;
  final terminal.TerminalCursorConfig cursor;

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
    final rows = widget.block.terminalRows;
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
