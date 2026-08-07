import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'app_bootstrap.dart';
import 'features/pty/pty.dart';

bool usesIosSandboxShell(TargetPlatform platform) {
  return platform == TargetPlatform.iOS;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final useSandboxShell = usesIosSandboxShell(defaultTargetPlatform);
  IosSandboxShellBackend? sandboxBackend;
  if (useSandboxShell) {
    final documents = await getApplicationDocumentsDirectory();
    sandboxBackend = IosSandboxShellBackend(
      rootDirectory: Directory('${documents.path}/IanvsShell'),
      terminalBackend: NativePtyBackend.load(
        emitRuntimeEventGapDiagnostics: true,
      ),
    );
  }
  runIanvsTerminalApp(
    enableSessionPolling: true,
    enableReferenceDemoMode: false,
    ptySessionBackend: sandboxBackend,
  );
}
