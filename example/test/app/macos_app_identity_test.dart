import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS project metadata tracks the Ianvs Terminal app identity', () {
    final exampleRoot = _exampleRoot();
    final appInfo = File(
      '${exampleRoot.path}/macos/Runner/Configs/AppInfo.xcconfig',
    );
    final project = File(
      '${exampleRoot.path}/macos/Runner.xcodeproj/project.pbxproj',
    );
    final scheme = File(
      '${exampleRoot.path}/macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme',
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
    expect(projectText, contains('/* Ianvs Terminal Dev.app */'));
    expect(
      projectText,
      contains(
        r'TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Ianvs Terminal Dev.app/'
        r'$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Ianvs Terminal Dev";',
      ),
    );
    expect(
      projectText,
      contains('PRODUCT_BUNDLE_IDENTIFIER = dev.ianvs.terminal.RunnerTests;'),
    );
    expect(projectText, isNot(contains('/* app.app */')));
    expect(projectText, isNot(contains('com.example.app')));

    final schemeText = scheme.readAsStringSync();
    expect(schemeText, contains('BuildableName = "Ianvs Terminal Dev.app"'));
    expect(schemeText, isNot(contains('BuildableName = "app.app"')));
  });

  test('example package metadata describes the Ianvs Terminal app', () {
    final exampleRoot = _exampleRoot();
    final pubspecText = File(
      '${exampleRoot.path}/pubspec.yaml',
    ).readAsStringSync();

    expect(pubspecText, contains('description:'));
    expect(pubspecText, contains('Ianvs Terminal'));
    expect(pubspecText, isNot(contains('A new Flutter project.')));
  });

  test(
    'macOS uses Swift Package plugins and an ad-hoc-signable Keychain setup',
    () {
      final exampleRoot = _exampleRoot();
      final macosRoot = Directory('${exampleRoot.path}/macos');
      final projectText = File(
        '${macosRoot.path}/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      final debugConfig = File(
        '${macosRoot.path}/Flutter/Flutter-Debug.xcconfig',
      ).readAsStringSync();
      final releaseConfig = File(
        '${macosRoot.path}/Flutter/Flutter-Release.xcconfig',
      ).readAsStringSync();
      final debugEntitlements = File(
        '${macosRoot.path}/Runner/DebugProfile.entitlements',
      ).readAsStringSync();
      final releaseEntitlements = File(
        '${macosRoot.path}/Runner/Release.entitlements',
      ).readAsStringSync();
      final secretCipher = File(
        '${exampleRoot.path}/lib/features/profiles/profile_secret_cipher.dart',
      ).readAsStringSync();

      expect(File('${macosRoot.path}/Podfile').existsSync(), isFalse);
      expect(projectText, contains('FlutterGeneratedPluginSwiftPackage'));
      expect(projectText, isNot(contains('Pods-Runner')));
      expect(debugConfig, isNot(contains('Pods/Target Support Files')));
      expect(releaseConfig, isNot(contains('Pods/Target Support Files')));
      expect(debugEntitlements, isNot(contains('keychain-access-groups')));
      expect(releaseEntitlements, isNot(contains('keychain-access-groups')));
      expect(
        secretCipher,
        contains('MacOsOptions(usesDataProtectionKeychain: false)'),
      );
    },
  );

  test(
    'macOS release build keeps core dylib signing and hardening explicit',
    () {
      final exampleRoot = _exampleRoot();
      final projectText = File(
        '${exampleRoot.path}/macos/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      final runnerRelease = RegExp(
        r'33CC10FD2044A3C60003C045 /\* Release \*/ = \{(.*?)\n\s*\};',
        dotAll: true,
      ).firstMatch(projectText)?.group(1);

      expect(runnerRelease, isNotNull);
      expect(
        runnerRelease,
        contains('CODE_SIGN_ENTITLEMENTS = Runner/Release.entitlements;'),
      );
      expect(
        runnerRelease,
        contains('CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO;'),
      );
      expect(runnerRelease, contains('ENABLE_HARDENED_RUNTIME = YES;'));
      expect(projectText, contains('libianvs_core.dylib'));
      expect(projectText, contains('codesign --force --sign'));
    },
  );

  test('macOS native test gate does not inherit credential variables', () {
    final repositoryRoot = _exampleRoot().parent;
    final verifier = File(
      '${repositoryRoot.path}/tools/verify_flutter_terminal.sh',
    ).readAsStringSync();

    expect(verifier, contains('/usr/bin/env -i'));
    final allowlistStart = verifier.indexOf('xcode_test_env=(');
    final allowlistEnd = verifier.indexOf(
      r'"${xcode_test_env[@]}" xcodebuild test',
    );
    expect(allowlistStart, greaterThanOrEqualTo(0));
    expect(allowlistEnd, greaterThan(allowlistStart));
    final allowlistBlock = verifier.substring(allowlistStart, allowlistEnd);
    final assignedNames = RegExp(
      r'["(]([A-Z][A-Z0-9_]*)=',
    ).allMatches(allowlistBlock).map((match) => match.group(1)).toSet();
    expect(
      assignedNames,
      equals({
        'HOME',
        'PATH',
        'TMPDIR',
        'LANG',
        'LC_ALL',
        'DEVELOPER_DIR',
        'TOOLCHAINS',
      }),
    );
  });

  test('macOS release entitlement inspection uses a cleaned random file', () {
    final repositoryRoot = _exampleRoot().parent;
    final verifier = File(
      '${repositoryRoot.path}/tools/verify_flutter_terminal.sh',
    ).readAsStringSync();

    expect(verifier, contains('ianvs-release-entitlements.plist.XXXXXX'));
    expect(
      verifier,
      isNot(contains('ianvs-release-entitlements.XXXXXX.plist')),
    );
    expect(verifier, contains('trap cleanup_release_entitlements EXIT'));
    expect(verifier, contains(r'plutil -lint "$release_entitlements"'));
    expect(verifier, contains('must have an empty entitlement dictionary'));
    expect(verifier, contains('must enable hardened runtime'));
    expect(
      RegExp(
        RegExp.escape(r'verify_release_bundle "$release_app"'),
      ).allMatches(verifier),
      hasLength(2),
    );
  });

  test(
    'local macOS release signing preserves hardening without weakening distribution entitlements',
    () {
      final exampleRoot = _exampleRoot();
      final repositoryRoot = exampleRoot.parent;
      final localEntitlements = File(
        '${exampleRoot.path}/macos/Runner/LocalRelease.entitlements',
      ).readAsStringSync();
      final releaseEntitlements = File(
        '${exampleRoot.path}/macos/Runner/Release.entitlements',
      ).readAsStringSync();
      final signer = File(
        '${repositoryRoot.path}/tools/sign_local_macos_release.sh',
      ).readAsStringSync();
      final refreshGate = File(
        '${repositoryRoot.path}/tools/run_release_real_pty_refresh_gate.sh',
      ).readAsStringSync();

      expect(
        localEntitlements,
        contains('com.apple.security.cs.disable-library-validation'),
      );
      expect(
        releaseEntitlements,
        isNot(contains('com.apple.security.cs.disable-library-validation')),
      );
      expect(signer, contains('--options runtime'));
      expect(signer, contains('codesign --verify --deep --strict'));
      expect(signer, contains('flags=0x'));
      expect(signer, contains('(adhoc,runtime)'));
      expect(
        refreshGate,
        contains(r'tools/sign_local_macos_release.sh" "$APP_PATH'),
      );
      expect(
        refreshGate,
        isNot(contains(r'codesign --force --deep --sign - "$APP_PATH"')),
      );
    },
  );

  test(
    'local macOS release signer preserves certificates and rejects entitlement drift',
    () async {
      const validEntitlements = '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>com.apple.security.cs.disable-library-validation</key><true/>
</dict></plist>
''';
      final adHoc = await _runSignerFixture(
        signature: 'adhoc',
        entitlements: validEntitlements,
      );
      expect(adHoc.result.exitCode, 0, reason: adHoc.result.stderr as String?);
      expect(
        RegExp(
          r'^--force .*--sign - .*--options runtime ',
          multiLine: true,
        ).allMatches(adHoc.codesignLog),
        hasLength(1),
      );

      final certificate = await _runSignerFixture(
        signature: 'certificate',
        entitlements: validEntitlements,
      );
      expect(
        certificate.result.exitCode,
        0,
        reason: certificate.result.stderr as String?,
      );
      expect(certificate.codesignLog, isNot(contains('--force')));
      expect(certificate.codesignLog, contains('--verify --deep --strict'));

      const falseEntitlements = '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>com.apple.security.cs.disable-library-validation</key><false/>
</dict></plist>
''';
      final falseValue = await _runSignerFixture(
        signature: 'adhoc',
        entitlements: falseEntitlements,
      );
      expect(falseValue.result.exitCode, isNonZero);

      const integerEntitlements = '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>com.apple.security.cs.disable-library-validation</key><integer>1</integer>
</dict></plist>
''';
      final integerValue = await _runSignerFixture(
        signature: 'adhoc',
        entitlements: integerEntitlements,
      );
      expect(integerValue.result.exitCode, isNonZero);

      const stringEntitlements = '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>com.apple.security.cs.disable-library-validation</key><string>true</string>
</dict></plist>
''';
      final stringValue = await _runSignerFixture(
        signature: 'adhoc',
        entitlements: stringEntitlements,
      );
      expect(stringValue.result.exitCode, isNonZero);

      const extraEntitlements = '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>com.apple.security.cs.disable-library-validation</key><true/>
<key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
</dict></plist>
''';
      final extraValue = await _runSignerFixture(
        signature: 'adhoc',
        entitlements: extraEntitlements,
      );
      expect(extraValue.result.exitCode, isNonZero);

      const missingEntitlements = '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict></dict></plist>
''';
      final missingValue = await _runSignerFixture(
        signature: 'adhoc',
        entitlements: missingEntitlements,
      );
      expect(missingValue.result.exitCode, isNonZero);

      final missingRuntime = await _runSignerFixture(
        signature: 'adhoc',
        entitlements: validEntitlements,
        runtimeFlag: false,
      );
      expect(missingRuntime.result.exitCode, isNonZero);

      final failedVerify = await _runSignerFixture(
        signature: 'adhoc',
        entitlements: validEntitlements,
        verifySucceeds: false,
      );
      expect(failedVerify.result.exitCode, isNonZero);
    },
  );
}

final class _SignerFixtureResult {
  const _SignerFixtureResult({required this.result, required this.codesignLog});

  final ProcessResult result;
  final String codesignLog;
}

Future<_SignerFixtureResult> _runSignerFixture({
  required String signature,
  required String entitlements,
  bool runtimeFlag = true,
  bool verifySucceeds = true,
}) async {
  final repositoryRoot = _exampleRoot().parent;
  final directory = Directory.systemTemp.createTempSync(
    'ianvs-local-release-signer-',
  );
  try {
    final app = Directory('${directory.path}/Fixture.app')..createSync();
    final bin = Directory('${directory.path}/bin')..createSync();
    final codesignLog = File('${directory.path}/codesign.log')..createSync();
    final finalEntitlements = File('${directory.path}/entitlements.plist')
      ..writeAsStringSync(entitlements);
    final uname = File('${bin.path}/uname')
      ..writeAsStringSync('#!/usr/bin/env bash\necho Darwin\n');
    final codesign = File('${bin.path}/codesign')
      ..writeAsStringSync(r'''#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_CODESIGN_LOG"
if [[ "$1" == "-d" && "$2" == "--verbose=4" ]]; then
  if [[ "$FAKE_SIGNATURE" == "adhoc" ]]; then
    if [[ "$FAKE_RUNTIME_FLAG" == "true" ]]; then
      echo 'CodeDirectory flags=0x10002(adhoc,runtime)' >&2
    else
      echo 'CodeDirectory flags=0x2(adhoc)' >&2
    fi
    echo 'Signature=adhoc' >&2
  else
    if [[ "$FAKE_RUNTIME_FLAG" == "true" ]]; then
      echo 'CodeDirectory flags=0x10000(runtime)' >&2
    else
      echo 'CodeDirectory flags=0x0(none)' >&2
    fi
    echo 'Signature=Developer ID Application' >&2
    echo 'TeamIdentifier=IANVSFIXTURE' >&2
  fi
elif [[ "$1" == "-d" && "$2" == "--entitlements" ]]; then
  cat "$FAKE_ENTITLEMENTS_FILE"
elif [[ "$1" == "--verify" && "$FAKE_VERIFY_SUCCEEDS" != "true" ]]; then
  exit 42
fi
''');
    final chmod = await Process.run('chmod', <String>[
      '+x',
      uname.path,
      codesign.path,
    ]);
    expect(chmod.exitCode, 0, reason: chmod.stderr as String?);

    final parentPath = Platform.environment['PATH'] ?? '/usr/bin:/bin';
    final result = await Process.run(
      'bash',
      <String>[
        '${repositoryRoot.path}/tools/sign_local_macos_release.sh',
        app.path,
      ],
      environment: <String, String>{
        'PATH': '${bin.path}:$parentPath',
        'FAKE_SIGNATURE': signature,
        'FAKE_RUNTIME_FLAG': runtimeFlag.toString(),
        'FAKE_VERIFY_SUCCEEDS': verifySucceeds.toString(),
        'FAKE_CODESIGN_LOG': codesignLog.path,
        'FAKE_ENTITLEMENTS_FILE': finalEntitlements.path,
      },
    );
    return _SignerFixtureResult(
      result: result,
      codesignLog: codesignLog.readAsStringSync(),
    );
  } finally {
    directory.deleteSync(recursive: true);
  }
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
