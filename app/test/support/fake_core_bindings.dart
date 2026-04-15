import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:app/ffi/flutterm_core.dart';

class FakeCoreBindings implements CoreBindings {
  int _nextSessionId = 0;
  final Map<int, Map<String, Object?>> _frames = {};
  final Map<int, List<Map<String, Object?>>> _events = {};
  final List<Uint8List> writes = [];
  final List<List<int>> resizeCalls = [];
  bool pingCalled = false;

  @override
  int ping() {
    pingCalled = true;
    return 42;
  }

  @override
  int sessionCreate(ffi.Pointer<Utf8> profileJson) {
    final sessionId = ++_nextSessionId;
    _frames[sessionId] = {
      'rows': [
        {
          'index': 0,
          'text': 'flutterm ready',
          'style_runs': [
            {
              'start': 0,
              'end': 14,
              'foreground': '#f8fafc',
              'background': null,
              'bold': false,
              'italic': false,
              'underline': false,
              'inverse': false,
            },
          ],
        },
      ],
      'cursor': {'row': 0, 'col': 4, 'visible': true},
      'selection': null,
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': [
        {'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
    };
    _events[sessionId] = [
      {'kind': 'started', 'session_id': sessionId, 'payload': null},
    ];
    return sessionId;
  }

  @override
  int sessionClose(int sessionId) {
    _frames.remove(sessionId);
    _events.remove(sessionId);
    return 0;
  }

  @override
  ffi.Pointer<Utf8> sessionPollEventsJson(int sessionId) {
    final events = _events.putIfAbsent(sessionId, () => []);
    final raw = jsonEncode(events);
    events.clear();
    return raw.toNativeUtf8();
  }

  @override
  int sessionResize(
    int sessionId,
    int cols,
    int rows,
    int pixelWidth,
    int pixelHeight,
  ) {
    resizeCalls.add([sessionId, cols, rows, pixelWidth, pixelHeight]);
    final frame = _frames[sessionId];
    if (frame != null) {
      frame['viewport_cols'] = cols;
      frame['viewport_rows'] = rows;
    }
    return 0;
  }

  @override
  int sessionScroll(int sessionId, int deltaLines) => 0;

  @override
  ffi.Pointer<Utf8> sessionTakeFrameDiffJson(int sessionId) {
    final frame = _frames[sessionId];
    if (frame == null) {
      return ffi.nullptr;
    }
    return jsonEncode(frame).toNativeUtf8();
  }

  @override
  int sessionWrite(int sessionId, ffi.Pointer<ffi.Uint8> bytes, int length) {
    writes.add(Uint8List.fromList(bytes.asTypedList(length)));
    return 0;
  }

  @override
  void stringFree(ffi.Pointer<Utf8> value) {
    malloc.free(value);
  }
}
