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
}
