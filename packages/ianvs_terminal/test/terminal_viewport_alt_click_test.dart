import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:ianvs_terminal/src/terminal/render_terminal_viewport.dart';

void main() {
  group('TerminalViewport Alt click', () {
    testWidgets(
      'sends one unmodified arrow batch and bypasses copy and links',
      (tester) async {
        final harness = await _pump(tester);
        await _click(tester, harness, col: 2);
        expect(harness.sink.inputs, ['\x1b[D' * 6]);
        expect(harness.copies, isEmpty);
        expect(harness.links, isEmpty);
        expect(harness.selection.selection, isNull);
      },
    );
    testWidgets('supports wrapped rows and alternate application cursor mode', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        modes: const TerminalFrameModes(
          alternateScreen: true,
          applicationCursor: true,
        ),
      );
      await _click(tester, harness, row: 1, col: 2);
      expect(harness.sink.inputs, ['\x1bOB${'\x1bOD' * 6}']);
    });
    testWidgets('does not navigate when disabled or viewing scrollback', (
      tester,
    ) async {
      final harness = await _pump(tester, enabled: false);
      await _click(tester, harness, col: 2);
      expect(harness.sink.inputs, isEmpty);
      harness.controller.updateFrame(_frame(scroll: 1));
      await tester.pumpWidget(harness.widget());
      await _click(tester, harness, col: 2);
      expect(harness.sink.inputs, isEmpty);
    });
    testWidgets(
      'keeps Alt drag as block selection even after returning to start',
      (tester) async {
        final harness = await _pump(tester);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        final start = harness.point(tester, 0, 2);
        final gesture = await tester.startGesture(
          start,
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveTo(harness.point(tester, 1, 7));
        await tester.pump();
        expect(harness.selection.isBlockSelection, isTrue);
        await gesture.moveTo(start);
        await gesture.up();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        expect(harness.sink.inputs, isEmpty);
      },
    );
    testWidgets('uses the latest cursor when output arrives during the click', (
      tester,
    ) async {
      final harness = await _pump(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      final gesture = await tester.startGesture(
        harness.point(tester, 0, 2),
        kind: PointerDeviceKind.mouse,
      );
      harness.controller.updateFrame(_frame(cursorCol: 10));
      await tester.pump();
      await gesture.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      expect(harness.sink.inputs, ['\x1b[D' * 8]);
    });
    testWidgets('empty-space dragging remains selection and sends no arrows', (
      tester,
    ) async {
      final harness = await _pump(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      final gesture = await tester.startGesture(
        harness.point(tester, 2, 2),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(harness.point(tester, 2, 12));
      await gesture.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      expect(harness.sink.inputs, isEmpty);
    });
    testWidgets('long press and cancellation do not navigate', (tester) async {
      final harness = await _pump(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      final gesture = await tester.startGesture(
        harness.point(tester, 0, 2),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.up(timeStamp: const Duration(milliseconds: 600));
      expect(harness.sink.inputs, isEmpty);
      final cancelled = await tester.startGesture(
        harness.point(tester, 0, 3),
        kind: PointerDeviceKind.mouse,
      );
      await cancelled.cancel();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      expect(harness.sink.inputs, isEmpty);
    });
    testWidgets('mouse reporting owns the gesture without synthetic arrows', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        modes: const TerminalFrameModes(
          mouseMode: 'normal',
          mouseEncoding: 'sgr',
        ),
      );
      await _click(tester, harness, col: 2);
      expect(harness.sink.inputs, hasLength(2));
      expect(
        harness.sink.inputs.every((input) => input.startsWith('\x1b[<')),
        isTrue,
      );
    });
    testWidgets(
      'mode change during a local click does not emit orphan mouse release',
      (tester) async {
        final harness = await _pump(tester);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        final gesture = await tester.startGesture(
          harness.point(tester, 0, 2),
          kind: PointerDeviceKind.mouse,
        );
        harness.controller.updateFrame(
          _frame(
            modes: const TerminalFrameModes(
              mouseMode: 'normal',
              mouseEncoding: 'sgr',
            ),
          ),
        );
        await tester.pump();
        await gesture.up();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        expect(harness.sink.inputs, isEmpty);
      },
    );
    testWidgets('ordinary click and touch do not move the input cursor', (
      tester,
    ) async {
      final harness = await _pump(tester);
      final gesture = await tester.startGesture(
        harness.point(tester, 0, 2),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.up();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(harness.point(tester, 0, 3));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      expect(harness.sink.inputs, isEmpty);
    });
  });
}

Future<_Harness> _pump(
  WidgetTester tester, {
  bool enabled = true,
  TerminalFrameModes modes = TerminalFrameModes.empty,
}) async {
  final harness = _Harness(modes);
  addTearDown(harness.controller.dispose);
  addTearDown(harness.selection.dispose);
  await tester.pumpWidget(harness.widget(enabled: enabled));
  await tester.pump();
  return harness;
}

Future<void> _click(
  WidgetTester tester,
  _Harness harness, {
  int row = 0,
  required int col,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  final gesture = await tester.startGesture(
    harness.point(tester, row, col),
    kind: PointerDeviceKind.mouse,
  );
  await gesture.up(timeStamp: const Duration(milliseconds: 100));
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await tester.pump(const Duration(milliseconds: 400));
}

class _Harness {
  _Harness(TerminalFrameModes modes) {
    controller.updateFrame(_frame(modes: modes));
    input = TerminalInputController(
      sessionId: 'test',
      runtime: sink,
      readFrame: () => controller.frame,
      readSelection: () => selection.textForFrame(controller.frame),
      copySelection: (text) async => copies.add(text),
      readClipboard: () async => '',
    );
  }
  final controller = TerminalViewportController();
  final selection = SelectionController();
  final sink = _Sink();
  final copies = <String>[];
  final links = <String>[];
  late final TerminalInputController input;
  Widget widget({bool enabled = true}) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 400,
          height: 180,
          child: TerminalViewport(
            controller: controller,
            selectionController: selection,
            inputController: input,
            altClickMovesCursor: enabled,
            copyOnSelect: true,
            onOpenLink: links.add,
            onScrollLines: (_) {},
            onScrollToOffset: (_) {},
          ),
        ),
      ),
    ),
  );
  Offset point(WidgetTester tester, int row, int col) {
    final render = tester.allRenderObjects
        .whereType<RenderTerminalViewport>()
        .single;
    return render.localToGlobal(
      Offset(
        (col + 0.2) * render.debugCellSize.width,
        (row + 0.5) * render.debugCellSize.height,
      ),
    );
  }
}

class _Sink implements TerminalInputSink {
  final inputs = <String>[];
  @override
  void sendInput(String sessionId, Uint8List bytes) =>
      inputs.add(utf8.decode(bytes));
}

TerminalFrameDiff _frame({
  TerminalFrameModes modes = TerminalFrameModes.empty,
  int scroll = 0,
  int cursorCol = 8,
}) => TerminalFrameDiff(
  rows: const [
    TerminalRow(index: 0, text: 'https://example.com'),
    TerminalRow(index: 1, text: 'second line'),
    TerminalRow(index: 2, text: ''),
  ],
  cursor: TerminalCursor(row: 0, col: cursorCol, visible: true),
  viewportRows: 3,
  viewportCols: 30,
  dirtyRanges: const [],
  scrollbackOffset: scroll,
  scrollbackMaxOffset: 20,
  modes: modes,
);
