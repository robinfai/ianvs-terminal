import 'package:flutter/material.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart' as terminal;

import '../profiles/profile_models.dart';
import 'selection_controller.dart';
import 'terminal_input_controller.dart';

export 'package:flutterm_terminal/flutterm_terminal.dart'
    hide
        SelectionController,
        TerminalCursorShape,
        TerminalEmulation,
        TerminalInputController,
        TerminalOptionDragMode,
        TerminalViewport,
        TerminalViewportColors,
        TerminalViewportController,
        terminalFallbackCellSize,
        terminalScrollbarThumbKey,
        terminalScrollbarTrackKey,
        terminalViewportColorFromHex,
        terminalViewportHexFromColor;

typedef TerminalViewportController = terminal.TerminalViewportController;

const Key terminalScrollbarTrackKey = terminal.terminalScrollbarTrackKey;
const Key terminalScrollbarThumbKey = terminal.terminalScrollbarThumbKey;
const Size terminalFallbackCellSize = terminal.terminalFallbackCellSize;

class TerminalViewport extends StatelessWidget {
  const TerminalViewport({
    super.key,
    required this.controller,
    required this.selectionController,
    required this.inputController,
    required this.onScrollLines,
    required this.onScrollToOffset,
    this.onMeasuredCellSizeChanged,
    this.contentPadding = EdgeInsets.zero,
    this.colors,
    this.backgroundColor,
    this.foregroundColor,
    this.font = const TerminalProfileFont(),
    this.cursor = const TerminalProfileCursor(),
    this.copyOnSelect = false,
    this.optionDragMode = TerminalOptionDragMode.blockSelection,
    this.focusNode,
    this.onOpenLink,
  });

  final TerminalViewportController controller;
  final SelectionController selectionController;
  final TerminalInputController inputController;
  final ValueChanged<int> onScrollLines;
  final ValueChanged<int> onScrollToOffset;
  final ValueChanged<Size>? onMeasuredCellSizeChanged;
  final EdgeInsets contentPadding;
  final terminal.TerminalViewportColors? colors;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Object font;
  final Object cursor;
  final bool copyOnSelect;
  final Object optionDragMode;
  final FocusNode? focusNode;
  final ValueChanged<String>? onOpenLink;

  @override
  Widget build(BuildContext context) {
    return terminal.TerminalViewport(
      controller: controller,
      selectionController: selectionController,
      inputController: inputController,
      onScrollLines: onScrollLines,
      onScrollToOffset: onScrollToOffset,
      onMeasuredCellSizeChanged: onMeasuredCellSizeChanged,
      contentPadding: contentPadding,
      colors: colors,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      font: _resolveFont(font),
      cursor: _resolveCursor(cursor),
      copyOnSelect: copyOnSelect,
      optionDragMode: _resolveDragMode(optionDragMode),
      focusNode: focusNode,
      onOpenLink: onOpenLink,
    );
  }
}

terminal.TerminalFontConfig _resolveFont(Object font) {
  return switch (font) {
    TerminalProfileFont value => value.toTerminalFontConfig(),
    terminal.TerminalFontConfig value => value,
    _ => throw FlutterError('Unsupported terminal font type: ${font.runtimeType}'),
  };
}

terminal.TerminalCursorConfig _resolveCursor(Object cursor) {
  return switch (cursor) {
    TerminalProfileCursor value => value.toTerminalCursorConfig(),
    terminal.TerminalCursorConfig value => value,
    _ =>
      throw FlutterError('Unsupported terminal cursor type: ${cursor.runtimeType}'),
  };
}

terminal.TerminalOptionDragMode _resolveDragMode(Object mode) {
  return switch (mode) {
    TerminalOptionDragMode.normalSelection =>
      terminal.TerminalOptionDragMode.normalSelection,
    TerminalOptionDragMode.blockSelection =>
      terminal.TerminalOptionDragMode.blockSelection,
    terminal.TerminalOptionDragMode value => value,
    _ =>
      throw FlutterError('Unsupported terminal drag mode type: ${mode.runtimeType}'),
  };
}
