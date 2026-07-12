import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

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
        theme: TerminalColorPalette(
          special: TerminalSpecialColors(
            foreground: '#EEEEEE',
            background: '#101010',
            cursor: '#FFFFFF',
            selection: '#334455',
          ),
          normal: TerminalAnsiColors(red: '#AA2200', blue: '#2244AA'),
          bright: TerminalAnsiColors(red: '#FF3300', blue: '#5577FF'),
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
    expect(backend.resizeCalls.last, <Object?>['1', 100, 30, 900, 540, 9, 18]);

    final payload = backend.lastCreateSessionPayload!;
    expect(payload['terminal'], <String, Object?>{
      'emulation': 'xterm256',
      'scrollbackLines': 5000,
      'graphics': <String, Object?>{
        'enabled': true,
        'advertise': 'kitty',
        'maxImageBytes': defaultTerminalGraphicMaxImageBytes,
        'maxTotalBytes': defaultTerminalGraphicMaxTotalBytes,
      },
      'dragDropEnabled': false,
    });
    expect(payload['appearance'], <String, Object?>{
      'font': <String, Object?>{
        'family': 'JetBrains Mono',
        'fallback': terminalFontFamilyFallback,
        'size': 15.0,
        'lineHeight': 1.3,
      },
      'colors': <String, Object?>{
        'special': <String, Object?>{
          'foreground': '#EEEEEE',
          'background': '#101010',
          'cursor': '#FFFFFF',
          'selection': '#334455',
          'tab': null,
        },
        'normal': <String, Object?>{
          'black': '#14191E',
          'red': '#AA2200',
          'green': '#00815B',
          'yellow': '#CFA518',
          'blue': '#2244AA',
          'magenta': '#8818A3',
          'cyan': '#009399',
          'white': '#E5E5E5',
        },
        'bright': <String, Object?>{
          'black': '#687378',
          'red': '#FF3300',
          'green': '#00C984',
          'yellow': '#FFC531',
          'blue': '#5577FF',
          'magenta': '#C54FFF',
          'cyan': '#00CCCC',
          'white': '#FFFFFF',
        },
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

    backend.setFrame(
      sessionId,
      _singleRowSnapshot(
        'ready',
        windowTitle: 'demo title',
        scrollbackOffset: 2,
        scrollbackMaxOffset: 9,
      ),
    );
    terminal.write('');
    await tester.pump();

    expect(selectionChanges, 2);
    expect(terminal.hasSelection(), isFalse);

    terminal.resize(120, 40);
    await tester.pump();

    expect(resizes.map((event) => (event.cols, event.rows)).last, (120, 40));
    expect(backend.resizeCalls.last, <Object?>['1', 120, 40, 1080, 720, 9, 18]);

    terminal.refresh();
    await tester.pump();
    expect(backend.scrollToCalls.last, (sessionId, 2));

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

  testWidgets('terminal facade rejects zero resize dimensions', (tester) async {
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

    final resizeCallCount = backend.resizeCalls.length;
    expect(() => terminal.resize(0, 24), throwsRangeError);
    expect(() => terminal.resize(80, 0), throwsRangeError);
    expect(backend.resizeCalls, hasLength(resizeCallCount));
    expect(terminal.cols, 80);
    expect(terminal.rows, 24);
  });

  test('terminal options normalize resize dimensions', () {
    final oversized = TerminalOptions(
      cols: maxTerminalDimension + 1,
      rows: maxTerminalDimension + 2,
    );
    const invalid = TerminalOptions(cols: 0, rows: -1);

    expect(oversized.cols, maxTerminalDimension);
    expect(oversized.rows, maxTerminalDimension);
    expect(invalid.cols, defaultTerminalColumns);
    expect(invalid.rows, defaultTerminalRows);
  });

  test('terminal options default invalid font dimensions', () {
    const invalid = TerminalOptions(
      fontSize: double.nan,
      lineHeight: double.infinity,
    );
    const nonPositive = TerminalOptions(fontSize: 0, lineHeight: -1);
    const valid = TerminalOptions(fontSize: 15, lineHeight: 1.3);

    expect(invalid.fontSize, terminalFontSize);
    expect(invalid.lineHeight, terminalLineHeight);
    expect(nonPositive.fontSize, terminalFontSize);
    expect(nonPositive.lineHeight, terminalLineHeight);
    expect(valid.fontSize, 15);
    expect(valid.lineHeight, 1.3);
  });

  testWidgets('terminal facade keeps dimensions when backend rejects resize', (
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
    final backendErrors = <TerminalSessionBackendErrorEvent>[];
    final subscription = runtime.events.listen((event) {
      if (event is TerminalSessionBackendErrorEvent) {
        backendErrors.add(event);
      }
    });
    addTearDown(subscription.cancel);
    backend.resizeError = RangeError('native resize rejected');

    terminal.resize(120, 40);
    await tester.pump();

    expect(terminal.cols, 80);
    expect(terminal.rows, 24);
    expect(backendErrors, hasLength(1));
    expect(backendErrors.single.operation, 'resizeSession');
    expect(backendErrors.single.error, isA<RangeError>());
  });

  testWidgets('terminal facade paste ignores empty text', (tester) async {
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
    backend.writeCalls.clear();

    terminal.paste('');
    await tester.pump();

    expect(backend.writeCalls, isEmpty);
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

class _FakePtyBackend
    implements PtySessionBackend, PtySessionJsonRequestBackend {
  String? lastCreateSessionJson;
  final List<String> closeCalls = <String>[];
  final List<Uint8List> writeCalls = <Uint8List>[];
  final List<List<Object?>> resizeCalls = <List<Object?>>[];
  final List<(String, int)> scrollToCalls = <(String, int)>[];
  final Map<String, Map<String, Object?>> _frames =
      <String, Map<String, Object?>>{};
  final Map<String, List<PtyEvent>> _queuedEvents = <String, List<PtyEvent>>{};
  Object? resizeError;
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
    int cellWidth = 0,
    int cellHeight = 0,
  }) {
    final error = resizeError;
    if (error != null) {
      throw error;
    }
    resizeCalls.add(<Object?>[
      sessionId,
      cols,
      rows,
      pixelWidth,
      pixelHeight,
      cellWidth,
      cellHeight,
    ]);
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
  void scrollViewportTo(String sessionId, int offset) {
    scrollToCalls.add((sessionId, offset));
  }

  @override
  String? requestSessionJson(String sessionId, String requestJson) {
    final request = (jsonDecode(requestJson) as Map).cast<String, Object?>();
    return switch (request['kind']) {
      'terminal.search_text' => '[]',
      'terminal.selection_text' => jsonEncode(<String, Object?>{
        'text': 'selected',
      }),
      _ => null,
    };
  }

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
    'selection': ?selection?.toJson(),
    'window_title': ?windowTitle,
  };
}
