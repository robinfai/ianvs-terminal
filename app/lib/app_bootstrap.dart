import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/sessions/session_controller.dart';
import 'features/shell/reference_demo.dart';
import 'features/shell/shell_screen.dart';

Widget buildFluttermRoot({
  bool enableSessionPolling = true,
  bool enableShellAnimations = true,
  bool enableDriverWarmUpRefresh = false,
  bool enableReferenceDemoMode = false,
  Map<String, String> sessionEnvironmentOverrides = const <String, String>{},
}) {
  return ProviderScope(
    overrides: [
      sessionPollingEnabledProvider.overrideWithValue(enableSessionPolling),
      driverWarmUpRefreshEnabledProvider.overrideWithValue(
        enableDriverWarmUpRefresh,
      ),
      sessionEnvironmentOverridesProvider.overrideWithValue(
        sessionEnvironmentOverrides,
      ),
      referenceDemoModeProvider.overrideWithValue(enableReferenceDemoMode),
      shellAnimationsEnabledProvider.overrideWithValue(enableShellAnimations),
    ],
    child: const FluttermApp(),
  );
}

void runFluttermApp({
  bool enableSessionPolling = true,
  bool enableShellAnimations = true,
  bool enableDriverWarmUpRefresh = false,
  bool enableReferenceDemoMode = false,
  Map<String, String> sessionEnvironmentOverrides = const <String, String>{},
}) {
  runApp(
    buildFluttermRoot(
      enableSessionPolling: enableSessionPolling,
      enableDriverWarmUpRefresh: enableDriverWarmUpRefresh,
      enableReferenceDemoMode: enableReferenceDemoMode,
      sessionEnvironmentOverrides: sessionEnvironmentOverrides,
      enableShellAnimations: enableShellAnimations,
    ),
  );
}
