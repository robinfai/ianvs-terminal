import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS project metadata tracks the Ianvs Terminal app identity', () {
    final appInfo = File('macos/Runner/Configs/AppInfo.xcconfig');
    final project = File('macos/Runner.xcodeproj/project.pbxproj');
    final scheme = File(
      'macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme',
    );

    final appInfoText = appInfo.readAsStringSync();
    expect(appInfoText, contains('PRODUCT_NAME = Ianvs Terminal'));
    expect(
      appInfoText,
      contains('PRODUCT_BUNDLE_IDENTIFIER = dev.ianvs.terminal'),
    );
    expect(appInfoText, contains('Ianvs Terminal contributors'));
    expect(appInfoText, isNot(contains('com.example')));

    final projectText = project.readAsStringSync();
    expect(projectText, contains('/* Ianvs Terminal.app */'));
    expect(
      projectText,
      contains(
        r'TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Ianvs Terminal.app/'
        r'$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Ianvs Terminal";',
      ),
    );
    expect(
      projectText,
      contains('PRODUCT_BUNDLE_IDENTIFIER = dev.ianvs.terminal.RunnerTests;'),
    );
    expect(projectText, isNot(contains('/* app.app */')));
    expect(projectText, isNot(contains('com.example.app')));

    final schemeText = scheme.readAsStringSync();
    expect(schemeText, contains('BuildableName = "Ianvs Terminal.app"'));
    expect(schemeText, isNot(contains('BuildableName = "app.app"')));
  });
}
