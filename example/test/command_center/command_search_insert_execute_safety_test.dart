import 'package:app/features/command_center/command_search_intents.dart';
import 'package:app/features/command_center/command_search_overlay_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandSearchInsertExecutePolicy', () {
    const policy = CommandSearchInsertExecutePolicy();

    test('enter inserts the selected command without sending return', () {
      final intent = policy.resolve(
        const CommandSearchOverlayOutput.insert('flutter test'),
        readOnly: false,
      );

      expect(intent.kind, CommandSearchTerminalIntentKind.insertText);
      expect(intent.text, 'flutter test');
      expect(intent.text, isNot(contains('\n')));
      expect(intent.reason, isNull);
    });

    test('modified enter creates explicit execute text', () {
      final intent = policy.resolve(
        const CommandSearchOverlayOutput.explicitExecute('flutter test'),
        readOnly: false,
      );

      expect(intent.kind, CommandSearchTerminalIntentKind.executeText);
      expect(intent.text, 'flutter test\n');
      expect(intent.reason, isNull);
    });

    test('read only disables insert and explicit execute with reason', () {
      final insert = policy.resolve(
        const CommandSearchOverlayOutput.insert('flutter test'),
        readOnly: true,
      );
      final execute = policy.resolve(
        const CommandSearchOverlayOutput.explicitExecute('flutter test'),
        readOnly: true,
      );

      expect(insert.kind, CommandSearchTerminalIntentKind.disabled);
      expect(execute.kind, CommandSearchTerminalIntentKind.disabled);
      expect(insert.reason, CommandSearchTerminalIntentReason.readOnly);
      expect(execute.reason, CommandSearchTerminalIntentReason.readOnly);
    });

    test('multiline commands are routed to paste policy', () {
      final intent = policy.resolve(
        const CommandSearchOverlayOutput.explicitExecute(
          'printf hello\nprintf world',
        ),
        readOnly: false,
      );

      expect(intent.kind, CommandSearchTerminalIntentKind.requiresPastePolicy);
      expect(intent.text, 'printf hello\nprintf world');
      expect(
        intent.reason,
        CommandSearchTerminalIntentReason.multilineRequiresPastePolicy,
      );
    });

    test('empty selection produces no terminal write', () {
      final intent = policy.resolve(
        CommandSearchOverlayOutput.none,
        readOnly: false,
      );

      expect(intent.kind, CommandSearchTerminalIntentKind.none);
      expect(intent.text, isNull);
      expect(intent.writesToShell, isFalse);
    });
  });
}
