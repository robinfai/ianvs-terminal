import 'package:flutter/material.dart';

import '../config/terminal_config.dart';
import 'render_terminal_viewport.dart';
import 'selection_controller.dart';
import 'terminal_models.dart';
import 'terminal_viewport.dart';
import 'terminal_viewport_colors.dart';

class TerminalFramePreview extends StatefulWidget {
  const TerminalFramePreview({
    super.key,
    required this.frame,
    required this.colors,
    this.font = const TerminalFontConfig(),
    this.cursor = const TerminalCursorConfig(),
  });

  final TerminalFrameDiff frame;
  final TerminalViewportColors colors;
  final TerminalFontConfig font;
  final TerminalCursorConfig cursor;

  @override
  State<TerminalFramePreview> createState() => _TerminalFramePreviewState();
}

class _TerminalFramePreviewState extends State<TerminalFramePreview> {
  late final TerminalViewportController _controller;
  late final SelectionController _selectionController;

  @override
  void initState() {
    super.initState();
    _controller = TerminalViewportController();
    _selectionController = SelectionController();
    _controller.applySnapshot(widget.frame);
  }

  @override
  void didUpdateWidget(covariant TerminalFramePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.frame, widget.frame)) {
      _controller.applySnapshot(widget.frame);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _selectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: widget.colors.canvasBackground),
      child: _TerminalFramePreviewSurface(
        controller: _controller,
        selectionController: _selectionController,
        font: widget.font,
        cursor: widget.cursor,
        colors: widget.colors,
      ),
    );
  }
}

class _TerminalFramePreviewSurface extends LeafRenderObjectWidget {
  const _TerminalFramePreviewSurface({
    required this.controller,
    required this.selectionController,
    required this.font,
    required this.cursor,
    required this.colors,
  });

  final TerminalViewportController controller;
  final SelectionController selectionController;
  final TerminalFontConfig font;
  final TerminalCursorConfig cursor;
  final TerminalViewportColors colors;

  @override
  RenderTerminalViewport createRenderObject(BuildContext context) {
    return RenderTerminalViewport(
      controller: controller,
      selectionController: selectionController,
      cursorVisible: false,
      font: font,
      cursor: cursor,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      colors: colors,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderTerminalViewport renderObject,
  ) {
    renderObject
      ..controller = controller
      ..selectionController = selectionController
      ..cursorVisible = false
      ..font = font
      ..cursor = cursor
      ..colors = colors
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  }
}
