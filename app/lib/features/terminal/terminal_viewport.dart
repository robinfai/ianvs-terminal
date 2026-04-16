import 'package:flutter/material.dart';

import 'render_terminal_viewport.dart';
import 'selection_controller.dart';
import 'terminal_input_controller.dart';
import 'terminal_painter_models.dart';

class TerminalViewportController extends ChangeNotifier {
  TerminalFrameDiff _frame = TerminalFrameDiff.empty;

  TerminalFrameDiff get frame => _frame;

  void updateFrame(TerminalFrameDiff value) {
    _frame = value;
    notifyListeners();
  }
}

class TerminalViewport extends StatefulWidget {
  const TerminalViewport({
    super.key,
    required this.controller,
    required this.selectionController,
    required this.inputController,
    required this.onScrollLines,
    this.focusNode,
  });

  final TerminalViewportController controller;
  final SelectionController selectionController;
  final TerminalInputController inputController;
  final ValueChanged<int> onScrollLines;
  final FocusNode? focusNode;

  @override
  State<TerminalViewport> createState() => _TerminalViewportState();
}

class _TerminalViewportState extends State<TerminalViewport> {
  FocusNode? _ownedFocusNode;

  FocusNode get _focusNode =>
      widget.focusNode ??
      (_ownedFocusNode ??= FocusNode(debugLabel: 'terminal-viewport'));

  @override
  void dispose() {
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      focusNode: _focusNode,
      onKeyEvent: (_, event) => widget.inputController.handle(event),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _focusNode.requestFocus,
        child: _TerminalViewportSurface(
          controller: widget.controller,
          selectionController: widget.selectionController,
          onScrollLines: widget.onScrollLines,
        ),
      ),
    );
  }
}

class _TerminalViewportSurface extends LeafRenderObjectWidget {
  const _TerminalViewportSurface({
    required this.controller,
    required this.selectionController,
    required this.onScrollLines,
  });

  final TerminalViewportController controller;
  final SelectionController selectionController;
  final ValueChanged<int> onScrollLines;

  @override
  RenderTerminalViewport createRenderObject(BuildContext context) {
    return RenderTerminalViewport(
      controller: controller,
      selectionController: selectionController,
      onScrollLines: onScrollLines,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
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
      ..onScrollLines = onScrollLines
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  }
}
