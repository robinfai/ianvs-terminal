import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../helpers/pump_app.dart';

class _Sink implements TerminalInputSink {
  final writes = <Uint8List>[];

  @override
  void sendInput(String sessionId, Uint8List bytes) => writes.add(bytes);
}

Map<String, Object?> _block(
  String id, {
  required bool running,
  bool suspended = false,
}) => {
  'id': id,
  'command': '$id shell',
  'contextId': id,
  'running': running,
  'suspended': suspended,
  'segmented': id == 'parent',
  'cursorLine': suspended ? 1 : 0,
  'columns': 80,
  'totalLines': 1,
  'sourceLineCount': 1,
  'matchingLines': 1,
  'lines': [
    {'index': 0, 'source_row': 100, 'text': '$id output', 'wrapped': false},
  ],
};

Finder _viewport(String id) => find.descendant(
  of: find.byKey(ValueKey('block-terminal-$id')),
  matching: find.byType(TerminalViewport),
);

Future<void> _click(
  WidgetTester tester,
  Finder target, {
  PointerDeviceKind kind = PointerDeviceKind.mouse,
}) async {
  // The terminal is wider than a phone's horizontal viewport. Its geometric
  // center may be off screen and cannot be used as a user interaction target.
  const alignment = Alignment(-.9, 0);
  expect(target.hitTestable(at: alignment), findsOneWidget);
  final rect = tester.getRect(target);
  final gesture = await tester.startGesture(
    alignment.withinRect(rect),
    kind: kind,
  );
  await gesture.up();
  await tester.pump();
}

Future<void> _ctrlC(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  group('$TerminalCommandBlocksView input ownership', () {
    late _Sink sink;
    late FocusNode focus;
    late TerminalInputController input;
    late CommandBlockController controller;
    late bool childRunning;
    late bool parentSuspended;
    const modes = TerminalFrameModes(mouseMode: 'normal', mouseEncoding: 'sgr');

    setUp(() {
      sink = _Sink();
      focus = FocusNode();
      input = TerminalInputController(
        sessionId: 'pty',
        runtime: sink,
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => 'paste',
      );
      childRunning = true;
      parentSuspended = true;
      controller = CommandBlockController(
        request: (_) => {
          'blocks': [
            _block('parent', running: true, suspended: parentSuspended),
            _block('child', running: childRunning),
          ],
        },
      )..refresh();
    });

    tearDown(() {
      controller.dispose();
      focus.dispose();
    });

    for (final phone in [false, true]) {
      testWidgets(
        'routes keys, paste and mouse only to the active shell on ${phone ? 'phone' : 'desktop'}',
        (tester) async {
          tester.view.physicalSize = phone
              ? const Size(390, 844)
              : const Size(1000, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          try {
            await tester.pumpApp(
              Scaffold(
                body: TerminalCommandBlocksView(
                  controller: controller,
                  onReinput: (_) {},
                  liveInput: input,
                  liveFocus: focus,
                  liveModes: modes,
                ),
              ),
              theme: ThemeData(
                platform: phone ? TargetPlatform.iOS : TargetPlatform.macOS,
              ),
            );
            await tester.pumpAndSettle();
            final parent = tester.widget<TerminalViewport>(_viewport('parent'));
            final child = tester.widget<TerminalViewport>(_viewport('child'));
            expect(parent.readOnly, isTrue);
            expect(parent.focusNode, isNot(same(focus)));
            expect(parent.controller.frame.cursor.visible, isFalse);
            expect(child.readOnly, isFalse);
            expect(child.focusNode, same(focus));

            sink.writes.clear();
            await _click(tester, _viewport('parent'));
            expect(focus.hasFocus, isFalse);
            if (phone) {
              await _click(
                tester,
                _viewport('parent'),
                kind: PointerDeviceKind.touch,
              );
              expect(focus.hasFocus, isFalse);
            }
            await _ctrlC(tester);
            await parent.inputController.pasteClipboard();
            expect(sink.writes, isEmpty);

            await _click(tester, _viewport('child'));
            expect(
              sink.writes,
              isNotEmpty,
              reason: 'The active child receives mouse reports',
            );
            sink.writes.clear();
            await _ctrlC(tester);
            expect(sink.writes, [
              <int>[3],
            ]);
            sink.writes.clear();
            await child.inputController.pasteClipboard();
            expect(sink.writes, [
              <int>[112, 97, 115, 116, 101],
            ]);

            // The nested shell is now at its prompt. Its parent is still running
            // and suspended; selecting the last running block would be wrong.
            childRunning = false;
            controller.refresh();
            await tester.pumpAndSettle();
            sink.writes.clear();
            await _click(tester, _viewport('parent'));
            await _ctrlC(tester);
            await tester
                .widget<TerminalViewport>(_viewport('parent'))
                .inputController
                .pasteClipboard();
            expect(sink.writes, isEmpty);
            expect(
              tester
                  .widgetList<TerminalViewport>(find.byType(TerminalViewport))
                  .every(
                    (viewport) =>
                        viewport.readOnly &&
                        !viewport.controller.frame.cursor.visible,
                  ),
              isTrue,
            );

            parentSuspended = false;
            controller.refresh();
            await tester.pumpAndSettle();
            await _click(tester, _viewport('parent'));
            sink.writes.clear();
            await _ctrlC(tester);
            expect(sink.writes, [
              <int>[3],
            ]);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
          }
        },
        variant: TargetPlatformVariant({
          if (phone) TargetPlatform.iOS else TargetPlatform.macOS,
        }),
      );
    }

    testWidgets(
      'does not create a live cursor or input in an empty suspended block',
      (tester) async {
        try {
          await tester.pumpApp(
            Scaffold(
              body: CommandBlockTerminal(
                block: const CommandBlock(
                  id: 'parent',
                  command: 'bash',
                  running: true,
                  suspended: true,
                ),
                liveInput: input,
                liveFocus: focus,
                modes: modes,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final viewport = tester.widget<TerminalViewport>(
            find.byType(TerminalViewport),
          );

          expect(viewport.controller.frame.cursor.visible, isFalse);
          await _click(tester, find.byType(TerminalViewport));
          await _ctrlC(tester);
          await viewport.inputController.pasteClipboard();
          expect(sink.writes, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
    );
  });
}
