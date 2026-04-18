import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'render_terminal_viewport.dart';
import 'selection_controller.dart';
import 'terminal_input_controller.dart';
import 'terminal_painter_models.dart';

const Key terminalScrollbarTrackKey = Key('terminal-scrollbar-track');
const Key terminalScrollbarThumbKey = Key('terminal-scrollbar-thumb');

class TerminalViewportController extends ChangeNotifier {
  TerminalFrameDiff _frame = TerminalFrameDiff.empty;

  TerminalFrameDiff get frame => _frame;

  void updateFrame(TerminalFrameDiff value) {
    _frame = value;
    notifyListeners();
  }
}

class TerminalViewport extends StatefulWidget {
  const TerminalViewport({
    super.key,
    required this.controller,
    required this.selectionController,
    required this.inputController,
    required this.onScrollLines,
    required this.onScrollToOffset,
    this.focusNode,
  });

  final TerminalViewportController controller;
  final SelectionController selectionController;
  final TerminalInputController inputController;
  final ValueChanged<int> onScrollLines;
  final ValueChanged<int> onScrollToOffset;
  final FocusNode? focusNode;

  @override
  State<TerminalViewport> createState() => _TerminalViewportState();
}

class _TerminalViewportState extends State<TerminalViewport> {
  Timer? _cursorBlinkTimer;
  bool _cursorVisible = true;
  FocusNode? _ownedFocusNode;
  final GlobalKey _surfaceKey = GlobalKey();
  double _pendingScrollLines = 0.0;

  FocusNode get _focusNode =>
      widget.focusNode ??
      (_ownedFocusNode ??= FocusNode(debugLabel: 'terminal-viewport'));

  @override
  void initState() {
    super.initState();
    _cursorBlinkTimer = Timer.periodic(const Duration(milliseconds: 650), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _cursorVisible = !_cursorVisible;
      });
    });
  }

  @override
  void dispose() {
    _cursorBlinkTimer?.cancel();
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  void _handleScrollDelta(double deltaY) {
    final lineHeight = _lineHeight;
    if (lineHeight <= 0) {
      return;
    }
    _pendingScrollLines += -deltaY / lineHeight;
    final deltaLines = _pendingScrollLines.round();
    if (deltaLines == 0) {
      return;
    }
    _pendingScrollLines -= deltaLines;
    widget.onScrollLines(deltaLines);
  }

  void _resetPendingScroll() {
    _pendingScrollLines = 0.0;
  }

  double get _lineHeight {
    final renderObject = _surfaceKey.currentContext?.findRenderObject();
    if (renderObject is RenderTerminalViewport) {
      return renderObject.debugCellSize.height;
    }
    if (renderObject is RenderBox) {
      final frame = widget.controller.frame;
      if (frame.viewportRows > 0 && renderObject.size.height > 0) {
        return renderObject.size.height / frame.viewportRows;
      }
    }
    return 18.0;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      focusNode: _focusNode,
      onKeyEvent: (_, event) => widget.inputController.handle(event),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _focusNode.requestFocus(),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              _handleScrollDelta(event.scrollDelta.dy);
            }
          },
          onPointerPanZoomStart: (_) => _resetPendingScroll(),
          onPointerPanZoomUpdate: (event) {
            _handleScrollDelta(event.panDelta.dy);
          },
          onPointerPanZoomEnd: (_) => _resetPendingScroll(),
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              final frame = widget.controller.frame;
              return LayoutBuilder(
                builder: (context, constraints) {
                  final trackHeight = math.max(0.0, constraints.maxHeight - 16);
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: _TerminalViewportSurface(
                          key: _surfaceKey,
                          controller: widget.controller,
                          selectionController: widget.selectionController,
                          cursorVisible: _cursorVisible,
                        ),
                      ),
                      if (frame.scrollbackMaxOffset > 0 && trackHeight > 0)
                        Positioned(
                          top: 8,
                          right: 6,
                          bottom: 8,
                          child: _TerminalScrollbar(
                            viewportRows: frame.viewportRows,
                            scrollbackOffset: frame.scrollbackOffset,
                            scrollbackMaxOffset: frame.scrollbackMaxOffset,
                            trackHeight: trackHeight,
                            onScrollToOffset: widget.onScrollToOffset,
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TerminalViewportSurface extends LeafRenderObjectWidget {
  const _TerminalViewportSurface({
    super.key,
    required this.controller,
    required this.selectionController,
    required this.cursorVisible,
  });

  final TerminalViewportController controller;
  final SelectionController selectionController;
  final bool cursorVisible;

  @override
  RenderTerminalViewport createRenderObject(BuildContext context) {
    return RenderTerminalViewport(
      controller: controller,
      selectionController: selectionController,
      cursorVisible: cursorVisible,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderTerminalViewport renderObject,
  ) {
    renderObject
      ..controller = controller
      ..selectionController = selectionController
      ..cursorVisible = cursorVisible
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  }
}

class _TerminalScrollbar extends StatefulWidget {
  const _TerminalScrollbar({
    required this.viewportRows,
    required this.scrollbackOffset,
    required this.scrollbackMaxOffset,
    required this.trackHeight,
    required this.onScrollToOffset,
  });

  final int viewportRows;
  final int scrollbackOffset;
  final int scrollbackMaxOffset;
  final double trackHeight;
  final ValueChanged<int> onScrollToOffset;

  @override
  State<_TerminalScrollbar> createState() => _TerminalScrollbarState();
}

class _TerminalScrollbarState extends State<_TerminalScrollbar> {
  double? _dragStartGlobalDy;
  double? _dragStartThumbTop;

  double get _thumbHeight {
    final totalRows = widget.viewportRows + widget.scrollbackMaxOffset;
    if (totalRows <= 0) {
      return widget.trackHeight;
    }
    final minThumbHeight = math.min(36.0, widget.trackHeight);
    final proportionalHeight =
        widget.trackHeight * (widget.viewportRows / totalRows);
    return proportionalHeight
        .clamp(minThumbHeight, widget.trackHeight)
        .toDouble();
  }

  double get _thumbTravelExtent =>
      math.max(0.0, widget.trackHeight - _thumbHeight);

  double get _thumbTop {
    if (widget.scrollbackMaxOffset <= 0 || _thumbTravelExtent == 0) {
      return _thumbTravelExtent;
    }
    final progress =
        1.0 - (widget.scrollbackOffset / widget.scrollbackMaxOffset);
    return _thumbTravelExtent * progress.clamp(0.0, 1.0).toDouble();
  }

  void _handleDragStart(DragStartDetails details) {
    _dragStartGlobalDy = details.globalPosition.dy;
    _dragStartThumbTop = _thumbTop;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final dragStartGlobalDy = _dragStartGlobalDy;
    final dragStartThumbTop = _dragStartThumbTop;
    if (dragStartGlobalDy == null || dragStartThumbTop == null) {
      return;
    }
    if (_thumbTravelExtent == 0 || widget.scrollbackMaxOffset <= 0) {
      widget.onScrollToOffset(widget.scrollbackMaxOffset);
      return;
    }
    final nextThumbTop =
        (dragStartThumbTop + (details.globalPosition.dy - dragStartGlobalDy))
            .clamp(0.0, _thumbTravelExtent)
            .toDouble();
    final nextProgress = nextThumbTop / _thumbTravelExtent;
    final nextOffset = ((1 - nextProgress) * widget.scrollbackMaxOffset)
        .round()
        .clamp(0, widget.scrollbackMaxOffset)
        .toInt();
    widget.onScrollToOffset(nextOffset);
  }

  void _handleDragEnd([DragEndDetails? _]) {
    _dragStartGlobalDy = null;
    _dragStartThumbTop = null;
  }

  void _handleDragCancel() {
    _handleDragEnd();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: terminalScrollbarTrackKey,
      width: 12,
      height: widget.trackHeight,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0x26FFFFFF),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Positioned(
            top: _thumbTop,
            left: 0,
            right: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: _handleDragStart,
              onVerticalDragUpdate: _handleDragUpdate,
              onVerticalDragEnd: _handleDragEnd,
              onVerticalDragCancel: _handleDragCancel,
              child: Container(
                key: terminalScrollbarThumbKey,
                height: _thumbHeight,
                decoration: BoxDecoration(
                  color: const Color(0x99FFFFFF),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
