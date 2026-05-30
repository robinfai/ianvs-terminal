import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

void main() {
  test('terminal viewport color decode tolerates malformed hex', () {
    expect(terminalViewportColorFromHex(null), isNull);
    expect(terminalViewportColorFromHex(''), isNull);
    expect(terminalViewportColorFromHex('  '), isNull);

    expect(
      terminalViewportColorFromHex('112233')?.toARGB32(),
      const Color(0xFF112233).toARGB32(),
    );
    expect(
      terminalViewportColorFromHex(' #445566 ')?.toARGB32(),
      const Color(0xFF445566).toARGB32(),
    );
    expect(
      terminalViewportColorFromHex('#80112233')?.toARGB32(),
      const Color(0x80112233).toARGB32(),
    );

    for (final value in ['#123', '#1234567', '#XYZXYZ', 'not-a-color']) {
      expect(terminalViewportColorFromHex(value), isNull);
    }
  });
}
