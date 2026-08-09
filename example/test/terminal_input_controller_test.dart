import 'dart:convert';
import 'dart:ui' as ui;

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/terminal/selection_controller.dart';
import 'package:app/features/terminal/terminal_input_controller.dart';
import 'package:app/features/terminal/terminal_viewport.dart';
import 'package:app/features/terminal/terminal_viewport_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
    'terminal input read-only mode blocks keyboard paste without reading clipboard',
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
          return 'blocked';
        },
        readOnly: () => true,
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
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV, platform: 'macos');
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
      await tester.pump();

      expect(clipboardReads, 0);
      expect(bindings.writes, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  test('terminal input read-only mode blocks focus tracking reports', () {
    final bindings = FakePtyBackend();
    final coreClient = testRuntime(bindings);
    final inputController = TerminalInputController(
      sessionId: '1',
      runtime: coreClient,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
      readOnly: () => true,
    );

    inputController.sendFocusReport(
      focused: true,
      modes: const TerminalFrameModes(focusTracking: true),
    );
    inputController.sendFocusReport(
      focused: false,
      modes: const TerminalFrameModes(focusTracking: true),
    );

    expect(bindings.writes, isEmpty);
  });

  testWidgets('terminal viewport read-only mode blocks mouse reports', (
    tester,
  ) async {
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
          modes: TerminalFrameModes(mouseMode: 'normal', mouseEncoding: 'sgr'),
        ),
      );
    final selectionController = SelectionController();
    final inputController = TerminalInputController(
      sessionId: '1',
      runtime: coreClient,
      readFrame: () => viewportController.frame,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
      readOnly: () => true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            height: 80,
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
    await tester.pump();

    final renderObject = tester.renderObject<RenderTerminalViewport>(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_TerminalViewportSurface',
      ),
    );
    final pointerPosition = renderObject.localToGlobal(
      Offset(
        renderObject.debugCellSize.width * 1.5,
        renderObject.debugCellSize.height * 0.5,
      ),
    );
    final pointer = TestPointer(19, ui.PointerDeviceKind.mouse);

    await tester.sendEventToBinding(pointer.down(pointerPosition));
    await tester.pump();
    await tester.sendEventToBinding(pointer.up());
    await tester.pump();

    expect(bindings.writes, isEmpty);
  });

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
    'terminal input sends Kitty CSI-u for Control+C when keyboard mode is enabled',
    (tester) async {
      final bindings = FakePtyBackend();
      String copied = '';
      final coreClient = testRuntime(bindings);
      final viewportController = TerminalViewportController();
      final selectionController = SelectionController();
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
          modes: TerminalFrameModes(kittyKeyboardFlags: 1),
        ),
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
      expect(utf8.decode(bindings.writes.last), equals('\x1B[99;5u'));
      expect(copied, isEmpty);

      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.controlLeft,
        platform: 'macos',
      );
      await tester.pump();
    },
  );

  testWidgets(
    'terminal input preserves Control+Space scope across legacy and Kitty modes',
    (tester) async {
      final bindings = FakePtyBackend();
      var kittyMode = false;
      final coreClient = testRuntime(bindings);
      final viewportController = TerminalViewportController();
      final selectionController = SelectionController();
      final inputController = TerminalInputController(
        sessionId: '1',
        runtime: coreClient,
        readFrame: () => TerminalFrameDiff(
          rows: const [],
          cursor: const TerminalCursor(row: 0, col: 0, visible: true),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: const [],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
          modes: TerminalFrameModes(kittyKeyboardFlags: kittyMode ? 1 : 0),
        ),
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
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.space,
        platform: 'macos',
      );
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space, platform: 'macos');

      kittyMode = true;
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.space,
        platform: 'macos',
      );
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space, platform: 'macos');
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.controlLeft,
        platform: 'macos',
      );
      await tester.pump();

      expect(bindings.writes, hasLength(2));
      expect(bindings.writes.first, equals(const [0x00]));
      expect(utf8.decode(bindings.writes.last), equals('\x1B[32;5u'));
    },
  );

  testWidgets(
    'terminal input sends Kitty associated text when report-all text mode is enabled',
    (tester) async {
      final bindings = FakePtyBackend();
      final coreClient = testRuntime(bindings);
      final viewportController = TerminalViewportController();
      final selectionController = SelectionController();
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
          modes: TerminalFrameModes(kittyKeyboardFlags: 24),
        ),
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
        LogicalKeyboardKey.keyE,
        character: 'é',
        platform: 'macos',
      );
      await tester.pump();

      expect(bindings.writes, isNotEmpty);
      expect(utf8.decode(bindings.writes.last), equals('\x1B[101;;233u'));

      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE, platform: 'macos');
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
                cursor: const TerminalCursorConfig(
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
    'terminal viewport clips long composing text to the terminal bounds',
    (tester) async {
      final viewportController = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: '')],
            cursor: TerminalCursor(row: 0, col: 26, visible: true),
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

      const composingText = 'composition-near-right-edge-overflow-probe';
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: composingText,
          selection: TextSelection.collapsed(offset: composingText.length),
          composing: TextRange(start: 0, end: composingText.length),
        ),
      );
      await tester.pump();

      final terminalRect = tester.getRect(find.byType(TerminalViewport));
      final overlayRect = tester.getRect(
        find.byKey(const Key('terminal-composing-overlay')),
      );
      expect(overlayRect.left, greaterThanOrEqualTo(terminalRect.left));
      expect(overlayRect.right, lessThanOrEqualTo(terminalRect.right));
      expect(find.text(composingText), findsOneWidget);
    },
  );

  testWidgets(
    'terminal input commits only the replaced IME segment from middle composition',
    (tester) async {
      final bindings = FakePtyBackend();
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
        runtime: testRuntime(bindings),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalViewport(
              controller: viewportController,
              selectionController: SelectionController(),
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
          text: 'leftni-right',
          selection: TextSelection.collapsed(offset: 6),
          composing: TextRange(start: 4, end: 6),
        ),
      );
      await tester.pump();

      expect(find.text('ni'), findsOneWidget);
      expect(bindings.writes, isEmpty);

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'left你-right',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      await tester.pump();

      expect(bindings.writes, hasLength(1));
      expect(bindings.writes.single, utf8.encode('你'));
    },
  );

  testWidgets('terminal input renders and commits RTL IME composition text', (
    tester,
  ) async {
    final bindings = FakePtyBackend();
    final viewportController = TerminalViewportController()
      ..updateFrame(
        const TerminalFrameDiff(
          rows: [TerminalRow(index: 0, text: '')],
          cursor: TerminalCursor(row: 0, col: 20, visible: true),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );
    final inputController = TerminalInputController(
      sessionId: '1',
      runtime: testRuntime(bindings),
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

    const composingText = 'שלום';
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: composingText,
        selection: TextSelection.collapsed(offset: composingText.length),
        composing: TextRange(start: 0, end: composingText.length),
      ),
    );
    await tester.pump();

    final terminalRect = tester.getRect(find.byType(TerminalViewport));
    final overlayRect = tester.getRect(
      find.byKey(const Key('terminal-composing-overlay')),
    );
    expect(find.text(composingText), findsOneWidget);
    expect(overlayRect.left, greaterThanOrEqualTo(terminalRect.left));
    expect(overlayRect.right, lessThanOrEqualTo(terminalRect.right));
    expect(bindings.writes, isEmpty);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: composingText,
        selection: TextSelection.collapsed(offset: composingText.length),
      ),
    );
    await tester.pump();

    expect(bindings.writes, hasLength(1));
    expect(bindings.writes.single, utf8.encode(composingText));
  });

  testWidgets(
    'terminal viewport keeps composing overlay anchored after resize',
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

      Future<void> pumpTerminal(Size size) {
        return tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: size.width,
                height: size.height,
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
      }

      await pumpTerminal(const Size(400, 200));
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

      final initialOverlayRect = tester.getRect(
        find.byKey(const Key('terminal-composing-overlay')),
      );

      viewportController.updateFrame(
        const TerminalFrameDiff(
          rows: [TerminalRow(index: 0, text: '')],
          cursor: TerminalCursor(row: 2, col: 12, visible: true),
          viewportRows: 12,
          viewportCols: 48,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );
      await pumpTerminal(const Size(320, 160));
      await tester.pump();

      final resizedOverlayRect = tester.getRect(
        find.byKey(const Key('terminal-composing-overlay')),
      );
      final terminalRect = tester.getRect(find.byType(TerminalViewport));

      expect(resizedOverlayRect.left, greaterThan(initialOverlayRect.left));
      expect(resizedOverlayRect.top, greaterThan(initialOverlayRect.top));
      expect(resizedOverlayRect.right, lessThanOrEqualTo(terminalRect.right));
      expect(find.text('ni'), findsOneWidget);
    },
  );

  testWidgets(
    'terminal viewport reports IME geometry at non-zero DPR after resize',
    (tester) async {
      tester.view.devicePixelRatio = 2.5;
      tester.view.physicalSize = const Size(1000, 500);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final textInputControl = _RecordingTextInputControl();
      TextInput.setInputControl(textInputControl);
      addTearDown(TextInput.restorePlatformInputControl);

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

      Future<void> pumpTerminal(Size size) {
        return tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: size.width,
                height: size.height,
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
      }

      await pumpTerminal(const Size(400, 200));
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

      expect(textInputControl.editableSizes, isNotEmpty);
      expect(textInputControl.editableTransforms, isNotEmpty);
      expect(textInputControl.composingRects, isNotEmpty);
      expect(textInputControl.caretRects, isNotEmpty);

      final initialEditableSize = textInputControl.editableSizes.last;
      final initialComposingRect = textInputControl.composingRects.last;
      expect(initialEditableSize.width, moreOrLessEquals(400));
      expect(initialEditableSize.height, moreOrLessEquals(200));
      expect(initialComposingRect.left, moreOrLessEquals(0));
      expect(initialComposingRect.top, moreOrLessEquals(0));

      viewportController.updateFrame(
        const TerminalFrameDiff(
          rows: [TerminalRow(index: 0, text: '')],
          cursor: TerminalCursor(row: 2, col: 12, visible: true),
          viewportRows: 12,
          viewportCols: 48,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 1)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );
      await pumpTerminal(const Size(320, 160));
      await tester.pump();

      final resizedEditableSize = textInputControl.editableSizes.last;
      final resizedEditableTransform = textInputControl.editableTransforms.last;
      final resizedComposingRect = textInputControl.composingRects.last;
      final resizedCaretRect = textInputControl.caretRects.last;

      expect(resizedEditableSize.width, moreOrLessEquals(320));
      expect(resizedEditableSize.height, moreOrLessEquals(160));
      expect(
        resizedEditableTransform.storage.every((value) => value.isFinite),
        isTrue,
      );
      expect(resizedComposingRect.left, greaterThan(initialComposingRect.left));
      expect(resizedComposingRect.top, greaterThan(initialComposingRect.top));
      expect(resizedComposingRect, resizedCaretRect);
      expect(find.text('ni'), findsOneWidget);
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

  testWidgets('terminal input preserves Shift for Alt letter chords', (
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
      LogicalKeyboardKey.altLeft,
      platform: 'macos',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF, platform: 'macos');
    await tester.pump();

    expect(bindings.writes, isNotEmpty);
    expect(bindings.writes.last, ascii.encode('\x1BF'));

    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF, platform: 'macos');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft, platform: 'macos');
    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.shiftLeft,
      platform: 'macos',
    );
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

  test('xterm keyboard paste removes embedded bracketed paste markers', () {
    final bytes = TerminalInputController.clipboardPasteBytesFor(
      emulation: TerminalEmulation.xterm256,
      modes: const TerminalFrameModes(bracketedPaste: true),
      text: 'safe\x1B[201~echo unsafe\x1B[200~tail\u{009B}200~end\u{009B}201~',
    );

    expect(utf8.decode(bytes), '\x1B[200~safeecho unsafetailend\x1B[201~');
  });

  test('xterm keyboard paste removes zero-padded C1 paste markers', () {
    final bytes = TerminalInputController.clipboardPasteBytesFor(
      emulation: TerminalEmulation.xterm256,
      modes: const TerminalFrameModes(bracketedPaste: true),
      text: 'safe\x1B[0201~echo unsafe\u{009B}0200~tail',
    );

    expect(utf8.decode(bytes), '\x1B[200~safeecho unsafetail\x1B[201~');
  });

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

class _RecordingTextInputControl with TextInputControl {
  final editableSizes = <Size>[];
  final editableTransforms = <Matrix4>[];
  final composingRects = <Rect>[];
  final caretRects = <Rect>[];

  @override
  void setEditableSizeAndTransform(Size editableBoxSize, Matrix4 transform) {
    editableSizes.add(editableBoxSize);
    editableTransforms.add(transform.clone());
  }

  @override
  void setComposingRect(Rect rect) {
    composingRects.add(rect);
  }

  @override
  void setCaretRect(Rect rect) {
    caretRects.add(rect);
  }
}
