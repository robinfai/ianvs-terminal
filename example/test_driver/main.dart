import 'package:app/app_bootstrap.dart';
import 'package:app/driver_command_extensions.dart';
import 'package:app/features/pty/pty.dart';
import 'package:app/features/shell/shell_acceptance.dart';
import 'package:flutter_driver/driver_extension.dart';

void main() {
  enableFlutterDriverExtension(
    handler: shellAcceptanceProbe.handleDriverRequest,
    commands: [UnsyncedTapCommandExtension()],
  );
  runIanvsTerminalApp(
    enableSessionPolling: false,
    ptySessionBackend: loadDefaultPtySessionBackend(),
    enableDriverWarmUpRefresh: true,
    enableShellAnimations: false,
    sessionEnvironmentOverrides: const {
      'TERM': 'xterm-256color',
      'COLORTERM': 'truecolor',
    },
  );
}
