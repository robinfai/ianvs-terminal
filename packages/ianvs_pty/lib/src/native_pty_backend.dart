import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _PingNative = ffi.Int32 Function();
typedef _PingDart = int Function();
typedef _CreateSessionNative = ffi.Uint64 Function(ffi.Pointer<Utf8>);
typedef _CreateSessionDart = int Function(ffi.Pointer<Utf8>);
typedef _CloseSessionNative = ffi.Int32 Function(ffi.Uint64);
typedef _CloseSessionDart = int Function(int);
typedef _ResizeSessionNative =
    ffi.Int32 Function(
      ffi.Uint64,
      ffi.Uint16,
      ffi.Uint16,
      ffi.Uint16,
      ffi.Uint16,
    );
typedef _ResizeSessionDart = int Function(int, int, int, int, int);
typedef _ResizeSessionWithCellSizeNative =
    ffi.Int32 Function(
      ffi.Uint64,
      ffi.Uint16,
      ffi.Uint16,
      ffi.Uint16,
      ffi.Uint16,
      ffi.Uint16,
      ffi.Uint16,
    );
typedef _ResizeSessionWithCellSizeDart =
    int Function(int, int, int, int, int, int, int);
typedef _WriteSessionNative =
    ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Uint8>, ffi.Size);
typedef _WriteSessionDart = int Function(int, ffi.Pointer<ffi.Uint8>, int);
typedef _ScrollSessionNative = ffi.Int32 Function(ffi.Uint64, ffi.Int32);
typedef _ScrollSessionDart = int Function(int, int);
typedef _ScrollToSessionNative = ffi.Int32 Function(ffi.Uint64, ffi.Size);
typedef _ScrollToSessionDart = int Function(int, int);
typedef _RequestSessionNative =
    ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Pointer<Utf8>);
typedef _RequestSessionDart =
    ffi.Pointer<Utf8> Function(int, ffi.Pointer<Utf8>);
typedef _StringReturningNative = ffi.Pointer<Utf8> Function(ffi.Uint64);
typedef _StringReturningDart = ffi.Pointer<Utf8> Function(int);
typedef _FreeStringNative = ffi.Void Function(ffi.Pointer<Utf8>);
typedef _FreeStringDart = void Function(ffi.Pointer<Utf8>);
typedef _BytesReturningNative =
    ffi.Pointer<ffi.Uint8> Function(ffi.Uint64, ffi.Pointer<ffi.Size>);
typedef _BytesReturningDart =
    ffi.Pointer<ffi.Uint8> Function(int, ffi.Pointer<ffi.Size>);
typedef _FreeBytesNative = ffi.Void Function(ffi.Pointer<ffi.Uint8>, ffi.Size);
typedef _FreeBytesDart = void Function(ffi.Pointer<ffi.Uint8>, int);
typedef _GraphicAssetMetaNative =
    ffi.Int32 Function(
      ffi.Uint64,
      ffi.Uint64,
      ffi.Uint64,
      ffi.Pointer<_NativeGraphicAssetMeta>,
    );
typedef _GraphicAssetMetaDart =
    int Function(int, int, int, ffi.Pointer<_NativeGraphicAssetMeta>);
typedef _GraphicAssetRgbaCopyNative =
    ffi.IntPtr Function(
      ffi.Uint64,
      ffi.Uint64,
      ffi.Uint64,
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
    );
typedef _GraphicAssetRgbaCopyDart =
    int Function(int, int, int, ffi.Pointer<ffi.Uint8>, int);

const _maxUint16 = 0xffff;
const _minInt32 = -0x80000000;
const _maxInt32 = 0x7fffffff;
const _maxEventKindLength = 128;
const _maxPtyEventBatchLength = 1024;
final _sessionIdDigits = RegExp(r'^[0-9]+$');
final _maxUint64 = BigInt.parse('18446744073709551615');

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

_RequestSessionDart? _lookupOptionalRequestSession(
  ffi.DynamicLibrary library,
  String symbolName,
) {
  try {
    return library.lookupFunction<_RequestSessionNative, _RequestSessionDart>(
      symbolName,
    );
  } on ArgumentError {
    return null;
  }
}

_BytesReturningDart? _lookupOptionalBytesReturning(
  ffi.DynamicLibrary library,
  String symbolName,
) {
  try {
    return library.lookupFunction<_BytesReturningNative, _BytesReturningDart>(
      symbolName,
    );
  } on ArgumentError {
    return null;
  }
}

_FreeBytesDart? _lookupOptionalFreeBytes(
  ffi.DynamicLibrary library,
  String symbolName,
) {
  try {
    return library.lookupFunction<_FreeBytesNative, _FreeBytesDart>(symbolName);
  } on ArgumentError {
    return null;
  }
}

_ResizeSessionWithCellSizeDart? _lookupOptionalResizeSessionWithCellSize(
  ffi.DynamicLibrary library,
) {
  try {
    return library.lookupFunction<
      _ResizeSessionWithCellSizeNative,
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
    return library
        .lookupFunction<_GraphicAssetMetaNative, _GraphicAssetMetaDart>(
          'ianvs_session_graphic_asset_meta',
        );
  } on ArgumentError {
    return null;
  }
}

_GraphicAssetRgbaCopyDart? _lookupOptionalGraphicAssetRgbaCopy(
  ffi.DynamicLibrary library,
) {
  try {
    return library
        .lookupFunction<_GraphicAssetRgbaCopyNative, _GraphicAssetRgbaCopyDart>(
          'ianvs_session_graphic_asset_rgba_copy',
        );
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

  @override
  String toString() {
    return 'PtyNativeCallException: $operation failed for session '
        '$sessionId with status $statusCode';
  }
}

class PtyEvent {
  const PtyEvent({required this.kind, required this.sessionId, this.payload});

  final String kind;
  final String sessionId;
  final Map<String, Object?>? payload;

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

class NativePtyBindings implements PtyBindings {
  NativePtyBindings(ffi.DynamicLibrary library)
    : _ping = library.lookupFunction<_PingNative, _PingDart>('ianvs_ping'),
      _createSession = library
          .lookupFunction<_CreateSessionNative, _CreateSessionDart>(
            'ianvs_session_create',
          ),
      _closeSession = library
          .lookupFunction<_CloseSessionNative, _CloseSessionDart>(
            'ianvs_session_close',
          ),
      _resizeSession = library
          .lookupFunction<_ResizeSessionNative, _ResizeSessionDart>(
            'ianvs_session_resize',
          ),
      _resizeSessionWithCellSize = _lookupOptionalResizeSessionWithCellSize(
        library,
      ),
      _writeSession = library
          .lookupFunction<_WriteSessionNative, _WriteSessionDart>(
            'ianvs_session_write',
          ),
      _scrollSession = library
          .lookupFunction<_ScrollSessionNative, _ScrollSessionDart>(
            'ianvs_session_scroll',
          ),
      _scrollToSession = library
          .lookupFunction<_ScrollToSessionNative, _ScrollToSessionDart>(
            'ianvs_session_scroll_to',
          ),
      _requestSessionJson = _lookupOptionalRequestSession(
        library,
        'ianvs_session_request_json',
      ),
      _takeFrameDiffJson = library
          .lookupFunction<_StringReturningNative, _StringReturningDart>(
            'ianvs_session_take_frame_diff_json',
          ),
      _takeFrameDiffProtobuf = _lookupOptionalBytesReturning(
        library,
        'ianvs_session_take_frame_diff_protobuf',
      ),
      _takeFrameDebugStatsJson = _lookupOptionalStringReturning(
        library,
        'ianvs_session_take_frame_debug_stats_json',
      ),
      _takeSessionDebugStatsJson = _lookupOptionalStringReturning(
        library,
        'ianvs_session_take_session_debug_stats_json',
      ),
      _pollEventsJson = library
          .lookupFunction<_StringReturningNative, _StringReturningDart>(
            'ianvs_session_poll_events_json',
          ),
      _graphicAssetMeta = _lookupOptionalGraphicAssetMeta(library),
      _graphicAssetRgbaCopy = _lookupOptionalGraphicAssetRgbaCopy(library),
      _stringFree = library.lookupFunction<_FreeStringNative, _FreeStringDart>(
        'ianvs_string_free',
      ),
      _bytesFree = _lookupOptionalFreeBytes(library, 'ianvs_bytes_free');

  final _PingDart _ping;
  final _CreateSessionDart _createSession;
  final _CloseSessionDart _closeSession;
  final _ResizeSessionDart _resizeSession;
  final _ResizeSessionWithCellSizeDart? _resizeSessionWithCellSize;
  final _WriteSessionDart _writeSession;
  final _ScrollSessionDart _scrollSession;
  final _ScrollToSessionDart _scrollToSession;
  final _RequestSessionDart? _requestSessionJson;
  final _StringReturningDart _takeFrameDiffJson;
  final _BytesReturningDart? _takeFrameDiffProtobuf;
  final _StringReturningDart? _takeFrameDebugStatsJson;
  final _StringReturningDart? _takeSessionDebugStatsJson;
  final _StringReturningDart _pollEventsJson;
  final _GraphicAssetMetaDart? _graphicAssetMeta;
  final _GraphicAssetRgbaCopyDart? _graphicAssetRgbaCopy;
  final _FreeStringDart _stringFree;
  final _FreeBytesDart? _bytesFree;

  @override
  bool get supportsFrameDiffProtobuf => _takeFrameDiffProtobuf != null;

  factory NativePtyBindings.load() {
    return NativePtyBindings(
      ffi.DynamicLibrary.open(resolveNativePtyLibraryPath()),
    );
  }

  @override
  int ping() => _ping();

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
  int sessionClose(int sessionId) => _closeSession(sessionId);

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
  int sessionScroll(int sessionId, int deltaLines) =>
      _scrollSession(sessionId, deltaLines);

  @override
  int sessionScrollTo(int sessionId, int offset) =>
      _scrollToSession(sessionId, offset);

  @override
  String? sessionRequestJson(int sessionId, String requestJson) {
    final requestSessionJson = _requestSessionJson;
    if (requestSessionJson == null) {
      return null;
    }
    final requestPointer = requestJson.toNativeUtf8();
    ffi.Pointer<Utf8> resultPointer = ffi.nullptr;
    try {
      resultPointer = requestSessionJson(sessionId, requestPointer);
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

abstract class PtySessionJsonRequestBackend {
  String? requestSessionJson(String sessionId, String requestJson);
}

abstract class PtySessionDiagnosticsBackend {
  String? takeDiagnosticsJson(String sessionId, String kind);
}

abstract class PtySessionGraphicAssetBackend {
  PtyGraphicAsset? loadGraphicAsset(
    String sessionId, {
    required int assetId,
    required int assetVersion,
  });
}

abstract class PtySessionProtobufFrameBackend {
  bool get supportsProtobufFrameDiffs;
  Uint8List? takeFrameDiffProtobuf(String sessionId);
}

class NativePtyBackend
    implements
        PtySessionBackend,
        PtySessionJsonRequestBackend,
        PtySessionDiagnosticsBackend,
        PtySessionGraphicAssetBackend,
        PtySessionProtobufFrameBackend {
  NativePtyBackend(this._bindings);

  final PtyBindings _bindings;

  factory NativePtyBackend.load() => NativePtyBackend(NativePtyBindings.load());

  factory NativePtyBackend.fromBindings(PtyBindings bindings) =>
      NativePtyBackend(bindings);

  @override
  int ping() => _bindings.ping();

  @override
  String createSession(String sessionConfigJson) {
    final sessionId = _bindings.sessionCreateJson(sessionConfigJson);
    if (sessionId == 0) {
      throw StateError('Failed to create session');
    }
    return sessionId.toString();
  }

  @override
  void closeSession(String sessionId) {
    final nativeSessionId = _nativeSessionId(sessionId);
    _checkNativeStatus(
      'closeSession',
      sessionId,
      _bindings.sessionClose(nativeSessionId),
    );
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
    final nativeSessionId = _nativeSessionId(sessionId);
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
    final nativeSessionId = _nativeSessionId(sessionId);
    _validateNativeBytes(bytes);
    _checkNativeStatus(
      'writeInput',
      sessionId,
      _bindings.sessionWrite(nativeSessionId, bytes),
    );
  }

  @override
  void scrollViewport(String sessionId, int deltaLines) {
    _checkNativeStatus(
      'scrollViewport',
      sessionId,
      _bindings.sessionScroll(
        _nativeSessionId(sessionId),
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
        _nativeSessionId(sessionId),
        _nativeNonNegativeOffset(offset),
      ),
    );
  }

  @override
  String? requestSessionJson(String sessionId, String requestJson) {
    return _bindings.sessionRequestJson(
      _nativeSessionId(sessionId),
      requestJson,
    );
  }

  @override
  String? takeFrameDiffJson(String sessionId) {
    return _bindings.sessionTakeFrameDiffJson(_nativeSessionId(sessionId));
  }

  @override
  bool get supportsProtobufFrameDiffs => _bindings.supportsFrameDiffProtobuf;

  @override
  Uint8List? takeFrameDiffProtobuf(String sessionId) {
    return _bindings.sessionTakeFrameDiffProtobuf(_nativeSessionId(sessionId));
  }

  @override
  String? takeDiagnosticsJson(String sessionId, String kind) {
    return _bindings.sessionDiagnosticsJson(_nativeSessionId(sessionId), kind);
  }

  @override
  List<PtyEvent> pollEvents(String sessionId) {
    return _bindings.sessionPollEvents(_nativeSessionId(sessionId));
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
    return _bindings.sessionGraphicAsset(
      _nativeSessionId(sessionId),
      assetId,
      assetVersion,
    );
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
