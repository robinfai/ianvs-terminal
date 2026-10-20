import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;

EditableTextState? focusedEditableTextForCurrentRoute() {
  final context = FocusManager.instance.primaryFocus?.context;
  final editor = context?.findAncestorStateOfType<EditableTextState>();
  return editor != null && ModalRoute.of(editor.context)?.isCurrent != false
      ? editor
      : null;
}

class TerminalInputController extends terminal.TerminalInputController {
  TerminalInputController({
    required super.sessionId,
    required terminal.TerminalInputSink runtime,
    super.readFrame,
    Object emulation = terminal.TerminalEmulation.xterm256,
    required super.readSelection,
    required super.copySelection,
    required super.readClipboard,
    this.readOnly,
    this.readOnlyFocusLoss,
  }) : _inputOwner = runtime,
       super(
         runtime: readOnly == null && readOnlyFocusLoss == null
             ? runtime
             : _RevocableInputSink(
                 runtime,
                 readOnly ?? () => false,
                 readOnlyFocusLoss: readOnlyFocusLoss,
               ),
         emulation: _resolveEmulation(emulation),
       );

  final bool Function()? readOnly;

  /// Separately revokes the final focus-loss report after a pane loses human
  /// input ownership. All other input still uses [readOnly]. Defaults to the
  /// same policy so read-only observers cannot emit terminal reports.
  final bool Function()? readOnlyFocusLoss;
  final terminal.TerminalInputSink _inputOwner;

  @override
  Object get inputOwner => _inputOwner;

  bool get isReadOnly => readOnly?.call() ?? false;

  @override
  Future<void> pasteClipboard() async {
    if (isReadOnly) {
      return;
    }
    await super.pasteClipboard();
  }

  @override
  void sendText(String text) {
    if (isReadOnly) {
      return;
    }
    super.sendText(text);
  }

  @override
  KeyEventResult handle(KeyEvent event) {
    if (!isReadOnly) {
      return super.handle(event);
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isMetaPressed &&
        event.logicalKey == LogicalKeyboardKey.keyC) {
      if (event is KeyRepeatEvent) {
        return KeyEventResult.handled;
      }
      unawaited(copySelection());
      return KeyEventResult.handled;
    }
    return KeyEventResult.handled;
  }

  @override
  void sendFocusReport({
    required bool focused,
    terminal.TerminalFrameModes? modes,
  }) {
    if (focused
        ? isReadOnly
        : (readOnlyFocusLoss ?? readOnly)?.call() ?? false) {
      return;
    }
    super.sendFocusReport(focused: focused, modes: modes);
  }

  @override
  void sendMouseReport({
    required terminal.TerminalFrameModes modes,
    required int row,
    required int col,
    required int button,
    required bool pressed,
    int modifiers = 0,
    int? pixelX,
    int? pixelY,
  }) {
    if (isReadOnly) {
      return;
    }
    super.sendMouseReport(
      modes: modes,
      row: row,
      col: col,
      button: button,
      pressed: pressed,
      modifiers: modifiers,
      pixelX: pixelX,
      pixelY: pixelY,
    );
  }

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

// Validate at the last write boundary as well as at the UI event boundary.
// The base controller can await clipboard data or retain a key callback while
// ownership changes. Every such continuation still uses this revocable sink.
final class _RevocableInputSink implements terminal.TerminalProtocolInputSink {
  _RevocableInputSink(
    this.delegate,
    this.readOnly, {
    bool Function()? readOnlyFocusLoss,
  }) : readOnlyFocusLoss = readOnlyFocusLoss ?? readOnly;

  final terminal.TerminalInputSink delegate;
  final bool Function() readOnly;
  final bool Function() readOnlyFocusLoss;

  @override
  void sendInput(String sessionId, Uint8List bytes) {
    if (!readOnly()) delegate.sendInput(sessionId, bytes);
  }

  @override
  void sendProtocolInput(String sessionId, Uint8List bytes) {
    // A pane can lose focus after the active session has already changed.
    // Only this exact system report uses the narrower ownership exception;
    // arbitrary protocol bytes and focus-in remain subject to the input gate.
    final isFocusLoss =
        bytes.length == 3 &&
        bytes[0] == 0x1b &&
        bytes[1] == 0x5b &&
        bytes[2] == 0x4f;
    if (isFocusLoss ? readOnlyFocusLoss() : readOnly()) return;
    final sink = delegate;
    if (sink is terminal.TerminalProtocolInputSink) {
      sink.sendProtocolInput(sessionId, bytes);
    } else {
      sink.sendInput(sessionId, bytes);
    }
  }
}

terminal.TerminalEmulation _resolveEmulation(Object emulation) {
  return switch (emulation) {
    final terminal.TerminalEmulation value => value,
    _ => throw FlutterError(
      'Unsupported terminal emulation type: ${emulation.runtimeType}',
    ),
  };
}
