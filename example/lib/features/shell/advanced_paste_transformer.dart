import 'dart:convert';

String transformAdvancedPasteText(
  String text, {
  required bool escapeSpecialCharacters,
  required bool base64Encode,
  required bool appendNewline,
}) {
  var output = text;
  if (escapeSpecialCharacters) {
    output = escapePasteSpecialCharacters(output);
  }
  if (base64Encode) {
    output = base64.encode(utf8.encode(output));
  }
  if (appendNewline) {
    output = '$output\n';
  }
  return output;
}

String escapePasteSpecialCharacters(String text) {
  return text
      .replaceAll('\\', r'\\')
      .replaceAll('\r', r'\r')
      .replaceAll('\n', r'\n')
      .replaceAll('\t', r'\t');
}
