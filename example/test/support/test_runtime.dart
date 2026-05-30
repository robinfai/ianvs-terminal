import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:ianvs_pty/ianvs_pty.dart';

TerminalRuntimeController testRuntime(
  PtySessionBackend backend, {
  Future<void> Function(String text)? copyToClipboard,
  Future<String> Function()? readClipboard,
  bool enableSessionPolling = false,
  bool enableWarmUpRefresh = false,
  TerminalWindowResizeCallback? resizeWindowBy,
  bool seedDefaultSession = true,
}) {
  final runtime = TerminalRuntimeController(
    backend: backend,
    copyToClipboard: copyToClipboard ?? (_) async {},
    readClipboard: readClipboard ?? () async => '',
    resizeWindowBy: resizeWindowBy,
    enableSessionPolling: enableSessionPolling,
    enableWarmUpRefresh: enableWarmUpRefresh,
  );
  if (seedDefaultSession) {
    runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
  }
  return runtime;
}
