import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Apple team detection reads the certificate subject OU', () async {
    final directory = Directory.systemTemp.createTempSync(
      'ianvs-apple-team-detector-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final bin = Directory('${directory.path}/bin')..createSync();
    final uname = File('${bin.path}/uname')
      ..writeAsStringSync('#!/usr/bin/env bash\necho Darwin\n');
    final security = File('${bin.path}/security')
      ..writeAsStringSync(r'''
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "find-identity" ]]; then
  echo '  1) AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "Apple Development: developer@example.test (WRONG12345)"'
elif [[ "$1" == "find-certificate" ]]; then
  echo 'fixture-certificate'
else
  exit 64
fi
''');
    final openssl = File('${bin.path}/openssl')
      ..writeAsStringSync('''
#!/usr/bin/env bash
cat >/dev/null
echo 'subject=C=US,O=Ianvs,OU=RIGHT12345,CN=Apple Development'
''');
    final chmod = await Process.run('chmod', <String>[
      '+x',
      uname.path,
      security.path,
      openssl.path,
    ]);
    expect(chmod.exitCode, 0, reason: chmod.stderr as String?);

    final result = await Process.run(
      'bash',
      <String>['tools/detect_apple_development_team.sh'],
      environment: <String, String>{
        'PATH': '${bin.path}:${Platform.environment['PATH']}',
      },
    );

    expect(result.exitCode, 0, reason: result.stderr as String?);
    expect((result.stdout as String).trim(), 'RIGHT12345');
  });

  test('Apple app identity is unified without a committed signing team', () {
    final iosProject = File(
      'example/ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final macosProject = File(
      'example/macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final appInfo = File(
      'example/macos/Runner/Configs/AppInfo.xcconfig',
    ).readAsStringSync();
    final iosReleaseEntitlements = File(
      'example/ios/Runner/Release.entitlements',
    ).readAsStringSync();
    final iosDebugProfileEntitlements = File(
      'example/ios/Runner/DebugProfile.entitlements',
    ).readAsStringSync();
    final appleBuilder = File(
      'tools/build_signed_apple_release.sh',
    ).readAsStringSync();
    final teamDetector = File(
      'tools/detect_apple_development_team.sh',
    ).readAsStringSync();
    final macosSigner = File(
      'tools/sign_macos_with_keychain_identity.sh',
    ).readAsStringSync();
    final makefile = File('Makefile').readAsStringSync();

    expect(
      'PRODUCT_BUNDLE_IDENTIFIER = dev.ianvs.terminal;'.allMatches(iosProject),
      hasLength(3),
    );
    expect(
      iosProject,
      isNot(contains('PRODUCT_BUNDLE_IDENTIFIER = dev.ianvs.terminal.dev;')),
    );
    expect('DEVELOPMENT_TEAM = "";'.allMatches(iosProject), hasLength(3));
    expect(
      RegExp('DEVELOPMENT_TEAM = (?!"";)[A-Z0-9]+;').hasMatch(iosProject),
      isFalse,
    );
    expect(appInfo, contains('PRODUCT_BUNDLE_IDENTIFIER = dev.ianvs.terminal'));
    expect(macosProject, isNot(contains('DEVELOPMENT_TEAM =')));
    expect(macosProject, isNot(contains('dev.ianvs.terminal.dev')));
    for (final entitlements in <String>[
      iosReleaseEntitlements,
      iosDebugProfileEntitlements,
    ]) {
      expect(
        entitlements,
        contains(r'$(AppIdentifierPrefix)dev.ianvs.terminal'),
      );
      expect(
        entitlements,
        isNot(contains(r'$(PRODUCT_BUNDLE_IDENTIFIER)')),
        reason:
            'Development installs must retain the production Keychain group.',
      );
    }

    expect(appleBuilder, contains('XCODE_XCCONFIG_FILE='));
    expect(appleBuilder, contains(r'DEVELOPMENT_TEAM = $TEAM'));
    expect(
      appleBuilder,
      contains(r'PRODUCT_BUNDLE_IDENTIFIER = $IOS_BUNDLE_ID'),
    );
    expect(makefile, contains('IPHONE_BUNDLE_ID ?= dev.ianvs.terminal.dev'));
    expect(makefile, contains('MACOS_BUNDLE_ID ?= dev.ianvs.terminal.dev'));
    expect(makefile, contains(r'IANVS_IOS_BUNDLE_ID="$(IPHONE_BUNDLE_ID)"'));
    expect(makefile, contains(r'IANVS_MACOS_BUNDLE_ID="$(MACOS_BUNDLE_ID)"'));
    expect(appleBuilder, contains('/usr/bin/env -i'));
    expect(appleBuilder, contains('-allowProvisioningUpdates'));
    expect(appleBuilder, contains('embedded.provisionprofile'));
    expect(
      appleBuilder,
      contains(r'${SIGNING_TEMP_BASE%/}/ianvs-macos-signing.XXXXXX'),
      reason: 'xcconfig paths must not contain //, which starts a comment.',
    );
    expect(
      appleBuilder,
      contains(r'$TEAM.$PRODUCTION_IDENTIFIER'),
      reason: 'macOS and iOS development installs share the production group.',
    );
    expect(teamDetector, contains('security find-identity'));
    expect(teamDetector, contains('security find-certificate'));
    expect(teamDetector, contains('openssl x509'));
    expect(teamDetector, contains('OU='));
    expect(teamDetector, isNot(matches(RegExp('[A-Z0-9]{10}'))));
    expect(macosSigner, contains('security find-identity'));
    expect(macosSigner, contains(r'$team.$EXPECTED_IDENTIFIER'));
  });

  test('iOS verification passes only an explicit environment allowlist', () {
    final source = File('tools/verify_ios_simulator.sh').readAsStringSync();
    final block = RegExp(
      r'apple_build_env=\((.*?)\n\)',
      dotAll: true,
    ).firstMatch(source);
    expect(block, isNotNull);

    final assignments = RegExp(
      '"([A-Z][A-Z0-9_]*)=',
    ).allMatches(block!.group(1)!).map((match) => match.group(1)).toSet();
    expect(assignments, {'HOME', 'PATH', 'TMPDIR', 'LANG', 'LC_ALL'});
    expect(
      RegExp(
        r'apple_build_env\+\=\("(DEVELOPER_DIR|TOOLCHAINS)=\$\1"\)',
      ).allMatches(source).length,
      2,
    );

    for (final command in <String>[
      'flutter build ios --simulator --debug --no-codesign',
      'flutter build ios --release --no-codesign',
      'xcodebuild test',
      r'flutter test -d "$IOS_SIMULATOR_UDID"',
    ]) {
      expect(
        source,
        contains(r'"${apple_build_env[@]}" ' + command),
        reason: '$command must run under the scrubbed environment',
      );
    }
  });

  test('iOS Runner exports the exact current native ABI', () {
    final manifest =
        jsonDecode(
              File('native/core/ianvs_core_abi_v1.json').readAsStringSync(),
            )
            as Map<String, Object?>;
    final functions = manifest['functions']! as Map<String, Object?>;
    final expectedSymbols = functions.keys.map((name) => '_$name').toList()
      ..sort();
    final exportedSymbols = File(
      'native/core/ianvs_core_ios_exports.txt',
    ).readAsLinesSync()..sort();
    expect(exportedSymbols, expectedSymbols);

    final project = File(
      'example/ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    const setting =
        'EXPORTED_SYMBOLS_FILE = '
        r'"$(PROJECT_DIR)/../../native/core/ianvs_core_ios_exports.txt";';
    expect(
      setting.allMatches(project),
      hasLength(3),
      reason: 'Debug, Profile, and Release must retain the exact C ABI.',
    );
  });

  test('iOS Runner links the Debug app without an Xcode debug dylib', () {
    final project = File(
      'example/ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final runnerDebug = RegExp(
      r'97C147061CF9000F007C117D /\* Debug \*/ = \{(.*?)\n\s*\};',
      dotAll: true,
    ).firstMatch(project)?.group(1);

    expect(runnerDebug, isNotNull);
    expect(
      runnerDebug,
      contains('ENABLE_DEBUG_DYLIB = NO;'),
      reason:
          'The force-loaded Rust core must be linked into Runner itself. '
          "Xcode's debug-dylib launcher otherwise aborts before Flutter starts.",
    );
  });

  test('iOS ABI verification ignores the Xcode debug stub executable', () {
    final source = File('tools/verify_ios_simulator.sh').readAsStringSync();

    expect(source, contains(r'link_images=("$executable")'));
    expect(
      source,
      contains(r'link_images=("$ios_app/$executable_name.debug.dylib")'),
    );
  });

  test('iOS Rust build separates host and target Apple SDK roots', () {
    final source = File('tools/build_core_ios.sh').readAsStringSync();

    expect(source, contains(r'IOS_SDKROOT="${SDKROOT:-'));
    expect(
      source,
      contains(r'MACOS_SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"'),
    );
    expect(source, contains('RUSTFLAGS_ENV_NAME="CARGO_TARGET_'));
    expect(source, contains(r'link-arg=$IOS_SDKROOT'));
    expect(source, contains(r'export SDKROOT="$MACOS_SDKROOT"'));
    expect(
      source.indexOf(r'export SDKROOT="$MACOS_SDKROOT"'),
      lessThan(source.indexOf(r'cargo "${CARGO_ARGS[@]}"')),
    );
  });

  test('iOS Rust build merges every simulator architecture from Xcode', () {
    final source = File('tools/build_core_ios.sh').readAsStringSync();

    expect(source, contains(r'requested_archs="${ARCHS:-$(uname -m)}"'));
    expect(source, contains(r'for arch in $requested_archs; do'));
    expect(source, contains('aarch64-apple-ios-sim'));
    expect(source, contains('x86_64-apple-ios'));
    expect(
      source,
      contains(
        r'xcrun lipo -create "${slices[@]}" -output '
        r'"$DEST_DIR/libianvs_core.a"',
      ),
    );
  });

  test('iOS Rust archive staging stays outside the installed products', () {
    final script = File('tools/build_core_ios.sh').readAsStringSync();
    final project = File(
      'example/ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    expect(script, contains(r'DEST_DIR="${DERIVED_FILE_DIR:?}/ianvs_core"'));
    expect(script, isNot(contains(r'DEST_DIR="${TARGET_BUILD_DIR:?}')));
    expect(
      r'$(DERIVED_FILE_DIR)/ianvs_core/libianvs_core.a'.allMatches(project),
      hasLength(4),
      reason: 'The script output and all linker configurations must agree.',
    );
    expect(
      project,
      isNot(contains(r'$(TARGET_BUILD_DIR)/ianvs_core/libianvs_core.a')),
    );
  });

  test('iOS release gate builds the App Store device architecture', () {
    final source = File('tools/verify_ios_simulator.sh').readAsStringSync();
    final workflow = File('.github/workflows/verify.yml').readAsStringSync();

    expect(source, contains('build/ios/iphoneos'));
    expect(
      source,
      contains(r'verify_ios_native_exports "$IOS_RELEASE_APP" arm64'),
    );
    expect(
      workflow,
      matches(RegExp(r'^\s+aarch64-apple-ios\s+\\$', multiLine: true)),
    );
  });
}
