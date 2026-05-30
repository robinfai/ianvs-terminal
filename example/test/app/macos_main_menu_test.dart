import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS main window is visible at launch', () {
    final mainMenu = File('macos/Runner/Base.lproj/MainMenu.xib');

    expect(mainMenu.existsSync(), isTrue);

    final xib = mainMenu.readAsStringSync();
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
