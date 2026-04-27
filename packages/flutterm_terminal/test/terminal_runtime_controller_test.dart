import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart';
import 'package:flutterm_pty/flutterm_pty.dart';

void main() {
  testWidgets(
    'terminal runtime controller owns sessions and viewport state without demo imports',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );

      expect(sessionId, '1');
      expect(runtime.viewportFor(sessionId).frame.rows.single.text, 'demo');
      expect(runtimeBackend.lastCreateSessionJson, isNotNull);
      expect(runtimeBackend.lastCreateSessionPayload!['id'], 'runtime-1');
      expect(runtimeBackend.lastCreateSessionPayload!['name'], 'sh');
      expect(
        runtimeBackend.lastCreateSessionPayload!['launch'],
        <String, Object?>{
          'program': '/bin/sh',
          'args': const <String>[],
          'env': const <String, String>{},
          'cwd': null,
        },
      );
    },
  );

  testWidgets(
    'terminal runtime controller refreshes after input and scrolling when polling is disabled',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );

      expect(runtimeBackend.takeFrameDiffCalls, 1);
      expect(runtimeBackend.pollEventsCalls, 1);

      runtime.sendInput(sessionId, Uint8List.fromList(const [0x41]));
      runtime.scrollViewport(sessionId, 1);
      runtime.scrollViewportTo(sessionId, 2);
      await tester.pump();

      expect(runtimeBackend.takeFrameDiffCalls, 4);
      expect(runtimeBackend.pollEventsCalls, 4);
    },
  );

  testWidgets(
    'terminal runtime controller dispose closes active sessions',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );

      runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/zsh'),
        ),
      );

      runtime.dispose();

      expect(runtimeBackend.closeCalls, <String>['1', '2']);
    },
  );

  testWidgets(
    'terminal runtime controller continues to handle exit events',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final seenEvents = <TerminalSessionEvent>[];
      final subscription = runtime.events.listen(seenEvents.add);
      addTearDown(subscription.cancel);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        const PtyEvent(
          kind: 'exit',
          sessionId: '1',
          payload: <String, Object?>{'code': 7},
        ),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      expect(runtime.hasSession(sessionId), isFalse);
      expect(
        seenEvents.whereType<TerminalSessionExitEvent>().single.exitCode,
        7,
      );
    },
  );

  testWidgets(
    'terminal runtime controller continues to handle clipboard and resize events',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      String copiedText = '';
      String? pasteWrite;
      double? resizeWidthDelta;
      double? resizeHeightDelta;
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (text) async {
          copiedText = text;
        },
        readClipboard: () async => 'paste me',
        resizeWindowBy: ({
          required double widthDelta,
          required double heightDelta,
        }) async {
          resizeWidthDelta = widthDelta;
          resizeHeightDelta = heightDelta;
        },
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      runtime.resizeSession(sessionId, const Size(180, 144), 1);

      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_copy',
          sessionId: sessionId,
          payload: <String, Object?>{
            'data': base64.encode(utf8.encode('copied text')),
          },
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_paste_request',
          sessionId: sessionId,
          payload: const <String, Object?>{'selection': 'c'},
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'resize',
          sessionId: sessionId,
          payload: const <String, Object?>{'cols': 21, 'rows': 9},
        ),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      pasteWrite = utf8.decode(runtimeBackend.writeCalls.last);

      expect(copiedText, 'copied text');
      expect(pasteWrite, '\x1B]52;c;cGFzdGUgbWU=\x07');
      expect(resizeWidthDelta, 9);
      expect(resizeHeightDelta, 18);
      expect(
        runtimeBackend.resizeCalls.last,
        <Object?>['1', 21, 9, 189, 162],
      );
    },
  );
}

class _FakePtyBackend implements PtySessionBackend {
  String? lastCreateSessionJson;
  int takeFrameDiffCalls = 0;
  int pollEventsCalls = 0;
  final List<String> closeCalls = <String>[];
  final List<Uint8List> writeCalls = <Uint8List>[];
  final List<List<Object?>> resizeCalls = <List<Object?>>[];

  final Map<String, Map<String, Object?>> _frames =
      <String, Map<String, Object?>>{};
  final Map<String, List<PtyEvent>> _queuedEvents = <String, List<PtyEvent>>{};
  int _nextSessionId = 0;

  Map<String, Object?>? get lastCreateSessionPayload {
    final raw = lastCreateSessionJson;
    if (raw == null) {
      return null;
    }
    return (jsonDecode(raw) as Map).cast<String, Object?>();
  }

  void enqueueEvent(String sessionId, PtyEvent event) {
    _queuedEvents.putIfAbsent(sessionId, () => <PtyEvent>[]).add(event);
  }

  @override
  int ping() => 1;

  @override
  String createSession(String sessionConfigJson) {
    lastCreateSessionJson = sessionConfigJson;
    final sessionId = (++_nextSessionId).toString();
    _frames[sessionId] = <String, Object?>{
      'rows': <Object?>[
        <String, Object?>{'index': 0, 'text': 'demo', 'style_runs': <Object?>[]},
      ],
      'cursor': <String, Object?>{'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': <Object?>[],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
    };
    return sessionId;
  }

  @override
  void closeSession(String sessionId) {
    closeCalls.add(sessionId);
    _frames.remove(sessionId);
    _queuedEvents.remove(sessionId);
  }

  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
  }) {
    resizeCalls.add(<Object?>[sessionId, cols, rows, pixelWidth, pixelHeight]);
    final frame = _frames[sessionId];
    if (frame != null) {
      frame['viewport_cols'] = cols;
      frame['viewport_rows'] = rows;
    }
  }

  @override
  void writeInput(String sessionId, List<int> bytes) {
    writeCalls.add(Uint8List.fromList(bytes));
  }

  @override
  void scrollViewport(String sessionId, int deltaLines) {}

  @override
  void scrollViewportTo(String sessionId, int offset) {}

  @override
  String? searchTextJson(String sessionId, String query) => '[]';

  @override
  String? selectionText(String sessionId, String requestJson) => '';

  @override
  String? takeFrameDiffJson(String sessionId) {
    takeFrameDiffCalls += 1;
    final frame = _frames[sessionId];
    return frame == null ? null : jsonEncode(frame);
  }

  @override
  List<PtyEvent> pollEvents(String sessionId) {
    pollEventsCalls += 1;
    return _queuedEvents.remove(sessionId) ?? const <PtyEvent>[];
  }
}
