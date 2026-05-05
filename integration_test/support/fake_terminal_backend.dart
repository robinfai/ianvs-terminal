import 'dart:collection';
import 'dart:convert';

import 'package:flutterm_pty/flutterm_pty.dart';
import 'package:ianvs_terminal/src/clipboard_client.dart';
import 'package:ianvs_terminal/src/terminal_blocks.dart';

class FakeClipboardClient implements ClipboardClient {
  FakeClipboardClient(this.text);

  String text;
  final List<String> copied = <String>[];

  @override
  Future<String> readText() async => text;

  @override
  Future<void> writeText(String text) async {
    copied.add(text);
    this.text = text;
  }
}

class FakePtySessionBackend implements PtySessionBackend {
  FakePtySessionBackend({this.selectedText = ''});

  final String selectedText;
  int _createCount = 0;
  final List<String> writes = <String>[];
  final Map<String, List<String>> writesBySession = <String, List<String>>{};
  final Queue<Map<String, Object?>> _queuedFrames =
      Queue<Map<String, Object?>>();

  void enqueueFrame(Map<String, Object?> frame) {
    _queuedFrames.add(frame);
  }

  @override
  int ping() => 42;

  @override
  String createSession(String sessionConfigJson) {
    _createCount += 1;
    return 'session-$_createCount';
  }

  @override
  void closeSession(String sessionId) {}

  @override
  List<PtyEvent> pollEvents(String sessionId) => const <PtyEvent>[];

  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
  }) {}

  @override
  void scrollViewport(String sessionId, int deltaLines) {}

  @override
  void scrollViewportTo(String sessionId, int offset) {}

  @override
  String? searchTextJson(String sessionId, String query) {
    return jsonEncode(const <Map<String, Object?>>[]);
  }

  @override
  String? selectionText(String sessionId, String requestJson) => selectedText;

  @override
  String? takeFrameDiffJson(String sessionId) {
    if (_queuedFrames.isNotEmpty) {
      return jsonEncode(_queuedFrames.removeFirst());
    }
    return jsonEncode(frameJson());
  }

  @override
  void writeInput(String sessionId, List<int> bytes) {
    final text = String.fromCharCodes(bytes);
    writes.add(text);
    writesBySession.putIfAbsent(sessionId, () => <String>[]).add(text);
  }
}

List<TerminalBlock> terminalBlocksForSession(String sessionId) {
  return switch (sessionId) {
    'session-1' => const <TerminalBlock>[
      TerminalBlock(
        id: 'session-1-block-1',
        sessionId: 'session-1',
        commandText: 'pwd',
        outputText: '/tmp\n',
        status: TerminalBlockStatus.succeeded,
        scrollbackOffset: 2,
        recordedAt: '2026-05-04T09:00:00Z',
      ),
      TerminalBlock(
        id: 'session-1-block-2',
        sessionId: 'session-1',
        commandText: 'sleep 1',
        outputText: '',
        status: TerminalBlockStatus.running,
        scrollbackOffset: 9,
        recordedAt: '2026-05-04T09:01:00Z',
      ),
    ],
    _ => const <TerminalBlock>[],
  };
}

Map<String, Object?> frameJson({
  String kind = 'snapshot',
  String text = 'ready',
  int cursorCol = 0,
  int cursorRow = 0,
  int viewportRows = 1,
  String? windowTitle,
  Map<String, Object?> modes = const <String, Object?>{},
  List<Map<String, Object?>> dirtyRanges = const <Map<String, Object?>>[
    <String, Object?>{'start': 0, 'end': 1},
  ],
}) {
  final frame = <String, Object?>{
    'frame_kind': kind,
    'rows': <Object?>[
      <String, Object?>{
        'index': 0,
        'text': text,
        'style_runs': const <Object?>[],
      },
    ],
    'cursor': <String, Object?>{
      'row': cursorRow,
      'col': cursorCol,
      'visible': true,
    },
    'viewport_rows': viewportRows,
    'viewport_cols': 80,
    'dirty_ranges': dirtyRanges,
    'scrollback_offset': 0,
    'scrollback_max_offset': 0,
    'modes': modes,
  };
  if (windowTitle != null) {
    frame['window_title'] = windowTitle;
  }
  return frame;
}
