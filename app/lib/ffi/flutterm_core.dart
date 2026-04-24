import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/widgets.dart';

import '../features/profiles/profile_models.dart';
import '../features/terminal/terminal_painter_models.dart';

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
typedef _StringReturningNative = ffi.Pointer<Utf8> Function(ffi.Uint64);
typedef _StringReturningDart = ffi.Pointer<Utf8> Function(int);
typedef _FreeStringNative = ffi.Void Function(ffi.Pointer<Utf8>);
typedef _FreeStringDart = void Function(ffi.Pointer<Utf8>);

abstract class CoreBindings {
  int ping();
  int sessionCreate(ffi.Pointer<Utf8> profileJson);
  int sessionClose(int sessionId);
  int sessionResize(
    int sessionId,
    int cols,
    int rows,
    int pixelWidth,
    int pixelHeight,
  );
  int sessionWrite(int sessionId, ffi.Pointer<ffi.Uint8> bytes, int length);
  int sessionScroll(int sessionId, int deltaLines);
  int sessionScrollTo(int sessionId, int offset);
  ffi.Pointer<Utf8> sessionSearchJson(int sessionId, ffi.Pointer<Utf8> query);
  ffi.Pointer<Utf8> sessionTakeFrameDiffJson(int sessionId);
  ffi.Pointer<Utf8> sessionPollEventsJson(int sessionId);
  void stringFree(ffi.Pointer<Utf8> value);
}

class FluttermCoreBindings implements CoreBindings {
  FluttermCoreBindings(ffi.DynamicLibrary library)
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
  final _StringReturningDart _takeFrameDiffJson;
  final _StringReturningDart _pollEventsJson;
  final _FreeStringDart _stringFree;

  factory FluttermCoreBindings.load() {
    return FluttermCoreBindings(ffi.DynamicLibrary.open(_resolveLibraryPath()));
  }

  @override
  int ping() => _ping();

  @override
  int sessionCreate(ffi.Pointer<Utf8> profileJson) =>
      _createSession(profileJson);

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
  int sessionWrite(int sessionId, ffi.Pointer<ffi.Uint8> bytes, int length) {
    return _writeSession(sessionId, bytes, length);
  }

  @override
  int sessionScroll(int sessionId, int deltaLines) =>
      _scrollSession(sessionId, deltaLines);

  @override
  int sessionScrollTo(int sessionId, int offset) =>
      _scrollToSession(sessionId, offset);

  @override
  ffi.Pointer<Utf8> sessionSearchJson(int sessionId, ffi.Pointer<Utf8> query) =>
      _searchSession(sessionId, query);

  @override
  ffi.Pointer<Utf8> sessionTakeFrameDiffJson(int sessionId) =>
      _takeFrameDiffJson(sessionId);

  @override
  ffi.Pointer<Utf8> sessionPollEventsJson(int sessionId) =>
      _pollEventsJson(sessionId);

  @override
  void stringFree(ffi.Pointer<Utf8> value) => _stringFree(value);
}

class TerminalEvent {
  const TerminalEvent({
    required this.kind,
    required this.sessionId,
    this.payload,
  });

  final String kind;
  final String sessionId;
  final Map<String, Object?>? payload;

  factory TerminalEvent.fromJson(Map<String, Object?> json) {
    return TerminalEvent(
      kind: json['kind']! as String,
      sessionId: (json['session_id']! as num).toInt().toString(),
      payload: (json['payload'] as Map<String, Object?>?)
          ?.cast<String, Object?>(),
    );
  }
}

class TerminalCoreClient {
  TerminalCoreClient(this._bindings);

  final CoreBindings _bindings;

  factory TerminalCoreClient.load() =>
      TerminalCoreClient(FluttermCoreBindings.load());

  int ping() => _bindings.ping();

  String createSession(TerminalProfile profile) {
    final profileJson = jsonEncode(profile.toJson()).toNativeUtf8();
    try {
      final sessionId = _bindings.sessionCreate(profileJson);
      if (sessionId == 0) {
        throw StateError('Failed to create session');
      }
      return sessionId.toString();
    } finally {
      malloc.free(profileJson);
    }
  }

  void closeSession(String sessionId) {
    _bindings.sessionClose(int.parse(sessionId));
  }

  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required Size pixelSize,
    required double devicePixelRatio,
  }) {
    _bindings.sessionResize(
      int.parse(sessionId),
      cols,
      rows,
      (pixelSize.width * devicePixelRatio).round(),
      (pixelSize.height * devicePixelRatio).round(),
    );
  }

  void sendInput(String sessionId, Uint8List bytes) {
    final pointer = malloc<ffi.Uint8>(bytes.length);
    try {
      pointer.asTypedList(bytes.length).setAll(0, bytes);
      _bindings.sessionWrite(int.parse(sessionId), pointer, bytes.length);
    } finally {
      malloc.free(pointer);
    }
  }

  void scrollViewport(String sessionId, int deltaLines) {
    _bindings.sessionScroll(int.parse(sessionId), deltaLines);
  }

  void scrollViewportTo(String sessionId, int offset) {
    _bindings.sessionScrollTo(int.parse(sessionId), offset);
  }

  List<TerminalSearchMatch> searchText(String sessionId, String query) {
    if (query.isEmpty) {
      return const [];
    }
    final queryPointer = query.toNativeUtf8();
    final ffi.Pointer<Utf8> jsonPointer;
    try {
      jsonPointer = _bindings.sessionSearchJson(
        int.parse(sessionId),
        queryPointer,
      );
    } finally {
      malloc.free(queryPointer);
    }
    if (jsonPointer == ffi.nullptr) {
      return const [];
    }
    try {
      final raw = jsonPointer.toDartString();
      return (jsonDecode(raw) as List<dynamic>)
          .map(
            (entry) =>
                TerminalSearchMatch.fromJson(entry as Map<String, Object?>),
          )
          .toList();
    } finally {
      _bindings.stringFree(jsonPointer);
    }
  }

  TerminalFrameDiff? takeFrameDiff(String sessionId) {
    final jsonPointer = _bindings.sessionTakeFrameDiffJson(
      int.parse(sessionId),
    );
    if (jsonPointer == ffi.nullptr) {
      return null;
    }
    try {
      final raw = jsonPointer.toDartString();
      return TerminalFrameDiff.fromJson(
        jsonDecode(raw) as Map<String, Object?>,
      );
    } finally {
      _bindings.stringFree(jsonPointer);
    }
  }

  List<TerminalEvent> pollEvents(String sessionId) {
    final jsonPointer = _bindings.sessionPollEventsJson(int.parse(sessionId));
    if (jsonPointer == ffi.nullptr) {
      return const [];
    }
    try {
      final raw = jsonPointer.toDartString();
      final entries = jsonDecode(raw) as List<dynamic>;
      return entries
          .map((entry) => TerminalEvent.fromJson(entry as Map<String, Object?>))
          .toList();
    } finally {
      _bindings.stringFree(jsonPointer);
    }
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
