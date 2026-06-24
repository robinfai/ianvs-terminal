import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../config/terminal_config.dart';
import 'render_terminal_viewport.dart';
import 'selection_controller.dart';
import 'terminal_graphics_cache.dart';
import 'terminal_input_controller.dart';
import 'terminal_models.dart';
import 'terminal_viewport_colors.dart';

const Key terminalScrollbarTrackKey = Key('terminal-scrollbar-track');
const Key terminalScrollbarThumbKey = Key('terminal-scrollbar-thumb');
const double _terminalTimestampOverlayWidth = 66;
const Size terminalFallbackCellSize = Size(9, 18);
final RegExp _visibleUrlPattern = RegExp(r'(?:https?|file)://[^\s<>()"]+');
final RegExp _smartEmailPattern = RegExp(
  r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}',
);
final RegExp _smartPathPattern = RegExp(
  r'''(?:~|\.{1,2}|/)[^\s<>()"']+|[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.:-]+)+''',
);
const String _smartSelectionLeadingTrim = "([<{\"'";
const String _smartSelectionTrailingTrim = ".,;:!?)]}>\"'";
const String _xtermWordSeparators = " ()[]{}',\"`";

class TerminalViewportController extends ChangeNotifier {
  TerminalViewportController({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  TerminalViewportState _state = TerminalViewportState.empty;
  final DateTime Function() _now;
  Size? _measuredCellSize;
  int _frameVersion = 0;

  TerminalViewportState get state => _state;
  TerminalFrameDiff get frame => _state.frame;
  int get frameVersion => _frameVersion;
  Size? get measuredCellSize => _measuredCellSize;

  void updateFrame(TerminalFrameDiff value) {
    _state = _state.applyFrame(value, capturedAt: _now());
    _frameVersion += 1;
    notifyListeners();
  }

  void applySnapshot(TerminalFrameDiff value) {
    _state = _state.applySnapshot(value, capturedAt: _now());
    _frameVersion += 1;
    notifyListeners();
  }

  void applyDelta(TerminalFrameDiff value) {
    _state = _state.applyDelta(value, capturedAt: _now());
    _frameVersion += 1;
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
    this.font = const TerminalFontConfig(),
    this.cursor = const TerminalCursorConfig(),
    this.copyOnSelect = false,
    this.showLineTimestamps = false,
    this.optionDragMode = TerminalOptionDragMode.blockSelection,
    this.focusNode,
    this.onHostKeyEvent,
    this.onOpenLink,
    this.searchMatches = const [],
    this.activeSearchMatchIndex = -1,
    this.searchHighlightStyle,
    this.graphicsCache,
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
  final TerminalFontConfig font;
  final TerminalCursorConfig cursor;
  final bool copyOnSelect;
  final bool showLineTimestamps;
  final TerminalOptionDragMode optionDragMode;
  final FocusNode? focusNode;
  final KeyEventResult Function(KeyEvent event)? onHostKeyEvent;
  final ValueChanged<String>? onOpenLink;
  final List<TerminalSearchMatch> searchMatches;
  final int activeSearchMatchIndex;
  final TerminalSearchHighlightStyle? searchHighlightStyle;
  final TerminalGraphicsCache? graphicsCache;

  @override
  State<TerminalViewport> createState() => _TerminalViewportState();
}

enum _LocalSelectionMode { cell, word }

class _TerminalViewportState extends State<TerminalViewport>
    with TextInputClient {
  static const Duration _selectionAutoScrollInterval = Duration(
    milliseconds: 50,
  );
  static const Duration _scrollMomentumInterval = Duration(milliseconds: 16);
  static const double _scrollMomentumDecayPerTick = 0.95;
  static const double _scrollMomentumStartThresholdLinesPerSecond = 24.0;
  static const double _scrollMomentumStopThresholdLinesPerSecond = 2.0;
  Timer? _cursorBlinkTimer;
  Timer? _selectionAutoScrollTimer;
  Timer? _scrollMomentumTimer;
  Timer? _pendingLinkOpenTimer;
  bool _cursorVisible = true;
  FocusNode? _ownedFocusNode;
  FocusNode? _listenedFocusNode;
  final GlobalKey _surfaceKey = GlobalKey();
  double _pendingScrollLines = 0.0;
  double _scrollMomentumLinesPerSecond = 0.0;
  Duration? _lastPanZoomUpdateTimeStamp;
  Size? _lastReportedCellSize;
  int? _activeMouseButton;
  bool? _lastReportedFocusTrackingFocus;
  bool _isLocalSelectionActive = false;
  Offset? _selectionPointerGlobalPosition;
  Offset? _selectionPointerDownGlobalPosition;
  Offset? _lastPrimaryTapUpPosition;
  Duration? _lastPrimaryTapUpTimestamp;
  int _lastPrimaryTapCount = 0;
  int _currentPrimaryTapCount = 0;
  bool _selectionMovedSincePointerDown = false;
  _LocalSelectionMode _localSelectionMode = _LocalSelectionMode.cell;
  _TerminalWordRange? _wordSelectionAnchor;
  TextInputConnection? _textInputConnection;
  TextEditingValue _textInputValue = TextEditingValue.empty;
  bool _hadImeComposition = false;
  bool _awaitingSystemTextCommit = false;
  String _deferredImeRawText = '';
  bool _textInputGeometrySyncScheduled = false;
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
    _closeTextInputConnection(notify: false);
    _cursorBlinkTimer?.cancel();
    _selectionAutoScrollTimer?.cancel();
    _scrollMomentumTimer?.cancel();
    _pendingLinkOpenTimer?.cancel();
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
    _scheduleTextInputGeometrySync();
    _syncFocusTrackingReport();
    _syncCursorBlinkTimer();
    _scheduleMeasuredCellSizeReport();
    _syncGraphicsCache();
    if (_isLocalSelectionActive &&
        !_terminalMouseEnabled &&
        _selectionPointerGlobalPosition != null) {
      _updateSelectionFromPointer(_selectionPointerGlobalPosition!);
      _syncSelectionAutoScroll();
    } else if (_terminalMouseEnabled) {
      _isLocalSelectionActive = false;
      _selectionPointerGlobalPosition = null;
      _selectionPointerDownGlobalPosition = null;
      _wordSelectionAnchor = null;
      _localSelectionMode = _LocalSelectionMode.cell;
      _stopSelectionAutoScroll();
    }
  }

  void _syncGraphicsCache() {
    final graphicsCache = widget.graphicsCache;
    if (graphicsCache == null) {
      return;
    }
    graphicsCache.evictExcept(
      widget.controller.frame.graphics
          .map((graphic) => graphic.assetKey)
          .toSet(),
    );
  }

  void _handleFocusChange() {
    if (!mounted) {
      return;
    }
    _syncTextInputConnection();
    _syncFocusTrackingReport();
    _syncCursorBlinkTimer();
  }

  void _syncTextInputConnection() {
    if (_focusNode.hasFocus) {
      _openTextInputConnection();
      _scheduleTextInputGeometrySync();
      return;
    }
    _closeTextInputConnection();
  }

  void _openTextInputConnection() {
    final existingConnection = _textInputConnection;
    if (existingConnection != null && existingConnection.attached) {
      existingConnection.show();
      existingConnection.setEditingState(_textInputValue);
      return;
    }
    final connection = TextInput.attach(
      this,
      const TextInputConfiguration(
        inputType: TextInputType.multiline,
        inputAction: TextInputAction.newline,
        autocorrect: false,
        enableSuggestions: false,
        enableInteractiveSelection: false,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
      ),
    );
    _textInputConnection = connection;
    connection.setEditingState(_textInputValue);
    connection.show();
  }

  void _closeTextInputConnection({bool notify = true}) {
    final connection = _textInputConnection;
    if (connection != null && connection.attached) {
      connection.close();
    }
    _textInputConnection = null;
    _updateTextInputState(_resetTextInputTracking, notify: notify);
  }

  void _resetTextInputTracking() {
    _textInputValue = TextEditingValue.empty;
    _hadImeComposition = false;
    _awaitingSystemTextCommit = false;
    _deferredImeRawText = '';
  }

  void _clearTextInputState() {
    _updateTextInputState(_resetTextInputTracking);
    final connection = _textInputConnection;
    if (connection != null && connection.attached) {
      connection.setEditingState(_textInputValue);
    }
  }

  void _updateTextInputState(VoidCallback mutate, {bool notify = true}) {
    if (!notify || !mounted) {
      mutate();
      return;
    }
    setState(mutate);
  }

  void _scheduleTextInputGeometrySync() {
    if (_textInputGeometrySyncScheduled) {
      return;
    }
    _textInputGeometrySyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _textInputGeometrySyncScheduled = false;
      _syncTextInputGeometry();
    });
  }

  void _syncTextInputGeometry() {
    if (!mounted) {
      return;
    }
    final connection = _textInputConnection;
    if (connection == null || !connection.attached) {
      return;
    }
    final renderObject = _surfaceKey.currentContext?.findRenderObject();
    if (renderObject is! RenderTerminalViewport) {
      return;
    }
    connection.setEditableSizeAndTransform(
      renderObject.size,
      renderObject.getTransformTo(null),
    );
    final caretCellRect = renderObject.debugCaretCellRect;
    if (caretCellRect == null) {
      return;
    }
    connection.setCaretRect(renderObject.debugCursorRect ?? caretCellRect);
    connection.setComposingRect(caretCellRect);
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

  bool get _canDisplayFrameCursor {
    final frame = widget.controller.frame;
    final cursor = frame.cursor;
    if (!cursor.visible ||
        frame.scrollbackOffset > 0 ||
        frame.viewportRows <= 0 ||
        frame.viewportCols <= 0) {
      return false;
    }
    return cursor.row < frame.viewportRows && cursor.col < frame.viewportCols;
  }

  bool get _shouldBlinkCursor =>
      widget.cursor.blink && _focusNode.hasFocus && _canDisplayFrameCursor;

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
    final rawDeltaLines = _rawScrollLinesForDelta(deltaY);
    if (rawDeltaLines == 0) {
      return;
    }
    if (_terminalAlternateScrollEnabled) {
      _sendAlternateScroll(rawDeltaLines);
      return;
    }
    _applyRawScrollLines(rawDeltaLines);
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (
      PointerSignalEvent resolvedEvent,
    ) {
      final scrollEvent = resolvedEvent as PointerScrollEvent;
      if (_terminalMouseEnabled) {
        _sendMouseWheel(
          scrollEvent.scrollDelta.dy,
          globalPosition: scrollEvent.position,
        );
      } else {
        _handleScrollDelta(scrollEvent.scrollDelta.dy);
      }
    });
  }

  double _rawScrollLinesForDelta(double deltaY) {
    final lineHeight = _lineHeight;
    if (lineHeight <= 0) {
      return 0;
    }
    return -deltaY / lineHeight;
  }

  bool _applyRawScrollLines(double rawDeltaLines) {
    if (rawDeltaLines == 0) {
      return false;
    }
    _pendingScrollLines += rawDeltaLines;
    final deltaLines = _pendingScrollLines.round();
    if (deltaLines == 0) {
      return true;
    }
    _pendingScrollLines -= deltaLines;
    widget.onScrollLines(deltaLines);
    return true;
  }

  void _handlePanZoomStart(PointerPanZoomStartEvent event) {
    _stopScrollMomentum();
    _resetPendingScroll();
    _lastPanZoomUpdateTimeStamp = event.timeStamp;
  }

  void _handlePanZoomUpdate(PointerPanZoomUpdateEvent event) {
    _cancelScrollMomentumTimer();
    if (_terminalMouseEnabled) {
      _sendMouseWheel(event.panDelta.dy, globalPosition: event.position);
      return;
    }
    final rawDeltaLines = _rawScrollLinesForDelta(event.panDelta.dy);
    if (rawDeltaLines == 0) {
      return;
    }
    if (_terminalAlternateScrollEnabled) {
      _sendAlternateScroll(rawDeltaLines);
      return;
    }
    final currentTimeStamp = event.timeStamp;
    final previousTimeStamp = _lastPanZoomUpdateTimeStamp;
    final deltaTime = previousTimeStamp == null
        ? Duration.zero
        : currentTimeStamp - previousTimeStamp;
    final effectiveDeltaTime = deltaTime > Duration.zero
        ? deltaTime
        : _scrollMomentumInterval;
    _scrollMomentumLinesPerSecond =
        rawDeltaLines /
        (effectiveDeltaTime.inMicroseconds / Duration.microsecondsPerSecond);
    _lastPanZoomUpdateTimeStamp = currentTimeStamp;
    _applyRawScrollLines(rawDeltaLines);
  }

  void _handlePanZoomEnd(PointerPanZoomEndEvent event) {
    _lastPanZoomUpdateTimeStamp = event.timeStamp;
    if (_terminalMouseEnabled || _terminalAlternateScrollEnabled) {
      _resetPendingScroll();
      return;
    }
    _startScrollMomentumIfNeeded();
  }

  void _startScrollMomentumIfNeeded() {
    if (_terminalMouseEnabled ||
        _scrollMomentumLinesPerSecond.abs() <
            _scrollMomentumStartThresholdLinesPerSecond) {
      _stopScrollMomentum(resetPendingScroll: false);
      return;
    }
    _scrollMomentumTimer ??= Timer.periodic(
      _scrollMomentumInterval,
      (_) => _handleScrollMomentumTick(),
    );
  }

  void _handleScrollMomentumTick() {
    if (!mounted || _terminalMouseEnabled) {
      _stopScrollMomentum();
      return;
    }
    final velocity = _scrollMomentumLinesPerSecond;
    if (velocity.abs() < _scrollMomentumStopThresholdLinesPerSecond) {
      _stopScrollMomentum(resetPendingScroll: false);
      return;
    }
    final frameBeforeScroll = widget.controller.frame;
    final rawDeltaLines =
        velocity *
        (_scrollMomentumInterval.inMicroseconds /
            Duration.microsecondsPerSecond);
    final didScroll = _applyRawScrollLines(rawDeltaLines);
    if (!didScroll) {
      _stopScrollMomentum();
      return;
    }
    final frameAfterScroll = widget.controller.frame;
    final hitUpperEdge =
        velocity > 0 &&
        frameBeforeScroll.scrollbackOffset >=
            frameBeforeScroll.scrollbackMaxOffset &&
        frameAfterScroll.scrollbackOffset >=
            frameAfterScroll.scrollbackMaxOffset;
    final hitLowerEdge =
        velocity < 0 &&
        frameBeforeScroll.scrollbackOffset <= 0 &&
        frameAfterScroll.scrollbackOffset <= 0;
    if (hitUpperEdge || hitLowerEdge) {
      _stopScrollMomentum();
      return;
    }
    _scrollMomentumLinesPerSecond *= _scrollMomentumDecayPerTick;
  }

  void _stopScrollMomentum({bool resetPendingScroll = true}) {
    _cancelScrollMomentumTimer();
    _scrollMomentumLinesPerSecond = 0.0;
    _lastPanZoomUpdateTimeStamp = null;
    if (resetPendingScroll) {
      _pendingScrollLines = 0.0;
    }
  }

  void _cancelScrollMomentumTimer() {
    _scrollMomentumTimer?.cancel();
    _scrollMomentumTimer = null;
  }

  bool get _terminalMouseEnabled =>
      widget.controller.frame.modes.mouseMode != 'off';

  bool get _terminalAlternateScrollEnabled {
    final modes = widget.controller.frame.modes;
    return modes.alternateScreen &&
        modes.alternateScroll &&
        modes.mouseMode == 'off';
  }

  bool get _usesOptionBlockSelection =>
      widget.optionDragMode == TerminalOptionDragMode.blockSelection &&
      HardwareKeyboard.instance.isAltPressed;

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

  TerminalCellPosition? _selectionCellForGlobalPosition(Offset globalPosition) {
    final renderObject = _renderViewport;
    if (renderObject == null) {
      return null;
    }
    final localPosition = renderObject.globalToLocal(globalPosition);
    final clampedPosition = Offset(
      localPosition.dx
          .clamp(0.0, math.max(0.0, renderObject.size.width - 0.001))
          .toDouble(),
      localPosition.dy
          .clamp(0.0, math.max(0.0, renderObject.size.height - 0.001))
          .toDouble(),
    );
    return renderObject.debugCellForOffset(clampedPosition);
  }

  bool _surfaceContainsGlobalPosition(Offset globalPosition) {
    final renderObject = _renderViewport;
    if (renderObject == null) {
      return false;
    }
    final localPosition = renderObject.globalToLocal(globalPosition);
    return localPosition.dx >= 0 &&
        localPosition.dy >= 0 &&
        localPosition.dx < renderObject.size.width &&
        localPosition.dy < renderObject.size.height;
  }

  bool _scrollbarContainsGlobalPosition(Offset globalPosition) {
    final frame = widget.controller.frame;
    if (frame.scrollbackMaxOffset <= 0) {
      return false;
    }
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || renderObject.size.height <= 16) {
      return false;
    }
    final localPosition = renderObject.globalToLocal(globalPosition);
    final trackRect = Rect.fromLTWH(
      renderObject.size.width - 18,
      8,
      12,
      renderObject.size.height - 16,
    );
    return trackRect.contains(localPosition);
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

  bool _isPrimarySelectionButton(int buttons) {
    return (buttons & kPrimaryButton) != 0;
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
    _stopScrollMomentum();
    if (!_terminalMouseEnabled) {
      if (!_isPrimarySelectionButton(event.buttons) ||
          _scrollbarContainsGlobalPosition(event.position) ||
          !_surfaceContainsGlobalPosition(event.position)) {
        return;
      }
      _cancelPendingLinkOpen();
      _focusNode.requestFocus();
      _selectionPointerGlobalPosition = event.position;
      _selectionPointerDownGlobalPosition = event.position;
      _selectionMovedSincePointerDown = false;
      final cell = _selectionCellForGlobalPosition(event.position);
      if (cell == null) {
        _isLocalSelectionActive = false;
        _selectionPointerDownGlobalPosition = null;
        _wordSelectionAnchor = null;
        _stopSelectionAutoScroll();
        return;
      }
      _currentPrimaryTapCount = _nextPrimaryTapCount(
        event.position,
        event.timeStamp,
      );
      _isLocalSelectionActive = true;
      if (!_usesOptionBlockSelection && _currentPrimaryTapCount == 2) {
        final wordRange = _wordRangeAtCell(cell);
        if (wordRange != null) {
          _localSelectionMode = _LocalSelectionMode.word;
          _wordSelectionAnchor = wordRange;
          widget.selectionController.setSelection(wordRange.selection);
          _syncSelectionAutoScroll();
          return;
        }
      }
      _localSelectionMode = _LocalSelectionMode.cell;
      _wordSelectionAnchor = null;
      widget.selectionController.begin(
        cell,
        block: _usesOptionBlockSelection,
        viewportStartRow: widget.controller.frame.viewportStartRow,
      );
      _syncSelectionAutoScroll();
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
    if (!_terminalMouseEnabled) {
      if (!_isLocalSelectionActive ||
          !_isPrimarySelectionButton(event.buttons)) {
        return;
      }
      _selectionPointerGlobalPosition = event.position;
      _selectionMovedSincePointerDown =
          _selectionMovedSincePointerDown ||
          _didSelectionMoveBeyondTapSlop(event.position);
      _updateSelectionFromPointer(event.position);
      _syncSelectionAutoScroll();
      return;
    }
    final mode = widget.controller.frame.modes.mouseMode;
    if (event.buttons == 0) {
      if (mode == 'any_event') {
        _sendAnyMouseMotion(event.position);
      }
      return;
    }
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

  void _handlePointerHover(PointerHoverEvent event) {
    if (!_terminalMouseEnabled ||
        widget.controller.frame.modes.mouseMode != 'any_event') {
      return;
    }
    _sendAnyMouseMotion(event.position);
  }

  void _sendAnyMouseMotion(Offset globalPosition) {
    _sendMouseEvent(globalPosition: globalPosition, button: 35, pressed: true);
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (!_terminalMouseEnabled) {
      if (_isLocalSelectionActive) {
        _selectionPointerGlobalPosition = event.position;
        _selectionMovedSincePointerDown =
            _selectionMovedSincePointerDown ||
            _didSelectionMoveBeyondTapSlop(event.position);
        _updateSelectionFromPointer(event.position);
        if (widget.copyOnSelect) {
          unawaited(widget.inputController.copySelection());
        }
      }
      final shouldOpenLink = _shouldOpenLinkForPointerUp(event);
      _recordPrimaryTapUp(event);
      if (shouldOpenLink) {
        _schedulePendingLinkOpen(event.position);
      }
      _isLocalSelectionActive = false;
      _selectionPointerGlobalPosition = null;
      _selectionPointerDownGlobalPosition = null;
      _wordSelectionAnchor = null;
      _localSelectionMode = _LocalSelectionMode.cell;
      _stopSelectionAutoScroll();
      return;
    }
    _sendMouseEvent(
      globalPosition: event.position,
      button: _activeMouseButton ?? 0,
      pressed: false,
    );
    _activeMouseButton = null;
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _stopScrollMomentum();
    if (_terminalMouseEnabled) {
      _activeMouseButton = null;
      return;
    }
    _currentPrimaryTapCount = 0;
    _selectionMovedSincePointerDown = false;
    _isLocalSelectionActive = false;
    _selectionPointerGlobalPosition = null;
    _selectionPointerDownGlobalPosition = null;
    _wordSelectionAnchor = null;
    _localSelectionMode = _LocalSelectionMode.cell;
    _cancelPendingLinkOpen();
    _stopSelectionAutoScroll();
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

  void _sendAlternateScroll(double rawDeltaLines) {
    if (rawDeltaLines == 0) {
      return;
    }
    _pendingScrollLines += rawDeltaLines;
    final stepCount = _pendingScrollLines.round();
    if (stepCount == 0) {
      return;
    }
    _pendingScrollLines -= stepCount;
    final modes = widget.controller.frame.modes;
    final upSequence = modes.applicationCursor ? '\x1BOA' : '\x1B[A';
    final downSequence = modes.applicationCursor ? '\x1BOB' : '\x1B[B';
    final sequence = stepCount > 0 ? upSequence : downSequence;
    widget.inputController.sendText(
      List<String>.filled(stepCount.abs(), sequence).join(),
    );
  }

  void _openLinkAt(Offset globalPosition) {
    final onOpenLink = widget.onOpenLink;
    if (onOpenLink == null) {
      return;
    }
    final link = _linkAt(globalPosition);
    if (link == null) {
      return;
    }
    onOpenLink(link);
  }

  int _nextPrimaryTapCount(Offset globalPosition, Duration timeStamp) {
    final lastPosition = _lastPrimaryTapUpPosition;
    final lastTimeStamp = _lastPrimaryTapUpTimestamp;
    if (lastPosition == null || lastTimeStamp == null) {
      return 1;
    }
    final withinTimeout = timeStamp - lastTimeStamp <= kDoubleTapTimeout;
    final withinSlop =
        (globalPosition - lastPosition).distance <= kDoubleTapSlop;
    if (!withinTimeout || !withinSlop) {
      return 1;
    }
    return _lastPrimaryTapCount == 1 ? 2 : 1;
  }

  bool _didSelectionMoveBeyondTapSlop(Offset globalPosition) {
    final start = _selectionPointerDownGlobalPosition;
    if (start == null) {
      return false;
    }
    return (globalPosition - start).distance > kTouchSlop;
  }

  void _recordPrimaryTapUp(PointerUpEvent event) {
    if (_selectionMovedSincePointerDown || _currentPrimaryTapCount != 1) {
      _lastPrimaryTapCount = 0;
    } else {
      _lastPrimaryTapCount = _currentPrimaryTapCount;
      _lastPrimaryTapUpPosition = event.position;
      _lastPrimaryTapUpTimestamp = event.timeStamp;
    }
    _currentPrimaryTapCount = 0;
    _selectionMovedSincePointerDown = false;
  }

  bool _shouldOpenLinkForPointerUp(PointerUpEvent event) {
    return !_selectionMovedSincePointerDown &&
        _currentPrimaryTapCount == 1 &&
        _localSelectionMode == _LocalSelectionMode.cell &&
        _surfaceContainsGlobalPosition(event.position) &&
        !_scrollbarContainsGlobalPosition(event.position);
  }

  void _schedulePendingLinkOpen(Offset globalPosition) {
    if (widget.onOpenLink == null) {
      return;
    }
    _cancelPendingLinkOpen();
    _pendingLinkOpenTimer = Timer(kDoubleTapTimeout, () {
      _pendingLinkOpenTimer = null;
      if (!mounted) {
        return;
      }
      _openLinkAt(globalPosition);
    });
  }

  void _cancelPendingLinkOpen() {
    _pendingLinkOpenTimer?.cancel();
    _pendingLinkOpenTimer = null;
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

  _TerminalWordRange? _wordRangeAtCell(TerminalCellPosition cell) {
    return _wordRangeAtRelativeCell(
      widget.controller.frame,
      cell.row,
      cell.col,
    );
  }

  void _updateSelectionFromPointer(
    Offset globalPosition, {
    int? viewportStartRow,
  }) {
    if (_localSelectionMode == _LocalSelectionMode.word) {
      _updateWordSelectionFromPointer(globalPosition);
      return;
    }
    _updateCellSelectionFromPointer(
      globalPosition,
      viewportStartRow: viewportStartRow,
    );
  }

  void _updateCellSelectionFromPointer(
    Offset globalPosition, {
    int? viewportStartRow,
  }) {
    final cell = _selectionCellForGlobalPosition(globalPosition);
    if (cell == null) {
      return;
    }
    widget.selectionController.update(
      cell,
      viewportStartRow:
          viewportStartRow ?? widget.controller.frame.viewportStartRow,
    );
  }

  void _updateWordSelectionFromPointer(Offset globalPosition) {
    final cell = _selectionCellForGlobalPosition(globalPosition);
    final anchor = _wordSelectionAnchor;
    if (cell == null || anchor == null) {
      return;
    }
    final targetRange = _wordRangeAtCell(cell);
    if (targetRange == null) {
      return;
    }
    widget.selectionController.setSelection(
      _selectionForWordDrag(anchor, targetRange),
    );
  }

  int _autoScrollLinesForOvershoot(double overshoot) {
    final lineHeight = _lineHeight;
    if (lineHeight <= 0) {
      return 1;
    }
    return (1 + (overshoot / lineHeight).floor()).clamp(1, 6).toInt();
  }

  int _selectionAutoScrollDelta() {
    final pointer = _selectionPointerGlobalPosition;
    final renderObject = _renderViewport;
    if (pointer == null || renderObject == null) {
      return 0;
    }
    final localPosition = renderObject.globalToLocal(pointer);
    if (localPosition.dy < 0) {
      return _autoScrollLinesForOvershoot(-localPosition.dy);
    }
    if (localPosition.dy > renderObject.size.height) {
      return -_autoScrollLinesForOvershoot(
        localPosition.dy - renderObject.size.height,
      );
    }
    return 0;
  }

  bool _canScrollSelection(int deltaLines) {
    final frame = widget.controller.frame;
    if (deltaLines > 0) {
      return frame.scrollbackOffset < frame.scrollbackMaxOffset;
    }
    if (deltaLines < 0) {
      return frame.scrollbackOffset > 0;
    }
    return false;
  }

  int _predictedViewportStartRow(int deltaLines) {
    final frame = widget.controller.frame;
    final nextOffset = (frame.scrollbackOffset + deltaLines)
        .clamp(0, frame.scrollbackMaxOffset)
        .toInt();
    return frame.scrollbackMaxOffset - nextOffset;
  }

  void _syncSelectionAutoScroll() {
    final deltaLines = _selectionAutoScrollDelta();
    if (!_isLocalSelectionActive ||
        _terminalMouseEnabled ||
        deltaLines == 0 ||
        !_canScrollSelection(deltaLines)) {
      _stopSelectionAutoScroll();
      return;
    }
    _selectionAutoScrollTimer ??= Timer.periodic(
      _selectionAutoScrollInterval,
      (_) => _handleSelectionAutoScrollTick(),
    );
  }

  void _handleSelectionAutoScrollTick() {
    final deltaLines = _selectionAutoScrollDelta();
    if (!_isLocalSelectionActive ||
        _terminalMouseEnabled ||
        deltaLines == 0 ||
        !_canScrollSelection(deltaLines)) {
      _stopSelectionAutoScroll();
      return;
    }
    widget.onScrollLines(deltaLines);
    final pointer = _selectionPointerGlobalPosition;
    if (pointer != null) {
      _updateSelectionFromPointer(
        pointer,
        viewportStartRow: _predictedViewportStartRow(deltaLines),
      );
    }
  }

  void _stopSelectionAutoScroll() {
    _selectionAutoScrollTimer?.cancel();
    _selectionAutoScrollTimer = null;
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

  KeyEventResult _handleTerminalKeyEvent(KeyEvent event) {
    if (!_isTerminalKeyPressEvent(event)) {
      return KeyEventResult.ignored;
    }
    if (_shouldDeferKeyPressToSystemTextInput(event)) {
      _recordDeferredImeKey(event);
      final character = event.character;
      if (_isDeferredTextCommitCharacter(character)) {
        _awaitingSystemTextCommit = true;
      }
      return KeyEventResult.ignored;
    }
    final hostResult = widget.onHostKeyEvent?.call(event);
    if (hostResult == KeyEventResult.handled) {
      return KeyEventResult.handled;
    }
    return widget.inputController.handle(event);
  }

  bool _shouldDeferKeyPressToSystemTextInput(KeyEvent event) {
    final connection = _textInputConnection;
    if (defaultTargetPlatform != TargetPlatform.macOS ||
        connection == null ||
        !connection.attached) {
      return false;
    }

    final isMetaPressed = HardwareKeyboard.instance.isMetaPressed;
    final isControlPressed = HardwareKeyboard.instance.isControlPressed;
    if (isMetaPressed || isControlPressed) {
      return false;
    }

    if (_hasActiveImeComposition(_textInputValue)) {
      return true;
    }

    if (HardwareKeyboard.instance.isAltPressed) {
      return false;
    }

    final character = event.character;
    return _isDeferredTextCommitCharacter(character);
  }

  void _recordDeferredImeKey(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_deferredImeRawText.isNotEmpty) {
        final runes = _deferredImeRawText.runes.toList(growable: false);
        _deferredImeRawText = String.fromCharCodes(
          runes.take(runes.length - 1),
        );
      }
      return;
    }

    if (HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return;
    }

    final character = event.character;
    if (character == null || !_isPrintableAscii(character)) {
      return;
    }
    _deferredImeRawText += character;
  }

  bool _isDeferredTextCommitCharacter(String? character) {
    if (character == null || character.isEmpty) {
      return false;
    }
    return character.runes.any(
      (codePoint) => codePoint >= 0x20 && codePoint != 0x7f,
    );
  }

  String? get _composingText {
    if (!_hasActiveImeComposition(_textInputValue)) {
      return null;
    }
    final composingRange = _textInputValue.composing;
    final text = composingRange.textInside(_textInputValue.text);
    return text.isEmpty ? null : text;
  }

  Widget? _buildComposingOverlay(
    TerminalViewportColors colors, {
    required double viewportWidth,
  }) {
    final text = _composingText;
    if (text == null) {
      return null;
    }
    final renderObject = _surfaceKey.currentContext?.findRenderObject();
    if (renderObject is! RenderTerminalViewport) {
      return null;
    }
    final caretCellRect = renderObject.debugCaretCellRect;
    if (caretCellRect == null) {
      return null;
    }
    final composingForeground = _composingForegroundColor(colors);
    final viewportRenderObject = context.findRenderObject();
    final viewportBoxWidth = viewportRenderObject is RenderBox
        ? viewportRenderObject.size.width
        : double.infinity;
    final visibleWidth =
        math.min(
          viewportWidth.isFinite ? viewportWidth : double.infinity,
          math.min(viewportBoxWidth, renderObject.size.width),
        ) -
        widget.contentPadding.horizontal;
    final maxWidth = math.max(0.0, visibleWidth - caretCellRect.left);
    return Positioned(
      left: widget.contentPadding.left + caretCellRect.left,
      top: widget.contentPadding.top + caretCellRect.top,
      child: IgnorePointer(
        child: SizedBox(
          key: const Key('terminal-composing-overlay'),
          width: maxWidth,
          child: ClipRect(
            child: DecoratedBox(
              decoration: BoxDecoration(color: colors.canvasBackground),
              child: Text(
                text,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  fontFamily: widget.font.family,
                  fontFamilyFallback: widget.font.fallback,
                  fontSize: widget.font.size,
                  height: widget.font.lineHeight,
                  color: composingForeground,
                  decoration: TextDecoration.underline,
                  decorationColor: composingForeground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _composingForegroundColor(TerminalViewportColors colors) {
    return Color.alphaBlend(
      colors.foreground.withAlpha(0x99),
      colors.canvasBackground,
    );
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasuredCellSizeReport();
    _scheduleTextInputGeometrySync();
    final colors = _resolvedColors(context);
    return Focus(
      autofocus: true,
      focusNode: _focusNode,
      onKeyEvent: (_, event) => _handleTerminalKeyEvent(event),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _focusNode.requestFocus(),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerHover: _handlePointerHover,
          onPointerUp: _handlePointerUp,
          onPointerCancel: _handlePointerCancel,
          onPointerSignal: _handlePointerSignal,
          onPointerPanZoomStart: _handlePanZoomStart,
          onPointerPanZoomUpdate: _handlePanZoomUpdate,
          onPointerPanZoomEnd: _handlePanZoomEnd,
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              final frame = widget.controller.frame;
              final graphics = frame.graphics;
              return LayoutBuilder(
                builder: (context, constraints) {
                  final contentPadding = widget.contentPadding;
                  final trackHeight = math.max(0.0, constraints.maxHeight - 16);
                  return DecoratedBox(
                    decoration: BoxDecoration(color: colors.canvasBackground),
                    child: Stack(
                      children: [
                        ..._buildGraphicOverlays(
                          frame,
                          graphics,
                          contentPadding,
                          belowText: true,
                        ),
                        Positioned.fill(
                          child: Padding(
                            padding: contentPadding,
                            child: _TerminalViewportSurface(
                              key: _surfaceKey,
                              controller: widget.controller,
                              selectionController: widget.selectionController,
                              cursorVisible:
                                  _canDisplayFrameCursor && _cursorVisible,
                              font: widget.font,
                              cursor: widget.cursor,
                              colors: colors,
                              searchMatches: widget.searchMatches,
                              activeSearchMatchIndex:
                                  widget.activeSearchMatchIndex,
                              searchHighlightStyle:
                                  widget.searchHighlightStyle ??
                                  const TerminalSearchHighlightStyle(),
                            ),
                          ),
                        ),
                        ..._buildInlineImageOverlays(
                          frame,
                          contentPadding,
                          colors,
                        ),
                        ..._buildGraphicOverlays(
                          frame,
                          graphics,
                          contentPadding,
                          belowText: false,
                        ),
                        if (widget.showLineTimestamps)
                          ..._buildTimestampOverlays(
                            frame,
                            contentPadding,
                            colors,
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
                        ?_buildComposingOverlay(
                          colors,
                          viewportWidth: constraints.maxWidth,
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

  List<Widget> _buildInlineImageOverlays(
    TerminalFrameDiff frame,
    EdgeInsets contentPadding,
    TerminalViewportColors colors,
  ) {
    if (frame.inlineImages.isEmpty) {
      return const <Widget>[];
    }
    final cellSize =
        widget.controller.measuredCellSize ?? terminalFallbackCellSize;
    if (cellSize.width <= 0 || cellSize.height <= 0) {
      return const <Widget>[];
    }
    return [
      for (final image in frame.inlineImages)
        if (image.row >= 0 &&
            image.row < frame.viewportRows &&
            image.col >= 0 &&
            image.widthCells > 0 &&
            image.heightCells > 0)
          Positioned(
            left: contentPadding.left + image.col * cellSize.width,
            top: contentPadding.top + image.row * cellSize.height,
            width: image.widthCells * cellSize.width,
            height: image.heightCells * cellSize.height,
            child: IgnorePointer(
              key: Key('terminal-inline-image-${image.row}-${image.col}'),
              child: Image.memory(
                image.bytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                semanticLabel: image.altText,
                errorBuilder: (context, error, stackTrace) {
                  return ColoredBox(
                    color: colors.foreground.withValues(alpha: 0.18),
                  );
                },
              ),
            ),
          ),
    ];
  }

  List<Widget> _buildGraphicOverlays(
    TerminalFrameDiff frame,
    List<TerminalGraphicPlacement> graphics,
    EdgeInsets contentPadding, {
    required bool belowText,
  }) {
    final graphicsCache = widget.graphicsCache;
    if (graphicsCache == null || graphics.isEmpty) {
      return const <Widget>[];
    }
    final cellSize =
        widget.controller.measuredCellSize ?? terminalFallbackCellSize;
    if (cellSize.width <= 0 || cellSize.height <= 0) {
      return const <Widget>[];
    }
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(
      context,
    ).clamp(1.0, double.infinity).toDouble();
    final placements = graphics
        .where((graphic) {
          return belowText ? graphic.zIndex < 0 : graphic.zIndex >= 0;
        })
        .toList(growable: false);
    if (placements.isEmpty) {
      return const <Widget>[];
    }
    return [
      for (final graphic in placements)
        if (graphic.row >= 0 &&
            graphic.row < frame.viewportRows &&
            graphic.col >= 0 &&
            graphic.widthCells > 0 &&
            graphic.heightCells > 0)
          Positioned(
            left:
                contentPadding.left +
                graphic.col * cellSize.width +
                graphic.xOffsetPx / devicePixelRatio,
            top:
                contentPadding.top +
                graphic.row * cellSize.height +
                graphic.yOffsetPx / devicePixelRatio,
              width: graphic.widthCells * cellSize.width,
              height: graphic.heightCells * cellSize.height,
              child: IgnorePointer(
                child: _TerminalGraphicOverlay(
                  key: Key('terminal-graphic-${graphic.renderId}'),
                  cache: graphicsCache,
                  placement: graphic,
                ),
              ),
          ),
    ];
  }

  List<Widget> _buildTimestampOverlays(
    TerminalFrameDiff frame,
    EdgeInsets contentPadding,
    TerminalViewportColors colors,
  ) {
    final timestampedRows = frame.rows
        .where((row) => row.modifiedAt != null && row.text.trim().isNotEmpty)
        .toList(growable: false);
    if (timestampedRows.isEmpty) {
      return const <Widget>[];
    }
    final cellSize =
        widget.controller.measuredCellSize ?? terminalFallbackCellSize;
    if (cellSize.width <= 0 || cellSize.height <= 0) {
      return const <Widget>[];
    }
    final textStyle = TextStyle(
      color: colors.foreground.withValues(alpha: 0.58),
      fontFamily: widget.font.family,
      fontFamilyFallback: widget.font.fallback,
      fontSize: math.max(9.0, math.min(11.0, widget.font.size * 0.72)),
      height: 1,
    );
    final rightInset =
        contentPadding.right + (frame.scrollbackMaxOffset > 0 ? 16.0 : 0.0);
    return [
      for (final row in timestampedRows)
        if (row.index >= 0 && row.index < frame.viewportRows)
          Positioned(
            top: contentPadding.top + row.index * cellSize.height,
            right: rightInset,
            width: _terminalTimestampOverlayWidth,
            height: cellSize.height,
            child: IgnorePointer(
              key: Key('terminal-line-timestamp-${row.index}'),
              child: Align(
                alignment: Alignment.centerRight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.canvasBackground.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      _formatLineTimestamp(row.modifiedAt!),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      textAlign: TextAlign.right,
                      style: textStyle,
                    ),
                  ),
                ),
              ),
            ),
          ),
    ];
  }

  @override
  TextEditingValue? get currentTextEditingValue => _textInputValue;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    final previousValue = _textInputValue;
    final hadActiveComposition = _hasActiveImeComposition(previousValue);
    final hasActiveComposition = _hasActiveImeComposition(value);
    _updateTextInputState(() {
      _textInputValue = value;
      if (hasActiveComposition) {
        _hadImeComposition = true;
      }
    });
    if (hasActiveComposition) {
      _scheduleTextInputGeometrySync();
      return;
    }
    final text = _committedTextFromEditingValue(
      value,
      previousValue: previousValue,
      hadActiveComposition: hadActiveComposition,
    );
    if (text.isNotEmpty && _shouldForwardCommittedText(text)) {
      widget.inputController.sendText(text);
    }
    _clearTextInputState();
  }

  String _committedTextFromEditingValue(
    TextEditingValue value, {
    required TextEditingValue previousValue,
    required bool hadActiveComposition,
  }) {
    final text = value.text;
    if (!hadActiveComposition || text.isEmpty) {
      return text;
    }

    final previousText = previousValue.text;
    if (previousText.isEmpty) {
      return text;
    }

    final previousComposingText = _activeComposingText(previousValue);
    if (previousComposingText != null &&
        _isPrintableAscii(previousComposingText) &&
        _isPrintableAscii(text)) {
      return _deferredImeRawText.isNotEmpty
          ? _deferredImeRawText
          : previousComposingText;
    }

    final replacement = _replacementTextBetween(previousText, text);
    if (replacement.isNotEmpty || text != previousText) {
      return replacement;
    }

    if (previousComposingText != null && previousComposingText.isNotEmpty) {
      return previousComposingText;
    }
    return text;
  }

  String _replacementTextBetween(String previousText, String text) {
    final previousRunes = previousText.runes.toList(growable: false);
    final textRunes = text.runes.toList(growable: false);
    var prefixLength = 0;
    final previousLength = previousRunes.length;
    final textLength = textRunes.length;
    while (prefixLength < previousLength &&
        prefixLength < textLength &&
        previousRunes[prefixLength] == textRunes[prefixLength]) {
      prefixLength += 1;
    }

    var previousSuffix = previousLength;
    var textSuffix = textLength;
    while (previousSuffix > prefixLength &&
        textSuffix > prefixLength &&
        previousRunes[previousSuffix - 1] == textRunes[textSuffix - 1]) {
      previousSuffix -= 1;
      textSuffix -= 1;
    }

    return String.fromCharCodes(textRunes.sublist(prefixLength, textSuffix));
  }

  @override
  void performAction(TextInputAction action) {}

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void connectionClosed() {
    _textInputConnection = null;
    _updateTextInputState(_resetTextInputTracking);
    if (_focusNode.hasFocus) {
      _openTextInputConnection();
      _scheduleTextInputGeometrySync();
    }
  }

  bool _hasActiveImeComposition(TextEditingValue value) {
    return value.composing.isValid && !value.composing.isCollapsed;
  }

  String? _activeComposingText(TextEditingValue value) {
    if (!_hasActiveImeComposition(value)) {
      return null;
    }
    return value.composing.textInside(value.text);
  }

  bool _shouldForwardCommittedText(String text) {
    return _hadImeComposition ||
        _awaitingSystemTextCommit ||
        _containsNonAscii(text) ||
        text.runes.length > 1;
  }

  bool _isPrintableAscii(String text) {
    return text.isNotEmpty &&
        text.runes.every((codePoint) => codePoint >= 0x20 && codePoint <= 0x7e);
  }

  bool _containsNonAscii(String text) {
    return text.runes.any((codePoint) => codePoint > 0x7f);
  }
}

bool _isTerminalKeyPressEvent(KeyEvent event) {
  return event is KeyDownEvent || event is KeyRepeatEvent;
}

_TerminalWordRange? _wordRangeAtRelativeCell(
  TerminalFrameDiff frame,
  int relativeRow,
  int column, {
  bool allowWhitespaceOnlySelection = true,
  bool followWrappedLinesAbove = true,
  bool followWrappedLinesBelow = true,
}) {
  final row = _rowForRelativeIndex(frame, relativeRow);
  if (row == null) {
    return null;
  }
  final rowCells = TerminalTextCells.fromText(row.text);
  final cell = _primaryCellAtColumn(rowCells, column);
  if (cell == null) {
    return null;
  }
  final smartRange = _smartRangeAtCell(
    frame: frame,
    relativeRow: relativeRow,
    rowText: row.text,
    rowCells: rowCells,
    cell: cell,
  );
  if (smartRange != null) {
    return smartRange;
  }
  final kind = _wordCellKind(cell);
  if (!allowWhitespaceOnlySelection && kind == _WordCellKind.whitespace) {
    return null;
  }

  var startRow = frame.viewportStartRow + relativeRow;
  var startCol = cell.column;
  var endRow = frame.viewportStartRow + relativeRow;
  var endCol = cell.column + cell.columnSpan;

  switch (kind) {
    case _WordCellKind.whitespace:
      while (true) {
        final previous = _primaryCellBeforeColumn(rowCells, startCol);
        if (previous == null || _wordCellKind(previous) != kind) {
          break;
        }
        startCol = previous.column;
      }
      while (true) {
        final next = _primaryCellAtOrAfterColumn(rowCells, endCol);
        if (next == null || _wordCellKind(next) != kind) {
          break;
        }
        endCol = next.column + next.columnSpan;
      }
      break;
    case _WordCellKind.separator:
      break;
    case _WordCellKind.text:
      while (true) {
        final previous = _primaryCellBeforeColumn(rowCells, startCol);
        if (previous == null || _wordCellKind(previous) != kind) {
          break;
        }
        startCol = previous.column;
      }
      while (true) {
        final next = _primaryCellAtOrAfterColumn(rowCells, endCol);
        if (next == null || _wordCellKind(next) != kind) {
          break;
        }
        endCol = next.column + next.columnSpan;
      }

      if (followWrappedLinesAbove &&
          startCol == 0 &&
          _rowContinuesFromAbove(frame, relativeRow)) {
        final previousRow = _rowForRelativeIndex(frame, relativeRow - 1);
        final previousCells = previousRow == null
            ? null
            : TerminalTextCells.fromText(previousRow.text);
        final previousLastCell = previousCells == null
            ? null
            : _primaryCellBeforeColumn(previousCells, previousCells.cellCount);
        if (previousLastCell != null &&
            _wordCellKind(previousLastCell) == _WordCellKind.text) {
          final previousRange = _wordRangeAtRelativeCell(
            frame,
            relativeRow - 1,
            previousLastCell.column,
            allowWhitespaceOnlySelection: false,
            followWrappedLinesAbove: true,
            followWrappedLinesBelow: false,
          );
          if (previousRange != null) {
            startRow = previousRange.startRow;
            startCol = previousRange.startCol;
          }
        }
      }

      if (followWrappedLinesBelow &&
          endCol == rowCells.cellCount &&
          row.wrapped) {
        final nextRow = _rowForRelativeIndex(frame, relativeRow + 1);
        final nextCells = nextRow == null
            ? null
            : TerminalTextCells.fromText(nextRow.text);
        final nextFirstCell = nextCells == null
            ? null
            : _primaryCellAtOrAfterColumn(nextCells, 0);
        if (nextFirstCell != null &&
            _wordCellKind(nextFirstCell) == _WordCellKind.text) {
          final nextRange = _wordRangeAtRelativeCell(
            frame,
            relativeRow + 1,
            nextFirstCell.column,
            allowWhitespaceOnlySelection: false,
            followWrappedLinesAbove: false,
            followWrappedLinesBelow: true,
          );
          if (nextRange != null) {
            endRow = nextRange.endRow;
            endCol = nextRange.endCol;
          }
        }
      }
  }

  return _TerminalWordRange(
    startRow: startRow,
    startCol: startCol,
    endRow: endRow,
    endCol: endCol,
  );
}

_TerminalWordRange? _smartRangeAtCell({
  required TerminalFrameDiff frame,
  required int relativeRow,
  required String rowText,
  required TerminalTextCells rowCells,
  required TerminalTextCell cell,
}) {
  final codeUnit = cell.codeUnitStart;
  final patterns = <RegExp>[
    _visibleUrlPattern,
    _smartEmailPattern,
    _smartPathPattern,
  ];
  for (final pattern in patterns) {
    for (final match in pattern.allMatches(rowText)) {
      final range = _trimSmartSelectionRange(rowText, match.start, match.end);
      if (range == null || codeUnit < range.start || codeUnit >= range.end) {
        continue;
      }
      return _TerminalWordRange(
        startRow: frame.viewportStartRow + relativeRow,
        startCol: rowCells.columnForCodeUnit(range.start),
        endRow: frame.viewportStartRow + relativeRow,
        endCol: rowCells.columnForCodeUnit(range.end),
      );
    }
  }
  return null;
}

_SmartSelectionCodeUnitRange? _trimSmartSelectionRange(
  String text,
  int start,
  int end,
) {
  var rangeStart = start;
  var rangeEnd = end;
  while (rangeStart < rangeEnd &&
      _smartSelectionLeadingTrim.contains(text[rangeStart])) {
    rangeStart += 1;
  }
  while (rangeEnd > rangeStart &&
      _smartSelectionTrailingTrim.contains(text[rangeEnd - 1])) {
    rangeEnd -= 1;
  }
  if (rangeStart >= rangeEnd) {
    return null;
  }
  return _SmartSelectionCodeUnitRange(rangeStart, rangeEnd);
}

class _SmartSelectionCodeUnitRange {
  const _SmartSelectionCodeUnitRange(this.start, this.end);

  final int start;
  final int end;
}

TerminalRow? _rowForRelativeIndex(TerminalFrameDiff frame, int rowIndex) {
  for (final row in frame.rows) {
    if (row.index == rowIndex) {
      return row;
    }
  }
  return null;
}

bool _rowContinuesFromAbove(TerminalFrameDiff frame, int rowIndex) {
  final previousRow = _rowForRelativeIndex(frame, rowIndex - 1);
  return previousRow?.wrapped ?? false;
}

String _formatLineTimestamp(DateTime timestamp) {
  final local = timestamp.toLocal();
  return '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}:'
      '${_twoDigits(local.second)}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

TerminalTextCell? _primaryCellAtColumn(TerminalTextCells cells, int column) {
  if (cells.cellCount <= 0) {
    return null;
  }
  var index = column.clamp(0, cells.cellCount - 1).toInt();
  while (index > 0 && cells.cells[index].isContinuation) {
    index -= 1;
  }
  final cell = cells.cells[index];
  return cell.isContinuation ? null : cell;
}

TerminalTextCell? _primaryCellBeforeColumn(
  TerminalTextCells cells,
  int column,
) {
  for (
    var index = math.min(column, cells.cellCount).toInt() - 1;
    index >= 0;
    index -= 1
  ) {
    final cell = cells.cells[index];
    if (!cell.isContinuation) {
      return cell;
    }
  }
  return null;
}

TerminalTextCell? _primaryCellAtOrAfterColumn(
  TerminalTextCells cells,
  int column,
) {
  for (
    var index = math.max(0, column).toInt();
    index < cells.cellCount;
    index += 1
  ) {
    final cell = cells.cells[index];
    if (!cell.isContinuation) {
      return cell;
    }
  }
  return null;
}

_WordCellKind _wordCellKind(TerminalTextCell cell) {
  if (cell.text.trim().isEmpty) {
    return _WordCellKind.whitespace;
  }
  if (_xtermWordSeparators.contains(cell.text)) {
    return _WordCellKind.separator;
  }
  return _WordCellKind.text;
}

TerminalSelection _selectionForWordDrag(
  _TerminalWordRange anchor,
  _TerminalWordRange target,
) {
  if (_compareSelectionPositions(
        target.endRow,
        target.endCol,
        anchor.startRow,
        anchor.startCol,
      ) <=
      0) {
    return TerminalSelection(
      startRow: target.startRow,
      startCol: target.startCol,
      endRow: anchor.endRow,
      endCol: anchor.endCol,
    );
  }
  if (_compareSelectionPositions(
        target.startRow,
        target.startCol,
        anchor.endRow,
        anchor.endCol,
      ) >=
      0) {
    return TerminalSelection(
      startRow: anchor.startRow,
      startCol: anchor.startCol,
      endRow: target.endRow,
      endCol: target.endCol,
    );
  }
  return anchor.selection;
}

int _compareSelectionPositions(
  int leftRow,
  int leftCol,
  int rightRow,
  int rightCol,
) {
  if (leftRow != rightRow) {
    return leftRow.compareTo(rightRow);
  }
  return leftCol.compareTo(rightCol);
}

enum _WordCellKind { whitespace, separator, text }

class _TerminalWordRange {
  const _TerminalWordRange({
    required this.startRow,
    required this.startCol,
    required this.endRow,
    required this.endCol,
  });

  final int startRow;
  final int startCol;
  final int endRow;
  final int endCol;

  TerminalSelection get selection => TerminalSelection(
    startRow: startRow,
    startCol: startCol,
    endRow: endRow,
    endCol: endCol,
  );
}

class _TerminalViewportSurface extends LeafRenderObjectWidget {
  const _TerminalViewportSurface({
    super.key,
    required this.controller,
    required this.selectionController,
    required this.cursorVisible,
    required this.font,
    required this.cursor,
    required this.colors,
    required this.searchMatches,
    required this.activeSearchMatchIndex,
    required this.searchHighlightStyle,
  });

  final TerminalViewportController controller;
  final SelectionController selectionController;
  final bool cursorVisible;
  final TerminalFontConfig font;
  final TerminalCursorConfig cursor;
  final TerminalViewportColors colors;
  final List<TerminalSearchMatch> searchMatches;
  final int activeSearchMatchIndex;
  final TerminalSearchHighlightStyle searchHighlightStyle;

  @override
  RenderTerminalViewport createRenderObject(BuildContext context) {
    return RenderTerminalViewport(
      controller: controller,
      selectionController: selectionController,
      cursorVisible: cursorVisible,
      font: font,
      cursor: cursor,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      colors: colors,
      searchMatches: searchMatches,
      activeSearchMatchIndex: activeSearchMatchIndex,
      searchHighlightStyle: searchHighlightStyle,
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
      ..font = font
      ..cursor = cursor
      ..colors = colors
      ..searchMatches = searchMatches
      ..activeSearchMatchIndex = activeSearchMatchIndex
      ..searchHighlightStyle = searchHighlightStyle
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  }
}

class _TerminalGraphicOverlay extends StatefulWidget {
  const _TerminalGraphicOverlay({
    super.key,
    required this.cache,
    required this.placement,
  });

  final TerminalGraphicsCache cache;
  final TerminalGraphicPlacement placement;

  @override
  State<_TerminalGraphicOverlay> createState() =>
      _TerminalGraphicOverlayState();
}

class _TerminalGraphicOverlayState extends State<_TerminalGraphicOverlay> {
  Future<ui.Image?>? _imageFuture;
  TerminalGraphicAssetKey? _assetKey;
  ui.Image? _visibleImage;

  @override
  void initState() {
    super.initState();
    _syncImageFuture();
  }

  @override
  void didUpdateWidget(covariant _TerminalGraphicOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cache != widget.cache) {
      _clearVisibleImage();
    }
    if (oldWidget.cache != widget.cache ||
        oldWidget.placement.assetKey != widget.placement.assetKey) {
      _syncImageFuture();
    }
  }

  @override
  void dispose() {
    _clearVisibleImage();
    super.dispose();
  }

  void _syncImageFuture() {
    final assetKey = widget.placement.assetKey;
    _assetKey = assetKey;
    final future = widget.cache.imageFor(assetKey);
    _imageFuture = future;
    future.then(
      (image) {
        if (!mounted || _assetKey != assetKey || image == null) {
          return;
        }
        setState(() {
          _replaceVisibleImage(image.clone());
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        // Keep the previous frame visible if a replacement image fails to load.
      },
    );
  }

  void _replaceVisibleImage(ui.Image image) {
    final previous = _visibleImage;
    _visibleImage = image;
    previous?.dispose();
  }

  void _clearVisibleImage() {
    _visibleImage?.dispose();
    _visibleImage = null;
  }

  @override
  Widget build(BuildContext context) {
    final image = _visibleImage;
    if (image == null || _imageFuture == null) {
      return const SizedBox.shrink();
    }
    return RawImage(
      image: image,
      fit: widget.placement.preserveAspectRatio ? BoxFit.contain : BoxFit.fill,
      filterQuality: FilterQuality.medium,
    );
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
