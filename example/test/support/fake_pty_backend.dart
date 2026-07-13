import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:ianvs_pty/ianvs_pty.dart';

class FakePtyBackend
    implements
        PtySessionBackend,
        PtySessionJsonRequestBackend,
        PtySessionFileDownloadBackend {
  int _nextSessionId = 0;
  final Map<String, Map<String, Object?>> _frames =
      <String, Map<String, Object?>>{};
  final Map<String, List<Map<String, Object?>>> _queuedFrames =
      <String, List<Map<String, Object?>>>{};
  final Map<String, List<PtyEvent>> _events = <String, List<PtyEvent>>{};
  final Map<String, Map<String, List<Map<String, Object?>>>> _searchMatches =
      <String, Map<String, List<Map<String, Object?>>>>{};
  final Map<String, int> _frameDiffReads = <String, int>{};
  final List<Uint8List> writes = <Uint8List>[];
  final List<MapEntry<String, Uint8List>> writesBySession =
      <MapEntry<String, Uint8List>>[];
  final List<List<int>> resizeCalls = <List<int>>[];
  final List<List<int>> scrollCalls = <List<int>>[];
  final List<List<int>> scrollToCalls = <List<int>>[];
  final List<List<Object?>> searchCalls = <List<Object?>>[];
  final List<List<Object?>> selectionTextCalls = <List<Object?>>[];
  final List<Map<String, Object?>> jsonRequests = <Map<String, Object?>>[];
  final Set<String> failingOperations = <String>{};
  final Map<(String, int), Uint8List> fileDownloads =
      <(String, int), Uint8List>{};
  final List<(String, int)> takenFileDownloads = <(String, int)>[];
  final List<(String, int)> discardedFileDownloads = <(String, int)>[];
  Map<String, Object?>? lastCreatedSessionPayload;
  bool pingCalled = false;

  void setFrame(Object sessionId, Map<String, Object?> frame) {
    _frames[_sessionKey(sessionId)] = frame;
  }

  void clearFrame(Object sessionId) {
    _frames.remove(_sessionKey(sessionId));
  }

  void enqueueFrame(Object sessionId, Map<String, Object?> frame) {
    _queuedFrames
        .putIfAbsent(_sessionKey(sessionId), () => <Map<String, Object?>>[])
        .add(frame);
  }

  void setSearchMatches(
    Object sessionId,
    String query,
    List<Map<String, Object?>> matches, {
    String mode = 'smart_case_substring',
  }) {
    _searchMatches.putIfAbsent(
      _sessionKey(sessionId),
      () => <String, List<Map<String, Object?>>>{},
    )[_searchKey(query, mode)] = matches;
  }

  void enqueueEvent(Object sessionId, PtyEvent event) {
    _events.putIfAbsent(_sessionKey(sessionId), () => <PtyEvent>[]).add(event);
  }

  @override
  int ping() {
    pingCalled = true;
    return 42;
  }

  @override
  String createSession(String sessionConfigJson) {
    _throwIfFailing('createSession');
    lastCreatedSessionPayload =
        jsonDecode(sessionConfigJson) as Map<String, Object?>;
    final sessionId = (++_nextSessionId).toString();
    _frames[sessionId] = <String, Object?>{
      'rows': <Object?>[
        <String, Object?>{
          'index': 0,
          'text': 'ianvs terminal ready',
          'style_runs': <Object?>[
            <String, Object?>{
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
      'cursor': <String, Object?>{'row': 0, 'col': 4, 'visible': true},
      'selection': null,
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': <Object?>[
        <String, Object?>{'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'window_title': null,
      'window_icon_name': null,
    };
    _events[sessionId] = <PtyEvent>[
      PtyEvent(kind: 'started', sessionId: sessionId),
    ];
    return sessionId;
  }

  @override
  void closeSession(String sessionId) {
    _frames.remove(sessionId);
    _events.remove(sessionId);
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
    resizeCalls.add([
      _numericSessionId(sessionId),
      cols,
      rows,
      pixelWidth,
      pixelHeight,
    ]);
    final frame = _frames[sessionId];
    if (frame != null) {
      frame['viewport_cols'] = cols;
      frame['viewport_rows'] = rows;
    }
  }

  @override
  void scrollViewport(String sessionId, int deltaLines) {
    scrollCalls.add([_numericSessionId(sessionId), deltaLines]);
    final frame = _frames[sessionId];
    if (frame == null) {
      return;
    }
    final maxOffset = frame['scrollback_max_offset'] as int? ?? 0;
    final currentOffset = frame['scrollback_offset'] as int? ?? 0;
    frame['scrollback_offset'] = (currentOffset + deltaLines).clamp(
      0,
      maxOffset,
    );
  }

  @override
  void scrollViewportTo(String sessionId, int offset) {
    scrollToCalls.add([_numericSessionId(sessionId), offset]);
    final frame = _frames[sessionId];
    if (frame == null) {
      return;
    }
    final maxOffset = frame['scrollback_max_offset'] as int? ?? 0;
    frame['scrollback_offset'] = offset.clamp(0, maxOffset);
  }

  @override
  String? requestSessionJson(String sessionId, String requestJson) {
    final request = jsonDecode(requestJson) as Map<String, Object?>;
    jsonRequests.add(request);
    return switch (request['kind']) {
      'terminal.search_text' => _searchTextJson(
        sessionId,
        request['query'] as String? ?? '',
        request['mode'] as String? ?? 'smart_case_substring',
      ),
      'terminal.selection_text' => _selectionTextJson(sessionId, request),
      'terminal.dismiss_osc99_notification' => jsonEncode(<String, Object?>{
        'dismissed': true,
      }),
      _ => null,
    };
  }

  String _searchTextJson(String sessionId, String query, String mode) {
    searchCalls.add([_numericSessionId(sessionId), query, mode]);
    final errorText = _searchErrorText(query, mode);
    final configuredMatches = _searchMatches[sessionId];
    final matches = errorText == null
        ? (configuredMatches?[_searchKey(query, mode)] ??
              configuredMatches?[_searchKey(query, 'smart_case_substring')] ??
              const <Map<String, Object?>>[])
        : const <Map<String, Object?>>[];
    return jsonEncode(<String, Object?>{
      'matches': matches.map((match) {
        return <String, Object?>{
          ...match,
          'scrollback_offset': match['scrollback_offset'] ?? match['row'] ?? 0,
        };
      }).toList(),
      'error_text': errorText,
    });
  }

  String _searchKey(String query, String mode) => '$mode\u0000$query';

  String? _searchErrorText(String query, String mode) {
    if (!mode.endsWith('_regex') || query.isEmpty) {
      return null;
    }
    try {
      RegExp(query);
      return null;
    } on FormatException {
      return 'Invalid regular expression';
    }
  }

  String? _selectionTextJson(String sessionId, Map<String, Object?> request) {
    final selection = request['selection'];
    if (selection is! Map) {
      return null;
    }
    final nativeRequest = <String, Object?>{
      ...selection.cast<String, Object?>(),
      'block': request['block'] == true,
    };
    selectionTextCalls.add([_numericSessionId(sessionId), nativeRequest]);
    final frame = _frames[sessionId];
    if (frame == null) {
      return null;
    }
    return jsonEncode(<String, Object?>{
      'text': _selectionTextForFrame(
        TerminalFrameDiff.fromJson(frame),
        TerminalSelection.fromJson(nativeRequest),
        block: nativeRequest['block'] as bool? ?? false,
      ),
    });
  }

  @override
  String? takeFrameDiffJson(String sessionId) {
    final queuedFrames = _queuedFrames[sessionId];
    if (queuedFrames != null && queuedFrames.isNotEmpty) {
      _frameDiffReads.update(
        sessionId,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      return jsonEncode(queuedFrames.removeAt(0));
    }
    final frame = _frames[sessionId];
    if (frame == null) {
      return null;
    }
    _frameDiffReads.update(sessionId, (value) => value + 1, ifAbsent: () => 1);
    return jsonEncode(frame);
  }

  @override
  void writeInput(String sessionId, List<int> bytes) {
    _throwIfFailing('writeInput');
    final write = Uint8List.fromList(bytes);
    writes.add(write);
    writesBySession.add(MapEntry<String, Uint8List>(sessionId, write));
  }

  void _throwIfFailing(String operation) {
    if (failingOperations.contains(operation)) {
      throw StateError('$operation failed');
    }
  }

  @override
  List<PtyEvent> pollEvents(String sessionId) {
    final events = _events.putIfAbsent(sessionId, () => <PtyEvent>[]);
    final copy = List<PtyEvent>.from(events);
    events.clear();
    return copy;
  }

  @override
  Uint8List? takeFileDownload(
    String sessionId, {
    required int downloadId,
    required int expectedSize,
  }) {
    _throwIfFailing('takeFileDownload');
    takenFileDownloads.add((sessionId, downloadId));
    final bytes = fileDownloads.remove((sessionId, downloadId));
    if (bytes == null || bytes.length != expectedSize) {
      return null;
    }
    return Uint8List.fromList(bytes);
  }

  @override
  bool discardFileDownload(String sessionId, {required int downloadId}) {
    _throwIfFailing('discardFileDownload');
    discardedFileDownloads.add((sessionId, downloadId));
    return fileDownloads.remove((sessionId, downloadId)) != null;
  }

  int getFrameDiffReadCount(Object sessionId) {
    return _frameDiffReads[_sessionKey(sessionId)] ?? 0;
  }

  String _sessionKey(Object sessionId) => sessionId.toString();

  int _numericSessionId(Object sessionId) {
    return int.tryParse(_sessionKey(sessionId)) ?? 0;
  }
}

String _selectionTextForFrame(
  TerminalFrameDiff frame,
  TerminalSelection selection, {
  required bool block,
}) {
  if (frame.viewportRows <= 0) {
    return '';
  }
  final normalized = block
      ? TerminalSelection(
          startRow: math.min(selection.startRow, selection.endRow),
          startCol: math.min(selection.startCol, selection.endCol),
          endRow: math.max(selection.startRow, selection.endRow),
          endCol: math.max(selection.startCol, selection.endCol),
        )
      : selection.normalized();
  final frameStartRow = frame.viewportStartRow;
  final frameEndRow = frameStartRow + frame.viewportRows - 1;
  if (normalized.endRow < frameStartRow || normalized.startRow > frameEndRow) {
    return '';
  }
  final visibleSelection = TerminalSelection(
    startRow: math.max(0, normalized.startRow - frameStartRow),
    startCol: block || normalized.startRow >= frameStartRow
        ? normalized.startCol
        : 0,
    endRow: math.min(frame.viewportRows - 1, normalized.endRow - frameStartRow),
    endCol: block || normalized.endRow <= frameEndRow
        ? normalized.endCol
        : frame.viewportCols,
  );
  return block
      ? _blockSelectionText(frame, visibleSelection)
      : _linearSelectionText(frame, visibleSelection);
}

String _linearSelectionText(
  TerminalFrameDiff frame,
  TerminalSelection selection,
) {
  final lines = <String>[];
  for (var row = selection.startRow; row <= selection.endRow; row += 1) {
    final text = row >= 0 && row < frame.rows.length
        ? frame.rows[row].text
        : '';
    final start = row == selection.startRow
        ? selection.startCol.clamp(0, text.length)
        : 0;
    final end = row == selection.endRow
        ? selection.endCol.clamp(0, text.length)
        : text.length;
    lines.add(text.substring(start, math.max(start, end)));
  }
  return lines.join('\n');
}

String _blockSelectionText(
  TerminalFrameDiff frame,
  TerminalSelection selection,
) {
  final lines = <String>[];
  final startCol = math.min(selection.startCol, selection.endCol);
  final endCol = math.max(selection.startCol, selection.endCol);
  for (var row = selection.startRow; row <= selection.endRow; row += 1) {
    final text = row >= 0 && row < frame.rows.length
        ? frame.rows[row].text
        : '';
    if (startCol >= text.length) {
      lines.add('');
      continue;
    }
    final safeEnd = endCol.clamp(startCol, text.length);
    lines.add(text.substring(startCol, safeEnd));
  }
  return lines.join('\n');
}
