import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';
import 'package:ianvs_terminal_core/src/terminal/render_terminal_viewport.dart';

void main() {
  testWidgets(
    'iPhone one-finger drag scrolls the viewport instead of terminal modes',
    (tester) async {
      final harness = _MobileViewportHarness(
        modes: const TerminalFrameModes(
          alternateScreen: true,
          alternateScroll: true,
          mouseMode: 'any_event',
          mouseEncoding: 'sgr',
        ),
        initialScrollbackOffset: 50,
        applyScrolls: true,
      );
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.widget());
      await tester.pump();

      final surface = _terminalSurface();
      final rect = tester.getRect(surface);
      final gesture = await tester.startGesture(
        Offset(rect.center.dx, rect.bottom - 24),
        kind: PointerDeviceKind.touch,
      );
      await gesture.moveBy(const Offset(0, -96));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16));

      expect(harness.scrollDeltas, isNotEmpty);
      expect(harness.scrollDeltas.reduce((a, b) => a + b), greaterThan(0));
      expect(harness.selectionController.selection, isNull);
      expect(harness.inputSink.inputs, isEmpty);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.iOS}),
  );

  testWidgets(
    'iPhone long press selects a word and exposes a 44-point copy action',
    (tester) async {
      final harness = _MobileViewportHarness();
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.widget());
      await tester.pump();

      final renderObject = tester.renderObject<RenderTerminalViewport>(
        _terminalSurface(),
      );
      final wordPosition = renderObject.localToGlobal(
        Offset(
          renderObject.debugCellSize.width * 7.5,
          renderObject.debugCellSize.height * 0.5,
        ),
      );
      await tester.longPressAt(wordPosition);
      await tester.pumpAndSettle();

      expect(harness.selectionController.selection, isNotNull);
      final copyAction = find.byKey(terminalTouchCopyMenuItemKey);
      expect(copyAction, findsOneWidget);
      expect(tester.getSize(copyAction).height, greaterThanOrEqualTo(44));

      await tester.tap(copyAction);
      await tester.pumpAndSettle();
      expect(harness.copiedText, <String>['beta']);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.iOS}),
  );

  testWidgets(
    'iPhone tap preserves the selection inside and clears it outside',
    (tester) async {
      final harness = _MobileViewportHarness(clipboardText: 'mobile paste');
      addTearDown(harness.dispose);
      harness.selectionController.setSelection(
        const TerminalSelection(
          startRow: 100,
          startCol: 6,
          endRow: 100,
          endCol: 10,
        ),
      );
      await tester.pumpWidget(harness.widget());
      await tester.pump();

      final renderObject = tester.renderObject<RenderTerminalViewport>(
        _terminalSurface(),
      );
      final cellSize = renderObject.debugCellSize;

      await tester.tapAt(
        renderObject.localToGlobal(
          Offset(cellSize.width * 7.5, cellSize.height * 0.5),
        ),
      );
      await tester.pump();

      expect(harness.selectionController.selection, isNotNull);

      await tester.tapAt(
        renderObject.localToGlobal(
          Offset(cellSize.width * 1.5, cellSize.height * 0.5),
        ),
      );
      await tester.pump();

      expect(harness.selectionController.selection, isNull);
      expect(harness.pasteCallbackCount, 0);
      expect(harness.inputSink.inputs, isEmpty);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.iOS}),
  );

  testWidgets(
    'iPhone blank tap clears an outside selection before it pastes',
    (tester) async {
      final harness = _MobileViewportHarness(clipboardText: 'mobile paste');
      addTearDown(harness.dispose);
      harness.selectionController.setSelection(
        const TerminalSelection(
          startRow: 100,
          startCol: 6,
          endRow: 100,
          endCol: 10,
        ),
      );
      await tester.pumpWidget(harness.widget());
      await tester.pump();

      final renderObject = tester.renderObject<RenderTerminalViewport>(
        _terminalSurface(),
      );
      final blankPosition = renderObject.localToGlobal(
        Offset(
          renderObject.debugCellSize.width * 20.5,
          renderObject.debugCellSize.height * 0.5,
        ),
      );

      await tester.tapAt(blankPosition);
      await tester.pump();

      expect(harness.selectionController.selection, isNull);
      expect(harness.pasteCallbackCount, 0);
      expect(harness.inputSink.inputs, isEmpty);

      await tester.tapAt(blankPosition);
      await tester.pump();

      expect(harness.pasteCallbackCount, 1);
      expect(harness.inputSink.inputs, hasLength(1));
      expect(harness.inputSink.inputs.single, 'mobile paste'.codeUnits);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.iOS}),
  );

  testWidgets(
    'iPhone software keyboard can delete repeatedly after a blank-tap paste',
    (tester) async {
      final harness = _MobileViewportHarness(clipboardText: 'mobile paste');
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.widget());
      await tester.pump();

      final renderObject = tester.renderObject<RenderTerminalViewport>(
        _terminalSurface(),
      );
      final blankPosition = renderObject.localToGlobal(
        Offset(
          renderObject.debugCellSize.width * 20.5,
          renderObject.debugCellSize.height * 0.5,
        ),
      );

      await tester.tapAt(blankPosition);
      await tester.pump();

      tester.testTextInput.updateEditingValue(TextEditingValue.empty);
      await tester.pump();
      tester.testTextInput.updateEditingValue(TextEditingValue.empty);
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'x',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      await tester.pump();

      expect(
        harness.inputSink.inputs.map((bytes) => bytes.toList()),
        <List<int>>[
          'mobile paste'.codeUnits,
          const <int>[0x7f],
          const <int>[0x7f],
          'x'.codeUnits,
        ],
      );
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.iOS}),
  );

  testWidgets(
    'iPhone paste backspace proxy stays outside IME composition',
    (tester) async {
      final harness = _MobileViewportHarness(clipboardText: 'mobile paste');
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.widget());
      await tester.pump();

      final renderObject = tester.renderObject<RenderTerminalViewport>(
        _terminalSurface(),
      );
      await tester.tapAt(
        renderObject.localToGlobal(
          Offset(
            renderObject.debugCellSize.width * 20.5,
            renderObject.debugCellSize.height * 0.5,
          ),
        ),
      );
      await tester.pump();

      final proxyText = tester.testTextInput.editingState!['text'] as String;
      expect(proxyText, isNotEmpty);
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: '${proxyText}n',
          selection: TextSelection.collapsed(offset: proxyText.length + 1),
          composing: TextRange(
            start: proxyText.length,
            end: proxyText.length + 1,
          ),
        ),
      );
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: proxyText,
          selection: TextSelection.collapsed(offset: proxyText.length),
        ),
      );
      await tester.pump();

      expect(harness.inputSink.inputs, hasLength(1));

      tester.testTextInput.updateEditingValue(TextEditingValue.empty);
      await tester.pump();

      expect(
        harness.inputSink.inputs.map((bytes) => bytes.toList()),
        <List<int>>[
          'mobile paste'.codeUnits,
          const <int>[0x7f],
        ],
      );
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.iOS}),
  );

  testWidgets(
    'iPhone character tap does not paste clipboard text',
    (tester) async {
      final harness = _MobileViewportHarness(clipboardText: 'mobile paste');
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.widget());
      await tester.pump();

      final renderObject = tester.renderObject<RenderTerminalViewport>(
        _terminalSurface(),
      );
      final characterPosition = renderObject.localToGlobal(
        Offset(
          renderObject.debugCellSize.width * 1.5,
          renderObject.debugCellSize.height * 0.5,
        ),
      );

      await tester.tapAt(characterPosition);
      await tester.pump();

      expect(harness.pasteCallbackCount, 0);
      expect(harness.inputSink.inputs, isEmpty);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.iOS}),
  );

  testWidgets(
    'iPhone drag near a selection endpoint adjusts instead of scrolling',
    (tester) async {
      final harness = _MobileViewportHarness();
      addTearDown(harness.dispose);
      harness.selectionController.setSelection(
        const TerminalSelection(
          startRow: 100,
          startCol: 6,
          endRow: 100,
          endCol: 10,
        ),
      );
      await tester.pumpWidget(harness.widget());
      await tester.pump();

      final renderObject = tester.renderObject<RenderTerminalViewport>(
        _terminalSurface(),
      );
      final cellSize = renderObject.debugCellSize;
      final gesture = await tester.startGesture(
        renderObject.localToGlobal(
          Offset(cellSize.width * 10, cellSize.height * 0.5),
        ),
        kind: PointerDeviceKind.touch,
      );
      await gesture.moveTo(
        renderObject.localToGlobal(
          Offset(cellSize.width * 16, cellSize.height * 0.5),
        ),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();

      final selection = harness.selectionController.selection;
      expect(selection, isNotNull);
      expect(selection!.startRow, 100);
      expect(selection.startCol, 6);
      expect(selection.endRow, 100);
      expect(selection.endCol, 16);
      expect(
        harness.selectionController.textForFrame(harness.controller.frame),
        'beta gamma',
      );
      expect(harness.scrollDeltas, isEmpty);
      expect(harness.inputSink.inputs, isEmpty);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.iOS}),
  );

  testWidgets(
    'iPhone long-press selection auto-scrolls at the top edge row',
    (tester) async {
      final harness = _MobileViewportHarness(
        modes: const TerminalFrameModes(mouseMode: 'any_event'),
        initialScrollbackOffset: 50,
        applyScrolls: true,
      );
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.widget());
      await tester.pump();

      final renderObject = tester.renderObject<RenderTerminalViewport>(
        _terminalSurface(),
      );
      final cellSize = renderObject.debugCellSize;
      final gesture = await tester.startGesture(
        renderObject.localToGlobal(
          Offset(cellSize.width * 7.5, cellSize.height * 2.5),
        ),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 1));
      expect(harness.selectionController.selection, isNotNull);

      await gesture.moveTo(
        renderObject.localToGlobal(
          Offset(cellSize.width * 2.5, cellSize.height * 0.5),
        ),
      );
      await tester.pump();
      final selectionAtEdge = harness.selectionController.selection!;
      await tester.pump(const Duration(milliseconds: 110));

      expect(harness.scrollDeltas, isNotEmpty);
      expect(harness.scrollDeltas.every((delta) => delta > 0), isTrue);
      expect(
        harness.selectionController.selection!.startRow,
        lessThan(selectionAtEdge.startRow),
      );
      expect(harness.inputSink.inputs, isEmpty);

      await gesture.up();
      await tester.pump();
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.iOS}),
  );

  testWidgets(
    'iPhone long press at an edge waits for a selection drag',
    (tester) async {
      final harness = _MobileViewportHarness(
        initialScrollbackOffset: 50,
        applyScrolls: true,
      );
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.widget());
      await tester.pump();

      final renderObject = tester.renderObject<RenderTerminalViewport>(
        _terminalSurface(),
      );
      final cellSize = renderObject.debugCellSize;
      final gesture = await tester.startGesture(
        renderObject.localToGlobal(
          Offset(cellSize.width * 7.5, cellSize.height * 0.5),
        ),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 110));

      expect(harness.selectionController.selection, isNotNull);
      expect(harness.scrollDeltas, isEmpty);

      await gesture.up();
      await tester.pump();
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.iOS}),
  );

  testWidgets(
    'iPhone long-press selection auto-scrolls at the bottom edge row',
    (tester) async {
      final harness = _MobileViewportHarness(
        initialScrollbackOffset: 50,
        applyScrolls: true,
      );
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.widget());
      await tester.pump();

      final renderObject = tester.renderObject<RenderTerminalViewport>(
        _terminalSurface(),
      );
      final cellSize = renderObject.debugCellSize;
      final gesture = await tester.startGesture(
        renderObject.localToGlobal(
          Offset(cellSize.width * 7.5, cellSize.height * 2.5),
        ),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 1));
      expect(harness.selectionController.selection, isNotNull);

      await gesture.moveTo(
        renderObject.localToGlobal(
          Offset(cellSize.width * 2.5, cellSize.height * 5.5),
        ),
      );
      await tester.pump();
      final selectionAtEdge = harness.selectionController.selection!;
      await tester.pump(const Duration(milliseconds: 110));

      expect(harness.scrollDeltas, isNotEmpty);
      expect(harness.scrollDeltas.every((delta) => delta < 0), isTrue);
      expect(
        harness.selectionController.selection!.endRow,
        greaterThan(selectionAtEdge.endRow),
      );

      await gesture.up();
      await tester.pump();
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.iOS}),
  );
}

Finder _terminalSurface() => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_TerminalViewportSurface',
);

final class _MobileViewportHarness {
  _MobileViewportHarness({
    this.modes = TerminalFrameModes.empty,
    int initialScrollbackOffset = 0,
    this.applyScrolls = false,
    this.clipboardText = '',
  }) : controller = TerminalViewportController(),
       selectionController = SelectionController(),
       inputSink = _RecordingInputSink(),
       _scrollbackOffset = initialScrollbackOffset {
    controller
      ..updateMeasuredCellSize(const Size(10, 18))
      ..updateFrame(_frameFor(_scrollbackOffset, modes));
    inputController = TerminalInputController(
      sessionId: 'mobile-review',
      runtime: inputSink,
      readFrame: () => controller.frame,
      readSelection: () => selectionController.textForFrame(controller.frame),
      copySelection: (text) async => copiedText.add(text),
      readClipboard: () async => clipboardText,
    );
  }

  static TerminalFrameDiff _frameFor(
    int scrollbackOffset,
    TerminalFrameModes modes,
  ) {
    const rowTexts = <String>[
      'alpha beta gamma',
      'second terminal row',
      'third terminal row',
      'fourth terminal row',
      'fifth terminal row',
      'sixth terminal row',
    ];
    final viewportStartRow = 100 - scrollbackOffset;
    return TerminalFrameDiff(
      rows: <TerminalRow>[
        for (var index = 0; index < rowTexts.length; index += 1)
          TerminalRow(
            index: index,
            text: rowTexts[index],
            sourceRow: viewportStartRow + index,
          ),
      ],
      cursor: const TerminalCursor(row: 5, col: 0, visible: false),
      viewportRows: 6,
      viewportCols: 30,
      dirtyRanges: const <TerminalDirtyRange>[
        TerminalDirtyRange(start: 0, end: 6),
      ],
      scrollbackOffset: scrollbackOffset,
      scrollbackMaxOffset: 100,
      viewportStartRow: viewportStartRow,
      modes: modes,
    );
  }

  final TerminalViewportController controller;
  final SelectionController selectionController;
  final TerminalFrameModes modes;
  final bool applyScrolls;
  final String clipboardText;
  final _RecordingInputSink inputSink;
  late final TerminalInputController inputController;
  final List<int> scrollDeltas = <int>[];
  final List<String> copiedText = <String>[];
  int pasteCallbackCount = 0;
  int _scrollbackOffset;

  void _handleScrollLines(int delta) {
    scrollDeltas.add(delta);
    if (!applyScrolls) {
      return;
    }
    final nextOffset = (_scrollbackOffset + delta).clamp(0, 100);
    if (nextOffset == _scrollbackOffset) {
      return;
    }
    _scrollbackOffset = nextOffset;
    controller.updateFrame(_frameFor(_scrollbackOffset, modes));
  }

  Widget widget() {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            height: 180,
            child: TerminalViewport(
              controller: controller,
              selectionController: selectionController,
              inputController: inputController,
              onPasteClipboard: () async {
                pasteCallbackCount += 1;
                await inputController.pasteClipboard();
              },
              onScrollLines: _handleScrollLines,
              onScrollToOffset: (_) {},
            ),
          ),
        ),
      ),
    );
  }

  void dispose() {
    controller.dispose();
    selectionController.dispose();
  }
}

final class _RecordingInputSink implements TerminalInputSink {
  final List<Uint8List> inputs = <Uint8List>[];

  @override
  void sendInput(String sessionId, Uint8List bytes) {
    inputs.add(Uint8List.fromList(bytes));
  }
}
