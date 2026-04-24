import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../profiles/profile_models.dart';
import '../../ffi/flutterm_core.dart';
import 'terminal_painter_models.dart';

class TerminalInputController {
  TerminalInputController({
    required this.sessionId,
    required this.coreClient,
    TerminalFrameDiff Function()? readFrame,
    this.emulation = TerminalEmulation.xterm256,
    required this.readSelection,
    required this.copySelection,
    required this.readClipboard,
  }) : readFrame = readFrame ?? _readEmptyFrame;

  final String sessionId;
  final TerminalCoreClient coreClient;
  final TerminalFrameDiff Function() readFrame;
  final TerminalEmulation emulation;
  final String Function() readSelection;
  final Future<void> Function(String text) copySelection;
  final Future<String> Function() readClipboard;

  KeyEventResult handle(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final isMetaPressed = HardwareKeyboard.instance.isMetaPressed;
    final isControlPressed = HardwareKeyboard.instance.isControlPressed;
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

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

    if ((isMetaPressed || isControlPressed) &&
        isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyP) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.keyT &&
        (isMetaPressed || isControlPressed)) {
      return KeyEventResult.ignored;
    }

    if (isMetaPressed) {
      return KeyEventResult.ignored;
    }

    final bytes = keyBytesFor(
      event: event,
      emulation: emulation,
      modes: readFrame().modes,
    );

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
    coreClient.sendInput(
      sessionId,
      clipboardPasteBytesFor(
        emulation: emulation,
        modes: readFrame().modes,
        text: text,
      ),
    );
  }

  Future<void> _copySelection() async {
    final text = readSelection();
    if (text.isEmpty) {
      return;
    }
    await copySelection(text);
  }

  static Uint8List clipboardPasteBytesFor({
    required TerminalEmulation emulation,
    required TerminalFrameModes modes,
    required String text,
  }) {
    if (emulation == TerminalEmulation.xterm256 && modes.bracketedPaste) {
      return Uint8List.fromList(
        ascii.encode('\x1B[200~') +
            utf8.encode(text) +
            ascii.encode('\x1B[201~'),
      );
    }
    return Uint8List.fromList(utf8.encode(text));
  }

  static List<int>? keyBytesFor({
    required KeyDownEvent event,
    required TerminalEmulation emulation,
    required TerminalFrameModes modes,
  }) {
    return switch (event.logicalKey) {
      LogicalKeyboardKey.enter => ascii.encode(
        modes.lineFeedNewLineMode ? '\r\n' : '\r',
      ),
      LogicalKeyboardKey.numpadEnter => _keypadSequence(
        modes: modes,
        numeric: '\r',
        application: '\x1BOM',
      ),
      LogicalKeyboardKey.backspace => const [0x7f],
      LogicalKeyboardKey.arrowUp => ascii.encode(
        modes.applicationCursor ? '\x1BOA' : '\x1B[A',
      ),
      LogicalKeyboardKey.arrowDown => ascii.encode(
        modes.applicationCursor ? '\x1BOB' : '\x1B[B',
      ),
      LogicalKeyboardKey.arrowLeft => ascii.encode(
        modes.applicationCursor ? '\x1BOD' : '\x1B[D',
      ),
      LogicalKeyboardKey.arrowRight => ascii.encode(
        modes.applicationCursor ? '\x1BOC' : '\x1B[C',
      ),
      LogicalKeyboardKey.home => ascii.encode('\x1B[H'),
      LogicalKeyboardKey.end => ascii.encode('\x1B[F'),
      LogicalKeyboardKey.insert => ascii.encode('\x1B[2~'),
      LogicalKeyboardKey.delete => ascii.encode('\x1B[3~'),
      LogicalKeyboardKey.pageUp => ascii.encode('\x1B[5~'),
      LogicalKeyboardKey.pageDown => ascii.encode('\x1B[6~'),
      LogicalKeyboardKey.f1 => ascii.encode('\x1BOP'),
      LogicalKeyboardKey.f2 => ascii.encode('\x1BOQ'),
      LogicalKeyboardKey.f3 => ascii.encode('\x1BOR'),
      LogicalKeyboardKey.f4 => ascii.encode('\x1BOS'),
      LogicalKeyboardKey.f5 => ascii.encode('\x1B[15~'),
      LogicalKeyboardKey.f6 => ascii.encode('\x1B[17~'),
      LogicalKeyboardKey.f7 => ascii.encode('\x1B[18~'),
      LogicalKeyboardKey.f8 => ascii.encode('\x1B[19~'),
      LogicalKeyboardKey.f9 => ascii.encode('\x1B[20~'),
      LogicalKeyboardKey.f10 => ascii.encode('\x1B[21~'),
      LogicalKeyboardKey.f11 => ascii.encode('\x1B[23~'),
      LogicalKeyboardKey.f12 => ascii.encode('\x1B[24~'),
      LogicalKeyboardKey.f13 => ascii.encode('\x1B[25~'),
      LogicalKeyboardKey.f14 => ascii.encode('\x1B[26~'),
      LogicalKeyboardKey.f15 => ascii.encode('\x1B[28~'),
      LogicalKeyboardKey.f16 => ascii.encode('\x1B[29~'),
      LogicalKeyboardKey.f17 => ascii.encode('\x1B[31~'),
      LogicalKeyboardKey.f18 => ascii.encode('\x1B[32~'),
      LogicalKeyboardKey.f19 => ascii.encode('\x1B[33~'),
      LogicalKeyboardKey.f20 => ascii.encode('\x1B[34~'),
      LogicalKeyboardKey.tab =>
        HardwareKeyboard.instance.isShiftPressed
            ? ascii.encode('\x1B[Z')
            : ascii.encode('\t'),
      LogicalKeyboardKey.numpadDivide => _keypadSequence(
        modes: modes,
        numeric: '/',
        application: '\x1BOo',
      ),
      LogicalKeyboardKey.numpadMultiply => _keypadSequence(
        modes: modes,
        numeric: '*',
        application: '\x1BOj',
      ),
      LogicalKeyboardKey.numpadSubtract => _keypadSequence(
        modes: modes,
        numeric: '-',
        application: '\x1BOm',
      ),
      LogicalKeyboardKey.numpadAdd => _keypadSequence(
        modes: modes,
        numeric: '+',
        application: '\x1BOk',
      ),
      LogicalKeyboardKey.numpadDecimal => _keypadSequence(
        modes: modes,
        numeric: '.',
        application: '\x1BOn',
      ),
      LogicalKeyboardKey.numpadComma => _keypadSequence(
        modes: modes,
        numeric: ',',
        application: '\x1BOl',
      ),
      LogicalKeyboardKey.numpadEqual => _keypadSequence(
        modes: modes,
        numeric: '=',
        application: '\x1BOX',
      ),
      LogicalKeyboardKey.numpad0 => _keypadSequence(
        modes: modes,
        numeric: '0',
        application: '\x1BOp',
      ),
      LogicalKeyboardKey.numpad1 => _keypadSequence(
        modes: modes,
        numeric: '1',
        application: '\x1BOq',
      ),
      LogicalKeyboardKey.numpad2 => _keypadSequence(
        modes: modes,
        numeric: '2',
        application: '\x1BOr',
      ),
      LogicalKeyboardKey.numpad3 => _keypadSequence(
        modes: modes,
        numeric: '3',
        application: '\x1BOs',
      ),
      LogicalKeyboardKey.numpad4 => _keypadSequence(
        modes: modes,
        numeric: '4',
        application: '\x1BOt',
      ),
      LogicalKeyboardKey.numpad5 => _keypadSequence(
        modes: modes,
        numeric: '5',
        application: '\x1BOu',
      ),
      LogicalKeyboardKey.numpad6 => _keypadSequence(
        modes: modes,
        numeric: '6',
        application: '\x1BOv',
      ),
      LogicalKeyboardKey.numpad7 => _keypadSequence(
        modes: modes,
        numeric: '7',
        application: '\x1BOw',
      ),
      LogicalKeyboardKey.numpad8 => _keypadSequence(
        modes: modes,
        numeric: '8',
        application: '\x1BOx',
      ),
      LogicalKeyboardKey.numpad9 => _keypadSequence(
        modes: modes,
        numeric: '9',
        application: '\x1BOy',
      ),
      _ => _characterBytesFor(event, emulation: emulation),
    };
  }
}

List<int>? _characterBytesFor(
  KeyDownEvent event, {
  required TerminalEmulation emulation,
}) {
  final character = event.character;
  if (character == null || character.isEmpty) {
    return null;
  }
  if (emulation == TerminalEmulation.vt220 && character == '\n') {
    return ascii.encode('\r');
  }
  return utf8.encode(character);
}

List<int> _keypadSequence({
  required TerminalFrameModes modes,
  required String numeric,
  required String application,
}) {
  return ascii.encode(modes.applicationKeypad ? application : numeric);
}

TerminalFrameDiff _readEmptyFrame() => TerminalFrameDiff.empty;
