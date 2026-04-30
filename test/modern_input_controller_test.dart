import 'package:flutter_test/flutter_test.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart' as terminal;

import 'package:ianvs_terminal/src/modern_input_controller.dart';

void main() {
  test(
    'updates draft, inserts newline, submits and clears command text',
    () async {
      final submitted = <String>[];
      final controller = ModernInputController(
        submitCommand: (command) async {
          submitted.add(command);
        },
      );

      controller.updateDraft('echo ianvs');
      controller.insertNewline();
      controller.insertText('echo next');

      expect(controller.state.draft, 'echo ianvs\necho next');

      final submittedCommand = await controller.submit();

      expect(submittedCommand, isTrue);
      expect(submitted, <String>['echo ianvs\necho next']);
      expect(controller.state.draft, isEmpty);
    },
  );

  test('empty draft submit is a no-op', () async {
    final submitted = <String>[];
    final controller = ModernInputController(
      submitCommand: (command) async {
        submitted.add(command);
      },
    );

    final submittedCommand = await controller.submit();

    expect(submittedCommand, isFalse);
    expect(submitted, isEmpty);
  });

  test('manual and automatic raw modes determine the effective mode', () {
    final controller = ModernInputController(submitCommand: (_) async {});

    expect(controller.state.effectiveMode, ModernInputEffectiveMode.modern);

    controller.enableManualRaw();
    expect(controller.state.manualRaw, isTrue);
    expect(controller.state.effectiveMode, ModernInputEffectiveMode.raw);

    controller.useModernInput();
    expect(controller.state.manualRaw, isFalse);
    expect(controller.state.effectiveMode, ModernInputEffectiveMode.modern);

    controller.updateAutoRawHintFromModes(
      const terminal.TerminalFrameModes(applicationCursor: true),
    );
    expect(controller.state.autoRawHint, isTrue);
    expect(controller.state.effectiveMode, ModernInputEffectiveMode.raw);

    controller.updateAutoRawHintFromModes(terminal.TerminalFrameModes.empty);
    expect(controller.state.autoRawHint, isFalse);
    expect(controller.state.effectiveMode, ModernInputEffectiveMode.modern);
  });

  test('reset clears draft and returns to modern mode', () {
    final controller = ModernInputController(submitCommand: (_) async {})
      ..updateDraft('pending')
      ..enableManualRaw()
      ..updateAutoRawHintFromModes(
        const terminal.TerminalFrameModes(mouseMode: 'sgr'),
      );

    controller.reset();

    expect(controller.state.draft, isEmpty);
    expect(controller.state.manualRaw, isFalse);
    expect(controller.state.autoRawHint, isFalse);
    expect(controller.state.effectiveMode, ModernInputEffectiveMode.modern);
  });
}
