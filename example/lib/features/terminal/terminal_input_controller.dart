import 'package:flutterm_terminal/flutterm_terminal.dart' as terminal;
import 'package:flutter/foundation.dart';

import '../profiles/profile_models.dart';

class TerminalInputController extends terminal.TerminalInputController {
  TerminalInputController({
    required super.sessionId,
    required super.runtime,
    super.readFrame,
    Object emulation = TerminalEmulation.xterm256,
    required super.readSelection,
    required super.copySelection,
    required super.readClipboard,
  }) : super(emulation: _resolveEmulation(emulation));

  static Uint8List clipboardPasteBytesFor({
    required Object emulation,
    required terminal.TerminalFrameModes modes,
    required String text,
  }) {
    return terminal.TerminalInputController.clipboardPasteBytesFor(
      emulation: _resolveEmulation(emulation),
      modes: modes,
      text: text,
    );
  }
}

terminal.TerminalEmulation _resolveEmulation(Object emulation) {
  return switch (emulation) {
    terminal.TerminalEmulation value => value,
    _ => throw FlutterError(
      'Unsupported terminal emulation type: ${emulation.runtimeType}',
    ),
  };
}
