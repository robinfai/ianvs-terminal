import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'app_bootstrap.dart';
import 'data/configuration/data_api_configuration_repository.dart';
import 'data/services/data_api_bootstrap.dart';
import 'data/services/data_api_runtime.dart';
import 'features/pty/pty.dart';

bool usesIosSandboxShell(TargetPlatform platform) {
  return platform == TargetPlatform.iOS;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appSupportDirectory = await getApplicationSupportDirectory();
  final dataApiConfigurationRepository = FileDataApiConfigurationRepository(
    appSupportDirectory: appSupportDirectory,
  );
  DataApiRuntime? dataApiRuntime;
  try {
    dataApiRuntime = await DataApiBootstrap(
      configurationRepository: dataApiConfigurationRepository,
    ).start(appSupportDirectory: appSupportDirectory);
  } on Object catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'data API bootstrap',
      ),
    );
  }
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
    dataApiRuntime: dataApiRuntime,
    dataApiConfigurationRepository: dataApiConfigurationRepository,
  );
}
