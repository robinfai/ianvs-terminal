import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../config/terminal_config.dart';
import '../config/terminal_defaults.dart';
import '../runtime/terminal_runtime_controller.dart';
import '../terminal/terminal_input_controller.dart';
import '../terminal/terminal_models.dart';
import '../terminal/terminal_viewport.dart';

const Duration _terminalDisposeRetryInterval = Duration(milliseconds: 50);

abstract interface class TerminalDisposable {
  void dispose();
}

abstract interface class TerminalAddon implements TerminalDisposable {
  void activate(Terminal terminal);
}

enum TerminalCursorStyle { block, underline, bar }

class TerminalOptions {
  const TerminalOptions({
    int cols = defaultTerminalColumns,
    int rows = defaultTerminalRows,
    int scrollback = defaultTerminalScrollbackLines,
    this.fontFamily = terminalPrimaryFontFamily,
    this.fontFamilyFallback = terminalFontFamilyFallback,
    double fontSize = terminalFontSize,
    double lineHeight = terminalLineHeight,
    this.cursorBlink = true,
    this.cursorStyle = TerminalCursorStyle.block,
    this.theme = const TerminalColorPalette(),
    this.copyOnSelect = false,
    this.optionDragMode = TerminalOptionDragMode.blockSelection,
    this.emulation = TerminalEmulation.xterm256,
  }) : cols = cols <= 0
           ? defaultTerminalColumns
           : cols > maxTerminalDimension
           ? maxTerminalDimension
           : cols,
       rows = rows <= 0
           ? defaultTerminalRows
           : rows > maxTerminalDimension
           ? maxTerminalDimension
           : rows,
       scrollback = scrollback < 1
           ? defaultTerminalScrollbackLines
           : scrollback > maxTerminalScrollbackLines
           ? maxTerminalScrollbackLines
           : scrollback,
       fontSize = fontSize > 0 && fontSize < double.infinity
           ? fontSize
           : terminalFontSize,
       lineHeight = lineHeight > 0 && lineHeight < double.infinity
           ? lineHeight
           : terminalLineHeight;

  final int cols;
  final int rows;
  final int scrollback;
  final String fontFamily;
  final List<String> fontFamilyFallback;
  final double fontSize;
  final double lineHeight;
  final bool cursorBlink;
  final TerminalCursorStyle cursorStyle;
  final TerminalColorPalette theme;
  final bool copyOnSelect;
  final TerminalOptionDragMode optionDragMode;
  final TerminalEmulation emulation;

  TerminalOptions copyWith({
    int? cols,
    int? rows,
    int? scrollback,
    String? fontFamily,
    List<String>? fontFamilyFallback,
    double? fontSize,
    double? lineHeight,
    bool? cursorBlink,
    TerminalCursorStyle? cursorStyle,
    TerminalColorPalette? theme,
    bool? copyOnSelect,
    TerminalOptionDragMode? optionDragMode,
    TerminalEmulation? emulation,
  }) {
    return TerminalOptions(
      cols: cols ?? this.cols,
      rows: rows ?? this.rows,
      scrollback: scrollback ?? this.scrollback,
      fontFamily: fontFamily ?? this.fontFamily,
      fontFamilyFallback: fontFamilyFallback ?? this.fontFamilyFallback,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      cursorBlink: cursorBlink ?? this.cursorBlink,
      cursorStyle: cursorStyle ?? this.cursorStyle,
      theme: theme ?? this.theme,
      copyOnSelect: copyOnSelect ?? this.copyOnSelect,
      optionDragMode: optionDragMode ?? this.optionDragMode,
      emulation: emulation ?? this.emulation,
    );
  }

  TerminalSessionConfig applyTo(TerminalSessionConfig config) {
    return config.copyWith(
      emulation: emulation,
      scrollbackLines: scrollback,
      display: config.display.copyWith(
        font: config.display.font.copyWith(
          family: fontFamily,
          fallback: fontFamilyFallback,
          size: fontSize,
          lineHeight: lineHeight,
        ),
        colors: theme,
        cursor: config.display.cursor.copyWith(
          shape: _cursorShapeFor(cursorStyle),
          blink: cursorBlink,
        ),
      ),
      interaction: config.interaction.copyWith(
        copyOnSelect: copyOnSelect,
        optionDragMode: optionDragMode,
      ),
    );
  }
}

class TerminalRenderEvent {
  const TerminalRenderEvent({required this.start, required this.end});

  final int start;
  final int end;
}

class TerminalResizeEvent {
  const TerminalResizeEvent({required this.cols, required this.rows});

  final int cols;
  final int rows;
}

class TerminalExitEvent {
  const TerminalExitEvent({this.exitCode});

  final int? exitCode;
}

class TerminalInputEvent {
  const TerminalInputEvent({required this.data, required this.bytes});

  final String data;
  final Uint8List bytes;
}

class Terminal implements TerminalDisposable {
  Terminal({
    required TerminalRuntimeController runtime,
    required TerminalSessionConfig sessionConfig,
    TerminalOptions options = const TerminalOptions(),
    bool disposeRuntime = false,
  }) : _runtime = runtime,
       _sessionConfig = sessionConfig,
       _options = options,
       _disposeRuntime = disposeRuntime;

  final TerminalRuntimeController _runtime;
  final TerminalSessionConfig _sessionConfig;
  final bool _disposeRuntime;
  final List<TerminalAddon> _addons = <TerminalAddon>[];
  final StreamController<String> _dataEvents =
      StreamController<String>.broadcast();
  final StreamController<TerminalInputEvent> _inputEvents =
      StreamController<TerminalInputEvent>.broadcast();
  final StreamController<TerminalRenderEvent> _renderEvents =
      StreamController<TerminalRenderEvent>.broadcast();
  final StreamController<TerminalResizeEvent> _resizeEvents =
      StreamController<TerminalResizeEvent>.broadcast();
  final StreamController<int> _scrollEvents = StreamController<int>.broadcast();
  final StreamController<void> _selectionChangeEvents =
      StreamController<void>.broadcast();
  final StreamController<String> _titleChangeEvents =
      StreamController<String>.broadcast();
  final StreamController<TerminalExitEvent> _exitEvents =
      StreamController<TerminalExitEvent>.broadcast();

  StreamSubscription<TerminalSessionEvent>? _runtimeEventsSubscription;
  StreamSubscription<TerminalSessionZmodemEvent>? _runtimeZmodemSubscription;
  StreamSubscription<TerminalSessionInputEvent>? _runtimeInputSubscription;
  StreamSubscription<TerminalSessionResizeEvent>? _runtimeResizeSubscription;
  TerminalOptions _options;
  String? _sessionId;
  String? _lastWindowTitle;
  TerminalSelection? _lastSelection;
  int? _lastScrollbackOffset;
  int? _currentCols;
  int? _currentRows;
  bool _disposeRequested = false;
  bool _disposeRetryScheduled = false;
  Timer? _disposeRetryTimer;
  bool _disposed = false;

  String? get sessionId => _sessionId;
  bool get isOpen => _sessionId != null;
  bool get disposed => _disposed;

  TerminalOptions get options => _options;
  set options(TerminalOptions value) {
    _ensureNotDisposed();
    _options = value;
  }

  int get cols {
    final frameCols = _currentCols ?? _currentFrame.viewportCols;
    return frameCols > 0 ? frameCols : _options.cols;
  }

  int get rows {
    final frameRows = _currentRows ?? _currentFrame.viewportRows;
    return frameRows > 0 ? frameRows : _options.rows;
  }

  TerminalFrameModes get modes => _currentFrame.modes;
  TerminalFrameDiff get frame => _currentFrame;

  TerminalViewportController get viewportController {
    return _runtime.viewportFor(_requireSessionId());
  }

  TerminalDisposable onData(void Function(String data) listener) {
    return _listen(_dataEvents.stream, listener);
  }

  TerminalDisposable onInput(void Function(TerminalInputEvent event) listener) {
    return _listen(_inputEvents.stream, listener);
  }

  TerminalDisposable onRender(
    void Function(TerminalRenderEvent event) listener,
  ) {
    return _listen(_renderEvents.stream, listener);
  }

  TerminalDisposable onResize(
    void Function(TerminalResizeEvent event) listener,
  ) {
    return _listen(_resizeEvents.stream, listener);
  }

  TerminalDisposable onScroll(void Function(int offset) listener) {
    return _listen(_scrollEvents.stream, listener);
  }

  TerminalDisposable onSelectionChange(void Function() listener) {
    return TerminalStreamSubscriptionDisposable(
      _selectionChangeEvents.stream.listen((_) {
        listener();
      }),
    );
  }

  TerminalDisposable onTitleChange(void Function(String title) listener) {
    return _listen(_titleChangeEvents.stream, listener);
  }

  TerminalDisposable onExit(void Function(TerminalExitEvent event) listener) {
    return _listen(_exitEvents.stream, listener);
  }

  void open() {
    _ensureNotDisposed();
    if (_sessionId != null) {
      return;
    }
    _runtimeEventsSubscription ??= _runtime.events.listen(_handleRuntimeEvent);
    _runtimeZmodemSubscription ??= _runtime.zmodemEvents.listen(
      _handleRuntimeZmodemEvent,
    );
    _runtimeInputSubscription ??= _runtime.inputEvents.listen(
      _handleRuntimeInputEvent,
    );
    _runtimeResizeSubscription ??= _runtime.resizeEvents.listen(
      _handleRuntimeResizeEvent,
    );
    _sessionId = _runtime.createSession(_options.applyTo(_sessionConfig));
    resize(_options.cols, _options.rows);
  }

  void loadAddon(TerminalAddon addon) {
    _ensureNotDisposed();
    addon.activate(this);
    _addons.add(addon);
  }

  void input(String data, {bool wasUserInput = true}) {
    write(data);
  }

  void write(Object data, [void Function()? callback]) {
    final bytes = switch (data) {
      final Uint8List value => Uint8List.fromList(value),
      final List<int> value => Uint8List.fromList(value),
      final String value => Uint8List.fromList(utf8.encode(value)),
      _ => throw ArgumentError.value(
        data,
        'data',
        'Expected String, Uint8List, or List<int>.',
      ),
    };
    writeBytes(bytes);
    callback?.call();
  }

  void writeln(Object data, [void Function()? callback]) {
    final bytes = switch (data) {
      final Uint8List value => Uint8List.fromList(value),
      final List<int> value => Uint8List.fromList(value),
      final String value => Uint8List.fromList(utf8.encode(value)),
      _ => throw ArgumentError.value(
        data,
        'data',
        'Expected String, Uint8List, or List<int>.',
      ),
    };
    writeBytes(Uint8List.fromList(<int>[...bytes, 0x0d, 0x0a]));
    callback?.call();
  }

  void writeBytes(Uint8List bytes) {
    _runtime.sendInput(_requireSessionId(), bytes);
  }

  void paste(String data) {
    final bytes = TerminalInputController.clipboardPasteBytesFor(
      emulation: _options.emulation,
      modes: modes,
      text: data,
    );
    if (bytes.isEmpty) {
      return;
    }
    writeBytes(bytes);
  }

  void resize(int columns, int rows) {
    if (columns <= 0 || rows <= 0) {
      throw RangeError('Terminal dimensions must be positive.');
    }
    final boundedColumns = _normalizeTerminalDimension(
      columns,
      defaultTerminalColumns,
    );
    final boundedRows = _normalizeTerminalDimension(rows, defaultTerminalRows);
    final resized = _runtime.resizeSessionCells(
      _requireSessionId(),
      cols: boundedColumns,
      rows: boundedRows,
    );
    if (!resized) {
      return;
    }
    _currentCols = boundedColumns;
    _currentRows = boundedRows;
  }

  void scrollLines(int amount) {
    _runtime.scrollViewport(_requireSessionId(), amount);
  }

  void scrollPages(int pageCount) {
    scrollLines(pageCount * rows);
  }

  void scrollToBottom() {
    _runtime.scrollViewportTo(_requireSessionId(), 0);
  }

  void scrollToTop() {
    _runtime.scrollViewportTo(_requireSessionId(), frame.scrollbackMaxOffset);
  }

  void scrollToLine(int line) {
    _runtime.scrollViewportTo(_requireSessionId(), line);
  }

  bool setBlockFolded(String id, {required bool folded}) {
    return _runtime.setBlockFolded(_requireSessionId(), id, folded: folded);
  }

  bool setBlockRendered(String id, {required bool rendered}) {
    return _runtime.setBlockRendered(
      _requireSessionId(),
      id,
      rendered: rendered,
    );
  }

  TerminalInlineButtonActivation activateItermButton(int id) {
    return _runtime.activateItermButton(_requireSessionId(), id);
  }

  void refresh() {
    _runtime.refreshSession(_requireSessionId());
  }

  void reset() {
    write('\x1Bc');
  }

  String getSelection({bool block = false}) {
    final selection = frame.selection;
    if (selection == null) {
      return '';
    }
    return _runtime.selectionText(
          _requireSessionId(),
          selection,
          block: block,
        ) ??
        '';
  }

  bool hasSelection() => frame.selection != null;

  TerminalSelection? getSelectionPosition() => frame.selection;

  /// Preserves the original xterm-compatible void API.
  void close() {
    tryClose();
  }

  /// Attempts an immediate close without discarding the facade when native
  /// ZMODEM state must first publish an authoritative terminal result.
  bool tryClose() {
    if (_disposed) {
      return true;
    }
    final sessionId = _sessionId;
    if (sessionId == null) {
      return true;
    }
    if (!_runtime.tryCloseSession(sessionId)) {
      return false;
    }
    _sessionId = null;
    return true;
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposeRequested = true;
    _tryCompleteRequestedDispose();
  }

  void _tryCompleteRequestedDispose() {
    if (!_disposeRequested || _disposed) {
      return;
    }
    if (_runtime.shutdownHasStarted || _runtime.disposed) {
      // An externally owned runtime remains with the process-level
      // infrastructure coordinator. A facade-owned runtime must itself start
      // that same infrastructure settlement before releasing local streams.
      _sessionId = null;
      _completeLocalDispose(disposeOwnedRuntime: _disposeRuntime);
      return;
    }
    final sessionId = _sessionId;
    if (sessionId != null && !_runtime.disposeSession(sessionId)) {
      // ZMODEM publication or a terminal result may still own native state.
      // Keep the facade subscribed until the authoritative terminal event
      // arrives; that event retries shutdown without requiring the void
      // TerminalDisposable caller to retain this object and call again.
      _scheduleRequestedDisposeFallback();
      return;
    }
    _sessionId = null;
    _completeLocalDispose(disposeOwnedRuntime: _disposeRuntime);
  }

  void _completeLocalDispose({required bool disposeOwnedRuntime}) {
    if (disposeOwnedRuntime) {
      // Runtime disposal records its own pending request and completes it
      // automatically after any other busy session publishes its result.
      _runtime.dispose();
    }
    _disposeRequested = false;
    _disposeRetryScheduled = false;
    _disposeRetryTimer?.cancel();
    _disposeRetryTimer = null;
    _disposed = true;
    for (final addon in _addons.reversed.toList(growable: false)) {
      addon.dispose();
    }
    _addons.clear();
    unawaited(_runtimeEventsSubscription?.cancel());
    unawaited(_runtimeZmodemSubscription?.cancel());
    unawaited(_runtimeInputSubscription?.cancel());
    unawaited(_runtimeResizeSubscription?.cancel());
    unawaited(_dataEvents.close());
    unawaited(_inputEvents.close());
    unawaited(_renderEvents.close());
    unawaited(_resizeEvents.close());
    unawaited(_scrollEvents.close());
    unawaited(_selectionChangeEvents.close());
    unawaited(_titleChangeEvents.close());
    unawaited(_exitEvents.close());
  }

  void _handleRuntimeZmodemEvent(TerminalSessionZmodemEvent event) {
    if (event.sessionId != _sessionId || !event.isTerminal) {
      return;
    }
    _scheduleRequestedDisposeRetry();
  }

  void _scheduleRequestedDisposeRetry() {
    if (!_disposeRequested || _disposed || _disposeRetryScheduled) {
      return;
    }
    _disposeRetryTimer?.cancel();
    _disposeRetryTimer = null;
    _disposeRetryScheduled = true;
    scheduleMicrotask(() {
      _disposeRetryScheduled = false;
      _tryCompleteRequestedDispose();
    });
  }

  void _scheduleRequestedDisposeFallback() {
    if (!_disposeRequested || _disposed || _disposeRetryTimer != null) {
      return;
    }
    _disposeRetryTimer = Timer(_terminalDisposeRetryInterval, () {
      _disposeRetryTimer = null;
      _tryCompleteRequestedDispose();
    });
  }

  TerminalFrameDiff get _currentFrame {
    final sessionId = _sessionId;
    if (sessionId == null ||
        _runtime.shutdownHasStarted ||
        _runtime.disposed ||
        !_runtime.hasSession(sessionId)) {
      return TerminalFrameDiff.empty;
    }
    return _runtime.viewportFor(sessionId).frame;
  }

  String _requireSessionId() {
    _ensureNotDisposed();
    final sessionId = _sessionId;
    if (sessionId == null) {
      throw StateError('Terminal.open() must be called before using this API.');
    }
    return sessionId;
  }

  void _handleRuntimeInputEvent(TerminalSessionInputEvent event) {
    if (event.sessionId != _sessionId) {
      return;
    }
    final data = utf8.decode(event.bytes, allowMalformed: true);
    _inputEvents.add(TerminalInputEvent(data: data, bytes: event.bytes));
    _dataEvents.add(data);
  }

  void _handleRuntimeResizeEvent(TerminalSessionResizeEvent event) {
    if (event.sessionId != _sessionId) {
      return;
    }
    _currentCols = event.cols;
    _currentRows = event.rows;
    _resizeEvents.add(TerminalResizeEvent(cols: event.cols, rows: event.rows));
  }

  void _handleRuntimeEvent(TerminalSessionEvent event) {
    if (event.sessionId != _sessionId) {
      return;
    }
    switch (event) {
      case TerminalSessionSshAuthPromptEvent():
        // The headless xterm-compatible facade has no credential UI.
        break;
      case TerminalSessionFrameEvent(:final frame):
        _handleFrame(frame);
      case TerminalSessionExitEvent(:final exitCode):
        _exitEvents.add(TerminalExitEvent(exitCode: exitCode));
        _sessionId = null;
        _scheduleRequestedDisposeRetry();
      case TerminalSessionBellEvent():
        break;
      case TerminalSessionShellHookEvent():
        break;
      case TerminalSessionShellContextEvent():
        break;
      case TerminalSessionShellCommandEvent():
        break;
      case TerminalSessionShellUserVarEvent():
        break;
      case TerminalSessionAnnotationEvent():
        break;
      case TerminalSessionNotificationEvent():
        break;
      case TerminalSessionProgressEvent():
        break;
      case TerminalSessionBadgeEvent():
        break;
      case TerminalSessionTabStatusEvent():
        break;
      case TerminalSessionContextEvent():
        break;
      case TerminalSessionDragDropCommandEvent():
        break;
      case TerminalSessionFileDownloadEvent():
        break;
      case TerminalSessionFileDownloadFailedEvent():
        break;
      case TerminalSessionFileUploadDeniedEvent():
        break;
      case TerminalSessionCellSizeReportRequestEvent():
        break;
      case TerminalSessionClearCapturedOutputEvent():
        break;
      case TerminalSessionReportVariableRequestEvent():
        // The xterm-compatible facade has no product-owned variable
        // permission store, so it fails closed with the required empty reply.
        _runtime.respondToOsc1337ReportVariable(event);
      case TerminalSessionOpenUrlRequestEvent():
        break;
      case TerminalSessionAttentionRequestEvent():
        break;
      case TerminalSessionResetEvent():
        break;
      case TerminalSessionClipboardEvent():
        break;
      case TerminalSessionBackendErrorEvent():
        break;
    }
  }

  void _handleFrame(TerminalFrameDiff frame) {
    if (frame.viewportCols > 0) {
      _currentCols = frame.viewportCols;
    }
    if (frame.viewportRows > 0) {
      _currentRows = frame.viewportRows;
    }
    final range = _renderEventFromIntent(
      TerminalRenderIntent.fromFrame(frame, hasNewFrame: true),
    );
    if (range != null) {
      _renderEvents.add(range);
    }
    if (_lastScrollbackOffset != frame.scrollbackOffset) {
      _lastScrollbackOffset = frame.scrollbackOffset;
      _scrollEvents.add(frame.scrollbackOffset);
    }
    final title = frame.windowTitle;
    if (title != null && title != _lastWindowTitle) {
      _lastWindowTitle = title;
      _titleChangeEvents.add(title);
    }
    if (!_sameSelection(_lastSelection, frame.selection)) {
      _lastSelection = frame.selection;
      _selectionChangeEvents.add(null);
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('Terminal has been disposed.');
    }
  }
}

class TerminalStreamSubscriptionDisposable<T> implements TerminalDisposable {
  TerminalStreamSubscriptionDisposable(this._subscription);

  final StreamSubscription<T> _subscription;
  bool _disposed = false;

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(_subscription.cancel());
  }
}

TerminalDisposable _listen<T>(
  Stream<T> stream,
  void Function(T event) listener,
) {
  return TerminalStreamSubscriptionDisposable(stream.listen(listener));
}

TerminalCursorShape _cursorShapeFor(TerminalCursorStyle style) {
  return switch (style) {
    TerminalCursorStyle.block => TerminalCursorShape.block,
    TerminalCursorStyle.underline => TerminalCursorShape.underline,
    TerminalCursorStyle.bar => TerminalCursorShape.beam,
  };
}

int _normalizeTerminalDimension(int value, int fallback) {
  if (value <= 0) {
    return fallback;
  }
  if (value > maxTerminalDimension) {
    return maxTerminalDimension;
  }
  return value;
}

TerminalRenderEvent? _renderEventFromIntent(TerminalRenderIntent intent) {
  if (!intent.hasDirtyExtent) {
    return null;
  }
  return TerminalRenderEvent(
    start: intent.dirtyStart!,
    end: intent.dirtyEnd! - 1,
  );
}

bool _sameSelection(TerminalSelection? left, TerminalSelection? right) {
  if (identical(left, right)) {
    return true;
  }
  if (left == null || right == null) {
    return false;
  }
  return left.startRow == right.startRow &&
      left.startCol == right.startCol &&
      left.endRow == right.endRow &&
      left.endCol == right.endCol;
}
