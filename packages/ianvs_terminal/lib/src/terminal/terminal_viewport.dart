import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/terminal_config.dart';
import '../runtime/terminal_benchmarking.dart';
import 'render_terminal_viewport.dart';
import 'selection_controller.dart';
import 'terminal_focus_reporter.dart';
import 'terminal_graphics_cache.dart';
import 'terminal_graphics_diagnostics.dart';
import 'terminal_graphics_sync.dart';
import 'terminal_input_controller.dart';
import 'terminal_models.dart';
import 'terminal_text_document_style.dart';
import 'terminal_viewport_colors.dart';

const Key terminalScrollbarTrackKey = Key('terminal-scrollbar-track');
const Key terminalScrollbarThumbKey = Key('terminal-scrollbar-thumb');
const Key terminalLinkTooltipKey = Key('terminal-link-tooltip');
Key terminalBlockToggleKey(String id) => Key('terminal-block-toggle-$id');
Key terminalBlockRenderCloseKey(String id) =>
    Key('terminal-block-render-close-$id');
Key terminalInlineButtonKey(int id) => Key('terminal-inline-button-$id');
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

MouseCursor _mouseCursorForPointerShape(TerminalPointerShape shape) {
  return switch (shape) {
    TerminalPointerShape.alias => SystemMouseCursors.alias,
    TerminalPointerShape.cell => SystemMouseCursors.cell,
    TerminalPointerShape.copy => SystemMouseCursors.copy,
    TerminalPointerShape.crosshair => SystemMouseCursors.precise,
    TerminalPointerShape.basic => SystemMouseCursors.basic,
    TerminalPointerShape.eastResize => SystemMouseCursors.resizeRight,
    TerminalPointerShape.eastWestResize => SystemMouseCursors.resizeLeftRight,
    TerminalPointerShape.grab => SystemMouseCursors.grab,
    TerminalPointerShape.grabbing => SystemMouseCursors.grabbing,
    TerminalPointerShape.help => SystemMouseCursors.help,
    TerminalPointerShape.move => SystemMouseCursors.move,
    TerminalPointerShape.northResize => SystemMouseCursors.resizeUp,
    TerminalPointerShape.northEastResize => SystemMouseCursors.resizeUpRight,
    TerminalPointerShape.northEastSouthWestResize =>
      SystemMouseCursors.resizeUpRightDownLeft,
    TerminalPointerShape.noDrop => SystemMouseCursors.noDrop,
    TerminalPointerShape.notAllowed => SystemMouseCursors.forbidden,
    TerminalPointerShape.northSouthResize => SystemMouseCursors.resizeUpDown,
    TerminalPointerShape.northWestResize => SystemMouseCursors.resizeUpLeft,
    TerminalPointerShape.northWestSouthEastResize =>
      SystemMouseCursors.resizeUpLeftDownRight,
    TerminalPointerShape.pointer => SystemMouseCursors.click,
    TerminalPointerShape.progress => SystemMouseCursors.progress,
    TerminalPointerShape.southResize => SystemMouseCursors.resizeDown,
    TerminalPointerShape.southEastResize => SystemMouseCursors.resizeDownRight,
    TerminalPointerShape.southWestResize => SystemMouseCursors.resizeDownLeft,
    TerminalPointerShape.text => SystemMouseCursors.text,
    TerminalPointerShape.verticalText => SystemMouseCursors.verticalText,
    TerminalPointerShape.westResize => SystemMouseCursors.resizeLeft,
    TerminalPointerShape.wait => SystemMouseCursors.wait,
    TerminalPointerShape.zoomIn => SystemMouseCursors.zoomIn,
    TerminalPointerShape.zoomOut => SystemMouseCursors.zoomOut,
  };
}

class TerminalLinkTarget {
  const TerminalLinkTarget({
    required this.uri,
    required this.globalPosition,
    this.visibleText,
    this.explicitHyperlink = false,
    this.protocolId,
  });

  final String uri;
  final Offset globalPosition;
  final String? visibleText;
  final bool explicitHyperlink;
  final String? protocolId;

  bool get hasMismatchedVisibleText {
    final text = visibleText?.trim();
    final target = uri.trim();
    return explicitHyperlink &&
        text != null &&
        text.isNotEmpty &&
        text != target;
  }
}

class TerminalViewportController extends ChangeNotifier {
  TerminalViewportController({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  TerminalViewportState _state = TerminalViewportState.empty;
  final DateTime Function() _now;
  Size? _measuredCellSize;
  int _frameVersion = 0;
  int _graphicsRevision = 0;
  int _graphicsAssetRevision = 0;
  Set<TerminalGraphicAssetKey> _graphicsAssetKeys =
      const <TerminalGraphicAssetKey>{};

  TerminalViewportState get state => _state;
  TerminalFrameDiff get frame => _state.frame;
  int get frameVersion => _frameVersion;
  int get graphicsRevision => _graphicsRevision;
  int get graphicsAssetRevision => _graphicsAssetRevision;
  Set<TerminalGraphicAssetKey> get graphicsAssetKeys => _graphicsAssetKeys;
  Size? get measuredCellSize => _measuredCellSize;

  void updateFrame(TerminalFrameDiff value) {
    _replaceState(_state.applyFrame(value, capturedAt: _now()));
  }

  void applySnapshot(TerminalFrameDiff value) {
    _replaceState(_state.applySnapshot(value, capturedAt: _now()));
  }

  void applyDelta(TerminalFrameDiff value) {
    _replaceState(_state.applyDelta(value, capturedAt: _now()));
  }

  void _replaceState(TerminalViewportState nextState) {
    final nextGraphics = nextState.frame.graphics;
    if (!listEquals(_state.frame.graphics, nextGraphics)) {
      _graphicsRevision += 1;
      final nextAssetKeys = nextGraphics.isEmpty
          ? const <TerminalGraphicAssetKey>{}
          : Set<TerminalGraphicAssetKey>.unmodifiable(
              nextGraphics.map((graphic) => graphic.assetKey),
            );
      if (!setEquals(_graphicsAssetKeys, nextAssetKeys)) {
        _graphicsAssetRevision += 1;
        _graphicsAssetKeys = nextAssetKeys;
      }
    }
    _state = nextState;
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
    this.useFrameDefaultColors = true,
    this.font = const TerminalFontConfig(),
    this.cursor = const TerminalCursorConfig(),
    this.copyOnSelect = false,
    this.showLineTimestamps = false,
    this.optionDragMode = TerminalOptionDragMode.blockSelection,
    this.focusNode,
    this.onHostKeyEvent,
    this.onOpenLink,
    this.onOpenLinkTarget,
    this.onLinkHoverChanged,
    this.onLinkContextMenu,
    this.searchMatches = const [],
    this.activeSearchMatchIndex = -1,
    this.searchHighlightStyle,
    this.graphicsCache,
    this.benchmarkEventSink,
    this.graphicsDiagnosticSessionId,
    this.onToggleBlock,
    this.onDismissBlockRender,
    this.onActivateInlineButton,
    this.inlineButtonEnabled,
    this.onScaleStart,
    this.onScaleUpdate,
    this.onScaleEnd,
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

  /// Whether the backend frame's default foreground and background override
  /// the viewport's configured colors.
  ///
  /// Set this to false when an app-level theme must remain authoritative.
  final bool useFrameDefaultColors;
  final TerminalFontConfig font;
  final TerminalCursorConfig cursor;
  final bool copyOnSelect;
  final bool showLineTimestamps;
  final TerminalOptionDragMode optionDragMode;
  final FocusNode? focusNode;
  final KeyEventResult Function(KeyEvent event)? onHostKeyEvent;
  final ValueChanged<String>? onOpenLink;
  final ValueChanged<TerminalLinkTarget>? onOpenLinkTarget;
  final ValueChanged<TerminalLinkTarget?>? onLinkHoverChanged;
  final ValueChanged<TerminalLinkTarget>? onLinkContextMenu;
  final List<TerminalSearchMatch> searchMatches;
  final int activeSearchMatchIndex;
  final TerminalSearchHighlightStyle? searchHighlightStyle;
  final TerminalGraphicsCache? graphicsCache;
  final TerminalBenchmarkEventSink? benchmarkEventSink;
  final String? graphicsDiagnosticSessionId;
  final ValueChanged<TerminalBlock>? onToggleBlock;
  final ValueChanged<TerminalBlock>? onDismissBlockRender;
  final ValueChanged<TerminalInlineButton>? onActivateInlineButton;
  final bool Function(TerminalInlineButton button)? inlineButtonEnabled;
  final GestureScaleStartCallback? onScaleStart;
  final GestureScaleUpdateCallback? onScaleUpdate;
  final GestureScaleEndCallback? onScaleEnd;

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
  final TerminalFocusReporter _focusReporter = TerminalFocusReporter();
  bool _isLocalSelectionActive = false;
  Offset? _selectionPointerGlobalPosition;
  Offset? _selectionPointerDownGlobalPosition;
  Offset? _lastHoverGlobalPosition;
  TerminalLinkTarget? _hoveredLinkTarget;
  Offset? _lastPrimaryTapUpPosition;
  Duration? _lastPrimaryTapUpTimestamp;
  int _lastPrimaryTapCount = 0;
  int _currentPrimaryTapCount = 0;
  Offset? _activeMouseButtonGlobalPosition;
  bool _selectionMovedSincePointerDown = false;
  bool _blockTogglePointerActive = false;
  bool _pinchGestureActive = false;
  _LocalSelectionMode _localSelectionMode = _LocalSelectionMode.cell;
  _TerminalWordRange? _wordSelectionAnchor;
  TextInputConnection? _textInputConnection;
  TextEditingValue _textInputValue = TextEditingValue.empty;
  bool _hadImeComposition = false;
  bool _awaitingSystemTextCommit = false;
  String _deferredImeRawText = '';
  bool _deferredImeBackspaceHandled = false;
  bool _suppressNextBackspaceAfterImeClear = false;
  bool _suppressImeClearBackspaceUntilKeyUp = false;
  bool _textInputGeometrySyncScheduled = false;
  bool _suppressNextMobileTextAction = false;
  String? _submittedMobileTextPendingReset;
  int _pendingMobileRawBackspaces = 0;
  bool _mobileRawBackspaceResetScheduled = false;
  final TerminalGraphicsSync _graphicsSync = TerminalGraphicsSync();
  late MouseCursor _lastTerminalPointerCursor;
  FocusNode get _focusNode =>
      widget.focusNode ??
      (_ownedFocusNode ??= FocusNode(debugLabel: 'terminal-viewport'));

  @override
  void initState() {
    super.initState();
    _lastTerminalPointerCursor = _terminalPointerCursor;
    widget.controller.addListener(_handleFrameUpdate);
    _bindFocusNodeListener();
    _syncCursorBlinkTimer();
    _syncGraphicsCache();
    if (_focusNode.hasFocus) {
      _syncFocusTrackingReport();
    }
  }

  @override
  void didUpdateWidget(covariant TerminalViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_handleFrameUpdate);
      widget.controller.addListener(_handleFrameUpdate);
      _lastTerminalPointerCursor = _terminalPointerCursor;
    }
    if (!identical(oldWidget.controller, widget.controller) ||
        !identical(oldWidget.graphicsCache, widget.graphicsCache)) {
      _syncGraphicsCache();
    }
    final focusNodeChanged = !identical(oldWidget.focusNode, widget.focusNode);
    final focusReportOwnerChanged =
        !identical(oldWidget.controller, widget.controller) ||
        oldWidget.inputController.sessionId !=
            widget.inputController.sessionId ||
        !identical(
          oldWidget.inputController.runtime,
          widget.inputController.runtime,
        );
    if (focusNodeChanged || focusReportOwnerChanged) {
      _reportFocusTrackingLossForDetachedFocus(
        focusNode: _listenedFocusNode,
        modes: oldWidget.controller.frame.modes,
        inputController: oldWidget.inputController,
      );
      if (focusReportOwnerChanged) {
        _focusReporter.reset();
      }
    }
    if (focusNodeChanged) {
      _unbindFocusNodeListener();
      _bindFocusNodeListener();
    }
    _syncTextInputConnection();
    _syncFocusTrackingReport();
    _syncCursorBlinkTimer();
  }

  @override
  void dispose() {
    widget.onLinkHoverChanged?.call(null);
    widget.controller.removeListener(_handleFrameUpdate);
    _graphicsSync.reset();
    _reportFocusTrackingLossOnUnmount();
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

  void _reportFocusTrackingLossOnUnmount() {
    _reportFocusTrackingLossForDetachedFocus(
      focusNode: _listenedFocusNode,
      modes: widget.controller.frame.modes,
    );
  }

  void _reportFocusTrackingLossForDetachedFocus({
    required FocusNode? focusNode,
    required TerminalFrameModes modes,
    TerminalInputController? inputController,
  }) {
    final decision = _focusReporter.detach(
      focusTrackingEnabled: modes.focusTracking,
      focusNodeHasFocus: focusNode?.hasFocus ?? false,
    );
    if (decision == null) {
      return;
    }
    (inputController ?? widget.inputController).sendFocusReport(
      focused: decision.focused,
      modes: modes,
    );
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
    final pointerCursor = _terminalPointerCursor;
    if (pointerCursor != _lastTerminalPointerCursor) {
      _lastTerminalPointerCursor = pointerCursor;
      setState(() {});
    }
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
      _setHoveredLinkTarget(null);
    } else {
      final hoverPosition = _lastHoverGlobalPosition;
      if (hoverPosition != null) {
        _updateHoveredLinkTarget(hoverPosition);
      }
    }
  }

  void _syncGraphicsCache() {
    final controller = widget.controller;
    _graphicsSync.synchronize(
      controllerIdentity: controller,
      cache: widget.graphicsCache,
      assetRevision: controller.graphicsAssetRevision,
      liveAssetKeys: controller.graphicsAssetKeys,
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

  void _focusTerminalFromTap() {
    _focusNode.requestFocus();
    if (!_usesMobileTextInput || !_focusNode.hasFocus) {
      return;
    }
    // iOS can dismiss the software keyboard without releasing Flutter focus.
    // A later tap on the still-focused terminal should ask the system input
    // connection to show the keyboard again.
    _openTextInputConnection();
    _scheduleTextInputGeometrySync();
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
    _deferredImeBackspaceHandled = false;
    _suppressNextBackspaceAfterImeClear = false;
    _suppressImeClearBackspaceUntilKeyUp = false;
    _submittedMobileTextPendingReset = null;
    _pendingMobileRawBackspaces = 0;
    _mobileRawBackspaceResetScheduled = false;
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
    final decision = _focusReporter.synchronize(
      focusTrackingEnabled: modes.focusTracking,
      hasFocus: _focusNode.hasFocus,
    );
    if (decision == null) {
      return;
    }
    widget.inputController.sendFocusReport(
      focused: decision.focused,
      modes: modes,
    );
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
      (widget.controller.frame.cursor.blink ?? widget.cursor.blink) &&
      _focusNode.hasFocus &&
      _canDisplayFrameCursor;

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
      resolvedEvent,
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

  MouseCursor get _terminalPointerCursor {
    final frame = widget.controller.frame;
    final shape = frame.pointerShape;
    if (shape != null) {
      return _mouseCursorForPointerShape(shape);
    }
    return frame.modes.mouseMode == 'off'
        ? SystemMouseCursors.text
        : SystemMouseCursors.basic;
  }

  MouseCursor get _effectivePointerCursor => _hoveredLinkTarget == null
      ? _terminalPointerCursor
      : SystemMouseCursors.click;

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
    return _mousePositionForGlobalPosition(globalPosition)?.cell;
  }

  ({TerminalCellPosition cell, int pixelX, int pixelY})?
  _mousePositionForGlobalPosition(Offset globalPosition) {
    final renderObject = _renderViewport;
    if (renderObject == null) {
      return null;
    }
    final localPosition = renderObject.globalToLocal(globalPosition);
    return _mousePositionForLocalPosition(renderObject, localPosition);
  }

  ({TerminalCellPosition cell, int pixelX, int pixelY})?
  _mousePositionForLocalPosition(
    RenderTerminalViewport renderObject,
    Offset localPosition,
  ) {
    if (localPosition.dx < 0 ||
        localPosition.dy < 0 ||
        localPosition.dx >= renderObject.size.width ||
        localPosition.dy >= renderObject.size.height) {
      return null;
    }
    final maxPixelX = math.max(0, renderObject.size.width.ceil() - 1);
    final maxPixelY = math.max(0, renderObject.size.height.ceil() - 1);
    return (
      cell: renderObject.debugCellForOffset(localPosition),
      pixelX: localPosition.dx.floor().clamp(0, maxPixelX),
      pixelY: localPosition.dy.floor().clamp(0, maxPixelY),
    );
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

  bool _isSecondaryButton(int buttons) {
    return (buttons & kSecondaryMouseButton) != 0;
  }

  void _sendMouseEvent({
    required Offset globalPosition,
    required int button,
    required bool pressed,
  }) {
    if (!_terminalMouseEnabled) {
      return;
    }
    final position = _mousePositionForGlobalPosition(globalPosition);
    if (position == null) {
      return;
    }
    widget.inputController.sendMouseReport(
      modes: widget.controller.frame.modes,
      row: position.cell.row,
      col: position.cell.col,
      button: button,
      pressed: pressed,
      modifiers: _mouseModifiers(),
      pixelX: position.pixelX,
      pixelY: position.pixelY,
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    _stopScrollMomentum();
    if (_blockTogglePointerActive) {
      return;
    }
    if (!_terminalMouseEnabled) {
      if (_isSecondaryButton(event.buttons)) {
        _showLinkContextMenuAt(event.position);
        return;
      }
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
      final sourceRow = widget.controller.frame.mappedSourceRowForViewportRow(
        cell.row,
      );
      if (sourceRow == null) {
        _isLocalSelectionActive = false;
        _selectionPointerDownGlobalPosition = null;
        _wordSelectionAnchor = null;
        _stopSelectionAutoScroll();
        return;
      }
      final foldedBlock = _foldedBlockAtViewportRow(cell.row);
      if (foldedBlock != null && widget.onToggleBlock != null) {
        _isLocalSelectionActive = false;
        _selectionPointerDownGlobalPosition = null;
        _wordSelectionAnchor = null;
        _stopSelectionAutoScroll();
        widget.onToggleBlock!(foldedBlock);
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
        sourceRow: sourceRow,
      );
      _syncSelectionAutoScroll();
      return;
    }
    if (!_surfaceContainsGlobalPosition(event.position)) {
      return;
    }
    _activeMouseButton = _mouseButtonFor(event.buttons);
    _activeMouseButtonGlobalPosition = event.position;
    _sendMouseEvent(
      globalPosition: event.position,
      button: _activeMouseButton!,
      pressed: true,
    );
  }

  TerminalBlock? _foldedBlockAtViewportRow(int row) {
    for (final block in widget.controller.frame.blocks) {
      if (block.folded && block.startRow == row) {
        return block;
      }
    }
    return null;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_pinchGestureActive) {
      return;
    }
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
    if (!_surfaceContainsGlobalPosition(event.position)) {
      return;
    }
    _activeMouseButton ??= _mouseButtonFor(event.buttons);
    _activeMouseButtonGlobalPosition = event.position;
    _sendMouseEvent(
      globalPosition: event.position,
      button: _activeMouseButton! | 32,
      pressed: true,
    );
  }

  void _handlePointerHover(PointerHoverEvent event) {
    _lastHoverGlobalPosition = event.position;
    if (!_terminalMouseEnabled) {
      _updateHoveredLinkTarget(event.position);
      return;
    }
    _setHoveredLinkTarget(null);
    if (widget.controller.frame.modes.mouseMode == 'any_event') {
      _sendAnyMouseMotion(event.position);
    }
  }

  void _sendAnyMouseMotion(Offset globalPosition) {
    _sendMouseEvent(globalPosition: globalPosition, button: 35, pressed: true);
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_pinchGestureActive) {
      return;
    }
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
    if (widget.controller.frame.modes.mouseMode == 'x10') {
      _activeMouseButton = null;
      _activeMouseButtonGlobalPosition = null;
      return;
    }
    final releasePosition = _surfaceContainsGlobalPosition(event.position)
        ? event.position
        : _activeMouseButtonGlobalPosition;
    if (releasePosition != null) {
      _sendMouseEvent(
        globalPosition: releasePosition,
        button: _activeMouseButton ?? 0,
        pressed: false,
      );
    }
    _activeMouseButton = null;
    _activeMouseButtonGlobalPosition = null;
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _stopScrollMomentum();
    if (_terminalMouseEnabled) {
      if (widget.controller.frame.modes.mouseMode == 'x10') {
        _activeMouseButton = null;
        _activeMouseButtonGlobalPosition = null;
        return;
      }
      final activeMouseButton = _activeMouseButton;
      final releasePosition = _surfaceContainsGlobalPosition(event.position)
          ? event.position
          : _activeMouseButtonGlobalPosition;
      if (activeMouseButton != null && releasePosition != null) {
        _sendMouseEvent(
          globalPosition: releasePosition,
          button: activeMouseButton,
          pressed: false,
        );
      }
      _activeMouseButton = null;
      _activeMouseButtonGlobalPosition = null;
      return;
    }
    _currentPrimaryTapCount = 0;
    _selectionMovedSincePointerDown = false;
    _isLocalSelectionActive = false;
    _selectionPointerGlobalPosition = null;
    _selectionPointerDownGlobalPosition = null;
    _lastHoverGlobalPosition = null;
    _wordSelectionAnchor = null;
    _localSelectionMode = _LocalSelectionMode.cell;
    _cancelPendingLinkOpen();
    _stopSelectionAutoScroll();
    _setHoveredLinkTarget(null);
  }

  void _handleScaleStart(ScaleStartDetails details) {
    widget.onScaleStart?.call(details);
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) {
      return;
    }
    if (!_pinchGestureActive) {
      _pinchGestureActive = true;
      _isLocalSelectionActive = false;
      _selectionPointerGlobalPosition = null;
      _selectionPointerDownGlobalPosition = null;
      _wordSelectionAnchor = null;
      _localSelectionMode = _LocalSelectionMode.cell;
      _cancelPendingLinkOpen();
      _stopSelectionAutoScroll();
      widget.selectionController.clear();
    }
    widget.onScaleUpdate?.call(details);
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    if (_pinchGestureActive) {
      widget.onScaleEnd?.call(details);
    }
    _pinchGestureActive = false;
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
    final position = globalPosition == null
        ? _mousePositionForLocalPosition(renderObject, localFallback)
        : _mousePositionForGlobalPosition(globalPosition);
    if (position == null) {
      return;
    }
    widget.inputController.sendMouseReport(
      modes: widget.controller.frame.modes,
      row: position.cell.row,
      col: position.cell.col,
      button: deltaY < 0 ? 64 : 65,
      pressed: true,
      modifiers: _mouseModifiers(),
      pixelX: position.pixelX,
      pixelY: position.pixelY,
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
    final onOpenLinkTarget = widget.onOpenLinkTarget;
    final onOpenLink = widget.onOpenLink;
    if (onOpenLinkTarget == null && onOpenLink == null) {
      return;
    }
    final target = _linkTargetAt(globalPosition);
    if (target == null) {
      return;
    }
    if (onOpenLinkTarget != null) {
      onOpenLinkTarget(target);
      return;
    }
    onOpenLink!(target.uri);
  }

  void _showLinkContextMenuAt(Offset globalPosition) {
    if (_scrollbarContainsGlobalPosition(globalPosition) ||
        !_surfaceContainsGlobalPosition(globalPosition)) {
      return;
    }
    final target = _linkTargetAt(globalPosition);
    if (target == null) {
      return;
    }
    _cancelPendingLinkOpen();
    _focusNode.requestFocus();
    widget.onLinkContextMenu?.call(target);
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
    if (widget.onOpenLink == null && widget.onOpenLinkTarget == null) {
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

  TerminalLinkTarget? _linkTargetAt(Offset globalPosition) {
    final cell = _cellForGlobalPosition(globalPosition);
    if (cell == null) {
      return null;
    }
    final frame = widget.controller.frame;
    for (final hyperlink in frame.hyperlinks) {
      if (hyperlink.row == cell.row &&
          cell.col >= hyperlink.startCol &&
          cell.col < hyperlink.endCol) {
        return TerminalLinkTarget(
          uri: hyperlink.uri,
          globalPosition: globalPosition,
          visibleText: _visibleTextForHyperlink(frame, hyperlink),
          explicitHyperlink: true,
          protocolId: hyperlink.protocolId,
        );
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
        final uri = match.group(0);
        if (uri == null) {
          continue;
        }
        return TerminalLinkTarget(
          uri: uri,
          globalPosition: globalPosition,
          visibleText: uri,
        );
      }
    }
    return null;
  }

  String? _visibleTextForHyperlink(
    TerminalFrameDiff frame,
    TerminalHyperlinkRange hyperlink,
  ) {
    TerminalRow? row;
    for (final candidate in frame.rows) {
      if (candidate.index == hyperlink.row) {
        row = candidate;
        break;
      }
    }
    final text = row?.text;
    if (text == null || text.isEmpty) {
      return null;
    }
    return TerminalTextCells.fromText(
      text,
    ).sliceColumns(hyperlink.startCol, hyperlink.endCol);
  }

  void _updateHoveredLinkTarget(Offset globalPosition) {
    if (_scrollbarContainsGlobalPosition(globalPosition) ||
        !_surfaceContainsGlobalPosition(globalPosition)) {
      _setHoveredLinkTarget(null);
      return;
    }
    _setHoveredLinkTarget(_linkTargetAt(globalPosition));
  }

  void _setHoveredLinkTarget(TerminalLinkTarget? target) {
    final previous = _hoveredLinkTarget;
    if (previous?.uri == target?.uri &&
        (previous == null ||
            target == null ||
            (previous.globalPosition - target.globalPosition).distance < 1)) {
      return;
    }
    _hoveredLinkTarget = target;
    widget.onLinkHoverChanged?.call(target);
    if (mounted) {
      setState(() {});
    }
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
    final mappedSourceRow = viewportStartRow == null
        ? widget.controller.frame.mappedSourceRowForViewportRow(cell.row)
        : null;
    if (viewportStartRow == null && mappedSourceRow == null) {
      return;
    }
    widget.selectionController.update(
      cell,
      viewportStartRow:
          viewportStartRow ?? widget.controller.frame.viewportStartRow,
      sourceRow: mappedSourceRow,
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
    return (1 + (overshoot / lineHeight).floor()).clamp(1, 6);
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
    final nextOffset = (frame.scrollbackOffset + deltaLines).clamp(
      0,
      frame.scrollbackMaxOffset,
    );
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

  TerminalViewportColors _effectiveColorsForFrame(
    TerminalViewportColors base,
    TerminalFrameDiff frame,
  ) {
    if (!widget.useFrameDefaultColors) {
      return base;
    }
    return base.copyWith(
      canvasBackground: frame.defaultBackground,
      foreground: frame.defaultForeground,
    );
  }

  KeyEventResult _handleTerminalKeyEvent(KeyEvent event) {
    if ((event.logicalKey == LogicalKeyboardKey.tab &&
            widget.onActivateInlineButton != null &&
            widget.controller.frame.inlineButtons.isNotEmpty) ||
        (!_focusNode.hasPrimaryFocus &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space))) {
      return KeyEventResult.ignored;
    }
    if (_consumeBackspaceAfterImeClear(event)) {
      return KeyEventResult.handled;
    }
    if (_consumeTabTraversalDuringImeComposition(event)) {
      return KeyEventResult.handled;
    }
    if (!_isTerminalKeyEvent(event, widget.controller.frame.modes)) {
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
    final terminalFirst = _isTerminalFirstHostShortcut(event);
    if (!terminalFirst) {
      final hostResult = widget.onHostKeyEvent?.call(event);
      if (hostResult == KeyEventResult.handled) {
        return KeyEventResult.handled;
      }
    }
    final result = widget.inputController.handle(event);
    if (_usesMobileTextInput && result == KeyEventResult.handled) {
      final isKeyPress = event is KeyDownEvent || event is KeyRepeatEvent;
      if (isKeyPress && event.logicalKey == LogicalKeyboardKey.enter) {
        _suppressNextMobileTextAction = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _suppressNextMobileTextAction = false;
        });
      } else if (isKeyPress &&
          event.logicalKey == LogicalKeyboardKey.backspace) {
        _pendingMobileRawBackspaces += 1;
        if (!_mobileRawBackspaceResetScheduled) {
          _mobileRawBackspaceResetScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _pendingMobileRawBackspaces = 0;
            _mobileRawBackspaceResetScheduled = false;
          });
        }
      }
    }
    return result;
  }

  bool _isTerminalFirstHostShortcut(KeyEvent event) {
    return event.logicalKey == LogicalKeyboardKey.keyQ &&
        HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isShiftPressed &&
        !HardwareKeyboard.instance.isAltPressed;
  }

  bool _consumeBackspaceAfterImeClear(KeyEvent event) {
    final isBackspace = event.logicalKey == LogicalKeyboardKey.backspace;
    if (_suppressImeClearBackspaceUntilKeyUp && isBackspace) {
      if (event is KeyUpEvent) {
        _suppressImeClearBackspaceUntilKeyUp = false;
        return true;
      }
      if (event is KeyRepeatEvent) {
        return true;
      }
      if (event is KeyDownEvent) {
        _suppressImeClearBackspaceUntilKeyUp = false;
      }
    }
    if (!_suppressNextBackspaceAfterImeClear) {
      return false;
    }
    if (isBackspace) {
      _suppressNextBackspaceAfterImeClear = false;
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        _suppressImeClearBackspaceUntilKeyUp = true;
        return true;
      }
      return event is KeyUpEvent;
    }
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _suppressNextBackspaceAfterImeClear = false;
    }
    return false;
  }

  bool _consumeTabTraversalDuringImeComposition(KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.tab ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        !_hasActiveImeComposition(_textInputValue)) {
      return false;
    }
    return !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isControlPressed;
  }

  bool _shouldDeferKeyPressToSystemTextInput(KeyEvent event) {
    final connection = _textInputConnection;
    if ((defaultTargetPlatform != TargetPlatform.macOS &&
            !_usesMobileTextInput) ||
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
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        _deferredImeBackspaceHandled = true;
      }
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
        child: ConstrainedBox(
          key: const Key('terminal-composing-overlay'),
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: ClipRect(
            child: DecoratedBox(
              decoration: BoxDecoration(color: colors.canvasBackground),
              child: Text(
                text,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  fontFamily: _effectiveFont.family,
                  fontFamilyFallback: _effectiveFont.fallback,
                  fontSize: _effectiveFont.size,
                  height: _effectiveFont.lineHeight,
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

  TerminalFontConfig get _effectiveFont {
    final family = widget.controller.frame.fontFamily;
    return family == null ? widget.font : widget.font.copyWith(family: family);
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasuredCellSizeReport();
    _scheduleTextInputGeometrySync();
    final colors = _resolvedColors(context);
    final terminal = Focus(
      autofocus: true,
      focusNode: _focusNode,
      onKeyEvent: (_, event) => _handleTerminalKeyEvent(event),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _focusTerminalFromTap,
        onScaleStart: widget.onScaleUpdate == null ? null : _handleScaleStart,
        onScaleUpdate: widget.onScaleUpdate == null ? null : _handleScaleUpdate,
        onScaleEnd: widget.onScaleUpdate == null ? null : _handleScaleEnd,
        child: MouseRegion(
          cursor: _effectivePointerCursor,
          onExit: (_) {
            _lastHoverGlobalPosition = null;
            _setHoveredLinkTarget(null);
          },
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
                final effectiveColors = _effectiveColorsForFrame(colors, frame);
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final contentPadding = widget.contentPadding;
                    final trackHeight = math.max(
                      0.0,
                      constraints.maxHeight - 16,
                    );
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        color: effectiveColors.canvasBackground,
                      ),
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
                                font: _effectiveFont,
                                cursor: widget.cursor,
                                colors: effectiveColors,
                                useFrameDefaultColors:
                                    widget.useFrameDefaultColors,
                                searchMatches: widget.searchMatches,
                                activeSearchMatchIndex:
                                    widget.activeSearchMatchIndex,
                                searchHighlightStyle:
                                    widget.searchHighlightStyle ??
                                    const TerminalSearchHighlightStyle(),
                                benchmarkEventSink: widget.benchmarkEventSink,
                              ),
                            ),
                          ),
                          ..._buildInlineImageOverlays(
                            frame,
                            contentPadding,
                            effectiveColors,
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
                              effectiveColors,
                            ),
                          ..._buildInlineButtonOverlays(
                            frame,
                            contentPadding,
                            effectiveColors,
                          ),
                          ..._buildBlockOverlays(
                            frame,
                            contentPadding,
                            effectiveColors,
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
                                colors: effectiveColors,
                                onScrollToOffset: widget.onScrollToOffset,
                              ),
                            ),
                          ?_buildComposingOverlay(
                            effectiveColors,
                            viewportWidth: constraints.maxWidth,
                          ),
                          ?_buildLinkTooltipOverlay(
                            constraints: constraints,
                            colors: effectiveColors,
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
      ),
    );
    return Focus(
      onKeyEvent: (_, event) {
        if (!_isTerminalFirstHostShortcut(event)) {
          return KeyEventResult.ignored;
        }
        return widget.onHostKeyEvent?.call(event) ?? KeyEventResult.ignored;
      },
      child: terminal,
    );
  }

  Widget? _buildLinkTooltipOverlay({
    required BoxConstraints constraints,
    required TerminalViewportColors colors,
  }) {
    final target = _hoveredLinkTarget;
    if (target == null ||
        target.uri.trim().isEmpty ||
        !constraints.hasBoundedWidth ||
        !constraints.hasBoundedHeight) {
      return null;
    }
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    final localPosition = renderObject.globalToLocal(target.globalPosition);
    final tooltipText = target.hasMismatchedVisibleText
        ? 'Target: ${target.uri}\nText: ${target.visibleText!.trim()}'
        : target.uri;
    final tooltipHeight = target.hasMismatchedVisibleText ? 54.0 : 34.0;
    final maxWidth = math.min(420.0, math.max(96.0, constraints.maxWidth - 16));
    final leftLimit = math.max(8.0, constraints.maxWidth - maxWidth - 8);
    final left = (localPosition.dx + 10).clamp(8.0, leftLimit);
    final aboveTop = localPosition.dy - tooltipHeight - 2;
    final belowTop = localPosition.dy + 18;
    final rawTop = aboveTop >= 8 ? aboveTop : belowTop;
    final top = rawTop
        .clamp(8.0, math.max(8.0, constraints.maxHeight - tooltipHeight))
        .toDouble();
    final background = colors.foreground.withValues(alpha: 0.94);
    final foreground = colors.canvasBackground;
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Semantics(
          container: true,
          label: target.hasMismatchedVisibleText
              ? 'Terminal link target: ${target.uri}. Visible text: ${target.visibleText!.trim()}'
              : 'Terminal link target: ${target.uri}',
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: DecoratedBox(
              key: terminalLinkTooltipKey,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: colors.canvasBackground.withValues(alpha: 0.34),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Text(
                  tooltipText,
                  maxLines: target.hasMismatchedVisibleText ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontFamily: _effectiveFont.family,
                    fontFamilyFallback: _effectiveFont.fallback,
                    fontSize: math.max(11, _effectiveFont.size * 0.82),
                    height: 1.1,
                  ),
                ),
              ),
            ),
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
        ?_buildInlineImageOverlay(
          frame,
          contentPadding,
          colors,
          cellSize,
          image,
        ),
    ];
  }

  Widget? _buildInlineImageOverlay(
    TerminalFrameDiff frame,
    EdgeInsets contentPadding,
    TerminalViewportColors colors,
    Size cellSize,
    TerminalInlineImage image,
  ) {
    if (image.row < 0 ||
        image.row >= frame.viewportRows ||
        image.col < 0 ||
        image.col >= frame.viewportCols ||
        image.widthCells <= 0 ||
        image.heightCells <= 0) {
      return null;
    }
    final visibleCols = frame.viewportCols - image.col;
    final visibleRows = frame.viewportRows - image.row;
    if (visibleCols <= 0 || visibleRows <= 0) {
      return null;
    }
    final fullWidth = image.widthCells * cellSize.width;
    final fullHeight = image.heightCells * cellSize.height;
    final visibleWidth = math.min(fullWidth, visibleCols * cellSize.width);
    final visibleHeight = math.min(fullHeight, visibleRows * cellSize.height);
    if (visibleWidth <= 0 || visibleHeight <= 0) {
      return null;
    }
    return Positioned(
      left: contentPadding.left + image.col * cellSize.width,
      top: contentPadding.top + image.row * cellSize.height,
      width: visibleWidth,
      height: visibleHeight,
      child: IgnorePointer(
        key: Key('terminal-inline-image-${image.row}-${image.col}'),
        child: ClipRect(
          child: SizedBox(
            width: visibleWidth,
            height: visibleHeight,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: fullWidth,
              maxWidth: fullWidth,
              minHeight: fullHeight,
              maxHeight: fullHeight,
              child: Image.memory(
                image.bytes,
                width: fullWidth,
                height: fullHeight,
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
        ),
      ),
    );
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
    ).clamp(1.0, double.infinity);
    final placements = graphics
        .where((graphic) {
          return belowText ? graphic.zIndex < 0 : graphic.zIndex >= 0;
        })
        .toList(growable: false);
    if (placements.isEmpty) {
      return const <Widget>[];
    }
    final visiblePlacements = <TerminalGraphicPlacement>[
      for (final graphic in placements)
        if (_graphicPlacementVisible(frame, graphic)) graphic,
    ];
    if (visiblePlacements.isEmpty) {
      return const <Widget>[];
    }
    final renderIdCounts = <int, int>{};
    for (final graphic in visiblePlacements) {
      renderIdCounts.update(
        graphic.renderId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final renderIdOccurrences = <int, int>{};
    return [
      for (var slot = 0; slot < visiblePlacements.length; slot += 1)
        _buildGraphicOverlay(
          visiblePlacements[slot],
          contentPadding,
          cellSize,
          devicePixelRatio,
          belowText: belowText,
          slot: slot,
          renderIdCounts: renderIdCounts,
          renderIdOccurrences: renderIdOccurrences,
          graphicsCache: graphicsCache,
        ),
    ];
  }

  Widget _buildGraphicOverlay(
    TerminalGraphicPlacement graphic,
    EdgeInsets contentPadding,
    Size cellSize,
    double devicePixelRatio, {
    required bool belowText,
    required int slot,
    required Map<int, int> renderIdCounts,
    required Map<int, int> renderIdOccurrences,
    required TerminalGraphicsCache graphicsCache,
  }) {
    return Positioned(
      left:
          contentPadding.left +
          graphic.col * cellSize.width +
          graphic.xOffsetPx / devicePixelRatio,
      top:
          contentPadding.top +
          graphic.row * cellSize.height +
          graphic.yOffsetPx / devicePixelRatio,
      width: graphic.visibleWidthPx / devicePixelRatio,
      height: graphic.visibleHeightPx / devicePixelRatio,
      child: IgnorePointer(
        child: _TerminalGraphicOverlay(
          key: _terminalGraphicOverlayStateKey(
            belowText: belowText,
            slot: slot,
          ),
          overlayKey: _terminalGraphicOverlayKey(
            graphic,
            renderIdCounts: renderIdCounts,
            renderIdOccurrences: renderIdOccurrences,
          ),
          cache: graphicsCache,
          placement: graphic,
          displayWidth: graphic.widthPx / devicePixelRatio,
          displayHeight: graphic.heightPx / devicePixelRatio,
          sourceXOffset: graphic.sourceXOffsetPx / devicePixelRatio,
          sourceYOffset: graphic.sourceYOffsetPx / devicePixelRatio,
          diagnosticSessionId: widget.graphicsDiagnosticSessionId,
          diagnosticEventSink: widget.benchmarkEventSink,
        ),
      ),
    );
  }

  bool _graphicPlacementVisible(
    TerminalFrameDiff frame,
    TerminalGraphicPlacement graphic,
  ) {
    return graphic.row >= 0 &&
        graphic.row < frame.viewportRows &&
        graphic.col >= 0 &&
        graphic.widthCells > 0 &&
        graphic.heightCells > 0;
  }

  Key _terminalGraphicOverlayKey(
    TerminalGraphicPlacement graphic, {
    required Map<int, int> renderIdCounts,
    required Map<int, int> renderIdOccurrences,
  }) {
    if ((renderIdCounts[graphic.renderId] ?? 0) <= 1) {
      return Key('terminal-graphic-${graphic.renderId}');
    }
    final occurrence = renderIdOccurrences.update(
      graphic.renderId,
      (value) => value + 1,
      ifAbsent: () => 0,
    );
    return Key(
      'terminal-graphic-${graphic.renderId}-'
      '${graphic.sourceXOffsetPx}-${graphic.sourceYOffsetPx}-$occurrence',
    );
  }

  Key _terminalGraphicOverlayStateKey({
    required bool belowText,
    required int slot,
  }) {
    return Key('terminal-graphic-state-${belowText ? 'below' : 'above'}-$slot');
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
      fontFamily: _effectiveFont.family,
      fontFamilyFallback: _effectiveFont.fallback,
      fontSize: math.max(9.0, math.min(11.0, _effectiveFont.size * 0.72)),
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

  List<Widget> _buildBlockOverlays(
    TerminalFrameDiff frame,
    EdgeInsets contentPadding,
    TerminalViewportColors colors,
  ) {
    final onToggleBlock = widget.onToggleBlock;
    final onDismissBlockRender = widget.onDismissBlockRender;
    if ((onToggleBlock == null && onDismissBlockRender == null) ||
        frame.blocks.isEmpty) {
      return const <Widget>[];
    }
    final cellSize =
        widget.controller.measuredCellSize ?? terminalFallbackCellSize;
    if (cellSize.height <= 0) {
      return const <Widget>[];
    }
    final buttonSize = math.max(28.0, math.min(36.0, cellSize.height * 1.8));
    final rightInset =
        contentPadding.right + (frame.scrollbackMaxOffset > 0 ? 20.0 : 4.0);
    return [
      for (final block in frame.blocks)
        if (block.startRow >= 0 &&
            block.startRow < frame.viewportRows &&
            ((onToggleBlock != null && block.canFold) ||
                (onDismissBlockRender != null &&
                    block.rendered &&
                    !block.folded)))
          Positioned(
            top:
                contentPadding.top +
                block.startRow * cellSize.height -
                (buttonSize - cellSize.height) / 2,
            right: rightInset,
            width: block.rendered && !block.folded
                ? math.max(
                    buttonSize,
                    math.min(
                      220.0,
                      frame.viewportCols * cellSize.width -
                          contentPadding.horizontal -
                          rightInset,
                    ),
                  )
                : buttonSize,
            height: buttonSize,
            child: Listener(
              onPointerDown: (_) => _blockTogglePointerActive = true,
              onPointerUp: (_) => _blockTogglePointerActive = false,
              onPointerCancel: (_) => _blockTogglePointerActive = false,
              child: block.rendered && !block.folded
                  ? _buildRenderedBlockControls(
                      frame,
                      block,
                      colors,
                      buttonSize,
                      onToggleBlock: onToggleBlock,
                      onDismissBlockRender: onDismissBlockRender,
                    )
                  : _buildFoldBlockControl(
                      block,
                      colors,
                      buttonSize,
                      onToggleBlock!,
                    ),
            ),
          ),
    ];
  }

  List<Widget> _buildInlineButtonOverlays(
    TerminalFrameDiff frame,
    EdgeInsets contentPadding,
    TerminalViewportColors colors,
  ) {
    final onActivate = widget.onActivateInlineButton;
    if (onActivate == null || frame.inlineButtons.isEmpty) {
      return const <Widget>[];
    }
    final cellSize =
        widget.controller.measuredCellSize ?? terminalFallbackCellSize;
    if (cellSize.width <= 0 || cellSize.height <= 0) {
      return const <Widget>[];
    }
    final controlHeight = math.max(
      22.0,
      math.min(28.0, cellSize.height * 1.35),
    );
    return [
      for (final button in frame.inlineButtons)
        if (button.row >= 0 &&
            button.row < frame.viewportRows &&
            button.col >= 0 &&
            button.col + button.widthCells <= frame.viewportCols)
          Positioned(
            top:
                contentPadding.top +
                button.row * cellSize.height -
                (controlHeight - cellSize.height) / 2,
            left: contentPadding.left + button.col * cellSize.width,
            width: button.widthCells * cellSize.width,
            height: controlHeight,
            child: Listener(
              onPointerDown: (_) => _blockTogglePointerActive = true,
              onPointerUp: (_) => _blockTogglePointerActive = false,
              onPointerCancel: (_) => _blockTogglePointerActive = false,
              child: _buildInlineButton(button, colors, onActivate),
            ),
          ),
    ];
  }

  Widget _buildInlineButton(
    TerminalInlineButton button,
    TerminalViewportColors colors,
    ValueChanged<TerminalInlineButton> onActivate,
  ) {
    final isCopy = button.kind == TerminalInlineButtonKind.copy;
    final enabled =
        button.valid && (widget.inlineButtonEnabled?.call(button) ?? true);
    final label = isCopy
        ? 'Copy terminal block ${button.blockId}'
        : 'Activate terminal button ${button.code}';
    final tooltip = enabled ? label : '$label (disabled)';
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        excludeSemantics: true,
        label: tooltip,
        onTap: enabled ? () => onActivate(button) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: IconButton(
            key: terminalInlineButtonKey(button.id),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              foregroundColor: colors.foreground,
              disabledForegroundColor: colors.foreground,
              backgroundColor: colors.canvasBackground.withValues(alpha: 0.9),
              disabledBackgroundColor: colors.canvasBackground.withValues(
                alpha: 0.9,
              ),
              side: BorderSide(
                color: colors.foreground.withValues(alpha: 0.24),
              ),
            ),
            iconSize: math.min(18.0, cellSizeForInlineButtonIcon(button)),
            tooltip: null,
            icon: Icon(
              isCopy ? Icons.copy_rounded : _iconForSfSymbol(button.icon),
            ),
            onPressed: enabled ? () => onActivate(button) : null,
          ),
        ),
      ),
    );
  }

  double cellSizeForInlineButtonIcon(TerminalInlineButton button) {
    final cellSize =
        widget.controller.measuredCellSize ?? terminalFallbackCellSize;
    return math.max(14.0, math.min(18.0, cellSize.height * 0.82));
  }

  IconData _iconForSfSymbol(String? symbol) {
    return switch (symbol) {
      'star' || 'star.fill' => Icons.star_rounded,
      'checkmark' ||
      'checkmark.circle' ||
      'checkmark.circle.fill' => Icons.check_circle_rounded,
      'play' ||
      'play.fill' ||
      'play.circle' ||
      'play.circle.fill' => Icons.play_arrow_rounded,
      'stop' ||
      'stop.fill' ||
      'stop.circle' ||
      'stop.circle.fill' => Icons.stop_rounded,
      'arrow.clockwise' => Icons.refresh_rounded,
      'xmark' || 'xmark.circle' || 'xmark.circle.fill' => Icons.close_rounded,
      _ => Icons.smart_button_outlined,
    };
  }

  Widget _buildFoldBlockControl(
    TerminalBlock block,
    TerminalViewportColors colors,
    double buttonSize,
    ValueChanged<TerminalBlock> onToggleBlock,
  ) {
    final label = block.folded
        ? 'Unfold terminal block'
        : 'Fold terminal block';
    return Tooltip(
      message: block.folded ? 'Unfold block' : 'Fold block',
      child: Semantics(
        button: true,
        excludeSemantics: true,
        label: label,
        onTap: () => onToggleBlock(block),
        child: IconButton(
          key: terminalBlockToggleKey(block.id),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            foregroundColor: colors.foreground,
            backgroundColor: colors.canvasBackground.withValues(alpha: 0.88),
          ),
          iconSize: math.min(20.0, buttonSize * 0.64),
          icon: Icon(
            block.folded
                ? Icons.chevron_right_rounded
                : Icons.expand_more_rounded,
          ),
          onPressed: () => onToggleBlock(block),
        ),
      ),
    );
  }

  Widget _buildRenderedBlockControls(
    TerminalFrameDiff frame,
    TerminalBlock block,
    TerminalViewportColors colors,
    double buttonSize, {
    required ValueChanged<TerminalBlock>? onToggleBlock,
    required ValueChanged<TerminalBlock>? onDismissBlockRender,
  }) {
    final visibleLines = <String>[
      for (final row in frame.rows)
        if (row.index >= block.startRow && row.index <= block.endRow) row.text,
    ];
    final kind = TerminalTextDocumentStyler.kindFor(
      type: block.blockType,
      visibleLines: visibleLines,
    );
    final documentLabel = TerminalTextDocumentStyler.displayLabel(
      block.blockType,
      kind,
    );
    final background = Color.alphaBlend(
      colors.cursor.withValues(alpha: 0.12),
      colors.canvasBackground,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final showFold =
            onToggleBlock != null &&
            block.canFold &&
            (onDismissBlockRender == null ||
                constraints.maxWidth >= buttonSize * 2);
        final actionWidth =
            (showFold ? buttonSize : 0) +
            (onDismissBlockRender != null ? buttonSize : 0);
        final showLabel = constraints.maxWidth >= actionWidth + 48;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: background.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.cursor.withValues(alpha: 0.36)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showLabel)
                Expanded(
                  child: Semantics(
                    label: 'Rendered terminal document: $documentLabel',
                    excludeSemantics: true,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8, right: 4),
                      child: Text(
                        documentLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.foreground.withValues(alpha: 0.82),
                          fontSize: math.max(10, buttonSize * 0.34),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              if (showFold)
                SizedBox(
                  width: buttonSize,
                  height: buttonSize,
                  child: _buildFoldBlockControl(
                    block,
                    colors,
                    buttonSize,
                    onToggleBlock,
                  ),
                ),
              if (onDismissBlockRender != null)
                SizedBox(
                  width: buttonSize,
                  height: buttonSize,
                  child: Tooltip(
                    message: 'Close rendered document',
                    child: Semantics(
                      button: true,
                      excludeSemantics: true,
                      label: 'Close terminal text document',
                      onTap: () => onDismissBlockRender(block),
                      child: IconButton(
                        key: terminalBlockRenderCloseKey(block.id),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        color: colors.foreground,
                        iconSize: math.min(18.0, buttonSize * 0.58),
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => onDismissBlockRender(block),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  TextEditingValue? get currentTextEditingValue => _textInputValue;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    var resolvedValue = value;
    final submittedMobileText = _submittedMobileTextPendingReset;
    if (_usesMobileTextInput && submittedMobileText != null) {
      if (value.text == submittedMobileText) {
        final connection = _textInputConnection;
        if (connection != null && connection.attached) {
          connection.setEditingState(TextEditingValue.empty);
        }
        return;
      }
      _submittedMobileTextPendingReset = null;
      if (submittedMobileText.isNotEmpty &&
          value.text.startsWith(submittedMobileText)) {
        final text = value.text.substring(submittedMobileText.length);
        resolvedValue = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    }
    final previousValue = _textInputValue;
    final hadActiveComposition = _hasActiveImeComposition(previousValue);
    final hasActiveComposition = _hasActiveImeComposition(resolvedValue);
    final clearedActiveComposition =
        hadActiveComposition &&
        !hasActiveComposition &&
        previousValue.text.isNotEmpty &&
        resolvedValue.text.isEmpty;
    final shouldSuppressBackspaceAfterImeClear =
        clearedActiveComposition && !_deferredImeBackspaceHandled;
    _updateTextInputState(() {
      _textInputValue = resolvedValue;
      if (hasActiveComposition) {
        _hadImeComposition = true;
        _deferredImeBackspaceHandled = false;
        _suppressNextBackspaceAfterImeClear = false;
        _suppressImeClearBackspaceUntilKeyUp = false;
      }
    });
    if (hasActiveComposition) {
      _scheduleTextInputGeometrySync();
      return;
    }
    if (_usesMobileTextInput && !hadActiveComposition) {
      final change = _editingReplacementBetween(
        previousValue.text,
        resolvedValue.text,
      );
      _sendMobileBackspaces(change.removedRuneCount);
    }
    final text = _committedTextFromEditingValue(
      resolvedValue,
      previousValue: previousValue,
      hadActiveComposition: hadActiveComposition,
    );
    if (text.isNotEmpty &&
        !_isHandledKeyboardControlCommit(text) &&
        _shouldForwardCommittedText(text)) {
      widget.inputController.sendText(text);
    }
    if (_usesMobileTextInput) {
      _resetCommittedTextTracking();
    } else {
      _clearTextInputState();
    }
    if (shouldSuppressBackspaceAfterImeClear) {
      _suppressNextBackspaceAfterImeClear = true;
    }
  }

  String _committedTextFromEditingValue(
    TextEditingValue value, {
    required TextEditingValue previousValue,
    required bool hadActiveComposition,
  }) {
    final text = value.text;
    if (!hadActiveComposition || text.isEmpty) {
      if (_usesMobileTextInput && previousValue.text.isNotEmpty) {
        return _editingReplacementBetween(
          previousValue.text,
          text,
        ).insertedText;
      }
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

    final replacement = _editingReplacementBetween(
      previousText,
      text,
    ).insertedText;
    if (replacement.isNotEmpty || text != previousText) {
      return replacement;
    }

    if (previousComposingText != null && previousComposingText.isNotEmpty) {
      return previousComposingText;
    }
    return text;
  }

  ({String insertedText, int removedRuneCount}) _editingReplacementBetween(
    String previousText,
    String text,
  ) {
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

    return (
      insertedText: String.fromCharCodes(
        textRunes.sublist(prefixLength, textSuffix),
      ),
      removedRuneCount: previousSuffix - prefixLength,
    );
  }

  void _sendMobileBackspaces(int count) {
    if (count <= 0) {
      return;
    }
    final suppressed = math.min(count, _pendingMobileRawBackspaces);
    _pendingMobileRawBackspaces -= suppressed;
    final remaining = count - suppressed;
    if (remaining == 0) {
      return;
    }
    widget.inputController.sendText(
      String.fromCharCodes(List<int>.filled(remaining, 0x7f)),
    );
  }

  void _resetCommittedTextTracking() {
    _hadImeComposition = false;
    _awaitingSystemTextCommit = false;
    _deferredImeRawText = '';
    _deferredImeBackspaceHandled = false;
    _suppressNextBackspaceAfterImeClear = false;
    _suppressImeClearBackspaceUntilKeyUp = false;
  }

  @override
  void performAction(TextInputAction action) {
    if (!_usesMobileTextInput ||
        _suppressNextMobileTextAction ||
        _submittedMobileTextPendingReset != null ||
        action != TextInputAction.newline) {
      return;
    }
    final submittedText = _textInputValue.text;
    widget.inputController.sendText('\r');
    _clearTextInputState();
    if (submittedText.isNotEmpty) {
      _submittedMobileTextPendingReset = submittedText;
    }
  }

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
    return _usesMobileTextInput ||
        _hadImeComposition ||
        _awaitingSystemTextCommit ||
        _containsNonAscii(text) ||
        text.runes.length > 1;
  }

  bool get _usesMobileTextInput => defaultTargetPlatform == TargetPlatform.iOS;

  bool _isHandledKeyboardControlCommit(String text) {
    return text.runes.every(
      (codePoint) =>
          codePoint == 0x09 || codePoint == 0x0a || codePoint == 0x0d,
    );
  }

  bool _isPrintableAscii(String text) {
    return text.isNotEmpty &&
        text.runes.every((codePoint) => codePoint >= 0x20 && codePoint <= 0x7e);
  }

  bool _containsNonAscii(String text) {
    return text.runes.any((codePoint) => codePoint > 0x7f);
  }
}

bool _isTerminalKeyEvent(KeyEvent event, TerminalFrameModes modes) {
  if (event is KeyDownEvent || event is KeyRepeatEvent) {
    return true;
  }
  if (event is! KeyUpEvent) {
    return false;
  }
  const kittyKeyboardDisambiguateFlag = 1;
  const kittyKeyboardReportEventsFlag = 2;
  const kittyKeyboardReportAllKeysFlag = 8;
  final flags = modes.kittyKeyboardFlags;
  if ((flags & kittyKeyboardReportEventsFlag) == 0) {
    return false;
  }
  return (flags & kittyKeyboardReportAllKeysFlag) != 0 ||
      (flags & kittyKeyboardDisambiguateFlag) != 0;
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
  final mappedStartRow = frame.mappedSourceRowForViewportRow(relativeRow);
  final mappedEndRow = frame.mappedSourceEndRowForViewportRow(relativeRow);
  if (mappedStartRow == null || mappedEndRow == null) {
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

  var startRow = mappedStartRow;
  var startCol = cell.column;
  var endRow = mappedEndRow;
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
      final startRow = frame.mappedSourceRowForViewportRow(relativeRow);
      final endRow = frame.mappedSourceEndRowForViewportRow(relativeRow);
      if (startRow == null || endRow == null) {
        return null;
      }
      return _TerminalWordRange(
        startRow: startRow,
        startCol: rowCells.columnForCodeUnit(range.start),
        endRow: endRow,
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
  var index = column.clamp(0, cells.cellCount - 1);
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
    var index = math.min(column, cells.cellCount) - 1;
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
  for (var index = math.max(0, column); index < cells.cellCount; index += 1) {
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
    required this.useFrameDefaultColors,
    required this.searchMatches,
    required this.activeSearchMatchIndex,
    required this.searchHighlightStyle,
    this.benchmarkEventSink,
  });

  final TerminalViewportController controller;
  final SelectionController selectionController;
  final bool cursorVisible;
  final TerminalFontConfig font;
  final TerminalCursorConfig cursor;
  final TerminalViewportColors colors;
  final bool useFrameDefaultColors;
  final List<TerminalSearchMatch> searchMatches;
  final int activeSearchMatchIndex;
  final TerminalSearchHighlightStyle searchHighlightStyle;
  final TerminalBenchmarkEventSink? benchmarkEventSink;

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
      useFrameDefaultColors: useFrameDefaultColors,
      searchMatches: searchMatches,
      activeSearchMatchIndex: activeSearchMatchIndex,
      searchHighlightStyle: searchHighlightStyle,
      benchmarkEventSink: benchmarkEventSink,
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
      ..useFrameDefaultColors = useFrameDefaultColors
      ..searchMatches = searchMatches
      ..activeSearchMatchIndex = activeSearchMatchIndex
      ..searchHighlightStyle = searchHighlightStyle
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..benchmarkEventSink = benchmarkEventSink;
  }
}

class _TerminalGraphicOverlay extends StatefulWidget {
  const _TerminalGraphicOverlay({
    super.key,
    required this.overlayKey,
    required this.cache,
    required this.placement,
    required this.displayWidth,
    required this.displayHeight,
    required this.sourceXOffset,
    required this.sourceYOffset,
    this.diagnosticSessionId,
    this.diagnosticEventSink,
  });

  final Key overlayKey;
  final TerminalGraphicsCache cache;
  final TerminalGraphicPlacement placement;
  final double displayWidth;
  final double displayHeight;
  final double sourceXOffset;
  final double sourceYOffset;
  final String? diagnosticSessionId;
  final TerminalBenchmarkEventSink? diagnosticEventSink;

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
      _clearVisibleImage(reason: 'cache_changed');
    }
    if (oldWidget.cache != widget.cache ||
        oldWidget.placement.assetKey != widget.placement.assetKey) {
      _syncImageFuture();
    }
  }

  @override
  void dispose() {
    _clearVisibleImage(reason: 'dispose');
    super.dispose();
  }

  void _syncImageFuture() {
    final assetKey = widget.placement.assetKey;
    final previousAssetKey = _assetKey;
    final hasVisibleImage = _visibleImage != null;
    _assetKey = assetKey;
    final future = widget.cache.imageFor(assetKey);
    _imageFuture = future;
    _emitDiagnostic(
      hasVisibleImage ? 'overlay_waiting_for_replacement' : 'overlay_waiting',
      assetKey: assetKey,
      fields: <String, Object?>{
        'has_visible_image': hasVisibleImage,
        if (previousAssetKey != null)
          'previous_asset_key': terminalGraphicsAssetKeyJson(previousAssetKey),
      },
    );
    unawaited(
      future.then(
        (image) {
          if (!mounted) {
            return;
          }
          if (_assetKey != assetKey) {
            _emitDiagnostic('overlay_stale_load', assetKey: assetKey);
            return;
          }
          if (image == null) {
            _emitDiagnostic('overlay_load_null', assetKey: assetKey);
            return;
          }
          setState(() {
            _replaceVisibleImage(image.clone());
          });
          _emitDiagnostic('overlay_visible', assetKey: assetKey);
        },
        onError: (Object error, StackTrace stackTrace) {
          // Keep the previous frame visible if a replacement image fails to load.
          _emitDiagnostic(
            'overlay_load_error',
            assetKey: assetKey,
            fields: <String, Object?>{'error': error.toString()},
          );
        },
      ),
    );
  }

  void _replaceVisibleImage(ui.Image image) {
    final previous = _visibleImage;
    _visibleImage = image;
    previous?.dispose();
  }

  void _clearVisibleImage({required String reason}) {
    if (_visibleImage != null) {
      _emitDiagnostic(
        'overlay_clear',
        assetKey: _assetKey,
        fields: <String, Object?>{'reason': reason},
      );
    }
    _visibleImage?.dispose();
    _visibleImage = null;
  }

  void _emitDiagnostic(
    String event, {
    TerminalGraphicAssetKey? assetKey,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    emitTerminalGraphicsDiagnostic(
      widget.diagnosticEventSink,
      layer: 'viewport_overlay',
      event: event,
      sessionId: widget.diagnosticSessionId,
      assetKey: assetKey ?? widget.placement.assetKey,
      graphics: <TerminalGraphicPlacement>[widget.placement],
      fields: <String, Object?>{
        'render_id': widget.placement.renderId,
        'placement_id': widget.placement.placementId,
        'row': widget.placement.row,
        'col': widget.placement.col,
        ...fields,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final image = _visibleImage;
    if (image == null || _imageFuture == null) {
      return KeyedSubtree(
        key: widget.overlayKey,
        child: const SizedBox.shrink(),
      );
    }
    return KeyedSubtree(
      key: widget.overlayKey,
      child: ClipRect(
        child: Transform.translate(
          offset: Offset(-widget.sourceXOffset, -widget.sourceYOffset),
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: widget.displayWidth,
            maxWidth: widget.displayWidth,
            minHeight: widget.displayHeight,
            maxHeight: widget.displayHeight,
            child: SizedBox(
              width: widget.displayWidth,
              height: widget.displayHeight,
              child: RawImage(
                image: image,
                fit: widget.placement.preserveAspectRatio
                    ? BoxFit.contain
                    : BoxFit.fill,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        ),
      ),
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
    return proportionalHeight.clamp(minThumbHeight, widget.trackHeight);
  }

  double get _thumbTravelExtent =>
      math.max(0.0, widget.trackHeight - _thumbHeight);

  double get _thumbTop {
    if (widget.scrollbackMaxOffset <= 0 || _thumbTravelExtent == 0) {
      return _thumbTravelExtent;
    }
    final progress =
        1.0 - (widget.scrollbackOffset / widget.scrollbackMaxOffset);
    return _thumbTravelExtent * progress.clamp(0.0, 1.0);
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
            .clamp(0.0, _thumbTravelExtent);
    final nextProgress = nextThumbTop / _thumbTravelExtent;
    final nextOffset = ((1 - nextProgress) * widget.scrollbackMaxOffset)
        .round()
        .clamp(0, widget.scrollbackMaxOffset);
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
