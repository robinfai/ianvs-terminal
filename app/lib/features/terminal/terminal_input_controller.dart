import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../ffi/flutterm_core.dart';

class TerminalInputController {
  const TerminalInputController({
    required this.sessionId,
    required this.coreClient,
    required this.readSelection,
    required this.copySelection,
    required this.readClipboard,
  });

  final String sessionId;
  final TerminalCoreClient coreClient;
  final String Function() readSelection;
  final Future<void> Function(String text) copySelection;
  final Future<String> Function() readClipboard;

  KeyEventResult handle(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final isMetaPressed = HardwareKeyboard.instance.isMetaPressed;
    final isControlPressed = HardwareKeyboard.instance.isControlPressed;

    if (isMetaPressed && event.logicalKey == LogicalKeyboardKey.keyC) {
      unawaited(_copySelection());
      return KeyEventResult.handled;
    }

    if (isControlPressed &&
        !isMetaPressed &&
        event.logicalKey == LogicalKeyboardKey.keyC) {
      coreClient.sendInput(sessionId, Uint8List.fromList(const [0x03]));
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.keyV &&
        (isMetaPressed || isControlPressed)) {
      unawaited(_pasteClipboard());
      return KeyEventResult.handled;
    }

    final bytes = switch (event.logicalKey) {
      LogicalKeyboardKey.enter => ascii.encode('\r'),
      LogicalKeyboardKey.backspace => const [0x7f],
      LogicalKeyboardKey.arrowUp => ascii.encode('\x1B[A'),
      LogicalKeyboardKey.arrowDown => ascii.encode('\x1B[B'),
      LogicalKeyboardKey.arrowLeft => ascii.encode('\x1B[D'),
      LogicalKeyboardKey.arrowRight => ascii.encode('\x1B[C'),
      LogicalKeyboardKey.tab => ascii.encode('\t'),
      _ =>
        event.character == null || event.character!.isEmpty
            ? null
            : utf8.encode(event.character!),
    };

    if (bytes == null) {
      return KeyEventResult.ignored;
    }

    coreClient.sendInput(sessionId, Uint8List.fromList(bytes));
    return KeyEventResult.handled;
  }

  Future<void> _pasteClipboard() async {
    final text = await readClipboard();
    if (text.isEmpty) {
      return;
    }
    coreClient.sendInput(sessionId, Uint8List.fromList(utf8.encode(text)));
  }

  Future<void> _copySelection() async {
    final text = readSelection();
    if (text.isEmpty) {
      return;
    }
    await copySelection(text);
  }
}
