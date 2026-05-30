import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../config/terminal_config.dart';
import '../runtime/terminal_runtime_controller.dart';
import 'terminal_models.dart';

class TerminalInputController {
  TerminalInputController({
    required this.sessionId,
    required this.runtime,
    TerminalFrameDiff Function()? readFrame,
    this.emulation = TerminalEmulation.xterm256,
    required this.readSelection,
    required Future<void> Function(String text) copySelection,
    required this.readClipboard,
  }) : _copySelectionToClipboard = copySelection,
       readFrame = readFrame ?? _readEmptyFrame;

  final String sessionId;
  final TerminalRuntimeController runtime;
  final TerminalFrameDiff Function() readFrame;
  final TerminalEmulation emulation;
  final String Function() readSelection;
  final Future<void> Function(String text) _copySelectionToClipboard;
  final Future<String> Function() readClipboard;

  Future<void> copySelection() => _copySelection();

  void sendText(String text) {
    if (text.isEmpty) {
      return;
    }
    runtime.sendInput(sessionId, Uint8List.fromList(utf8.encode(text)));
  }

  KeyEventResult handle(KeyEvent event) {
    if (!_isKeyPressEvent(event)) {
      return KeyEventResult.ignored;
    }

    final isRepeated = event is KeyRepeatEvent;
    final isMetaPressed = HardwareKeyboard.instance.isMetaPressed;
    final isControlPressed = HardwareKeyboard.instance.isControlPressed;
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
    final usesAppModifier = _platformAppModifierPressed(
      isMetaPressed: isMetaPressed,
      isControlPressed: isControlPressed,
    );

    if (isMetaPressed && event.logicalKey == LogicalKeyboardKey.keyC) {
      if (isRepeated) {
        return KeyEventResult.handled;
      }
      unawaited(_copySelection());
      return KeyEventResult.handled;
    }

    if (isControlPressed &&
        !isMetaPressed &&
        event.logicalKey == LogicalKeyboardKey.keyC) {
      runtime.sendInput(sessionId, Uint8List.fromList(const [0x03]));
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.keyV && usesAppModifier) {
      if (isRepeated) {
        return KeyEventResult.handled;
      }
      unawaited(_pasteClipboard());
      return KeyEventResult.handled;
    }

    if (isMetaPressed && !isControlPressed && !isShiftPressed) {
      final navigationBytes = switch (event.logicalKey) {
        LogicalKeyboardKey.arrowLeft => ascii.encode('\x1B[H'),
        LogicalKeyboardKey.arrowRight => ascii.encode('\x1B[F'),
        _ => null,
      };
      if (navigationBytes != null) {
        runtime.sendInput(sessionId, Uint8List.fromList(navigationBytes));
        return KeyEventResult.handled;
      }
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

    runtime.sendInput(sessionId, Uint8List.fromList(bytes));
    return KeyEventResult.handled;
  }

  void sendFocusReport({required bool focused}) {
    final sequence = focused ? '\x1B[I' : '\x1B[O';
    runtime.sendInput(sessionId, Uint8List.fromList(ascii.encode(sequence)));
  }

  void sendMouseReport({
    required TerminalFrameModes modes,
    required int row,
    required int col,
    required int button,
    required bool pressed,
    int modifiers = 0,
  }) {
    if (modes.mouseMode == 'off') {
      return;
    }
    final bytes = mouseReportBytesFor(
      modes: modes,
      row: row,
      col: col,
      button: button,
      pressed: pressed,
      modifiers: modifiers,
    );
    if (bytes.isEmpty) {
      return;
    }
    runtime.sendInput(sessionId, Uint8List.fromList(bytes));
  }

  Future<void> _pasteClipboard() async {
    final text = await readClipboard();
    if (text.isEmpty) {
      return;
    }
    runtime.sendInput(
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
    await _copySelectionToClipboard(text);
  }

  static Uint8List clipboardPasteBytesFor({
    required TerminalEmulation emulation,
    required TerminalFrameModes modes,
    required String text,
  }) {
    if (emulation == TerminalEmulation.xterm256 && modes.bracketedPaste) {
      final sanitizedText = _sanitizeBracketedPasteText(text);
      return Uint8List.fromList(
        ascii.encode('\x1B[200~') +
            utf8.encode(sanitizedText) +
            ascii.encode('\x1B[201~'),
      );
    }
    return Uint8List.fromList(utf8.encode(text));
  }

  static String _sanitizeBracketedPasteText(String text) {
    return text
        .replaceAll('\x1B[200~', '')
        .replaceAll('\x1B[201~', '')
        .replaceAll('\u{009B}200~', '')
        .replaceAll('\u{009B}201~', '');
  }

  static List<int>? keyBytesFor({
    required KeyEvent event,
    required TerminalEmulation emulation,
    required TerminalFrameModes modes,
  }) {
    if (HardwareKeyboard.instance.isAltPressed &&
        !HardwareKeyboard.instance.isShiftPressed &&
        !HardwareKeyboard.instance.isControlPressed) {
      final optionArrow = _optionArrowBytesFor(event.logicalKey, modes: modes);
      if (optionArrow != null) {
        return optionArrow;
      }
    }

    final modifier = _xtermKeyboardModifier();
    if (modifier != null) {
      final modified = _modifiedKeyBytesFor(
        event.logicalKey,
        modifier: modifier,
      );
      if (modified != null) {
        return modified;
      }
    }

    final controlLetterBytes = _controlLetterBytesFor(event.logicalKey);
    if (controlLetterBytes != null &&
        HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isAltPressed) {
      return controlLetterBytes;
    }

    if (HardwareKeyboard.instance.isAltPressed) {
      final character = _altCharacterFor(event);
      if (character != null) {
        return ascii.encode('\x1B') + utf8.encode(character);
      }
    }

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

  static List<int> mouseReportBytesFor({
    required TerminalFrameModes modes,
    required int row,
    required int col,
    required int button,
    required bool pressed,
    int modifiers = 0,
  }) {
    final buttonCode = button | (modifiers << 2);
    return switch (modes.mouseEncoding) {
      'sgr' => ascii.encode(
        '\x1B[<$buttonCode;${col + 1};${row + 1}${pressed ? 'M' : 'm'}',
      ),
      'urxvt' => ascii.encode(
        '\x1B[${(button | (modifiers << 2) | (pressed ? 0 : 3)) + 32};${col + 1};${row + 1}M',
      ),
      'utf8' => _defaultMouseReportBytes(
        row: row,
        col: col,
        button: button,
        pressed: pressed,
        modifiers: modifiers,
        utf8Coordinates: true,
      ),
      _ => _defaultMouseReportBytes(
        row: row,
        col: col,
        button: button,
        pressed: pressed,
        modifiers: modifiers,
        utf8Coordinates: false,
      ),
    };
  }
}

List<int>? _characterBytesFor(
  KeyEvent event, {
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

bool _isKeyPressEvent(KeyEvent event) {
  return event is KeyDownEvent || event is KeyRepeatEvent;
}

bool _platformUsesMetaAppModifier() {
  return switch (defaultTargetPlatform) {
    TargetPlatform.macOS || TargetPlatform.iOS => true,
    _ => false,
  };
}

bool _platformAppModifierPressed({
  required bool isMetaPressed,
  required bool isControlPressed,
}) {
  if (_platformUsesMetaAppModifier()) {
    return isMetaPressed && !isControlPressed;
  }
  return isControlPressed && !isMetaPressed;
}

List<int>? _controlLetterBytesFor(LogicalKeyboardKey key) {
  return switch (key) {
    LogicalKeyboardKey.keyA => const <int>[0x01],
    LogicalKeyboardKey.keyB => const <int>[0x02],
    LogicalKeyboardKey.keyD => const <int>[0x04],
    LogicalKeyboardKey.keyE => const <int>[0x05],
    LogicalKeyboardKey.keyF => const <int>[0x06],
    LogicalKeyboardKey.keyG => const <int>[0x07],
    LogicalKeyboardKey.keyH => const <int>[0x08],
    LogicalKeyboardKey.keyI => const <int>[0x09],
    LogicalKeyboardKey.keyJ => const <int>[0x0A],
    LogicalKeyboardKey.keyK => const <int>[0x0B],
    LogicalKeyboardKey.keyL => const <int>[0x0C],
    LogicalKeyboardKey.keyM => const <int>[0x0D],
    LogicalKeyboardKey.keyN => const <int>[0x0E],
    LogicalKeyboardKey.keyO => const <int>[0x0F],
    LogicalKeyboardKey.keyP => const <int>[0x10],
    LogicalKeyboardKey.keyQ => const <int>[0x11],
    LogicalKeyboardKey.keyR => const <int>[0x12],
    LogicalKeyboardKey.keyS => const <int>[0x13],
    LogicalKeyboardKey.keyT => const <int>[0x14],
    LogicalKeyboardKey.keyU => const <int>[0x15],
    LogicalKeyboardKey.keyV => const <int>[0x16],
    LogicalKeyboardKey.keyW => const <int>[0x17],
    LogicalKeyboardKey.keyX => const <int>[0x18],
    LogicalKeyboardKey.keyY => const <int>[0x19],
    LogicalKeyboardKey.keyZ => const <int>[0x1A],
    _ => null,
  };
}

int? _xtermKeyboardModifier() {
  var value = 1;
  if (HardwareKeyboard.instance.isShiftPressed) {
    value += 1;
  }
  if (HardwareKeyboard.instance.isAltPressed) {
    value += 2;
  }
  if (HardwareKeyboard.instance.isControlPressed) {
    value += 4;
  }
  return value == 1 ? null : value;
}

List<int>? _modifiedKeyBytesFor(
  LogicalKeyboardKey key, {
  required int modifier,
}) {
  String? finalByte;
  switch (key) {
    case LogicalKeyboardKey.arrowUp:
      finalByte = 'A';
      break;
    case LogicalKeyboardKey.arrowDown:
      finalByte = 'B';
      break;
    case LogicalKeyboardKey.arrowRight:
      finalByte = 'C';
      break;
    case LogicalKeyboardKey.arrowLeft:
      finalByte = 'D';
      break;
    case LogicalKeyboardKey.home:
      finalByte = 'H';
      break;
    case LogicalKeyboardKey.end:
      finalByte = 'F';
      break;
    default:
      finalByte = null;
  }
  if (finalByte != null) {
    return ascii.encode('\x1B[1;$modifier$finalByte');
  }

  final tildeCode = switch (key) {
    LogicalKeyboardKey.insert => 2,
    LogicalKeyboardKey.delete => 3,
    LogicalKeyboardKey.pageUp => 5,
    LogicalKeyboardKey.pageDown => 6,
    _ => null,
  };
  if (tildeCode != null) {
    return ascii.encode('\x1B[$tildeCode;$modifier~');
  }

  final functionCode = switch (key) {
    LogicalKeyboardKey.f1 => 1,
    LogicalKeyboardKey.f2 => 1,
    LogicalKeyboardKey.f3 => 1,
    LogicalKeyboardKey.f4 => 1,
    LogicalKeyboardKey.f5 => 15,
    LogicalKeyboardKey.f6 => 17,
    LogicalKeyboardKey.f7 => 18,
    LogicalKeyboardKey.f8 => 19,
    LogicalKeyboardKey.f9 => 20,
    LogicalKeyboardKey.f10 => 21,
    LogicalKeyboardKey.f11 => 23,
    LogicalKeyboardKey.f12 => 24,
    _ => null,
  };
  if (functionCode == null) {
    return null;
  }
  final functionFinal = switch (key) {
    LogicalKeyboardKey.f1 => 'P',
    LogicalKeyboardKey.f2 => 'Q',
    LogicalKeyboardKey.f3 => 'R',
    LogicalKeyboardKey.f4 => 'S',
    _ => null,
  };
  if (functionFinal != null) {
    return ascii.encode('\x1B[1;$modifier$functionFinal');
  }
  return ascii.encode('\x1B[$functionCode;$modifier~');
}

String? _altCharacterFor(KeyEvent event) {
  final label = event.logicalKey.keyLabel;
  if (label.length == 1) {
    final codeUnit = label.codeUnitAt(0);
    final isAsciiLetter =
        (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
        (codeUnit >= 0x61 && codeUnit <= 0x7a);
    if (isAsciiLetter) {
      return HardwareKeyboard.instance.isShiftPressed
          ? label.toUpperCase()
          : label.toLowerCase();
    }
  }
  final character = event.character;
  if (character == null || character.isEmpty || character == '\n') {
    return null;
  }
  return character;
}

List<int>? _optionArrowBytesFor(
  LogicalKeyboardKey key, {
  required TerminalFrameModes modes,
}) {
  return switch (key) {
    LogicalKeyboardKey.arrowLeft => ascii.encode('\x1Bb'),
    LogicalKeyboardKey.arrowRight => ascii.encode('\x1Bf'),
    LogicalKeyboardKey.arrowUp => ascii.encode(
      modes.applicationCursor ? '\x1BOA' : '\x1B[A',
    ),
    LogicalKeyboardKey.arrowDown => ascii.encode(
      modes.applicationCursor ? '\x1BOB' : '\x1B[B',
    ),
    _ => null,
  };
}

List<int> _defaultMouseReportBytes({
  required int row,
  required int col,
  required int button,
  required bool pressed,
  required int modifiers,
  required bool utf8Coordinates,
}) {
  final buttonCode = button | (modifiers << 2) | (pressed ? 0 : 3);
  final encoded = <int>[0x1b, 0x5b, 0x4d, buttonCode + 32];
  if (utf8Coordinates) {
    encoded.addAll(utf8.encode(String.fromCharCode(col + 33)));
    encoded.addAll(utf8.encode(String.fromCharCode(row + 33)));
  } else {
    encoded.add((col + 33).clamp(0, 255).toInt());
    encoded.add((row + 33).clamp(0, 255).toInt());
  }
  return encoded;
}

List<int> _keypadSequence({
  required TerminalFrameModes modes,
  required String numeric,
  required String application,
}) {
  return ascii.encode(modes.applicationKeypad ? application : numeric);
}

TerminalFrameDiff _readEmptyFrame() => TerminalFrameDiff.empty;
