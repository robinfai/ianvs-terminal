import 'package:flutter/material.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart' as terminal;

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
export 'package:flutterm_terminal/flutterm_terminal_debug.dart'
    show
        RenderTerminalViewport,
        TerminalGlyphClass,
        TerminalGlyphPlacementPolicy,
        TerminalResolvedBackgroundSpan,
        TerminalResolvedCell,
        TerminalResolvedStyle,
        TerminalRowTextMetrics;

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
    this.font = const terminal.TerminalFontConfig(),
    this.cursor = const terminal.TerminalCursorConfig(),
    this.copyOnSelect = false,
    this.optionDragMode = terminal.TerminalOptionDragMode.blockSelection,
    this.focusNode,
    this.onHostKeyEvent,
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
  final terminal.TerminalFontConfig font;
  final terminal.TerminalCursorConfig cursor;
  final bool copyOnSelect;
  final terminal.TerminalOptionDragMode optionDragMode;
  final FocusNode? focusNode;
  final KeyEventResult Function(KeyEvent event)? onHostKeyEvent;
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
      font: font,
      cursor: cursor,
      copyOnSelect: copyOnSelect,
      optionDragMode: optionDragMode,
      focusNode: focusNode,
      onHostKeyEvent: onHostKeyEvent,
      onOpenLink: onOpenLink,
    );
  }
}
