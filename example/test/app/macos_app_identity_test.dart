import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

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
        r'TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Ianvs Terminal Dev.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Ianvs Terminal Dev";',
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

  test('macOS native core has one CodeAsset packaging owner', () {
    final exampleRoot = _exampleRoot();
    final repositoryRoot = exampleRoot.parent;
    final projectText = File(
      '${exampleRoot.path}/macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final hookText = File(
      '${repositoryRoot.path}/packages/ianvs_pty/hook/build.dart',
    ).readAsStringSync();
    final examplePubspec = File(
      '${exampleRoot.path}/pubspec.yaml',
    ).readAsStringSync();
    final dependencyClosure = _localDependencyClosure(
      File('${exampleRoot.path}/pubspec.yaml'),
    );
    final verifierText = File(
      '${repositoryRoot.path}/tools/verify_flutter_terminal.sh',
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
    expect(runnerRelease, contains('CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO;'));
    expect(runnerRelease, contains('ENABLE_HARDENED_RUNTIME = YES;'));
    expect(
      _nativeCorePackagingViolations(
        project: projectText,
        hook: hookText,
        bundleVerifier: verifierText,
        exampleDependencyClosure: dependencyClosure,
      ),
      isEmpty,
    );

    for (final mutation in <_NativeCorePackagingFixture>[
      _NativeCorePackagingFixture(
        label: 'custom Xcode phase',
        project: '$projectText\nname = "Bundle Rust Core";',
        hook: hookText,
        bundleVerifier: verifierText,
      ),
      _NativeCorePackagingFixture(
        label: 'direct Xcode build script',
        project: '$projectText\ntools/build_core.sh',
        hook: hookText,
        bundleVerifier: verifierText,
      ),
      _NativeCorePackagingFixture(
        label: 'missing CodeAsset registration',
        project: projectText,
        hook: hookText.replaceFirst('CodeAsset(', 'Object('),
        bundleVerifier: verifierText,
      ),
      _NativeCorePackagingFixture(
        label: 'renamed bundled dylib',
        project: projectText,
        hook: hookText.replaceAll(
          'libianvs_core.dylib',
          'libianvs_core_compat.dylib',
        ),
        bundleVerifier: verifierText,
      ),
      _NativeCorePackagingFixture(
        label: 'missing bundle output assertion',
        project: projectText,
        hook: hookText,
        bundleVerifier: verifierText.replaceFirst(
          r'release_core="$release_app/Contents/Frameworks/ianvs_core.framework/ianvs_core"',
          '',
        ),
      ),
      _NativeCorePackagingFixture(
        label: 'missing bundle ABI verification',
        project: projectText,
        hook: hookText,
        bundleVerifier: verifierText.replaceFirst(
          r'python3 "$ROOT_DIR/tools/verify_native_contract.py"',
          'python3',
        ),
      ),
    ]) {
      expect(
        _nativeCorePackagingViolations(
          project: mutation.project,
          hook: mutation.hook,
          bundleVerifier: mutation.bundleVerifier,
          exampleDependencyClosure: dependencyClosure,
        ),
        isNotEmpty,
        reason: mutation.label,
      );
    }

    for (final duplicateHookDependency in <String>[
      examplePubspec.replaceFirst(
        'dependencies:\n',
        'dependencies:\n'
            '  ianvs_terminal_core:\n'
            '    path: ../packages/ianvs_terminal_core\n',
      ),
      examplePubspec.replaceFirst(
        'dependencies:\n',
        'dependencies:\n  ianvs_terminal_core: ^0.1.0\n',
      ),
      examplePubspec.replaceFirst(
        'dependencies:\n',
        'dependencies:\n'
            '  ianvs_terminal_core: '
            '{path: ../packages/ianvs_terminal_core}\n',
      ),
    ]) {
      expect(
        _nativeCorePackagingViolations(
          project: projectText,
          hook: hookText,
          bundleVerifier: verifierText,
          exampleDependencyClosure: _localDependencyClosure(
            File('${exampleRoot.path}/pubspec.yaml'),
            rootSource: duplicateHookDependency,
          ),
        ),
        isNotEmpty,
        reason: 'two packages must not register the same bundled dylib',
      );
    }
  });

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
      '["(]([A-Z][A-Z0-9_]*)=',
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
          '^--force .*--sign - .*--options runtime ',
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

List<String> _nativeCorePackagingViolations({
  required String project,
  required String hook,
  required String bundleVerifier,
  required Set<String> exampleDependencyClosure,
}) {
  final violations = <String>[];
  for (final forbidden in <String>[
    'Bundle Rust Core',
    'tools/build_core.sh',
    'libianvs_core.dylib',
  ]) {
    if (project.contains(forbidden)) {
      violations.add('Runner project contains $forbidden');
    }
  }
  if (!hook.contains("const _assetName = 'libianvs_core.dylib';")) {
    violations.add('ianvs_pty hook has the wrong native asset name');
  }
  if (RegExp(r'\bCodeAsset\(').allMatches(hook).length != 1) {
    violations.add('ianvs_pty hook must register exactly one CodeAsset');
  }
  if (!hook.contains('linkMode: DynamicLoadingBundled()')) {
    violations.add('ianvs_pty hook must bundle the dynamic native asset');
  }
  if (!bundleVerifier.contains(
    r'release_core="$release_app/Contents/Frameworks/ianvs_core.framework/ianvs_core"',
  )) {
    violations.add('release bundle verification does not require the core');
  }
  if (!bundleVerifier.contains(r'lipo "$release_core" -verify_arch')) {
    violations.add('release bundle verification does not inspect core slices');
  }
  if (!bundleVerifier.contains(
    r'python3 "$ROOT_DIR/tools/verify_native_contract.py"',
  )) {
    violations.add('release bundle verification does not inspect core ABI');
  }
  if (!exampleDependencyClosure.contains('ianvs_pty')) {
    violations.add('example dependency closure omits the CodeAsset owner');
  }
  if (exampleDependencyClosure.contains('ianvs_terminal_core')) {
    violations.add('example dependency closure has two native core hooks');
  }
  return violations;
}

Set<String> _localDependencyClosure(File rootPubspec, {String? rootSource}) {
  final repositoryRoot = _exampleRoot().parent;
  final workspace =
      loadYaml(File('${repositoryRoot.path}/pubspec.yaml').readAsStringSync())
          as YamlMap;
  final workspacePackages = <String, File>{};
  for (final member in (workspace['workspace'] as YamlList?) ?? const []) {
    final pubspec = File(
      '${repositoryRoot.path}/$member/pubspec.yaml',
    ).absolute;
    final document = loadYaml(pubspec.readAsStringSync()) as YamlMap;
    workspacePackages[document['name'] as String] = pubspec;
  }

  final pending = <File>[rootPubspec.absolute];
  final visited = <String>{};
  final packageNames = <String>{};
  while (pending.isNotEmpty) {
    final pubspec = pending.removeLast();
    if (!visited.add(pubspec.path)) {
      continue;
    }
    final source =
        pubspec.path == rootPubspec.absolute.path && rootSource != null
        ? rootSource
        : pubspec.readAsStringSync();
    final document = loadYaml(source) as YamlMap;
    final name = document['name'];
    if (name is String) {
      packageNames.add(name);
    }
    for (final sectionName in const <String>[
      'dependencies',
      'dev_dependencies',
      'dependency_overrides',
    ]) {
      final section = document[sectionName];
      if (section is! YamlMap) {
        continue;
      }
      for (final entry in section.entries) {
        final dependencyName = entry.key;
        if (dependencyName is! String) {
          continue;
        }
        final specification = entry.value;
        final path = specification is YamlMap ? specification['path'] : null;
        if (path is String) {
          pending.add(
            File.fromUri(
              pubspec.parent.uri.resolve('$path/pubspec.yaml'),
            ).absolute,
          );
          continue;
        }
        final workspacePubspec = workspacePackages[dependencyName];
        if (workspacePubspec != null) {
          pending.add(workspacePubspec);
        }
      }
    }
  }
  return packageNames;
}

final class _NativeCorePackagingFixture {
  const _NativeCorePackagingFixture({
    required this.label,
    required this.project,
    required this.hook,
    required this.bundleVerifier,
  });

  final String label;
  final String project;
  final String hook;
  final String bundleVerifier;
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
      ..writeAsStringSync(r'''
#!/usr/bin/env bash
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
