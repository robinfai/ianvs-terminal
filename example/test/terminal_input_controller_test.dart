import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/terminal/selection_controller.dart';
import 'package:app/features/terminal/terminal_input_controller.dart';
import 'package:app/features/terminal/terminal_viewport.dart';

import 'support/fake_pty_backend.dart';
import 'support/test_runtime.dart';

void main() {
  testWidgets(
    'terminal input uses keyboard paste shortcut to send clipboard text',
    (tester) async {
      final bindings = FakePtyBackend();
      final coreClient = testRuntime(bindings);
      final viewportController = TerminalViewportController();
      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: coreClient,
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => 'hello\nworld',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalViewport(
              controller: viewportController,
              selectionController: selectionController,
              inputController: inputController,
              onScrollLines: (_) {},
              onScrollToOffset: (_) {},
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();

      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV, platform: 'macos');
      await tester.pump();
      expect(bindings.writes, isNotEmpty);
      expect(bindings.writes.last, utf8.encode('hello\nworld'));

      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
      await tester.pump();
    },
  );

  testWidgets(
    'terminal input uses keyboard copy shortcut to copy selected text',
    (tester) async {
      final bindings = FakePtyBackend();
      String copied = '';
      final coreClient = testRuntime(bindings);
      final viewportController = TerminalViewportController();
      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: coreClient,
        readSelection: () => 'selection text',
        copySelection: (text) async {
          copied = text;
        },
        readClipboard: () async => 'ignored',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalViewport(
              controller: viewportController,
              selectionController: selectionController,
              inputController: inputController,
              onScrollLines: (_) {},
              onScrollToOffset: (_) {},
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();

      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC, platform: 'macos');
      await tester.pump();
      expect(copied, equals('selection text'));
      expect(bindings.writes, isEmpty);

      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
      await tester.pump();
    },
  );

  testWidgets(
    'terminal input sends ETX for Control+C instead of treating it as copy',
    (tester) async {
      final bindings = FakePtyBackend();
      String copied = '';
      final coreClient = testRuntime(bindings);
      final viewportController = TerminalViewportController();
      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: coreClient,
        readSelection: () => 'selected text',
        copySelection: (text) async {
          copied = text;
        },
        readClipboard: () async => 'ignored',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalViewport(
              controller: viewportController,
              selectionController: selectionController,
              inputController: inputController,
              onScrollLines: (_) {},
              onScrollToOffset: (_) {},
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();

      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.controlLeft,
        platform: 'macos',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC, platform: 'macos');
      await tester.pump();

      expect(bindings.writes, isNotEmpty);
      expect(bindings.writes.last, equals(const [0x03]));
      expect(copied, isEmpty);

      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.controlLeft,
        platform: 'macos',
      );
      await tester.pump();
    },
  );

  testWidgets(
    'terminal input keeps normal typing for key V without paste shortcut',
    (tester) async {
      final bindings = FakePtyBackend();
      final coreClient = testRuntime(bindings);
      final viewportController = TerminalViewportController();
      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: coreClient,
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => 'ignored',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalViewport(
              controller: viewportController,
              selectionController: selectionController,
              inputController: inputController,
              onScrollLines: (_) {},
              onScrollToOffset: (_) {},
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV, platform: 'macos');
      await tester.pump();
      expect(bindings.writes, isNotEmpty);
      expect(bindings.writes.last, utf8.encode('v'));
    },
  );

  testWidgets(
    'terminal input keyboard paste keeps Unicode text in UTF-8 encoding',
    (tester) async {
      final bindings = FakePtyBackend();
      final coreClient = testRuntime(bindings);
      final viewportController = TerminalViewportController();
      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: coreClient,
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '你好, 世界🌟',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalViewport(
              controller: viewportController,
              selectionController: selectionController,
              inputController: inputController,
              onScrollLines: (_) {},
              onScrollToOffset: (_) {},
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();

      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV, platform: 'macos');
      await tester.pump();

      expect(bindings.writes, isNotEmpty);
      expect(bindings.writes.last, utf8.encode('你好, 世界🌟'));

      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
      await tester.pump();
    },
  );

  testWidgets('terminal input keyboard copy preserves Unicode selected text', (
    tester,
  ) async {
    final bindings = FakePtyBackend();
    String copied = '';
    final coreClient = testRuntime(bindings);
    final viewportController = TerminalViewportController();
    final selectionController = SelectionController();
    final inputController = TerminalInputController(
      sessionId: '1',
      runtime: coreClient,
      readSelection: () => '复制内容🌟',
      copySelection: (text) async {
        copied = text;
      },
      readClipboard: () async => 'ignored',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalViewport(
            controller: viewportController,
            selectionController: selectionController,
            inputController: inputController,
            onScrollLines: (_) {},
            onScrollToOffset: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TerminalViewport));
    await tester.pump();

    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.metaLeft,
      platform: 'macos',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC, platform: 'macos');
    await tester.pump();

    expect(copied, equals('复制内容🌟'));
    expect(bindings.writes, isEmpty);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
    await tester.pump();
  });

  testWidgets(
    'terminal input ignores unhandled Meta app shortcuts without writing text',
    (tester) async {
      final bindings = FakePtyBackend();
      final coreClient = testRuntime(bindings);
      final viewportController = TerminalViewportController();
      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: coreClient,
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => 'ignored',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalViewport(
              controller: viewportController,
              selectionController: selectionController,
              inputController: inputController,
              onScrollLines: (_) {},
              onScrollToOffset: (_) {},
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();

      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
      for (final key in <LogicalKeyboardKey>[
        LogicalKeyboardKey.keyQ,
        LogicalKeyboardKey.keyW,
        LogicalKeyboardKey.comma,
      ]) {
        await tester.sendKeyDownEvent(key, platform: 'macos');
        await tester.sendKeyUpEvent(key, platform: 'macos');
      }
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
      await tester.pump();

      expect(bindings.writes, isEmpty);
    },
  );

  test('terminal input encodes direct Chinese key input as UTF-8', () {
    final bindings = FakePtyBackend();
    final coreClient = testRuntime(bindings);
    final inputController = TerminalInputController(
      sessionId: '1',
      runtime: coreClient,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );

    final result = inputController.handle(
      const KeyDownEvent(
        timeStamp: Duration.zero,
        physicalKey: PhysicalKeyboardKey.keyA,
        logicalKey: LogicalKeyboardKey.keyA,
        character: '你',
      ),
    );

    expect(result, KeyEventResult.handled);
    expect(bindings.writes.last, utf8.encode('你'));
  });

  test('terminal input switches arrow keys in application cursor mode', () {
    final bindings = FakePtyBackend();
    final coreClient = testRuntime(bindings);
    final inputController = TerminalInputController(
      sessionId: '1',
      runtime: coreClient,
      readFrame: () => const TerminalFrameDiff(
        rows: [],
        cursor: TerminalCursor(row: 0, col: 0, visible: true),
        viewportRows: 24,
        viewportCols: 80,
        dirtyRanges: [],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
        modes: TerminalFrameModes(applicationCursor: true),
      ),
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );

    final result = inputController.handle(
      const KeyDownEvent(
        timeStamp: Duration.zero,
        physicalKey: PhysicalKeyboardKey.arrowUp,
        logicalKey: LogicalKeyboardKey.arrowUp,
      ),
    );

    expect(result, KeyEventResult.handled);
    expect(bindings.writes.last, ascii.encode('\x1BOA'));
  });

  test(
    'terminal input switches keypad encoding in application keypad mode',
    () {
      final bindings = FakePtyBackend();
      final coreClient = testRuntime(bindings);
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: coreClient,
        readFrame: () => const TerminalFrameDiff(
          rows: [],
          cursor: TerminalCursor(row: 0, col: 0, visible: true),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: [],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
          modes: TerminalFrameModes(applicationKeypad: true),
        ),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      final result = inputController.handle(
        const KeyDownEvent(
          timeStamp: Duration.zero,
          physicalKey: PhysicalKeyboardKey.numpad1,
          logicalKey: LogicalKeyboardKey.numpad1,
        ),
      );

      expect(result, KeyEventResult.handled);
      expect(bindings.writes.last, ascii.encode('\x1BOq'));
    },
  );

  testWidgets('terminal input sends escape-prefixed bytes for Alt key chords', (
    tester,
  ) async {
    final bindings = FakePtyBackend();
    final coreClient = testRuntime(bindings);
    final viewportController = TerminalViewportController();
    final selectionController = SelectionController();
    final inputController = TerminalInputController(
      sessionId: '1',
      runtime: coreClient,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalViewport(
            controller: viewportController,
            selectionController: selectionController,
            inputController: inputController,
            onScrollLines: (_) {},
            onScrollToOffset: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TerminalViewport));
    await tester.pump();

    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.altLeft,
      platform: 'macos',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF, platform: 'macos');
    await tester.pump();

    expect(bindings.writes, isNotEmpty);
    expect(bindings.writes.last, ascii.encode('\x1Bf'));

    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF, platform: 'macos');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft, platform: 'macos');
  });

  testWidgets('terminal input sends modified arrow bytes for Shift+Arrow', (
    tester,
  ) async {
    final bindings = FakePtyBackend();
    final coreClient = testRuntime(bindings);
    final viewportController = TerminalViewportController();
    final selectionController = SelectionController();
    final inputController = TerminalInputController(
      sessionId: '1',
      runtime: coreClient,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalViewport(
            controller: viewportController,
            selectionController: selectionController,
            inputController: inputController,
            onScrollLines: (_) {},
            onScrollToOffset: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TerminalViewport));
    await tester.pump();

    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.shiftLeft,
      platform: 'macos',
    );
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.arrowUp,
      platform: 'macos',
    );
    await tester.pump();

    expect(bindings.writes, isNotEmpty);
    expect(bindings.writes.last, ascii.encode('\x1B[1;2A'));

    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp, platform: 'macos');
    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.shiftLeft,
      platform: 'macos',
    );
  });

  test(
    'xterm keyboard paste uses bracketed paste when the mode is enabled',
    () {
      final bytes = TerminalInputController.clipboardPasteBytesFor(
        emulation: TerminalEmulation.xterm256,
        modes: const TerminalFrameModes(bracketedPaste: true),
        text: 'hello\nworld',
      );

      expect(
        bytes,
        ascii.encode('\x1B[200~') +
            utf8.encode('hello\nworld') +
            ascii.encode('\x1B[201~'),
      );
    },
  );

  test(
    'vt220 keyboard paste stays unwrapped even when xterm paste mode is absent',
    () {
      final bytes = TerminalInputController.clipboardPasteBytesFor(
        emulation: TerminalEmulation.vt220,
        modes: const TerminalFrameModes(bracketedPaste: true),
        text: 'plain',
      );

      expect(bytes, utf8.encode('plain'));
    },
  );
}
