import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

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

  testWidgets('terminal input controller maps Control letters to C0 bytes', (
    tester,
  ) async {
    final previousOverride = debugDefaultTargetPlatformOverride;
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

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

      await tester.pumpWidget(
        _KeyHandlerHarness(onKeyEvent: controller.handle),
      );

      const cases = <(LogicalKeyboardKey, int)>[
        (LogicalKeyboardKey.keyA, 0x01),
        (LogicalKeyboardKey.keyB, 0x02),
        (LogicalKeyboardKey.keyC, 0x03),
        (LogicalKeyboardKey.keyD, 0x04),
        (LogicalKeyboardKey.keyE, 0x05),
        (LogicalKeyboardKey.keyF, 0x06),
        (LogicalKeyboardKey.keyG, 0x07),
        (LogicalKeyboardKey.keyH, 0x08),
        (LogicalKeyboardKey.keyI, 0x09),
        (LogicalKeyboardKey.keyJ, 0x0A),
        (LogicalKeyboardKey.keyK, 0x0B),
        (LogicalKeyboardKey.keyL, 0x0C),
        (LogicalKeyboardKey.keyM, 0x0D),
        (LogicalKeyboardKey.keyN, 0x0E),
        (LogicalKeyboardKey.keyO, 0x0F),
        (LogicalKeyboardKey.keyP, 0x10),
        (LogicalKeyboardKey.keyQ, 0x11),
        (LogicalKeyboardKey.keyR, 0x12),
        (LogicalKeyboardKey.keyS, 0x13),
        (LogicalKeyboardKey.keyT, 0x14),
        (LogicalKeyboardKey.keyU, 0x15),
        (LogicalKeyboardKey.keyV, 0x16),
        (LogicalKeyboardKey.keyW, 0x17),
        (LogicalKeyboardKey.keyX, 0x18),
        (LogicalKeyboardKey.keyY, 0x19),
        (LogicalKeyboardKey.keyZ, 0x1A),
      ];

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      for (final (key, expectedByte) in cases) {
        await tester.sendKeyDownEvent(key);
        await tester.pump();
        await tester.sendKeyUpEvent(key);
        await tester.pump();

        expect(backend.writeCalls.last.toList(), <int>[expectedByte]);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(backend.writeCalls, hasLength(cases.length));
    } finally {
      debugDefaultTargetPlatformOverride = previousOverride;
    }
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
