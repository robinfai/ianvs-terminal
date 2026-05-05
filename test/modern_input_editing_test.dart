import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/src/modern_input_editing.dart';

void main() {
  test('inserts bracket and quote pairs with cursor in the middle', () {
    for (final entry in <String, String>{
      '(': '()',
      '[': '[]',
      '{': '{}',
      "'": "''",
      '"': '""',
    }.entries) {
      final result = applyModernInputPairInsertion(
        const TextEditingValue(text: 'echo '),
        entry.key,
      );

      expect(result, isNotNull);
      expect(result!.text, 'echo ${entry.value}');
      expect(result.selection.baseOffset, 6);
      expect(result.selection.extentOffset, 6);
    }
  });

  test('wraps selected text with bracket and quote pairs', () {
    final result = applyModernInputPairInsertion(
      const TextEditingValue(
        text: 'echo value',
        selection: TextSelection(baseOffset: 5, extentOffset: 10),
      ),
      '(',
    );

    expect(result, isNotNull);
    expect(result!.text, 'echo (value)');
    expect(result.selection.baseOffset, 6);
    expect(result.selection.extentOffset, 11);
  });

  test('skips over existing closing pair instead of inserting duplicate', () {
    final result = applyModernInputPairInsertion(
      const TextEditingValue(
        text: 'echo ()',
        selection: TextSelection.collapsed(offset: 6),
      ),
      ')',
    );

    expect(result, isNotNull);
    expect(result!.text, 'echo ()');
    expect(result.selection.baseOffset, 7);
  });

  test('backspace removes empty surrounding pair', () {
    final result = applyModernInputPairBackspace(
      const TextEditingValue(
        text: 'echo ()',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );

    expect(result, isNotNull);
    expect(result!.text, 'echo ');
    expect(result.selection.baseOffset, 5);
  });

  test('ordinary characters backquote and unrelated keys are ignored', () {
    final value = const TextEditingValue(
      text: 'echo',
      selection: TextSelection.collapsed(offset: 4),
    );

    expect(applyModernInputPairInsertion(value, 'a'), isNull);
    expect(applyModernInputPairInsertion(value, '`'), isNull);
    expect(applyModernInputPairBackspace(value), isNull);
  });

  test('editor shortcuts clear select and delete command text', () {
    final cleared = applyModernInputClearLine(
      const TextEditingValue(
        text: 'echo one\necho two',
        selection: TextSelection.collapsed(offset: 14),
      ),
    );
    expect(cleared.text, 'echo one\ntwo');
    expect(cleared.selection.baseOffset, 9);

    final selected = applyModernInputSelectBuffer(
      const TextEditingValue(text: 'echo all'),
    );
    expect(selected.selection.baseOffset, 0);
    expect(selected.selection.extentOffset, 8);

    final deleted = applyModernInputDeletePreviousWord(
      const TextEditingValue(
        text: 'kubectl get pods',
        selection: TextSelection.collapsed(offset: 16),
      ),
    );
    expect(deleted.text, 'kubectl get ');
    expect(deleted.selection.baseOffset, 12);
  });
}
