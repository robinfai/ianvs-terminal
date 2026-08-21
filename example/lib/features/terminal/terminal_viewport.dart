import 'package:flutter/material.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;

import '../../l10n/l10n.dart';
import 'selection_controller.dart';
import 'terminal_input_controller.dart';

export 'package:ianvs_terminal/ianvs_terminal.dart'
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
export 'package:ianvs_terminal/ianvs_terminal_debug.dart'
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
    this.useFrameDefaultColors = true,
    this.font = const terminal.TerminalFontConfig(),
    this.cursor = const terminal.TerminalCursorConfig(),
    this.copyOnSelect = false,
    this.showLineTimestamps = false,
    this.optionDragMode = terminal.TerminalOptionDragMode.blockSelection,
    this.focusNode,
    this.onHostKeyEvent,
    this.onOpenLink,
    this.onOpenLinkTarget,
    this.onLinkHoverChanged,
    this.onLinkContextMenu,
    this.onPasteClipboard,
    this.searchMatches = const [],
    this.activeSearchMatchIndex = -1,
    this.searchHighlightStyle,
    this.graphicsCache,
    this.onSaveGraphicImage,
    this.onCopyGraphicImage,
    this.benchmarkEventSink,
    this.graphicsDiagnosticSessionId,
    this.onToggleBlock,
    this.onDismissBlockRender,
    this.onActivateInlineButton,
    this.inlineButtonEnabled,
    this.onScaleStart,
    this.onScaleUpdate,
    this.onScaleEnd,
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
  final bool useFrameDefaultColors;
  final terminal.TerminalFontConfig font;
  final terminal.TerminalCursorConfig cursor;
  final bool copyOnSelect;
  final bool showLineTimestamps;
  final terminal.TerminalOptionDragMode optionDragMode;
  final FocusNode? focusNode;
  final KeyEventResult Function(KeyEvent event)? onHostKeyEvent;
  final ValueChanged<String>? onOpenLink;
  final ValueChanged<terminal.TerminalLinkTarget>? onOpenLinkTarget;
  final ValueChanged<terminal.TerminalLinkTarget?>? onLinkHoverChanged;
  final ValueChanged<terminal.TerminalLinkTarget>? onLinkContextMenu;
  final Future<void> Function()? onPasteClipboard;
  final List<terminal.TerminalSearchMatch> searchMatches;
  final int activeSearchMatchIndex;
  final terminal.TerminalSearchHighlightStyle? searchHighlightStyle;
  final terminal.TerminalGraphicsCache? graphicsCache;
  final terminal.TerminalGraphicImageCallback? onSaveGraphicImage;
  final terminal.TerminalGraphicImageCallback? onCopyGraphicImage;
  final terminal.TerminalBenchmarkEventSink? benchmarkEventSink;
  final String? graphicsDiagnosticSessionId;
  final ValueChanged<terminal.TerminalBlock>? onToggleBlock;
  final ValueChanged<terminal.TerminalBlock>? onDismissBlockRender;
  final ValueChanged<terminal.TerminalInlineButton>? onActivateInlineButton;
  final bool Function(terminal.TerminalInlineButton button)?
  inlineButtonEnabled;
  final GestureScaleStartCallback? onScaleStart;
  final GestureScaleUpdateCallback? onScaleUpdate;
  final GestureScaleEndCallback? onScaleEnd;

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
      useFrameDefaultColors: useFrameDefaultColors,
      font: font,
      cursor: cursor,
      copyOnSelect: copyOnSelect,
      showLineTimestamps: showLineTimestamps,
      optionDragMode: optionDragMode,
      focusNode: focusNode,
      onHostKeyEvent: onHostKeyEvent,
      onOpenLink: onOpenLink,
      onOpenLinkTarget: onOpenLinkTarget,
      onLinkHoverChanged: onLinkHoverChanged,
      onLinkContextMenu: onLinkContextMenu,
      onPasteClipboard: onPasteClipboard,
      searchMatches: searchMatches,
      activeSearchMatchIndex: activeSearchMatchIndex,
      searchHighlightStyle: searchHighlightStyle,
      graphicsCache: graphicsCache,
      onSaveGraphicImage: onSaveGraphicImage,
      onCopyGraphicImage: onCopyGraphicImage,
      benchmarkEventSink: benchmarkEventSink,
      graphicsDiagnosticSessionId: graphicsDiagnosticSessionId,
      onToggleBlock: onToggleBlock,
      onDismissBlockRender: onDismissBlockRender,
      onActivateInlineButton: onActivateInlineButton,
      inlineButtonEnabled: inlineButtonEnabled,
      onScaleStart: onScaleStart,
      onScaleUpdate: onScaleUpdate,
      onScaleEnd: onScaleEnd,
      strings: terminal.TerminalViewportStrings(
        saveImageAs: context.l10n.saveImageAs,
        copyImage: context.l10n.copyImage,
        openImage: context.l10n.openImage,
        inspect: context.l10n.inspect,
        imageInformation: context.l10n.imageInformation,
        protocol: context.l10n.protocol,
        sourceSize: context.l10n.sourceSize,
        displaySize: context.l10n.displaySize,
        visibleArea: context.l10n.visibleArea,
        cellPosition: context.l10n.cellPosition,
        renderId: context.l10n.renderId,
        placementId: context.l10n.placementId,
        asset: context.l10n.asset,
        close: context.l10n.close,
        unfoldTerminalBlock: context.l10n.unfoldTerminalBlock,
        foldTerminalBlock: context.l10n.foldTerminalBlock,
        unfoldBlock: context.l10n.unfoldBlock,
        foldBlock: context.l10n.foldBlock,
        renderedTerminalDocument: context.l10n.renderedTerminalDocument,
        closeRenderedDocument: context.l10n.closeRenderedDocument,
        closeTerminalTextDocument: context.l10n.closeTerminalTextDocument,
        openTerminalImagePreview: context.l10n.openTerminalImagePreview,
        terminalImagePreview: context.l10n.terminalImagePreview,
        closeImagePreview: context.l10n.closeImagePreview,
      ),
    );
  }
}
