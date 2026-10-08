import 'package:app/ui/foundation/phone_text_scale_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

void main() {
  for (final scenario in [
    (
      name: 'portrait phone',
      display: const Size(390, 844),
      window: const Size(390, 844),
      platform: TargetPlatform.iOS,
      expected: 1.0,
    ),
    (
      name: 'landscape phone',
      display: const Size(844, 390),
      window: const Size(844, 390),
      platform: TargetPlatform.iOS,
      expected: 1.0,
    ),
    (
      name: 'narrow iPad window',
      display: const Size(1024, 1366),
      window: const Size(375, 1024),
      platform: TargetPlatform.iOS,
      expected: 2.0,
    ),
    (
      name: 'narrow macOS window',
      display: const Size(1280, 900),
      window: const Size(390, 844),
      platform: TargetPlatform.macOS,
      expected: 2.0,
    ),
  ]) {
    testWidgets('${scenario.name} preserves the device text policy', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.display.size = scenario.display;
      tester.view.physicalSize = scenario.window;
      addTearDown(tester.view.reset);
      addTearDown(tester.view.display.reset);
      double? scale;
      await tester.pumpApp(
        PhoneTextScalePolicy(
          child: Builder(
            builder: (context) {
              scale = MediaQuery.textScalerOf(context).scale(16) / 16;
              return const Text('Fixed phone UI, scalable iPad / desktop');
            },
          ),
        ),
        platform: scenario.platform,
        textScale: 2,
      );
      expect(scale, scenario.expected);
      expect(tester.takeException(), isNull);
    });
  }
}
