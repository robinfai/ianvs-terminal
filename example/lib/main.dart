import 'package:flutter/widgets.dart';

import 'startup/app_startup_host.dart';
import 'startup/production_app_startup.dart';

bool usesIosSandboxShell(TargetPlatform platform) {
  return platform == TargetPlatform.iOS;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AppStartupHost(coordinator: createProductionAppStartupCoordinator()));
}
