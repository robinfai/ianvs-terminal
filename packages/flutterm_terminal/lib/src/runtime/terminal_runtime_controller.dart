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
  final Set<String> _activeSessionIds = <String>{};
  Timer? _pollTimer;
  int _wireSessionSeed = 0;

  Stream<TerminalSessionEvent> get events => _events.stream;

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
    _refreshSession(sessionId);
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
    _backend.writeInput(sessionId, bytes);
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
    if (!enableSessionPolling) {
      _refreshSession(sessionId);
    }
  }

  void _startPolling() {
    _pollTimer ??= Timer.periodic(const Duration(milliseconds: 33), (_) {
      for (final sessionId in _activeSessionIds.toList(growable: false)) {
        _refreshSession(sessionId);
      }
    });
  }

  void _refreshSession(String sessionId) {
    final rawFrame = _backend.takeFrameDiffJson(sessionId);
    if (rawFrame != null && rawFrame.isNotEmpty) {
      final frame = TerminalFrameDiff.fromJson(
        (jsonDecode(rawFrame) as Map).cast<String, Object?>(),
      );
      _applyFrame(sessionId, frame);
    }
    unawaited(_processEvents(sessionId, _backend.pollEvents(sessionId)));
  }

  void _refreshSessionIfNeeded(String sessionId) {
    if (!enableSessionPolling) {
      _refreshSession(sessionId);
    }
  }

  void _applyFrame(String sessionId, TerminalFrameDiff frame) {
    viewportFor(sessionId).updateFrame(frame);
    _events.add(TerminalSessionFrameEvent(sessionId, frame));
  }

  Future<void> _processEvents(String sessionId, List<PtyEvent> events) async {
    for (final event in events) {
      switch (event.kind) {
        case 'exit':
          final exitCode = (event.payload?['code'] as num?)?.toInt();
          _removeSessionState(sessionId);
          _events.add(TerminalSessionExitEvent(sessionId, exitCode: exitCode));
          return;
        case 'resize':
          await _handleResizeEvent(sessionId, event.payload);
          break;
        case 'clipboard_copy':
          await _handleClipboardCopyEvent(event.payload);
          break;
        case 'clipboard_paste_request':
          await _handleClipboardPasteRequestEvent(sessionId, event.payload);
          break;
        default:
          break;
      }
    }
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
    if (!enableSessionPolling) {
      _refreshSession(sessionId);
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
          _refreshSession(sessionId);
        }),
      );
    }
    _warmUpTimers[sessionId] = timers;
  }

  void _removeSessionState(String sessionId) {
    _activeSessionIds.remove(sessionId);
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
