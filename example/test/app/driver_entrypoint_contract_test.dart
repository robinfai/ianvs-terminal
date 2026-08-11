import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy test driver composes an explicit PTY backend', () {
    final source = File('test_driver/main.dart').readAsStringSync();

    expect(source, contains('ptySessionBackend:'));
    expect(source, contains('loadDefaultPtySessionBackend()'));
    expect(
      source,
      isNot(contains('enableReferenceDemoMode: true')),
      reason: 'The integration driver exercises the production PTY path.',
    );
  });
}
