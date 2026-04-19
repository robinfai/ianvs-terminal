import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/terminal/selection_controller.dart';
import 'package:app/features/terminal/terminal_input_controller.dart';
import 'package:app/features/terminal/terminal_viewport.dart';
import 'package:app/ffi/flutterm_core.dart';

import 'support/fake_core_bindings.dart';

void main() {
  testWidgets(
    'terminal input uses keyboard paste shortcut to send clipboard text',
    (tester) async {
      final bindings = FakeCoreBindings();
      final coreClient = TerminalCoreClient(bindings);
      final viewportController = TerminalViewportController();
      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        coreClient: coreClient,
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
      final bindings = FakeCoreBindings();
      String copied = '';
      final coreClient = TerminalCoreClient(bindings);
      final viewportController = TerminalViewportController();
      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        coreClient: coreClient,
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
      final bindings = FakeCoreBindings();
      String copied = '';
      final coreClient = TerminalCoreClient(bindings);
      final viewportController = TerminalViewportController();
      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        coreClient: coreClient,
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
      final bindings = FakeCoreBindings();
      final coreClient = TerminalCoreClient(bindings);
      final viewportController = TerminalViewportController();
      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        coreClient: coreClient,
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
      final bindings = FakeCoreBindings();
      final coreClient = TerminalCoreClient(bindings);
      final viewportController = TerminalViewportController();
      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        coreClient: coreClient,
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
    final bindings = FakeCoreBindings();
    String copied = '';
    final coreClient = TerminalCoreClient(bindings);
    final viewportController = TerminalViewportController();
    final selectionController = SelectionController();
    final inputController = TerminalInputController(
      sessionId: '1',
      coreClient: coreClient,
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

  test('terminal input encodes direct Chinese key input as UTF-8', () {
    final bindings = FakeCoreBindings();
    final coreClient = TerminalCoreClient(bindings);
    final inputController = TerminalInputController(
      sessionId: '1',
      coreClient: coreClient,
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
}
