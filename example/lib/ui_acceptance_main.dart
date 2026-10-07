// UI automation only: no test configuration, task injection, controller access,
// automatic approvals or alternative startup graph. Run the production UI and
// expose Flutter's standard tap/text/scroll/screenshot driver commands.
// ignore: depend_on_referenced_packages
import 'package:flutter_driver/driver_extension.dart';

import 'main.dart' as app;

Future<void> main() async {
  // Choose the keyboard backend before any input client attaches. Switching
  // from Driver emulation while a terminal owns a client can leave the macOS
  // text plugin without the matching native client.
  enableFlutterDriverExtension(
    enableTextEntryEmulation: !const bool.fromEnvironment(
      'TRAIL_UI_NATIVE_KEYBOARD',
    ),
  );
  await app.main();
}
