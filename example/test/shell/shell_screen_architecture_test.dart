import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shell_screen.dart keeps only the screen coordinator', () {
    const rootPath = 'example/lib/features/shell/shell_screen.dart';
    const packagePath = 'lib/features/shell/shell_screen.dart';
    final shellScreen = File(
      File(rootPath).existsSync() ? rootPath : packagePath,
    );
    final lineCount = shellScreen.readAsLinesSync().length;

    expect(lineCount, lessThanOrEqualTo(7000));
  });
}
