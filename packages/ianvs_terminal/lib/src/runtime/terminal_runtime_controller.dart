import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:ianvs_pty/ianvs_pty.dart';

import '../config/terminal_config.dart';
import '../terminal/selection_controller.dart';
import '../terminal/terminal_graphics_cache.dart';
import '../terminal/terminal_graphics_diagnostics.dart';
import '../terminal/terminal_models.dart';
import '../terminal/terminal_viewport.dart';
import 'terminal_benchmarking.dart';
import 'terminal_clipboard_policy.dart';
import 'terminal_diagnostics.dart';
import 'terminal_event_router.dart';
import 'terminal_frame_decoder.dart';
import 'terminal_frame_pump.dart';
import 'terminal_json_request_client.dart';
import 'terminal_refresh_scheduler.dart';
import 'terminal_resize_coordinator.dart';
import 'terminal_session_registry.dart';

export 'terminal_clipboard_policy.dart';
export 'terminal_diagnostics.dart';

const int _maxOsc52ClipboardDecodedBytes = 4 * 1024 * 1024;
const int _maxOsc52ClipboardEncodedLength =
    ((_maxOsc52ClipboardDecodedBytes + 2) ~/ 3) * 4;

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

final class TerminalSessionBackendErrorEvent extends TerminalSessionEvent {
  const TerminalSessionBackendErrorEvent(
    super.sessionId, {
    required this.operation,
    required this.error,
    required this.stackTrace,
  });

  final String operation;
  final Object error;
  final StackTrace stackTrace;
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

final class TerminalSessionShellContextEvent extends TerminalSessionEvent {
  TerminalSessionShellContextEvent(
    super.sessionId, {
    Map<String, Object?>? rawPayload,
  }) : rawPayload = Map.unmodifiable(rawPayload ?? const <String, Object?>{});

  final Map<String, Object?> rawPayload;

  String? get source => _stringValue(rawPayload['source']);
  String? get cwd => _stringValue(rawPayload['cwd']);
  String? get hostname => _stringValue(rawPayload['hostname']);
  String? get username => _stringValue(rawPayload['username']);

  static String? _stringValue(Object? value) {
    return value is String ? value : null;
  }
}

final class TerminalSessionShellCommandEvent extends TerminalSessionEvent {
  TerminalSessionShellCommandEvent(
    super.sessionId, {
    Map<String, Object?>? rawPayload,
  }) : rawPayload = Map.unmodifiable(rawPayload ?? const <String, Object?>{});

  final Map<String, Object?> rawPayload;

  String? get source => _stringValue(rawPayload['source']);
  String? get eventType => _stringValue(rawPayload['eventType']);
  String? get command => _stringValue(rawPayload['command']);
  int? get exitCode => _wholeIntValue(rawPayload['exitCode']);
  int? get timestamp => _wholeIntValue(rawPayload['timestamp']);
  int? get cursorLine => _wholeIntValue(rawPayload['cursorLine']);
  int? get zoneId => _wholeIntValue(rawPayload['zoneId']);
  String? get zoneType => _stringValue(rawPayload['zoneType']);
  int? get absRowStart => _wholeIntValue(rawPayload['absRowStart']);
  int? get absRowEnd => _wholeIntValue(rawPayload['absRowEnd']);

  static String? _stringValue(Object? value) {
    return value is String ? value : null;
  }
}

final class TerminalSessionShellUserVarEvent extends TerminalSessionEvent {
  TerminalSessionShellUserVarEvent(
    super.sessionId, {
    Map<String, Object?>? rawPayload,
  }) : rawPayload = Map.unmodifiable(rawPayload ?? const <String, Object?>{});

  final Map<String, Object?> rawPayload;

  String? get source => _stringValue(rawPayload['source']);
  String? get name => _stringValue(rawPayload['name']);
  String? get value => _stringValue(rawPayload['value']);

  static String? _stringValue(Object? value) {
    return value is String ? value : null;
  }
}

final class TerminalSessionNotificationEvent extends TerminalSessionEvent {
  TerminalSessionNotificationEvent(
    super.sessionId, {
    Map<String, Object?>? rawPayload,
  }) : rawPayload = Map.unmodifiable(rawPayload ?? const <String, Object?>{});

  final Map<String, Object?> rawPayload;

  String? get source => _stringValue(rawPayload['source']);
  String get title => _stringValue(rawPayload['title']) ?? '';
  String get message => _stringValue(rawPayload['message']) ?? '';

  static String? _stringValue(Object? value) {
    return value is String ? value : null;
  }
}

final class TerminalSessionProgressEvent extends TerminalSessionEvent {
  TerminalSessionProgressEvent(
    super.sessionId, {
    Map<String, Object?>? rawPayload,
  }) : rawPayload = Map.unmodifiable(rawPayload ?? const <String, Object?>{});

  final Map<String, Object?> rawPayload;

  String? get source => _stringValue(rawPayload['source']);
  bool get named => rawPayload['named'] == true;
  String? get action => _stringValue(rawPayload['action']);
  String? get id => _stringValue(rawPayload['id']);
  String? get state => _stringValue(rawPayload['state']);
  int? get percent => _wholeIntValue(rawPayload['percent']);
  String? get label => _stringValue(rawPayload['label']);
  bool get active => state != null && state != 'hidden' && action != 'clear';

  static String? _stringValue(Object? value) {
    return value is String ? value : null;
  }
}

final class TerminalSessionBadgeEvent extends TerminalSessionEvent {
  TerminalSessionBadgeEvent(super.sessionId, {Map<String, Object?>? rawPayload})
    : rawPayload = Map.unmodifiable(rawPayload ?? const <String, Object?>{});

  final Map<String, Object?> rawPayload;

  String? get source => _stringValue(rawPayload['source']);
  String? get text => _stringValue(rawPayload['text']);

  static String? _stringValue(Object? value) {
    return value is String ? value : null;
  }
}

final class TerminalSessionClipboardEvent extends TerminalSessionEvent {
  const TerminalSessionClipboardEvent(
    super.sessionId, {
    required this.operation,
    required this.decision,
    this.selection,
    this.byteCount,
    this.characterCount,
    this.textPreview,
    this.textPreviewTruncated = false,
  });

  final TerminalClipboardOperation operation;
  final TerminalClipboardDecision decision;
  final String? selection;
  final int? byteCount;
  final int? characterCount;
  final String? textPreview;
  final bool textPreviewTruncated;

  bool get allowed => decision == TerminalClipboardDecision.allowed;
}

final class _ClipboardTextSummary {
  const _ClipboardTextSummary({
    required this.byteCount,
    required this.characterCount,
    required this.preview,
    required this.previewTruncated,
  });

  final int byteCount;
  final int characterCount;
  final String preview;
  final bool previewTruncated;
}

final class TerminalSessionResizeEvent {
  const TerminalSessionResizeEvent(
    this.sessionId, {
    required this.cols,
    required this.rows,
    required this.pixelWidth,
    required this.pixelHeight,
    this.cellWidth = 0,
    this.cellHeight = 0,
    required this.viewportSize,
    required this.devicePixelRatio,
  });

  final String sessionId;
  final int cols;
  final int rows;
  final int pixelWidth;
  final int pixelHeight;
  final int cellWidth;
  final int cellHeight;
  final Size viewportSize;
  final double devicePixelRatio;
}

final class TerminalSessionInputEvent {
  const TerminalSessionInputEvent(this.sessionId, this.bytes);

  final String sessionId;
  final Uint8List bytes;
}

enum TerminalFrameWireFormatPreference { automatic, json }

class TerminalRuntimeController {
  static const Duration _pollingFrameInterval = Duration(milliseconds: 33);
  static const int _pollingIdleBackoffAfterEmptyRefreshes = 2;
  static const int _pollingIdleBackoffInitialTicks = 3;
  static const int _pollingIdleBackoffMaxTicks = 48;
  static const int _clipboardPreviewRunes = 120;

  TerminalRuntimeController({
    required PtySessionBackend backend,
    required Future<void> Function(String text) copyToClipboard,
    required Future<String> Function() readClipboard,
    Future<bool> Function()? allowClipboardCopy,
    Future<bool> Function()? allowClipboardPasteRequest,
    Future<bool> Function(TerminalClipboardAccessRequest request)?
    allowClipboardCopyWithContext,
    Future<bool> Function(TerminalClipboardAccessRequest request)?
    allowClipboardPasteRequestWithContext,
    TerminalWindowResizeCallback? resizeWindowBy,
    bool enableSessionPolling = true,
    bool enableWarmUpRefresh = false,
    TerminalFrameWireFormatPreference frameWireFormatPreference =
        TerminalFrameWireFormatPreference.automatic,
    TerminalBenchmarkEventSink? benchmarkEventSink,
  }) : this.withClipboardPolicy(
         backend: backend,
         copyToClipboard: copyToClipboard,
         readClipboard: readClipboard,
         clipboardPolicy: TerminalClipboardPolicyAdapter(
           allowClipboardCopy: allowClipboardCopy,
           allowClipboardPasteRequest: allowClipboardPasteRequest,
           allowClipboardCopyWithContext: allowClipboardCopyWithContext,
           allowClipboardPasteRequestWithContext:
               allowClipboardPasteRequestWithContext,
         ),
         resizeWindowBy: resizeWindowBy,
         enableSessionPolling: enableSessionPolling,
         enableWarmUpRefresh: enableWarmUpRefresh,
         frameWireFormatPreference: frameWireFormatPreference,
         benchmarkEventSink: benchmarkEventSink,
       );

  TerminalRuntimeController.withClipboardPolicy({
    required PtySessionBackend backend,
    required this.copyToClipboard,
    required this.readClipboard,
    required TerminalClipboardPolicyAdapter clipboardPolicy,
    this.resizeWindowBy,
    this.enableSessionPolling = true,
    this.enableWarmUpRefresh = false,
    this.frameWireFormatPreference =
        TerminalFrameWireFormatPreference.automatic,
    this.benchmarkEventSink,
  }) : _backend = backend,
       allowClipboardCopy = clipboardPolicy.allowCopy,
       allowClipboardPasteRequest = clipboardPolicy.allowPasteRequest {
    _diagnosticsClient = TerminalDiagnosticsClient.fromBackend(
      backend,
      onRequestError: _emitBackendRequestError,
    );
    _jsonRequestClient = TerminalJsonRequestClient.fromBackend(
      backend,
      onRequestError: _emitBackendRequestError,
    );
    _sessions = TerminalSessionRegistry(
      loadGraphicAsset: loadGraphicAsset,
      diagnosticEventSink: benchmarkEventSink,
    );
    _frameDecoder = TerminalFrameDecoder(
      collectMetrics: benchmarkEventSink != null,
    );
  }

  final PtySessionBackend _backend;
  late final TerminalDiagnosticsClient _diagnosticsClient;
  late final TerminalJsonRequestClient _jsonRequestClient;
  final TerminalEventRouter _eventRouter = const TerminalEventRouter();
  late final TerminalSessionRegistry _sessions;
  late final TerminalFrameDecoder _frameDecoder;
  final Future<void> Function(String text) copyToClipboard;
  final Future<String> Function() readClipboard;
  final Future<bool> Function(TerminalClipboardAccessRequest request)
  allowClipboardCopy;
  final Future<bool> Function(TerminalClipboardAccessRequest request)
  allowClipboardPasteRequest;
  final TerminalWindowResizeCallback? resizeWindowBy;
  final bool enableSessionPolling;
  final bool enableWarmUpRefresh;
  final TerminalFrameWireFormatPreference frameWireFormatPreference;
  final TerminalBenchmarkEventSink? benchmarkEventSink;

  final TerminalResizeCoordinator _resizeCoordinator =
      TerminalResizeCoordinator();
  final TerminalRefreshScheduler _refreshScheduler = TerminalRefreshScheduler();
  final Map<String, List<Timer>> _warmUpTimers = <String, List<Timer>>{};
  final TerminalFramePumpBackoff _framePumpBackoff = TerminalFramePumpBackoff(
    emptyRefreshesBeforeBackoff: _pollingIdleBackoffAfterEmptyRefreshes,
    initialSkipTicks: _pollingIdleBackoffInitialTicks,
    maxSkipTicks: _pollingIdleBackoffMaxTicks,
  );
  final Map<String, DateTime> _lastFrameAppliedAt = <String, DateTime>{};
  final StreamController<TerminalSessionEvent> _events =
      StreamController<TerminalSessionEvent>.broadcast();
  final StreamController<TerminalSessionInputEvent> _inputEvents =
      StreamController<TerminalSessionInputEvent>.broadcast();
  final StreamController<TerminalSessionResizeEvent> _resizeEvents =
      StreamController<TerminalSessionResizeEvent>.broadcast();
  final Map<TerminalFrameDiff, TerminalFrameDecodeMetrics>
  _decodedFrameBenchmarkMetrics =
      <TerminalFrameDiff, TerminalFrameDecodeMetrics>{};
  Timer? _pollTimer;
  int _wireSessionSeed = 0;
  int _benchmarkFrameId = 0;

  Stream<TerminalSessionEvent> get events => _events.stream;
  Stream<TerminalSessionInputEvent> get inputEvents => _inputEvents.stream;
  Stream<TerminalSessionResizeEvent> get resizeEvents => _resizeEvents.stream;

  TerminalViewportController viewportFor(String sessionId) {
    return _sessions.viewportFor(sessionId);
  }

  TerminalGraphicsCache graphicsCacheFor(String sessionId) {
    return _sessions.graphicsCacheFor(sessionId);
  }

  bool hasSession(String sessionId) => _sessions.hasSession(sessionId);

  String createSession(TerminalSessionConfig config) {
    final sessionId = _backend.createSession(
      _encodeNativeSessionConfig(_resolveColorsForRuntime(config)),
    );
    _sessions.register(sessionId);
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
    if (!_runBackendOperation(
      sessionId,
      'closeSession',
      () => _backend.closeSession(sessionId),
    )) {
      return;
    }
    _removeSessionState(sessionId);
  }

  void sendInput(String sessionId, Uint8List bytes) {
    _sendInput(sessionId, bytes);
  }

  bool _sendInput(String sessionId, Uint8List bytes) {
    if (!hasSession(sessionId)) {
      return false;
    }
    final copiedBytes = Uint8List.fromList(bytes);
    if (copiedBytes.isNotEmpty) {
      if (!_scrollToLiveCursorIfNeeded(sessionId)) {
        return false;
      }
    }
    if (!_runBackendOperation(
      sessionId,
      'writeInput',
      () => _backend.writeInput(sessionId, copiedBytes),
    )) {
      return false;
    }
    _inputEvents.add(TerminalSessionInputEvent(sessionId, copiedBytes));
    _resetPollingIdleBackoff(sessionId);
    _refreshSessionIfNeeded(sessionId);
    return true;
  }

  bool _scrollToLiveCursorIfNeeded(String sessionId) {
    final frame = viewportFor(sessionId).frame;
    if (frame.scrollbackOffset <= 0) {
      return true;
    }
    return _runBackendOperation(
      sessionId,
      'scrollViewportTo',
      () => _backend.scrollViewportTo(sessionId, 0),
    );
  }

  void scrollViewport(String sessionId, int deltaLines) {
    if (!hasSession(sessionId)) {
      return;
    }
    if (!_runBackendOperation(
      sessionId,
      'scrollViewport',
      () => _backend.scrollViewport(sessionId, deltaLines),
    )) {
      return;
    }
    _resetPollingIdleBackoff(sessionId);
    _refreshSessionIfNeeded(sessionId);
  }

  void scrollViewportTo(String sessionId, int offset) {
    if (!hasSession(sessionId)) {
      return;
    }
    if (!_runBackendOperation(
      sessionId,
      'scrollViewportTo',
      () => _backend.scrollViewportTo(sessionId, offset),
    )) {
      return;
    }
    _resetPollingIdleBackoff(sessionId);
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
    if (!_runBackendOperation(
      sessionId,
      'scrollViewportTo',
      () => _backend.scrollViewportTo(sessionId, scrollbackOffset),
    )) {
      return;
    }
    _resetPollingIdleBackoff(sessionId);
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
    final PtyGraphicAsset? nativeAsset;
    try {
      nativeAsset = graphicBackend.loadGraphicAsset(
        sessionId,
        assetId: key.id,
        assetVersion: key.version,
      );
    } on Object catch (error, stackTrace) {
      _emitBackendRequestError(
        sessionId,
        'loadGraphicAsset',
        error,
        stackTrace,
      );
      return null;
    }
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
    final text = _jsonRequestClient.selectionText(
      sessionId,
      selection,
      block: block,
    );
    if (text != null) {
      return text;
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
    return _jsonRequestClient.searchTextResult(sessionId, query, mode: mode);
  }

  List<TerminalSearchMatch> searchText(
    String sessionId,
    String query, {
    TerminalSearchMode mode = TerminalSearchMode.smartCaseSubstring,
  }) {
    return searchTextResult(sessionId, query, mode: mode).matches;
  }

  bool clearScrollback(String sessionId) {
    if (!hasSession(sessionId)) {
      return false;
    }
    if (!_jsonRequestClient.clearScrollback(sessionId)) {
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
    return _jsonRequestClient.exportScrollbackText(
      sessionId,
      maxLines: maxLines,
    );
  }

  TerminalDiagnosticsExport? exportSessionDiagnostics(
    String sessionId, {
    TerminalDiagnosticsPolicy policy = const TerminalDiagnosticsPolicy(),
  }) {
    if (!hasSession(sessionId)) {
      return null;
    }
    return _diagnosticsClient.exportSession(sessionId, policy: policy);
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

  bool resizeSession(
    String sessionId,
    Size viewportSize,
    double devicePixelRatio,
  ) {
    if (!hasSession(sessionId)) {
      return false;
    }
    final plan = _resizeCoordinator.planViewportResize(
      sessionId,
      viewportSize: viewportSize,
      devicePixelRatio: devicePixelRatio,
      cellSize: _cellSizeFor(sessionId),
    );
    if (plan == null) {
      return false;
    }
    if (plan.isDuplicate) {
      return true;
    }
    final metric = plan.metric;
    if (!_runBackendOperation(
      sessionId,
      'resizeSession',
      () => _backend.resizeSession(
        sessionId,
        cols: metric.cols,
        rows: metric.rows,
        pixelWidth: metric.pixelWidth,
        pixelHeight: metric.pixelHeight,
        cellWidth: metric.cellWidth,
        cellHeight: metric.cellHeight,
      ),
    )) {
      return false;
    }
    _resizeCoordinator.commit(sessionId, metric);
    _resizeEvents.add(
      TerminalSessionResizeEvent(
        sessionId,
        cols: metric.cols,
        rows: metric.rows,
        pixelWidth: metric.pixelWidth,
        pixelHeight: metric.pixelHeight,
        cellWidth: metric.cellWidth,
        cellHeight: metric.cellHeight,
        viewportSize: plan.viewportSize,
        devicePixelRatio: metric.devicePixelRatio,
      ),
    );
    _requestRefreshAfterResize(sessionId);
    return true;
  }

  bool resizeSessionCells(
    String sessionId, {
    required int cols,
    required int rows,
    double devicePixelRatio = 1,
    Size? cellSize,
  }) {
    if (!hasSession(sessionId)) {
      return false;
    }
    final plan = _resizeCoordinator.planCellResize(
      sessionId,
      cols: cols,
      rows: rows,
      devicePixelRatio: devicePixelRatio,
      cellSize: cellSize ?? _cellSizeFor(sessionId),
    );
    if (plan.isDuplicate) {
      return true;
    }
    final metric = plan.metric;
    if (!_runBackendOperation(
      sessionId,
      'resizeSession',
      () => _backend.resizeSession(
        sessionId,
        cols: metric.cols,
        rows: metric.rows,
        pixelWidth: metric.pixelWidth,
        pixelHeight: metric.pixelHeight,
        cellWidth: metric.cellWidth,
        cellHeight: metric.cellHeight,
      ),
    )) {
      return false;
    }
    _resizeCoordinator.commit(sessionId, metric);
    _resizeEvents.add(
      TerminalSessionResizeEvent(
        sessionId,
        cols: metric.cols,
        rows: metric.rows,
        pixelWidth: metric.pixelWidth,
        pixelHeight: metric.pixelHeight,
        cellWidth: metric.cellWidth,
        cellHeight: metric.cellHeight,
        viewportSize: plan.viewportSize,
        devicePixelRatio: metric.devicePixelRatio,
      ),
    );
    _requestRefreshAfterResize(sessionId);
    return true;
  }

  void _startPolling() {
    _pollTimer ??= Timer.periodic(_pollingFrameInterval, (_) {
      for (final sessionId in _sessions.sessionIds) {
        _requestPollingRefreshSession(sessionId);
      }
    });
  }

  void _requestPollingRefreshSession(String sessionId) {
    if (_framePumpBackoff.shouldSkipPollingRefresh(sessionId)) {
      return;
    }
    _requestRefreshSession(sessionId);
  }

  void _requestRefreshSession(String sessionId, {bool immediate = false}) {
    if (!hasSession(sessionId)) {
      return;
    }
    if (enableSessionPolling && !immediate) {
      _requestThrottledRefreshSession(sessionId);
      return;
    }
    _requestUnthrottledRefreshSession(sessionId, immediate: immediate);
  }

  void _requestUnthrottledRefreshSession(
    String sessionId, {
    bool immediate = false,
  }) {
    if (!hasSession(sessionId)) {
      return;
    }
    if (immediate) {
      _refreshScheduler.cancelCooldown(sessionId);
    }
    if (_refreshScheduler.isRefreshing(sessionId)) {
      _refreshScheduler.queueRefresh(sessionId);
      return;
    }
    if (!immediate) {
      if (!_refreshScheduler.scheduleDeferredRefresh(sessionId, () {
        _requestRefreshSession(sessionId, immediate: true);
      })) {
        return;
      }
      return;
    }
    unawaited(_refreshSession(sessionId));
  }

  void _requestThrottledRefreshSession(String sessionId) {
    if (!hasSession(sessionId)) {
      return;
    }
    if (_refreshScheduler.isRefreshing(sessionId)) {
      _refreshScheduler.queueRefresh(sessionId);
      return;
    }
    if (_refreshScheduler.hasCooldown(sessionId)) {
      _refreshScheduler.queueRefresh(sessionId);
      return;
    }
    _requestUnthrottledRefreshSession(sessionId, immediate: true);
  }

  Future<void> _refreshSession(String sessionId) async {
    if (enableSessionPolling) {
      await _refreshSessionOnce(sessionId);
      return;
    }
    await _refreshSessionDraining(sessionId);
  }

  Future<void> _refreshSessionOnce(String sessionId) async {
    if (!hasSession(sessionId)) {
      return;
    }

    _refreshScheduler.markRefreshing(sessionId);
    try {
      final pendingFrames = <TerminalFrameDiff>[];
      _refreshScheduler.consumeQueuedRefresh(sessionId);
      var receivedFrame = false;

      final frame = _takeFrameDiff(sessionId);
      if (frame != null) {
        receivedFrame = true;
        _queuePendingFrame(sessionId, pendingFrames, frame);
      }

      final events = _eventsForSession(
        sessionId,
        _pollBackendEvents(sessionId),
      );
      final shouldApplyBeforeEvents =
          pendingFrames.isNotEmpty &&
          (!_eventsDelayFrame(events) || _eventsContainExit(events));
      if (shouldApplyBeforeEvents) {
        _applyPendingFrames(sessionId, pendingFrames);
      }

      final eventProcessing = _processEvents(sessionId, events);
      if (eventProcessing != null) {
        await eventProcessing;
      }
      if (!hasSession(sessionId)) {
        return;
      }

      if (pendingFrames.isNotEmpty) {
        _applyPendingFrames(sessionId, pendingFrames);
      }
      _recordPollingRefreshResult(
        sessionId,
        hadActivity: receivedFrame || events.isNotEmpty,
      );
    } finally {
      _refreshScheduler.clearRefreshing(sessionId);
      if (_refreshScheduler.consumeQueuedRefresh(sessionId) &&
          hasSession(sessionId)) {
        _requestRefreshSession(sessionId);
      }
    }
  }

  Future<void> _refreshSessionDraining(String sessionId) async {
    if (!hasSession(sessionId)) {
      return;
    }

    _refreshScheduler.markRefreshing(sessionId);
    try {
      var runAgain = true;
      final pendingFrames = <TerminalFrameDiff>[];
      var skippedQueuedFrames = 0;
      while (runAgain && hasSession(sessionId)) {
        _refreshScheduler.consumeQueuedRefresh(sessionId);
        runAgain = false;

        final frame = _takeFrameDiff(sessionId);
        if (frame != null) {
          _queuePendingFrame(sessionId, pendingFrames, frame);
        }

        final events = _eventsForSession(
          sessionId,
          _pollBackendEvents(sessionId),
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

        runAgain = _refreshScheduler.consumeQueuedRefresh(sessionId);
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
      _refreshScheduler.clearRefreshing(sessionId);
      if (_refreshScheduler.consumeQueuedRefresh(sessionId) &&
          hasSession(sessionId)) {
        _requestRefreshSession(sessionId);
      }
    }
  }

  void _refreshSessionIfNeeded(String sessionId) {
    _requestRefreshSession(sessionId);
  }

  bool _runBackendOperation(
    String sessionId,
    String operation,
    void Function() run,
  ) {
    try {
      run();
      return true;
    } on Object catch (error, stackTrace) {
      _events.add(
        TerminalSessionBackendErrorEvent(
          sessionId,
          operation: operation,
          error: error,
          stackTrace: stackTrace,
        ),
      );
      return false;
    }
  }

  String? _takeFrameDiffJson(String sessionId) {
    try {
      return _backend.takeFrameDiffJson(sessionId);
    } on Object catch (error, stackTrace) {
      _emitBackendRequestError(
        sessionId,
        'takeFrameDiffJson',
        error,
        stackTrace,
      );
      return null;
    }
  }

  List<PtyEvent> _pollBackendEvents(String sessionId) {
    try {
      return _backend.pollEvents(sessionId);
    } on Object catch (error, stackTrace) {
      _emitBackendRequestError(sessionId, 'pollEvents', error, stackTrace);
      return const <PtyEvent>[];
    }
  }

  void _emitBackendRequestError(
    String sessionId,
    String operation,
    Object error,
    StackTrace stackTrace,
  ) {
    _events.add(
      TerminalSessionBackendErrorEvent(
        sessionId,
        operation: operation,
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  void _requestRefreshAfterResize(String sessionId) {
    _resetPollingIdleBackoff(sessionId);
    _requestRefreshSession(sessionId, immediate: !enableSessionPolling);
  }

  void _applyFrame(
    String sessionId,
    TerminalFrameDiff frame, {
    int pendingFramesBefore = 0,
    int pendingFramesAfter = 0,
  }) {
    final decodedMetrics = _decodedFrameBenchmarkMetrics.remove(frame);
    final applyWatch = benchmarkEventSink == null
        ? null
        : (Stopwatch()..start());
    final viewport = viewportFor(sessionId);
    viewport.updateFrame(frame);
    applyWatch?.stop();
    _lastFrameAppliedAt[sessionId] = DateTime.now();
    _startPollingCooldown(sessionId);
    _events.add(TerminalSessionFrameEvent(sessionId, frame));
    _emitGraphicsDiagnostic(
      sessionId,
      event: 'frame_applied',
      frame: frame,
      fields: <String, Object?>{
        'pending_frames_before': pendingFramesBefore,
        'pending_frames_after': pendingFramesAfter,
        'applied_graphics_count': viewport.frame.graphics.length,
        'applied_graphics_signature': terminalGraphicsSignature(
          viewport.frame.graphics,
        ),
      },
    );
    _emitRuntimeBenchmarkEvent(
      sessionId: sessionId,
      frame: frame,
      appliedFrame: viewport.frame,
      decodedMetrics: decodedMetrics,
      applyFrameMicros: applyWatch?.elapsedMicroseconds ?? 0,
      pendingFramesBefore: pendingFramesBefore,
      pendingFramesAfter: pendingFramesAfter,
    );
  }

  void _startPollingCooldown(String sessionId) {
    if (!enableSessionPolling || !hasSession(sessionId)) {
      return;
    }
    _refreshScheduler.startCooldown(sessionId, _pollingFrameInterval, () {
      if (hasSession(sessionId)) {
        _requestThrottledRefreshSession(sessionId);
      }
    });
  }

  void _recordPollingRefreshResult(
    String sessionId, {
    required bool hadActivity,
  }) {
    if (!enableSessionPolling || !hasSession(sessionId)) {
      return;
    }
    if (hadActivity) {
      _resetPollingIdleBackoff(sessionId);
      return;
    }
    _framePumpBackoff.recordRefreshResult(sessionId, hadActivity: false);
  }

  void _resetPollingIdleBackoff(String sessionId) {
    _framePumpBackoff.reset(sessionId);
  }

  TerminalFrameDiff? _takeFrameDiff(String sessionId) {
    if (frameWireFormatPreference == TerminalFrameWireFormatPreference.json) {
      final rawFrame = _takeFrameDiffJson(sessionId);
      if (rawFrame == null || rawFrame.isEmpty) {
        return null;
      }
      return _decodeJsonFrame(sessionId, rawFrame);
    }

    final backend = _backend;
    final protobufBackend = backend is PtySessionProtobufFrameBackend
        ? backend as PtySessionProtobufFrameBackend
        : null;
    if (protobufBackend != null && protobufBackend.supportsProtobufFrameDiffs) {
      final protobufBytes = _takeFrameDiffProtobuf(sessionId, protobufBackend);
      if (protobufBytes == null || protobufBytes.isEmpty) {
        return null;
      }
      return _decodeProtobufFrame(sessionId, protobufBytes);
    }

    final rawFrame = _takeFrameDiffJson(sessionId);
    if (rawFrame == null || rawFrame.isEmpty) {
      return null;
    }
    return _decodeJsonFrame(sessionId, rawFrame);
  }

  Uint8List? _takeFrameDiffProtobuf(
    String sessionId,
    PtySessionProtobufFrameBackend backend,
  ) {
    try {
      return backend.takeFrameDiffProtobuf(sessionId);
    } on Object catch (error, stackTrace) {
      _emitBackendRequestError(
        sessionId,
        'takeFrameDiffProtobuf',
        error,
        stackTrace,
      );
      return null;
    }
  }

  TerminalFrameDiff? _decodeJsonFrame(String sessionId, String rawFrame) {
    final decoded = _frameDecoder.decode(rawFrame);
    if (decoded == null) {
      return null;
    }
    final metrics = decoded.metrics;
    if (metrics != null) {
      _decodedFrameBenchmarkMetrics[decoded.frame] = TerminalFrameDecodeMetrics(
        rawFrameBytes: metrics.rawFrameBytes,
        wireFormat: 'json',
        jsonDecodeMicros: metrics.jsonDecodeMicros,
        protobufDecodeMicros: 0,
        nativeFrameStats: _takeNativeFrameDebugStats(sessionId),
      );
    }
    return decoded.frame;
  }

  TerminalFrameDiff? _decodeProtobufFrame(
    String sessionId,
    Uint8List rawFrame,
  ) {
    final decodeWatch = benchmarkEventSink == null
        ? null
        : (Stopwatch()..start());
    try {
      final frame = TerminalFrameDiff.fromProtobufBytes(rawFrame);
      decodeWatch?.stop();
      if (benchmarkEventSink != null) {
        _decodedFrameBenchmarkMetrics[frame] = TerminalFrameDecodeMetrics(
          rawFrameBytes: rawFrame.length,
          wireFormat: 'protobuf',
          jsonDecodeMicros: 0,
          protobufDecodeMicros: decodeWatch?.elapsedMicroseconds ?? 0,
          nativeFrameStats: _takeNativeFrameDebugStats(sessionId),
        );
      }
      return frame;
    } on Object {
      return null;
    }
  }

  Map<String, Object?> _takeNativeFrameDebugStats(String sessionId) {
    final backend = _backend;
    final diagnosticsBackend = backend is PtySessionDiagnosticsBackend
        ? backend as PtySessionDiagnosticsBackend
        : null;
    if (diagnosticsBackend == null) {
      return const <String, Object?>{};
    }
    final raw = diagnosticsBackend.takeDiagnosticsJson(sessionId, 'frame');
    if (raw == null || raw.isEmpty) {
      return const <String, Object?>{};
    }
    final decoded = _tryDecodeJsonObject(raw);
    if (decoded == null) {
      return const <String, Object?>{};
    }
    return decoded;
  }

  void _queuePendingFrame(
    String sessionId,
    List<TerminalFrameDiff> pendingFrames,
    TerminalFrameDiff frame,
  ) {
    if (frame.modes.synchronizedOutput) {
      _decodedFrameBenchmarkMetrics.remove(frame);
      _emitGraphicsDiagnostic(
        sessionId,
        event: 'frame_skipped_synchronized',
        frame: frame,
        fields: <String, Object?>{
          'applied_graphics_count': viewportFor(
            sessionId,
          ).frame.graphics.length,
          'applied_graphics_signature': terminalGraphicsSignature(
            viewportFor(sessionId).frame.graphics,
          ),
        },
      );
      return;
    }
    if (frame.frameKind == TerminalFrameKind.snapshot) {
      pendingFrames.clear();
    }
    pendingFrames.add(frame);
  }

  void _emitGraphicsDiagnostic(
    String sessionId, {
    required String event,
    required TerminalFrameDiff frame,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    emitTerminalGraphicsDiagnostic(
      benchmarkEventSink,
      layer: 'runtime',
      event: event,
      sessionId: sessionId,
      graphics: frame.graphics,
      fields: <String, Object?>{
        'frame_kind': frame.frameKind.name,
        'synchronized_output': frame.modes.synchronizedOutput,
        'incoming_graphics_count': frame.graphics.length,
        'incoming_graphics_signature': terminalGraphicsSignature(
          frame.graphics,
        ),
        ...fields,
      },
    );
  }

  void _applyPendingFrames(
    String sessionId,
    List<TerminalFrameDiff> pendingFrames,
  ) {
    for (var index = 0; index < pendingFrames.length; index += 1) {
      _applyFrame(
        sessionId,
        pendingFrames[index],
        pendingFramesBefore: pendingFrames.length - index,
        pendingFramesAfter: pendingFrames.length - index - 1,
      );
    }
    pendingFrames.clear();
  }

  void _emitRuntimeBenchmarkEvent({
    required String sessionId,
    required TerminalFrameDiff frame,
    required TerminalFrameDiff appliedFrame,
    required TerminalFrameDecodeMetrics? decodedMetrics,
    required int applyFrameMicros,
    required int pendingFramesBefore,
    required int pendingFramesAfter,
  }) {
    final sink = benchmarkEventSink;
    if (sink == null) {
      return;
    }
    _benchmarkFrameId += 1;
    sink(<String, Object?>{
      'schema_version': 'ianvs-bench-dart-runtime-v1',
      'timestamp_micros': DateTime.now().microsecondsSinceEpoch,
      'session_id': sessionId,
      'frame_id': _benchmarkFrameId,
      'raw_frame_bytes': decodedMetrics?.rawFrameBytes ?? 0,
      'wire_format': decodedMetrics?.wireFormat ?? 'unknown',
      'frame_kind': frame.frameKind.name,
      'json_decode_micros': decodedMetrics?.jsonDecodeMicros ?? 0,
      'protobuf_decode_micros': decodedMetrics?.protobufDecodeMicros ?? 0,
      'native_frame_build_micros':
          _wholeIntValue(
            decodedMetrics?.nativeFrameStats['frame_build_micros'],
          ) ??
          0,
      'native_json_encode_micros':
          _wholeIntValue(
            decodedMetrics?.nativeFrameStats['json_encode_micros'],
          ) ??
          0,
      'native_protobuf_encode_micros':
          _wholeIntValue(
            decodedMetrics?.nativeFrameStats['protobuf_encode_micros'],
          ) ??
          0,
      'native_rows_scanned':
          _wholeIntValue(decodedMetrics?.nativeFrameStats['rows_scanned']) ?? 0,
      'native_rows_emitted':
          _wholeIntValue(decodedMetrics?.nativeFrameStats['rows_emitted']) ?? 0,
      'apply_frame_micros': applyFrameMicros,
      'pending_frames_before': pendingFramesBefore,
      'pending_frames_after': pendingFramesAfter,
      'queued_refresh_count': _refreshScheduler.hasQueuedRefresh(sessionId)
          ? 1
          : 0,
      'events_processed': 0,
      'viewport_hash_after_apply': terminalBenchmarkViewportHash(appliedFrame),
    });
  }

  bool _eventsContainExit(List<PtyEvent> events) {
    for (final event in events) {
      if (_eventRouter.route(event) is TerminalExitEventRoute) {
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
      final route = _eventRouter.route(event);
      if (route is TerminalAsyncEventRoute &&
          route.kind == TerminalAsyncEventKind.resize) {
        return true;
      }
    }
    return false;
  }

  Future<void>? _processEvents(String sessionId, List<PtyEvent> events) {
    Future<void>? pendingAsyncWork;
    for (final event in events) {
      final route = _eventRouter.route(event);
      if (route is TerminalExitEventRoute) {
        if (pendingAsyncWork == null) {
          _removeSessionState(sessionId);
          _events.add(
            TerminalSessionExitEvent(sessionId, exitCode: route.exitCode),
          );
          return null;
        }
        return pendingAsyncWork.then((_) {
          _removeSessionState(sessionId);
          _events.add(
            TerminalSessionExitEvent(sessionId, exitCode: route.exitCode),
          );
        });
      }
      if (route is TerminalAsyncEventRoute) {
        pendingAsyncWork = _chainAsyncEvent(
          pendingAsyncWork,
          () => _handleAsyncEventRoute(sessionId, route),
        );
        continue;
      }
      if (route is TerminalImmediateEventRoute) {
        _emitImmediateEventRoute(sessionId, route);
      }
    }
    return pendingAsyncWork;
  }

  Future<void> _handleAsyncEventRoute(
    String sessionId,
    TerminalAsyncEventRoute route,
  ) {
    return switch (route.kind) {
      TerminalAsyncEventKind.resize => _handleResizeEvent(
        sessionId,
        route.payload,
      ),
      TerminalAsyncEventKind.clipboardCopy => _handleClipboardCopyEvent(
        sessionId,
        route.payload,
      ),
      TerminalAsyncEventKind.clipboardPasteRequest =>
        _handleClipboardPasteRequestEvent(sessionId, route.payload),
    };
  }

  void _emitImmediateEventRoute(
    String sessionId,
    TerminalImmediateEventRoute route,
  ) {
    switch (route.kind) {
      case TerminalImmediateEventKind.bell:
        _events.add(TerminalSessionBellEvent(sessionId));
      case TerminalImmediateEventKind.shellHook:
        _events.add(
          TerminalSessionShellHookEvent(sessionId, rawPayload: route.payload),
        );
      case TerminalImmediateEventKind.shellContext:
        _events.add(
          TerminalSessionShellContextEvent(
            sessionId,
            rawPayload: route.payload,
          ),
        );
      case TerminalImmediateEventKind.shellCommand:
        _events.add(
          TerminalSessionShellCommandEvent(
            sessionId,
            rawPayload: route.payload,
          ),
        );
      case TerminalImmediateEventKind.shellUserVar:
        _events.add(
          TerminalSessionShellUserVarEvent(
            sessionId,
            rawPayload: route.payload,
          ),
        );
      case TerminalImmediateEventKind.sessionNotification:
        _events.add(
          TerminalSessionNotificationEvent(
            sessionId,
            rawPayload: route.payload,
          ),
        );
      case TerminalImmediateEventKind.sessionProgress:
        _events.add(
          TerminalSessionProgressEvent(sessionId, rawPayload: route.payload),
        );
      case TerminalImmediateEventKind.sessionBadge:
        _events.add(
          TerminalSessionBadgeEvent(sessionId, rawPayload: route.payload),
        );
    }
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
    if (cols == null || rows == null) {
      return;
    }
    final plan = _resizeCoordinator.planNativeResizeEvent(
      sessionId,
      cols: cols,
      rows: rows,
      cellSize: _cellSizeFor(sessionId),
    );
    if (plan == null) {
      return;
    }

    final metric = plan.metric;
    if (!_runBackendOperation(
      sessionId,
      'resizeSession',
      () => _backend.resizeSession(
        sessionId,
        cols: metric.cols,
        rows: metric.rows,
        pixelWidth: metric.pixelWidth,
        pixelHeight: metric.pixelHeight,
        cellWidth: metric.cellWidth,
        cellHeight: metric.cellHeight,
      ),
    )) {
      return;
    }
    _resizeCoordinator.commit(sessionId, metric);
    _resizeEvents.add(
      TerminalSessionResizeEvent(
        sessionId,
        cols: metric.cols,
        rows: metric.rows,
        pixelWidth: metric.pixelWidth,
        pixelHeight: metric.pixelHeight,
        cellWidth: metric.cellWidth,
        cellHeight: metric.cellHeight,
        viewportSize: plan.viewportSize,
        devicePixelRatio: metric.devicePixelRatio,
      ),
    );
    _requestRefreshAfterResize(sessionId);

    if (plan.widthDelta == 0 && plan.heightDelta == 0) {
      return;
    }

    await resizeWindowBy?.call(
      widthDelta: plan.widthDelta,
      heightDelta: plan.heightDelta,
    );
  }

  Size _cellSizeFor(String sessionId) {
    return viewportFor(sessionId).measuredCellSize ?? terminalFallbackCellSize;
  }

  Future<void> _handleClipboardCopyEvent(
    String sessionId,
    Map<String, Object?>? payload,
  ) async {
    final selection = _nonEmptyTrimmedStringFromJsonValue(
      payload?['selection'],
    );
    if (payload == null) {
      _events.add(
        TerminalSessionClipboardEvent(
          sessionId,
          operation: TerminalClipboardOperation.copy,
          decision: TerminalClipboardDecision.invalidPayload,
          selection: selection,
        ),
      );
      return;
    }
    final raw = _stringFromJsonValue(payload['data']);
    if (raw == null) {
      _events.add(
        TerminalSessionClipboardEvent(
          sessionId,
          operation: TerminalClipboardOperation.copy,
          decision: TerminalClipboardDecision.invalidPayload,
          selection: selection,
        ),
      );
      return;
    }
    final bytes = _decodeOsc52ClipboardPayload(raw);
    if (bytes == null) {
      _events.add(
        TerminalSessionClipboardEvent(
          sessionId,
          operation: TerminalClipboardOperation.copy,
          decision: TerminalClipboardDecision.invalidPayload,
          selection: selection,
        ),
      );
      return;
    }
    late final String decoded;
    try {
      decoded = utf8.decode(bytes);
    } on FormatException {
      _events.add(
        TerminalSessionClipboardEvent(
          sessionId,
          operation: TerminalClipboardOperation.copy,
          decision: TerminalClipboardDecision.invalidPayload,
          selection: selection,
        ),
      );
      return;
    }
    final summary = _summarizeClipboardText(decoded, byteCount: bytes.length);
    final request = TerminalClipboardAccessRequest(
      sessionId: sessionId,
      operation: TerminalClipboardOperation.copy,
      selection: selection,
      byteCount: summary.byteCount,
      characterCount: summary.characterCount,
      textPreview: summary.preview,
      textPreviewTruncated: summary.previewTruncated,
    );
    if (!await allowClipboardCopy(request)) {
      _events.add(
        TerminalSessionClipboardEvent(
          sessionId,
          operation: TerminalClipboardOperation.copy,
          decision: TerminalClipboardDecision.blocked,
          selection: selection,
          byteCount: summary.byteCount,
          characterCount: summary.characterCount,
          textPreview: summary.preview,
          textPreviewTruncated: summary.previewTruncated,
        ),
      );
      return;
    }
    await copyToClipboard(decoded);
    _events.add(
      TerminalSessionClipboardEvent(
        sessionId,
        operation: TerminalClipboardOperation.copy,
        decision: TerminalClipboardDecision.allowed,
        selection: selection,
        byteCount: summary.byteCount,
        characterCount: summary.characterCount,
        textPreview: summary.preview,
        textPreviewTruncated: summary.previewTruncated,
      ),
    );
  }

  Uint8List? _decodeOsc52ClipboardPayload(String raw) {
    final normalized = _normalizedBoundedBase64Payload(raw);
    if (normalized == null) {
      return null;
    }
    try {
      final bytes = Uint8List.fromList(base64.decode(normalized));
      return bytes.length > _maxOsc52ClipboardDecodedBytes ? null : bytes;
    } on FormatException {
      return null;
    }
  }

  String? _normalizedBoundedBase64Payload(String raw) {
    final buffer = StringBuffer();
    for (var index = 0; index < raw.length; index += 1) {
      final codeUnit = raw.codeUnitAt(index);
      if (_isAsciiWhitespace(codeUnit)) {
        continue;
      }
      buffer.writeCharCode(codeUnit);
      if (buffer.length > _maxOsc52ClipboardEncodedLength) {
        return null;
      }
    }
    return buffer.toString();
  }

  bool _isAsciiWhitespace(int codeUnit) {
    return codeUnit == 0x09 ||
        codeUnit == 0x0a ||
        codeUnit == 0x0b ||
        codeUnit == 0x0c ||
        codeUnit == 0x0d ||
        codeUnit == 0x20;
  }

  Future<void> _handleClipboardPasteRequestEvent(
    String sessionId,
    Map<String, Object?>? payload,
  ) async {
    final selection =
        _nonEmptyTrimmedStringFromJsonValue(payload?['selection']) ?? 'c';
    String? resolvedClipboardText;
    Future<String> resolveClipboardText() async {
      final cached = resolvedClipboardText;
      if (cached != null) {
        return cached;
      }
      final clipboardText = await readClipboard();
      resolvedClipboardText = clipboardText;
      return clipboardText;
    }

    final request = TerminalClipboardAccessRequest(
      sessionId: sessionId,
      operation: TerminalClipboardOperation.pasteRequest,
      selection: selection,
      resolveText: resolveClipboardText,
    );
    if (!await allowClipboardPasteRequest(request)) {
      _events.add(
        TerminalSessionClipboardEvent(
          sessionId,
          operation: TerminalClipboardOperation.pasteRequest,
          decision: TerminalClipboardDecision.blocked,
          selection: selection,
        ),
      );
      return;
    }
    final clipboardText = await resolveClipboardText();
    final clipboardBytes = _boundedUtf8Encode(
      clipboardText,
      _maxOsc52ClipboardDecodedBytes,
    );
    if (clipboardBytes == null) {
      _events.add(
        TerminalSessionClipboardEvent(
          sessionId,
          operation: TerminalClipboardOperation.pasteRequest,
          decision: TerminalClipboardDecision.invalidPayload,
          selection: selection,
        ),
      );
      return;
    }
    final summary = _summarizeClipboardText(
      clipboardText,
      byteCount: clipboardBytes.length,
    );
    final encoded = base64.encode(clipboardBytes);
    final response = '\x1B]52;$selection;$encoded\x07';
    if (!_sendInput(sessionId, Uint8List.fromList(utf8.encode(response)))) {
      return;
    }
    _events.add(
      TerminalSessionClipboardEvent(
        sessionId,
        operation: TerminalClipboardOperation.pasteRequest,
        decision: TerminalClipboardDecision.allowed,
        selection: selection,
        byteCount: summary.byteCount,
        characterCount: summary.characterCount,
        textPreview: summary.preview,
        textPreviewTruncated: summary.previewTruncated,
      ),
    );
  }

  Uint8List? _boundedUtf8Encode(String text, int maxBytes) {
    var byteLength = 0;
    for (final rune in text.runes) {
      if (rune <= 0x7f) {
        byteLength += 1;
      } else if (rune <= 0x7ff) {
        byteLength += 2;
      } else if (rune <= 0xffff) {
        byteLength += 3;
      } else {
        byteLength += 4;
      }
      if (byteLength > maxBytes) {
        return null;
      }
    }
    return Uint8List.fromList(utf8.encode(text));
  }

  _ClipboardTextSummary _summarizeClipboardText(String text, {int? byteCount}) {
    final runes = text.runes.toList(growable: false);
    final previewRunes = runes.take(_clipboardPreviewRunes).toList();
    return _ClipboardTextSummary(
      byteCount: byteCount ?? utf8.encode(text).length,
      characterCount: runes.length,
      preview: String.fromCharCodes(previewRunes),
      previewTruncated: runes.length > _clipboardPreviewRunes,
    );
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
          final controller = _sessions.existingViewportFor(sessionId);
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
    _refreshScheduler.remove(sessionId);
    _framePumpBackoff.remove(sessionId);
    _lastFrameAppliedAt.remove(sessionId);
    for (final timer in _warmUpTimers.remove(sessionId) ?? const <Timer>[]) {
      timer.cancel();
    }
    _sessions.remove(sessionId);
    _resizeCoordinator.remove(sessionId);
    if (_sessions.isEmpty) {
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
    for (final sessionId in _sessions.sessionIds) {
      _runBackendOperation(
        sessionId,
        'closeSession',
        () => _backend.closeSession(sessionId),
      );
      _removeSessionState(sessionId);
    }
    _pollTimer?.cancel();
    for (final timers in _warmUpTimers.values) {
      for (final timer in timers) {
        timer.cancel();
      }
    }
    _refreshScheduler.dispose();
    _sessions.dispose();
    _events.close();
    _inputEvents.close();
    _resizeEvents.close();
  }
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

Map<String, Object?>? _tryDecodeJsonObject(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return null;
    }
    return <String, Object?>{
      for (final entry in decoded.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  } on Object {
    return null;
  }
}
