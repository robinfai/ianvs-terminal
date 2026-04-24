import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'render_terminal_viewport.dart';
import 'selection_controller.dart';
import 'terminal_input_controller.dart';
import 'terminal_painter_models.dart';
import 'terminal_viewport_colors.dart';

const Key terminalScrollbarTrackKey = Key('terminal-scrollbar-track');
const Key terminalScrollbarThumbKey = Key('terminal-scrollbar-thumb');
const Size terminalFallbackCellSize = Size(9, 18);
final RegExp _visibleUrlPattern = RegExp(r'(?:https?|file)://[^\s<>()"]+');

class TerminalViewportController extends ChangeNotifier {
  TerminalFrameDiff _frame = TerminalFrameDiff.empty;
  Size? _measuredCellSize;

  TerminalFrameDiff get frame => _frame;
  Size? get measuredCellSize => _measuredCellSize;

  void updateFrame(TerminalFrameDiff value) {
    _frame = value;
    notifyListeners();
  }

  void updateMeasuredCellSize(Size value) {
    if (!value.isFinite ||
        value.width <= 0 ||
        value.height <= 0 ||
        _measuredCellSize == value) {
      return;
    }
    _measuredCellSize = value;
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
    this.onMeasuredCellSizeChanged,
    this.contentPadding = EdgeInsets.zero,
    this.colors,
    this.backgroundColor,
    this.foregroundColor,
    this.focusNode,
    this.onOpenLink,
  });

  final TerminalViewportController controller;
  final SelectionController selectionController;
  final TerminalInputController inputController;
  final ValueChanged<int> onScrollLines;
  final ValueChanged<int> onScrollToOffset;
  final ValueChanged<Size>? onMeasuredCellSizeChanged;
  final EdgeInsets contentPadding;
  final TerminalViewportColors? colors;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final FocusNode? focusNode;
  final ValueChanged<String>? onOpenLink;

  @override
  State<TerminalViewport> createState() => _TerminalViewportState();
}

class _TerminalViewportState extends State<TerminalViewport> {
  Timer? _cursorBlinkTimer;
  bool _cursorVisible = true;
  FocusNode? _ownedFocusNode;
  FocusNode? _listenedFocusNode;
  final GlobalKey _surfaceKey = GlobalKey();
  double _pendingScrollLines = 0.0;
  Size? _lastReportedCellSize;
  int? _activeMouseButton;
  bool? _lastReportedFocusTrackingFocus;

  FocusNode get _focusNode =>
      widget.focusNode ??
      (_ownedFocusNode ??= FocusNode(debugLabel: 'terminal-viewport'));

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleFrameUpdate);
    _bindFocusNodeListener();
    _syncCursorBlinkTimer();
  }

  @override
  void didUpdateWidget(covariant TerminalViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_handleFrameUpdate);
      widget.controller.addListener(_handleFrameUpdate);
    }
    if (!identical(oldWidget.focusNode, widget.focusNode)) {
      _unbindFocusNodeListener();
      _bindFocusNodeListener();
    }
    _syncCursorBlinkTimer();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleFrameUpdate);
    _unbindFocusNodeListener();
    _cursorBlinkTimer?.cancel();
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  void _bindFocusNodeListener() {
    final focusNode = _focusNode;
    _listenedFocusNode = focusNode;
    focusNode.addListener(_handleFocusChange);
  }

  void _unbindFocusNodeListener() {
    _listenedFocusNode?.removeListener(_handleFocusChange);
    _listenedFocusNode = null;
  }

  void _handleFrameUpdate() {
    if (!mounted) {
      return;
    }
    _syncFocusTrackingReport();
    _syncCursorBlinkTimer();
    _scheduleMeasuredCellSizeReport();
  }

  void _handleFocusChange() {
    if (!mounted) {
      return;
    }
    _syncFocusTrackingReport();
    _syncCursorBlinkTimer();
  }

  void _syncFocusTrackingReport() {
    final modes = widget.controller.frame.modes;
    if (!modes.focusTracking) {
      _lastReportedFocusTrackingFocus = null;
      return;
    }
    final focused = _focusNode.hasFocus;
    if (_lastReportedFocusTrackingFocus == focused) {
      return;
    }
    _lastReportedFocusTrackingFocus = focused;
    widget.inputController.sendFocusReport(focused: focused);
  }

  void _scheduleMeasuredCellSizeReport() {
    if (widget.onMeasuredCellSizeChanged == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final renderObject = _surfaceKey.currentContext?.findRenderObject();
      if (renderObject is! RenderTerminalViewport) {
        return;
      }
      final measured = renderObject.debugCellSize;
      if (measured.width <= 0 || measured.height <= 0) {
        return;
      }
      if (_lastReportedCellSize == measured) {
        return;
      }
      _lastReportedCellSize = measured;
      widget.onMeasuredCellSizeChanged?.call(measured);
    });
  }

  bool get _shouldBlinkCursor {
    final frameCursorVisible = widget.controller.frame.cursor.visible;
    return _focusNode.hasFocus && frameCursorVisible;
  }

  void _syncCursorBlinkTimer() {
    if (_shouldBlinkCursor) {
      _cursorBlinkTimer ??= Timer.periodic(const Duration(milliseconds: 650), (
        _,
      ) {
        if (!mounted || !_shouldBlinkCursor) {
          return;
        }
        setState(() {
          _cursorVisible = !_cursorVisible;
        });
      });
      return;
    }

    _cursorBlinkTimer?.cancel();
    _cursorBlinkTimer = null;
    if (!_cursorVisible) {
      setState(() {
        _cursorVisible = true;
      });
    }
  }

  void _handleScrollDelta(double deltaY) {
    if (_terminalMouseEnabled) {
      _sendMouseWheel(deltaY);
      return;
    }
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

  bool get _terminalMouseEnabled =>
      widget.controller.frame.modes.mouseMode != 'off';

  RenderTerminalViewport? get _renderViewport {
    final renderObject = _surfaceKey.currentContext?.findRenderObject();
    return renderObject is RenderTerminalViewport ? renderObject : null;
  }

  TerminalCellPosition? _cellForGlobalPosition(Offset globalPosition) {
    final renderObject = _renderViewport;
    if (renderObject == null) {
      return null;
    }
    final localPosition = renderObject.globalToLocal(globalPosition);
    return renderObject.debugCellForOffset(localPosition);
  }

  int _mouseModifiers() {
    var modifiers = 0;
    if (HardwareKeyboard.instance.isShiftPressed) {
      modifiers += 1;
    }
    if (HardwareKeyboard.instance.isAltPressed) {
      modifiers += 2;
    }
    if (HardwareKeyboard.instance.isControlPressed) {
      modifiers += 4;
    }
    return modifiers;
  }

  int _mouseButtonFor(int buttons) {
    if ((buttons & kMiddleMouseButton) != 0) {
      return 1;
    }
    if ((buttons & kSecondaryMouseButton) != 0) {
      return 2;
    }
    return 0;
  }

  void _sendMouseEvent({
    required Offset globalPosition,
    required int button,
    required bool pressed,
  }) {
    if (!_terminalMouseEnabled) {
      return;
    }
    final cell = _cellForGlobalPosition(globalPosition);
    if (cell == null) {
      return;
    }
    widget.inputController.sendMouseReport(
      modes: widget.controller.frame.modes,
      row: cell.row,
      col: cell.col,
      button: button,
      pressed: pressed,
      modifiers: _mouseModifiers(),
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!_terminalMouseEnabled) {
      return;
    }
    _activeMouseButton = _mouseButtonFor(event.buttons);
    _sendMouseEvent(
      globalPosition: event.position,
      button: _activeMouseButton!,
      pressed: true,
    );
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_terminalMouseEnabled || event.buttons == 0) {
      return;
    }
    final mode = widget.controller.frame.modes.mouseMode;
    if (mode != 'button_event' && mode != 'any_event') {
      return;
    }
    _activeMouseButton ??= _mouseButtonFor(event.buttons);
    _sendMouseEvent(
      globalPosition: event.position,
      button: _activeMouseButton! | 32,
      pressed: true,
    );
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (!_terminalMouseEnabled) {
      return;
    }
    _sendMouseEvent(
      globalPosition: event.position,
      button: _activeMouseButton ?? 0,
      pressed: false,
    );
    _activeMouseButton = null;
  }

  void _sendMouseWheel(double deltaY, {Offset? globalPosition}) {
    if (deltaY == 0) {
      return;
    }
    final renderObject = _renderViewport;
    if (renderObject == null) {
      return;
    }
    final localFallback = Offset(
      renderObject.size.width / 2,
      renderObject.size.height / 2,
    );
    final cell = globalPosition == null
        ? renderObject.debugCellForOffset(localFallback)
        : _cellForGlobalPosition(globalPosition);
    if (cell == null) {
      return;
    }
    widget.inputController.sendMouseReport(
      modes: widget.controller.frame.modes,
      row: cell.row,
      col: cell.col,
      button: deltaY < 0 ? 64 : 65,
      pressed: true,
      modifiers: _mouseModifiers(),
    );
  }

  void _handleTapUp(TapUpDetails details) {
    final onOpenLink = widget.onOpenLink;
    if (onOpenLink == null) {
      return;
    }
    final link = _linkAt(details.globalPosition);
    if (link == null) {
      return;
    }
    onOpenLink(link);
  }

  String? _linkAt(Offset globalPosition) {
    final cell = _cellForGlobalPosition(globalPosition);
    if (cell == null) {
      return null;
    }
    final frame = widget.controller.frame;
    for (final hyperlink in frame.hyperlinks) {
      if (hyperlink.row == cell.row &&
          cell.col >= hyperlink.startCol &&
          cell.col < hyperlink.endCol) {
        return hyperlink.uri;
      }
    }

    TerminalRow? row;
    for (final candidate in frame.rows) {
      if (candidate.index == cell.row) {
        row = candidate;
        break;
      }
    }
    final text = row?.text;
    if (text == null || text.isEmpty) {
      return null;
    }
    final textCells = TerminalTextCells.fromText(text);
    final codeUnit = textCells.codeUnitForColumn(cell.col);
    for (final match in _visibleUrlPattern.allMatches(text)) {
      if (codeUnit >= match.start && codeUnit < match.end) {
        return match.group(0);
      }
    }
    return null;
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
    return terminalFallbackCellSize.height;
  }

  TerminalViewportColors _resolvedColors(BuildContext context) {
    final base =
        widget.colors ??
        TerminalViewportColors.fromBrightness(Theme.of(context).brightness);
    if (widget.backgroundColor == null && widget.foregroundColor == null) {
      return base;
    }
    return base.copyWith(
      canvasBackground: widget.backgroundColor,
      foreground: widget.foregroundColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasuredCellSizeReport();
    final colors = _resolvedColors(context);
    return Focus(
      autofocus: true,
      focusNode: _focusNode,
      onKeyEvent: (_, event) => widget.inputController.handle(event),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _focusNode.requestFocus(),
        onTapUp: _handleTapUp,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerUp,
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              if (_terminalMouseEnabled) {
                _sendMouseWheel(
                  event.scrollDelta.dy,
                  globalPosition: event.position,
                );
              } else {
                _handleScrollDelta(event.scrollDelta.dy);
              }
            }
          },
          onPointerPanZoomStart: (_) => _resetPendingScroll(),
          onPointerPanZoomUpdate: (event) {
            if (_terminalMouseEnabled) {
              _sendMouseWheel(
                event.panDelta.dy,
                globalPosition: event.position,
              );
            } else {
              _handleScrollDelta(event.panDelta.dy);
            }
          },
          onPointerPanZoomEnd: (_) => _resetPendingScroll(),
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              final frame = widget.controller.frame;
              return LayoutBuilder(
                builder: (context, constraints) {
                  final contentPadding = widget.contentPadding;
                  final trackHeight = math.max(0.0, constraints.maxHeight - 16);
                  return DecoratedBox(
                    decoration: BoxDecoration(color: colors.canvasBackground),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Padding(
                            padding: contentPadding,
                            child: _TerminalViewportSurface(
                              key: _surfaceKey,
                              controller: widget.controller,
                              selectionController: widget.selectionController,
                              cursorVisible: _cursorVisible,
                              colors: colors,
                              terminalMouseEnabled: _terminalMouseEnabled,
                            ),
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
                              colors: colors,
                              onScrollToOffset: widget.onScrollToOffset,
                            ),
                          ),
                      ],
                    ),
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
    required this.colors,
    required this.terminalMouseEnabled,
  });

  final TerminalViewportController controller;
  final SelectionController selectionController;
  final bool cursorVisible;
  final TerminalViewportColors colors;
  final bool terminalMouseEnabled;

  @override
  RenderTerminalViewport createRenderObject(BuildContext context) {
    return RenderTerminalViewport(
      controller: controller,
      selectionController: selectionController,
      cursorVisible: cursorVisible,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      colors: colors,
      terminalMouseEnabled: terminalMouseEnabled,
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
      ..colors = colors
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..terminalMouseEnabled = terminalMouseEnabled;
  }
}

class _TerminalScrollbar extends StatefulWidget {
  const _TerminalScrollbar({
    required this.viewportRows,
    required this.scrollbackOffset,
    required this.scrollbackMaxOffset,
    required this.trackHeight,
    required this.colors,
    required this.onScrollToOffset,
  });

  final int viewportRows;
  final int scrollbackOffset;
  final int scrollbackMaxOffset;
  final double trackHeight;
  final TerminalViewportColors colors;
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
                color: widget.colors.scrollbarTrack,
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
                  color: widget.colors.scrollbarThumb,
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
