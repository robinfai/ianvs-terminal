import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ianvs_terminal/main.dart';
import 'package:ianvs_terminal/src/terminal_blocks.dart';

import 'support/fake_terminal_backend.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('modern input focus e2e', () {
    testWidgets('starts single-line and keeps focus while expanding', (
      tester,
    ) async {
      final backend = FakePtySessionBackend();
      await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
      await _pumpTerminalUi(tester);

      final fieldFinder = find.byKey(const Key('terminal-modern-input-field'));
      await tester.tap(fieldFinder);
      await _pumpTerminalUi(tester);

      var field = tester.widget<TextField>(fieldFinder);
      expect(field.focusNode?.hasFocus, isTrue);
      expect(field.maxLines, 1);

      await tester.enterText(fieldFinder, 'echo one');
      await _pumpTerminalUi(tester);

      field = tester.widget<TextField>(fieldFinder);
      expect(field.focusNode?.hasFocus, isTrue);
      expect(field.maxLines, 1);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await _pumpTerminalUi(tester);

      expect(_modernInputText(tester), 'echo one\n');
      field = tester.widget<TextField>(fieldFinder);
      expect(field.focusNode?.hasFocus, isTrue);
      expect(field.maxLines, 2);
    });

    testWidgets('completed block stays on modern input during auto-raw updates', (
      tester,
    ) async {
      final backend = FakePtySessionBackend();
      final clipboard = FakeClipboardClient('echo complete');
      await tester.pumpWidget(
        IanvsTerminalApp(
          backendFactory: () => backend,
          clipboardClient: clipboard,
          initialBlocksForSession: terminalBlocksForSession,
        ),
      );
      await _pumpTerminalUi(tester);

      final fieldFinder = find.byKey(const Key('terminal-modern-input-field'));
      await tester.tap(fieldFinder);
      await tester.enterText(fieldFinder, 'pwd');
      await _pumpTerminalUi(tester);

      var field = tester.widget<TextField>(fieldFinder);
      expect(field.focusNode?.hasFocus, isTrue);
      expect(
        find.byKey(const Key('terminal-input-command-detection-strip')),
        findsNothing,
      );
      expect(find.byKey(const Key('terminal-input-context-strip')), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('terminal-inline-block-chip-session-1-block-1')),
      );
      await _pumpTerminalUi(tester);

      backend.enqueueFrame(
        frameJson(
          modes: const <String, Object?>{'application_cursor': true},
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await _pumpTerminalUi(tester);

      expect(find.textContaining('Auto raw'), findsNothing);
      field = tester.widget<TextField>(fieldFinder);
      expect(field.focusNode?.hasFocus, isTrue);

      await _selectHeaderOverflowAction(tester, 'paste');
      expect(_modernInputText(tester), contains('echo complete'));
      expect(backend.writesBySession['session-1'], isNull);
    });

    testWidgets('completed block raw request switches to running terminal', (
      tester,
    ) async {
      final backend = FakePtySessionBackend();
      await tester.pumpWidget(
        IanvsTerminalApp(
          backendFactory: () => backend,
          initialBlocksForSession: terminalBlocksForSession,
        ),
      );
      await _pumpTerminalUi(tester);

      await tester.tap(
        find.byKey(const Key('terminal-inline-block-chip-session-1-block-1')),
      );
      await _pumpTerminalUi(tester);
      await _metaShiftShortcut(tester, LogicalKeyboardKey.keyI);
      await _pumpTerminalUi(tester);

      expect(find.textContaining('Raw input active'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'ianvs-terminal');
      expect(
        find.descendant(
          of: find.byKey(const Key('terminal-inline-active-block-card')),
          matching: find.textContaining('sleep 1'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'completed block without running stays modern and still submits',
      (tester) async {
        final backend = FakePtySessionBackend();
        await tester.pumpWidget(
          IanvsTerminalApp(
            backendFactory: () => backend,
            initialBlocksForSession: (String sessionId) {
              if (sessionId != 'session-1') {
                return const <TerminalBlock>[];
              }
              return const <TerminalBlock>[
                TerminalBlock(
                  id: 'session-1-block-1',
                  sessionId: 'session-1',
                  commandText: 'pwd',
                  outputText: '/tmp\n',
                  status: TerminalBlockStatus.succeeded,
                  scrollbackOffset: 2,
                  recordedAt: '2026-05-04T09:00:00Z',
                ),
              ];
            },
          ),
        );
        await _pumpTerminalUi(tester);

        await _metaShiftShortcut(tester, LogicalKeyboardKey.keyI);
        await _pumpTerminalUi(tester);

        expect(find.textContaining('Raw input active'), findsNothing);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'ianvs-modern-input',
        );

        final fieldFinder = find.byKey(const Key('terminal-modern-input-field'));
        await tester.enterText(fieldFinder, 'echo no-running');
        await _pumpTerminalUi(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await _pumpTerminalUi(tester);

        expect(
          backend.writesBySession['session-1'],
          contains('echo no-running\r'),
        );
      },
    );
  });
}

Future<void> _pumpTerminalUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _selectHeaderOverflowAction(
  WidgetTester tester,
  String action,
) async {
  final overflowMenu = find.byKey(
    const Key('terminal-header-overflow-menu-button'),
  );
  tester.widget<PopupMenuButton<String>>(overflowMenu).onSelected!(action);
  await _pumpTerminalUi(tester);
}

String _modernInputText(WidgetTester tester) {
  return tester
      .widget<TextField>(find.byKey(const Key('terminal-modern-input-field')))
      .controller!
      .text;
}

Future<void> _metaShiftShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump();
}
