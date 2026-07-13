import 'dart:async';
import 'dart:convert';
import 'dart:math';
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
import 'terminal_frame_pump_controller.dart';
import 'terminal_frame_transport_coordinator.dart';
import 'terminal_json_request_client.dart';
import 'terminal_refresh_policy.dart';
import 'terminal_refresh_scheduler.dart';
import 'terminal_resize_coordinator.dart';
import 'terminal_session_registry.dart';

export 'terminal_clipboard_policy.dart';
export 'terminal_diagnostics.dart';
export 'terminal_frame_transport_coordinator.dart'
    show TerminalFrameWireFormatPreference;

const int _maxOsc52ClipboardDecodedBytes = 4 * 1024 * 1024;
const int _maxOsc52ClipboardEncodedLength =
    ((_maxOsc52ClipboardDecodedBytes + 2) ~/ 3) * 4;
const int _maxPendingOsc1337CellSizeReports = 16;
const int _osc5522ChunkBytes = 4096;
const Duration _osc5522PasteTokenLifetime = Duration(seconds: 10);
const int _osc5522MaxRememberedPasswords = 32;
const int _osc5522MaxPasteTokens = 8;

Future<void> _writeMimeClipboardAsText(
  Future<void> Function(String text) writer,
  List<TerminalClipboardMimeItem> items,
) async {
  TerminalClipboardMimeItem? textItem;
  for (final item in items) {
    if (item.mimeType == 'text/plain') {
      textItem = item;
      break;
    }
  }
  if (textItem == null) {
    throw UnsupportedError('No text/plain clipboard representation');
  }
  await writer(utf8.decode(textItem.bytes));
}

Future<List<TerminalClipboardMimeItem>> _readMimeClipboardAsText(
  Future<String> Function() reader,
  List<String> mimeTypes,
) async {
  if (!mimeTypes.any(
    (mime) => mime == 'text/plain' || mime == 'text/*' || mime == '*/*',
  )) {
    return const <TerminalClipboardMimeItem>[];
  }
  return <TerminalClipboardMimeItem>[
    TerminalClipboardMimeItem(
      mimeType: 'text/plain',
      bytes: Uint8List.fromList(utf8.encode(await reader())),
    ),
  ];
}

Future<List<String>> _listTextClipboardMimeType() async => const <String>[
  'text/plain',
];

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
  String? get integrationVersion => _stringValue(rawPayload['version']);
  String? get shell => _stringValue(rawPayload['shell']);
  String? get promptKind => _stringValue(rawPayload['promptKind']);
  String? get aid => _stringValue(rawPayload['aid']);
  String? get parentAid => _stringValue(rawPayload['parentAid']);
  int? get implicitClosedCount =>
      _wholeIntValue(rawPayload['implicitClosedCount']);
  bool? get freshLine =>
      rawPayload['freshLine'] is bool ? rawPayload['freshLine'] as bool : null;

  static String? _stringValue(Object? value) {
    return value is String ? value : null;
  }
}

final class TerminalSessionCellSizeReportRequestEvent
    extends TerminalSessionEvent {
  const TerminalSessionCellSizeReportRequestEvent(super.sessionId);
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

final class TerminalSessionAnnotationEvent extends TerminalSessionEvent {
  TerminalSessionAnnotationEvent(
    super.sessionId, {
    Map<String, Object?>? rawPayload,
  }) : rawPayload = Map.unmodifiable(rawPayload ?? const <String, Object?>{});

  final Map<String, Object?> rawPayload;

  String? get source => _stringValue(rawPayload['source']);
  String? get message => _stringValue(rawPayload['message']);
  String? get selectedText => _stringValue(rawPayload['selectedText']);
  bool get visible => rawPayload['visible'] == true;
  int? get startAbsRow => _wholeIntValue(rawPayload['startAbsRow']);
  int? get startCol => _wholeIntValue(rawPayload['startCol']);
  int? get endAbsRow => _wholeIntValue(rawPayload['endAbsRow']);
  int? get endCol => _wholeIntValue(rawPayload['endCol']);
  int? get startRow => _wholeIntValue(rawPayload['startRow']);
  int? get endRow => _wholeIntValue(rawPayload['endRow']);

  static String? _stringValue(Object? value) => value is String ? value : null;
}

final class TerminalSessionNotificationEvent extends TerminalSessionEvent {
  TerminalSessionNotificationEvent(
    super.sessionId, {
    Map<String, Object?>? rawPayload,
  }) : rawPayload = Map.unmodifiable(rawPayload ?? const <String, Object?>{});

  final Map<String, Object?> rawPayload;

  String? get source => _stringValue(rawPayload['source']);
  String get action => _stringValue(rawPayload['action']) ?? 'show';
  String? get identifier => _stringValue(rawPayload['id']);
  String get title => _stringValue(rawPayload['title']) ?? '';
  String get message => _stringValue(rawPayload['message']) ?? '';
  String? get applicationName => _stringValue(rawPayload['application']);
  List<String> get notificationTypes {
    final values = rawPayload['types'];
    if (values is! List<Object?>) {
      return const <String>[];
    }
    return List<String>.unmodifiable(values.whereType<String>().take(8));
  }

  int? get expiresAfterMs => _wholeIntValue(rawPayload['expiresAfterMs']);
  bool get isClose => action == 'close';

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

/// Incremental iTerm2 OSC 21337 tab-status update.
///
/// Each `*Present` flag distinguishes an omitted field (keep the current
/// value) from a present `null` value (clear it).
final class TerminalSessionTabStatusEvent extends TerminalSessionEvent {
  TerminalSessionTabStatusEvent(
    super.sessionId, {
    Map<String, Object?>? rawPayload,
  }) : rawPayload = Map.unmodifiable(rawPayload ?? const <String, Object?>{});

  final Map<String, Object?> rawPayload;

  String? get source => _stringValue(rawPayload['source']);
  bool get indicatorPresent => rawPayload['indicatorPresent'] == true;
  String? get indicator => _colorValue(rawPayload['indicator']);
  bool get statusPresent => rawPayload['statusPresent'] == true;
  String? get status => _stringValue(rawPayload['status']);
  bool get statusColorPresent => rawPayload['statusColorPresent'] == true;
  String? get statusColor => _colorValue(rawPayload['statusColor']);

  static String? _stringValue(Object? value) {
    return value is String ? value : null;
  }

  static String? _colorValue(Object? value) {
    if (value is! String || !RegExp(r'^#[0-9a-f]{6}$').hasMatch(value)) {
      return null;
    }
    return value;
  }
}

/// Untrusted UAPI OSC 3008 hierarchy metadata emitted by the child process.
final class TerminalSessionContextEvent extends TerminalSessionEvent {
  TerminalSessionContextEvent(
    super.sessionId, {
    Map<String, Object?>? rawPayload,
  }) : rawPayload = Map.unmodifiable(rawPayload ?? const <String, Object?>{});

  final Map<String, Object?> rawPayload;

  String? get source => _stringValue(rawPayload['source']);
  String? get action => _stringValue(rawPayload['action']);
  String? get identifier => _stringValue(rawPayload['id']);
  int? get depth => _wholeIntValue(rawPayload['depth']);
  bool get active => rawPayload['active'] == true;
  String? get contextType => _stringValue(rawPayload['type']);
  String? get user => _stringValue(rawPayload['user']);
  String? get hostname => _stringValue(rawPayload['hostname']);
  String? get machineId => _stringValue(rawPayload['machineId']);
  String? get bootId => _stringValue(rawPayload['bootId']);
  int? get pid => _wholeIntValue(rawPayload['pid']);
  int? get pidfdId => _wholeIntValue(rawPayload['pidfdId']);
  String? get commandName => _stringValue(rawPayload['commandName']);
  String? get cwd => _stringValue(rawPayload['cwd']);
  String? get commandLine => _stringValue(rawPayload['commandLine']);
  String? get vm => _stringValue(rawPayload['vm']);
  String? get container => _stringValue(rawPayload['container']);
  String? get targetUser => _stringValue(rawPayload['targetUser']);
  String? get targetHost => _stringValue(rawPayload['targetHost']);
  String? get contextSessionId => _stringValue(rawPayload['contextSessionId']);
  String? get exit => _stringValue(rawPayload['exit']);
  int? get status => _wholeIntValue(rawPayload['status']);
  String? get signal => _stringValue(rawPayload['signal']);
  int get implicitClosedCount =>
      _wholeIntValue(rawPayload['implicitClosedCount']) ?? 0;

  static String? _stringValue(Object? value) {
    return value is String ? value : null;
  }
}

/// A bounded Kitty OSC 72 command. This describes an untrusted child request;
/// it never authorizes a system drag/drop or file read by itself.
final class TerminalSessionDragDropCommandEvent extends TerminalSessionEvent {
  TerminalSessionDragDropCommandEvent(
    super.sessionId, {
    Map<String, Object?>? rawPayload,
  }) : rawPayload = Map.unmodifiable(rawPayload ?? const <String, Object?>{});

  final Map<String, Object?> rawPayload;

  String get action => _stringValue(rawPayload['action']) ?? 'a';
  bool get more => rawPayload['more'] == true;
  int? get identifier => _wholeIntValue(rawPayload['identifier']);
  int? get operation => _wholeIntValue(rawPayload['operation']);
  int? get x => _wholeIntValue(rawPayload['x']);
  int? get y => _wholeIntValue(rawPayload['y']);
  int? get pixelX => _wholeIntValue(rawPayload['pixelX']);
  int? get pixelY => _wholeIntValue(rawPayload['pixelY']);
  String get payload => _stringValue(rawPayload['payload']) ?? '';

  static String? _stringValue(Object? value) => value is String ? value : null;
}

/// The parser received RIS (`ESC c`) and reset terminal semantic state.
final class TerminalSessionResetEvent extends TerminalSessionEvent {
  const TerminalSessionResetEvent(super.sessionId);
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
    this.protocol = 'osc52',
    this.mimeTypes = const <String>[],
  });

  final TerminalClipboardOperation operation;
  final TerminalClipboardDecision decision;
  final String? selection;
  final int? byteCount;
  final int? characterCount;
  final String? textPreview;
  final bool textPreviewTruncated;
  final String protocol;
  final List<String> mimeTypes;

  bool get allowed => decision == TerminalClipboardDecision.allowed;
}

final class _Osc5522PasteToken {
  const _Osc5522PasteToken({required this.location, required this.expiresAt});

  final String location;
  final Duration expiresAt;
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

class TerminalRuntimeController {
  static const Duration _pollingFrameInterval = Duration(milliseconds: 33);
  static const int _clipboardPreviewRunes = 120;

  TerminalRuntimeController({
    required PtySessionBackend backend,
    required Future<void> Function(String text) copyToClipboard,
    required Future<String> Function() readClipboard,
    TerminalClipboardTextWriter? writeTextClipboard,
    Future<bool> Function()? allowClipboardCopy,
    Future<bool> Function()? allowClipboardPasteRequest,
    Future<bool> Function(TerminalClipboardAccessRequest request)?
    allowClipboardCopyWithContext,
    Future<bool> Function(TerminalClipboardAccessRequest request)?
    allowClipboardPasteRequestWithContext,
    TerminalClipboardMimeWriter? writeMimeClipboard,
    TerminalClipboardMimeReader? readMimeClipboard,
    TerminalClipboardMimeTypeLister? listClipboardMimeTypes,
    TerminalClipboardAuthorizer? authorizeMimeClipboardAccessWithContext,
    TerminalWindowResizeCallback? resizeWindowBy,
    bool enableSessionPolling = true,
    bool enableWarmUpRefresh = false,
    TerminalFrameWireFormatPreference frameWireFormatPreference =
        TerminalFrameWireFormatPreference.automatic,
    TerminalBenchmarkEventSink? benchmarkEventSink,
    Duration Function()? monotonicNow,
  }) : this.withClipboardPolicy(
         backend: backend,
         copyToClipboard: copyToClipboard,
         readClipboard: readClipboard,
         writeTextClipboard: writeTextClipboard,
         clipboardPolicy: TerminalClipboardPolicyAdapter(
           allowClipboardCopy: allowClipboardCopy,
           allowClipboardPasteRequest: allowClipboardPasteRequest,
           allowClipboardCopyWithContext: allowClipboardCopyWithContext,
           allowClipboardPasteRequestWithContext:
               allowClipboardPasteRequestWithContext,
         ),
         writeMimeClipboard: writeMimeClipboard,
         readMimeClipboard: readMimeClipboard,
         listClipboardMimeTypes: listClipboardMimeTypes,
         authorizeMimeClipboardAccessWithContext:
             authorizeMimeClipboardAccessWithContext,
         resizeWindowBy: resizeWindowBy,
         enableSessionPolling: enableSessionPolling,
         enableWarmUpRefresh: enableWarmUpRefresh,
         frameWireFormatPreference: frameWireFormatPreference,
         benchmarkEventSink: benchmarkEventSink,
         monotonicNow: monotonicNow,
       );

  TerminalRuntimeController.withClipboardPolicy({
    required PtySessionBackend backend,
    required this.copyToClipboard,
    required this.readClipboard,
    required TerminalClipboardPolicyAdapter clipboardPolicy,
    TerminalClipboardTextWriter? writeTextClipboard,
    TerminalClipboardMimeWriter? writeMimeClipboard,
    TerminalClipboardMimeReader? readMimeClipboard,
    TerminalClipboardMimeTypeLister? listClipboardMimeTypes,
    TerminalClipboardAuthorizer? authorizeMimeClipboardAccessWithContext,
    this.resizeWindowBy,
    this.enableSessionPolling = true,
    this.enableWarmUpRefresh = false,
    this.frameWireFormatPreference =
        TerminalFrameWireFormatPreference.automatic,
    this.benchmarkEventSink,
    Duration Function()? monotonicNow,
  }) : _backend = backend,
       writeTextClipboard =
           writeTextClipboard ?? ((text, selection) => copyToClipboard(text)),
       allowClipboardCopy = clipboardPolicy.allowCopy,
       allowClipboardPasteRequest = clipboardPolicy.allowPasteRequest,
       writeMimeClipboard =
           writeMimeClipboard ??
           ((items) => _writeMimeClipboardAsText(copyToClipboard, items)),
       readMimeClipboard =
           readMimeClipboard ??
           ((mimeTypes) => _readMimeClipboardAsText(readClipboard, mimeTypes)),
       listClipboardMimeTypes =
           listClipboardMimeTypes ?? _listTextClipboardMimeType,
       authorizeMimeClipboardAccess =
           authorizeMimeClipboardAccessWithContext ??
           ((request) async {
             final allowed = switch (request.operation) {
               TerminalClipboardOperation.copy ||
               TerminalClipboardOperation.mimeWrite =>
                 await clipboardPolicy.allowCopy(request),
               TerminalClipboardOperation.pasteRequest ||
               TerminalClipboardOperation.mimeRead =>
                 await clipboardPolicy.allowPasteRequest(request),
             };
             return allowed
                 ? TerminalClipboardAuthorization.allowOnce
                 : TerminalClipboardAuthorization.denied;
           }),
       _readMonotonicNow = monotonicNow {
    final refreshHintBackend = backend is PtySessionRefreshHintBackend
        ? backend as PtySessionRefreshHintBackend
        : null;
    _refreshHintBackend = refreshHintBackend;
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
    _frameTransportCoordinator = TerminalFrameTransportCoordinator(
      backend: backend,
      decoder: _frameDecoder,
      preference: frameWireFormatPreference,
      onRequestError: _emitBackendRequestError,
    );
  }

  final PtySessionBackend _backend;
  late final PtySessionRefreshHintBackend? _refreshHintBackend;
  final Set<String> _refreshHintDisabledSessions = <String>{};
  late final TerminalDiagnosticsClient _diagnosticsClient;
  late final TerminalJsonRequestClient _jsonRequestClient;
  final TerminalEventRouter _eventRouter = const TerminalEventRouter();
  late final TerminalSessionRegistry _sessions;
  late final TerminalFrameDecoder _frameDecoder;
  late final TerminalFrameTransportCoordinator _frameTransportCoordinator;
  final Future<void> Function(String text) copyToClipboard;
  final TerminalClipboardTextWriter writeTextClipboard;
  final Future<String> Function() readClipboard;
  final TerminalClipboardMimeWriter writeMimeClipboard;
  final TerminalClipboardMimeReader readMimeClipboard;
  final TerminalClipboardMimeTypeLister listClipboardMimeTypes;
  final TerminalClipboardAuthorizer authorizeMimeClipboardAccess;
  final Future<bool> Function(TerminalClipboardAccessRequest request)
  allowClipboardCopy;
  final Future<bool> Function(TerminalClipboardAccessRequest request)
  allowClipboardPasteRequest;
  final TerminalWindowResizeCallback? resizeWindowBy;
  final bool enableSessionPolling;
  final bool enableWarmUpRefresh;
  final TerminalFrameWireFormatPreference frameWireFormatPreference;
  final TerminalBenchmarkEventSink? benchmarkEventSink;
  final Duration Function()? _readMonotonicNow;

  final TerminalResizeCoordinator _resizeCoordinator =
      TerminalResizeCoordinator();
  final TerminalRefreshScheduler _refreshScheduler = TerminalRefreshScheduler();
  final TerminalFramePumpController _framePumpController =
      TerminalFramePumpController.standard();
  final Map<String, List<Timer>> _warmUpTimers = <String, List<Timer>>{};
  final Stopwatch _monotonicClock = Stopwatch()..start();
  // Stopwatch remains authoritative in production. The floor lets FakeAsync
  // advance the same monotonic deadline when it fires scheduled polling ticks.
  Duration _scheduledPollingFloor = Duration.zero;
  final Map<String, _TerminalRefreshTrace> _pendingRefreshTraces =
      <String, _TerminalRefreshTrace>{};
  final Map<String, _TerminalRefreshTrace> _activeRefreshTraces =
      <String, _TerminalRefreshTrace>{};
  final Set<String> _pendingFullPollRequests = <String>{};
  final Map<String, int> _pendingCellSizeReports = <String, int>{};
  final Map<String, int> _refreshIdSeeds = <String, int>{};
  final Map<String, int> _sessionEpochs = <String, int>{};
  final Map<String, DateTime> _lastFrameAppliedAt = <String, DateTime>{};
  final Map<String, List<String>> _osc5522RememberedPasswords =
      <String, List<String>>{};
  final Map<String, Map<String, _Osc5522PasteToken>> _osc5522PasteTokens =
      <String, Map<String, _Osc5522PasteToken>>{};
  final Random _osc5522SecureRandom = Random.secure();
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
  int _sessionEpochSeed = 0;

  Stream<TerminalSessionEvent> get events => _events.stream;
  Stream<TerminalSessionInputEvent> get inputEvents => _inputEvents.stream;
  Stream<TerminalSessionResizeEvent> get resizeEvents => _resizeEvents.stream;

  Duration get _rawMonotonicNow =>
      _readMonotonicNow?.call() ?? _monotonicClock.elapsed;

  Duration get _monotonicNow {
    final rawNow = _rawMonotonicNow;
    if (_readMonotonicNow != null || rawNow >= _scheduledPollingFloor) {
      return rawNow;
    }
    return _scheduledPollingFloor;
  }

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
    _sessionEpochSeed += 1;
    _sessionEpochs[sessionId] = _sessionEpochSeed;
    _framePumpController.reset(
      sessionId,
      now: _monotonicNow,
      reason: TerminalFramePumpResetReason.activation,
      active: true,
    );
    _requestRefreshSession(sessionId, immediate: true);
    if (enableSessionPolling) {
      _startPolling();
    } else {
      _scheduleWarmUpRefreshes(sessionId);
    }
    return sessionId;
  }

  void setSessionActive(String sessionId, {required bool active}) {
    if (!hasSession(sessionId)) {
      return;
    }
    _framePumpController.reset(
      sessionId,
      now: _monotonicNow,
      reason: TerminalFramePumpResetReason.activation,
      active: active,
    );
  }

  void setSessionFocused(String sessionId, {required bool focused}) {
    if (!hasSession(sessionId)) {
      return;
    }
    if (focused) {
      _framePumpController.reset(
        sessionId,
        now: _monotonicNow,
        reason: TerminalFramePumpResetReason.focusGain,
      );
    } else {
      _framePumpController.recordFocusLoss(sessionId, now: _monotonicNow);
    }
  }

  TerminalRefreshSnapshot refreshPolicySnapshotFor(String sessionId) {
    return _framePumpController.snapshot(sessionId, now: _monotonicNow);
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

  Future<bool> sendOsc5522PasteEvent(
    String sessionId, {
    String location = 'clipboard',
  }) async {
    final sessionEpoch = _sessionEpochs[sessionId];
    if (sessionEpoch == null || location != 'clipboard') {
      return false;
    }
    late final List<String> available;
    try {
      available =
          (await listClipboardMimeTypes())
              .where(_isValidOsc5522Mime)
              .toSet()
              .toList()
            ..sort();
    } on Object {
      return false;
    }
    if (!_isCurrentSession(sessionId, sessionEpoch)) {
      return false;
    }
    final mimeTypes = available.take(64).toList(growable: false);
    final password = List<int>.generate(
      32,
      (_) => _osc5522SecureRandom.nextInt(256),
      growable: false,
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final tokens = _osc5522PasteTokens.putIfAbsent(
      sessionId,
      () => <String, _Osc5522PasteToken>{},
    );
    final now = _monotonicNow;
    tokens.removeWhere((_, token) => token.expiresAt <= now);
    while (tokens.length >= _osc5522MaxPasteTokens) {
      tokens.remove(tokens.keys.first);
    }
    tokens[password] = _Osc5522PasteToken(
      location: location,
      expiresAt: now + _osc5522PasteTokenLifetime,
    );
    final encodedPassword = base64.encode(utf8.encode(password));
    final packets = <String>[
      '\u001b]5522;type=read:status=OK:pw=$encodedPassword\u001b\\',
      for (final mime in mimeTypes)
        '\u001b]5522;type=read:status=DATA:mime=${base64.encode(utf8.encode(mime))}\u001b\\',
      '\u001b]5522;type=read:status=DONE\u001b\\',
    ];
    for (final packet in packets) {
      if (!_sendInput(
        sessionId,
        Uint8List.fromList(ascii.encode(packet)),
        sessionEpoch: sessionEpoch,
      )) {
        tokens.remove(password);
        return false;
      }
    }
    return true;
  }

  bool _sendInput(String sessionId, Uint8List bytes, {int? sessionEpoch}) {
    if (sessionEpoch != null && !_isCurrentSession(sessionId, sessionEpoch)) {
      return false;
    }
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
    if (sessionEpoch != null && !_isCurrentSession(sessionId, sessionEpoch)) {
      return false;
    }
    _inputEvents.add(TerminalSessionInputEvent(sessionId, copiedBytes));
    _framePumpController.reset(
      sessionId,
      now: _monotonicNow,
      reason: TerminalFramePumpResetReason.input,
    );
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
    _framePumpController.reset(
      sessionId,
      now: _monotonicNow,
      reason: TerminalFramePumpResetReason.input,
    );
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
    _framePumpController.reset(
      sessionId,
      now: _monotonicNow,
      reason: TerminalFramePumpResetReason.input,
    );
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
        pointerShape: current.pointerShape,
        modes: current.modes,
        windowTitle: current.windowTitle,
        windowIconName: current.windowIconName,
        sizedText: current.sizedText,
      ),
    );
    return true;
  }

  bool setBlockFolded(String sessionId, String id, {required bool folded}) {
    if (!hasSession(sessionId) || id.isEmpty) {
      return false;
    }
    if (!_jsonRequestClient.setBlockFolded(sessionId, id, folded: folded)) {
      return false;
    }
    _framePumpController.reset(
      sessionId,
      now: _monotonicNow,
      reason: TerminalFramePumpResetReason.input,
    );
    _requestRefreshSession(sessionId, immediate: true);
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
    _flushPendingCellSizeReport(sessionId);
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
    _flushPendingCellSizeReport(sessionId);
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
    if (_pollTimer != null) {
      return;
    }
    var scheduledTick = _monotonicNow + _pollingFrameInterval;
    _pollTimer = Timer.periodic(_pollingFrameInterval, (_) {
      final rawNow = _rawMonotonicNow;
      if (_readMonotonicNow == null) {
        final scheduledNow = rawNow >= scheduledTick ? rawNow : scheduledTick;
        if (scheduledNow > _scheduledPollingFloor) {
          _scheduledPollingFloor = scheduledNow;
        }
      }
      if (rawNow - scheduledTick >= _pollingFrameInterval) {
        scheduledTick = rawNow + _pollingFrameInterval;
      } else {
        scheduledTick += _pollingFrameInterval;
      }
      for (final sessionId in _sessions.sessionIds) {
        _requestPollingRefreshSession(sessionId);
      }
    });
  }

  void _requestPollingRefreshSession(String sessionId) {
    final now = _monotonicNow;
    final decision = _framePumpController.decisionForTick(
      sessionId,
      now: now,
      hintReady: _nativeRefreshHintReady(sessionId),
    );
    if (!decision.shouldRequestFullPoll) {
      _emitSkippedPollingTick(sessionId);
      return;
    }
    _requestRefreshSession(
      sessionId,
      requestReason: decision.requestReason ?? 'deadline',
    );
  }

  bool? _nativeRefreshHintReady(String sessionId) {
    final backend = _refreshHintBackend;
    if (backend == null ||
        !backend.supportsRefreshHints ||
        _refreshHintDisabledSessions.contains(sessionId)) {
      return null;
    }
    try {
      final flags = backend.refreshHintFlags(sessionId);
      return flags & PtyRefreshHintFlags.frameDirty != 0;
    } on Object catch (error, stackTrace) {
      _refreshHintDisabledSessions.add(sessionId);
      _emitBackendRequestError(
        sessionId,
        'refreshHintFlags',
        error,
        stackTrace,
      );
      return null;
    }
  }

  void _requestRefreshSession(
    String sessionId, {
    bool immediate = false,
    String requestReason = 'runtime',
  }) {
    if (!hasSession(sessionId)) {
      return;
    }
    _prepareRefreshTrace(sessionId, requestReason: requestReason);
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
    final sessionEpoch = _sessionEpochs[sessionId];
    if (sessionEpoch == null) {
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
        if (_isCurrentSession(sessionId, sessionEpoch)) {
          _requestRefreshSession(sessionId, immediate: true);
        }
      })) {
        return;
      }
      return;
    }
    unawaited(_refreshSession(sessionId, sessionEpoch));
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

  bool _isCurrentSession(String sessionId, int sessionEpoch) {
    return _sessionEpochs[sessionId] == sessionEpoch && hasSession(sessionId);
  }

  Future<void> _refreshSession(String sessionId, int sessionEpoch) async {
    if (enableSessionPolling) {
      await _refreshSessionOnce(sessionId, sessionEpoch);
      return;
    }
    await _refreshSessionDraining(sessionId, sessionEpoch);
  }

  Future<void> _refreshSessionOnce(String sessionId, int sessionEpoch) async {
    if (!_isCurrentSession(sessionId, sessionEpoch)) {
      return;
    }

    _refreshScheduler.markRefreshing(sessionId);
    try {
      _startRefreshTrace(sessionId);
      final pendingFrames = <TerminalFrameDiff>[];
      _refreshScheduler.consumeQueuedRefresh(sessionId);
      var receivedFrame = false;

      final frame = _takeFrameDiff(sessionId);
      _recordFrameTaken(sessionId);
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

      final eventProcessing = _processEvents(sessionId, sessionEpoch, events);
      if (eventProcessing != null) {
        await eventProcessing;
      }
      if (!_isCurrentSession(sessionId, sessionEpoch)) {
        return;
      }

      if (pendingFrames.isNotEmpty) {
        _applyPendingFrames(sessionId, pendingFrames);
      }
      _recordPollingRefreshResult(
        sessionId,
        hadActivity: receivedFrame || events.isNotEmpty,
        receivedFrame: receivedFrame,
        eventCount: events.length,
      );
    } finally {
      if (_isCurrentSession(sessionId, sessionEpoch)) {
        _activeRefreshTraces.remove(sessionId);
        _refreshScheduler.clearRefreshing(sessionId);
        if (_refreshScheduler.consumeQueuedRefresh(sessionId)) {
          _requestRefreshSession(sessionId);
        }
      }
    }
  }

  Future<void> _refreshSessionDraining(
    String sessionId,
    int sessionEpoch,
  ) async {
    if (!_isCurrentSession(sessionId, sessionEpoch)) {
      return;
    }

    _refreshScheduler.markRefreshing(sessionId);
    try {
      var runAgain = true;
      final pendingFrames = <TerminalFrameDiff>[];
      var skippedQueuedFrames = 0;
      while (runAgain && _isCurrentSession(sessionId, sessionEpoch)) {
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

        final eventProcessing = _processEvents(sessionId, sessionEpoch, events);
        if (eventProcessing != null) {
          await eventProcessing;
        }
        if (!_isCurrentSession(sessionId, sessionEpoch)) {
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
        _framePumpController.recordRefreshResult(
          sessionId,
          now: _monotonicNow,
          receivedFrame: frame != null,
          eventCount: events.length,
          modes: frame?.modes ?? viewportFor(sessionId).frame.modes,
        );
      }
    } finally {
      if (_isCurrentSession(sessionId, sessionEpoch)) {
        _refreshScheduler.clearRefreshing(sessionId);
        if (_refreshScheduler.consumeQueuedRefresh(sessionId)) {
          _requestRefreshSession(sessionId);
        }
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
    _framePumpController.reset(
      sessionId,
      now: _monotonicNow,
      reason: TerminalFramePumpResetReason.resize,
    );
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
    _recordFrameApplied(sessionId);
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
        _requestRefreshSession(sessionId, requestReason: 'frame_cooldown');
      }
    });
  }

  void _recordPollingRefreshResult(
    String sessionId, {
    required bool hadActivity,
    required bool receivedFrame,
    required int eventCount,
  }) {
    if (!hasSession(sessionId)) {
      return;
    }
    final now = _monotonicNow;
    _framePumpController.recordRefreshResult(
      sessionId,
      now: now,
      receivedFrame: receivedFrame,
      eventCount: eventCount,
      modes: viewportFor(sessionId).frame.modes,
    );
    if (!enableSessionPolling) {
      return;
    }
    _finishRefreshTrace(
      sessionId,
      now: now,
      hadActivity: hadActivity,
      receivedFrame: receivedFrame,
      eventCount: eventCount,
    );
  }

  void _emitSkippedPollingTick(String sessionId) {
    if (benchmarkEventSink == null) {
      return;
    }
    _emitRefreshDiagnostic(
      sessionId,
      event: 'poll_tick_skipped',
      now: _monotonicNow,
    );
  }

  void _prepareRefreshTrace(String sessionId, {required String requestReason}) {
    if (!enableSessionPolling || !_pendingFullPollRequests.add(sessionId)) {
      return;
    }
    _framePumpController.recordFullPollRequest(sessionId);
    if (benchmarkEventSink == null) {
      return;
    }
    final now = _monotonicNow;
    final refreshId = (_refreshIdSeeds[sessionId] ?? 0) + 1;
    _refreshIdSeeds[sessionId] = refreshId;
    final trace = _TerminalRefreshTrace(
      refreshId: refreshId,
      requestReason: requestReason,
      refreshRequestedMicros: now.inMicroseconds,
    );
    _pendingRefreshTraces[sessionId] = trace;
    _emitRefreshDiagnostic(
      sessionId,
      event: 'full_poll_requested',
      now: now,
      trace: trace,
    );
  }

  void _startRefreshTrace(String sessionId) {
    if (!enableSessionPolling) {
      return;
    }
    if (!_pendingFullPollRequests.contains(sessionId)) {
      _prepareRefreshTrace(sessionId, requestReason: 'scheduler');
    }
    _pendingFullPollRequests.remove(sessionId);
    if (benchmarkEventSink == null) {
      return;
    }
    final trace = _pendingRefreshTraces.remove(sessionId);
    if (trace == null) {
      return;
    }
    final now = _monotonicNow;
    trace.refreshStartedMicros = now.inMicroseconds;
    _activeRefreshTraces[sessionId] = trace;
    _emitRefreshDiagnostic(
      sessionId,
      event: 'refresh_started',
      now: now,
      trace: trace,
    );
  }

  void _recordFrameTaken(String sessionId) {
    final trace = _activeRefreshTraces[sessionId];
    if (trace == null) {
      return;
    }
    final now = _monotonicNow;
    trace.frameTakenMicros = now.inMicroseconds;
    _emitRefreshDiagnostic(
      sessionId,
      event: 'frame_taken',
      now: now,
      trace: trace,
    );
  }

  void _recordFrameApplied(String sessionId) {
    final trace = _activeRefreshTraces[sessionId];
    if (trace == null) {
      return;
    }
    final now = _monotonicNow;
    trace.frameAppliedMicros = now.inMicroseconds;
    _emitRefreshDiagnostic(
      sessionId,
      event: 'frame_applied',
      now: now,
      trace: trace,
    );
  }

  void _finishRefreshTrace(
    String sessionId, {
    required Duration now,
    required bool hadActivity,
    required bool receivedFrame,
    required int eventCount,
  }) {
    final trace = _activeRefreshTraces.remove(sessionId);
    if (trace == null) {
      return;
    }
    final metrics = _framePumpController
        .snapshot(sessionId, now: now)
        .pumpMetrics;
    _emitRefreshDiagnostic(
      sessionId,
      event: 'refresh_result',
      now: now,
      trace: trace,
      metrics: metrics,
      fields: <String, Object?>{
        'had_activity': hadActivity,
        'received_frame': receivedFrame,
        'event_count': eventCount,
        'next_deadline_micros':
            now.inMicroseconds + metrics.currentDelay.inMicroseconds,
      },
    );
  }

  void _emitRefreshDiagnostic(
    String sessionId, {
    required String event,
    required Duration now,
    _TerminalRefreshTrace? trace,
    TerminalFramePumpMetrics? metrics,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    final sink = benchmarkEventSink;
    if (sink == null) {
      return;
    }
    final policySnapshot = _framePumpController.snapshot(sessionId, now: now);
    final snapshot = metrics ?? policySnapshot.pumpMetrics;
    try {
      sink(<String, Object?>{
        'schema_version': 'ianvs-terminal-refresh-policy-v1',
        'event': event,
        'monotonic_micros': now.inMicroseconds,
        'session_id': sessionId,
        'refresh_id': trace?.refreshId,
        'refresh_class': policySnapshot.refreshClass.name,
        'empty_refresh_count': snapshot.emptyRefreshCount,
        'backoff_skip_ticks': snapshot.backoffSkipTicks,
        'current_delay_micros': snapshot.currentDelay.inMicroseconds,
        'hint_poll_count': policySnapshot.hintPollCount,
        'full_poll_count': policySnapshot.fullPollCount,
        'refresh_requested_micros': trace?.refreshRequestedMicros,
        'refresh_started_micros': trace?.refreshStartedMicros,
        'frame_taken_micros': trace?.frameTakenMicros,
        'frame_applied_micros': trace?.frameAppliedMicros,
        if (trace != null) 'request_reason': trace.requestReason,
        ...fields,
      });
    } on Object {
      // Diagnostics are observational and must never interrupt refreshes.
    }
  }

  TerminalFrameDiff? _takeFrameDiff(String sessionId) {
    final decoded = _frameTransportCoordinator.take(sessionId);
    if (decoded == null) {
      return null;
    }
    final metrics = decoded.metrics;
    if (metrics != null) {
      _decodedFrameBenchmarkMetrics[decoded.frame] = TerminalFrameDecodeMetrics(
        rawFrameBytes: metrics.rawFrameBytes,
        wireFormat: metrics.wireFormat,
        jsonDecodeMicros: metrics.jsonDecodeMicros,
        protobufDecodeMicros: metrics.protobufDecodeMicros,
        nativeFrameStats: _takeNativeFrameDebugStats(sessionId),
      );
    }
    return decoded.frame;
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

  Future<void>? _processEvents(
    String sessionId,
    int sessionEpoch,
    List<PtyEvent> events,
  ) {
    Future<void>? pendingAsyncWork;
    for (final event in events) {
      if (!_isCurrentSession(sessionId, sessionEpoch)) {
        return pendingAsyncWork;
      }
      final route = _eventRouter.route(event);
      if (route is TerminalExitEventRoute) {
        if (pendingAsyncWork == null) {
          _emitExitIfCurrent(sessionId, sessionEpoch, route.exitCode);
          return null;
        }
        return pendingAsyncWork.then((_) {
          _emitExitIfCurrent(sessionId, sessionEpoch, route.exitCode);
        });
      }
      if (route is TerminalAsyncEventRoute) {
        pendingAsyncWork = _chainAsyncEvent(
          pendingAsyncWork,
          sessionId,
          sessionEpoch,
          () => _handleAsyncEventRoute(sessionId, sessionEpoch, route),
        );
        continue;
      }
      if (route is TerminalImmediateEventRoute) {
        _emitImmediateEventRoute(sessionId, sessionEpoch, route);
      }
    }
    return pendingAsyncWork;
  }

  void _emitExitIfCurrent(String sessionId, int sessionEpoch, int? exitCode) {
    if (!_isCurrentSession(sessionId, sessionEpoch)) {
      return;
    }
    _removeSessionState(sessionId);
    _events.add(TerminalSessionExitEvent(sessionId, exitCode: exitCode));
  }

  Future<void> _handleAsyncEventRoute(
    String sessionId,
    int sessionEpoch,
    TerminalAsyncEventRoute route,
  ) {
    if (!_isCurrentSession(sessionId, sessionEpoch)) {
      return Future<void>.value();
    }
    return switch (route.kind) {
      TerminalAsyncEventKind.resize => _handleResizeEvent(
        sessionId,
        sessionEpoch,
        route.payload,
      ),
      TerminalAsyncEventKind.clipboardCopy => _handleClipboardCopyEvent(
        sessionId,
        sessionEpoch,
        route.payload,
      ),
      TerminalAsyncEventKind.clipboardPasteRequest =>
        _handleClipboardPasteRequestEvent(
          sessionId,
          sessionEpoch,
          route.payload,
        ),
      TerminalAsyncEventKind.clipboardMimeWrite => _handleClipboardMimeWrite(
        sessionId,
        sessionEpoch,
        route.payload,
      ),
      TerminalAsyncEventKind.clipboardMimeReadRequest =>
        _handleClipboardMimeReadRequest(sessionId, sessionEpoch, route.payload),
      TerminalAsyncEventKind.clipboardMimeError => _handleClipboardMimeError(
        sessionId,
        sessionEpoch,
        route.payload,
      ),
    };
  }

  void _emitImmediateEventRoute(
    String sessionId,
    int sessionEpoch,
    TerminalImmediateEventRoute route,
  ) {
    switch (route.kind) {
      case TerminalImmediateEventKind.bell:
        _emitEventIfCurrent(
          sessionId,
          sessionEpoch,
          TerminalSessionBellEvent(sessionId),
        );
      case TerminalImmediateEventKind.shellHook:
        _emitEventIfCurrent(
          sessionId,
          sessionEpoch,
          TerminalSessionShellHookEvent(sessionId, rawPayload: route.payload),
        );
      case TerminalImmediateEventKind.shellContext:
        _emitEventIfCurrent(
          sessionId,
          sessionEpoch,
          TerminalSessionShellContextEvent(
            sessionId,
            rawPayload: route.payload,
          ),
        );
      case TerminalImmediateEventKind.shellCommand:
        _emitEventIfCurrent(
          sessionId,
          sessionEpoch,
          TerminalSessionShellCommandEvent(
            sessionId,
            rawPayload: route.payload,
          ),
        );
      case TerminalImmediateEventKind.shellUserVar:
        _emitEventIfCurrent(
          sessionId,
          sessionEpoch,
          TerminalSessionShellUserVarEvent(
            sessionId,
            rawPayload: route.payload,
          ),
        );
      case TerminalImmediateEventKind.sessionAnnotation:
        _emitEventIfCurrent(
          sessionId,
          sessionEpoch,
          TerminalSessionAnnotationEvent(sessionId, rawPayload: route.payload),
        );
      case TerminalImmediateEventKind.sessionNotification:
        _emitEventIfCurrent(
          sessionId,
          sessionEpoch,
          TerminalSessionNotificationEvent(
            sessionId,
            rawPayload: route.payload,
          ),
        );
      case TerminalImmediateEventKind.sessionProgress:
        _emitEventIfCurrent(
          sessionId,
          sessionEpoch,
          TerminalSessionProgressEvent(sessionId, rawPayload: route.payload),
        );
      case TerminalImmediateEventKind.sessionBadge:
        _emitEventIfCurrent(
          sessionId,
          sessionEpoch,
          TerminalSessionBadgeEvent(sessionId, rawPayload: route.payload),
        );
      case TerminalImmediateEventKind.sessionTabStatus:
        _emitEventIfCurrent(
          sessionId,
          sessionEpoch,
          TerminalSessionTabStatusEvent(sessionId, rawPayload: route.payload),
        );
      case TerminalImmediateEventKind.terminalContext:
        _emitEventIfCurrent(
          sessionId,
          sessionEpoch,
          TerminalSessionContextEvent(sessionId, rawPayload: route.payload),
        );
      case TerminalImmediateEventKind.dragDropCommand:
        _emitEventIfCurrent(
          sessionId,
          sessionEpoch,
          TerminalSessionDragDropCommandEvent(
            sessionId,
            rawPayload: route.payload,
          ),
        );
      case TerminalImmediateEventKind.cellSizeReportRequest:
        _replyOrQueueCellSizeReport(sessionId, sessionEpoch);
        _emitEventIfCurrent(
          sessionId,
          sessionEpoch,
          TerminalSessionCellSizeReportRequestEvent(sessionId),
        );
      case TerminalImmediateEventKind.sessionReset:
        _emitEventIfCurrent(
          sessionId,
          sessionEpoch,
          TerminalSessionResetEvent(sessionId),
        );
    }
  }

  void _emitEventIfCurrent(
    String sessionId,
    int sessionEpoch,
    TerminalSessionEvent event,
  ) {
    if (_isCurrentSession(sessionId, sessionEpoch)) {
      _events.add(event);
    }
  }

  Future<void> _chainAsyncEvent(
    Future<void>? pendingAsyncWork,
    String sessionId,
    int sessionEpoch,
    Future<void> Function() process,
  ) {
    if (!_isCurrentSession(sessionId, sessionEpoch)) {
      return Future<void>.value();
    }
    if (pendingAsyncWork == null) {
      return process();
    }
    return pendingAsyncWork.then((_) async {
      if (!_isCurrentSession(sessionId, sessionEpoch)) {
        return;
      }
      await process();
    });
  }

  Future<void> _handleResizeEvent(
    String sessionId,
    int sessionEpoch,
    Map<String, Object?>? payload,
  ) async {
    if (!_isCurrentSession(sessionId, sessionEpoch) || payload == null) {
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
    if (!_isCurrentSession(sessionId, sessionEpoch)) {
      return;
    }
    _resizeCoordinator.commit(sessionId, metric);
    _flushPendingCellSizeReport(sessionId);
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
    if (!_isCurrentSession(sessionId, sessionEpoch)) {
      return;
    }
  }

  Size _cellSizeFor(String sessionId) {
    return viewportFor(sessionId).measuredCellSize ?? terminalFallbackCellSize;
  }

  void _replyOrQueueCellSizeReport(String sessionId, int sessionEpoch) {
    if (!_sendCellSizeReport(sessionId, sessionEpoch: sessionEpoch)) {
      if (_isCurrentSession(sessionId, sessionEpoch)) {
        _pendingCellSizeReports.update(
          sessionId,
          (count) =>
              (count + 1).clamp(1, _maxPendingOsc1337CellSizeReports).toInt(),
          ifAbsent: () => 1,
        );
      }
    }
  }

  void _flushPendingCellSizeReport(String sessionId) {
    final count = _pendingCellSizeReports[sessionId];
    if (count == null) {
      return;
    }
    for (var index = 0; index < count; index += 1) {
      if (!_sendCellSizeReport(sessionId)) {
        _pendingCellSizeReports[sessionId] = count - index;
        return;
      }
    }
    _pendingCellSizeReports.remove(sessionId);
  }

  bool _sendCellSizeReport(String sessionId, {int? sessionEpoch}) {
    final metric = _resizeCoordinator.metricFor(sessionId);
    if (metric == null ||
        !metric.logicalCellWidth.isFinite ||
        metric.logicalCellWidth <= 0 ||
        !metric.logicalCellHeight.isFinite ||
        metric.logicalCellHeight <= 0 ||
        !metric.devicePixelRatio.isFinite ||
        metric.devicePixelRatio <= 0) {
      return false;
    }
    final response =
        '\u001b]1337;ReportCellSize='
        '${metric.logicalCellHeight.toStringAsFixed(2)};'
        '${metric.logicalCellWidth.toStringAsFixed(2)};'
        '${metric.devicePixelRatio.toStringAsFixed(2)}\u001b\\';
    return _sendInput(
      sessionId,
      Uint8List.fromList(ascii.encode(response)),
      sessionEpoch: sessionEpoch,
    );
  }

  Future<void> _handleClipboardCopyEvent(
    String sessionId,
    int sessionEpoch,
    Map<String, Object?>? payload,
  ) async {
    if (!_isCurrentSession(sessionId, sessionEpoch)) {
      return;
    }
    final selection = _nonEmptyTrimmedStringFromJsonValue(
      payload?['selection'],
    );
    final protocol = switch (_nonEmptyTrimmedStringFromJsonValue(
      payload?['protocol'],
    )?.toLowerCase()) {
      'iterm1337' => 'iterm1337',
      _ => 'osc52',
    };
    if (payload == null) {
      _emitEventIfCurrent(
        sessionId,
        sessionEpoch,
        TerminalSessionClipboardEvent(
          sessionId,
          operation: TerminalClipboardOperation.copy,
          decision: TerminalClipboardDecision.invalidPayload,
          selection: selection,
          protocol: protocol,
        ),
      );
      return;
    }
    final raw = _stringFromJsonValue(payload['data']);
    if (raw == null) {
      _emitEventIfCurrent(
        sessionId,
        sessionEpoch,
        TerminalSessionClipboardEvent(
          sessionId,
          operation: TerminalClipboardOperation.copy,
          decision: TerminalClipboardDecision.invalidPayload,
          selection: selection,
          protocol: protocol,
        ),
      );
      return;
    }
    final bytes = _decodeOsc52ClipboardPayload(raw);
    if (bytes == null) {
      _emitEventIfCurrent(
        sessionId,
        sessionEpoch,
        TerminalSessionClipboardEvent(
          sessionId,
          operation: TerminalClipboardOperation.copy,
          decision: TerminalClipboardDecision.invalidPayload,
          selection: selection,
          protocol: protocol,
        ),
      );
      return;
    }
    late final String decoded;
    try {
      decoded = utf8.decode(bytes);
    } on FormatException {
      _emitEventIfCurrent(
        sessionId,
        sessionEpoch,
        TerminalSessionClipboardEvent(
          sessionId,
          operation: TerminalClipboardOperation.copy,
          decision: TerminalClipboardDecision.invalidPayload,
          selection: selection,
          protocol: protocol,
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
      protocol: protocol,
    );
    final allowed = await allowClipboardCopy(request);
    if (!_isCurrentSession(sessionId, sessionEpoch)) {
      return;
    }
    if (!allowed) {
      _emitEventIfCurrent(
        sessionId,
        sessionEpoch,
        TerminalSessionClipboardEvent(
          sessionId,
          operation: TerminalClipboardOperation.copy,
          decision: TerminalClipboardDecision.blocked,
          selection: selection,
          byteCount: summary.byteCount,
          characterCount: summary.characterCount,
          textPreview: summary.preview,
          textPreviewTruncated: summary.previewTruncated,
          protocol: protocol,
        ),
      );
      return;
    }
    try {
      await writeTextClipboard(decoded, selection ?? 'c');
    } on Object {
      _emitEventIfCurrent(
        sessionId,
        sessionEpoch,
        TerminalSessionClipboardEvent(
          sessionId,
          operation: TerminalClipboardOperation.copy,
          decision: TerminalClipboardDecision.invalidPayload,
          selection: selection,
          byteCount: summary.byteCount,
          characterCount: summary.characterCount,
          textPreview: summary.preview,
          textPreviewTruncated: summary.previewTruncated,
          protocol: protocol,
        ),
      );
      return;
    }
    if (!_isCurrentSession(sessionId, sessionEpoch)) {
      return;
    }
    _emitEventIfCurrent(
      sessionId,
      sessionEpoch,
      TerminalSessionClipboardEvent(
        sessionId,
        operation: TerminalClipboardOperation.copy,
        decision: TerminalClipboardDecision.allowed,
        selection: selection,
        byteCount: summary.byteCount,
        characterCount: summary.characterCount,
        textPreview: summary.preview,
        textPreviewTruncated: summary.previewTruncated,
        protocol: protocol,
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
    int sessionEpoch,
    Map<String, Object?>? payload,
  ) async {
    if (!_isCurrentSession(sessionId, sessionEpoch)) {
      return;
    }
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
    final allowed = await allowClipboardPasteRequest(request);
    if (!_isCurrentSession(sessionId, sessionEpoch)) {
      return;
    }
    if (!allowed) {
      _emitEventIfCurrent(
        sessionId,
        sessionEpoch,
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
    if (!_isCurrentSession(sessionId, sessionEpoch)) {
      return;
    }
    final clipboardBytes = _boundedUtf8Encode(
      clipboardText,
      _maxOsc52ClipboardDecodedBytes,
    );
    if (clipboardBytes == null) {
      _emitEventIfCurrent(
        sessionId,
        sessionEpoch,
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
    if (!_sendInput(
      sessionId,
      Uint8List.fromList(utf8.encode(response)),
      sessionEpoch: sessionEpoch,
    )) {
      return;
    }
    _emitEventIfCurrent(
      sessionId,
      sessionEpoch,
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

  Future<void> _handleClipboardMimeWrite(
    String sessionId,
    int sessionEpoch,
    Map<String, Object?>? payload,
  ) async {
    final id = _osc5522Id(payload?['id']);
    final location = _stringFromJsonValue(payload?['location']);
    final password = _osc5522Credential(payload?['password'], maxBytes: 256);
    final applicationName = _osc5522Credential(
      payload?['applicationName'],
      maxBytes: 256,
      rejectControls: true,
    );
    final rawItems = payload?['items'];
    if (location != 'clipboard' ||
        (payload?.containsKey('password') == true && password == null) ||
        (payload?.containsKey('applicationName') == true &&
            applicationName == null) ||
        rawItems is! List<Object?> ||
        rawItems.isEmpty) {
      _sendOsc5522Status(
        sessionId,
        sessionEpoch,
        operation: 'write',
        status: location == 'primary' ? 'ENOSYS' : 'EINVAL',
        id: id,
      );
      return;
    }
    final items = <TerminalClipboardMimeItem>[];
    var totalBytes = 0;
    for (final rawItem in rawItems) {
      if (rawItem is! Map<String, Object?> || items.length >= 64) {
        _sendOsc5522Status(
          sessionId,
          sessionEpoch,
          operation: 'write',
          status: 'EINVAL',
          id: id,
        );
        return;
      }
      final mime = _validOsc5522Mime(rawItem['mime']);
      final encoded = _stringFromJsonValue(rawItem['data']);
      if (mime == null || encoded == null) {
        _sendOsc5522Status(
          sessionId,
          sessionEpoch,
          operation: 'write',
          status: 'EINVAL',
          id: id,
        );
        return;
      }
      final bytes = _decodeOsc52ClipboardPayload(encoded);
      if (bytes == null) {
        _sendOsc5522Status(
          sessionId,
          sessionEpoch,
          operation: 'write',
          status: 'EINVAL',
          id: id,
        );
        return;
      }
      totalBytes += bytes.length;
      if (totalBytes > _maxOsc52ClipboardDecodedBytes) {
        _sendOsc5522Status(
          sessionId,
          sessionEpoch,
          operation: 'write',
          status: 'EINVAL',
          id: id,
        );
        return;
      }
      final aliases = switch (rawItem['aliases']) {
        final List<Object?> values
            when values.length <= 16 &&
                values.every(
                  (value) => value is String && _isValidOsc5522Mime(value),
                ) =>
          values.cast<String>().toList(growable: false),
        null => const <String>[],
        _ => null,
      };
      if (aliases == null) {
        _sendOsc5522Status(
          sessionId,
          sessionEpoch,
          operation: 'write',
          status: 'EINVAL',
          id: id,
        );
        return;
      }
      items.add(
        TerminalClipboardMimeItem(
          mimeType: mime,
          bytes: bytes,
          aliases: aliases,
        ),
      );
    }
    final mimeTypes = items
        .map((item) => item.mimeType)
        .toList(growable: false);
    final authorization = await _authorizeOsc5522Access(
      TerminalClipboardAccessRequest(
        sessionId: sessionId,
        operation: TerminalClipboardOperation.mimeWrite,
        protocol: 'osc5522',
        selection: location,
        byteCount: totalBytes,
        mimeTypes: mimeTypes,
        authorizationPassword: password,
        applicationName: applicationName,
      ),
    );
    if (!_isCurrentSession(sessionId, sessionEpoch)) return;
    if (!authorization.allowed) {
      _sendOsc5522Status(
        sessionId,
        sessionEpoch,
        operation: 'write',
        status: 'EPERM',
        id: id,
      );
      _emitOsc5522ClipboardEvent(
        sessionId,
        sessionEpoch,
        TerminalClipboardOperation.mimeWrite,
        TerminalClipboardDecision.blocked,
        mimeTypes,
        totalBytes,
      );
      return;
    }
    try {
      await writeMimeClipboard(items);
    } on Object {
      _sendOsc5522Status(
        sessionId,
        sessionEpoch,
        operation: 'write',
        status: 'EIO',
        id: id,
      );
      _emitOsc5522ClipboardEvent(
        sessionId,
        sessionEpoch,
        TerminalClipboardOperation.mimeWrite,
        TerminalClipboardDecision.invalidPayload,
        mimeTypes,
        totalBytes,
      );
      return;
    }
    if (!_isCurrentSession(sessionId, sessionEpoch)) return;
    _sendOsc5522Status(
      sessionId,
      sessionEpoch,
      operation: 'write',
      status: 'DONE',
      id: id,
    );
    _emitOsc5522ClipboardEvent(
      sessionId,
      sessionEpoch,
      TerminalClipboardOperation.mimeWrite,
      TerminalClipboardDecision.allowed,
      mimeTypes,
      totalBytes,
    );
  }

  Future<void> _handleClipboardMimeReadRequest(
    String sessionId,
    int sessionEpoch,
    Map<String, Object?>? payload,
  ) async {
    final id = _osc5522Id(payload?['id']);
    final location = _stringFromJsonValue(payload?['location']);
    final password = _osc5522Credential(payload?['password'], maxBytes: 256);
    final applicationName = _osc5522Credential(
      payload?['applicationName'],
      maxBytes: 256,
      rejectControls: true,
    );
    final listOnly = payload?['listOnly'] == true;
    final mimeTypes = switch (payload?['mimeTypes']) {
      final List<Object?> values
          when values.length <= 64 &&
              values.every((value) => value is String) =>
        values.cast<String>().toList(growable: false),
      _ => const <String>[],
    };
    final validRequest = listOnly
        ? mimeTypes.length == 1 && mimeTypes.single == '.'
        : mimeTypes.isNotEmpty && mimeTypes.every(_isValidOsc5522MimePattern);
    if (location != 'clipboard' ||
        (payload?.containsKey('password') == true && password == null) ||
        (payload?.containsKey('applicationName') == true &&
            applicationName == null) ||
        !validRequest) {
      _sendOsc5522Status(
        sessionId,
        sessionEpoch,
        operation: 'read',
        status: location == 'primary' ? 'ENOSYS' : 'EINVAL',
        id: id,
      );
      return;
    }
    if (listOnly) {
      try {
        final available =
            (await listClipboardMimeTypes())
                .where(_isValidOsc5522Mime)
                .toSet()
                .take(64)
                .toList()
              ..sort();
        if (!_isCurrentSession(sessionId, sessionEpoch)) return;
        _sendOsc5522ReadData(
          sessionId,
          sessionEpoch,
          id: id,
          items: <TerminalClipboardMimeItem>[
            TerminalClipboardMimeItem(
              mimeType: '.',
              bytes: Uint8List.fromList(utf8.encode(available.join(' '))),
            ),
          ],
        );
      } on Object {
        _sendOsc5522Status(
          sessionId,
          sessionEpoch,
          operation: 'read',
          status: 'EIO',
          id: id,
        );
      }
      return;
    }
    final authorization = await _authorizeOsc5522Access(
      TerminalClipboardAccessRequest(
        sessionId: sessionId,
        operation: TerminalClipboardOperation.mimeRead,
        protocol: 'osc5522',
        selection: location,
        mimeTypes: mimeTypes,
        authorizationPassword: password,
        applicationName: applicationName,
      ),
    );
    if (!_isCurrentSession(sessionId, sessionEpoch)) return;
    if (!authorization.allowed) {
      _sendOsc5522Status(
        sessionId,
        sessionEpoch,
        operation: 'read',
        status: 'EPERM',
        id: id,
      );
      _emitOsc5522ClipboardEvent(
        sessionId,
        sessionEpoch,
        TerminalClipboardOperation.mimeRead,
        TerminalClipboardDecision.blocked,
        mimeTypes,
        null,
      );
      return;
    }
    try {
      final items = (await readMimeClipboard(mimeTypes))
          .where(
            (item) =>
                _isValidOsc5522Mime(item.mimeType) &&
                mimeTypes.any(
                  (pattern) => _mimePatternMatches(pattern, item.mimeType),
                ),
          )
          .take(64)
          .toList(growable: false);
      if (!_isCurrentSession(sessionId, sessionEpoch)) return;
      if (items.isEmpty ||
          items.fold<int>(0, (total, item) => total + item.bytes.length) >
              _maxOsc52ClipboardDecodedBytes) {
        _sendOsc5522Status(
          sessionId,
          sessionEpoch,
          operation: 'read',
          status: 'ENOSYS',
          id: id,
        );
        return;
      }
      _sendOsc5522ReadData(sessionId, sessionEpoch, id: id, items: items);
      _emitOsc5522ClipboardEvent(
        sessionId,
        sessionEpoch,
        TerminalClipboardOperation.mimeRead,
        TerminalClipboardDecision.allowed,
        items.map((item) => item.mimeType).toList(growable: false),
        items.fold<int>(0, (total, item) => total + item.bytes.length),
      );
    } on Object {
      _sendOsc5522Status(
        sessionId,
        sessionEpoch,
        operation: 'read',
        status: 'EIO',
        id: id,
      );
    }
  }

  Future<void> _handleClipboardMimeError(
    String sessionId,
    int sessionEpoch,
    Map<String, Object?>? payload,
  ) async {
    final operation = _stringFromJsonValue(payload?['operation']);
    final status = _stringFromJsonValue(payload?['status']);
    if ((operation == 'read' || operation == 'write') &&
        status != null &&
        const <String>{
          'EINVAL',
          'ENOSYS',
          'EPERM',
          'EBUSY',
          'EIO',
        }.contains(status)) {
      _sendOsc5522Status(
        sessionId,
        sessionEpoch,
        operation: operation!,
        status: status,
        id: _osc5522Id(payload?['id']),
      );
    }
  }

  void _sendOsc5522ReadData(
    String sessionId,
    int sessionEpoch, {
    required String? id,
    required List<TerminalClipboardMimeItem> items,
  }) {
    _sendOsc5522Status(
      sessionId,
      sessionEpoch,
      operation: 'read',
      status: 'OK',
      id: id,
    );
    for (final item in items) {
      final encodedMime = base64.encode(utf8.encode(item.mimeType));
      final chunks = item.bytes.isEmpty
          ? <Uint8List>[Uint8List(0)]
          : <Uint8List>[
              for (
                var offset = 0;
                offset < item.bytes.length;
                offset += _osc5522ChunkBytes
              )
                Uint8List.sublistView(
                  item.bytes,
                  offset,
                  (offset + _osc5522ChunkBytes).clamp(0, item.bytes.length),
                ),
            ];
      for (final chunk in chunks) {
        final metadata = _osc5522Metadata(
          'read',
          id: id,
          status: 'DATA',
          mime: encodedMime,
        );
        _sendInput(
          sessionId,
          Uint8List.fromList(
            ascii.encode(
              '\u001b]5522;$metadata;${base64.encode(chunk)}\u001b\\',
            ),
          ),
          sessionEpoch: sessionEpoch,
        );
      }
    }
    _sendOsc5522Status(
      sessionId,
      sessionEpoch,
      operation: 'read',
      status: 'DONE',
      id: id,
    );
  }

  void _sendOsc5522Status(
    String sessionId,
    int sessionEpoch, {
    required String operation,
    required String status,
    required String? id,
  }) {
    final metadata = _osc5522Metadata(operation, status: status, id: id);
    _sendInput(
      sessionId,
      Uint8List.fromList(ascii.encode('\u001b]5522;$metadata\u001b\\')),
      sessionEpoch: sessionEpoch,
    );
  }

  String _osc5522Metadata(
    String operation, {
    String? status,
    String? id,
    String? mime,
  }) => <String>[
    'type=$operation',
    if (status != null) 'status=$status',
    if (mime != null) 'mime=$mime',
    if (id != null) 'id=$id',
  ].join(':');

  String? _osc5522Id(Object? value) {
    final id = _stringFromJsonValue(value);
    if (id == null ||
        id.isEmpty ||
        id.length > 128 ||
        !RegExp(r'^[A-Za-z0-9_+.-]+$').hasMatch(id)) {
      return null;
    }
    return id;
  }

  String? _osc5522Credential(
    Object? value, {
    required int maxBytes,
    bool rejectControls = false,
  }) {
    final credential = _stringFromJsonValue(value);
    if (credential == null || credential.isEmpty) {
      return null;
    }
    final bytes = utf8.encode(credential);
    if (bytes.length > maxBytes ||
        (rejectControls &&
            credential.runes.any((rune) => rune < 0x20 || rune == 0x7f))) {
      return null;
    }
    return credential;
  }

  Future<TerminalClipboardAuthorization> _authorizeOsc5522Access(
    TerminalClipboardAccessRequest request,
  ) async {
    final password = request.authorizationPassword;
    if (password != null &&
        request.operation == TerminalClipboardOperation.mimeRead) {
      final tokens = _osc5522PasteTokens[request.sessionId];
      final token = tokens?[password];
      if (token != null) {
        if (token.expiresAt <= _monotonicNow) {
          tokens!.remove(password);
        } else if (token.location == request.selection) {
          tokens!.remove(password);
          return TerminalClipboardAuthorization.allowOnce;
        }
      }
    }
    final applicationName = request.applicationName;
    final cacheKey = password != null && applicationName != null
        ? jsonEncode(<String>[applicationName, password])
        : null;
    if (cacheKey != null &&
        (_osc5522RememberedPasswords[request.sessionId]?.contains(cacheKey) ??
            false)) {
      return TerminalClipboardAuthorization.allowOnce;
    }
    final authorization = await authorizeMimeClipboardAccess(request);
    if (authorization.allowed &&
        authorization.rememberPassword &&
        cacheKey != null) {
      final remembered = _osc5522RememberedPasswords.putIfAbsent(
        request.sessionId,
        () => <String>[],
      );
      remembered.remove(cacheKey);
      remembered.add(cacheKey);
      while (remembered.length > _osc5522MaxRememberedPasswords) {
        remembered.removeAt(0);
      }
    }
    return authorization;
  }

  String? _validOsc5522Mime(Object? value) {
    final mime = _stringFromJsonValue(value);
    return mime != null && _isValidOsc5522Mime(mime) ? mime : null;
  }

  bool _isValidOsc5522Mime(String mime) =>
      mime.length <= 255 &&
      RegExp(r'^[A-Za-z0-9!#\$&^_.+-]+/[A-Za-z0-9!#\$&^_.+-]+$').hasMatch(mime);

  bool _isValidOsc5522MimePattern(String pattern) =>
      pattern == '*/*' ||
      (pattern.length <= 255 &&
          RegExp(
            r'^(?:\*|[A-Za-z0-9!#\$&^_.+-]+)/(?:\*|[A-Za-z0-9!#\$&^_.+-]+)$',
          ).hasMatch(pattern));

  bool _mimePatternMatches(String pattern, String mime) {
    if (pattern == '*/*') return true;
    final slash = pattern.indexOf('/');
    if (slash < 1) return pattern == mime;
    final major = pattern.substring(0, slash);
    final minor = pattern.substring(slash + 1);
    final mimeParts = mime.split('/');
    return mimeParts.length == 2 &&
        (major == '*' || major == mimeParts[0]) &&
        (minor == '*' || minor == mimeParts[1]);
  }

  void _emitOsc5522ClipboardEvent(
    String sessionId,
    int sessionEpoch,
    TerminalClipboardOperation operation,
    TerminalClipboardDecision decision,
    List<String> mimeTypes,
    int? byteCount,
  ) {
    _emitEventIfCurrent(
      sessionId,
      sessionEpoch,
      TerminalSessionClipboardEvent(
        sessionId,
        operation: operation,
        decision: decision,
        protocol: 'osc5522',
        selection: 'clipboard',
        mimeTypes: List<String>.unmodifiable(mimeTypes),
        byteCount: byteCount,
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
    _framePumpController.remove(sessionId);
    _refreshHintDisabledSessions.remove(sessionId);
    _pendingRefreshTraces.remove(sessionId);
    _activeRefreshTraces.remove(sessionId);
    _pendingFullPollRequests.remove(sessionId);
    _pendingCellSizeReports.remove(sessionId);
    _refreshIdSeeds.remove(sessionId);
    _sessionEpochs.remove(sessionId);
    _lastFrameAppliedAt.remove(sessionId);
    _osc5522RememberedPasswords.remove(sessionId);
    _osc5522PasteTokens.remove(sessionId);
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

final class _TerminalRefreshTrace {
  _TerminalRefreshTrace({
    required this.refreshId,
    required this.requestReason,
    required this.refreshRequestedMicros,
  });

  final int refreshId;
  final String requestReason;
  final int refreshRequestedMicros;
  int? refreshStartedMicros;
  int? frameTakenMicros;
  int? frameAppliedMicros;
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
