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
  final Set<LogicalKeyboardKey> _suppressedKeyUps = <LogicalKeyboardKey>{};

  Future<void> copySelection() => _copySelection();

  void sendText(String text) {
    if (text.isEmpty) {
      return;
    }
    runtime.sendInput(sessionId, Uint8List.fromList(utf8.encode(text)));
  }

  KeyEventResult handle(KeyEvent event) {
    final frameModes = readFrame().modes;
    if (!_shouldHandleKeyEvent(event, modes: frameModes)) {
      return KeyEventResult.ignored;
    }

    final isKeyPress = _isKeyPressEvent(event);
    final isRepeated = event is KeyRepeatEvent;
    final isMetaPressed = HardwareKeyboard.instance.isMetaPressed;
    final isControlPressed = HardwareKeyboard.instance.isControlPressed;
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
    final usesAppModifier = _platformAppModifierPressed(
      isMetaPressed: isMetaPressed,
      isControlPressed: isControlPressed,
    );

    if (event is KeyUpEvent && _suppressedKeyUps.remove(event.logicalKey)) {
      return KeyEventResult.handled;
    }

    if (isKeyPress &&
        isMetaPressed &&
        event.logicalKey == LogicalKeyboardKey.keyC) {
      _suppressKeyUp(event.logicalKey);
      if (isRepeated) {
        return KeyEventResult.handled;
      }
      unawaited(_copySelection());
      return KeyEventResult.handled;
    }

    if (isKeyPress &&
        isControlPressed &&
        !isMetaPressed &&
        event.logicalKey == LogicalKeyboardKey.keyC &&
        frameModes.kittyKeyboardFlags == 0) {
      runtime.sendInput(sessionId, Uint8List.fromList(const [0x03]));
      return KeyEventResult.handled;
    }

    if (isKeyPress &&
        event.logicalKey == LogicalKeyboardKey.keyV &&
        usesAppModifier) {
      _suppressKeyUp(event.logicalKey);
      if (isRepeated) {
        return KeyEventResult.handled;
      }
      unawaited(_pasteClipboard());
      return KeyEventResult.handled;
    }

    if (isKeyPress && isMetaPressed && !isControlPressed && !isShiftPressed) {
      final navigationBytes = switch (event.logicalKey) {
        LogicalKeyboardKey.arrowLeft => ascii.encode('\x1B[H'),
        LogicalKeyboardKey.arrowRight => ascii.encode('\x1B[F'),
        _ => null,
      };
      if (navigationBytes != null) {
        _suppressKeyUp(event.logicalKey);
        runtime.sendInput(sessionId, Uint8List.fromList(navigationBytes));
        return KeyEventResult.handled;
      }
    }

    if (isKeyPress && isMetaPressed) {
      _suppressKeyUp(event.logicalKey);
      return KeyEventResult.ignored;
    }

    final bytes = keyBytesFor(
      event: event,
      emulation: emulation,
      modes: frameModes,
    );

    if (bytes == null) {
      return KeyEventResult.ignored;
    }

    runtime.sendInput(sessionId, Uint8List.fromList(bytes));
    return KeyEventResult.handled;
  }

  void _suppressKeyUp(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight) {
      return;
    }
    _suppressedKeyUps.add(key);
  }

  void sendFocusReport({required bool focused, TerminalFrameModes? modes}) {
    final resolvedModes = modes ?? readFrame().modes;
    if (emulation != TerminalEmulation.xterm256 ||
        !resolvedModes.focusTracking) {
      return;
    }
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
    int? pixelX,
    int? pixelY,
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
      pixelX: pixelX,
      pixelY: pixelY,
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
    final bytes = clipboardPasteBytesFor(
      emulation: emulation,
      modes: readFrame().modes,
      text: text,
    );
    if (bytes.isEmpty) {
      return;
    }
    runtime.sendInput(sessionId, bytes);
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
    if (text.isEmpty) {
      return Uint8List(0);
    }
    if (emulation == TerminalEmulation.xterm256 && modes.bracketedPaste) {
      final sanitizedText = _sanitizeBracketedPasteText(text);
      if (sanitizedText.isEmpty) {
        return Uint8List(0);
      }
      return Uint8List.fromList(
        ascii.encode('\x1B[200~') +
            utf8.encode(sanitizedText) +
            ascii.encode('\x1B[201~'),
      );
    }
    return Uint8List.fromList(utf8.encode(text));
  }

  static String _sanitizeBracketedPasteText(String text) {
    final buffer = StringBuffer();
    var index = 0;
    while (index < text.length) {
      final markerEnd = _bracketedPasteMarkerEnd(text, index);
      if (markerEnd != null) {
        index = markerEnd;
        continue;
      }
      buffer.writeCharCode(text.codeUnitAt(index));
      index += 1;
    }
    return buffer.toString();
  }

  static int? _bracketedPasteMarkerEnd(String text, int start) {
    var index = start;
    final firstUnit = text.codeUnitAt(index);
    if (firstUnit == 0x1b) {
      index += 1;
      if (index >= text.length || text.codeUnitAt(index) != 0x5b) {
        return null;
      }
      index += 1;
    } else if (firstUnit == 0x9b) {
      index += 1;
    } else {
      return null;
    }

    final paramsStart = index;
    while (index < text.length) {
      final unit = text.codeUnitAt(index);
      if (unit == 0x7e) {
        final params = text.substring(paramsStart, index);
        return _isBracketedPasteMarkerParams(params) ? index + 1 : null;
      }
      if (!_isCsiParameterUnit(unit)) {
        return null;
      }
      index += 1;
    }
    return null;
  }

  static bool _isCsiParameterUnit(int unit) {
    return (unit >= 0x30 && unit <= 0x39) || unit == 0x3a || unit == 0x3b;
  }

  static bool _isBracketedPasteMarkerParams(String params) {
    final parts = params.split(RegExp(r'[;:]'));
    if (parts.length != 1) {
      return false;
    }
    final value = int.tryParse(parts.single);
    return value == 200 || value == 201;
  }

  static List<int>? keyBytesFor({
    required KeyEvent event,
    required TerminalEmulation emulation,
    required TerminalFrameModes modes,
  }) {
    if (emulation == TerminalEmulation.xterm256) {
      final kittyKeyboardBytes = _kittyKeyboardBytesFor(event, modes: modes);
      if (kittyKeyboardBytes != null) {
        return kittyKeyboardBytes;
      }
    }

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

    final controlAsciiBytes = _controlAsciiBytesFor(event.logicalKey);
    if (controlAsciiBytes != null &&
        HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isAltPressed) {
      return controlAsciiBytes;
    }

    if (HardwareKeyboard.instance.isAltPressed) {
      final character = _altCharacterFor(event);
      if (character != null) {
        return ascii.encode('\x1B') + utf8.encode(character);
      }
    }

    return switch (event.logicalKey) {
      LogicalKeyboardKey.escape => ascii.encode('\x1B'),
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
    int? pixelX,
    int? pixelY,
  }) {
    if (!_shouldReportMouseEvent(
      mode: modes.mouseMode,
      button: button,
      pressed: pressed,
    )) {
      return const <int>[];
    }
    final normalizedRow = row < 0 ? 0 : row;
    final normalizedCol = col < 0 ? 0 : col;
    final normalizedPixelX = pixelX == null
        ? null
        : pixelX < 0
        ? 0
        : pixelX;
    final normalizedPixelY = pixelY == null
        ? null
        : pixelY < 0
        ? 0
        : pixelY;
    final normalizedModifiers = modifiers < 0 ? 0 : modifiers & 0x07;
    final buttonCode = button | (normalizedModifiers << 2);
    return switch (modes.mouseEncoding) {
      'sgr' => ascii.encode(
        '\x1B[<$buttonCode;${normalizedCol + 1};${normalizedRow + 1}${pressed ? 'M' : 'm'}',
      ),
      'sgr_pixels' => ascii.encode(
        '\x1B[<$buttonCode;${(normalizedPixelX ?? normalizedCol) + 1};${(normalizedPixelY ?? normalizedRow) + 1}${pressed ? 'M' : 'm'}',
      ),
      'urxvt' => ascii.encode(
        '\x1B[${(buttonCode | (pressed ? 0 : 3)) + 32};${normalizedCol + 1};${normalizedRow + 1}M',
      ),
      'utf8' => _defaultMouseReportBytes(
        row: normalizedRow,
        col: normalizedCol,
        button: button,
        pressed: pressed,
        modifiers: normalizedModifiers,
        utf8Coordinates: true,
      ),
      _ => _defaultMouseReportBytes(
        row: normalizedRow,
        col: normalizedCol,
        button: button,
        pressed: pressed,
        modifiers: normalizedModifiers,
        utf8Coordinates: false,
      ),
    };
  }
}

bool _shouldReportMouseEvent({
  required String mode,
  required int button,
  required bool pressed,
}) {
  if (mode == 'off') {
    return false;
  }
  if (!pressed && _isMouseWheelButton(button)) {
    return false;
  }
  final isMotion = button >= 32 && button < 64;
  final isButtonDragMotion = button >= 32 && button <= 34;
  return switch (mode) {
    'x10' => pressed && !isMotion && button < 64,
    'normal' => !isMotion,
    'button_event' => !isMotion || isButtonDragMotion,
    'any_event' => true,
    _ => false,
  };
}

bool _isMouseWheelButton(int button) => button >= 64 && button <= 67;

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

bool _shouldHandleKeyEvent(
  KeyEvent event, {
  required TerminalFrameModes modes,
}) {
  if (_isKeyPressEvent(event)) {
    return true;
  }
  return _kittyKeyboardShouldReportRelease(event, modes: modes);
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

List<int>? _controlAsciiBytesFor(LogicalKeyboardKey key) {
  return switch (key) {
    LogicalKeyboardKey.space => const <int>[0x00],
    LogicalKeyboardKey.digit0 => const <int>[0x30],
    LogicalKeyboardKey.digit1 => const <int>[0x31],
    LogicalKeyboardKey.digit2 => const <int>[0x00],
    LogicalKeyboardKey.digit3 => const <int>[0x1b],
    LogicalKeyboardKey.digit4 => const <int>[0x1c],
    LogicalKeyboardKey.digit5 => const <int>[0x1d],
    LogicalKeyboardKey.digit6 => const <int>[0x1e],
    LogicalKeyboardKey.digit7 => const <int>[0x1f],
    LogicalKeyboardKey.digit8 => const <int>[0x7f],
    LogicalKeyboardKey.digit9 => const <int>[0x39],
    LogicalKeyboardKey.slash => const <int>[0x1f],
    LogicalKeyboardKey.semicolon => const <int>[0x3b],
    LogicalKeyboardKey.bracketLeft => const <int>[0x1b],
    LogicalKeyboardKey.backslash => const <int>[0x1c],
    LogicalKeyboardKey.bracketRight => const <int>[0x1d],
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

const int _kittyKeyboardDisambiguateFlag = 1;
const int _kittyKeyboardReportEventsFlag = 2;
const int _kittyKeyboardReportAlternateKeysFlag = 4;
const int _kittyKeyboardReportAllKeysFlag = 8;
const int _kittyKeyboardReportAssociatedTextFlag = 16;

List<int>? _kittyKeyboardBytesFor(
  KeyEvent event, {
  required TerminalFrameModes modes,
}) {
  final flags = modes.kittyKeyboardFlags;
  if (flags == 0) {
    return null;
  }
  final reportAllKeys = (flags & _kittyKeyboardReportAllKeysFlag) != 0;
  final reportEvents = (flags & _kittyKeyboardReportEventsFlag) != 0;
  final associatedText = reportAllKeys
      ? _kittyKeyboardAssociatedText(event, flags: flags)
      : null;
  final disambiguate =
      reportAllKeys || (flags & _kittyKeyboardDisambiguateFlag) != 0;
  if (!disambiguate) {
    return null;
  }

  final modifier = _kittyKeyboardModifier();
  final eventType = _kittyKeyboardEventType(event, reportEvents: reportEvents);
  if (eventType == null) {
    return null;
  }
  final functionalBytes = _kittyKeyboardFunctionalBytesFor(
    event,
    modifier: modifier,
    eventType: eventType,
  );
  if (functionalBytes != null) {
    return functionalBytes;
  }

  final keyCode = _kittyKeyboardCodeFor(event.logicalKey);
  if (keyCode == null) {
    return null;
  }
  final keyCodeParameter = _kittyKeyboardKeyCodeParameter(
    event,
    flags: flags,
    keyCode: keyCode,
  );

  final isModifierOnly = _isKittyKeyboardModifierOnlyKey(event.logicalKey);
  if (!reportAllKeys && isModifierOnly) {
    return null;
  }

  if (!reportAllKeys &&
      modifier == 1 &&
      event.logicalKey != LogicalKeyboardKey.escape) {
    return null;
  }

  final isLegacyC0Exception =
      event.logicalKey == LogicalKeyboardKey.enter ||
      event.logicalKey == LogicalKeyboardKey.numpadEnter ||
      event.logicalKey == LogicalKeyboardKey.tab ||
      event.logicalKey == LogicalKeyboardKey.backspace;
  if (!reportAllKeys &&
      isLegacyC0Exception &&
      eventType != _kittyKeyboardRepeatEvent &&
      _kittyKeyboardUsesLegacyC0Exception(
        event.logicalKey,
        modifier: modifier,
      )) {
    return null;
  }

  final suffix = switch (eventType) {
    _kittyKeyboardPressEvent => '',
    _ => ':$eventType',
  };
  if (associatedText != null) {
    final modifierParameter =
        modifier == 1 && eventType == _kittyKeyboardPressEvent
        ? ''
        : '$modifier$suffix';
    return ascii.encode(
      '\x1B[$keyCodeParameter;$modifierParameter;${associatedText}u',
    );
  }
  return ascii.encode(
    modifier == 1 && eventType == _kittyKeyboardPressEvent
        ? '\x1B[${keyCodeParameter}u'
        : '\x1B[$keyCodeParameter;$modifier${suffix}u',
  );
}

List<int>? _kittyKeyboardFunctionalBytesFor(
  KeyEvent event, {
  required int modifier,
  required int eventType,
}) {
  final finalByte = _kittyKeyboardCsiFinalFor(event.logicalKey);
  if (finalByte != null) {
    if (modifier == 1 && eventType == _kittyKeyboardPressEvent) {
      return null;
    }
    return ascii.encode(
      '\x1B[1;${_kittyKeyboardModifierEventParameter(modifier, eventType)}$finalByte',
    );
  }

  final tildeCode = _kittyKeyboardTildeCodeFor(event.logicalKey);
  if (tildeCode != null) {
    if (modifier == 1 && eventType == _kittyKeyboardPressEvent) {
      return null;
    }
    return ascii.encode(
      '\x1B[$tildeCode;${_kittyKeyboardModifierEventParameter(modifier, eventType)}~',
    );
  }

  final privateCode = _kittyKeyboardPrivateFunctionalCodeFor(event.logicalKey);
  if (privateCode != null) {
    if (modifier == 1 && eventType == _kittyKeyboardPressEvent) {
      return null;
    }
    return ascii.encode(
      '\x1B[$privateCode;${_kittyKeyboardModifierEventParameter(modifier, eventType)}u',
    );
  }

  return null;
}

String _kittyKeyboardModifierEventParameter(int modifier, int eventType) {
  return eventType == _kittyKeyboardPressEvent
      ? '$modifier'
      : '$modifier:$eventType';
}

String? _kittyKeyboardCsiFinalFor(LogicalKeyboardKey key) {
  return switch (key) {
    LogicalKeyboardKey.arrowUp => 'A',
    LogicalKeyboardKey.arrowDown => 'B',
    LogicalKeyboardKey.arrowRight => 'C',
    LogicalKeyboardKey.arrowLeft => 'D',
    LogicalKeyboardKey.home => 'H',
    LogicalKeyboardKey.end => 'F',
    LogicalKeyboardKey.f1 => 'P',
    LogicalKeyboardKey.f2 => 'Q',
    LogicalKeyboardKey.f4 => 'S',
    _ => null,
  };
}

int? _kittyKeyboardTildeCodeFor(LogicalKeyboardKey key) {
  return switch (key) {
    LogicalKeyboardKey.insert => 2,
    LogicalKeyboardKey.delete => 3,
    LogicalKeyboardKey.pageUp => 5,
    LogicalKeyboardKey.pageDown => 6,
    LogicalKeyboardKey.f3 => 13,
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
}

int? _kittyKeyboardPrivateFunctionalCodeFor(LogicalKeyboardKey key) {
  return switch (key) {
    LogicalKeyboardKey.f13 => 57376,
    LogicalKeyboardKey.f14 => 57377,
    LogicalKeyboardKey.f15 => 57378,
    LogicalKeyboardKey.f16 => 57379,
    LogicalKeyboardKey.f17 => 57380,
    LogicalKeyboardKey.f18 => 57381,
    LogicalKeyboardKey.f19 => 57382,
    LogicalKeyboardKey.f20 => 57383,
    _ => null,
  };
}

const int _kittyKeyboardPressEvent = 1;
const int _kittyKeyboardRepeatEvent = 2;
const int _kittyKeyboardReleaseEvent = 3;

int? _kittyKeyboardEventType(KeyEvent event, {required bool reportEvents}) {
  if (event is KeyDownEvent) {
    return _kittyKeyboardPressEvent;
  }
  if (event is KeyRepeatEvent) {
    return reportEvents ? _kittyKeyboardRepeatEvent : _kittyKeyboardPressEvent;
  }
  if (event is KeyUpEvent) {
    return reportEvents ? _kittyKeyboardReleaseEvent : null;
  }
  return null;
}

String? _kittyKeyboardAssociatedText(KeyEvent event, {required int flags}) {
  if ((flags & _kittyKeyboardReportAssociatedTextFlag) == 0) {
    return null;
  }
  final character = event.character;
  if (character == null || character.isEmpty) {
    return null;
  }
  final codepoints = <int>[];
  for (final rune in character.runes) {
    if (_isKittyKeyboardAssociatedTextControlRune(rune)) {
      continue;
    }
    codepoints.add(rune);
  }
  if (codepoints.isEmpty) {
    return null;
  }
  return codepoints.join(':');
}

bool _isKittyKeyboardAssociatedTextControlRune(int rune) {
  return rune < 0x20 || rune == 0x7f || (rune >= 0x80 && rune <= 0x9f);
}

String _kittyKeyboardKeyCodeParameter(
  KeyEvent event, {
  required int flags,
  required int keyCode,
}) {
  if ((flags & _kittyKeyboardReportAlternateKeysFlag) == 0) {
    return '$keyCode';
  }
  final shiftedKeyCode = _kittyKeyboardShiftedAlternateCodeFor(
    event,
    keyCode: keyCode,
  );
  if (shiftedKeyCode == null) {
    return '$keyCode';
  }
  return '$keyCode:$shiftedKeyCode';
}

int? _kittyKeyboardShiftedAlternateCodeFor(
  KeyEvent event, {
  required int keyCode,
}) {
  if (!HardwareKeyboard.instance.isShiftPressed ||
      _isKittyKeyboardModifierOnlyKey(event.logicalKey)) {
    return null;
  }

  final character = event.character;
  if (character != null && character.isNotEmpty) {
    final rune = _singleNonControlRune(character);
    if (rune != null && rune != keyCode) {
      return rune;
    }
  }

  final shiftedKeyCode = _asciiShiftedKeyCodeFor(event.logicalKey);
  if (shiftedKeyCode == null || shiftedKeyCode == keyCode) {
    return null;
  }
  return shiftedKeyCode;
}

int? _singleNonControlRune(String text) {
  final iterator = text.runes.iterator;
  if (!iterator.moveNext()) {
    return null;
  }
  final rune = iterator.current;
  if (iterator.moveNext() || _isKittyKeyboardAssociatedTextControlRune(rune)) {
    return null;
  }
  return rune;
}

int? _asciiShiftedKeyCodeFor(LogicalKeyboardKey key) {
  if (key.keyLabel.length == 1) {
    final codeUnit = key.keyLabel.codeUnitAt(0);
    if (codeUnit >= 0x41 && codeUnit <= 0x5a) {
      return codeUnit;
    }
  }
  return switch (key) {
    LogicalKeyboardKey.digit1 => 33,
    LogicalKeyboardKey.digit2 => 64,
    LogicalKeyboardKey.digit3 => 35,
    LogicalKeyboardKey.digit4 => 36,
    LogicalKeyboardKey.digit5 => 37,
    LogicalKeyboardKey.digit6 => 94,
    LogicalKeyboardKey.digit7 => 38,
    LogicalKeyboardKey.digit8 => 42,
    LogicalKeyboardKey.digit9 => 40,
    LogicalKeyboardKey.digit0 => 41,
    LogicalKeyboardKey.minus => 95,
    LogicalKeyboardKey.equal => 43,
    LogicalKeyboardKey.bracketLeft => 123,
    LogicalKeyboardKey.bracketRight => 125,
    LogicalKeyboardKey.backslash => 124,
    LogicalKeyboardKey.semicolon => 58,
    LogicalKeyboardKey.quote => 34,
    LogicalKeyboardKey.comma => 60,
    LogicalKeyboardKey.period => 62,
    LogicalKeyboardKey.slash => 63,
    LogicalKeyboardKey.backquote => 126,
    _ => null,
  };
}

bool _kittyKeyboardShouldReportRelease(
  KeyEvent event, {
  required TerminalFrameModes modes,
}) {
  if (event is! KeyUpEvent) {
    return false;
  }
  final flags = modes.kittyKeyboardFlags;
  if ((flags & _kittyKeyboardReportEventsFlag) == 0) {
    return false;
  }
  return (flags & _kittyKeyboardReportAllKeysFlag) != 0 ||
      (flags & _kittyKeyboardDisambiguateFlag) != 0;
}

bool _kittyKeyboardUsesLegacyC0Exception(
  LogicalKeyboardKey key, {
  required int modifier,
}) {
  if (modifier == 1) {
    return true;
  }
  return key == LogicalKeyboardKey.tab && modifier == 2;
}

int _kittyKeyboardModifier() {
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
  return value;
}

int? _kittyKeyboardCodeFor(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.escape) {
    return 27;
  }
  if (key == LogicalKeyboardKey.space) {
    return 32;
  }
  if (key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter) {
    return 13;
  }
  if (key == LogicalKeyboardKey.tab) {
    return 9;
  }
  if (key == LogicalKeyboardKey.backspace) {
    return 127;
  }
  if (key == LogicalKeyboardKey.shiftLeft) {
    return 57441;
  }
  if (key == LogicalKeyboardKey.shiftRight) {
    return 57447;
  }
  if (key == LogicalKeyboardKey.controlLeft) {
    return 57442;
  }
  if (key == LogicalKeyboardKey.controlRight) {
    return 57448;
  }
  if (key == LogicalKeyboardKey.altLeft) {
    return 57443;
  }
  if (key == LogicalKeyboardKey.altRight) {
    return 57449;
  }

  final label = key.keyLabel;
  if (label.length == 1) {
    return label.toLowerCase().codeUnitAt(0);
  }
  return null;
}

bool _isKittyKeyboardModifierOnlyKey(LogicalKeyboardKey key) {
  return key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight ||
      key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight ||
      key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight;
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
