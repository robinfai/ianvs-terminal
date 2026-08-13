import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('cross-platform sync acceptance is ordered and secret-safe', () {
    final script = File(
      'tools/verify_remote_data_api_cross_platform.sh',
    ).readAsStringSync();

    expect(script, contains('set -euo pipefail'));
    expect(script, contains('read -r -s -p "Acceptance password: "'));
    expect(
      script,
      contains('read -r -s -p "Acceptance data encryption key: "'),
    );
    expect(
      script,
      contains(
        r'chmod 600 "$defines_file" "$credentials_file" '
        r'"$broker_ready_file"',
      ),
    );
    expect(script, contains(r'--dart-define-from-file="$defines_file"'));
    expect(script, contains('IANVS_ACCEPTANCE_CREDENTIALS_URL'));
    expect(script, isNot(contains('"IANVS_ACCEPTANCE_REMOTE_PASSWORD": os.')));
    expect(script, contains('/usr/bin/env -i'));
    expect(script, contains(r'"${test_env[@]}" flutter test'));
    expect(script, contains('trap cleanup EXIT INT TERM'));
    expect(script, contains('for _ in {1..600}; do'));
    expect(
      script,
      contains(
        'The acceptance credential broker did not become ready within '
        '30 seconds.',
      ),
    );

    final macWrite = script.indexOf('run_phase macos macos-write');
    final iosGate = script.indexOf(r'"$IOS_GATE_TARGET" --reporter compact');
    final iosReadWrite = script.indexOf(
      r'run_phase "$IOS_SIMULATOR_UDID" ios-read-write',
    );
    final macRead = script.indexOf('run_phase macos macos-read-cleanup');
    expect(iosGate, greaterThanOrEqualTo(0));
    expect(macWrite, greaterThan(iosGate));
    expect(iosReadWrite, greaterThan(macWrite));
    expect(macRead, greaterThan(iosReadWrite));
  });
}
