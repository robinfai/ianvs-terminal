import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS entitlements keep App Sandbox disabled for local PTY spawn', () {
    const entitlementPaths = <String>[
      'macos/Runner/DebugProfile.entitlements',
      'macos/Runner/Release.entitlements',
    ];

    for (final path in entitlementPaths) {
      final contents = File(path).readAsStringSync();

      expect(
        contents,
        isNot(contains('com.apple.security.app-sandbox')),
        reason: '$path must allow flutterm native core to spawn a local shell.',
      );
    }
  });
}
