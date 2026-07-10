import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void ensureMacosIntegrationTestFramesEnabled(
  TestWidgetsFlutterBinding binding,
) {
  // The macOS integration-test runner can attach while LaunchServices still
  // reports the app as hidden. Hidden bindings disable frames, so pumpWidget
  // would otherwise wait forever for a frame that cannot be scheduled.
  if (binding.lifecycleState == AppLifecycleState.hidden) {
    binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
  expect(
    binding.framesEnabled,
    isTrue,
    reason:
        'The macOS integration-test binding must be able to schedule frames; '
        'lifecycle=${binding.lifecycleState}.',
  );
}
