import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:app/ffi/flutterm_core.dart';

class FakeCoreBindings implements CoreBindings {
  int _nextSessionId = 0;
  final Map<int, Map<String, Object?>> _frames = {};
  final Map<int, List<Map<String, Object?>>> _events = {};
  final Map<int, Map<String, List<Map<String, Object?>>>> _searchMatches = {};
  final Map<int, int> _frameDiffReads = {};
  final List<Uint8List> writes = [];
  final List<List<int>> resizeCalls = [];
  final List<List<int>> scrollCalls = [];
  final List<List<int>> scrollToCalls = [];
  final List<List<Object?>> searchCalls = [];
  Map<String, Object?>? lastCreatedProfileJson;
  bool pingCalled = false;

  void setFrame(int sessionId, Map<String, Object?> frame) {
    _frames[sessionId] = frame;
  }

  void setSearchMatches(
    int sessionId,
    String query,
    List<Map<String, Object?>> matches,
  ) {
    _searchMatches.putIfAbsent(
      sessionId,
      () => <String, List<Map<String, Object?>>>{},
    )[query] = matches;
  }

  @override
  int ping() {
    pingCalled = true;
    return 42;
  }

  @override
  int sessionCreate(ffi.Pointer<Utf8> profileJson) {
    lastCreatedProfileJson =
        jsonDecode(profileJson.toDartString()) as Map<String, Object?>;
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
      'scrollback_max_offset': 0,
      'window_title': null,
      'window_icon_name': null,
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
  int sessionScroll(int sessionId, int deltaLines) {
    scrollCalls.add([sessionId, deltaLines]);
    final frame = _frames[sessionId];
    if (frame == null) {
      return 0;
    }
    final maxOffset = frame['scrollback_max_offset'] as int? ?? 0;
    final currentOffset = frame['scrollback_offset'] as int? ?? 0;
    frame['scrollback_offset'] = (currentOffset + deltaLines).clamp(
      0,
      maxOffset,
    );
    return 0;
  }

  @override
  int sessionScrollTo(int sessionId, int offset) {
    scrollToCalls.add([sessionId, offset]);
    final frame = _frames[sessionId];
    if (frame == null) {
      return 0;
    }
    final maxOffset = frame['scrollback_max_offset'] as int? ?? 0;
    frame['scrollback_offset'] = offset.clamp(0, maxOffset);
    return 0;
  }

  @override
  ffi.Pointer<Utf8> sessionSearchJson(int sessionId, ffi.Pointer<Utf8> query) {
    final queryText = query.toDartString();
    searchCalls.add([sessionId, queryText]);
    final matches =
        _searchMatches[sessionId]?[queryText] ?? const <Map<String, Object?>>[];
    return jsonEncode(
      matches.map((match) {
        return <String, Object?>{
          ...match,
          'scrollback_offset': match['scrollback_offset'] ?? match['row'] ?? 0,
        };
      }).toList(),
    ).toNativeUtf8();
  }

  @override
  ffi.Pointer<Utf8> sessionTakeFrameDiffJson(int sessionId) {
    final frame = _frames[sessionId];
    if (frame == null) {
      return ffi.nullptr;
    }
    _frameDiffReads.update(sessionId, (value) => value + 1, ifAbsent: () => 1);
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
