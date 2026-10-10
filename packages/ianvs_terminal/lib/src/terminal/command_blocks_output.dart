part of 'command_blocks_view.dart';

/// Real terminal cells in both states. Completed blocks have no PTY write
/// capability; running blocks route keyboard/IME to the live terminal session.
class CommandBlockTerminal extends StatefulWidget {
  const CommandBlockTerminal({
    super.key,
    required this.block,
    this.liveInput,
    this.liveFocus,
    this.liveFocusSource,
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

  /// The same pane's editor may hand focus to its newly running terminal.
  /// An unrelated editor, modal or inactive window never gives that consent.
  final FocusNode? liveFocusSource;
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

class _CommandBlockTerminalState extends State<CommandBlockTerminal>
    with
        WidgetsBindingObserver,
        AutomaticKeepAliveClientMixin<CommandBlockTerminal> {
  final _viewport = TerminalViewportController();
  late final SelectionController _selection =
      widget.selectionController ?? SelectionController();
  late final _scroll = _BlockOutputScrollController(
    ancestor: () => mounted
        ? Scrollable.maybeOf(context, axis: Axis.vertical)?.position
        : null,
    onTrackpadActivityChanged: _trackpadActivityChanged,
  );
  bool _trackpadActive = false;
  bool _disposing = false;
  final _tailFollow = _CommandTailFollow();
  bool _followTail = true;
  Size? _cell;
  late TerminalInputController _input;
  int _inputRevision = 0;
  int _focusRevision = 0;
  bool _initialFocusChecked = false;

  @override
  bool get wantKeepAlive => _trackpadActive;

  void _trackpadActivityChanged(bool active) {
    if (!mounted || _disposing || _trackpadActive == active) return;
    // A lazy timeline must retain the gesture's recognizer even after its
    // starting block scrolls away. Release it when the native drag ends;
    // the outer position then owns its ballistic activity independently.
    _trackpadActive = active;
    updateKeepAlive();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_focusChanged);
    _updateFrame();
    _followOutput();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialFocusChecked) {
      _initialFocusChecked = true;
      if (widget.block.running) _focusRunning();
    }
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
    if (oldWidget.liveFocus != widget.liveFocus ||
        oldWidget.liveFocusSource != widget.liveFocusSource ||
        oldWidget.requestLiveFocus != widget.requestLiveFocus) {
      ++_focusRevision;
    }
    if (oldWidget.block.id != widget.block.id ||
        oldWidget.block.contextId != widget.block.contextId ||
        oldWidget.block.running != widget.block.running ||
        oldWidget.block.suspended != widget.block.suspended ||
        oldWidget.liveInput?.sessionId != widget.liveInput?.sessionId ||
        !identical(
          oldWidget.liveInput?.inputOwner,
          widget.liveInput?.inputOwner,
        )) {
      // A callback from the previous input owner must stay revoked even if
      // this same block becomes live again before a clipboard read returns.
      ++_inputRevision;
    }
    if (oldWidget.block != widget.block ||
        oldWidget.modes != widget.modes ||
        oldWidget.liveInput != widget.liveInput ||
        oldWidget.onCopySelection != widget.onCopySelection) {
      _updateFrame();
      _followOutput();
    }
    if ((oldWidget.liveFocus != widget.liveFocus ||
            !oldWidget.block.running ||
            oldWidget.block.suspended) &&
        widget.block.running &&
        !widget.block.suspended) {
      _focusRunning();
    }
  }

  void _focusChanged() => ++_focusRevision;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ++_focusRevision;
  }

  bool get _canRequestLiveFocus {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return mounted &&
        widget.requestLiveFocus &&
        widget.liveInput != null &&
        widget.block.running &&
        !widget.block.suspended &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed) &&
        ModalRoute.of(context)?.isCurrent != false;
  }

  void _focusRunning() {
    final target = widget.liveFocus;
    if (target == null || !_canRequestLiveFocus) return;
    final owner = FocusManager.instance.primaryFocus;
    if (owner != null &&
        owner is! FocusScopeNode &&
        owner != target &&
        owner != widget.liveFocusSource) {
      return;
    }
    final focusRevision = _focusRevision;
    final inputRevision = _inputRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_canRequestLiveFocus &&
          focusRevision == _focusRevision &&
          inputRevision == _inputRevision &&
          FocusManager.instance.primaryFocus == owner &&
          widget.liveFocus == target &&
          target.canRequestFocus) {
        target.requestFocus();
      }
    });
  }

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
    if (block.running && !block.suspended && rows.isEmpty) {
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
          visible:
              block.running &&
              !block.suspended &&
              cursor >= 0 &&
              !widget.modes.hideCursor,
        ),
        viewportRows: rows.length.clamp(1, 2048),
        viewportCols: block.columns,
        dirtyRanges: const [],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
        modes: widget.modes,
      ),
    );
    final live = block.running && !block.suspended ? widget.liveInput : null;
    final revision = _inputRevision;
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
        : _LiveBlockInput(
            sessionId: live.sessionId,
            inputOwner: live.inputOwner,
            runtime: _BlockInputSink(
              live.runtime,
              () =>
                  mounted &&
                  revision == _inputRevision &&
                  widget.block.running &&
                  !widget.block.suspended &&
                  widget.liveInput != null,
            ),
            emulation: live.emulation,
            readFrame: () => _viewport.frame,
            readSelection: () => _selection.textForFrame(_viewport.frame),
            copySelection: live.copyText,
            readClipboard: live.readClipboard,
          );
  }

  @override
  void dispose() {
    _disposing = true;
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_focusChanged);
    ++_inputRevision;
    _viewport.dispose();
    if (widget.selectionController == null) _selection.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
            readOnly:
                !widget.block.running ||
                widget.block.suspended ||
                widget.liveInput == null,
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
              readOnly:
                  !widget.block.running ||
                  widget.block.suspended ||
                  widget.liveInput == null,
              selectionHitTest: widget.selectionHitTest,
              canScrollSelection: widget.canScrollSelection,
              captureSelectionText: widget.captureSelectionText,
              focusNode: widget.block.running && !widget.block.suspended
                  ? widget.liveFocus
                  : null,
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

/// Flutter's inner vertical recognizer wins even when the output is already
/// at an edge. Keep its drag protocol, but choose one scroll position for the
/// entire trackpad gesture before the first update. Wheel signals keep their
/// existing resolver, and horizontal/touch gestures keep their recognizers.
class _BlockOutputScrollController extends ScrollController {
  _BlockOutputScrollController({
    required this.ancestor,
    required this.onTrackpadActivityChanged,
  });

  final ScrollPosition? Function() ancestor;
  final ValueChanged<bool> onTrackpadActivityChanged;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _BlockOutputScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
    ancestor: ancestor,
    onTrackpadActivityChanged: onTrackpadActivityChanged,
  );
}

class _BlockOutputScrollPosition extends ScrollPositionWithSingleContext {
  _BlockOutputScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    required this.ancestor,
    required this.onTrackpadActivityChanged,
  });

  final ScrollPosition? Function() ancestor;
  final ValueChanged<bool> onTrackpadActivityChanged;
  _BlockTrackpadDrag? _trackpadDrag;

  @override
  void absorb(ScrollPosition other) {
    if (other is _BlockOutputScrollPosition) {
      // Flutter transfers its native drag when density/physics replaces a
      // position. Keep the recognizer's wrapper and keep-alive owner with it.
      _trackpadDrag = other._trackpadDrag;
      other._trackpadDrag = null;
      _trackpadDrag?.position = this;
    }
    super.absorb(other);
  }

  Drag _dragInside(DragStartDetails details, VoidCallback onDispose) =>
      super.drag(details, onDispose);

  @override
  Drag drag(DragStartDetails details, VoidCallback dragCancelCallback) {
    if (details.kind != PointerDeviceKind.trackpad) {
      return super.drag(details, dragCancelCallback);
    }
    _trackpadDrag?.cancel();
    late final _BlockTrackpadDrag drag;
    drag = _BlockTrackpadDrag(
      position: this,
      start: (update, onDispose) {
        final position = drag.position;
        final delta = update.primaryDelta ?? update.delta.dy;
        final outward =
            delta > 0 && position.pixels <= position.minScrollExtent + .1 ||
            delta < 0 && position.pixels >= position.maxScrollExtent - .1;
        final outer = outward ? position.ancestor() : null;
        if (outer != null && !identical(outer, position)) {
          position.goIdle();
          final outerContext = outer.context.storageContext;
          final outerScrollable = outer.context;
          final outerDrag = outer.drag(details, onDispose);
          final outerActivity = outer.activity;
          drag.detachDelegate = () {
            // The output can unmount while its ancestor remains. Stop that
            // drag after tree finalization, without dispatching notifications
            // through inactive elements or cancelling a newer ancestor drag.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!outerContext.mounted) return;
              final currentOuter = outerScrollable is ScrollableState
                  ? outerScrollable.position
                  : outer;
              if (identical(currentOuter.activity, outerActivity)) {
                outerDrag.cancel();
              }
            });
          };
          return outerDrag;
        }
        return position._dragInside(details, onDispose);
      },
      onEmptyEnd: () => drag.position.goBallistic(0),
      onDispose: () {
        final position = drag.position;
        if (identical(position._trackpadDrag, drag)) {
          position._trackpadDrag = null;
          position.onTrackpadActivityChanged(false);
        }
        dragCancelCallback();
      },
    );
    _trackpadDrag = drag;
    onTrackpadActivityChanged(true);
    return drag;
  }

  @override
  void dispose() {
    _trackpadDrag?.detach();
    super.dispose();
  }
}

class _BlockTrackpadDrag implements Drag {
  _BlockTrackpadDrag({
    required this.position,
    required this.start,
    required this.onEmptyEnd,
    required this.onDispose,
  });

  _BlockOutputScrollPosition position;
  final Drag Function(DragUpdateDetails, VoidCallback) start;
  final VoidCallback onEmptyEnd;
  final VoidCallback onDispose;
  Drag? _delegate;
  VoidCallback? detachDelegate;
  bool _disposed = false;

  @override
  void update(DragUpdateDetails details) {
    if (_disposed || details.delta.dy == 0) return;
    _delegate ??= start(details, _dispose);
    _delegate?.update(details);
  }

  @override
  void end(DragEndDetails details) {
    if (_disposed) return;
    if (_delegate case final drag?) {
      drag.end(details);
    } else {
      onEmptyEnd();
      _dispose();
    }
  }

  @override
  void cancel() {
    if (_disposed) return;
    if (_delegate case final drag?) {
      drag.cancel();
    } else {
      onEmptyEnd();
    }
    _dispose();
  }

  void _dispose() {
    if (_disposed) return;
    _disposed = true;
    onDispose();
  }

  void detach() {
    if (_disposed) return;
    detachDelegate?.call();
    _dispose();
  }
}

/// Retains the host's write policy and also revokes callbacks belonging to a
/// completed, suspended, inactive or unmounted block. This boundary runs after
/// asynchronous clipboard reads as well as for immediate key/IME/mouse input.
class _BlockInputSink implements TerminalProtocolInputSink {
  const _BlockInputSink(this.delegate, this.isCurrent);

  final TerminalInputSink delegate;
  final bool Function() isCurrent;

  @override
  void sendInput(String sessionId, Uint8List bytes) {
    if (isCurrent()) delegate.sendInput(sessionId, bytes);
  }

  @override
  void sendProtocolInput(String sessionId, Uint8List bytes) {
    if (!isCurrent()) return;
    final sink = delegate;
    if (sink is TerminalProtocolInputSink) {
      sink.sendProtocolInput(sessionId, bytes);
    } else {
      sink.sendInput(sessionId, bytes);
    }
  }
}

class _LiveBlockInput extends TerminalInputController {
  _LiveBlockInput({
    required this.inputOwner,
    required super.sessionId,
    required super.runtime,
    required super.emulation,
    required super.readFrame,
    required super.readSelection,
    required super.copySelection,
    required super.readClipboard,
  });

  // Replacing a revocable wrapper on output updates is not a new focus owner.
  @override
  final Object inputOwner;
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
