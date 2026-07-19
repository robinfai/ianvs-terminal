import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS main window is visible at launch', () {
    final mainMenu = File(
      '${_exampleRoot().path}/macos/Runner/Base.lproj/MainMenu.xib',
    );

    expect(mainMenu.existsSync(), isTrue);

    final xib = mainMenu.readAsStringSync();
    expect(xib, contains('title="Settings…" keyEquivalent=","'));
    expect(xib, contains('action selector="showSettings:"'));
    expect(
      xib,
      contains(
        '<window title="APP_NAME" '
        'allowsToolTipsWhenApplicationIsInactive="NO" '
        'autorecalculatesKeyViewLoop="NO" '
        'visibleAtLaunch="YES"',
      ),
    );
  });
}

Directory _exampleRoot() {
  final current = Directory.current;
  if (Directory('${current.path}/macos').existsSync()) {
    return current;
  }
  final nestedExample = Directory('${current.path}/example');
  if (Directory('${nestedExample.path}/macos').existsSync()) {
    return nestedExample;
  }
  return current;
}
