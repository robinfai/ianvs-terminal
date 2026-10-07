part of 'command_blocks_view.dart';

/// Real terminal cells in both states. Completed blocks have no PTY write
/// capability; running blocks route keyboard/IME to the live terminal session.
class CommandBlockTerminal extends StatefulWidget {
  const CommandBlockTerminal({
    super.key,
    required this.block,
    this.liveInput,
    this.liveFocus,
    this.modes = TerminalFrameModes.empty,
    this.font = const TerminalFontConfig(),
    this.onMeasuredCellSizeChanged,
    this.onOpenLinkTarget,
    this.onScrollLines,
    this.maxHeight = double.infinity,
    this.previewLines,
    this.scrollOutput = true,
    this.scrollHorizontally = true,
    this.requestLiveFocus = true,
    this.selectionController,
    this.onCopySelection,
    this.selectionHitTest,
    this.canScrollSelection,
    this.captureSelectionText,
    this.highlightedRow,
  });
  final CommandBlock block;
  final TerminalInputController? liveInput;
  final FocusNode? liveFocus;
  final TerminalFrameModes modes;
  final TerminalFontConfig font;
  final ValueChanged<Size>? onMeasuredCellSizeChanged;
  final ValueChanged<TerminalLinkTarget>? onOpenLinkTarget;
  final ValueChanged<int>? onScrollLines;

  /// A viewport budget, rounded down to whole terminal rows after measuring
  /// the actual font. Infinity exposes the entire retained output page.
  final double maxHeight;
  final int? previewLines;
  final bool scrollOutput;
  final bool scrollHorizontally;
  final bool requestLiveFocus;
  final SelectionController? selectionController;

  /// Readers can resolve a shared selection across native output pages.
  final Future<void> Function()? onCopySelection;
  final TerminalSelectionTarget? Function(Offset globalPosition)?
  selectionHitTest;
  final bool Function(int deltaLines)? canScrollSelection;
  final Future<String> Function()? captureSelectionText;

  /// A reader's current find result, independent of its copy/attachment selection.
  final int? highlightedRow;
  @override
  State<CommandBlockTerminal> createState() => _CommandBlockTerminalState();
}

class _CommandBlockTerminalState extends State<CommandBlockTerminal> {
  final _viewport = TerminalViewportController();
  late final SelectionController _selection =
      widget.selectionController ?? SelectionController();
  final _scroll = ScrollController();
  final _tailFollow = _CommandTailFollow();
  bool _followTail = true;
  Size? _cell;
  late TerminalInputController _input;
  @override
  void initState() {
    super.initState();
    _updateFrame();
    _followOutput();
    if (widget.block.running) _focusRunning();
  }

  void _followOutput() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _followTail && _scroll.hasClients) {
      final end = _scroll.position.maxScrollExtent;
      if ((_scroll.offset - end).abs() > .1) _scroll.jumpTo(end);
    }
  });

  @override
  void didUpdateWidget(CommandBlockTerminal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block != widget.block ||
        oldWidget.modes != widget.modes ||
        oldWidget.liveInput != widget.liveInput ||
        oldWidget.onCopySelection != widget.onCopySelection) {
      _updateFrame();
      _followOutput();
    }
    if ((oldWidget.liveFocus != widget.liveFocus || !oldWidget.block.running) &&
        widget.block.running) {
      _focusRunning();
    }
  }

  void _focusRunning() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && widget.requestLiveFocus && widget.block.running) {
      widget.liveFocus?.requestFocus();
    }
  });
  void _updateFrame() {
    final block = widget.block;
    final start = widget.previewLines == null
        ? 0
        : (block.lines.length - widget.previewLines!).clamp(
            0,
            block.lines.length,
          );
    final visibleLines = block.lines.skip(start).toList();
    final rows = <TerminalRow>[
      for (var i = 0; i < visibleLines.length; i++)
        TerminalRow(
          index: i,
          text: visibleLines[i].text,
          wrapped: visibleLines[i].wrapped,
          styleRuns: visibleLines[i].styleRuns,
          sourceRow: visibleLines[i].index,
          sourceEndRow: visibleLines[i].index,
        ),
    ];
    var cursor = visibleLines.indexWhere(
      (row) => row.index == block.cursorLine,
    );
    if (block.running && rows.isEmpty) {
      rows.add(
        TerminalRow(
          index: 0,
          text: '',
          wrapped: false,
          sourceRow: block.cursorLine,
          sourceEndRow: block.cursorLine,
        ),
      );
      cursor = 0;
    }
    _viewport.updateFrame(
      TerminalFrameDiff(
        rows: rows,
        hyperlinks: [
          for (final link in block.hyperlinks)
            if (link.row >= start)
              TerminalHyperlinkRange(
                row: link.row - start,
                startCol: link.startCol,
                endCol: link.endCol,
                uri: link.uri,
                protocolId: link.protocolId,
              ),
        ],
        cursor: TerminalCursor(
          row: cursor.clamp(0, 2047),
          col: block.cursorColumn,
          visible: block.running && cursor >= 0 && !widget.modes.hideCursor,
        ),
        viewportRows: rows.length.clamp(1, 2048),
        viewportCols: block.columns,
        dirtyRanges: const [],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
        modes: widget.modes,
      ),
    );
    final live = block.running ? widget.liveInput : null;
    _input = live == null
        ? _ReadOnlyBlockInput(
            copyRange: widget.onCopySelection,
            sessionId: block.id,
            runtime: const _ReadOnlyBlockSink(),
            readFrame: () => _viewport.frame,
            readSelection: () => _selection.textForFrame(_viewport.frame),
            copySelection: (text) =>
                Clipboard.setData(ClipboardData(text: text)),
            readClipboard: () async => '',
          )
        : TerminalInputController(
            sessionId: live.sessionId,
            runtime: live.runtime,
            emulation: live.emulation,
            readFrame: () => _viewport.frame,
            readSelection: () => _selection.textForFrame(_viewport.frame),
            copySelection: live.copyText,
            readClipboard: live.readClipboard,
          );
  }

  @override
  void dispose() {
    _viewport.dispose();
    if (widget.selectionController == null) _selection.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ComposerTheme.of(context);
    final scale = MediaQuery.textScalerOf(context);
    final cellHeight =
        _cell?.height ?? scale.scale(widget.font.size) * widget.font.lineHeight;
    final cellWidth = _cell?.width ?? scale.scale(widget.font.size) * .61;
    final rows = _viewport.frame.viewportRows;
    return LayoutBuilder(
      builder: (context, constraints) {
        final budget = widget.maxHeight < constraints.maxHeight
            ? widget.maxHeight
            : constraints.maxHeight;
        final visibleRows = budget.isFinite
            ? (budget / cellHeight).floor().clamp(0, rows)
            : rows;
        final scrollable = visibleRows < rows;
        Widget output = SizedBox(
          width: (widget.block.columns * cellWidth).clamp(
            constraints.maxWidth,
            double.infinity,
          ),
          height: rows * cellHeight,
          child: Semantics(
            readOnly: !widget.block.running,
            child: TerminalViewport(
              controller: _viewport,
              selectionController: _selection,
              searchMatches: [
                for (var i = 0; i < widget.block.lines.length; i++)
                  if (widget.block.lines[i].index == widget.highlightedRow)
                    TerminalSearchMatch(
                      row: widget.block.lines[i].index,
                      startCol: 0,
                      endCol: widget.block.columns,
                      text: widget.block.lines[i].text,
                      scrollbackOffset: 0,
                    ),
              ],
              activeSearchMatchIndex: 0,
              inputController: _input,
              readOnly: widget.liveInput == null,
              selectionHitTest: widget.selectionHitTest,
              canScrollSelection: widget.canScrollSelection,
              captureSelectionText: widget.captureSelectionText,
              focusNode: widget.block.running ? widget.liveFocus : null,
              onScrollLines: widget.onScrollLines ?? (_) {},
              onScrollToOffset: (_) {},
              onMeasuredCellSizeChanged: (size) {
                widget.onMeasuredCellSizeChanged?.call(size);
                if (_cell != size) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _cell != size) {
                      setState(() => _cell = size);
                    }
                  });
                }
              },
              onOpenLinkTarget: widget.onOpenLinkTarget,
              useFrameDefaultColors: false,
              altClickMovesCursor: false,
              // The enclosing scrollables own pixel deltas and inertia. This
              // terminal renders the full page and has no native scrollback.
              handleScrollGestures: false,
              font: widget.font,
              colors: TerminalViewportColors(
                canvasBackground: tokens.surface,
                foreground: tokens.foreground,
                cursor: tokens.accent,
                selection: tokens.selection,
                scrollbarTrack: tokens.surface,
                scrollbarThumb: tokens.border,
                minimumContrastRatio: 4.5,
              ),
            ),
          ),
        );
        if (widget.scrollHorizontally) {
          output = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: output,
          );
        }
        if (widget.scrollOutput) {
          output = NotificationListener<ScrollNotification>(
            onNotification: (notification) => _tailFollow.handle(
              notification,
              distance: cellHeight * 2,
              detach: () => _followTail = false,
              attach: () {
                _followTail = true;
                _followOutput();
              },
            ),
            child: Scrollbar(
              controller: _scroll,
              child: SingleChildScrollView(
                key: ValueKey('block-output-scroll-${widget.block.id}'),
                controller: _scroll,
                primary: false,
                physics: scrollable
                    ? null
                    : const NeverScrollableScrollPhysics(),
                child: output,
              ),
            ),
          );
        }
        return SizedBox(height: visibleRows * cellHeight, child: output);
      },
    );
  }
}

class _ReadOnlyBlockSink implements TerminalInputSink {
  const _ReadOnlyBlockSink();
  @override
  void sendInput(String sessionId, Uint8List bytes) {}
}

class _ReadOnlyBlockInput extends TerminalInputController {
  _ReadOnlyBlockInput({
    this.copyRange,
    required super.sessionId,
    required super.runtime,
    required super.readFrame,
    required super.readSelection,
    required super.copySelection,
    required super.readClipboard,
  });
  final Future<void> Function()? copyRange;
  @override
  Future<void> copySelection() => copyRange?.call() ?? super.copySelection();
  @override
  KeyEventResult handle(KeyEvent event) {
    final keys = HardwareKeyboard.instance;
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyC &&
        (keys.isMetaPressed || keys.isControlPressed && keys.isShiftPressed)) {
      unawaited(copySelection());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}
