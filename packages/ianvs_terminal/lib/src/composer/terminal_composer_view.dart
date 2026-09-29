import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'completion_models.dart';
import 'terminal_composer_controller.dart';

/// Semantic tokens derived from the host ColorScheme. No product palette is
/// embedded in the editor; the host's light/dark/high-contrast theme wins.
@immutable
final class ComposerTheme {
  const ComposerTheme({
    required this.surface,
    required this.border,
    required this.foreground,
    required this.muted,
    required this.accent,
    required this.chip,
    required this.selection,
  });
  factory ComposerTheme.of(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ComposerTheme(
      surface: colors.surfaceContainerLow,
      border: colors.outlineVariant,
      foreground: colors.onSurface,
      muted: colors.onSurfaceVariant,
      accent: colors.primary,
      chip: colors.surfaceContainerHighest,
      selection: colors.secondaryContainer,
    );
  }
  static const radius = 12.0;
  static const gap = 8.0;
  static const inset = 12.0;
  static const controlExtent = 32.0;
  final Color surface;
  final Color border;
  final Color foreground;
  final Color muted;
  final Color accent;
  final Color chip;
  final Color selection;
}

/// Compact, docked command editor inspired by Warp Universal Input.
class TerminalComposerView extends StatefulWidget {
  const TerminalComposerView({
    required this.controller,
    required this.targetLabel,
    required this.onUseTerminal,
    this.focusNode,
    this.autofocus = false,
    this.chinese = false,
    this.maxLines = 6,
    super.key,
  });
  final TerminalComposerController controller;
  final String targetLabel;
  final VoidCallback onUseTerminal;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool chinese;
  final int maxLines;

  @override
  State<TerminalComposerView> createState() => _TerminalComposerViewState();
}

class _TerminalComposerViewState extends State<TerminalComposerView> {
  final _overlay = OverlayPortalController();
  final _link = LayerLink();
  final _scroll = ScrollController();
  late FocusNode _focus;
  double _width = 320;
  TerminalComposerController get model => widget.controller;
  String tr(String en, String zh) => widget.chinese ? zh : en;

  @override
  void initState() {
    super.initState();
    _focus = widget.focusNode ?? FocusNode(debugLabel: 'Composer');
    _focus.addListener(_changed);
    model.addListener(_changed);
  }

  @override
  void didUpdateWidget(TerminalComposerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _focus.removeListener(_changed);
      if (oldWidget.focusNode == null) _focus.dispose();
      _focus = widget.focusNode ?? FocusNode(debugLabel: 'Composer');
      _focus.addListener(_changed);
    }
    if (oldWidget.controller != model) {
      oldWidget.controller.removeListener(_changed);
      model.addListener(_changed);
    }
  }

  void _changed() {
    if (!mounted) return;
    final show =
        _focus.hasFocus &&
        model.items.isNotEmpty &&
        model.editor.value.composing.isCollapsed;
    if (show && !_overlay.isShowing) _overlay.show();
    if (!show && _overlay.isShowing) _overlay.hide();
    setState(() {});
    final index = model.selectedIndex;
    if (index >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _revealSelection();
        }
      });
    }
  }

  double _candidateExtent(CompletionEdit item) {
    final scaler = MediaQuery.textScalerOf(context);
    final detail = item.detail.replaceAll(RegExp(r'[\x00-\x1f\x7f-\x9f]'), '');
    final textHeight =
        scaler.scale(13) * 1.4 + (detail.isEmpty ? 0 : scaler.scale(11) * 1.4);
    return (14 + textHeight.clamp(16, double.infinity)).ceilToDouble();
  }

  void _revealSelection() {
    final index = model.selectedIndex;
    if (index < 0) return;
    var top = 4.0;
    for (final item in model.items.take(index)) {
      top += _candidateExtent(item);
    }
    final bottom = top + _candidateExtent(model.items[index]);
    final position = _scroll.position;
    final target = top < position.pixels
        ? top
        : bottom > position.pixels + position.viewportDimension
        ? bottom - position.viewportDimension
        : position.pixels;
    _scroll.jumpTo(target.clamp(0, position.maxScrollExtent));
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final hardware = HardwareKeyboard.instance;
    final composing = !model.editor.value.composing.isCollapsed;
    if (composing) return KeyEventResult.ignored;
    final command =
        hardware.isMetaPressed ||
        (defaultTargetPlatform != TargetPlatform.macOS &&
            hardware.isControlPressed);
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) {
        if (hardware.isShiftPressed) {
          model.insertNewline();
        } else if (model.selectedIndex >= 0) {
          model.accept();
        } else {
          unawaited(model.run());
        }
      }
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (command && key == LogicalKeyboardKey.keyZ) {
      hardware.isShiftPressed ? model.redo() : model.undo();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      if (hardware.isShiftPressed) {
        FocusScope.of(context).previousFocus();
      } else if (model.selectedIndex >= 0) {
        model.accept();
      } else if (model.items.isNotEmpty) {
        model.selectNext(1);
      } else {
        model.requestCompletions();
      }
      return KeyEventResult.handled;
    }
    if (model.items.isNotEmpty &&
        (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowUp)) {
      model.selectNext(key == LogicalKeyboardKey.arrowDown ? 1 : -1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (model.items.isNotEmpty) {
        model.dismissCompletions();
      } else if (!model.editor.selection.isCollapsed) {
        model.editor.selection = TextSelection.collapsed(
          offset: model.editor.selection.extentOffset,
        );
      } else {
        widget.onUseTerminal();
      }
      return KeyEventResult.handled;
    }
    if (hardware.isControlPressed && key == LogicalKeyboardKey.keyC) {
      model.editor.clear();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ComposerTheme.of(context);
    final ready = model.ownership == ComposerOwnership.ready;
    final status = switch (model.ownership) {
      ComposerOwnership.ready => tr('Ready', '就绪'),
      ComposerOwnership.submitting => tr('Sending…', '发送中…'),
      ComposerOwnership.running => tr('Running', '运行中'),
      ComposerOwnership.unknown => tr(
        'Check terminal before retrying',
        '执行结果未知，请先检查终端',
      ),
      ComposerOwnership.suspended => tr('Terminal has input', '终端正在接收输入'),
      ComposerOwnership.draft => tr('Draft', '草稿'),
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        final compact = constraints.maxWidth < 450;
        return CompositedTransformTarget(
          link: _link,
          child: OverlayPortal(
            controller: _overlay,
            overlayChildBuilder: (context) => Positioned(
              width: _width,
              child: CompositedTransformFollower(
                link: _link,
                showWhenUnlinked: false,
                targetAnchor: Alignment.topLeft,
                followerAnchor: Alignment.bottomLeft,
                offset: const Offset(0, -6),
                child: _candidates(tokens),
              ),
            ),
            child: Material(
              color: tokens.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ComposerTheme.radius),
                side: BorderSide(
                  color: _focus.hasFocus
                      ? tokens.accent.withValues(alpha: .65)
                      : tokens.border,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(ComposerTheme.inset),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: _chip(
                            Icons.computer_outlined,
                            widget.targetLabel,
                            tokens,
                          ),
                        ),
                        if (model.cwd.isNotEmpty) ...[
                          const SizedBox(width: ComposerTheme.gap),
                          Flexible(
                            flex: 3,
                            child: _chip(
                              Icons.folder_open_rounded,
                              model.cwd,
                              tokens,
                            ),
                          ),
                        ],
                        const SizedBox(width: ComposerTheme.gap),
                        Tooltip(
                          message: status,
                          child: Icon(
                            ready
                                ? Icons.check_circle_outline_rounded
                                : Icons.edit_note_rounded,
                            size: 14,
                            color: ready ? tokens.accent : tokens.muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Focus(
                      onKeyEvent: _key,
                      child: TextField(
                        key: const Key('composer-editor'),
                        controller: model.editor,
                        focusNode: _focus,
                        autofocus: widget.autofocus,
                        minLines: 1,
                        maxLines: widget.maxLines,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        autocorrect: false,
                        enableSuggestions: false,
                        smartDashesType: SmartDashesType.disabled,
                        smartQuotesType: SmartQuotesType.disabled,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 14,
                          height: 1.5,
                          color: tokens.foreground,
                        ),
                        decoration: InputDecoration(
                          hintText: tr('Type a command…', '输入命令…'),
                          hintStyle: TextStyle(color: tokens.muted),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: compact
                                ? constraints.maxWidth * .22
                                : 140,
                          ),
                          child: _chip(
                            Icons.terminal_rounded,
                            tr('Terminal', '命令'),
                            tokens,
                            accented: true,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _button(
                          Icons.keyboard_return_rounded,
                          tr('Use terminal · Esc', '传统输入 · Esc'),
                          widget.onUseTerminal,
                        ),
                        _button(
                          Icons.copy_outlined,
                          tr(
                            'Copy draft · kept only in this session',
                            '复制草稿 · 仅保留于当前会话',
                          ),
                          model.editor.text.isEmpty
                              ? null
                              : () => unawaited(
                                  Clipboard.setData(
                                    ClipboardData(text: model.editor.text),
                                  ),
                                ),
                        ),
                        _button(
                          model.localSuggestions
                              ? Icons.folder_rounded
                              : Icons.folder_outlined,
                          model.localSuggestions
                              ? tr(
                                  'Disable local file and script suggestions',
                                  '关闭本地文件与脚本补全',
                                )
                              : tr(
                                  'Enable local suggestions · reads current folder and package.json',
                                  '启用本地补全 · 读取当前目录与 package.json',
                                ),
                          model.toggleLocalSuggestions,
                          filled: model.localSuggestions,
                        ),
                        if (!compact)
                          _button(
                            Icons.undo_rounded,
                            tr('Undo', '撤销'),
                            model.canUndo ? model.undo : null,
                          ),
                        if (!compact) ...[
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              tr(
                                '⇧ Enter newline  ·  Tab complete',
                                '⇧ Enter 换行  ·  Tab 补全',
                              ),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: tokens.muted,
                              ),
                            ),
                          ),
                        ] else
                          const Spacer(),
                        _button(
                          Icons.arrow_upward_rounded,
                          model.canRun
                              ? tr('Run command · Enter', '执行命令 · Enter')
                              : model.ownership == ComposerOwnership.ready
                              ? tr(
                                  'Finish entering a command to run',
                                  '请输入完整命令后执行',
                                )
                              : tr(
                                  'A ready shell is required to run',
                                  '当前 shell 未就绪，可编辑或复制草稿',
                                ),
                          model.canRun ? () => unawaited(model.run()) : null,
                          filled: true,
                        ),
                      ],
                    ),
                    if (model.status.isNotEmpty ||
                        model.ownership == ComposerOwnership.unknown)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _statusText(),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: tokens.muted,
                                ),
                              ),
                            ),
                            if (model.pendingSubmission != null)
                              TextButton(
                                onPressed: model.recoverDraft,
                                child: Text(tr('Recover draft', '恢复草稿')),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _statusText() => switch (model.status) {
    'unknown_outcome' => tr(
      'Execution could not be confirmed. Check the terminal before retrying.',
      '执行结果无法确认。请检查终端后再决定是否重试。',
    ),
    'submission_rejected' => tr(
      'The shell declined the command. Your draft is preserved.',
      'Shell 未接收命令，草稿已保留。',
    ),
    'completion_unavailable' => tr(
      'Completions unavailable. You can continue editing.',
      '补全暂不可用，可继续编辑。',
    ),
    'unsupported_context' => tr(
      'No completions for this shell expression.',
      '此 shell 表达式暂不提供补全。',
    ),
    _ => '',
  };

  Widget _button(
    IconData icon,
    String tooltip,
    VoidCallback? onPressed, {
    bool filled = false,
  }) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 17, semanticLabel: tooltip),
    style: IconButton.styleFrom(
      minimumSize: const Size.square(ComposerTheme.controlExtent),
      maximumSize: const Size.square(ComposerTheme.controlExtent),
      padding: EdgeInsets.zero,
      backgroundColor: filled && onPressed != null
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
  );

  Widget _chip(
    IconData icon,
    String label,
    ComposerTheme tokens, {
    bool accented = false,
  }) => Tooltip(
    message: label,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: accented ? tokens.selection : tokens.chip.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: accented ? tokens.accent : tokens.muted),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                color: tokens.foreground,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _candidates(ComposerTheme tokens) => Material(
    elevation: 8,
    color: tokens.surface,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: tokens.border),
    ),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: (MediaQuery.sizeOf(context).height * .3).clamp(80, 260),
      ),
      child: ListView.builder(
        controller: _scroll,
        itemExtentBuilder: (index, _) => _candidateExtent(model.items[index]),
        shrinkWrap: true,
        padding: const EdgeInsets.all(4),
        itemCount: model.items.length,
        itemBuilder: (context, index) {
          final item = model.items[index];
          return _candidate(item, index, tokens);
        },
      ),
    ),
  );

  Widget _candidate(CompletionEdit item, int index, ComposerTheme tokens) {
    final selected = model.selectedIndex == index;
    final safeLabel = item.label.replaceAll(
      RegExp(r'[\x00-\x1f\x7f-\x9f]'),
      '',
    );
    final safeDetail = item.detail.replaceAll(
      RegExp(r'[\x00-\x1f\x7f-\x9f]'),
      '',
    );
    return Semantics(
      selected: selected,
      label: '$safeLabel, ${item.source}, ${index + 1}/${model.items.length}',
      child: InkWell(
        canRequestFocus: false,
        onTap: () {
          model.accept(item);
          _focus.requestFocus();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? tokens.selection : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(
                item.riskHint
                    ? Icons.warning_amber_rounded
                    : Icons.code_rounded,
                size: 16,
                color: tokens.muted,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      safeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        height: 1.4,
                        color: tokens.foreground,
                      ),
                    ),
                    if (safeDetail.isNotEmpty)
                      Text(
                        safeDetail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          color: tokens.muted,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                item.kind,
                style: TextStyle(fontSize: 10, color: tokens.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    model.removeListener(_changed);
    _focus.removeListener(_changed);
    if (widget.focusNode == null) _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }
}
