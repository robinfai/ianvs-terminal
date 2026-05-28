// ignore: depend_on_referenced_packages
import 'package:flutter_driver/driver_extension.dart';
import 'package:app/features/shell/shell_acceptance.dart';

import 'app_bootstrap.dart';
import 'driver_command_extensions.dart';

void main() {
  enableFlutterDriverExtension(
    handler: shellAcceptanceProbe.handleDriverRequest,
    commands: [UnsyncedTapCommandExtension()],
  );
  runIanvsTerminalApp(
    enableSessionPolling: false,
    enableDriverWarmUpRefresh: false,
    enableReferenceDemoMode: true,
    enableShellAnimations: false,
    sessionEnvironmentOverrides: const {
      'TERM': 'xterm-256color',
      'COLORTERM': 'truecolor',
    },
  );
}
