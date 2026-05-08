import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterm_pty/flutterm_pty.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart';

void main() {
  testWidgets('terminal input controller forwards repeated backspace events', (
    tester,
  ) async {
    final backend = _FakePtyBackend();
    final runtime = _runtimeFor(backend);
    addTearDown(runtime.dispose);
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    final controller = TerminalInputController(
      sessionId: sessionId,
      runtime: runtime,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );

    await tester.pumpWidget(_KeyHandlerHarness(onKeyEvent: controller.handle));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.backspace);

    expect(
      backend.writeCalls.map((bytes) => bytes.toList()).toList(growable: false),
      <List<int>>[
        <int>[0x7f],
        <int>[0x7f],
      ],
    );
  });

  testWidgets('terminal viewport forwards repeated backspace events', (
    tester,
  ) async {
    final backend = _FakePtyBackend();
    final runtime = _runtimeFor(backend);
    addTearDown(runtime.dispose);
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    final viewportController = TerminalViewportController()
      ..applySnapshot(TerminalFrameDiff.fromJson(_singleRowSnapshot()));
    final inputController = TerminalInputController(
      sessionId: sessionId,
      runtime: runtime,
      readFrame: () => viewportController.frame,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 240,
            child: TerminalViewport(
              controller: viewportController,
              selectionController: SelectionController(),
              inputController: inputController,
              onScrollLines: (_) {},
              onScrollToOffset: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.backspace);

    expect(
      backend.writeCalls.map((bytes) => bytes.toList()).toList(growable: false),
      <List<int>>[
        <int>[0x7f],
        <int>[0x7f],
      ],
    );
  });

  testWidgets(
    'terminal input controller does not repeat app-modifier paste shortcuts',
    (tester) async {
      final previousOverride = debugDefaultTargetPlatformOverride;
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;

        final backend = _FakePtyBackend();
        final runtime = _runtimeFor(backend);
        addTearDown(runtime.dispose);
        final sessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/sh'),
          ),
        );
        var clipboardReads = 0;
        final controller = TerminalInputController(
          sessionId: sessionId,
          runtime: runtime,
          readSelection: () => '',
          copySelection: (_) async {},
          readClipboard: () async {
            clipboardReads += 1;
            return 'clip';
          },
        );

        await tester.pumpWidget(
          _KeyHandlerHarness(onKeyEvent: controller.handle),
        );

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
        await tester.pump();
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyV);
        await tester.pump();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

        expect(clipboardReads, 1);
        expect(
          backend.writeCalls.map(utf8.decode).toList(growable: false),
          <String>['clip'],
        );
      } finally {
        debugDefaultTargetPlatformOverride = previousOverride;
      }
    },
  );
}

class _KeyHandlerHarness extends StatelessWidget {
  const _KeyHandlerHarness({required this.onKeyEvent});

  final KeyEventResult Function(KeyEvent event) onKeyEvent;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) => onKeyEvent(event),
        child: const SizedBox.expand(),
      ),
    );
  }
}

TerminalRuntimeController _runtimeFor(_FakePtyBackend backend) {
  return TerminalRuntimeController(
    backend: backend,
    copyToClipboard: (_) async {},
    readClipboard: () async => '',
    enableSessionPolling: false,
  );
}

class _FakePtyBackend implements PtySessionBackend {
  final List<Uint8List> writeCalls = <Uint8List>[];
  int _nextSessionId = 0;

  @override
  int ping() => 1;

  @override
  String createSession(String sessionConfigJson) {
    return (++_nextSessionId).toString();
  }

  @override
  void closeSession(String sessionId) {}

  @override
  void writeInput(String sessionId, List<int> bytes) {
    writeCalls.add(Uint8List.fromList(bytes));
  }

  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
  }) {}

  @override
  String? takeFrameDiffJson(String sessionId) {
    return jsonEncode(_singleRowSnapshot());
  }

  @override
  List<PtyEvent> pollEvents(String sessionId) => const <PtyEvent>[];

  @override
  void scrollViewport(String sessionId, int deltaLines) {}

  @override
  void scrollViewportTo(String sessionId, int offset) {}

  @override
  String? selectionText(String sessionId, String selectionJson) => null;

  @override
  String searchTextJson(String sessionId, String query) => '[]';
}

Map<String, Object?> _singleRowSnapshot() {
  return <String, Object?>{
    'rows': <Object?>[
      <String, Object?>{'index': 0, 'text': '', 'segments': const <Object?>[]},
    ],
    'cursor': <String, Object?>{'row': 0, 'col': 0, 'visible': true},
    'viewport_rows': 1,
    'viewport_cols': 80,
    'scrollback_offset': 0,
    'scrollback_max_offset': 0,
    'modes': const <String, Object?>{},
  };
}
