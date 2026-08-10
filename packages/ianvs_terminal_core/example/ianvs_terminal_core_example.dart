import 'package:flutter/services.dart';
import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';

TerminalRuntimeController createTerminalRuntime() {
  return TerminalRuntimeController.native(
    copyToClipboard: (text) => Clipboard.setData(ClipboardData(text: text)),
    readClipboard: () async =>
        (await Clipboard.getData('text/plain'))?.text ?? '',
  );
}
