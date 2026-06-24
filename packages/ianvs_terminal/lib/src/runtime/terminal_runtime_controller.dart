import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:ianvs_pty/ianvs_pty.dart';

import '../config/terminal_config.dart';
import '../terminal/selection_controller.dart';
import '../terminal/terminal_graphics_cache.dart';
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

final class TerminalSessionBellEvent extends TerminalSessionEvent {
  const TerminalSessionBellEvent(super.sessionId);
}

final class TerminalSessionShellHookEvent extends TerminalSessionEvent {
  TerminalSessionShellHookEvent(
    super.sessionId, {
    Map<String, Object?>? rawPayload,
  }) : rawPayload = Map.unmodifiable(rawPayload ?? const <String, Object?>{});

  final Map<String, Object?> rawPayload;

  String? get hook => _hookValue(rawPayload['hook']);
  String? get command => _stringValue(rawPayload['command']);
  String? get cwd => _stringValue(rawPayload['cwd'] ?? rawPayload['pwd']);
  String? get shell => _stringValue(rawPayload['shell']);
  String? get hostname =>
      _stringValue(rawPayload['hostname'] ?? rawPayload['host']);
  String? get username =>
      _stringValue(rawPayload['username'] ?? rawPayload['user']);
  int? get promptScrollbackOffset => _intValue(
    rawPayload['promptScrollbackOffset'] ??
        rawPayload['prompt_scrollback_offset'] ??
        rawPayload['scrollback_offset'],
  );
  int? get exitCode =>
      _intValue(rawPayload['exitCode'] ?? rawPayload['exit_code']);

  static String? _stringValue(Object? value) {
    return value is String ? value : null;
  }

  static String? _hookValue(Object? value) {
    if (value is! String) {
      return null;
    }
    final hook = value.trim();
    return hook.isEmpty ? null : hook;
  }

  static int? _intValue(Object? value) {
    return _wholeIntValue(value);
  }
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

final class TerminalDiagnosticsPolicy {
  const TerminalDiagnosticsPolicy({
    this.maxSamples = 60,
    this.includeScrollback = false,
    this.includeRawCommand = false,
    this.includeRawCwd = false,
    this.includeEnv = false,
    this.redactionMode = 'basic',
  });

  final int maxSamples;
  final bool includeScrollback;
  final bool includeRawCommand;
  final bool includeRawCwd;
  final bool includeEnv;
  final String redactionMode;

  bool get includeContent =>
      includeScrollback || includeRawCommand || includeRawCwd || includeEnv;

  Map<String, Object?> toRequestJson() {
    final effectiveMaxSamples = maxSamples.clamp(1, 60).toInt();
    return <String, Object?>{
      'kind': 'terminal.export_diagnostics',
      'maxSamples': effectiveMaxSamples,
      'includeContent': includeContent,
      'redactionMode': redactionMode,
      'policy': <String, Object?>{
        'includeScrollback': includeScrollback,
        'includeRawCommand': includeRawCommand,
        'includeRawCwd': includeRawCwd,
        'includeEnv': includeEnv,
      },
    };
  }
}

final class TerminalDiagnosticsExport {
  const TerminalDiagnosticsExport({
    required this.manifest,
    required this.resourceSamples,
    required this.terminalStats,
    required this.events,
    required this.summary,
  });

  factory TerminalDiagnosticsExport.fromJson(Map<String, Object?> json) {
    return TerminalDiagnosticsExport(
      manifest: _mapValue(json['manifest']),
      resourceSamples: _mapList(
        json['resource_samples'] ?? json['resourceSamples'],
      ),
      terminalStats: _mapValue(json['terminal_stats'] ?? json['terminalStats']),
      events: _mapList(json['events']),
      summary: _mapValue(json['summary']),
    );
  }

  final Map<String, Object?> manifest;
  final List<Map<String, Object?>> resourceSamples;
  final Map<String, Object?> terminalStats;
  final List<Map<String, Object?>> events;
  final Map<String, Object?> summary;

  String? get conclusion =>
      _nonEmptyTrimmedStringFromJsonValue(summary['conclusion']);
  String? get summaryMarkdown =>
      _nonEmptyTrimmedStringFromJsonValue(summary['markdown']);

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'manifest': manifest,
      'resource_samples': resourceSamples,
      'terminal_stats': terminalStats,
      'events': events,
      'summary': summary,
    };
  }
}

Map<String, Object?> _mapValue(Object? value) {
  if (value is Map) {
    return Map<String, Object?>.unmodifiable(_stringKeyedJsonMap(value));
  }
  return const <String, Object?>{};
}

List<Map<String, Object?>> _mapList(Object? value) {
  if (value is! List) {
    return const <Map<String, Object?>>[];
  }
  return List<Map<String, Object?>>.unmodifiable(
    value.whereType<Map>().map(
      (entry) => Map<String, Object?>.unmodifiable(_stringKeyedJsonMap(entry)),
    ),
  );
}

class TerminalRuntimeController {
  TerminalRuntimeController({
    required PtySessionBackend backend,
    required this.copyToClipboard,
    required this.readClipboard,
    Future<bool> Function()? allowClipboardCopy,
    Future<bool> Function()? allowClipboardPasteRequest,
    this.resizeWindowBy,
    this.enableSessionPolling = true,
    this.enableWarmUpRefresh = false,
  }) : _backend = backend,
       allowClipboardCopy = allowClipboardCopy ?? _allowClipboardAccess,
       allowClipboardPasteRequest =
           allowClipboardPasteRequest ?? _allowClipboardAccess;

  final PtySessionBackend _backend;
  final Future<void> Function(String text) copyToClipboard;
  final Future<String> Function() readClipboard;
  final Future<bool> Function() allowClipboardCopy;
  final Future<bool> Function() allowClipboardPasteRequest;
  final TerminalWindowResizeCallback? resizeWindowBy;
  final bool enableSessionPolling;
  final bool enableWarmUpRefresh;

  final Map<String, TerminalViewportController> _viewportControllers =
      <String, TerminalViewportController>{};
  final Map<String, TerminalGraphicsCache> _graphicsCaches =
      <String, TerminalGraphicsCache>{};
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

  TerminalGraphicsCache graphicsCacheFor(String sessionId) {
    return _graphicsCaches.putIfAbsent(
      sessionId,
      () => TerminalGraphicsCache(
        loadAsset: (key) => loadGraphicAsset(sessionId, key),
      ),
    );
  }

  bool hasSession(String sessionId) => _activeSessionIds.contains(sessionId);

  String createSession(TerminalSessionConfig config) {
    final sessionId = _backend.createSession(
      _encodeNativeSessionConfig(_resolveColorsForRuntime(config)),
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
    if (!hasSession(sessionId)) {
      return;
    }
    _backend.closeSession(sessionId);
    _removeSessionState(sessionId);
  }

  void sendInput(String sessionId, Uint8List bytes) {
    if (!hasSession(sessionId)) {
      return;
    }
    final copiedBytes = Uint8List.fromList(bytes);
    _inputEvents.add(TerminalSessionInputEvent(sessionId, copiedBytes));
    _backend.writeInput(sessionId, copiedBytes);
    _refreshSessionIfNeeded(sessionId);
  }

  void scrollViewport(String sessionId, int deltaLines) {
    if (!hasSession(sessionId)) {
      return;
    }
    _backend.scrollViewport(sessionId, deltaLines);
    _refreshSessionIfNeeded(sessionId);
  }

  void scrollViewportTo(String sessionId, int offset) {
    if (!hasSession(sessionId)) {
      return;
    }
    _backend.scrollViewportTo(sessionId, offset);
    _refreshSessionIfNeeded(sessionId);
  }

  void refreshSession(String sessionId) {
    if (!hasSession(sessionId)) {
      return;
    }
    final frame = viewportFor(sessionId).frame;
    final scrollbackOffset = frame.scrollbackOffset
        .clamp(0, frame.scrollbackMaxOffset)
        .toInt();
    _backend.scrollViewportTo(sessionId, scrollbackOffset);
    _requestRefreshSession(sessionId, immediate: true);
  }

  Future<TerminalGraphicAsset?> loadGraphicAsset(
    String sessionId,
    TerminalGraphicAssetKey key,
  ) async {
    if (!hasSession(sessionId)) {
      return null;
    }
    final backend = _backend;
    final graphicBackend = backend is PtySessionGraphicAssetBackend
        ? backend as PtySessionGraphicAssetBackend
        : null;
    if (graphicBackend == null) {
      return null;
    }
    final nativeAsset = graphicBackend.loadGraphicAsset(
      sessionId,
      assetId: key.id,
      assetVersion: key.version,
    );
    if (nativeAsset == null) {
      return null;
    }
    return TerminalGraphicAsset(
      key: key,
      width: nativeAsset.width,
      height: nativeAsset.height,
      rgba: nativeAsset.rgba,
    );
  }

  String? selectionText(
    String sessionId,
    TerminalSelection selection, {
    required bool block,
  }) {
    if (!hasSession(sessionId)) {
      return '';
    }
    final backend = _backend;
    final requestBackend = backend is PtySessionJsonRequestBackend
        ? backend as PtySessionJsonRequestBackend
        : null;
    if (requestBackend != null) {
      final raw = requestBackend.requestSessionJson(
        sessionId,
        jsonEncode(<String, Object?>{
          'kind': 'terminal.selection_text',
          'selection': selection.toJson(),
          'block': block,
        }),
      );
      if (raw != null && raw.isNotEmpty) {
        final decoded = _tryDecodeJsonObject(raw);
        if (decoded != null) {
          final text = _stringFromJsonValue(decoded['text']);
          if (text != null) {
            return text;
          }
        }
      }
    }
    return _selectionTextFromViewport(sessionId, selection, block: block);
  }

  TerminalSearchResult searchTextResult(
    String sessionId,
    String query, {
    TerminalSearchMode mode = TerminalSearchMode.smartCaseSubstring,
  }) {
    if (!hasSession(sessionId)) {
      return TerminalSearchResult.empty;
    }
    if (query.isEmpty) {
      return TerminalSearchResult.empty;
    }
    final backend = _backend;
    final requestBackend = backend is PtySessionJsonRequestBackend
        ? backend as PtySessionJsonRequestBackend
        : null;
    if (requestBackend == null) {
      return TerminalSearchResult.empty;
    }
    final raw = requestBackend.requestSessionJson(
      sessionId,
      jsonEncode(<String, Object?>{
        'kind': 'terminal.search_text',
        'query': query,
        'mode': mode.wireName,
      }),
    );
    if (raw == null || raw.isEmpty) {
      return TerminalSearchResult.empty;
    }
    return _decodeSearchResult(_tryDecodeJsonObject(raw));
  }

  List<TerminalSearchMatch> searchText(
    String sessionId,
    String query, {
    TerminalSearchMode mode = TerminalSearchMode.smartCaseSubstring,
  }) {
    return searchTextResult(sessionId, query, mode: mode).matches;
  }

  TerminalSearchResult _decodeSearchResult(Object? decoded) {
    if (decoded is Map) {
      final json = _stringKeyedJsonMap(decoded);
      final rawMatches = json['matches'];
      return TerminalSearchResult(
        matches: rawMatches is List
            ? _decodeSearchMatches(rawMatches)
            : const <TerminalSearchMatch>[],
        errorText: _nonEmptyTrimmedStringFromJsonValue(
          json['error_text'] ?? json['errorText'],
        ),
      );
    }
    return TerminalSearchResult.empty;
  }

  List<TerminalSearchMatch> _decodeSearchMatches(List<dynamic> entries) {
    final matches = <TerminalSearchMatch>[];
    for (final entry in entries) {
      if (entry is! Map) {
        continue;
      }
      try {
        matches.add(TerminalSearchMatch.fromJson(_stringKeyedJsonMap(entry)));
      } on Object {
        continue;
      }
    }
    return matches;
  }

  bool clearScrollback(String sessionId) {
    if (!hasSession(sessionId)) {
      return false;
    }
    final backend = _backend;
    final requestBackend = backend is PtySessionJsonRequestBackend
        ? backend as PtySessionJsonRequestBackend
        : null;
    if (requestBackend == null) {
      return false;
    }
    final raw = requestBackend.requestSessionJson(
      sessionId,
      jsonEncode(<String, Object?>{'kind': 'terminal.clear_scrollback'}),
    );
    if (raw == null || raw.isEmpty) {
      return false;
    }
    final decoded = _tryDecodeJsonObject(raw);
    if (decoded == null || decoded['cleared'] != true) {
      return false;
    }

    final current = viewportFor(sessionId).frame;
    viewportFor(sessionId).applySnapshot(
      TerminalFrameDiff(
        frameKind: TerminalFrameKind.snapshot,
        rows: const [],
        cursor: current.cursor,
        viewportRows: current.viewportRows,
        viewportCols: current.viewportCols,
        dirtyRanges: [TerminalDirtyRange(start: 0, end: current.viewportRows)],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
        modes: current.modes,
        windowTitle: current.windowTitle,
        windowIconName: current.windowIconName,
      ),
    );
    return true;
  }

  String? exportScrollbackText(String sessionId, {int? maxLines}) {
    if (!hasSession(sessionId)) {
      return null;
    }
    final backend = _backend;
    final requestBackend = backend is PtySessionJsonRequestBackend
        ? backend as PtySessionJsonRequestBackend
        : null;
    if (requestBackend == null) {
      return null;
    }
    final raw = requestBackend.requestSessionJson(
      sessionId,
      jsonEncode(<String, Object?>{
        'kind': 'terminal.export_scrollback',
        'maxLines': ?maxLines,
      }),
    );
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final decoded = _tryDecodeJsonObject(raw);
    if (decoded == null) {
      return null;
    }
    return _stringFromJsonValue(decoded['content']);
  }

  TerminalDiagnosticsExport? exportSessionDiagnostics(
    String sessionId, {
    TerminalDiagnosticsPolicy policy = const TerminalDiagnosticsPolicy(),
  }) {
    if (!hasSession(sessionId)) {
      return null;
    }
    final backend = _backend;
    final requestBackend = backend is PtySessionJsonRequestBackend
        ? backend as PtySessionJsonRequestBackend
        : null;
    if (requestBackend == null) {
      return null;
    }

    try {
      final raw = requestBackend.requestSessionJson(
        sessionId,
        jsonEncode(policy.toRequestJson()),
      );
      if (raw == null || raw.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      return TerminalDiagnosticsExport.fromJson(
        decoded.cast<String, Object?>(),
      );
    } on Object {
      return null;
    }
  }

  String _selectionTextFromViewport(
    String sessionId,
    TerminalSelection selection, {
    required bool block,
  }) {
    final controller = SelectionController()
      ..setSelection(
        selection,
        mode: block ? SelectionMode.block : SelectionMode.linear,
      );
    try {
      return controller.textForFrame(viewportFor(sessionId).frame);
    } finally {
      controller.dispose();
    }
  }

  void resizeSession(
    String sessionId,
    Size viewportSize,
    double devicePixelRatio,
  ) {
    if (!hasSession(sessionId)) {
      return;
    }
    if (!_isPositiveFiniteSize(viewportSize) ||
        !_isPositiveFiniteDouble(devicePixelRatio)) {
      return;
    }
    final measuredCellSize = _cellSizeFor(sessionId);
    if (!_isPositiveFiniteSize(measuredCellSize)) {
      return;
    }
    final cellWidth = measuredCellSize.width;
    final cellHeight = measuredCellSize.height;
    final cols = math.max(20, (viewportSize.width / cellWidth).floor());
    final rows = math.max(8, (viewportSize.height / cellHeight).floor());
    final pixelWidth = math.max(
      1,
      (viewportSize.width * devicePixelRatio).round(),
    );
    final pixelHeight = math.max(
      1,
      (viewportSize.height * devicePixelRatio).round(),
    );
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
    if (!hasSession(sessionId)) {
      return;
    }
    if (cols <= 0 || rows <= 0 || !_isPositiveFiniteDouble(devicePixelRatio)) {
      throw RangeError(
        'Terminal dimensions and devicePixelRatio must be positive.',
      );
    }
    final measuredCellSize = cellSize ?? _cellSizeFor(sessionId);
    if (!_isPositiveFiniteSize(measuredCellSize)) {
      throw RangeError('Cell size must be positive and finite.');
    }
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
          final frame = _decodeFrame(rawFrame);
          if (frame != null) {
            _queuePendingFrame(pendingFrames, frame);
          }
        }

        final events = _eventsForSession(
          sessionId,
          _backend.pollEvents(sessionId),
        );
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

  TerminalFrameDiff? _decodeFrame(String rawFrame) {
    final json = _tryDecodeJsonObject(rawFrame);
    if (json == null) {
      return null;
    }
    try {
      return TerminalFrameDiff.fromJson(json);
    } on Object {
      return null;
    }
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

  List<PtyEvent> _eventsForSession(String sessionId, List<PtyEvent> events) {
    return events
        .where((event) => event.sessionId == sessionId)
        .toList(growable: false);
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
          final exitCode = _intFromEventPayload(event.payload?['code']);
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
        case 'bell':
          _events.add(TerminalSessionBellEvent(sessionId));
          break;
        case 'shell_hook':
          _events.add(
            TerminalSessionShellHookEvent(sessionId, rawPayload: event.payload),
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
    final cols = _intFromEventPayload(payload['cols']);
    final rows = _intFromEventPayload(payload['rows']);
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

  bool _isPositiveFiniteSize(Size size) {
    return _isPositiveFiniteDouble(size.width) &&
        _isPositiveFiniteDouble(size.height);
  }

  bool _isPositiveFiniteDouble(double value) {
    return value.isFinite && value > 0;
  }

  Future<void> _handleClipboardCopyEvent(Map<String, Object?>? payload) async {
    if (!await allowClipboardCopy()) {
      return;
    }
    if (payload == null) {
      return;
    }
    final raw = _stringFromJsonValue(payload['data']);
    if (raw == null) {
      return;
    }
    final bytes = _decodeOsc52ClipboardPayload(raw);
    if (bytes == null) {
      return;
    }
    final decoded = utf8.decode(bytes, allowMalformed: true);
    await copyToClipboard(decoded);
  }

  Uint8List? _decodeOsc52ClipboardPayload(String raw) {
    final normalized = raw.replaceAll(RegExp(r'\s+'), '');
    try {
      return Uint8List.fromList(base64.decode(normalized));
    } on FormatException {
      return null;
    }
  }

  Future<void> _handleClipboardPasteRequestEvent(
    String sessionId,
    Map<String, Object?>? payload,
  ) async {
    if (!await allowClipboardPasteRequest()) {
      return;
    }
    final selection =
        _nonEmptyTrimmedStringFromJsonValue(payload?['selection']) ?? 'c';
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
    _graphicsCaches.remove(sessionId)?.dispose();
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
      'id': 'runtime-$_wireSessionSeed',
      'name': wireName,
      ...json,
    });
  }

  TerminalSessionConfig _resolveColorsForRuntime(TerminalSessionConfig config) {
    return config.copyWith(
      display: config.display.copyWith(
        colors: config.display.colors.resolveWith(),
      ),
    );
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

Future<bool> _allowClipboardAccess() async => true;

Map<String, Object?>? _tryDecodeJsonObject(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return null;
    }
    return _stringKeyedJsonMap(decoded);
  } on Object {
    return null;
  }
}

Map<String, Object?> _stringKeyedJsonMap(Map<dynamic, dynamic> decoded) {
  final json = <String, Object?>{};
  for (final entry in decoded.entries) {
    final key = entry.key;
    if (key is String) {
      json[key] = entry.value;
    }
  }
  return json;
}

int? _intFromEventPayload(Object? value) {
  return _wholeIntValue(value);
}

int? _wholeIntValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num && value.isFinite) {
    final parsed = value.toInt();
    if (value == parsed) {
      return parsed;
    }
  }
  return null;
}

String? _stringFromJsonValue(Object? value) {
  if (value is String) {
    return value;
  }
  return null;
}

String? _nonEmptyTrimmedStringFromJsonValue(Object? value) {
  final text = _stringFromJsonValue(value)?.trim();
  return text == null || text.isEmpty ? null : text;
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
