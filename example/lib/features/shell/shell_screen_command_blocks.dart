part of 'shell_screen.dart';

const int shellCommandBlockPreviewMaxRows = 8;
const int shellCommandBlockLiveTerminalMaxRows = 60;
const int shellCommandBlockLiveTerminalPaddingRows = 3;

typedef ShellCommandBlockLiveTerminalBuilder =
    Widget Function(BuildContext context, ShellCommandBlockOverlayItem block);
typedef ShellCommandBlockActionCallback =
    void Function(ShellCommandBlockOverlayItem block, Rect anchorRect);

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
                            liveTerminalRows: widget.liveTerminalRows,
                            liveTerminalBuilder: widget.liveTerminalBuilder,
                            onOpenBlockActions: widget.onOpenBlockActions,
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
    required this.liveTerminalRows,
    required this.liveTerminalBuilder,
    required this.onOpenBlockActions,
  });

  final ShellCommandBlockOverlayItem block;
  final double rowHeight;
  final terminal.TerminalViewportColors colors;
  final terminal.TerminalFontConfig font;
  final terminal.TerminalCursorConfig cursor;
  final int liveTerminalRows;
  final ShellCommandBlockLiveTerminalBuilder? liveTerminalBuilder;
  final ShellCommandBlockActionCallback? onOpenBlockActions;

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
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _ShellCommandBlockStatusDot(color: statusColor),
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
                              if (metadata.isNotEmpty) ...[
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
                              _ShellCommandBlockInfoButton(
                                block: block,
                                palette: palette,
                                statusColor: statusColor,
                              ),
                              if (onOpenBlockActions != null) ...[
                                SizedBox(width: palette.spacing.xs),
                                Builder(
                                  builder: (buttonContext) {
                                    return IconButton(
                                      key: Key(
                                        'shell-command-block-actions-${block.id}',
                                      ),
                                      tooltip: 'Block actions',
                                      onPressed: () => onOpenBlockActions!(
                                        block,
                                        _globalRectForContext(buttonContext),
                                      ),
                                      style: IconButton.styleFrom(
                                        foregroundColor: palette.textPrimary,
                                        fixedSize: const Size.square(44),
                                        minimumSize: const Size.square(44),
                                        maximumSize: const Size.square(44),
                                        padding: EdgeInsets.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.padded,
                                      ),
                                      icon: const Icon(
                                        Icons.more_horiz,
                                        semanticLabel: 'Block actions',
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
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
    this.contextChips = const <String>[],
    this.contextOptions = const <UniversalInputToolOption>[],
    this.modelLabel = 'Local heuristic',
    this.onModeChanged,
    this.onChanged,
    this.onContextSelected,
    this.onModelSelected,
    this.onOpenCommandSearch,
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
  final List<String> contextChips;
  final List<UniversalInputToolOption> contextOptions;
  final String modelLabel;
  final ValueChanged<UniversalInputMode>? onModeChanged;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onContextSelected;
  final ValueChanged<String>? onModelSelected;
  final VoidCallback? onOpenCommandSearch;

  @override
  State<ShellCommandInputBar> createState() => _ShellCommandInputBarState();
}

class _ShellCommandInputBarState extends State<ShellCommandInputBar> {
  int _activeSuggestionIndex = 0;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeTokens.of(context);

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
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.controller,
          builder: (context, value, _) {
            final text = value.text;
            final classification = _classificationFor(text);
            final suggestions = _suggestionsFor(text, classification);
            final accent = _universalInputAccentColor(palette, classification);
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
              children: [
                Row(
                  children: [
                    _UniversalInputModeSwitcher(
                      keyPrefix: 'shell-command-input',
                      mode: widget.inputMode,
                      palette: palette,
                      onModeChanged: _handleModeChanged,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _UniversalInputStatusPill(
                        key: const Key('shell-command-input-detection-label'),
                        label: _universalInputStatusLabel(
                          widget.inputMode,
                          classification,
                        ),
                        accent: accent,
                        palette: palette,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _UniversalInputModelBadge(
                      keyPrefix: 'shell-command-input',
                      label: widget.modelLabel,
                      palette: palette,
                    ),
                  ],
                ),
                if (widget.contextChips.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final chip in widget.contextChips) ...[
                            _UniversalInputContextChip(
                              label: chip,
                              palette: palette,
                            ),
                            const SizedBox(width: 5),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Icon(
                        _universalInputLeadingIcon(classification),
                        size: 18,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: _UniversalInputToolMenuButton(
                        key: const Key('shell-command-input-context'),
                        tooltip: 'Add context',
                        icon: Icons.alternate_email_rounded,
                        options: widget.contextOptions,
                        palette: palette,
                        onSelected: _handleContextSelected,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: _UniversalInputToolMenuButton(
                        key: const Key('shell-command-input-slash'),
                        tooltip: 'Slash commands',
                        icon: Icons.bolt_rounded,
                        options: _universalInputSlashCommandOptions,
                        palette: palette,
                        onSelected: _insertSnippet,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: _UniversalInputToolMenuButton(
                        key: const Key('shell-command-input-model'),
                        tooltip: 'Model picker',
                        icon: Icons.tune_rounded,
                        options: _universalInputModelOptions,
                        palette: palette,
                        onSelected: _handleModelSelected,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: CallbackShortcuts(
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
                        child: Focus(
                          canRequestFocus: false,
                          skipTraversal: true,
                          onKeyEvent: (node, event) => _handleKeyEvent(
                            context,
                            node,
                            event,
                            classification,
                            suggestions,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 168),
                            child: Semantics(
                              container: true,
                              label: 'Command input',
                              hint: fieldHint,
                              textField: true,
                              enabled: widget.enabled,
                              child: TextField(
                                key: const Key('shell-command-input-field'),
                                controller: widget.controller,
                                focusNode: widget.focusNode,
                                enabled: widget.enabled,
                                autofocus: widget.enabled,
                                minLines: 1,
                                maxLines: null,
                                keyboardType: TextInputType.multiline,
                                textInputAction: TextInputAction.newline,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: palette.textPrimary,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.w600,
                                    ),
                                decoration: InputDecoration(
                                  hintText: fieldHint,
                                  isDense: true,
                                  filled: true,
                                  fillColor: palette.terminalSurface,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: palette.spacing.md,
                                    vertical: palette.spacing.sm,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      palette.radius.md,
                                    ),
                                    borderSide: BorderSide(
                                      color: palette.border,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      palette.radius.md,
                                    ),
                                    borderSide: BorderSide(
                                      color: palette.border,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      palette.radius.md,
                                    ),
                                    borderSide: BorderSide(
                                      color: accent,
                                      width: 1.4,
                                    ),
                                  ),
                                ),
                                onChanged: _handleTextChanged,
                              ),
                            ),
                          ),
                        ),
                      ),
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
                    _buildCompactActionButton(
                      key: const Key('shell-command-run-button'),
                      tooltip: _universalInputSendTooltip(classification),
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
                if (suggestions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  const Divider(height: 1),
                  const SizedBox(height: 4),
                  for (
                    var index = 0;
                    index < suggestions.length && index < 4;
                    index++
                  )
                    _AutoComposerSuggestionTile(
                      suggestion: suggestions[index],
                      active: index == effectiveActiveIndex,
                      palette: palette,
                      onTap: () =>
                          _acceptSuggestion(suggestions[index], classification),
                    ),
                ],
              ],
            );
          },
        ),
      ),
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

  KeyEventResult _handleKeyEvent(
    BuildContext context,
    FocusNode node,
    KeyEvent event,
    UniversalInputClassification classification,
    List<String> suggestions,
  ) {
    final key = event.logicalKey;
    final isEnter =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) {
      return KeyEventResult.handled;
    }
    if (_hasActiveComposing) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      _insertText('\n');
      return KeyEventResult.handled;
    }
    unawaited(
      _submit(
        context,
        widget.controller.text,
        classification,
        _prioritizedSuggestions(
          suggestions,
          suggestions.isEmpty
              ? -1
              : _activeSuggestionIndex.clamp(0, suggestions.length - 1),
        ),
      ),
    );
    return KeyEventResult.handled;
  }

  bool get _hasActiveComposing {
    final composing = widget.controller.value.composing;
    return composing.isValid && !composing.isCollapsed;
  }

  void _insertText(String text) {
    final current = widget.controller.value;
    final currentText = current.text;
    final selection = current.selection;
    final start = selection.isValid
        ? selection.start.clamp(0, currentText.length).toInt()
        : currentText.length;
    final end = selection.isValid
        ? selection.end.clamp(0, currentText.length).toInt()
        : currentText.length;
    final replaceStart = math.min(start, end);
    final replaceEnd = math.max(start, end);
    final nextText = currentText.replaceRange(replaceStart, replaceEnd, text);
    final nextOffset = replaceStart + text.length;
    widget.controller.value = current.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
      composing: TextRange.empty,
    );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Natural language detected. Choose a command suggestion or switch to Terminal mode.',
          ),
        ),
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
    final mode = switch (text) {
      '* ' || '＊ ' => UniversalInputMode.agent,
      '! ' || '！ ' => UniversalInputMode.terminal,
      _ => null,
    };
    if (mode != null && widget.onModeChanged != null) {
      widget.controller.clear();
      widget.onModeChanged!(mode);
      _restoreTextInputFocus();
      setState(() {
        _activeSuggestionIndex = 0;
      });
      return;
    }
    widget.onChanged?.call(text);
    setState(() {
      _activeSuggestionIndex = 0;
    });
  }

  void _handleModeChanged(UniversalInputMode mode) {
    if (!widget.enabled) {
      return;
    }
    widget.onModeChanged?.call(mode);
    setState(() {
      _activeSuggestionIndex = 0;
    });
    _restoreTextInputFocus();
  }

  void _handleContextSelected(String value) {
    widget.onContextSelected?.call(value);
    _restoreTextInputFocus();
  }

  void _handleModelSelected(String value) {
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
