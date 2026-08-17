import 'dart:io';

import 'package:test/test.dart';

void main() {
  late String makefile;
  late String installer;

  setUpAll(() {
    makefile = File('Makefile').readAsStringSync();
    installer = File('tools/install_ios_simulator.sh').readAsStringSync();
  });

  test(
    'install-iphone falls back to the simulator only when no phone exists',
    () {
      expect(makefile, contains('select_physical_ios_device.dart" --optional'));
      expect(makefile, contains('install-iphone-physical'));
      expect(makefile, contains('install-iphone-simulator'));
      expect(makefile, contains(r'IPHONE_DEVICE="$$device_id"'));
    },
  );

  test('simulator installer builds, installs, and launches the app', () {
    expect(installer, startsWith('#!/usr/bin/env bash\nset -euo pipefail'));
    expect(installer, contains('select_simulator_line Booted'));
    expect(installer, contains('select_simulator_line Shutdown'));
    expect(installer, contains(r'xcrun simctl boot "$IOS_SIMULATOR_UDID"'));
    expect(
      installer,
      contains(r'xcrun simctl bootstatus "$IOS_SIMULATOR_UDID" -b'),
    );
    expect(installer, contains('--simulator --debug --no-codesign'));
    expect(installer, contains('-t lib/simulator_main.dart'));
    expect(installer, contains('xcrun simctl install'));
    expect(installer, contains('xcrun simctl launch'));
    expect(installer, contains('SIMCTL_CHILD_IANVS_SIMULATOR_CREDENTIALS_URL'));
    expect(installer, contains('serve_acceptance_credentials.py'));
    expect(
      installer,
      isNot(contains('SIMCTL_CHILD_IANVS_SIMULATOR_MASTER_KEY')),
    );
    expect(
      installer,
      isNot(contains('SIMCTL_CHILD_IANVS_SIMULATOR_REMOTE_PASSWORD')),
    );
    expect(installer, contains("stat -f '%Lp'"));
    expect(installer, isNot(contains('simctl shutdown')));
  });

  test('simulator build runs with an allowlisted environment', () {
    expect(installer, contains('/usr/bin/env -i'));
    expect(installer, contains(r'"HOME=$HOME"'));
    expect(installer, contains(r'"PATH=$PATH"'));
    expect(installer, contains(r'"${apple_build_env[@]}" "$FLUTTER_BIN"'));
  });

  test('native launch bridge is compiled only for CoreSimulator', () {
    final appDelegate = File(
      'example/ios/Runner/AppDelegate.swift',
    ).readAsStringSync();
    expect(appDelegate, contains('#if targetEnvironment(simulator)'));
    expect(appDelegate, contains('ProcessInfo.processInfo.environment'));
    expect(appDelegate, contains('dev.ianvs.terminal/simulator-acceptance'));
    expect(appDelegate, isNot(contains('print(')));
  });
}
