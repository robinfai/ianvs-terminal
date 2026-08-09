import 'package:app/features/profiles/utils/hex_color_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizeHexColor standardizes valid values', () {
    expect(normalizeHexColor('ffffff'), '#FFFFFF');
    expect(normalizeHexColor('#abcdef'), '#ABCDEF');
    expect(normalizeHexColor(''), '');
  });

  test('isValidOptionalHexColor accepts empty and six-digit hex only', () {
    expect(isValidOptionalHexColor(''), isTrue);
    expect(isValidOptionalHexColor('#112233'), isTrue);
    expect(isValidOptionalHexColor('112233'), isTrue);
    expect(isValidOptionalHexColor('#FFF'), isFalse);
    expect(isValidOptionalHexColor('#FFFFFG'), isFalse);
  });

  test('parseOptionalHexColor converts normalized values to colors', () {
    expect(parseOptionalHexColor(''), isNull);
    expect(
      parseOptionalHexColor('112233')?.toARGB32(),
      const Color(0xFF112233).toARGB32(),
    );
  });

  test('hex and hsv helpers round-trip stable colors', () {
    final hsv = hexToHsvColor('#A1B2C3');
    expect(hsvColorToHex(hsv), '#A1B2C3');
  });
}
