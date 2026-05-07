import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/terminal/selection_controller.dart';
import 'package:app/features/terminal/terminal_input_controller.dart';
import 'package:app/features/terminal/terminal_viewport.dart';
import 'package:app/features/terminal/terminal_viewport_colors.dart';

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
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'terminal input on macOS sends Control+V to the session instead of pasting clipboard text',
    (tester) async {
      final bindings = FakePtyBackend();
      var clipboardReads = 0;
      final coreClient = testRuntime(bindings);
      final viewportController = TerminalViewportController();
      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: coreClient,
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async {
          clipboardReads += 1;
          return 'ignored';
        },
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
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV, platform: 'macos');
      await tester.pump();

      expect(clipboardReads, 0);
      expect(bindings.writes, isNotEmpty);
      expect(bindings.writes.last, equals(const [0x16]));

      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.controlLeft,
        platform: 'macos',
      );
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'terminal input on macOS sends Control+T to the session',
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
        LogicalKeyboardKey.controlLeft,
        platform: 'macos',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT, platform: 'macos');
      await tester.pump();

      expect(bindings.writes, isNotEmpty);
      expect(bindings.writes.last, equals(const [0x14]));

      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.controlLeft,
        platform: 'macos',
      );
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
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
    'terminal input defers plain macOS text keys to system text input',
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

      expect(bindings.writes, isEmpty);

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'v',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      await tester.pump();

      expect(bindings.writes, hasLength(1));
      expect(bindings.writes.single, utf8.encode('v'));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
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
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'terminal input attaches system text input and commits IME-composed Chinese text',
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

      expect(tester.testTextInput.hasAnyClients, isTrue);

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'ni',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      await tester.pump();

      expect(bindings.writes, isEmpty);

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '你',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      await tester.pump();

      expect(bindings.writes, hasLength(1));
      expect(bindings.writes.single, utf8.encode('你'));
    },
  );

  testWidgets(
    'terminal viewport shows composing text during IME composition and hides it after commit',
    (tester) async {
      final bindings = FakePtyBackend();
      final coreClient = testRuntime(bindings);
      final viewportController = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: '')],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );
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
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: viewportController,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'ni',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      await tester.pump();

      expect(find.text('ni'), findsOneWidget);

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '你',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      await tester.pump();

      expect(find.text('ni'), findsNothing);
      expect(bindings.writes.single, utf8.encode('你'));
    },
  );

  testWidgets(
    'terminal viewport renders composing text in a muted color instead of the main foreground',
    (tester) async {
      final viewportController = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: '')],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: testRuntime(FakePtyBackend()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );
      const colors = TerminalViewportColors.dark;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: viewportController,
                selectionController: SelectionController(),
                inputController: inputController,
                colors: colors,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'ni',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      await tester.pump();

      final textWidget = tester.widget<Text>(find.text('ni'));
      expect(textWidget.style?.color, isNotNull);
      expect(textWidget.style!.color, isNot(colors.foreground));
      expect(textWidget.style!.decorationColor, isNot(colors.foreground));
    },
  );

  testWidgets(
    'terminal viewport keeps composing text visible across cursor blink frames',
    (tester) async {
      final viewportController = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: '')],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: testRuntime(FakePtyBackend()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
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
      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'ni',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      await tester.pump();

      expect(find.text('ni'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1400));

      expect(find.text('ni'), findsOneWidget);
    },
  );

  testWidgets(
    'terminal viewport anchors composing text to the cursor cell instead of the underline stroke',
    (tester) async {
      final viewportController = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: '')],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: testRuntime(FakePtyBackend()),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 200,
              child: TerminalViewport(
                controller: viewportController,
                selectionController: SelectionController(),
                inputController: inputController,
                cursor: const TerminalProfileCursor(
                  shape: TerminalCursorShape.underline,
                  blink: false,
                ),
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'ni',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      await tester.pump();

      final composingTop = tester.getTopLeft(find.text('ni')).dy;
      expect(composingTop, lessThan(terminalFallbackCellSize.height / 2));
    },
  );

  testWidgets(
    'terminal input leaves arrow keys with active IME composition to macOS text input',
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

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'ni',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      await tester.pump();

      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.arrowLeft,
        platform: 'macos',
      );
      await tester.pump();

      expect(bindings.writes, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'terminal input keeps backspace on terminal key path for macOS',
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
        LogicalKeyboardKey.backspace,
        platform: 'macos',
        character: '\b',
      );
      await tester.pump();

      expect(bindings.writes, hasLength(1));
      expect(bindings.writes.single, equals(const [0x7f]));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
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

  testWidgets('terminal input sends Home for Command+Left', (tester) async {
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
      LogicalKeyboardKey.metaLeft,
      platform: 'macos',
    );
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.arrowLeft,
      platform: 'macos',
    );
    await tester.pump();

    expect(bindings.writes, isNotEmpty);
    expect(bindings.writes.last, ascii.encode('\x1B[H'));

    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.arrowLeft,
      platform: 'macos',
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
  });

  testWidgets('terminal input sends End for Command+Right', (tester) async {
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
      LogicalKeyboardKey.metaLeft,
      platform: 'macos',
    );
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.arrowRight,
      platform: 'macos',
    );
    await tester.pump();

    expect(bindings.writes, isNotEmpty);
    expect(bindings.writes.last, ascii.encode('\x1B[F'));

    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.arrowRight,
      platform: 'macos',
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
  });

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

  testWidgets(
    'terminal input maps Option+Left and Option+Right to word moves',
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
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.arrowLeft,
        platform: 'macos',
      );
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.arrowLeft,
        platform: 'macos',
      );
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.arrowRight,
        platform: 'macos',
      );
      await tester.pump();

      expect(bindings.writes, hasLength(2));
      expect(bindings.writes[0], ascii.encode('\x1Bb'));
      expect(bindings.writes[1], ascii.encode('\x1Bf'));

      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.arrowRight,
        platform: 'macos',
      );
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.altLeft,
        platform: 'macos',
      );
    },
  );

  testWidgets(
    'terminal input keeps Option+Up and Option+Down as plain arrows',
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
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.arrowUp,
        platform: 'macos',
      );
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.arrowUp,
        platform: 'macos',
      );
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.arrowDown,
        platform: 'macos',
      );
      await tester.pump();

      expect(bindings.writes, hasLength(2));
      expect(bindings.writes[0], ascii.encode('\x1B[A'));
      expect(bindings.writes[1], ascii.encode('\x1B[B'));

      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.arrowDown,
        platform: 'macos',
      );
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.altLeft,
        platform: 'macos',
      );
    },
  );

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
