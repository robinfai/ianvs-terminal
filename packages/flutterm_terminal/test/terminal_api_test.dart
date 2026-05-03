import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterm_pty/flutterm_pty.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart';

void main() {
  testWidgets('terminal facade opens with xterm-style options and addons', (
    tester,
  ) async {
    final backend = _FakePtyBackend();
    final runtime = _runtimeFor(backend);
    addTearDown(runtime.dispose);
    final terminal = Terminal(
      runtime: runtime,
      sessionConfig: const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
      options: const TerminalOptions(
        cols: 100,
        rows: 30,
        scrollback: 5000,
        fontFamily: 'JetBrains Mono',
        fontSize: 15,
        lineHeight: 1.3,
        cursorBlink: false,
        cursorStyle: TerminalCursorStyle.bar,
        theme: TerminalTheme(
          foreground: '#eeeeee',
          background: '#101010',
          cursor: '#ffffff',
          selectionBackground: '#334455',
        ),
        copyOnSelect: true,
      ),
    );
    addTearDown(terminal.dispose);

    final lifecycle = <String>[];
    terminal.loadAddon(_RecordingAddon(lifecycle));
    terminal.open();

    expect(lifecycle, <String>['activate:false']);
    expect(terminal.sessionId, '1');
    expect(terminal.cols, 100);
    expect(terminal.rows, 30);
    expect(backend.resizeCalls.last, <Object?>['1', 100, 30, 900, 540]);

    final payload = backend.lastCreateSessionPayload!;
    expect(payload['terminal'], <String, Object?>{
      'emulation': 'xterm256',
      'scrollbackLines': 5000,
    });
    expect(payload['appearance'], <String, Object?>{
      'font': <String, Object?>{
        'family': 'JetBrains Mono',
        'fallback': terminalFontFamilyFallback,
        'size': 15.0,
        'lineHeight': 1.3,
      },
      'colors': <String, Object?>{
        'foreground': '#eeeeee',
        'background': '#101010',
        'cursor': '#ffffff',
        'selection': '#334455',
      },
      'cursor': <String, Object?>{'shape': 'beam', 'blink': false},
    });
    expect(payload['interaction'], <String, Object?>{
      'copyOnSelect': true,
      'optionDragMode': 'block_selection',
    });

    final dataEvents = <String>[];
    final inputEvents = <TerminalInputEvent>[];
    terminal.onData(dataEvents.add);
    terminal.onInput(inputEvents.add);
    terminal.write('ls');
    await tester.pump();

    expect(utf8.decode(backend.writeCalls.last), 'ls');
    expect(dataEvents, <String>['ls']);
    expect(inputEvents.single.bytes, Uint8List.fromList(utf8.encode('ls')));

    terminal.dispose();

    expect(backend.closeCalls, <String>['1']);
    expect(lifecycle, <String>['activate:false', 'dispose']);
  });

  testWidgets('terminal facade maps runtime frame, resize, and exit events', (
    tester,
  ) async {
    final backend = _FakePtyBackend();
    final runtime = _runtimeFor(backend);
    addTearDown(runtime.dispose);
    final terminal = Terminal(
      runtime: runtime,
      sessionConfig: const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    addTearDown(terminal.dispose);
    terminal.open();
    final sessionId = terminal.sessionId!;

    final renders = <TerminalRenderEvent>[];
    final resizes = <TerminalResizeEvent>[];
    final scrolls = <int>[];
    final titles = <String>[];
    var selectionChanges = 0;
    final exits = <TerminalExitEvent>[];
    terminal.onRender(renders.add);
    terminal.onResize(resizes.add);
    terminal.onScroll(scrolls.add);
    terminal.onTitleChange(titles.add);
    terminal.onSelectionChange(() {
      selectionChanges += 1;
    });
    terminal.onExit(exits.add);

    backend.setFrame(
      sessionId,
      _singleRowSnapshot(
        'ready',
        windowTitle: 'demo title',
        scrollbackOffset: 2,
        scrollbackMaxOffset: 9,
        selection: const TerminalSelection(
          startRow: 0,
          startCol: 0,
          endRow: 0,
          endCol: 5,
        ),
      ),
    );
    terminal.write('');
    await tester.pump();

    expect(renders.last, isA<TerminalRenderEvent>());
    expect(renders.last.start, 0);
    expect(renders.last.end, 0);
    expect(scrolls.last, 2);
    expect(titles.last, 'demo title');
    expect(selectionChanges, 1);
    expect(terminal.hasSelection(), isTrue);

    terminal.resize(120, 40);
    await tester.pump();

    expect(resizes.map((event) => (event.cols, event.rows)).last, (120, 40));
    expect(backend.resizeCalls.last, <Object?>['1', 120, 40, 1080, 720]);

    backend.enqueueEvent(
      sessionId,
      PtyEvent(
        kind: 'exit',
        sessionId: sessionId,
        payload: const <String, Object?>{'code': 12},
      ),
    );
    terminal.write('');
    await tester.pump();

    expect(exits.single.exitCode, 12);
    expect(terminal.isOpen, isFalse);
  });
}

TerminalRuntimeController _runtimeFor(_FakePtyBackend backend) {
  return TerminalRuntimeController(
    backend: backend,
    copyToClipboard: (_) async {},
    readClipboard: () async => '',
    enableSessionPolling: false,
  );
}

class _RecordingAddon implements TerminalAddon {
  _RecordingAddon(this.lifecycle);

  final List<String> lifecycle;

  @override
  void activate(Terminal terminal) {
    lifecycle.add('activate:${terminal.isOpen}');
  }

  @override
  void dispose() {
    lifecycle.add('dispose');
  }
}

class _FakePtyBackend implements PtySessionBackend {
  String? lastCreateSessionJson;
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

  void setFrame(String sessionId, Map<String, Object?> frame) {
    _frames[sessionId] = frame;
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
    _frames[sessionId] = _singleRowSnapshot('initial');
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
  String? selectionText(String sessionId, String requestJson) => 'selected';

  @override
  String? takeFrameDiffJson(String sessionId) {
    final frame = _frames[sessionId];
    return frame == null ? null : jsonEncode(frame);
  }

  @override
  List<PtyEvent> pollEvents(String sessionId) {
    return _queuedEvents.remove(sessionId) ?? const <PtyEvent>[];
  }
}

Map<String, Object?> _singleRowSnapshot(
  String text, {
  String? windowTitle,
  int scrollbackOffset = 0,
  int scrollbackMaxOffset = 0,
  TerminalSelection? selection,
}) {
  return <String, Object?>{
    'frame_kind': 'snapshot',
    'rows': <Object?>[
      <String, Object?>{'index': 0, 'text': text, 'style_runs': const []},
    ],
    'cursor': <String, Object?>{'row': 0, 'col': 0, 'visible': true},
    'viewport_rows': 24,
    'viewport_cols': 80,
    'dirty_ranges': <Object?>[
      <String, Object?>{'start': 0, 'end': 1},
    ],
    'scrollback_offset': scrollbackOffset,
    'scrollback_max_offset': scrollbackMaxOffset,
    if (selection != null) 'selection': selection.toJson(),
    if (windowTitle != null) 'window_title': windowTitle,
  };
}
