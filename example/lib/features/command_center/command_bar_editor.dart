import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum CommandBarEditorBlockedReason { readOnly, emptyCommand }

class CommandBarEditorController {
  CommandBarEditorController({String text = ''})
    : textEditingController = TextEditingController(text: text);

  final TextEditingController textEditingController;

  String get text => textEditingController.text;

  TextEditingValue get value => textEditingController.value;

  set value(TextEditingValue value) {
    textEditingController.value = value;
  }

  bool get hasActiveComposing {
    final composing = value.composing;
    return composing.isValid && !composing.isCollapsed;
  }

  void insertText(String text) {
    final current = value;
    final currentText = current.text;
    final selection = current.selection;
    final start = selection.isValid
        ? selection.start.clamp(0, currentText.length).toInt()
        : currentText.length;
    final end = selection.isValid
        ? selection.end.clamp(0, currentText.length).toInt()
        : currentText.length;
    final replaceStart = start < end ? start : end;
    final replaceEnd = start < end ? end : start;
    final nextText = currentText.replaceRange(replaceStart, replaceEnd, text);
    final nextOffset = replaceStart + text.length;
    value = current.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
      composing: TextRange.empty,
    );
  }

  void insertNewline() {
    insertText('\n');
  }

  void clear() {
    textEditingController.clear();
  }

  void dispose() {
    textEditingController.dispose();
  }
}

class CommandBarEditorHost extends StatelessWidget {
  const CommandBarEditorHost({
    required this.visible,
    required this.controller,
    required this.onSend,
    required this.child,
    this.readOnly = false,
    this.onBlocked,
    super.key,
  });

  final bool visible;
  final CommandBarEditorController controller;
  final ValueChanged<String> onSend;
  final Widget child;
  final bool readOnly;
  final ValueChanged<CommandBarEditorBlockedReason>? onBlocked;

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return child;
    }
    return Stack(
      children: [
        child,
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: CommandBarEditor(
                controller: controller,
                onSend: onSend,
                readOnly: readOnly,
                onBlocked: onBlocked,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class CommandBarEditor extends StatefulWidget {
  const CommandBarEditor({
    required this.controller,
    required this.onSend,
    this.readOnly = false,
    this.onBlocked,
    super.key,
  });

  final CommandBarEditorController controller;
  final ValueChanged<String> onSend;
  final bool readOnly;
  final ValueChanged<CommandBarEditorBlockedReason>? onBlocked;

  @override
  State<CommandBarEditor> createState() => _CommandBarEditorState();
}

class _CommandBarEditorState extends State<CommandBarEditor> {
  @override
  void initState() {
    super.initState();
    widget.controller.textEditingController.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(covariant CommandBarEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.textEditingController.removeListener(
        _handleTextChanged,
      );
      widget.controller.textEditingController.addListener(_handleTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.textEditingController.removeListener(_handleTextChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final canSend = _canSend;

    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: Material(
        key: const Key('command-bar-editor'),
        color: colorScheme.surfaceContainerHigh,
        elevation: 3,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 168),
                  child: TextField(
                    key: const Key('command-bar-editor-field'),
                    controller: widget.controller.textEditingController,
                    autofocus: true,
                    minLines: 1,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.terminal),
                      hintText: 'Command',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      isDense: true,
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const Key('command-bar-editor-send'),
                tooltip: 'Send',
                onPressed: canSend ? _submit : null,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _canSend {
    return !widget.readOnly &&
        !widget.controller.hasActiveComposing &&
        widget.controller.text.trim().isNotEmpty;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final isEnter =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) {
      return KeyEventResult.handled;
    }
    if (widget.controller.hasActiveComposing) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      widget.controller.insertNewline();
      return KeyEventResult.handled;
    }
    _submit();
    return KeyEventResult.handled;
  }

  void _submit() {
    if (widget.readOnly) {
      widget.onBlocked?.call(CommandBarEditorBlockedReason.readOnly);
      return;
    }
    final text = widget.controller.text;
    if (text.trim().isEmpty) {
      widget.onBlocked?.call(CommandBarEditorBlockedReason.emptyCommand);
      return;
    }
    widget.onSend(text);
    widget.controller.clear();
  }

  void _handleTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }
}
