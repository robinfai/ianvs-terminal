import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/src/terminal/terminal_input_controller.dart';
import 'package:ianvs_terminal_core/src/terminal/terminal_input_sink.dart';
import 'package:ianvs_terminal_core/src/terminal/terminal_models.dart';

void main() {
  testWidgets(
    'Linux plain Control-C and Control-V remain terminal control bytes',
    (tester) async {
      final fixture = _InputFixture();
      await tester.pumpWidget(fixture.widget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      for (final key in [LogicalKeyboardKey.keyC, LogicalKeyboardKey.keyV]) {
        await tester.sendKeyDownEvent(key);
        await tester.sendKeyRepeatEvent(key);
        await tester.sendKeyUpEvent(key);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(fixture.input, <String>['\x03', '\x03', '\x16', '\x16']);
      expect(fixture.copiedText, isEmpty);
      expect(fixture.clipboardReads, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'Linux plain Control-C and Control-V retain Kitty keyboard events',
    (tester) async {
      final fixture = _InputFixture(kittyKeyboardFlags: 3);
      await tester.pumpWidget(fixture.widget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      for (final key in [LogicalKeyboardKey.keyC, LogicalKeyboardKey.keyV]) {
        await tester.sendKeyDownEvent(key);
        await tester.sendKeyRepeatEvent(key);
        await tester.sendKeyUpEvent(key);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(fixture.input, <String>[
        '\x1B[99;5u',
        '\x1B[99;5:2u',
        '\x1B[99;5:3u',
        '\x1B[118;5u',
        '\x1B[118;5:2u',
        '\x1B[118;5:3u',
      ]);
      expect(fixture.copiedText, isEmpty);
      expect(fixture.clipboardReads, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  for (final kittyKeyboardFlags in [0, 3]) {
    testWidgets(
      'Linux Control-Shift clipboard shortcuts run once with Kitty flags '
      '$kittyKeyboardFlags',
      (tester) async {
        final fixture = _InputFixture(kittyKeyboardFlags: kittyKeyboardFlags);
        await tester.pumpWidget(fixture.widget);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        for (final key in [LogicalKeyboardKey.keyC, LogicalKeyboardKey.keyV]) {
          await tester.sendKeyDownEvent(key);
          await tester.sendKeyRepeatEvent(key);
          await tester.sendKeyUpEvent(key);
        }
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();

        expect(fixture.copiedText, <String>['selection']);
        expect(fixture.clipboardReads, 1);
        expect(fixture.input, <String>['\x1B[200~clipboard\x1B[201~']);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  }

  for (final extraModifier in [
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.metaLeft,
  ]) {
    testWidgets(
      'Linux clipboard shortcuts reject an extra ${extraModifier.keyLabel}',
      (tester) async {
        final fixture = _InputFixture();
        await tester.pumpWidget(fixture.widget);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyDownEvent(extraModifier);
        for (final key in [LogicalKeyboardKey.keyC, LogicalKeyboardKey.keyV]) {
          await tester.sendKeyDownEvent(key);
          await tester.sendKeyUpEvent(key);
        }
        await tester.sendKeyUpEvent(extraModifier);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();

        expect(fixture.copiedText, isEmpty);
        expect(fixture.clipboardReads, 0);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  }

  testWidgets(
    'macOS Command clipboard shortcuts preserve copy and bracketed paste',
    (tester) async {
      final fixture = _InputFixture(kittyKeyboardFlags: 3);
      await tester.pumpWidget(fixture.widget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      for (final key in [LogicalKeyboardKey.keyC, LogicalKeyboardKey.keyV]) {
        await tester.sendKeyDownEvent(key);
        await tester.sendKeyRepeatEvent(key);
        await tester.sendKeyUpEvent(key);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      expect(fixture.copiedText, <String>['selection']);
      expect(fixture.clipboardReads, 1);
      expect(fixture.input, <String>['\x1B[200~clipboard\x1B[201~']);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}

class _InputFixture implements TerminalInputSink {
  _InputFixture({int kittyKeyboardFlags = 0}) {
    controller = TerminalInputController(
      sessionId: 'test-session',
      runtime: this,
      readFrame: () => TerminalFrameDiff(
        rows: const [],
        cursor: const TerminalCursor(row: 0, col: 0, visible: true),
        viewportRows: 24,
        viewportCols: 80,
        dirtyRanges: const [],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
        modes: TerminalFrameModes(
          bracketedPaste: true,
          kittyKeyboardFlags: kittyKeyboardFlags,
        ),
      ),
      readSelection: () => 'selection',
      copySelection: (text) async => copiedText.add(text),
      readClipboard: () async {
        clipboardReads += 1;
        return 'clipboard';
      },
    );
  }

  late final TerminalInputController controller;
  final List<String> copiedText = <String>[];
  final List<String> input = <String>[];
  int clipboardReads = 0;

  Widget get widget => Directionality(
    textDirection: TextDirection.ltr,
    child: Focus(
      autofocus: true,
      onKeyEvent: (_, event) => controller.handle(event),
      child: const SizedBox.expand(),
    ),
  );

  @override
  void sendInput(String sessionId, Uint8List bytes) {
    expect(sessionId, 'test-session');
    input.add(utf8.decode(bytes));
  }
}
