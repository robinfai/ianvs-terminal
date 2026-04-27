import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

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
typedef _WriteSessionNative =
    ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Uint8>, ffi.Size);
typedef _WriteSessionDart = int Function(int, ffi.Pointer<ffi.Uint8>, int);
typedef _ScrollSessionNative = ffi.Int32 Function(ffi.Uint64, ffi.Int32);
typedef _ScrollSessionDart = int Function(int, int);
typedef _ScrollToSessionNative = ffi.Int32 Function(ffi.Uint64, ffi.Size);
typedef _ScrollToSessionDart = int Function(int, int);
typedef _SearchSessionNative =
    ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Pointer<Utf8>);
typedef _SearchSessionDart = ffi.Pointer<Utf8> Function(int, ffi.Pointer<Utf8>);
typedef _SelectionTextSessionNative =
    ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Pointer<Utf8>);
typedef _SelectionTextSessionDart =
    ffi.Pointer<Utf8> Function(int, ffi.Pointer<Utf8>);
typedef _StringReturningNative = ffi.Pointer<Utf8> Function(ffi.Uint64);
typedef _StringReturningDart = ffi.Pointer<Utf8> Function(int);
typedef _FreeStringNative = ffi.Void Function(ffi.Pointer<Utf8>);
typedef _FreeStringDart = void Function(ffi.Pointer<Utf8>);

class PtyEvent {
  const PtyEvent({required this.kind, required this.sessionId, this.payload});

  final String kind;
  final String sessionId;
  final Map<String, Object?>? payload;

  factory PtyEvent.fromJson(Map<String, Object?> json) {
    return PtyEvent(
      kind: json['kind']! as String,
      sessionId: (json['session_id']! as num).toInt().toString(),
      payload: (json['payload'] as Map?)?.cast<String, Object?>(),
    );
  }
}

abstract class PtyBindings {
  int ping();
  int sessionCreateJson(String sessionConfigJson);
  int sessionClose(int sessionId);
  int sessionResize(
    int sessionId,
    int cols,
    int rows,
    int pixelWidth,
    int pixelHeight,
  );
  int sessionWrite(int sessionId, List<int> bytes);
  int sessionScroll(int sessionId, int deltaLines);
  int sessionScrollTo(int sessionId, int offset);
  String? sessionSearchJson(int sessionId, String query);
  String? sessionSelectionText(int sessionId, String requestJson);
  String? sessionTakeFrameDiffJson(int sessionId);
  List<PtyEvent> sessionPollEvents(int sessionId);
}

class NativePtyBindings implements PtyBindings {
  NativePtyBindings(ffi.DynamicLibrary library)
    : _ping = library.lookupFunction<_PingNative, _PingDart>('flutterm_ping'),
      _createSession = library
          .lookupFunction<_CreateSessionNative, _CreateSessionDart>(
            'flutterm_session_create',
          ),
      _closeSession = library
          .lookupFunction<_CloseSessionNative, _CloseSessionDart>(
            'flutterm_session_close',
          ),
      _resizeSession = library
          .lookupFunction<_ResizeSessionNative, _ResizeSessionDart>(
            'flutterm_session_resize',
          ),
      _writeSession = library
          .lookupFunction<_WriteSessionNative, _WriteSessionDart>(
            'flutterm_session_write',
          ),
      _scrollSession = library
          .lookupFunction<_ScrollSessionNative, _ScrollSessionDart>(
            'flutterm_session_scroll',
          ),
      _scrollToSession = library
          .lookupFunction<_ScrollToSessionNative, _ScrollToSessionDart>(
            'flutterm_session_scroll_to',
          ),
      _searchSession = library
          .lookupFunction<_SearchSessionNative, _SearchSessionDart>(
            'flutterm_session_search_json',
          ),
      _selectionTextSession = library
          .lookupFunction<
            _SelectionTextSessionNative,
            _SelectionTextSessionDart
          >('flutterm_session_selection_text'),
      _takeFrameDiffJson = library
          .lookupFunction<_StringReturningNative, _StringReturningDart>(
            'flutterm_session_take_frame_diff_json',
          ),
      _pollEventsJson = library
          .lookupFunction<_StringReturningNative, _StringReturningDart>(
            'flutterm_session_poll_events_json',
          ),
      _stringFree = library.lookupFunction<_FreeStringNative, _FreeStringDart>(
        'flutterm_string_free',
      );

  final _PingDart _ping;
  final _CreateSessionDart _createSession;
  final _CloseSessionDart _closeSession;
  final _ResizeSessionDart _resizeSession;
  final _WriteSessionDart _writeSession;
  final _ScrollSessionDart _scrollSession;
  final _ScrollToSessionDart _scrollToSession;
  final _SearchSessionDart _searchSession;
  final _SelectionTextSessionDart _selectionTextSession;
  final _StringReturningDart _takeFrameDiffJson;
  final _StringReturningDart _pollEventsJson;
  final _FreeStringDart _stringFree;

  factory NativePtyBindings.load() {
    return NativePtyBindings(ffi.DynamicLibrary.open(_resolveLibraryPath()));
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
    int pixelHeight,
  ) {
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
  String? sessionSearchJson(int sessionId, String query) {
    final queryPointer = query.toNativeUtf8();
    ffi.Pointer<Utf8> resultPointer = ffi.nullptr;
    try {
      resultPointer = _searchSession(sessionId, queryPointer);
      if (resultPointer == ffi.nullptr) {
        return null;
      }
      return resultPointer.toDartString();
    } finally {
      malloc.free(queryPointer);
      if (resultPointer != ffi.nullptr) {
        _stringFree(resultPointer);
      }
    }
  }

  @override
  String? sessionSelectionText(int sessionId, String requestJson) {
    final requestPointer = requestJson.toNativeUtf8();
    ffi.Pointer<Utf8> resultPointer = ffi.nullptr;
    try {
      resultPointer = _selectionTextSession(sessionId, requestPointer);
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
    final resultPointer = _takeFrameDiffJson(sessionId);
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
      final entries = jsonDecode(raw) as List<dynamic>;
      return entries
          .map(
            (entry) =>
                PtyEvent.fromJson((entry as Map).cast<String, Object?>()),
          )
          .toList();
    } finally {
      _stringFree(resultPointer);
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
  });
  void writeInput(String sessionId, List<int> bytes);
  void scrollViewport(String sessionId, int deltaLines);
  void scrollViewportTo(String sessionId, int offset);
  String? searchTextJson(String sessionId, String query);
  String? selectionText(String sessionId, String requestJson);
  String? takeFrameDiffJson(String sessionId);
  List<PtyEvent> pollEvents(String sessionId);
}

class NativePtyBackend implements PtySessionBackend {
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
    _bindings.sessionClose(int.parse(sessionId));
  }

  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
  }) {
    _bindings.sessionResize(
      int.parse(sessionId),
      cols,
      rows,
      pixelWidth,
      pixelHeight,
    );
  }

  @override
  void writeInput(String sessionId, List<int> bytes) {
    _bindings.sessionWrite(int.parse(sessionId), bytes);
  }

  @override
  void scrollViewport(String sessionId, int deltaLines) {
    _bindings.sessionScroll(int.parse(sessionId), deltaLines);
  }

  @override
  void scrollViewportTo(String sessionId, int offset) {
    _bindings.sessionScrollTo(int.parse(sessionId), offset);
  }

  @override
  String? searchTextJson(String sessionId, String query) {
    return _bindings.sessionSearchJson(int.parse(sessionId), query);
  }

  @override
  String? selectionText(String sessionId, String requestJson) {
    return _bindings.sessionSelectionText(int.parse(sessionId), requestJson);
  }

  @override
  String? takeFrameDiffJson(String sessionId) {
    return _bindings.sessionTakeFrameDiffJson(int.parse(sessionId));
  }

  @override
  List<PtyEvent> pollEvents(String sessionId) {
    return _bindings.sessionPollEvents(int.parse(sessionId));
  }
}

String _resolveLibraryPath() {
  final explicit = Platform.environment['FLUTTERM_CORE_LIB'];
  if (explicit != null && File(explicit).existsSync()) {
    return explicit;
  }

  final candidates = <String>[
    '${executableDirectory.path}/../Frameworks/libflutterm_core.dylib',
    '${executableDirectory.path}/../Resources/libflutterm_core.dylib',
    '../native/core/target/debug/libflutterm_core.dylib',
    '../../native/core/target/debug/libflutterm_core.dylib',
  ];

  for (final candidate in candidates) {
    final file = File(candidate);
    if (file.existsSync()) {
      return file.absolute.path;
    }
  }

  var directory = executableDirectory;
  for (var index = 0; index < 10; index += 1) {
    final candidate = File(
      '${directory.path}/../../../../../../../../native/core/target/debug/libflutterm_core.dylib',
    );
    if (candidate.existsSync()) {
      return candidate.absolute.path;
    }
    directory = directory.parent;
  }

  throw StateError(
    'Unable to locate libflutterm_core.dylib. Set FLUTTERM_CORE_LIB to an absolute path.',
  );
}

Directory get executableDirectory => File(Platform.resolvedExecutable).parent;
