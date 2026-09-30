import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void ensureMacosIntegrationTestFramesEnabled(
  TestWidgetsFlutterBinding binding,
) => ensureDesktopIntegrationTestFramesEnabled(binding);

void ensureDesktopIntegrationTestFramesEnabled(
  TestWidgetsFlutterBinding binding,
) {
  // A desktop integration-test runner can attach while the window system still
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
        'The desktop integration-test binding must be able to schedule frames; '
        'lifecycle=${binding.lifecycleState}.',
  );
}
