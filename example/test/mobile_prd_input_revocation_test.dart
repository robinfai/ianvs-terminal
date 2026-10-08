import 'dart:async';
import 'dart:convert';

import 'package:app/features/terminal/terminal_input_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;

class _InputSink implements terminal.TerminalInputSink {
  final writes = <(String, String)>[];

  @override
  void sendInput(String sessionId, Uint8List bytes) {
    writes.add((sessionId, utf8.decode(bytes)));
  }
}

class _ProtocolSink extends _InputSink
    implements terminal.TerminalProtocolInputSink {
  final protocolWrites = <(String, String)>[];

  @override
  void sendProtocolInput(String sessionId, Uint8List bytes) {
    protocolWrites.add((sessionId, utf8.decode(bytes)));
  }
}

TerminalInputController _input(
  terminal.TerminalInputSink sink, {
  required bool Function() readOnly,
  Future<String> Function()? readClipboard,
}) => TerminalInputController(
  sessionId: 'original-session',
  runtime: sink,
  readOnly: readOnly,
  readSelection: () => '',
  copySelection: (_) async {},
  readClipboard: readClipboard ?? () async => '',
);

const _reportingModes = terminal.TerminalFrameModes(
  focusTracking: true,
  mouseMode: 'any_event',
  mouseEncoding: 'sgr',
);

void main() {
  test(
    'clipboard completion cannot write after input ownership is revoked',
    () async {
      final sink = _ProtocolSink();
      final clipboard = Completer<String>();
      var readOnly = false;
      var reads = 0;
      final input = _input(
        sink,
        readOnly: () => readOnly,
        readClipboard: () {
          reads++;
          return clipboard.future;
        },
      );

      final pendingPaste = input.pasteClipboard();
      expect(reads, 1);
      readOnly = true;
      clipboard.complete('do not submit this stale paste');
      await pendingPaste;

      expect(sink.writes, isEmpty);
      expect(sink.protocolWrites, isEmpty);
      await input.pasteClipboard();
      expect(
        reads,
        1,
        reason: 'A newly blocked paste must not read the clipboard',
      );

      readOnly = false;
      await input.pasteClipboard();
      expect(sink.writes, [
        ('original-session', 'do not submit this stale paste'),
      ], reason: 'Only a new explicit paste after takeover may write');
    },
  );

  testWidgets(
    'Meta+V private base-controller paste rechecks ownership after clipboard await',
    (tester) async {
      final sink = _ProtocolSink();
      final clipboard = Completer<String>();
      var readOnly = false;
      var reads = 0;
      final input = _input(
        sink,
        readOnly: () => readOnly,
        readClipboard: () {
          reads++;
          return clipboard.future;
        },
      );
      await tester.pumpWidget(
        Focus(
          autofocus: true,
          onKeyEvent: (_, event) => input.handle(event),
          child: const SizedBox(width: 100, height: 100),
        ),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV, platform: 'macos');
      expect(reads, 1);

      readOnly = true;
      clipboard.complete('stale shortcut paste');
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV, platform: 'macos');
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
      await tester.pump();

      expect(sink.writes, isEmpty);
      expect(sink.protocolWrites, isEmpty);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  test(
    'retained text, focus, mouse and sink callbacks lose write capability',
    () {
      final sink = _ProtocolSink();
      var readOnly = false;
      final input = _input(sink, readOnly: () => readOnly);
      final sendText = input.sendText;
      final sendFocus = input.sendFocusReport;
      final sendMouse = input.sendMouseReport;
      final retainedSink = input.runtime;

      sendText('manual');
      sendFocus(focused: true, modes: _reportingModes);
      sendMouse(
        modes: _reportingModes,
        row: 0,
        col: 0,
        button: 0,
        pressed: true,
      );
      expect(sink.writes, [
        ('original-session', 'manual'),
        ('original-session', '\x1b[<0;1;1M'),
      ]);
      expect(sink.protocolWrites, [('original-session', '\x1b[I')]);
      sink.writes.clear();
      sink.protocolWrites.clear();

      readOnly = true;
      sendText('stale IME commit');
      sendFocus(focused: false, modes: _reportingModes);
      sendMouse(
        modes: _reportingModes,
        row: 2,
        col: 3,
        button: 0,
        pressed: true,
      );
      retainedSink.sendInput('original-session', Uint8List.fromList([0x41]));
      expect(retainedSink, isA<terminal.TerminalProtocolInputSink>());
      (retainedSink as terminal.TerminalProtocolInputSink).sendProtocolInput(
        'original-session',
        Uint8List.fromList([0x42]),
      );

      expect(sink.writes, isEmpty);
      expect(sink.protocolWrites, isEmpty);

      readOnly = false;
      sendText('new manual input');
      expect(sink.writes, [('original-session', 'new manual input')]);
    },
  );

  test(
    'focus fallback for a plain input sink remains dynamically revocable',
    () {
      final sink = _InputSink();
      var readOnly = false;
      final input = _input(sink, readOnly: () => readOnly);
      final retainedSink = input.runtime as terminal.TerminalProtocolInputSink;
      input.sendFocusReport(focused: true, modes: _reportingModes);
      expect(sink.writes, [('original-session', '\x1b[I')]);
      sink.writes.clear();

      readOnly = true;
      retainedSink.sendProtocolInput(
        'original-session',
        Uint8List.fromList(ascii.encode('\x1b[O')),
      );
      expect(sink.writes, isEmpty);
    },
  );

  testWidgets(
    'rebuilding a guarded controller preserves the original focus-report owner',
    (tester) async {
      final sink = _ProtocolSink();
      final viewport = terminal.TerminalViewportController()
        ..updateFrame(
          const terminal.TerminalFrameDiff(
            rows: [terminal.TerminalRow(index: 0, text: 'focused terminal')],
            cursor: terminal.TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [terminal.TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
            modes: _reportingModes,
          ),
        );
      final selection = terminal.SelectionController();
      final focus = FocusNode();
      var readOnly = false;
      Widget buildTerminal() => MaterialApp(
        home: Scaffold(
          body: terminal.TerminalViewport(
            controller: viewport,
            selectionController: selection,
            focusNode: focus,
            inputController: _input(sink, readOnly: () => readOnly),
            onScrollLines: (_) {},
            onScrollToOffset: (_) {},
          ),
        ),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        focus.dispose();
        selection.dispose();
        viewport.dispose();
      });
      await tester.pumpWidget(buildTerminal());
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      expect(sink.protocolWrites, contains(('original-session', '\x1b[I')));
      sink.writes.clear();
      sink.protocolWrites.clear();

      await tester.pumpWidget(buildTerminal());
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      expect(
        sink.protocolWrites,
        isEmpty,
        reason: 'A new revocable wrapper is still the same PTY focus owner',
      );
      expect(sink.writes, isEmpty);

      readOnly = true;
      await tester.pumpWidget(buildTerminal());
      focus.unfocus();
      await tester.pump();
      expect(sink.protocolWrites, isEmpty);
    },
  );
}
