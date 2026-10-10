import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../helpers/pump_app.dart';

class _Sink implements TerminalInputSink {
  final writes = <Uint8List>[];

  @override
  void sendInput(String sessionId, Uint8List bytes) => writes.add(bytes);
}

void main() {
  for (final transition in ['finished', 'suspended', 'inactive', 'unmounted']) {
    testWidgets('a clipboard read cannot outlive its $transition block owner', (
      tester,
    ) async {
      final sink = _Sink();
      final clipboard = Completer<String>();
      final input = TerminalInputController(
        sessionId: 'session',
        runtime: sink,
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () => clipboard.future,
      );
      var running = true;
      var suspended = false;
      var active = true;
      late StateSetter update;
      Future<void> mount() => tester.pumpApp(
        StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return CommandBlockTerminal(
              block: CommandBlock(
                id: 'command',
                command: 'interactive command',
                running: running,
                suspended: suspended,
                columns: 80,
                lines: const [TerminalRow(index: 0, text: 'prompt')],
              ),
              liveInput: active ? input : null,
              requestLiveFocus: false,
            );
          },
        ),
      );
      try {
        await mount();
        await tester.pumpAndSettle();
        final oldInput = tester
            .widget<TerminalViewport>(find.byType(TerminalViewport))
            .inputController;
        final pending = oldInput.pasteClipboard();
        if (transition == 'unmounted') {
          await tester.pumpWidget(const SizedBox.shrink());
        } else {
          update(() {
            running = transition != 'finished';
            suspended = transition == 'suspended';
            active = transition != 'inactive';
          });
          await tester.pump();
        }
        clipboard.complete('late paste\n');
        await pending;
        expect(sink.writes, isEmpty);

        if (transition != 'unmounted') {
          // Reacquiring the same source must not reactivate an old callback.
          update(() {
            running = true;
            suspended = false;
            active = true;
          });
          await tester.pump();
          oldInput.sendText('stale callback');
          expect(sink.writes, isEmpty);
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  }

  testWidgets('ordinary output refresh retains a current clipboard operation', (
    tester,
  ) async {
    final sink = _Sink();
    final clipboard = Completer<String>();
    final input = TerminalInputController(
      sessionId: 'session',
      runtime: sink,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () => clipboard.future,
    );
    var text = 'prompt';
    late StateSetter update;
    try {
      await tester.pumpApp(
        StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return CommandBlockTerminal(
              block: CommandBlock(
                id: 'command',
                command: 'interactive command',
                running: true,
                columns: 80,
                lines: [TerminalRow(index: 0, text: text)],
              ),
              liveInput: input,
              requestLiveFocus: false,
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      final oldInput = tester
          .widget<TerminalViewport>(find.byType(TerminalViewport))
          .inputController;
      final pending = oldInput.pasteClipboard();
      update(() => text = 'updated prompt');
      await tester.pump();
      clipboard.complete('valid paste');
      await pending;
      expect(sink.writes, hasLength(1));
      expect(String.fromCharCodes(sink.writes.single), 'valid paste');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}
