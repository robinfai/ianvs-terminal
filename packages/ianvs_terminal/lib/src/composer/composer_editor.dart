import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Keeps predictions out of the editable document, selection and semantics.
/// The foreground painter shares the editor's actual metrics and scroll offset.
class ComposerEditor extends StatefulWidget {
  const ComposerEditor({
    required this.controller,
    required this.focusNode,
    required this.suggestion,
    required this.style,
    required this.suggestionColor,
    required this.hint,
    required this.maxLines,
    required this.autofocus,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String suggestion;
  final TextStyle style;
  final Color suggestionColor;
  final String hint;
  final int maxLines;
  final bool autofocus;

  @override
  State<ComposerEditor> createState() => ComposerEditorState();
}

class ComposerEditorState extends State<ComposerEditor> {
  final GlobalKey _fieldKey = GlobalKey();
  final GlobalKey _paintKey = GlobalKey();
  final _scroll = ScrollController();

  RenderEditable? _editable() {
    RenderEditable? result;
    void visit(RenderObject object) {
      if (object is RenderEditable) {
        result = object;
      } else if (result == null) {
        object.visitChildren(visit);
      }
    }

    final object = _fieldKey.currentContext?.findRenderObject();
    if (object != null) visit(object);
    return result;
  }

  bool get onFirstVisualLine {
    final selection = widget.controller.selection;
    final editable = _editable();
    return selection.isValid &&
        selection.isCollapsed &&
        editable != null &&
        editable.getLineAtOffset(selection.extent).start == 0;
  }

  bool get hasSingleVisualLine =>
      (_editable()?.getLineAtOffset(const TextPosition(offset: 0)).end ?? -1) >=
      widget.controller.text.length;

  Offset? globalPosition(int offset) {
    final editable = _editable();
    if (editable == null ||
        offset < 0 ||
        offset > widget.controller.text.length) {
      return null;
    }
    return editable.localToGlobal(
      editable.getLocalRectForCaret(TextPosition(offset: offset)).topLeft,
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final strut = StrutStyle.fromTextStyle(widget.style);
      final scaler = MediaQuery.textScalerOf(context);
      var lines = 1;
      if (widget.suggestion.isNotEmpty) {
        final measure = TextPainter(
          text: TextSpan(
            text: widget.controller.text + widget.suggestion,
            style: widget.style,
          ),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          strutStyle: strut,
        )..layout(maxWidth: math.max(0, constraints.maxWidth - 3));
        lines = measure.computeLineMetrics().length.clamp(1, widget.maxLines);
        measure.dispose();
      }
      return CustomPaint(
        key: _paintKey,
        foregroundPainter: _SuggestionPainter(
          controller: widget.controller,
          scroll: _scroll,
          suggestion: widget.suggestion,
          color: widget.suggestionColor,
          editable: _editable,
          container: () =>
              _paintKey.currentContext?.findRenderObject() as RenderBox?,
        ),
        child: KeyedSubtree(
          key: _fieldKey,
          child: TextField(
            key: const Key('composer-editor'),
            controller: widget.controller,
            focusNode: widget.focusNode,
            scrollController: _scroll,
            autofocus: widget.autofocus,
            minLines: lines,
            maxLines: widget.maxLines,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            autocorrect: false,
            enableSuggestions: false,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            style: widget.style,
            strutStyle: strut,
            decoration: InputDecoration(
              hintText: widget.hint,
              hintMaxLines: 1,
              hintStyle: widget.style.copyWith(color: widget.suggestionColor),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      );
    },
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }
}

class _SuggestionPainter extends CustomPainter {
  _SuggestionPainter({
    required this.controller,
    required this.scroll,
    required this.suggestion,
    required this.color,
    required this.editable,
    required this.container,
  }) : super(repaint: Listenable.merge([controller, scroll]));

  final TextEditingController controller;
  final ScrollController scroll;
  final String suggestion;
  final Color color;
  final RenderEditable? Function() editable;
  final RenderBox? Function() container;

  @override
  void paint(Canvas canvas, Size size) {
    final field = editable();
    final parent = container();
    if (suggestion.isEmpty ||
        field == null ||
        parent == null ||
        !field.hasSize) {
      return;
    }
    final origin = field.localToGlobal(Offset.zero, ancestor: parent);
    final style = field.text!.style!;
    final text = TextPainter(
      text: TextSpan(
        style: style,
        children: [
          TextSpan(
            text: controller.text,
            style: const TextStyle(color: Colors.transparent),
          ),
          TextSpan(
            text: suggestion,
            style: TextStyle(color: color),
          ),
        ],
      ),
      textDirection: field.textDirection,
      textAlign: field.textAlign,
      textScaler: field.textScaler,
      strutStyle: field.strutStyle,
      locale: field.locale,
      textWidthBasis: field.textWidthBasis,
      textHeightBehavior: field.textHeightBehavior,
    );
    // RenderEditable reserves one logical pixel plus cursorWidth for its caret.
    final width = math.max(0.0, field.size.width - field.cursorWidth - 1);
    text.layout(minWidth: width, maxWidth: width);
    canvas.save();
    canvas.clipRect(origin & field.size);
    text.paint(
      canvas,
      origin - Offset(0, scroll.hasClients ? scroll.offset : 0),
    );
    canvas.restore();
    text.dispose();
  }

  @override
  bool shouldRepaint(_SuggestionPainter old) => true;
}
