import 'package:app/features/command_center/command_bar_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandBarEditor', () {
    testWidgets('hidden host leaves ordinary terminal keys alone', (
      tester,
    ) async {
      final terminalKeys = <LogicalKeyboardKey>[];
      final terminalFocus = FocusNode(debugLabel: 'terminal-capture');
      addTearDown(terminalFocus.dispose);

      await tester.pumpWidget(
        _app(
          CommandBarEditorHost(
            visible: false,
            controller: CommandBarEditorController(),
            onSend: (_) {},
            child: Focus(
              focusNode: terminalFocus,
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent) {
                  terminalKeys.add(event.logicalKey);
                }
                return KeyEventResult.handled;
              },
              child: const SizedBox(width: 200, height: 80),
            ),
          ),
        ),
      );
      terminalFocus.requestFocus();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);

      expect(find.byKey(const Key('command-bar-editor-field')), findsNothing);
      expect(terminalKeys, [LogicalKeyboardKey.keyA]);
    });

    testWidgets('Shift+Enter inserts newline and Enter sends the command', (
      tester,
    ) async {
      final controller = CommandBarEditorController();
      final sent = <String>[];
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _app(CommandBarEditor(controller: controller, onSend: sent.add)),
      );

      await tester.enterText(
        find.byKey(const Key('command-bar-editor-field')),
        'printf one',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      controller.insertText('printf two');
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);

      expect(sent, ['printf one\nprintf two']);
      expect(controller.text, isEmpty);
    });

    testWidgets('soft wrap does not change sent text', (tester) async {
      final controller = CommandBarEditorController();
      final sent = <String>[];
      const longCommand =
          r'for file in lib test example; do echo "$file"; done';
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 180,
            child: CommandBarEditor(controller: controller, onSend: sent.add),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('command-bar-editor-field')),
        longCommand,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);

      expect(sent, [longCommand]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('read-only blocks sends', (tester) async {
      final controller = CommandBarEditorController();
      final sent = <String>[];
      final blocked = <CommandBarEditorBlockedReason>[];
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _app(
          CommandBarEditor(
            controller: controller,
            readOnly: true,
            onSend: sent.add,
            onBlocked: blocked.add,
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('command-bar-editor-field')),
        'date',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);

      expect(sent, isEmpty);
      expect(blocked, [CommandBarEditorBlockedReason.readOnly]);
      final sendButton = tester.widget<IconButton>(
        find.byKey(const Key('command-bar-editor-send')),
      );
      expect(sendButton.onPressed, isNull);
    });

    testWidgets('IME composition is not intercepted by Enter', (tester) async {
      final controller = CommandBarEditorController();
      final sent = <String>[];
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _app(CommandBarEditor(controller: controller, onSend: sent.add)),
      );
      controller.value = const TextEditingValue(
        text: 'pin',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 0, end: 3),
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);

      expect(sent, isEmpty);
      expect(controller.text, 'pin');
    });

    testWidgets('inserted command text does not auto execute', (tester) async {
      final controller = CommandBarEditorController();
      final sent = <String>[];
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _app(CommandBarEditor(controller: controller, onSend: sent.add)),
      );

      controller.insertText('git status');
      await tester.pump();

      expect(controller.text, 'git status');
      expect(sent, isEmpty);
    });
  });
}

Widget _app(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
    ),
    home: Scaffold(body: Center(child: child)),
  );
}
