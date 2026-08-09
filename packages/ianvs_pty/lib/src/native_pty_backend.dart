import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'pty_diagnostic_event_v1.dart';
import 'pty_graphic_asset_packet_v1.dart';
import 'pty_host_request_v1.dart';
import 'pty_runtime_capabilities.dart';
import 'pty_runtime_envelope.dart';

typedef _PingDart = int Function();
typedef _RuntimeCapabilitiesDart = ffi.Pointer<Utf8> Function();
typedef _CreateSessionNative = ffi.Uint64 Function(ffi.Pointer<Utf8>);
typedef _CreateSessionDart = int Function(ffi.Pointer<Utf8>);
typedef _CloseSessionDart = int Function(int);
typedef _RefreshHintDart = int Function(int);
typedef _ResizeSessionDart = int Function(int, int, int, int, int);
typedef _ResizeSessionWithCellSizeDart =
    int Function(int, int, int, int, int, int, int);
typedef _WriteSessionNative =
    ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Uint8>, ffi.Size);
typedef _WriteSessionDart = int Function(int, ffi.Pointer<ffi.Uint8>, int);
typedef _ReplayExitDart = int Function(int, int, int);
typedef _ReplayCheckpointCaptureDart = int Function(int);
typedef _ReplayCheckpointRestoreDart = int Function(int, int);
typedef _ScrollSessionDart = int Function(int, int);
typedef _ScrollToSessionDart = int Function(int, int);
typedef _RequestSessionDart =
    ffi.Pointer<Utf8> Function(int, ffi.Pointer<Utf8>);
typedef _HostResponseDart = int Function(int, ffi.Pointer<Utf8>);
typedef _StringReturningNative = ffi.Pointer<Utf8> Function(ffi.Uint64);
typedef _StringReturningDart = ffi.Pointer<Utf8> Function(int);
typedef _FreeStringDart = void Function(ffi.Pointer<Utf8>);
typedef _BytesReturningDart =
    ffi.Pointer<ffi.Uint8> Function(int, ffi.Pointer<ffi.Size>);
typedef _FramePacketV1Dart =
    ffi.Pointer<ffi.Uint8> Function(int, int, int, ffi.Pointer<ffi.Size>);
typedef _GraphicAssetPacketV1Dart =
    ffi.Pointer<ffi.Uint8> Function(int, int, int, ffi.Pointer<ffi.Size>);
typedef _FreeBytesDart = void Function(ffi.Pointer<ffi.Uint8>, int);
typedef _GraphicAssetMetaDart =
    int Function(int, int, int, ffi.Pointer<_NativeGraphicAssetMeta>);
typedef _GraphicAssetRgbaCopyDart =
    int Function(int, int, int, ffi.Pointer<ffi.Uint8>, int);
typedef _FileDownloadTakeDart =
    int Function(int, int, ffi.Pointer<ffi.Uint8>, int);
typedef _FileDownloadDiscardDart = int Function(int, int);

const _maxUint16 = 0xffff;
const _minInt32 = -0x80000000;
const _maxInt32 = 0x7fffffff;
const _maxEventKindLength = 128;
const _maxPtyEventBatchLength = 1024;
const int _maxFileDownloadBytes = 16 * 1024 * 1024;
final _sessionIdDigits = RegExp(r'^[0-9]+$');
final BigInt _maxUint64 = BigInt.parse('18446744073709551615');

final class _NativeGraphicAssetMeta extends ffi.Struct {
  @ffi.Uint32()
  external int width;

  @ffi.Uint32()
  external int height;

  @ffi.Size()
  external int rgbaLen;

  @ffi.Uint64()
  external int version;
}

_StringReturningDart? _lookupOptionalStringReturning(
  ffi.DynamicLibrary library,
  String symbolName,
) {
  try {
    return library.lookupFunction<_StringReturningNative, _StringReturningDart>(
      symbolName,
    );
  } on ArgumentError {
    return null;
  }
}

_RuntimeCapabilitiesDart? _lookupOptionalRuntimeCapabilities(
  ffi.DynamicLibrary library,
) {
  try {
    return library
        .lookupFunction<ffi.Pointer<Utf8> Function(), _RuntimeCapabilitiesDart>(
          'ianvs_runtime_capabilities_json',
        );
  } on ArgumentError {
    return null;
  }
}

_CreateSessionDart? _lookupOptionalSessionCreate(
  ffi.DynamicLibrary library,
  String symbolName,
) {
  try {
    return library.lookupFunction<_CreateSessionNative, _CreateSessionDart>(
      symbolName,
    );
  } on ArgumentError {
    return null;
  }
}

_RequestSessionDart? _lookupOptionalRequestSession(
  ffi.DynamicLibrary library,
  String symbolName,
) {
  try {
    return library.lookupFunction<
      ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Pointer<Utf8>),
      _RequestSessionDart
    >(symbolName);
  } on ArgumentError {
    return null;
  }
}

_HostResponseDart? _lookupOptionalHostResponse(ffi.DynamicLibrary library) {
  try {
    return library.lookupFunction<
      ffi.Int32 Function(ffi.Uint64, ffi.Pointer<Utf8>),
      _HostResponseDart
    >('ianvs_session_host_response_v1_json');
  } on ArgumentError {
    return null;
  }
}

_BytesReturningDart? _lookupOptionalBytesReturning(
  ffi.DynamicLibrary library,
  String symbolName,
) {
  try {
    return library.lookupFunction<
      ffi.Pointer<ffi.Uint8> Function(ffi.Uint64, ffi.Pointer<ffi.Size>),
      _BytesReturningDart
    >(symbolName);
  } on ArgumentError {
    return null;
  }
}

_FramePacketV1Dart? _lookupOptionalFramePacketV1(ffi.DynamicLibrary library) {
  try {
    return library.lookupFunction<
      ffi.Pointer<ffi.Uint8> Function(
        ffi.Uint64,
        ffi.Uint64,
        ffi.Uint8,
        ffi.Pointer<ffi.Size>,
      ),
      _FramePacketV1Dart
    >('ianvs_session_take_frame_packet_v1_protobuf');
  } on ArgumentError {
    return null;
  }
}

_GraphicAssetPacketV1Dart? _lookupOptionalGraphicAssetPacketV1(
  ffi.DynamicLibrary library,
) {
  try {
    return library.lookupFunction<
      ffi.Pointer<ffi.Uint8> Function(
        ffi.Uint64,
        ffi.Uint64,
        ffi.Uint64,
        ffi.Pointer<ffi.Size>,
      ),
      _GraphicAssetPacketV1Dart
    >('ianvs_session_graphic_asset_packet_v1_protobuf');
  } on ArgumentError {
    return null;
  }
}

_FreeBytesDart? _lookupOptionalFreeBytes(
  ffi.DynamicLibrary library,
  String symbolName,
) {
  try {
    return library.lookupFunction<
      ffi.Void Function(ffi.Pointer<ffi.Uint8>, ffi.Size),
      _FreeBytesDart
    >(symbolName);
  } on ArgumentError {
    return null;
  }
}

_ResizeSessionWithCellSizeDart? _lookupOptionalResizeSessionWithCellSize(
  ffi.DynamicLibrary library,
) {
  try {
    return library.lookupFunction<
      ffi.Int32 Function(
        ffi.Uint64,
        ffi.Uint16,
        ffi.Uint16,
        ffi.Uint16,
        ffi.Uint16,
        ffi.Uint16,
        ffi.Uint16,
      ),
      _ResizeSessionWithCellSizeDart
    >('ianvs_session_resize_with_cell_size');
  } on ArgumentError {
    return null;
  }
}

_GraphicAssetMetaDart? _lookupOptionalGraphicAssetMeta(
  ffi.DynamicLibrary library,
) {
  try {
    return library.lookupFunction<
      ffi.Int32 Function(
        ffi.Uint64,
        ffi.Uint64,
        ffi.Uint64,
        ffi.Pointer<_NativeGraphicAssetMeta>,
      ),
      _GraphicAssetMetaDart
    >('ianvs_session_graphic_asset_meta');
  } on ArgumentError {
    return null;
  }
}

_GraphicAssetRgbaCopyDart? _lookupOptionalGraphicAssetRgbaCopy(
  ffi.DynamicLibrary library,
) {
  try {
    return library.lookupFunction<
      ffi.IntPtr Function(
        ffi.Uint64,
        ffi.Uint64,
        ffi.Uint64,
        ffi.Pointer<ffi.Uint8>,
        ffi.Size,
      ),
      _GraphicAssetRgbaCopyDart
    >('ianvs_session_graphic_asset_rgba_copy');
  } on ArgumentError {
    return null;
  }
}

_FileDownloadTakeDart? _lookupOptionalFileDownloadTake(
  ffi.DynamicLibrary library,
) {
  try {
    return library.lookupFunction<
      ffi.IntPtr Function(
        ffi.Uint64,
        ffi.Uint64,
        ffi.Pointer<ffi.Uint8>,
        ffi.Size,
      ),
      _FileDownloadTakeDart
    >('ianvs_session_file_download_take');
  } on ArgumentError {
    return null;
  }
}

_FileDownloadDiscardDart? _lookupOptionalFileDownloadDiscard(
  ffi.DynamicLibrary library,
) {
  try {
    return library.lookupFunction<
      ffi.Int32 Function(ffi.Uint64, ffi.Uint64),
      _FileDownloadDiscardDart
    >('ianvs_session_file_download_discard');
  } on ArgumentError {
    return null;
  }
}

_RefreshHintDart? _lookupOptionalRefreshHint(ffi.DynamicLibrary library) {
  try {
    return library
        .lookupFunction<ffi.Uint32 Function(ffi.Uint64), _RefreshHintDart>(
          'ianvs_session_refresh_hint',
        );
  } on ArgumentError {
    return null;
  }
}

_CreateSessionDart? _lookupOptionalReplayCreate(ffi.DynamicLibrary library) {
  try {
    return library.lookupFunction<_CreateSessionNative, _CreateSessionDart>(
      'ianvs_replay_session_create',
    );
  } on ArgumentError {
    return null;
  }
}

_WriteSessionDart? _lookupOptionalReplayOutput(ffi.DynamicLibrary library) {
  try {
    return library.lookupFunction<_WriteSessionNative, _WriteSessionDart>(
      'ianvs_replay_session_output',
    );
  } on ArgumentError {
    return null;
  }
}

_WriteSessionDart? _lookupOptionalProtocolReply(ffi.DynamicLibrary library) {
  try {
    return library.lookupFunction<_WriteSessionNative, _WriteSessionDart>(
      'ianvs_session_write_protocol_reply',
    );
  } on ArgumentError {
    return null;
  }
}

_ReplayExitDart? _lookupOptionalReplayExit(ffi.DynamicLibrary library) {
  try {
    return library.lookupFunction<
      ffi.Int32 Function(ffi.Uint64, ffi.Int32, ffi.Int32),
      _ReplayExitDart
    >('ianvs_replay_session_exit');
  } on ArgumentError {
    return null;
  }
}

_ReplayCheckpointCaptureDart? _lookupOptionalReplayCheckpointCapture(
  ffi.DynamicLibrary library,
) {
  try {
    return library.lookupFunction<
      ffi.Uint64 Function(ffi.Uint64),
      _ReplayCheckpointCaptureDart
    >('ianvs_replay_session_checkpoint_capture');
  } on ArgumentError {
    return null;
  }
}

_ReplayCheckpointRestoreDart? _lookupOptionalReplayCheckpointRestore(
  ffi.DynamicLibrary library,
) {
  try {
    return library.lookupFunction<
      ffi.Int32 Function(ffi.Uint64, ffi.Uint64),
      _ReplayCheckpointRestoreDart
    >('ianvs_replay_session_checkpoint_restore');
  } on ArgumentError {
    return null;
  }
}

class PtyGraphicAsset {
  const PtyGraphicAsset({
    required this.assetId,
    required this.assetVersion,
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int assetId;
  final int assetVersion;
  final int width;
  final int height;
  final Uint8List rgba;
}

class PtyNativeCallException implements Exception {
  const PtyNativeCallException({
    required this.operation,
    required this.sessionId,
    required this.statusCode,
  });

  final String operation;
  final String sessionId;
  final int statusCode;

  /// True only when native retained the session so a pending ZMODEM result
  /// can be drained before close is retried.
  bool get isRetryableClose => operation == 'closeSession' && statusCode == -2;

  @override
  String toString() {
    return 'PtyNativeCallException: $operation failed for session '
        '$sessionId with status $statusCode';
  }
}

class PtyEvent {
  const PtyEvent({
    required this.kind,
    required this.sessionId,
    this.payload,
    this.sequence,
    this.timestampMicros,
    this.wireSchemaVersion,
    this.hostRequest,
  });

  final String kind;
  final String sessionId;
  final Map<String, Object?>? payload;
  final int? sequence;
  final int? timestampMicros;
  final int? wireSchemaVersion;
  final PtyHostRequestV1? hostRequest;

  factory PtyEvent.fromJson(Map<String, Object?> json) {
    final event = PtyEvent.tryFromJson(json);
    if (event == null) {
      throw const FormatException('Invalid PTY event payload');
    }
    return event;
  }

  static PtyEvent? tryFromJson(Object? json) {
    final map = _stringKeyedJsonMap(json);
    if (map == null) {
      return null;
    }
    final kind = _eventKindFromJson(map['kind']);
    final sessionId = _sessionIdFromJson(map['session_id']);
    if (kind == null || sessionId == null) {
      return null;
    }
    return PtyEvent(
      kind: kind,
      sessionId: sessionId,
      payload: _stringKeyedJsonMap(map['payload']),
    );
  }

  static List<PtyEvent> listFromJson(Object? json) {
    if (json is! List) {
      return const <PtyEvent>[];
    }
    final events = <PtyEvent>[];
    for (final entry in json.take(_maxPtyEventBatchLength)) {
      final event = PtyEvent.tryFromJson(entry);
      if (event != null) {
        events.add(event);
      }
    }
    return events;
  }
}

/// A synthetic, local diagnostic inserted before surviving Runtime Event v1
/// messages when their sequence cursor proves that native events were lost.
///
/// This event has no wire sequence of its own. It is emitted only when
/// [NativePtyBackend] was constructed with
/// `emitRuntimeEventGapDiagnostics: true`, allowing an opted-in controller to
/// reconcile sensitive state before it processes any surviving native event.
final class PtyRuntimeEventGapDiagnostic extends PtyEvent {
  PtyRuntimeEventGapDiagnostic({
    required super.sessionId,
    required this.expectedSequence,
    required this.nextSequence,
    required this.droppedCount,
    required this.survivingEventCount,
  }) : super(
         kind: 'runtime_event_gap',
         payload: Map<String, Object?>.unmodifiable(<String, Object?>{
           'code': 'event_sequence_gap',
           'expectedSequence': expectedSequence,
           'nextSequence': nextSequence,
           'droppedCount': droppedCount,
           'survivingEventCount': survivingEventCount,
         }),
         wireSchemaVersion: ptyRuntimeEnvelopeSchemaVersion,
       );

  final int expectedSequence;
  final int nextSequence;
  final int droppedCount;
  final int survivingEventCount;
}

String? _eventKindFromJson(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length > _maxEventKindLength) {
    return null;
  }
  return trimmed;
}

Map<String, Object?>? _stringKeyedJsonMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  final json = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is String) {
      json[key] = entry.value;
    }
  }
  return json;
}

String? _sessionIdFromJson(Object? value) {
  if (value is int) {
    return _sessionIdStringFromDigits(value.toString());
  }
  if (value is double && value.isFinite) {
    final parsed = value.toInt();
    if (value == parsed) {
      return _sessionIdStringFromDigits(parsed.toString());
    }
  }
  if (value is String) {
    return _sessionIdStringFromDigits(value.trim());
  }
  return null;
}

String? _sessionIdStringFromDigits(String value) {
  if (!_sessionIdDigits.hasMatch(value)) {
    return null;
  }
  final parsed = BigInt.parse(value);
  if (parsed <= BigInt.zero || parsed > _maxUint64) {
    return null;
  }
  return parsed.toString();
}

abstract class PtyBindings {
  bool get supportsFrameDiffProtobuf;
  int ping();
  int sessionCreateJson(String sessionConfigJson);
  int sessionClose(int sessionId);
  int sessionResize(
    int sessionId,
    int cols,
    int rows,
    int pixelWidth,
    int pixelHeight, [
    int cellWidth = 0,
    int cellHeight = 0,
  ]);
  int sessionWrite(int sessionId, List<int> bytes);
  int sessionScroll(int sessionId, int deltaLines);
  int sessionScrollTo(int sessionId, int offset);
  String? sessionRequestJson(int sessionId, String requestJson);
  String? sessionDiagnosticsJson(int sessionId, String kind);
  String? sessionTakeFrameDiffJson(int sessionId);
  Uint8List? sessionTakeFrameDiffProtobuf(int sessionId);
  List<PtyEvent> sessionPollEvents(int sessionId);
  PtyGraphicAsset? sessionGraphicAsset(
    int sessionId,
    int assetId,
    int assetVersion,
  );
}

abstract interface class PtyRefreshHintBindings {
  bool get supportsRefreshHints;
  int sessionRefreshHintFlags(int sessionId);
}

abstract interface class PtyFileDownloadBindings {
  Uint8List? sessionTakeFileDownload(
    int sessionId,
    int downloadId,
    int expectedSize,
  );

  bool sessionDiscardFileDownload(int sessionId, int downloadId);
}

abstract interface class PtyReplayBindings {
  bool get supportsReplaySessions;
  int replaySessionCreateJson(String sessionConfigJson);
  int replaySessionOutput(int sessionId, List<int> bytes);
  int replaySessionExit(int sessionId, int? exitCode);
}

/// Optional native binding surface for complete in-memory replay snapshots.
abstract interface class PtyReplayCheckpointBindings {
  bool get supportsReplayCheckpoints;
  int replaySessionCheckpointCapture(int sessionId);
  bool replaySessionCheckpointRestore(int sessionId, int checkpointId);
}

/// Optional binding surface for the versioned, product-neutral SessionConfig
/// contract. Legacy create methods remain available during the compatibility
/// window.
abstract interface class PtySessionConfigV1Bindings {
  bool get supportsSessionConfigV1;
  bool get supportsReplaySessionConfigV1;
  int sessionCreateV1Json(String sessionConfigV1Json);
  int replaySessionCreateV1Json(String sessionConfigV1Json);
}

abstract interface class PtyRuntimeCapabilityBindings {
  String? runtimeCapabilitiesJson();
}

abstract interface class PtyRuntimeEventBindings {
  bool get supportsRuntimeEventEnvelopes;
  String? sessionPollEventEnvelopesJson(int sessionId);
}

abstract interface class PtySessionRequestV1Bindings {
  bool get supportsSessionRequestV1;
  String? sessionRequestV1Json(int sessionId, String requestV1Json);
}

abstract interface class PtyHostResponseV1Bindings {
  bool get supportsHostResponseV1;
  bool sessionHostResponseV1Json(int sessionId, String responseV1Json);
}

abstract interface class PtyProtocolReplyBindings {
  bool get supportsProtocolReplies;
  int sessionWriteProtocolReply(int sessionId, List<int> bytes);
}

abstract interface class PtyDiagnosticEventV1Bindings {
  bool get supportsDiagnosticEventV1;
  String? sessionTakeDiagnosticEventV1Json(int sessionId, String name);
}

abstract interface class PtyFramePacketV1Bindings {
  bool get supportsFramePacketV1;
  Uint8List? sessionTakeFramePacketV1Protobuf(
    int sessionId, {
    required int? afterSequence,
  });
}

abstract interface class PtyGraphicAssetPacketV1Bindings {
  bool get supportsGraphicAssetPacketV1;
  Uint8List? sessionGraphicAssetPacketV1Protobuf(
    int sessionId,
    int assetId,
    int assetVersion,
  );
}

abstract final class PtyRefreshHintFlags {
  static const int none = 0;
  static const int frameDirty = 1 << 0;
  static const int eventPending = 1 << 1;
  static const int exitPending = 1 << 2;

  static const int anyRefreshWork = frameDirty | eventPending | exitPending;
}

class NativePtyBindings
    implements
        PtyBindings,
        PtyRefreshHintBindings,
        PtyFileDownloadBindings,
        PtyReplayBindings,
        PtyReplayCheckpointBindings,
        PtySessionConfigV1Bindings,
        PtySessionRequestV1Bindings,
        PtyHostResponseV1Bindings,
        PtyProtocolReplyBindings,
        PtyDiagnosticEventV1Bindings,
        PtyFramePacketV1Bindings,
        PtyGraphicAssetPacketV1Bindings,
        PtyRuntimeCapabilityBindings,
        PtyRuntimeEventBindings {
  NativePtyBindings(ffi.DynamicLibrary library)
    : _ping = library.lookupFunction<ffi.Int32 Function(), _PingDart>(
        'ianvs_ping',
      ),
      _runtimeCapabilities = _lookupOptionalRuntimeCapabilities(library),
      _createSession = library
          .lookupFunction<_CreateSessionNative, _CreateSessionDart>(
            'ianvs_session_create',
          ),
      _createSessionV1 = _lookupOptionalSessionCreate(
        library,
        'ianvs_session_create_v1',
      ),
      _replaySessionCreate = _lookupOptionalReplayCreate(library),
      _replaySessionCreateV1 = _lookupOptionalSessionCreate(
        library,
        'ianvs_replay_session_create_v1',
      ),
      _replaySessionOutput = _lookupOptionalReplayOutput(library),
      _replaySessionExit = _lookupOptionalReplayExit(library),
      _replayCheckpointCapture = _lookupOptionalReplayCheckpointCapture(
        library,
      ),
      _replayCheckpointRestore = _lookupOptionalReplayCheckpointRestore(
        library,
      ),
      _closeSession = library
          .lookupFunction<ffi.Int32 Function(ffi.Uint64), _CloseSessionDart>(
            'ianvs_session_close',
          ),
      _refreshHint = _lookupOptionalRefreshHint(library),
      _resizeSession = library
          .lookupFunction<
            ffi.Int32 Function(
              ffi.Uint64,
              ffi.Uint16,
              ffi.Uint16,
              ffi.Uint16,
              ffi.Uint16,
            ),
            _ResizeSessionDart
          >('ianvs_session_resize'),
      _resizeSessionWithCellSize = _lookupOptionalResizeSessionWithCellSize(
        library,
      ),
      _writeSession = library
          .lookupFunction<_WriteSessionNative, _WriteSessionDart>(
            'ianvs_session_write',
          ),
      _writeProtocolReply = _lookupOptionalProtocolReply(library),
      _scrollSession = library
          .lookupFunction<
            ffi.Int32 Function(ffi.Uint64, ffi.Int32),
            _ScrollSessionDart
          >('ianvs_session_scroll'),
      _scrollToSession = library
          .lookupFunction<
            ffi.Int32 Function(ffi.Uint64, ffi.Size),
            _ScrollToSessionDart
          >('ianvs_session_scroll_to'),
      _requestSessionJson = _lookupOptionalRequestSession(
        library,
        'ianvs_session_request_json',
      ),
      _requestSessionV1Json = _lookupOptionalRequestSession(
        library,
        'ianvs_session_request_v1_json',
      ),
      _hostResponseV1 = _lookupOptionalHostResponse(library),
      _takeDiagnosticEventV1Json = _lookupOptionalRequestSession(
        library,
        'ianvs_session_take_diagnostic_event_v1_json',
      ),
      _takeFrameDiffJson = library
          .lookupFunction<_StringReturningNative, _StringReturningDart>(
            'ianvs_session_take_frame_diff_json',
          ),
      _takeFrameDiffProtobuf = _lookupOptionalBytesReturning(
        library,
        'ianvs_session_take_frame_diff_protobuf',
      ),
      _takeFramePacketV1Protobuf = _lookupOptionalFramePacketV1(library),
      _graphicAssetPacketV1Protobuf = _lookupOptionalGraphicAssetPacketV1(
        library,
      ),
      _takeFrameDebugStatsJson = _lookupOptionalStringReturning(
        library,
        'ianvs_session_take_frame_debug_stats_json',
      ),
      _takeSessionDebugStatsJson = _lookupOptionalStringReturning(
        library,
        'ianvs_session_take_session_debug_stats_json',
      ),
      _pollEventEnvelopesJson = _lookupOptionalStringReturning(
        library,
        'ianvs_session_poll_event_envelopes_json',
      ),
      _pollEventsJson = library
          .lookupFunction<_StringReturningNative, _StringReturningDart>(
            'ianvs_session_poll_events_json',
          ),
      _graphicAssetMeta = _lookupOptionalGraphicAssetMeta(library),
      _graphicAssetRgbaCopy = _lookupOptionalGraphicAssetRgbaCopy(library),
      _fileDownloadTake = _lookupOptionalFileDownloadTake(library),
      _fileDownloadDiscard = _lookupOptionalFileDownloadDiscard(library),
      _stringFree = library
          .lookupFunction<
            ffi.Void Function(ffi.Pointer<Utf8>),
            _FreeStringDart
          >('ianvs_string_free'),
      _bytesFree = _lookupOptionalFreeBytes(library, 'ianvs_bytes_free');

  final _PingDart _ping;
  final _RuntimeCapabilitiesDart? _runtimeCapabilities;
  final _CreateSessionDart _createSession;
  final _CreateSessionDart? _createSessionV1;
  final _CreateSessionDart? _replaySessionCreate;
  final _CreateSessionDart? _replaySessionCreateV1;
  final _WriteSessionDart? _replaySessionOutput;
  final _ReplayExitDart? _replaySessionExit;
  final _ReplayCheckpointCaptureDart? _replayCheckpointCapture;
  final _ReplayCheckpointRestoreDart? _replayCheckpointRestore;
  final _CloseSessionDart _closeSession;
  final _RefreshHintDart? _refreshHint;
  final _ResizeSessionDart _resizeSession;
  final _ResizeSessionWithCellSizeDart? _resizeSessionWithCellSize;
  final _WriteSessionDart _writeSession;
  final _WriteSessionDart? _writeProtocolReply;
  final _ScrollSessionDart _scrollSession;
  final _ScrollToSessionDart _scrollToSession;
  final _RequestSessionDart? _requestSessionJson;
  final _RequestSessionDart? _requestSessionV1Json;
  final _HostResponseDart? _hostResponseV1;
  final _RequestSessionDart? _takeDiagnosticEventV1Json;
  final _StringReturningDart _takeFrameDiffJson;
  final _BytesReturningDart? _takeFrameDiffProtobuf;
  final _FramePacketV1Dart? _takeFramePacketV1Protobuf;
  final _GraphicAssetPacketV1Dart? _graphicAssetPacketV1Protobuf;
  final _StringReturningDart? _takeFrameDebugStatsJson;
  final _StringReturningDart? _takeSessionDebugStatsJson;
  final _StringReturningDart? _pollEventEnvelopesJson;
  final _StringReturningDart _pollEventsJson;
  final _GraphicAssetMetaDart? _graphicAssetMeta;
  final _GraphicAssetRgbaCopyDart? _graphicAssetRgbaCopy;
  final _FileDownloadTakeDart? _fileDownloadTake;
  final _FileDownloadDiscardDart? _fileDownloadDiscard;
  final _FreeStringDart _stringFree;
  final _FreeBytesDart? _bytesFree;

  @override
  bool get supportsFrameDiffProtobuf => _takeFrameDiffProtobuf != null;

  @override
  bool get supportsFramePacketV1 =>
      _takeFramePacketV1Protobuf != null && _bytesFree != null;

  @override
  bool get supportsGraphicAssetPacketV1 =>
      _graphicAssetPacketV1Protobuf != null && _bytesFree != null;

  @override
  bool get supportsRefreshHints => _refreshHint != null;

  @override
  bool get supportsReplaySessions =>
      _replaySessionCreate != null &&
      _replaySessionOutput != null &&
      _replaySessionExit != null;

  @override
  bool get supportsReplayCheckpoints =>
      _replayCheckpointCapture != null && _replayCheckpointRestore != null;

  @override
  bool get supportsSessionConfigV1 => _createSessionV1 != null;

  @override
  bool get supportsReplaySessionConfigV1 =>
      _replaySessionCreateV1 != null &&
      _replaySessionOutput != null &&
      _replaySessionExit != null;

  @override
  bool get supportsRuntimeEventEnvelopes => _pollEventEnvelopesJson != null;

  @override
  bool get supportsSessionRequestV1 => _requestSessionV1Json != null;

  @override
  bool get supportsHostResponseV1 => _hostResponseV1 != null;

  @override
  bool get supportsProtocolReplies => _writeProtocolReply != null;

  @override
  bool get supportsDiagnosticEventV1 => _takeDiagnosticEventV1Json != null;

  factory NativePtyBindings.load() {
    return NativePtyBindings(
      Platform.isIOS
          ? ffi.DynamicLibrary.process()
          : ffi.DynamicLibrary.open(resolveNativePtyLibraryPath()),
    );
  }

  @override
  int ping() => _ping();

  @override
  String? runtimeCapabilitiesJson() {
    final binding = _runtimeCapabilities;
    if (binding == null) {
      return null;
    }
    final resultPointer = binding();
    if (resultPointer == ffi.nullptr) {
      return null;
    }
    try {
      return resultPointer.toDartString();
    } finally {
      _stringFree(resultPointer);
    }
  }

  @override
  int sessionCreateJson(String sessionConfigJson) {
    final pointer = sessionConfigJson.toNativeUtf8();
    try {
      return _createSession(pointer);
    } finally {
      malloc.free(pointer);
    }
  }

  @override
  int sessionCreateV1Json(String sessionConfigV1Json) {
    final binding = _createSessionV1;
    if (binding == null) {
      return 0;
    }
    final pointer = sessionConfigV1Json.toNativeUtf8();
    try {
      return binding(pointer);
    } finally {
      malloc.free(pointer);
    }
  }

  @override
  int replaySessionCreateJson(String sessionConfigJson) {
    final binding = _replaySessionCreate;
    if (binding == null) {
      return 0;
    }
    final pointer = sessionConfigJson.toNativeUtf8();
    try {
      return binding(pointer);
    } finally {
      malloc.free(pointer);
    }
  }

  @override
  int replaySessionCreateV1Json(String sessionConfigV1Json) {
    final binding = _replaySessionCreateV1;
    if (binding == null) {
      return 0;
    }
    final pointer = sessionConfigV1Json.toNativeUtf8();
    try {
      return binding(pointer);
    } finally {
      malloc.free(pointer);
    }
  }

  @override
  int replaySessionOutput(int sessionId, List<int> bytes) {
    final binding = _replaySessionOutput;
    if (binding == null) {
      return -1;
    }
    final pointer = malloc<ffi.Uint8>(bytes.isEmpty ? 1 : bytes.length);
    try {
      if (bytes.isNotEmpty) {
        pointer.asTypedList(bytes.length).setAll(0, bytes);
      }
      return binding(sessionId, pointer, bytes.length);
    } finally {
      malloc.free(pointer);
    }
  }

  @override
  int replaySessionExit(int sessionId, int? exitCode) {
    final binding = _replaySessionExit;
    if (binding == null) {
      return -1;
    }
    return binding(sessionId, exitCode ?? 0, exitCode == null ? 0 : 1);
  }

  @override
  int replaySessionCheckpointCapture(int sessionId) {
    return _replayCheckpointCapture?.call(sessionId) ?? 0;
  }

  @override
  bool replaySessionCheckpointRestore(int sessionId, int checkpointId) {
    return _replayCheckpointRestore?.call(sessionId, checkpointId) == 0;
  }

  @override
  int sessionClose(int sessionId) => _closeSession(sessionId);

  @override
  int sessionRefreshHintFlags(int sessionId) =>
      _refreshHint?.call(sessionId) ?? PtyRefreshHintFlags.none;

  @override
  int sessionResize(
    int sessionId,
    int cols,
    int rows,
    int pixelWidth,
    int pixelHeight, [
    int cellWidth = 0,
    int cellHeight = 0,
  ]) {
    final resizeSessionWithCellSize = _resizeSessionWithCellSize;
    if (resizeSessionWithCellSize != null) {
      return resizeSessionWithCellSize(
        sessionId,
        cols,
        rows,
        pixelWidth,
        pixelHeight,
        cellWidth,
        cellHeight,
      );
    }
    return _resizeSession(sessionId, cols, rows, pixelWidth, pixelHeight);
  }

  @override
  int sessionWrite(int sessionId, List<int> bytes) {
    final pointer = malloc<ffi.Uint8>(bytes.length);
    try {
      pointer.asTypedList(bytes.length).setAll(0, bytes);
      return _writeSession(sessionId, pointer, bytes.length);
    } finally {
      malloc.free(pointer);
    }
  }

  @override
  int sessionWriteProtocolReply(int sessionId, List<int> bytes) {
    final binding = _writeProtocolReply;
    if (binding == null) {
      return -1;
    }
    final pointer = malloc<ffi.Uint8>(bytes.length);
    try {
      pointer.asTypedList(bytes.length).setAll(0, bytes);
      return binding(sessionId, pointer, bytes.length);
    } finally {
      malloc.free(pointer);
    }
  }

  @override
  int sessionScroll(int sessionId, int deltaLines) =>
      _scrollSession(sessionId, deltaLines);

  @override
  int sessionScrollTo(int sessionId, int offset) =>
      _scrollToSession(sessionId, offset);

  @override
  String? sessionRequestJson(int sessionId, String requestJson) {
    return _callSessionRequest(_requestSessionJson, sessionId, requestJson);
  }

  @override
  String? sessionRequestV1Json(int sessionId, String requestV1Json) {
    return _callSessionRequest(_requestSessionV1Json, sessionId, requestV1Json);
  }

  @override
  bool sessionHostResponseV1Json(int sessionId, String responseV1Json) {
    final binding = _hostResponseV1;
    if (binding == null) {
      return false;
    }
    final responsePointer = responseV1Json.toNativeUtf8();
    try {
      return binding(sessionId, responsePointer) == 0;
    } finally {
      malloc.free(responsePointer);
    }
  }

  @override
  String? sessionTakeDiagnosticEventV1Json(int sessionId, String name) {
    return _callSessionRequest(_takeDiagnosticEventV1Json, sessionId, name);
  }

  String? _callSessionRequest(
    _RequestSessionDart? binding,
    int sessionId,
    String requestJson,
  ) {
    if (binding == null) {
      return null;
    }
    final requestPointer = requestJson.toNativeUtf8();
    ffi.Pointer<Utf8> resultPointer = ffi.nullptr;
    try {
      resultPointer = binding(sessionId, requestPointer);
      if (resultPointer == ffi.nullptr) {
        return null;
      }
      return resultPointer.toDartString();
    } finally {
      malloc.free(requestPointer);
      if (resultPointer != ffi.nullptr) {
        _stringFree(resultPointer);
      }
    }
  }

  @override
  String? sessionTakeFrameDiffJson(int sessionId) {
    return _callStringReturning(_takeFrameDiffJson, sessionId);
  }

  @override
  Uint8List? sessionTakeFrameDiffProtobuf(int sessionId) {
    final binding = _takeFrameDiffProtobuf;
    final freeBytes = _bytesFree;
    if (binding == null || freeBytes == null) {
      return null;
    }
    final lenPointer = calloc<ffi.Size>();
    ffi.Pointer<ffi.Uint8> resultPointer = ffi.nullptr;
    try {
      resultPointer = binding(sessionId, lenPointer);
      final len = lenPointer.value;
      if (resultPointer == ffi.nullptr || len <= 0) {
        return null;
      }
      return Uint8List.fromList(resultPointer.asTypedList(len));
    } finally {
      if (resultPointer != ffi.nullptr) {
        freeBytes(resultPointer, lenPointer.value);
      }
      calloc.free(lenPointer);
    }
  }

  @override
  Uint8List? sessionTakeFramePacketV1Protobuf(
    int sessionId, {
    required int? afterSequence,
  }) {
    final binding = _takeFramePacketV1Protobuf;
    final freeBytes = _bytesFree;
    if (binding == null || freeBytes == null) {
      return null;
    }
    if (afterSequence != null && afterSequence < 0) {
      throw ArgumentError.value(
        afterSequence,
        'afterSequence',
        'must be non-negative',
      );
    }
    final lenPointer = calloc<ffi.Size>();
    ffi.Pointer<ffi.Uint8> resultPointer = ffi.nullptr;
    try {
      resultPointer = binding(
        sessionId,
        afterSequence ?? 0,
        afterSequence == null ? 0 : 1,
        lenPointer,
      );
      final len = lenPointer.value;
      if (resultPointer == ffi.nullptr || len <= 0) {
        return null;
      }
      return Uint8List.fromList(resultPointer.asTypedList(len));
    } finally {
      if (resultPointer != ffi.nullptr) {
        freeBytes(resultPointer, lenPointer.value);
      }
      calloc.free(lenPointer);
    }
  }

  @override
  Uint8List? sessionGraphicAssetPacketV1Protobuf(
    int sessionId,
    int assetId,
    int assetVersion,
  ) {
    final binding = _graphicAssetPacketV1Protobuf;
    final freeBytes = _bytesFree;
    if (binding == null || freeBytes == null) {
      return null;
    }
    final lenPointer = calloc<ffi.Size>();
    ffi.Pointer<ffi.Uint8> resultPointer = ffi.nullptr;
    try {
      resultPointer = binding(sessionId, assetId, assetVersion, lenPointer);
      final len = lenPointer.value;
      if (resultPointer == ffi.nullptr || len <= 0) {
        return null;
      }
      if (len > ptyGraphicAssetPacketMaxEncodedBytes) {
        throw const PtyGraphicAssetPacketFormatException(
          code: PtyGraphicAssetPacketErrorCode.capacityExceeded,
          message: 'Native Graphic Asset Packet exceeds its encoded byte limit',
        );
      }
      return Uint8List.fromList(resultPointer.asTypedList(len));
    } finally {
      if (resultPointer != ffi.nullptr) {
        freeBytes(resultPointer, lenPointer.value);
      }
      calloc.free(lenPointer);
    }
  }

  @override
  String? sessionDiagnosticsJson(int sessionId, String kind) {
    final binding = switch (kind) {
      'frame' => _takeFrameDebugStatsJson,
      'session' => _takeSessionDebugStatsJson,
      _ => null,
    };
    if (binding == null) {
      return null;
    }
    return _callStringReturning(binding, sessionId);
  }

  String? _callStringReturning(_StringReturningDart binding, int sessionId) {
    final resultPointer = binding(sessionId);
    if (resultPointer == ffi.nullptr) {
      return null;
    }
    try {
      return resultPointer.toDartString();
    } finally {
      _stringFree(resultPointer);
    }
  }

  @override
  List<PtyEvent> sessionPollEvents(int sessionId) {
    final resultPointer = _pollEventsJson(sessionId);
    if (resultPointer == ffi.nullptr) {
      return const <PtyEvent>[];
    }
    try {
      final raw = resultPointer.toDartString();
      return PtyEvent.listFromJson(jsonDecode(raw));
    } on Object {
      return const <PtyEvent>[];
    } finally {
      _stringFree(resultPointer);
    }
  }

  @override
  String? sessionPollEventEnvelopesJson(int sessionId) {
    final binding = _pollEventEnvelopesJson;
    return binding == null ? null : _callStringReturning(binding, sessionId);
  }

  @override
  PtyGraphicAsset? sessionGraphicAsset(
    int sessionId,
    int assetId,
    int assetVersion,
  ) {
    final metaBinding = _graphicAssetMeta;
    final copyBinding = _graphicAssetRgbaCopy;
    if (metaBinding == null || copyBinding == null) {
      return null;
    }

    final metaPointer = calloc<_NativeGraphicAssetMeta>();
    try {
      final metaStatus = metaBinding(
        sessionId,
        assetId,
        assetVersion,
        metaPointer,
      );
      if (metaStatus != 0) {
        return null;
      }
      final meta = metaPointer.ref;
      final rgbaLen = meta.rgbaLen;
      if (meta.width <= 0 || meta.height <= 0 || rgbaLen <= 0) {
        return null;
      }
      final rgbaPointer = malloc<ffi.Uint8>(rgbaLen);
      try {
        final copied = copyBinding(
          sessionId,
          assetId,
          assetVersion,
          rgbaPointer,
          rgbaLen,
        );
        if (copied != rgbaLen) {
          return null;
        }
        return PtyGraphicAsset(
          assetId: assetId,
          assetVersion: meta.version,
          width: meta.width,
          height: meta.height,
          rgba: Uint8List.fromList(rgbaPointer.asTypedList(rgbaLen)),
        );
      } finally {
        malloc.free(rgbaPointer);
      }
    } finally {
      calloc.free(metaPointer);
    }
  }

  @override
  Uint8List? sessionTakeFileDownload(
    int sessionId,
    int downloadId,
    int expectedSize,
  ) {
    final binding = _fileDownloadTake;
    if (binding == null ||
        downloadId <= 0 ||
        expectedSize < 0 ||
        expectedSize > _maxFileDownloadBytes) {
      return null;
    }
    final pointer = malloc<ffi.Uint8>(expectedSize == 0 ? 1 : expectedSize);
    try {
      final copied = binding(sessionId, downloadId, pointer, expectedSize);
      if (copied != expectedSize) {
        return null;
      }
      return Uint8List.fromList(pointer.asTypedList(expectedSize));
    } finally {
      malloc.free(pointer);
    }
  }

  @override
  bool sessionDiscardFileDownload(int sessionId, int downloadId) {
    final binding = _fileDownloadDiscard;
    return binding != null &&
        downloadId > 0 &&
        binding(sessionId, downloadId) == 0;
  }
}

abstract class PtySessionBackend {
  int ping();
  String createSession(String sessionConfigJson);
  void closeSession(String sessionId);
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
    int cellWidth = 0,
    int cellHeight = 0,
  });
  void writeInput(String sessionId, List<int> bytes);
  void scrollViewport(String sessionId, int deltaLines);
  void scrollViewportTo(String sessionId, int offset);
  String? takeFrameDiffJson(String sessionId);
  List<PtyEvent> pollEvents(String sessionId);
}

/// Optional capability for sessions fed by deterministic recorded PTY output
/// instead of a live child process.
abstract interface class PtyReplaySessionBackend {
  String createReplaySession(String sessionConfigJson);
  void replayOutput(String sessionId, List<int> bytes);
  void replayExit(String sessionId, {int? exitCode});
}

/// Optional capability for capturing and restoring complete replay terminal
/// state. Checkpoint IDs are scoped to one replay session.
abstract interface class PtyReplayCheckpointBackend {
  bool get supportsReplayCheckpoints;
  int captureReplayCheckpoint(String sessionId);
  bool restoreReplayCheckpoint(String sessionId, int checkpointId);
}

/// Optional live-session creation path for SessionConfig v1.
abstract interface class PtySessionConfigV1Backend {
  bool get supportsSessionConfigV1;
  String createSessionV1(String sessionConfigV1Json);
}

/// Optional replay-session creation path for SessionConfig v1.
abstract interface class PtyReplaySessionConfigV1Backend {
  bool get supportsReplaySessionConfigV1;
  String createReplaySessionV1(String sessionConfigV1Json);
}

abstract class PtySessionJsonRequestBackend {
  String? requestSessionJson(String sessionId, String requestJson);
}

abstract interface class PtySessionRequestV1Backend {
  bool get supportsSessionRequestV1;
  String? requestSessionV1Json(String sessionId, String requestV1Json);
}

abstract interface class PtyHostResponseV1Backend {
  bool get supportsHostResponseV1;
  bool respondToHostRequestV1(String sessionId, String responseV1Json);
}

/// Optional ordered path for terminal/host protocol replies that may finish
/// while native ZMODEM state is ahead of the Dart event stream.
abstract interface class PtyProtocolReplyBackend {
  bool get supportsProtocolReplies;
  void writeProtocolReply(String sessionId, List<int> bytes);
}

abstract class PtySessionDiagnosticsBackend {
  String? takeDiagnosticsJson(String sessionId, String kind);
}

abstract interface class PtySessionDiagnosticEventV1Backend {
  bool get supportsDiagnosticEventV1;
  PtyDiagnosticEventV1? takeDiagnosticEventV1(String sessionId, String name);
}

abstract class PtySessionGraphicAssetBackend {
  PtyGraphicAsset? loadGraphicAsset(
    String sessionId, {
    required int assetId,
    required int assetVersion,
  });
}

abstract class PtySessionFileDownloadBackend {
  Uint8List? takeFileDownload(
    String sessionId, {
    required int downloadId,
    required int expectedSize,
  });

  bool discardFileDownload(String sessionId, {required int downloadId});
}

abstract class PtySessionProtobufFrameBackend {
  bool get supportsProtobufFrameDiffs;
  Uint8List? takeFrameDiffProtobuf(String sessionId);
}

abstract interface class PtySessionFramePacketV1Backend {
  bool get supportsFramePacketV1;
  Uint8List? takeFramePacketV1Protobuf(
    String sessionId, {
    required int? afterSequence,
  });
}

abstract interface class PtySessionRefreshHintBackend {
  bool get supportsRefreshHints;
  int refreshHintFlags(String sessionId);
}

abstract interface class PtyRuntimeCapabilityBackend {
  PtyRuntimeCapabilities? get runtimeCapabilities;
}

class NativePtyBackend
    implements
        PtySessionBackend,
        PtyReplaySessionBackend,
        PtyReplayCheckpointBackend,
        PtySessionConfigV1Backend,
        PtyReplaySessionConfigV1Backend,
        PtySessionJsonRequestBackend,
        PtySessionRequestV1Backend,
        PtyHostResponseV1Backend,
        PtyProtocolReplyBackend,
        PtySessionDiagnosticsBackend,
        PtySessionDiagnosticEventV1Backend,
        PtySessionGraphicAssetBackend,
        PtySessionFileDownloadBackend,
        PtySessionProtobufFrameBackend,
        PtySessionFramePacketV1Backend,
        PtySessionRefreshHintBackend,
        PtyRuntimeCapabilityBackend {
  NativePtyBackend(
    this._bindings, {
    this.emitRuntimeEventGapDiagnostics = false,
  });

  final PtyBindings _bindings;

  /// When false, a Runtime Event sequence gap preserves the historical public
  /// API behavior and throws `PtyRuntimeContractException`.
  ///
  /// Set this only when the consumer recognizes
  /// [PtyRuntimeEventGapDiagnostic] and reconciles it before survivors.
  final bool emitRuntimeEventGapDiagnostics;
  final Map<String, int> _nativeSessionIds = <String, int>{};
  final Map<int, int> _nextEventSequenceBySession = <int, int>{};

  @override
  late final PtyRuntimeCapabilities? runtimeCapabilities =
      _loadRuntimeCapabilities();

  factory NativePtyBackend.load({
    bool emitRuntimeEventGapDiagnostics = false,
  }) => NativePtyBackend(
    NativePtyBindings.load(),
    emitRuntimeEventGapDiagnostics: emitRuntimeEventGapDiagnostics,
  );

  factory NativePtyBackend.fromBindings(
    PtyBindings bindings, {
    bool emitRuntimeEventGapDiagnostics = false,
  }) => NativePtyBackend(
    bindings,
    emitRuntimeEventGapDiagnostics: emitRuntimeEventGapDiagnostics,
  );

  @override
  int ping() => _bindings.ping();

  PtyRuntimeCapabilities? _loadRuntimeCapabilities() {
    final bindings = _bindings;
    final capabilityBindings = bindings is PtyRuntimeCapabilityBindings
        ? bindings as PtyRuntimeCapabilityBindings
        : null;
    final raw = capabilityBindings?.runtimeCapabilitiesJson();
    return raw == null ? null : PtyRuntimeCapabilities.fromJsonString(raw);
  }

  @override
  String createSession(String sessionConfigJson) {
    final createdSessionId = _bindings.sessionCreateJson(sessionConfigJson);
    return _registerCreatedSession(createdSessionId, 'session');
  }

  @override
  bool get supportsSessionConfigV1 {
    final bindings = _bindings;
    final configBindings = bindings is PtySessionConfigV1Bindings
        ? bindings as PtySessionConfigV1Bindings
        : null;
    return configBindings?.supportsSessionConfigV1 ?? false;
  }

  @override
  String createSessionV1(String sessionConfigV1Json) {
    final bindings = _bindings;
    final configBindings = bindings is PtySessionConfigV1Bindings
        ? bindings as PtySessionConfigV1Bindings
        : null;
    if (configBindings == null || !configBindings.supportsSessionConfigV1) {
      throw UnsupportedError('Native SessionConfig v1 is not supported');
    }
    return _registerCreatedSession(
      configBindings.sessionCreateV1Json(sessionConfigV1Json),
      'SessionConfig v1 session',
    );
  }

  @override
  String createReplaySession(String sessionConfigJson) {
    final bindings = _bindings;
    final replayBindings = bindings is PtyReplayBindings
        ? bindings as PtyReplayBindings
        : null;
    if (replayBindings == null || !replayBindings.supportsReplaySessions) {
      throw UnsupportedError('Native replay sessions are not supported');
    }
    final createdSessionId = replayBindings.replaySessionCreateJson(
      sessionConfigJson,
    );
    return _registerCreatedSession(createdSessionId, 'replay session');
  }

  @override
  bool get supportsReplaySessionConfigV1 {
    final bindings = _bindings;
    final configBindings = bindings is PtySessionConfigV1Bindings
        ? bindings as PtySessionConfigV1Bindings
        : null;
    return configBindings?.supportsReplaySessionConfigV1 ?? false;
  }

  @override
  String createReplaySessionV1(String sessionConfigV1Json) {
    final bindings = _bindings;
    final configBindings = bindings is PtySessionConfigV1Bindings
        ? bindings as PtySessionConfigV1Bindings
        : null;
    if (configBindings == null ||
        !configBindings.supportsReplaySessionConfigV1) {
      throw UnsupportedError('Native replay SessionConfig v1 is not supported');
    }
    return _registerCreatedSession(
      configBindings.replaySessionCreateV1Json(sessionConfigV1Json),
      'SessionConfig v1 replay session',
    );
  }

  String _registerCreatedSession(int createdSessionId, String description) {
    if (createdSessionId == 0) {
      throw StateError('Failed to create $description');
    }
    final sessionId = createdSessionId.toString();
    _nativeSessionIds[sessionId] = createdSessionId;
    _nextEventSequenceBySession[createdSessionId] = 0;
    return sessionId;
  }

  @override
  void replayOutput(String sessionId, List<int> bytes) {
    final bindings = _bindings;
    final replayBindings = bindings is PtyReplayBindings
        ? bindings as PtyReplayBindings
        : null;
    if (replayBindings == null || !replayBindings.supportsReplaySessions) {
      throw UnsupportedError('Native replay sessions are not supported');
    }
    _validateNativeBytes(bytes);
    _checkNativeStatus(
      'replayOutput',
      sessionId,
      replayBindings.replaySessionOutput(_nativeSessionIdFor(sessionId), bytes),
    );
  }

  @override
  void replayExit(String sessionId, {int? exitCode}) {
    final bindings = _bindings;
    final replayBindings = bindings is PtyReplayBindings
        ? bindings as PtyReplayBindings
        : null;
    if (replayBindings == null || !replayBindings.supportsReplaySessions) {
      throw UnsupportedError('Native replay sessions are not supported');
    }
    final nativeExitCode = exitCode == null
        ? null
        : _nativeInt32('exitCode', exitCode);
    _checkNativeStatus(
      'replayExit',
      sessionId,
      replayBindings.replaySessionExit(
        _nativeSessionIdFor(sessionId),
        nativeExitCode,
      ),
    );
  }

  @override
  bool get supportsReplayCheckpoints {
    final bindings = _bindings;
    return bindings is PtyReplayCheckpointBindings &&
        (bindings as PtyReplayCheckpointBindings).supportsReplayCheckpoints;
  }

  @override
  int captureReplayCheckpoint(String sessionId) {
    final bindings = _bindings;
    final checkpointBindings = bindings is PtyReplayCheckpointBindings
        ? bindings as PtyReplayCheckpointBindings
        : null;
    if (checkpointBindings == null ||
        !checkpointBindings.supportsReplayCheckpoints) {
      throw UnsupportedError('Native replay checkpoints are not supported');
    }
    final checkpointId = checkpointBindings.replaySessionCheckpointCapture(
      _nativeSessionIdFor(sessionId),
    );
    if (checkpointId == 0) {
      throw PtyNativeCallException(
        operation: 'captureReplayCheckpoint',
        sessionId: sessionId,
        statusCode: -1,
      );
    }
    return checkpointId;
  }

  @override
  bool restoreReplayCheckpoint(String sessionId, int checkpointId) {
    final bindings = _bindings;
    final checkpointBindings = bindings is PtyReplayCheckpointBindings
        ? bindings as PtyReplayCheckpointBindings
        : null;
    if (checkpointBindings == null ||
        !checkpointBindings.supportsReplayCheckpoints) {
      throw UnsupportedError('Native replay checkpoints are not supported');
    }
    if (checkpointId <= 0) {
      throw ArgumentError.value(
        checkpointId,
        'checkpointId',
        'must be positive',
      );
    }
    return checkpointBindings.replaySessionCheckpointRestore(
      _nativeSessionIdFor(sessionId),
      checkpointId,
    );
  }

  @override
  void closeSession(String sessionId) {
    final nativeSessionId = _nativeSessionIdFor(sessionId);
    _checkNativeStatus(
      'closeSession',
      sessionId,
      _bindings.sessionClose(nativeSessionId),
    );
    // A native busy result intentionally keeps the session alive so its late
    // ZMODEM completion/recovery event can still be polled. Forget mappings
    // only after native confirms that close committed.
    _nativeSessionIds
      ..remove(sessionId)
      ..remove(nativeSessionId.toString());
    _nextEventSequenceBySession.remove(nativeSessionId);
  }

  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
    int cellWidth = 0,
    int cellHeight = 0,
  }) {
    final nativeSessionId = _nativeSessionIdFor(sessionId);
    final nativeCols = _nativeUint16('cols', cols, min: 1);
    final nativeRows = _nativeUint16('rows', rows, min: 1);
    final nativePixelWidth = _nativeUint16('pixelWidth', pixelWidth);
    final nativePixelHeight = _nativeUint16('pixelHeight', pixelHeight);
    final nativeCellWidth = _nativeUint16('cellWidth', cellWidth);
    final nativeCellHeight = _nativeUint16('cellHeight', cellHeight);
    _checkNativeStatus(
      'resizeSession',
      sessionId,
      _bindings.sessionResize(
        nativeSessionId,
        nativeCols,
        nativeRows,
        nativePixelWidth,
        nativePixelHeight,
        nativeCellWidth,
        nativeCellHeight,
      ),
    );
  }

  @override
  void writeInput(String sessionId, List<int> bytes) {
    final nativeSessionId = _nativeSessionIdFor(sessionId);
    _validateNativeBytes(bytes);
    _checkNativeStatus(
      'writeInput',
      sessionId,
      _bindings.sessionWrite(nativeSessionId, bytes),
    );
  }

  @override
  bool get supportsProtocolReplies {
    final bindings = _bindings;
    return bindings is PtyProtocolReplyBindings &&
        (bindings as PtyProtocolReplyBindings).supportsProtocolReplies;
  }

  @override
  void writeProtocolReply(String sessionId, List<int> bytes) {
    final bindings = _bindings;
    if (bindings is! PtyProtocolReplyBindings ||
        !(bindings as PtyProtocolReplyBindings).supportsProtocolReplies) {
      throw UnsupportedError('ordered protocol replies are unavailable');
    }
    final protocolBindings = bindings as PtyProtocolReplyBindings;
    final nativeSessionId = _nativeSessionIdFor(sessionId);
    _validateNativeBytes(bytes);
    _checkNativeStatus(
      'writeProtocolReply',
      sessionId,
      protocolBindings.sessionWriteProtocolReply(nativeSessionId, bytes),
    );
  }

  @override
  void scrollViewport(String sessionId, int deltaLines) {
    _checkNativeStatus(
      'scrollViewport',
      sessionId,
      _bindings.sessionScroll(
        _nativeSessionIdFor(sessionId),
        _nativeInt32('deltaLines', deltaLines),
      ),
    );
  }

  @override
  void scrollViewportTo(String sessionId, int offset) {
    _checkNativeStatus(
      'scrollViewportTo',
      sessionId,
      _bindings.sessionScrollTo(
        _nativeSessionIdFor(sessionId),
        _nativeNonNegativeOffset(offset),
      ),
    );
  }

  @override
  String? requestSessionJson(String sessionId, String requestJson) {
    return _bindings.sessionRequestJson(
      _nativeSessionIdFor(sessionId),
      requestJson,
    );
  }

  @override
  bool get supportsSessionRequestV1 {
    final bindings = _bindings;
    final requestBindings = bindings is PtySessionRequestV1Bindings
        ? bindings as PtySessionRequestV1Bindings
        : null;
    return requestBindings?.supportsSessionRequestV1 ?? false;
  }

  @override
  String? requestSessionV1Json(String sessionId, String requestV1Json) {
    final bindings = _bindings;
    final requestBindings = bindings is PtySessionRequestV1Bindings
        ? bindings as PtySessionRequestV1Bindings
        : null;
    if (requestBindings == null || !requestBindings.supportsSessionRequestV1) {
      throw UnsupportedError('Native Session Request v1 is not supported');
    }
    return requestBindings.sessionRequestV1Json(
      _nativeSessionIdFor(sessionId),
      requestV1Json,
    );
  }

  @override
  bool get supportsHostResponseV1 {
    final bindings = _bindings;
    final hostBindings = bindings is PtyHostResponseV1Bindings
        ? bindings as PtyHostResponseV1Bindings
        : null;
    return hostBindings?.supportsHostResponseV1 ?? false;
  }

  @override
  bool respondToHostRequestV1(String sessionId, String responseV1Json) {
    final bindings = _bindings;
    final hostBindings = bindings is PtyHostResponseV1Bindings
        ? bindings as PtyHostResponseV1Bindings
        : null;
    if (hostBindings == null || !hostBindings.supportsHostResponseV1) {
      throw UnsupportedError('Native Host Response v1 is not supported');
    }
    return hostBindings.sessionHostResponseV1Json(
      _nativeSessionIdFor(sessionId),
      responseV1Json,
    );
  }

  @override
  String? takeFrameDiffJson(String sessionId) {
    return _bindings.sessionTakeFrameDiffJson(_nativeSessionIdFor(sessionId));
  }

  @override
  bool get supportsProtobufFrameDiffs => _bindings.supportsFrameDiffProtobuf;

  @override
  bool get supportsRefreshHints {
    final bindings = _bindings;
    final hintBindings = bindings is PtyRefreshHintBindings
        ? bindings as PtyRefreshHintBindings
        : null;
    return hintBindings?.supportsRefreshHints ?? false;
  }

  @override
  int refreshHintFlags(String sessionId) {
    final bindings = _bindings;
    final hintBindings = bindings is PtyRefreshHintBindings
        ? bindings as PtyRefreshHintBindings
        : null;
    if (hintBindings == null || !hintBindings.supportsRefreshHints) {
      return PtyRefreshHintFlags.none;
    }
    return hintBindings.sessionRefreshHintFlags(_nativeSessionIdFor(sessionId));
  }

  @override
  Uint8List? takeFrameDiffProtobuf(String sessionId) {
    return _bindings.sessionTakeFrameDiffProtobuf(
      _nativeSessionIdFor(sessionId),
    );
  }

  @override
  bool get supportsFramePacketV1 {
    final bindings = _bindings;
    final packetBindings = bindings is PtyFramePacketV1Bindings
        ? bindings as PtyFramePacketV1Bindings
        : null;
    return packetBindings?.supportsFramePacketV1 ?? false;
  }

  @override
  Uint8List? takeFramePacketV1Protobuf(
    String sessionId, {
    required int? afterSequence,
  }) {
    final bindings = _bindings;
    final packetBindings = bindings is PtyFramePacketV1Bindings
        ? bindings as PtyFramePacketV1Bindings
        : null;
    if (packetBindings == null || !packetBindings.supportsFramePacketV1) {
      throw UnsupportedError('Native Frame Packet v1 is not supported');
    }
    return packetBindings.sessionTakeFramePacketV1Protobuf(
      _nativeSessionIdFor(sessionId),
      afterSequence: afterSequence,
    );
  }

  @override
  String? takeDiagnosticsJson(String sessionId, String kind) {
    return _bindings.sessionDiagnosticsJson(
      _nativeSessionIdFor(sessionId),
      kind,
    );
  }

  @override
  bool get supportsDiagnosticEventV1 {
    final bindings = _bindings;
    final diagnosticBindings = bindings is PtyDiagnosticEventV1Bindings
        ? bindings as PtyDiagnosticEventV1Bindings
        : null;
    return diagnosticBindings?.supportsDiagnosticEventV1 ?? false;
  }

  @override
  PtyDiagnosticEventV1? takeDiagnosticEventV1(String sessionId, String name) {
    final bindings = _bindings;
    final diagnosticBindings = bindings is PtyDiagnosticEventV1Bindings
        ? bindings as PtyDiagnosticEventV1Bindings
        : null;
    if (diagnosticBindings == null ||
        !diagnosticBindings.supportsDiagnosticEventV1) {
      throw UnsupportedError('Native Diagnostic Event v1 is not supported');
    }
    final nativeSessionId = _nativeSessionIdFor(sessionId);
    final raw = diagnosticBindings.sessionTakeDiagnosticEventV1Json(
      nativeSessionId,
      name,
    );
    return raw == null
        ? null
        : PtyDiagnosticEventV1.fromJsonString(
            raw,
            expectedSessionId: nativeSessionId.toString(),
            expectedName: name,
          );
  }

  @override
  List<PtyEvent> pollEvents(String sessionId) {
    final nativeSessionId = _nativeSessionIdFor(sessionId);
    final bindings = _bindings;
    final eventBindings = bindings is PtyRuntimeEventBindings
        ? bindings as PtyRuntimeEventBindings
        : null;
    if (eventBindings == null || !eventBindings.supportsRuntimeEventEnvelopes) {
      return bindings.sessionPollEvents(nativeSessionId);
    }

    final raw = eventBindings.sessionPollEventEnvelopesJson(nativeSessionId);
    if (raw == null) {
      return const <PtyEvent>[];
    }
    final batch = PtyRuntimeEventBatch.fromJsonString(raw);
    if (batch.sessionId != nativeSessionId.toString()) {
      throw PtyRuntimeContractException(
        code: 'event_session_mismatch',
        path: r'$.session_id',
        message: 'Runtime Event batch does not belong to session $sessionId',
      );
    }

    final expectedSequenceBeforeBatch =
        _nextEventSequenceBySession[nativeSessionId] ?? 0;
    if (batch.nextSequence < expectedSequenceBeforeBatch) {
      throw PtyRuntimeContractException(
        code: 'event_sequence_reordered',
        path: r'$.next_sequence',
        message:
            'Runtime Event batch cursor moved backwards for session '
            '$sessionId',
      );
    }
    var expectedSequence = expectedSequenceBeforeBatch;
    var sequenceGap = batch.droppedCount > 0;
    for (var index = 0; index < batch.messages.length; index += 1) {
      final message = batch.messages[index];
      final sequence = message.sequence!;
      if (sequence < expectedSequence) {
        throw PtyRuntimeContractException(
          code: 'event_sequence_reordered',
          path: '\$.messages[$index].sequence',
          message: 'Runtime Event sequence was replayed for session $sessionId',
        );
      }
      if (sequence != expectedSequence) {
        sequenceGap = true;
      }
      expectedSequence = sequence + 1;
    }
    if (expectedSequence != batch.nextSequence) {
      sequenceGap = true;
    }
    _nextEventSequenceBySession[nativeSessionId] = batch.nextSequence;
    final events = <PtyEvent>[];
    if (sequenceGap) {
      if (!emitRuntimeEventGapDiagnostics) {
        throw PtyRuntimeContractException(
          code: 'event_sequence_gap',
          path: r'$.messages',
          message:
              'Runtime Event loss detected for session $sessionId; construct '
              'NativePtyBackend with emitRuntimeEventGapDiagnostics: true only '
              'when the consumer reconciles survivors',
        );
      }
      events.add(
        PtyRuntimeEventGapDiagnostic(
          sessionId: sessionId,
          expectedSequence: expectedSequenceBeforeBatch,
          nextSequence: batch.nextSequence,
          droppedCount: batch.droppedCount,
          survivingEventCount: batch.messages.length,
        ),
      );
    }
    events.addAll(batch.messages.map(_eventFromRuntimeEnvelope));
    return List<PtyEvent>.unmodifiable(events);
  }

  PtyEvent _eventFromRuntimeEnvelope(PtyRuntimeEnvelope message) {
    PtyHostRequestV1? hostRequest;
    var kind = message.messageName;
    var payload = _stringKeyedJsonMap(message.payload);
    if (message.messageName == 'host_request') {
      hostRequest = PtyHostRequestV1.fromJson(
        message.payload,
        expectedSessionId: message.sessionId!,
        expectedSequence: message.sequence!,
        expectedTimestampMicros: message.timestampMicros,
      );
      payload = hostRequest.payload;
      if (hostRequest.operation == 'clipboard.read_text') {
        kind = 'clipboard_paste_request';
      }
    }
    return PtyEvent(
      kind: kind,
      sessionId: message.sessionId!,
      payload: payload,
      sequence: message.sequence,
      timestampMicros: message.timestampMicros,
      wireSchemaVersion: message.schemaVersion,
      hostRequest: hostRequest,
    );
  }

  @override
  PtyGraphicAsset? loadGraphicAsset(
    String sessionId, {
    required int assetId,
    required int assetVersion,
  }) {
    if (assetId <= 0) {
      throw ArgumentError.value(assetId, 'assetId', 'must be positive');
    }
    if (assetVersion <= 0) {
      throw ArgumentError.value(
        assetVersion,
        'assetVersion',
        'must be positive',
      );
    }
    final nativeSessionId = _nativeSessionIdFor(sessionId);
    final bindings = _bindings;
    final packetBindings = bindings is PtyGraphicAssetPacketV1Bindings
        ? bindings as PtyGraphicAssetPacketV1Bindings
        : null;
    if (packetBindings?.supportsGraphicAssetPacketV1 ?? false) {
      final bytes = packetBindings!.sessionGraphicAssetPacketV1Protobuf(
        nativeSessionId,
        assetId,
        assetVersion,
      );
      if (bytes == null) {
        return null;
      }
      final packet = PtyGraphicAssetPacketV1.decode(
        bytes,
        expectedSessionId: '$nativeSessionId',
        expectedAssetId: assetId,
        expectedAssetVersion: assetVersion,
      );
      return PtyGraphicAsset(
        assetId: packet.assetId,
        assetVersion: packet.assetVersion,
        width: packet.width,
        height: packet.height,
        rgba: packet.rgba,
      );
    }
    return bindings.sessionGraphicAsset(nativeSessionId, assetId, assetVersion);
  }

  @override
  Uint8List? takeFileDownload(
    String sessionId, {
    required int downloadId,
    required int expectedSize,
  }) {
    if (downloadId <= 0) {
      throw ArgumentError.value(downloadId, 'downloadId', 'must be positive');
    }
    if (expectedSize < 0 || expectedSize > _maxFileDownloadBytes) {
      throw RangeError.range(
        expectedSize,
        0,
        _maxFileDownloadBytes,
        'expectedSize',
      );
    }
    final bindings = _bindings;
    final fileBindings = bindings is PtyFileDownloadBindings
        ? bindings as PtyFileDownloadBindings
        : null;
    return fileBindings?.sessionTakeFileDownload(
      _nativeSessionIdFor(sessionId),
      downloadId,
      expectedSize,
    );
  }

  @override
  bool discardFileDownload(String sessionId, {required int downloadId}) {
    if (downloadId <= 0) {
      return false;
    }
    final bindings = _bindings;
    final fileBindings = bindings is PtyFileDownloadBindings
        ? bindings as PtyFileDownloadBindings
        : null;
    return fileBindings?.sessionDiscardFileDownload(
          _nativeSessionIdFor(sessionId),
          downloadId,
        ) ??
        false;
  }

  int _nativeSessionIdFor(String sessionId) {
    return _nativeSessionIds[sessionId] ?? _nativeSessionId(sessionId);
  }
}

int _nativeSessionId(String sessionId) {
  if (!_sessionIdDigits.hasMatch(sessionId)) {
    throw ArgumentError.value(
      sessionId,
      'sessionId',
      'must be a positive integer',
    );
  }
  final parsedBigInt = BigInt.parse(sessionId);
  if (parsedBigInt <= BigInt.zero) {
    throw ArgumentError.value(
      sessionId,
      'sessionId',
      'must be a positive integer',
    );
  }
  if (parsedBigInt > _maxUint64) {
    throw RangeError('sessionId must fit in uint64: $sessionId');
  }
  final parsed = int.tryParse(sessionId);
  if (parsed == null) {
    throw RangeError('sessionId must fit in Dart int: $sessionId');
  }
  return parsed;
}

void _validateNativeBytes(List<int> bytes) {
  for (var index = 0; index < bytes.length; index += 1) {
    final byte = bytes[index];
    if (byte < 0 || byte > 0xff) {
      throw RangeError.range(byte, 0, 0xff, 'bytes[$index]');
    }
  }
}

int _nativeUint16(String name, int value, {int min = 0}) {
  if (value < min || value > _maxUint16) {
    throw RangeError.range(value, min, _maxUint16, name);
  }
  return value;
}

int _nativeInt32(String name, int value) {
  if (value < _minInt32 || value > _maxInt32) {
    throw RangeError.range(value, _minInt32, _maxInt32, name);
  }
  return value;
}

int _nativeNonNegativeOffset(int offset) {
  if (offset < 0) {
    throw RangeError.range(offset, 0, null, 'offset');
  }
  return offset;
}

void _checkNativeStatus(String operation, String sessionId, int statusCode) {
  if (statusCode != 0) {
    throw PtyNativeCallException(
      operation: operation,
      sessionId: sessionId,
      statusCode: statusCode,
    );
  }
}

String resolveNativePtyLibraryPath({
  Map<String, String>? environment,
  Directory? executableDirectory,
  bool isProduct = const bool.fromEnvironment('dart.vm.product'),
}) {
  final env = environment ?? Platform.environment;
  final executableDir =
      executableDirectory ?? File(Platform.resolvedExecutable).parent;
  final explicit = env['IANVS_CORE_LIB'];
  if (!isProduct && explicit != null && File(explicit).existsSync()) {
    return explicit;
  }

  final candidates = <String>[
    '${executableDir.path}/../Frameworks/libianvs_core.dylib',
    '${executableDir.path}/../Resources/libianvs_core.dylib',
    if (!isProduct) '../native/core/target/debug/libianvs_core.dylib',
    if (!isProduct) '../../native/core/target/debug/libianvs_core.dylib',
  ];

  for (final candidate in candidates) {
    final file = File(candidate);
    if (file.existsSync()) {
      return file.absolute.path;
    }
  }

  if (!isProduct) {
    var directory = executableDir;
    for (var index = 0; index < 10; index += 1) {
      final candidate = File(
        '${directory.path}/../../../../../../../../native/core/target/debug/libianvs_core.dylib',
      );
      if (candidate.existsSync()) {
        return candidate.absolute.path;
      }
      directory = directory.parent;
    }
  }

  final productOverrideNote = isProduct && explicit != null
      ? ' IANVS_CORE_LIB is ignored in product builds.'
      : '';
  final debugOverrideHint = isProduct
      ? ''
      : ' Set IANVS_CORE_LIB to an absolute path.';
  throw StateError(
    'Unable to locate libianvs_core.dylib.$productOverrideNote'
    '$debugOverrideHint',
  );
}

Directory get executableDirectory => File(Platform.resolvedExecutable).parent;
