import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'composer_theme.dart';
import 'input_intent.dart';

/// An unsent edit. Hosts validate the original task/session and revision before
/// applying it. This result carries no execution permission or submit callback.
@immutable
class ComposerDraftEditResult {
  const ComposerDraftEditResult(this.value, this.intentChoice);
  final TextEditingValue value;
  final InputIntentChoice intentChoice;
}

typedef ComposerDraftIntentResolver =
    InputIntentDecision Function(
      TextEditingValue value,
      InputIntentChoice choice,
    );

Future<ComposerDraftEditResult?> showComposerDraftEditor(
  BuildContext context, {
  required TextEditingValue initialValue,
  required InputIntentChoice initialIntentChoice,
  required ComposerDraftIntentResolver resolveIntent,
  required String targetLabel,
  bool chinese = false,
  bool allowAi = true,
  bool Function()? canChooseCommand,
  bool Function()? isCurrent,
  Listenable? stateChanges,
  TextStyle? textStyle,
}) => Navigator.of(context).push<ComposerDraftEditResult>(
  _ComposerDraftRoute(
    reducedMotion: MediaQuery.disableAnimationsOf(context),
    builder: (_) => ComposerDraftEditor(
      initialValue: initialValue,
      initialIntentChoice: initialIntentChoice,
      resolveIntent: resolveIntent,
      targetLabel: targetLabel,
      chinese: chinese,
      allowAi: allowAi,
      canChooseCommand: canChooseCommand,
      isCurrent: isCurrent,
      stateChanges: stateChanges,
      textStyle: textStyle,
    ),
  ),
);

class _ComposerDraftRoute extends MaterialPageRoute<ComposerDraftEditResult> {
  _ComposerDraftRoute({required super.builder, required this.reducedMotion})
    : super(fullscreenDialog: true);

  final bool reducedMotion;

  @override
  Duration get transitionDuration =>
      reducedMotion ? Duration.zero : ComposerTheme.stateDuration;
  @override
  Duration get reverseTransitionDuration => transitionDuration;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => reducedMotion
      ? child
      : super.buildTransitions(context, animation, secondaryAnimation, child);
}

/// A local, transactional draft editor shared by command and AI inputs.
class ComposerDraftEditor extends StatefulWidget {
  const ComposerDraftEditor({
    required this.initialValue,
    required this.initialIntentChoice,
    required this.resolveIntent,
    required this.targetLabel,
    this.chinese = false,
    this.allowAi = true,
    this.canChooseCommand,
    this.isCurrent,
    this.stateChanges,
    this.textStyle,
    super.key,
  });

  final TextEditingValue initialValue;
  final InputIntentChoice initialIntentChoice;
  final ComposerDraftIntentResolver resolveIntent;
  final String targetLabel;
  final bool chinese;
  final bool allowAi;
  final bool Function()? canChooseCommand;
  final bool Function()? isCurrent;
  final Listenable? stateChanges;
  final TextStyle? textStyle;

  @override
  State<ComposerDraftEditor> createState() => _ComposerDraftEditorState();
}

class _ComposerDraftEditorState extends State<ComposerDraftEditor> {
  late final TextEditingController _editor;
  final _focus = FocusNode(debugLabel: 'Expanded draft');
  late InputIntentChoice _choice;
  String t(String en, String zh) => widget.chinese ? zh : en;
  bool get _current => widget.isCurrent?.call() ?? true;

  @override
  void initState() {
    super.initState();
    _choice = widget.initialIntentChoice;
    _editor = TextEditingController.fromValue(
      widget.initialValue.copyWith(composing: TextRange.empty),
    )..addListener(_changed);
    widget.stateChanges?.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _hideKeyboard() {
    _focus.unfocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
  }

  void _cancel() {
    _hideKeyboard();
    Navigator.of(context).pop();
  }

  void _done() {
    if (!_current || !_editor.value.composing.isCollapsed) return;
    final result = ComposerDraftEditResult(_editor.value, _choice);
    _hideKeyboard();
    Navigator.of(context).pop(result);
  }

  @override
  void dispose() {
    widget.stateChanges?.removeListener(_changed);
    _editor.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ComposerTheme.of(context);
    final decision = widget.resolveIntent(_editor.value, _choice);
    final commandEnabled = widget.canChooseCommand?.call() ?? true;
    final direction = decision.intent == InputIntent.command
        ? t('Command', '命令')
        : 'AI';
    final intentLabel = _choice == InputIntentChoice.automatic
        ? '${t('Auto', '自动')} · $direction'
        : direction;
    final style = widget.textStyle ?? tokens.commandStyle;
    final toolbar = SizedBox(
      height: 48,
      child: Row(
        children: [
          TextButton(
            key: const Key('composer-draft-cancel'),
            style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
            onPressed: _cancel,
            child: Text(t('Cancel', '取消')),
          ),
          Expanded(
            child: Text(
              t('Edit draft', '编辑草稿'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            key: const Key('composer-draft-hide-keyboard'),
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            tooltip: t('Hide keyboard', '收起键盘'),
            onPressed: _hideKeyboard,
            icon: const Icon(Icons.keyboard_hide_outlined),
          ),
          TextButton(
            key: const Key('composer-draft-done'),
            style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
            onPressed: _current && _editor.value.composing.isCollapsed
                ? _done
                : null,
            child: Text(t('Done', '完成编辑')),
          ),
        ],
      ),
    );
    final intent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Flexible(
            child: PopupMenuButton<InputIntentChoice>(
              key: const Key('composer-draft-intent'),
              popUpAnimationStyle: MediaQuery.disableAnimationsOf(context)
                  ? AnimationStyle.noAnimation
                  : const AnimationStyle(duration: ComposerTheme.stateDuration),
              tooltip: t('Input intent', '输入意图'),
              onSelected: (value) => setState(() => _choice = value),
              itemBuilder: (_) => [
                CheckedPopupMenuItem(
                  value: InputIntentChoice.automatic,
                  checked: _choice == InputIntentChoice.automatic,
                  child: Text(t('Automatic', '自动识别')),
                ),
                CheckedPopupMenuItem(
                  value: InputIntentChoice.command,
                  enabled: commandEnabled,
                  checked: _choice == InputIntentChoice.command,
                  child: Text(t('Command', '命令')),
                ),
                if (widget.allowAi)
                  CheckedPopupMenuItem(
                    value: InputIntentChoice.ai,
                    checked: _choice == InputIntentChoice.ai,
                    child: const Text('AI'),
                  ),
              ],
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        intentLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.expand_more),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Tooltip(
              message: widget.targetLabel,
              child: Text(
                widget.targetLabel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: tokens.contextStyle,
              ),
            ),
          ),
        ],
      ),
    );
    final field = Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: TextField(
        key: const Key('composer-draft-editor'),
        controller: _editor,
        focusNode: _focus,
        // In a short window, focusing immediately would scroll the toolbar
        // out of view before the user can cancel or hide the keyboard.
        autofocus:
            MediaQuery.sizeOf(context).height -
                MediaQuery.viewInsetsOf(context).bottom >=
            220,
        expands: true,
        minLines: null,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        textAlignVertical: TextAlignVertical.top,
        autocorrect: false,
        enableSuggestions: false,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        style: style,
        strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: true),
        decoration: InputDecoration(
          hintText: t('Unsent draft', '尚未发送的草稿'),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
    return Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            _editor.value.composing.isCollapsed) {
          _cancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        key: const Key('composer-draft-page'),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, bounds) {
              final short = bounds.maxHeight < 220;
              final content = Column(
                mainAxisSize: short ? MainAxisSize.min : MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  toolbar,
                  intent,
                  if (!_current)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        t(
                          'The original draft changed. Cancel to return to it.',
                          '原草稿已变化。请取消编辑并返回查看。',
                        ),
                        style: tokens.statusStyle.copyWith(color: tokens.error),
                      ),
                    ),
                  if (short)
                    SizedBox(height: 120, child: field)
                  else
                    Expanded(child: field),
                ],
              );
              // Keep the full control targets and direction available even
              // when a landscape keyboard leaves less than one control row.
              return short
                  ? SingleChildScrollView(
                      key: const Key('composer-draft-short-scroll'),
                      child: content,
                    )
                  : content;
            },
          ),
        ),
      ),
    );
  }
}
