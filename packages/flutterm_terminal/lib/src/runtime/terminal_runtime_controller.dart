import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutterm_pty/flutterm_pty.dart';

import '../config/terminal_config.dart';
import '../terminal/terminal_models.dart';
import '../terminal/terminal_viewport.dart';

typedef TerminalWindowResizeCallback =
    Future<void> Function({
      required double widthDelta,
      required double heightDelta,
    });

sealed class TerminalSessionEvent {
  const TerminalSessionEvent(this.sessionId);

  final String sessionId;
}

final class TerminalSessionFrameEvent extends TerminalSessionEvent {
  const TerminalSessionFrameEvent(super.sessionId, this.frame);

  final TerminalFrameDiff frame;
}

final class TerminalSessionExitEvent extends TerminalSessionEvent {
  const TerminalSessionExitEvent(super.sessionId, {this.exitCode});

  final int? exitCode;
}

final class TerminalSessionResizeEvent {
  const TerminalSessionResizeEvent(
    this.sessionId, {
    required this.cols,
    required this.rows,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.viewportSize,
    required this.devicePixelRatio,
  });

  final String sessionId;
  final int cols;
  final int rows;
  final int pixelWidth;
  final int pixelHeight;
  final Size viewportSize;
  final double devicePixelRatio;
}

final class TerminalSessionInputEvent {
  const TerminalSessionInputEvent(this.sessionId, this.bytes);

  final String sessionId;
  final Uint8List bytes;
}

class TerminalRuntimeController {
  TerminalRuntimeController({
    required PtySessionBackend backend,
    required this.copyToClipboard,
    required this.readClipboard,
    this.resizeWindowBy,
    this.enableSessionPolling = true,
    this.enableWarmUpRefresh = false,
  }) : _backend = backend;

  final PtySessionBackend _backend;
  final Future<void> Function(String text) copyToClipboard;
  final Future<String> Function() readClipboard;
  final TerminalWindowResizeCallback? resizeWindowBy;
  final bool enableSessionPolling;
  final bool enableWarmUpRefresh;

  final Map<String, TerminalViewportController> _viewportControllers =
      <String, TerminalViewportController>{};
  final Map<String, _SessionResizeMetric> _lastResizeMetrics =
      <String, _SessionResizeMetric>{};
  final Map<String, List<Timer>> _warmUpTimers = <String, List<Timer>>{};
  final StreamController<TerminalSessionEvent> _events =
      StreamController<TerminalSessionEvent>.broadcast();
  final StreamController<TerminalSessionInputEvent> _inputEvents =
      StreamController<TerminalSessionInputEvent>.broadcast();
  final StreamController<TerminalSessionResizeEvent> _resizeEvents =
      StreamController<TerminalSessionResizeEvent>.broadcast();
  final Set<String> _activeSessionIds = <String>{};
  final Set<String> _refreshingSessionIds = <String>{};
  final Set<String> _queuedRefreshSessionIds = <String>{};
  final Set<String> _scheduledRefreshSessionIds = <String>{};
  Timer? _pollTimer;
  int _wireSessionSeed = 0;

  Stream<TerminalSessionEvent> get events => _events.stream;
  Stream<TerminalSessionInputEvent> get inputEvents => _inputEvents.stream;
  Stream<TerminalSessionResizeEvent> get resizeEvents => _resizeEvents.stream;

  TerminalViewportController viewportFor(String sessionId) {
    return _viewportControllers.putIfAbsent(
      sessionId,
      TerminalViewportController.new,
    );
  }

  bool hasSession(String sessionId) => _activeSessionIds.contains(sessionId);

  String createSession(TerminalSessionConfig config) {
    final sessionId = _backend.createSession(
      _encodeNativeSessionConfig(config),
    );
    _activeSessionIds.add(sessionId);
    viewportFor(sessionId);
    _requestRefreshSession(sessionId, immediate: true);
    if (enableSessionPolling) {
      _startPolling();
    } else {
      _scheduleWarmUpRefreshes(sessionId);
    }
    return sessionId;
  }

  void closeSession(String sessionId) {
    _backend.closeSession(sessionId);
    _removeSessionState(sessionId);
  }

  void sendInput(String sessionId, Uint8List bytes) {
    final copiedBytes = Uint8List.fromList(bytes);
    _inputEvents.add(TerminalSessionInputEvent(sessionId, copiedBytes));
    _backend.writeInput(sessionId, copiedBytes);
    _refreshSessionIfNeeded(sessionId);
  }

  void scrollViewport(String sessionId, int deltaLines) {
    _backend.scrollViewport(sessionId, deltaLines);
    _refreshSessionIfNeeded(sessionId);
  }

  void scrollViewportTo(String sessionId, int offset) {
    _backend.scrollViewportTo(sessionId, offset);
    _refreshSessionIfNeeded(sessionId);
  }

  String? selectionText(
    String sessionId,
    TerminalSelection selection, {
    required bool block,
  }) {
    return _backend.selectionText(
      sessionId,
      jsonEncode(<String, Object?>{...selection.toJson(), 'block': block}),
    );
  }

  List<TerminalSearchMatch> searchText(String sessionId, String query) {
    if (query.isEmpty) {
      return const <TerminalSearchMatch>[];
    }
    final raw = _backend.searchTextJson(sessionId, query);
    if (raw == null || raw.isEmpty) {
      return const <TerminalSearchMatch>[];
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map(
          (entry) => TerminalSearchMatch.fromJson(
            (entry as Map).cast<String, Object?>(),
          ),
        )
        .toList();
  }

  void resizeSession(
    String sessionId,
    Size viewportSize,
    double devicePixelRatio,
  ) {
    final measuredCellSize = _cellSizeFor(sessionId);
    final cellWidth = measuredCellSize.width;
    final cellHeight = measuredCellSize.height;
    final cols = math.max(20, (viewportSize.width / cellWidth).floor());
    final rows = math.max(8, (viewportSize.height / cellHeight).floor());
    final pixelWidth = (viewportSize.width * devicePixelRatio).round();
    final pixelHeight = (viewportSize.height * devicePixelRatio).round();
    final nextMetric = _SessionResizeMetric(
      cols: cols,
      rows: rows,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      logicalWidth: viewportSize.width,
      logicalHeight: viewportSize.height,
      devicePixelRatio: devicePixelRatio,
    );
    final previous = _lastResizeMetrics[sessionId];
    if (previous != null &&
        previous.cols == cols &&
        previous.rows == rows &&
        previous.pixelWidth == pixelWidth &&
        previous.pixelHeight == pixelHeight) {
      return;
    }
    _backend.resizeSession(
      sessionId,
      cols: cols,
      rows: rows,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
    );
    _lastResizeMetrics[sessionId] = nextMetric;
    _resizeEvents.add(
      TerminalSessionResizeEvent(
        sessionId,
        cols: cols,
        rows: rows,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        viewportSize: viewportSize,
        devicePixelRatio: devicePixelRatio,
      ),
    );
    if (!enableSessionPolling) {
      _requestRefreshSession(sessionId, immediate: true);
    }
  }

  void resizeSessionCells(
    String sessionId, {
    required int cols,
    required int rows,
    double devicePixelRatio = 1,
    Size? cellSize,
  }) {
    if (cols <= 0 || rows <= 0 || devicePixelRatio <= 0) {
      throw RangeError(
        'Terminal dimensions and devicePixelRatio must be positive.',
      );
    }
    final measuredCellSize = cellSize ?? _cellSizeFor(sessionId);
    final logicalWidth = cols * measuredCellSize.width;
    final logicalHeight = rows * measuredCellSize.height;
    final pixelWidth = math.max(1, (logicalWidth * devicePixelRatio).round());
    final pixelHeight = math.max(1, (logicalHeight * devicePixelRatio).round());
    final nextMetric = _SessionResizeMetric(
      cols: cols,
      rows: rows,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      logicalWidth: logicalWidth,
      logicalHeight: logicalHeight,
      devicePixelRatio: devicePixelRatio,
    );
    final previous = _lastResizeMetrics[sessionId];
    if (previous != null &&
        previous.cols == cols &&
        previous.rows == rows &&
        previous.pixelWidth == pixelWidth &&
        previous.pixelHeight == pixelHeight) {
      return;
    }
    _backend.resizeSession(
      sessionId,
      cols: cols,
      rows: rows,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
    );
    _lastResizeMetrics[sessionId] = nextMetric;
    _resizeEvents.add(
      TerminalSessionResizeEvent(
        sessionId,
        cols: cols,
        rows: rows,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        viewportSize: Size(logicalWidth, logicalHeight),
        devicePixelRatio: devicePixelRatio,
      ),
    );
    if (!enableSessionPolling) {
      _requestRefreshSession(sessionId, immediate: true);
    }
  }

  void _startPolling() {
    _pollTimer ??= Timer.periodic(const Duration(milliseconds: 33), (_) {
      for (final sessionId in _activeSessionIds.toList(growable: false)) {
        _requestRefreshSession(sessionId, immediate: true);
      }
    });
  }

  void _requestRefreshSession(String sessionId, {bool immediate = false}) {
    if (!hasSession(sessionId)) {
      return;
    }
    if (_refreshingSessionIds.contains(sessionId)) {
      _queuedRefreshSessionIds.add(sessionId);
      return;
    }
    if (!immediate) {
      if (!_scheduledRefreshSessionIds.add(sessionId)) {
        return;
      }
      scheduleMicrotask(() {
        _scheduledRefreshSessionIds.remove(sessionId);
        _requestRefreshSession(sessionId, immediate: true);
      });
      return;
    }
    unawaited(_refreshSession(sessionId));
  }

  Future<void> _refreshSession(String sessionId) async {
    if (!hasSession(sessionId)) {
      return;
    }

    _refreshingSessionIds.add(sessionId);
    try {
      var runAgain = true;
      final pendingFrames = <TerminalFrameDiff>[];
      var skippedQueuedFrames = 0;
      while (runAgain && hasSession(sessionId)) {
        _queuedRefreshSessionIds.remove(sessionId);
        runAgain = false;

        final rawFrame = _backend.takeFrameDiffJson(sessionId);
        if (rawFrame != null && rawFrame.isNotEmpty) {
          _queuePendingFrame(pendingFrames, _decodeFrame(rawFrame));
        }

        final events = _backend.pollEvents(sessionId);
        final shouldApplyBeforeEvents =
            pendingFrames.isNotEmpty &&
            (!_eventsDelayFrame(events) || _eventsContainExit(events));
        if (shouldApplyBeforeEvents) {
          _applyPendingFrames(sessionId, pendingFrames);
          skippedQueuedFrames = 0;
        }

        final eventProcessing = _processEvents(sessionId, events);
        if (eventProcessing != null) {
          await eventProcessing;
        }
        if (!hasSession(sessionId)) {
          return;
        }

        runAgain = _queuedRefreshSessionIds.remove(sessionId);
        final shouldApplyPendingFrame =
            pendingFrames.isNotEmpty && (!runAgain || skippedQueuedFrames >= 1);
        if (shouldApplyPendingFrame) {
          _applyPendingFrames(sessionId, pendingFrames);
          skippedQueuedFrames = 0;
        } else if (runAgain && pendingFrames.isNotEmpty) {
          skippedQueuedFrames += 1;
        }
      }
    } finally {
      _refreshingSessionIds.remove(sessionId);
      if (_queuedRefreshSessionIds.remove(sessionId) && hasSession(sessionId)) {
        _requestRefreshSession(sessionId);
      }
    }
  }

  void _refreshSessionIfNeeded(String sessionId) {
    if (!enableSessionPolling) {
      _requestRefreshSession(sessionId);
    }
  }

  void _applyFrame(String sessionId, TerminalFrameDiff frame) {
    viewportFor(sessionId).updateFrame(frame);
    _events.add(TerminalSessionFrameEvent(sessionId, frame));
  }

  TerminalFrameDiff _decodeFrame(String rawFrame) {
    return TerminalFrameDiff.fromJson(
      (jsonDecode(rawFrame) as Map).cast<String, Object?>(),
    );
  }

  void _queuePendingFrame(
    List<TerminalFrameDiff> pendingFrames,
    TerminalFrameDiff frame,
  ) {
    if (frame.frameKind == TerminalFrameKind.snapshot) {
      pendingFrames.clear();
    }
    pendingFrames.add(frame);
  }

  void _applyPendingFrames(
    String sessionId,
    List<TerminalFrameDiff> pendingFrames,
  ) {
    for (final frame in pendingFrames) {
      _applyFrame(sessionId, frame);
    }
    pendingFrames.clear();
  }

  bool _eventsContainExit(List<PtyEvent> events) {
    for (final event in events) {
      if (event.kind == 'exit') {
        return true;
      }
    }
    return false;
  }

  bool _eventsDelayFrame(List<PtyEvent> events) {
    for (final event in events) {
      switch (event.kind) {
        case 'resize':
          return true;
        default:
          break;
      }
    }
    return false;
  }

  Future<void>? _processEvents(String sessionId, List<PtyEvent> events) {
    Future<void>? pendingAsyncWork;
    for (final event in events) {
      switch (event.kind) {
        case 'exit':
          final exitCode = (event.payload?['code'] as num?)?.toInt();
          if (pendingAsyncWork == null) {
            _removeSessionState(sessionId);
            _events.add(
              TerminalSessionExitEvent(sessionId, exitCode: exitCode),
            );
            return null;
          }
          return pendingAsyncWork.then((_) {
            _removeSessionState(sessionId);
            _events.add(
              TerminalSessionExitEvent(sessionId, exitCode: exitCode),
            );
          });
        case 'resize':
          pendingAsyncWork = _chainAsyncEvent(
            pendingAsyncWork,
            () => _handleResizeEvent(sessionId, event.payload),
          );
          break;
        case 'clipboard_copy':
          pendingAsyncWork = _chainAsyncEvent(
            pendingAsyncWork,
            () => _handleClipboardCopyEvent(event.payload),
          );
          break;
        case 'clipboard_paste_request':
          pendingAsyncWork = _chainAsyncEvent(
            pendingAsyncWork,
            () => _handleClipboardPasteRequestEvent(sessionId, event.payload),
          );
          break;
        default:
          break;
      }
    }
    return pendingAsyncWork;
  }

  Future<void> _chainAsyncEvent(
    Future<void>? pendingAsyncWork,
    Future<void> Function() process,
  ) {
    if (pendingAsyncWork == null) {
      return process();
    }
    return pendingAsyncWork.then((_) => process());
  }

  Future<void> _handleResizeEvent(
    String sessionId,
    Map<String, Object?>? payload,
  ) async {
    if (payload == null) {
      return;
    }
    final cols = (payload['cols'] as num?)?.toInt();
    final rows = (payload['rows'] as num?)?.toInt();
    final metric = _lastResizeMetrics[sessionId];
    if (cols == null ||
        rows == null ||
        cols <= 0 ||
        rows <= 0 ||
        metric == null) {
      return;
    }

    final measuredCellSize = _cellSizeFor(sessionId);
    final targetWidth = cols * measuredCellSize.width;
    final targetHeight = rows * measuredCellSize.height;
    final widthDelta = targetWidth - metric.logicalWidth;
    final heightDelta = targetHeight - metric.logicalHeight;
    final targetPixelWidth = math.max(
      1,
      (targetWidth * metric.devicePixelRatio).round(),
    );
    final targetPixelHeight = math.max(
      1,
      (targetHeight * metric.devicePixelRatio).round(),
    );

    _backend.resizeSession(
      sessionId,
      cols: cols,
      rows: rows,
      pixelWidth: targetPixelWidth,
      pixelHeight: targetPixelHeight,
    );
    _lastResizeMetrics[sessionId] = _SessionResizeMetric(
      cols: cols,
      rows: rows,
      pixelWidth: targetPixelWidth,
      pixelHeight: targetPixelHeight,
      logicalWidth: targetWidth,
      logicalHeight: targetHeight,
      devicePixelRatio: metric.devicePixelRatio,
    );
    _resizeEvents.add(
      TerminalSessionResizeEvent(
        sessionId,
        cols: cols,
        rows: rows,
        pixelWidth: targetPixelWidth,
        pixelHeight: targetPixelHeight,
        viewportSize: Size(targetWidth, targetHeight),
        devicePixelRatio: metric.devicePixelRatio,
      ),
    );
    if (!enableSessionPolling) {
      _requestRefreshSession(sessionId, immediate: true);
    }

    if (widthDelta == 0 && heightDelta == 0) {
      return;
    }

    await resizeWindowBy?.call(
      widthDelta: widthDelta,
      heightDelta: heightDelta,
    );
  }

  Size _cellSizeFor(String sessionId) {
    return viewportFor(sessionId).measuredCellSize ?? terminalFallbackCellSize;
  }

  Future<void> _handleClipboardCopyEvent(Map<String, Object?>? payload) async {
    if (payload == null) {
      return;
    }
    final raw = payload['data'] as String?;
    if (raw == null || raw.isEmpty) {
      return;
    }
    final decoded = utf8.decode(base64.decode(raw), allowMalformed: true);
    if (decoded.isEmpty) {
      return;
    }
    await copyToClipboard(decoded);
  }

  Future<void> _handleClipboardPasteRequestEvent(
    String sessionId,
    Map<String, Object?>? payload,
  ) async {
    final selection = payload?['selection'] as String? ?? 'c';
    final clipboardText = await readClipboard();
    final encoded = base64.encode(utf8.encode(clipboardText));
    final response = '\x1B]52;$selection;$encoded\x07';
    sendInput(sessionId, Uint8List.fromList(utf8.encode(response)));
  }

  void _scheduleWarmUpRefreshes(String sessionId) {
    if (!enableWarmUpRefresh) {
      return;
    }
    for (final timer in _warmUpTimers.remove(sessionId) ?? const <Timer>[]) {
      timer.cancel();
    }
    final delays = <Duration>[
      const Duration(milliseconds: 60),
      const Duration(milliseconds: 140),
      const Duration(milliseconds: 260),
    ];
    final timers = <Timer>[];
    for (final delay in delays) {
      timers.add(
        Timer(delay, () {
          if (!hasSession(sessionId)) {
            return;
          }
          final controller = _viewportControllers[sessionId];
          final hasVisibleContent =
              controller != null &&
              controller.frame.rows.any((row) => row.text.trim().isNotEmpty);
          if (hasVisibleContent) {
            for (final timer
                in _warmUpTimers.remove(sessionId) ?? const <Timer>[]) {
              timer.cancel();
            }
            return;
          }
          _requestRefreshSession(sessionId);
        }),
      );
    }
    _warmUpTimers[sessionId] = timers;
  }

  void _removeSessionState(String sessionId) {
    _activeSessionIds.remove(sessionId);
    _refreshingSessionIds.remove(sessionId);
    _queuedRefreshSessionIds.remove(sessionId);
    _scheduledRefreshSessionIds.remove(sessionId);
    for (final timer in _warmUpTimers.remove(sessionId) ?? const <Timer>[]) {
      timer.cancel();
    }
    _viewportControllers.remove(sessionId)?.dispose();
    _lastResizeMetrics.remove(sessionId);
    if (_activeSessionIds.isEmpty) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  String _encodeNativeSessionConfig(TerminalSessionConfig config) {
    _wireSessionSeed += 1;
    final program = config.launch.program.trim();
    final wireName = program.isEmpty
        ? 'Terminal Session'
        : program.split('/').last;
    final json = config.toJson();
    return jsonEncode(<String, Object?>{
      'id': 'runtime-${_wireSessionSeed}',
      'name': wireName,
      ...json,
    });
  }

  void dispose() {
    for (final sessionId in _activeSessionIds.toList(growable: false)) {
      _backend.closeSession(sessionId);
      _removeSessionState(sessionId);
    }
    _pollTimer?.cancel();
    for (final timers in _warmUpTimers.values) {
      for (final timer in timers) {
        timer.cancel();
      }
    }
    for (final controller in _viewportControllers.values) {
      controller.dispose();
    }
    _events.close();
    _inputEvents.close();
    _resizeEvents.close();
  }
}

class _SessionResizeMetric {
  _SessionResizeMetric({
    required this.cols,
    required this.rows,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.logicalWidth,
    required this.logicalHeight,
    required this.devicePixelRatio,
  });

  final int cols;
  final int rows;
  final int pixelWidth;
  final int pixelHeight;
  final double logicalWidth;
  final double logicalHeight;
  final double devicePixelRatio;
}
