import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../helpers/pump_app.dart';

class _Sink implements TerminalInputSink {
  @override
  void sendInput(String sessionId, List<int> bytes) {}
}

void main() {
  for (final scenario in ['same pane', 'another editor', 'modal', 'inactive']) {
    testWidgets('new running block respects $scenario focus', (tester) async {
      final editorFocus = FocusNode(debugLabel: 'Source composer');
      final terminalFocus = FocusNode(debugLabel: 'Live block');
      final otherFocus = FocusNode(debugLabel: 'Other pane editor');
      final dialogFocus = FocusNode(debugLabel: 'Settings editor');
      final input = TerminalInputController(
        sessionId: 'session',
        runtime: _Sink(),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );
      var running = false;
      late StateSetter update;
      try {
        await tester.pumpApp(
          StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return Scaffold(
                body: Column(
                  children: [
                    TextField(focusNode: editorFocus),
                    TextField(focusNode: otherFocus),
                    Expanded(
                      child: running
                          ? CommandBlockTerminal(
                              block: const CommandBlock(
                                id: 'command',
                                command: 'interactive command',
                                running: true,
                                columns: 80,
                                lines: [TerminalRow(index: 0, text: 'prompt')],
                              ),
                              liveInput: input,
                              liveFocus: terminalFocus,
                              liveFocusSource: editorFocus,
                            )
                          : const SizedBox.expand(),
                    ),
                  ],
                ),
              );
            },
          ),
        );
        await tester.pumpAndSettle();
        editorFocus.requestFocus();
        await tester.pump();

        if (scenario == 'another editor') {
          otherFocus.requestFocus();
          await tester.pump();
        } else if (scenario == 'modal') {
          final context = tester.element(find.byType(TextField).first);
          unawaited(
            showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Settings'),
                content: TextField(focusNode: dialogFocus),
              ),
            ),
          );
          await tester.pumpAndSettle();
          dialogFocus.requestFocus();
          await tester.pump();
        } else if (scenario == 'inactive') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await tester.pump();
        }

        final owner = FocusManager.instance.primaryFocus;
        update(() => running = true);
        await tester.pump();
        await tester.pump();
        if (scenario == 'same pane') {
          expect(terminalFocus.hasFocus, isTrue);
        } else {
          expect(FocusManager.instance.primaryFocus, same(owner));
          expect(terminalFocus.hasFocus, isFalse);
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        editorFocus.dispose();
        terminalFocus.dispose();
        otherFocus.dispose();
        dialogFocus.dispose();
      }
    });
  }
}
