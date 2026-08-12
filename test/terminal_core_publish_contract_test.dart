import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('standalone publish gate rejects every pub ignore control file', () {
    final source = File(
      'tools/verify_terminal_core_publish.dart',
    ).readAsStringSync();

    expect(_publishIgnoreViolations(source), isEmpty);
    for (final ignoredControl in const <String>['.gitignore', '.pubignore']) {
      expect(
        _publishIgnoreViolations(
          source.replaceAll("'$ignoredControl'", "'archive-control-disabled'"),
        ),
        isNotEmpty,
        reason: '$ignoredControl can remove required native archive inputs',
      );
    }
  });
}

List<String> _publishIgnoreViolations(String source) {
  final violations = <String>[];
  for (final required in const <String>[
    "'native/core/ianvs_core_abi_v1.json'",
    "'hook/build.dart'",
    "'.gitignore'",
    "'.pubignore'",
    "'pub', 'publish', '--dry-run'",
    'Package has 0 warnings.',
  ]) {
    if (!source.contains(required)) {
      violations.add('publish verifier omits $required');
    }
  }
  return violations;
}
