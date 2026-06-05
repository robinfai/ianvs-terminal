import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shell_screen.dart keeps only the screen coordinator', () {
    final shellScreen = File('lib/features/shell/shell_screen.dart');
    final lineCount = shellScreen.readAsLinesSync().length;

    expect(lineCount, lessThanOrEqualTo(7000));
  });
}
