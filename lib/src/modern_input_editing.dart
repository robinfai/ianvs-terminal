import 'package:flutter/services.dart';

const Map<String, String> _openingToClosing = <String, String>{
  '(': ')',
  '[': ']',
  '{': '}',
  "'": "'",
  '"': '"',
};

const Set<String> _symmetricPairs = <String>{"'", '"'};

TextEditingValue? applyModernInputPairInsertion(
  TextEditingValue value,
  String input,
) {
  if (input == '`') {
    return null;
  }

  final selection = value.selection.isValid
      ? value.selection
      : TextSelection.collapsed(offset: value.text.length);

  final normalizedSelection = TextSelection(
    baseOffset: selection.start,
    extentOffset: selection.end,
  );
  final start = normalizedSelection.start;
  final end = normalizedSelection.end;
  final text = value.text;

  final openingClose = _openingToClosing[input];
  if (!normalizedSelection.isCollapsed && openingClose != null) {
    final nextText = text.replaceRange(
      start,
      end,
      '$input${text.substring(start, end)}$openingClose',
    );
    return value.copyWith(
      text: nextText,
      selection: TextSelection(baseOffset: start + 1, extentOffset: end + 1),
      composing: TextRange.empty,
    );
  }

  if (!normalizedSelection.isCollapsed) {
    return null;
  }

  if (_isClosingInput(input) &&
      start < text.length &&
      text.substring(start, start + 1) == input) {
    return value.copyWith(
      selection: TextSelection.collapsed(offset: start + 1),
      composing: TextRange.empty,
    );
  }

  if (openingClose == null) {
    return null;
  }

  if (_symmetricPairs.contains(input) &&
      start < text.length &&
      text.substring(start, start + 1) == input) {
    return value.copyWith(
      selection: TextSelection.collapsed(offset: start + 1),
      composing: TextRange.empty,
    );
  }

  final nextText = text.replaceRange(start, end, '$input$openingClose');
  return value.copyWith(
    text: nextText,
    selection: TextSelection.collapsed(offset: start + 1),
    composing: TextRange.empty,
  );
}

TextEditingValue? applyModernInputPairBackspace(TextEditingValue value) {
  final selection = value.selection;
  if (!selection.isValid || !selection.isCollapsed) {
    return null;
  }

  final offset = selection.start;
  final text = value.text;
  if (offset <= 0 || offset >= text.length) {
    return null;
  }

  final before = text.substring(offset - 1, offset);
  final after = text.substring(offset, offset + 1);
  if (_openingToClosing[before] != after) {
    return null;
  }

  return value.copyWith(
    text: text.replaceRange(offset - 1, offset + 1, ''),
    selection: TextSelection.collapsed(offset: offset - 1),
    composing: TextRange.empty,
  );
}

TextEditingValue applyModernInputClearLine(TextEditingValue value) {
  final normalized = _normalizedValue(value);
  final selection = normalized.selection;
  final text = normalized.text;
  final caret = selection.end;
  final lineStart = text.lastIndexOf('\n', caret - 1) + 1;
  final nextText = text.replaceRange(lineStart, caret, '');
  return normalized.copyWith(
    text: nextText,
    selection: TextSelection.collapsed(offset: lineStart),
    composing: TextRange.empty,
  );
}

TextEditingValue applyModernInputSelectBuffer(TextEditingValue value) {
  final normalized = _normalizedValue(value);
  return normalized.copyWith(
    selection: TextSelection(
      baseOffset: 0,
      extentOffset: normalized.text.length,
    ),
    composing: TextRange.empty,
  );
}

TextEditingValue applyModernInputDeletePreviousWord(TextEditingValue value) {
  final normalized = _normalizedValue(value);
  final selection = normalized.selection;
  final text = normalized.text;
  if (!selection.isCollapsed) {
    return normalized.copyWith(
      text: text.replaceRange(selection.start, selection.end, ''),
      selection: TextSelection.collapsed(offset: selection.start),
      composing: TextRange.empty,
    );
  }

  final caret = selection.start;
  if (caret <= 0) {
    return normalized;
  }

  var start = caret;
  while (start > 0 && _isWhitespace(text.codeUnitAt(start - 1))) {
    start -= 1;
  }
  while (start > 0 && !_isWhitespace(text.codeUnitAt(start - 1))) {
    start -= 1;
  }

  return normalized.copyWith(
    text: text.replaceRange(start, caret, ''),
    selection: TextSelection.collapsed(offset: start),
    composing: TextRange.empty,
  );
}

bool _isClosingInput(String input) {
  return _openingToClosing.values.contains(input) &&
      !_symmetricPairs.contains(input);
}

TextEditingValue _normalizedValue(TextEditingValue value) {
  final text = value.text;
  if (!value.selection.isValid) {
    return value.copyWith(
      selection: TextSelection.collapsed(offset: text.length),
      composing: TextRange.empty,
    );
  }
  final start = value.selection.start.clamp(0, text.length);
  final end = value.selection.end.clamp(0, text.length);
  return value.copyWith(
    selection: TextSelection(baseOffset: start, extentOffset: end),
    composing: TextRange.empty,
  );
}

bool _isWhitespace(int codeUnit) {
  return codeUnit == 0x09 ||
      codeUnit == 0x0A ||
      codeUnit == 0x0D ||
      codeUnit == 0x20;
}
