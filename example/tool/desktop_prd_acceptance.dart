import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
// UI interaction only; no requestData handler, task injection or autoapproval.
import 'package:flutter_driver/driver_extension.dart';

import 'desktop_prd_environment.dart';

/// Manual acceptance of the production startup and runtime graph with its own
/// development file stores and local shell home. No user configuration is read
/// or copied by this entrypoint. ACP may use its existing restricted auth loader
/// only after the tester explicitly configures that backend in the normal UI.
Future<void> main() async {
  if (!Platform.isMacOS || !kDebugMode) {
    throw UnsupportedError(
      'Desktop PRD acceptance requires a macOS debug build.',
    );
  }
  const fixturePath = String.fromEnvironment('TRAIL_DESKTOP_PRD_DIRECTORY');
  if (fixturePath.isEmpty) {
    throw ArgumentError(
      'Use tools/desktop_prd/run_manual.py to choose a fixture.',
    );
  }
  enableFlutterDriverExtension(
    enableTextEntryEmulation: !const bool.fromEnvironment(
      'TRAIL_UI_NATIVE_KEYBOARD',
      defaultValue: true,
    ),
  );
  WidgetsFlutterBinding.ensureInitialized();
  final environment = await DesktopPrdEnvironment.prepare(
    Directory(fixturePath),
  );
  runApp(
    buildDesktopPrdApp(
      environment: environment,
      coordinator: createDesktopPrdStartupCoordinator(environment),
    ),
  );
}
