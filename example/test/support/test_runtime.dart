import 'package:flutterm_terminal/flutterm_terminal.dart';
import 'package:flutterm_pty/flutterm_pty.dart';

TerminalRuntimeController testRuntime(
  PtySessionBackend backend, {
  Future<void> Function(String text)? copyToClipboard,
  Future<String> Function()? readClipboard,
  bool enableSessionPolling = false,
  bool enableWarmUpRefresh = false,
  TerminalWindowResizeCallback? resizeWindowBy,
}) {
  return TerminalRuntimeController(
    backend: backend,
    copyToClipboard: copyToClipboard ?? (_) async {},
    readClipboard: readClipboard ?? () async => '',
    resizeWindowBy: resizeWindowBy,
    enableSessionPolling: enableSessionPolling,
    enableWarmUpRefresh: enableWarmUpRefresh,
  );
}
