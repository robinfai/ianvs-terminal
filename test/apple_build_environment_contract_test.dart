import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
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

  test('iOS Debug keeps the native ABI in the executable', () {
    final project = File(
      'example/ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    final runnerDebug = RegExp(
      r'97C147061CF9000F007C117D /\* Debug \*/ = \{(.*?)\n\t\t\};',
      dotAll: true,
    ).firstMatch(project);
    expect(runnerDebug, isNotNull);
    expect(
      runnerDebug!.group(1),
      contains('ENABLE_DEBUG_DYLIB = NO;'),
      reason: 'Xcode debug dylibs require an extra exported entry point.',
    );
  });

  test('iOS ABI verification ignores the Xcode debug stub executable', () {
    final source = File('tools/verify_ios_simulator.sh').readAsStringSync();

    expect(source, contains(r'link_images=("$executable")'));
    expect(
      source,
      contains(
        r'link_images=("$ios_app/$executable_name.debug.dylib")',
      ),
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
      r'$(DERIVED_FILE_DIR)/ianvs_core/libianvs_core.a'
          .allMatches(project),
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
