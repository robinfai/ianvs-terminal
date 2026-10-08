import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'composer_draft_editor.dart';
import 'composer_editor.dart';
import 'composer_icons.dart';
import 'composer_suggestions.dart';
import 'composer_theme.dart';
import 'input_intent.dart';
import 'terminal_composer_controller.dart';

export 'composer_icons.dart' show ComposerIcons;
export 'composer_theme.dart' show ComposerTheme;

/// Compact, docked command editor inspired by Warp Universal Input.
class TerminalComposerView extends StatefulWidget {
  const TerminalComposerView({
    required this.controller,
    required this.targetLabel,
    this.onUseTerminal,
    this.focusNode,
    this.autofocus = false,
    this.chinese = false,
    this.maxLines = 6,
    this.onNavigateBlocks,
    this.onAskAi,
    this.onOpenAi,
    this.isNaturalLanguage,
    super.key,
  });
  final TerminalComposerController controller;
  final String targetLabel;
  final VoidCallback? onUseTerminal;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool chinese;
  final int maxLines;
  final bool Function(int delta)? onNavigateBlocks;
  final ValueChanged<String>? onAskAi;
  final VoidCallback? onOpenAi;
  final bool Function(String)? isNaturalLanguage;

  @override
  State<TerminalComposerView> createState() => _TerminalComposerViewState();
}

class _TerminalComposerViewState extends State<TerminalComposerView> {
  final _overlay = OverlayPortalController();
  final _resultsFocus = FocusNode(debugLabel: 'Composer result details');
  final _scroll = ScrollController();
  final _editorKey = GlobalKey<ComposerEditorState>();
  final GlobalKey _anchorKey = GlobalKey();
  late FocusNode _focus;
  double _width = 320;
  double _availableHeight = double.infinity;
  bool _draftEditorOpen = false;
  String _copyFeedback = '';
  bool get _asksAi =>
      widget.onAskAi != null &&
      !model.historyOpen &&
      model.selectedIndex < 0 &&
      (model.inputIntent.choice == InputIntentChoice.automatic &&
              widget.isNaturalLanguage != null
          ? widget.isNaturalLanguage!(model.editor.text)
          : model.intentDecision.intent == InputIntent.ai);

  void _performPrimary() {
    if (_asksAi && model.canPerformPrimaryAction) {
      model.dismissCompletions();
      widget.onAskAi!(model.editor.text);
      model.chooseInputIntent(InputIntentChoice.automatic);
    } else {
      unawaited(model.performPrimaryAction());
    }
  }

  Future<void> _expandDraft() async {
    if (_disabled || _draftEditorOpen) return;
    final owner = model;
    owner.dismissHistory();
    owner.dismissCompletions();
    owner.editor.value = owner.editor.value.copyWith(
      composing: TextRange.empty,
    );
    _focus.unfocus();
    final original = owner.snapshot;
    final choice = owner.inputIntent.choice;
    bool current() =>
        mounted &&
        identical(model, owner) &&
        !_disabled &&
        owner.snapshot.contextRevision == original.contextRevision &&
        owner.snapshot.editorRevision == original.editorRevision &&
        owner.editor.value == original.value &&
        owner.inputIntent.choice == choice;
    _draftEditorOpen = true;
    try {
      final result = await showComposerDraftEditor(
        context,
        initialValue: original.value,
        initialIntentChoice: choice,
        resolveIntent: (value, intent) {
          if (intent == InputIntentChoice.automatic &&
              widget.isNaturalLanguage != null &&
              widget.onAskAi != null) {
            return InputIntentDecision(
              widget.isNaturalLanguage!(value.text)
                  ? InputIntent.ai
                  : InputIntent.command,
              'host',
            );
          }
          return owner.previewInputIntent(value, intent);
        },
        targetLabel: '${widget.targetLabel} · ${owner.cwd}',
        chinese: widget.chinese,
        allowAi: widget.onAskAi != null,
        isCurrent: current,
        stateChanges: owner,
      );
      if (result != null && current()) {
        owner.editor.value = result.value;
        owner.chooseInputIntent(result.intentChoice);
      }
    } finally {
      _draftEditorOpen = false;
      if (mounted) _focus.unfocus();
    }
  }

  Widget _expandButton(ComposerTheme tokens) => IconButton(
    key: const Key('composer-expand-draft'),
    tooltip: tr('Expand editor', '展开编辑'),
    color: tokens.muted,
    onPressed: _disabled ? null : _expandDraft,
    icon: const Icon(Icons.open_in_full),
  );

  Widget _historyButton(ComposerTheme tokens) => IconButton(
    key: const Key('composer-history-toggle'),
    tooltip: tr('Command history', '命令历史'),
    color: tokens.muted,
    isSelected: model.historyOpen,
    onPressed: !model.canOpenHistory
        ? null
        : () {
            model.toggleHistory();
            _focus.requestFocus();
          },
    icon: const Icon(ComposerIcons.history),
  );

  Widget _hideKeyboardButton(ComposerTheme tokens) => IconButton(
    key: const Key('composer-dismiss-keyboard'),
    tooltip: tr('Hide keyboard', '收起键盘'),
    color: tokens.muted,
    onPressed: () {
      _focus.unfocus();
      unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
    },
    icon: const Icon(Icons.keyboard_hide_outlined),
  );

  Timer? _feedbackTimer;
  int _selectionNavigationRevision = -1;
  double? _busyHeight;
  (double, Size, TextScaler)? _layoutSize;
  TerminalComposerController get model => widget.controller;
  bool get _disabled => switch (model.ownership) {
    ComposerOwnership.submitting ||
    ComposerOwnership.running ||
    ComposerOwnership.suspended => true,
    _ => false,
  };
  String tr(String en, String zh) => widget.chinese ? zh : en;
  double get _menuWidth => (_width - ComposerTheme.inset * 2).clamp(0, 760);
  bool get _touchCompact =>
      (_width < 600 || _availableHeight < 200) &&
      (Theme.of(context).platform == TargetPlatform.iOS ||
          Theme.of(context).platform == TargetPlatform.android);

  Offset get _menuOffset {
    final anchor = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final start = model.historyOpen || model.items.isEmpty
        ? 0
        : model.items.first.start;
    final point = _editorKey.currentState?.globalPosition(start);
    final x = anchor != null && point != null
        ? anchor.globalToLocal(point).dx
        : ComposerTheme.inset;
    final inset = ComposerTheme.inset.clamp(0.0, _width / 2);
    return Offset(x.clamp(inset, _width - _menuWidth - inset), -6);
  }

  @override
  void initState() {
    super.initState();
    _focus = widget.focusNode ?? FocusNode(debugLabel: 'Composer');
    _focus.addListener(_changed);
    _resultsFocus.addListener(_changed);
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
      _selectionNavigationRevision = -1;
      _busyHeight = null;
    }
  }

  void _changed() {
    if (!mounted) return;
    if (_disabled) {
      // Read the last laid-out height before an accepted submission clears the
      // draft. Keep the footer and terminal viewport in place while busy.
      final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) _busyHeight ??= box.size.height;
    } else {
      _busyHeight = null;
    }
    final show =
        !_disabled &&
        (_focus.hasFocus || _resultsFocus.hasFocus) &&
        (model.completionMenuOpen || model.historyOpen) &&
        model.editor.value.composing.isCollapsed;
    final opening = show && !_overlay.isShowing;
    final navigation =
        _selectionNavigationRevision != model.selectionNavigationRevision;
    _selectionNavigationRevision = model.selectionNavigationRevision;
    if (opening) _overlay.show();
    if (!show && _overlay.isShowing) _overlay.hide();
    setState(() {});
    final index = model.historyOpen
        ? model.historySelectedIndex
        : model.selectedIndex;
    if (show && index >= 0 && (opening || navigation)) {
      final revision = model.selectionNavigationRevision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _overlay.isShowing &&
            _scroll.hasClients &&
            model.selectionNavigationRevision == revision) {
          _revealSelection();
        }
      });
    }
  }

  double get _rowExtent {
    final scaler = MediaQuery.textScalerOf(context);
    return ComposerSuggestions.rowExtent(
      scaler,
      inlineDetail: !model.historyOpen && _menuWidth < scaler.scale(600),
      tokens: ComposerTheme.of(context),
    );
  }

  void _revealSelection() {
    final index = model.historyOpen
        ? model.historySelectedIndex
        : model.selectedIndex;
    if (index < 0) return;
    final top = 4.0 + index * _rowExtent;
    final bottom = top + _rowExtent + 4;
    final position = _scroll.position;
    final target = top < position.pixels
        ? top
        : bottom > position.pixels + position.viewportDimension
        ? bottom - position.viewportDimension
        : position.pixels;
    final offset = target.clamp(0.0, position.maxScrollExtent);
    // Even a jump to the current offset cancels the trackpad drag/inertia.
    if (offset != position.pixels) _scroll.jumpTo(offset);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (_disabled) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final hardware = HardwareKeyboard.instance;
    final composing = !model.editor.value.composing.isCollapsed;
    if (composing) return KeyEventResult.ignored;
    final command =
        hardware.isMetaPressed ||
        (defaultTargetPlatform != TargetPlatform.macOS &&
            hardware.isControlPressed);
    if (command &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown) &&
        (event is KeyDownEvent || event is KeyRepeatEvent) &&
        widget.onNavigateBlocks?.call(
              key == LogicalKeyboardKey.arrowUp ? -1 : 1,
            ) ==
            true) {
      model.dismissHistory();
      model.dismissCompletions();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) {
        if (hardware.isShiftPressed ||
            hardware.isAltPressed ||
            hardware.isControlPressed) {
          model.insertNewline();
        } else {
          _performPrimary();
        }
      }
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (command && key == LogicalKeyboardKey.keyZ) {
      model.dismissHistory();
      hardware.isShiftPressed ? model.redo() : model.undo();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyI && widget.onAskAi != null) {
      if (event is KeyDownEvent) {
        model.chooseInputIntent(
          _asksAi ? InputIntentChoice.command : InputIntentChoice.ai,
        );
      }
      return KeyEventResult.handled;
    }
    if (hardware.isControlPressed && key == LogicalKeyboardKey.keyR) {
      model.openHistory();
      return KeyEventResult.handled;
    }
    if (!hardware.isShiftPressed &&
        !hardware.isMetaPressed &&
        !hardware.isAltPressed &&
        (key == LogicalKeyboardKey.arrowRight ||
            (hardware.isControlPressed &&
                (key == LogicalKeyboardKey.keyF ||
                    key == LogicalKeyboardKey.keyE)))) {
      if (model.acceptInline(
        partial:
            key == LogicalKeyboardKey.arrowRight && hardware.isControlPressed,
      )) {
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.tab) {
      // Application tab switching and OS shortcuts keep their own routing.
      if (hardware.isControlPressed ||
          hardware.isMetaPressed ||
          hardware.isAltPressed) {
        return KeyEventResult.ignored;
      }
      if (event is KeyDownEvent) {
        if (hardware.isShiftPressed) {
          FocusScope.of(context).previousFocus();
        } else {
          model.completeOnTab();
        }
      }
      return KeyEventResult.handled;
    }
    if (!hardware.isShiftPressed &&
        !hardware.isControlPressed &&
        !hardware.isAltPressed &&
        !hardware.isMetaPressed &&
        (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowUp)) {
      final delta = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
      if (model.historyOpen) {
        model.selectHistory(delta);
        return KeyEventResult.handled;
      }
      if (model.completionMenuOpen) {
        model.selectNext(delta);
        return KeyEventResult.handled;
      }
      if (delta < 0 && _editorKey.currentState?.onFirstVisualLine == true) {
        model.openHistory();
        return KeyEventResult.handled;
      }
      if (delta > 0 &&
          _editorKey.currentState?.hasSingleVisualLine == true &&
          model.items.isNotEmpty) {
        model.selectNext(1);
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.escape) {
      if (model.historyOpen) {
        model.dismissHistory();
      } else if (model.completionMenuOpen) {
        model.dismissCompletions();
        model.dismissInline();
      } else if (model.inlineSuggestion.isNotEmpty) {
        model.dismissInline();
      } else if (!model.editor.selection.isCollapsed) {
        model.editor.selection = TextSelection.collapsed(
          offset: model.editor.selection.extentOffset,
        );
      } else {
        widget.onUseTerminal?.call();
      }
      return KeyEventResult.handled;
    }
    if (hardware.isControlPressed && key == LogicalKeyboardKey.keyC) {
      model.clearDraft();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ComposerTheme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        final media = MediaQuery.of(context);
        final availableHeight = math.min(
          constraints.maxHeight,
          media.size.height - media.viewInsets.bottom - media.padding.vertical,
        );
        final short = availableHeight < 200;
        _availableHeight = availableHeight;
        final layoutSize = (
          _width,
          Size(media.size.width, availableHeight),
          scaler,
        );
        // A real window/text-size change should reflow rather than retain an
        // obsolete height from a wider or shorter layout.
        if (_layoutSize != layoutSize) _busyHeight = null;
        _layoutSize = layoutSize;
        final compact =
            constraints.maxWidth - ComposerTheme.inset * 2 <
            math.max(scaler.scale(520), _toolbarMinimumWidth(tokens));
        final inlineEditor =
            short &&
            _touchCompact &&
            _width >= scaler.scale(280) + tokens.controlHeight * 4;
        final lineBudget = math.max(
          1,
          ((availableHeight * .4) /
                  scaler.scale(tokens.commandStyle.fontSize! * 1.5))
              .floor(),
        );
        final editor = Focus(
          onKeyEvent: _key,
          child: ComposerEditor(
            key: _editorKey,
            controller: model.editor,
            focusNode: _focus,
            autofocus: widget.autofocus,
            enabled: !_disabled,
            centerVertically: inlineEditor,
            maxLines: short && _touchCompact
                ? 1
                : math.min(
                    _touchCompact
                        ? math.min(4, widget.maxLines)
                        : widget.maxLines,
                    lineBudget,
                  ),
            suggestion: !_disabled && _focus.hasFocus
                ? model.inlineSuggestion
                : '',
            suggestionColor: _disabled
                ? tokens.disabledForeground
                : tokens.muted,
            hint: model.historyOpen
                ? tr('Filter command history…', '筛选历史命令…')
                : tr('Type a command…', '输入命令…'),
            style: _disabled
                ? tokens.commandStyle.copyWith(color: tokens.disabledForeground)
                : tokens.commandStyle,
          ),
        );
        final surface = TextFieldTapRegion(
          child: KeyedSubtree(
            key: _anchorKey,
            child: OverlayPortal.overlayChildLayoutBuilder(
              controller: _overlay,
              overlayChildBuilder: (context, info) {
                final origin = MatrixUtils.transformPoint(
                  info.childPaintTransform,
                  Offset.zero,
                );
                final available =
                    (origin.dy - MediaQuery.paddingOf(context).top - 8).clamp(
                      0.0,
                      320.0,
                    );
                final left = (origin.dx + _menuOffset.dx).clamp(
                  0.0,
                  math.max(0.0, info.overlaySize.width - _menuWidth),
                );
                return Positioned(
                  left: left.toDouble(),
                  bottom: math.max(
                    0.0,
                    info.overlaySize.height - origin.dy + 6,
                  ),
                  width: _menuWidth,
                  child: TextFieldTapRegion(
                    child: Focus(
                      focusNode: _resultsFocus,
                      onKeyEvent: (_, event) {
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.escape) {
                          model.historyOpen
                              ? model.dismissHistory()
                              : model.dismissCompletions();
                          _focus.requestFocus();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: ComposerSuggestions(
                        model: model,
                        scroll: _scroll,
                        chinese: widget.chinese,
                        maxHeight: available,
                        onAccepted: _focus.requestFocus,
                        onClosed: _focus.requestFocus,
                      ),
                    ),
                  ),
                );
              },
              child: Material(
                key: const Key('composer-surface'),
                color: tokens.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ComposerTheme.radius),
                  side: BorderSide(
                    color: tokens.border,
                    width: tokens.borderWidth,
                  ),
                ),
                child: SizedBox(
                  height: _busyHeight,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: ComposerTheme.inset,
                      vertical: short && _touchCompact
                          ? 6
                          : ComposerTheme.inset,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!(short && _touchCompact)) ...[
                          _context(tokens, compact: compact),
                          SizedBox(height: short ? 8 : 12),
                        ],
                        if (inlineEditor)
                          Row(
                            children: [
                              Expanded(child: editor),
                              const SizedBox(width: 8),
                              _actions(tokens, compact: compact, inline: true),
                            ],
                          )
                        else ...[
                          if (_busyHeight != null)
                            Expanded(
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: editor,
                              ),
                            )
                          else
                            editor,
                          SizedBox(height: short ? 6 : 12),
                          _actions(tokens, compact: compact, short: short),
                        ],
                        if (!_disabled && model.executionStatus.isNotEmpty)
                          _executionFeedback(tokens),
                        if (!_disabled &&
                            (model.loading ||
                                model.completionStatus.isNotEmpty))
                          _completionFeedback(tokens),
                        if (!_disabled && _copyFeedback.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Semantics(
                              key: const Key('composer-feedback'),
                              liveRegion: true,
                              child: Text(
                                _copyFeedback,
                                style: tokens.statusStyle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        return _touchCompact && availableHeight < 140
            ? SingleChildScrollView(
                key: const Key('composer-short-window-scroll'),
                child: surface,
              )
            : surface;
      },
    );
  }

  Widget _context(ComposerTheme tokens, {required bool compact}) {
    final target = _metadata(
      tokens,
      ComposerIcons.localTarget,
      model.dialect == 'generic'
          ? widget.targetLabel
          : '${widget.targetLabel} · ${model.dialect}',
    );
    final path = _metadata(
      tokens,
      ComposerIcons.directory,
      model.cwd,
      key: const Key('composer-context-path'),
      path: true,
    );
    if (_touchCompact) {
      return Row(
        children: [
          Expanded(child: model.cwd.isEmpty ? target : path),
          const SizedBox(width: 8),
          Flexible(child: _ownership(tokens)),
          _historyButton(tokens),
          if (_focus.hasFocus) _hideKeyboardButton(tokens),
          _moreActions(tokens),
        ],
      );
    }
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          target,
          if (model.cwd.isNotEmpty) ...[const SizedBox(height: 6), path],
          const SizedBox(height: 6),
          Align(alignment: Alignment.centerLeft, child: _ownership(tokens)),
        ],
      );
    }
    return Row(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: _width * .35),
          child: target,
        ),
        if (model.cwd.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              height: 16,
              child: VerticalDivider(width: 1, color: tokens.divider),
            ),
          ),
          Expanded(child: path),
        ] else
          const Spacer(),
        const SizedBox(width: 12),
        _ownership(tokens),
      ],
    );
  }

  Widget _metadata(
    ComposerTheme tokens,
    IconData icon,
    String label, {
    Key? key,
    bool path = false,
  }) => Tooltip(
    message: label,
    child: Semantics(
      key: key,
      label: label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: ComposerTheme.rowIconSize, color: tokens.muted),
          const SizedBox(width: 8),
          Flexible(
            child: path
                ? LayoutBuilder(
                    builder: (context, bounds) => Text(
                      path
                          ? _visiblePath(
                              label,
                              bounds.maxWidth,
                              tokens.contextStyle,
                            )
                          : label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: path ? TextDirection.ltr : null,
                      style: tokens.contextStyle,
                    ),
                  )
                : Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.contextStyle,
                  ),
          ),
        ],
      ),
    ),
  );

  String _visiblePath(String full, double width, TextStyle style) {
    bool fits(String value) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: style),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final fits = painter.width <= width;
      painter.dispose();
      return fits;
    }

    if (fits(full)) return full;
    final segments = full.split('/').where((part) => part.isNotEmpty).toList();
    if (segments.length < 2) return full;
    var tail = segments.last;
    for (var i = segments.length - 2; i >= 0; i--) {
      final next = '${segments[i]}/$tail';
      if (!fits('…/$next')) break;
      tail = next;
    }
    return '…/$tail';
  }

  String get _ownershipLabel => switch (model.ownership) {
    ComposerOwnership.ready => tr('Shell ready', 'Shell 就绪'),
    ComposerOwnership.submitting => tr('Sending…', '发送中…'),
    ComposerOwnership.running => tr('Running', '运行中'),
    ComposerOwnership.unknown => tr('Result unknown', '结果未知'),
    ComposerOwnership.suspended => tr('Terminal input', '终端输入中'),
    ComposerOwnership.draft => tr('Draft only', '仅编辑'),
  };

  Widget _ownership(ComposerTheme tokens) {
    final color = model.ownership == ComposerOwnership.unknown
        ? tokens.error
        : tokens.muted;
    return Semantics(
      key: const Key('composer-status'),
      liveRegion: true,
      label: _ownershipLabel,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (model.ownership == ComposerOwnership.submitting)
            SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
            )
          else if (model.ownership == ComposerOwnership.ready)
            DecoratedBox(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: const SizedBox.square(dimension: 7),
            )
          else
            Icon(
              ComposerIcons.forOwnership(model.ownership),
              size: ComposerTheme.rowIconSize,
              color: color,
            ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _ownershipLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.statusStyle.copyWith(
                color: model.ownership == ComposerOwnership.unknown
                    ? tokens.error
                    : tokens.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _toolbarMinimumWidth(ComposerTheme tokens) {
    final labels = [
      tr('Command', '命令'),
      tr('History', '历史'),
      tr('Automatic suggestions', '自动建议'),
      tr('Sending', '发送中'),
    ];
    // Include the expanded editor's control in the responsive dock budget.
    var width = 280.0 + tokens.controlHeight;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: tokens.actionStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      width += painter.width;
      painter.dispose();
    }
    return width;
  }

  Widget _actions(
    ComposerTheme tokens, {
    required bool compact,
    bool inline = false,
    bool short = false,
  }) {
    if (_touchCompact) {
      final actions = <Widget>[
        if (widget.onOpenAi != null || widget.onAskAi != null)
          _intent(tokens, compact: true)
        else
          Text(tr('Command', '命令'), style: tokens.metadataStyle),
        _expandButton(tokens),
        if (inline || short) _hideKeyboardButton(tokens),
        _primary(tokens, iconOnly: (short || inline) && _width < 480),
      ];
      if (inline) {
        return Row(mainAxisSize: MainAxisSize.min, children: actions);
      }
      return Row(
        children: [
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: actions.first),
          ),
          ...actions.skip(1),
        ],
      );
    }
    final utilities = <Widget>[
      if (!compact)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.selection,
              borderRadius: BorderRadius.circular(tokens.controlHeight / 2),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    ComposerIcons.terminal,
                    size: ComposerTheme.iconSize,
                    color: tokens.onSelection,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    tr('Command', '命令'),
                    style: tokens.actionStyle.copyWith(
                      color: tokens.onSelection,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      Semantics(
        toggled: model.historyOpen,
        child: Tooltip(
          message: !model.canOpenHistory
              ? tr(
                  'History is available while editing a ready shell or draft',
                  '就绪或草稿状态下可浏览历史',
                )
              : model.historyOpen
              ? tr('Close history and restore draft · Esc', '关闭历史并恢复草稿 · Esc')
              : tr('Command history · ↑ / Ctrl+R', '命令历史 · ↑ / Ctrl+R'),
          child: TextButton.icon(
            key: const Key('composer-history-toggle'),
            onPressed: !model.canOpenHistory
                ? null
                : () {
                    model.toggleHistory();
                    _focus.requestFocus();
                  },
            style: _utilityStyle(tokens, selected: model.historyOpen),
            icon: const Icon(
              ComposerIcons.history,
              size: ComposerTheme.iconSize,
            ),
            label: Text(tr('History', '历史')),
          ),
        ),
      ),
      _automaticSuggestions(tokens),
      if (widget.onOpenAi != null || widget.onAskAi != null) _intent(tokens),
      _expandButton(tokens),
      _moreActions(tokens),
    ];
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: utilities,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  _keyHint(compact: true),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.metadataStyle,
                ),
              ),
              const SizedBox(width: 8),
              _primary(tokens),
            ],
          ),
        ],
      );
    }
    return Row(
      children: [
        ...utilities,
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _keyHint(),
            textAlign: TextAlign.end,
            maxLines: 2,
            style: tokens.metadataStyle,
          ),
        ),
        const SizedBox(width: 16),
        _primary(tokens),
      ],
    );
  }

  ButtonStyle _utilityStyle(ComposerTheme tokens, {bool selected = false}) =>
      TextButton.styleFrom(
        foregroundColor: selected ? tokens.onSelection : tokens.muted,
        disabledForegroundColor: tokens.disabledForeground,
        backgroundColor: selected ? tokens.selection : null,
        minimumSize: Size(32, tokens.controlHeight),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        textStyle: tokens.actionStyle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ComposerTheme.controlRadius),
        ),
      );

  Widget _automaticSuggestions(ComposerTheme tokens) {
    final label = tr('Automatic suggestions', '自动建议');
    final stateLabel =
        '$label · ${model.localSuggestions ? tr('On', '开') : tr('Off', '关')}';
    final help = tr(
      'Show suggestions while typing. Tab always completes on demand.',
      '输入时自动显示候选；Tab 始终可按需补全。',
    );
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: math.max(0, _width - ComposerTheme.inset * 2),
      ),
      child: Tooltip(
        message: '$stateLabel\n$help',
        child: Semantics(
          key: const Key('composer-automatic-suggestions-toggle'),
          label: stateLabel,
          hint: help,
          toggled: model.localSuggestions,
          button: true,
          enabled: !_disabled,
          onTap: _disabled ? null : model.toggleLocalSuggestions,
          excludeSemantics: true,
          child: TextButton(
            onPressed: _disabled ? null : model.toggleLocalSuggestions,
            style: _utilityStyle(tokens),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // This is a visual indicator inside the labelled button, not
                // a second focus stop or independently announced switch.
                SizedBox.square(
                  dimension: 28,
                  child: Center(
                    child: Container(
                      width: 26,
                      height: 14,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: _disabled
                            ? tokens.disabledSurface
                            : model.localSuggestions
                            ? tokens.primaryAction
                            : tokens.chip,
                        border: Border.all(
                          color: _disabled
                              ? tokens.border
                              : model.localSuggestions
                              ? tokens.primaryAction
                              : tokens.border,
                        ),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Align(
                        alignment: model.localSuggestions
                            ? AlignmentDirectional.centerEnd
                            : AlignmentDirectional.centerStart,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: _disabled
                                ? tokens.disabledForeground
                                : model.localSuggestions
                                ? tokens.onPrimaryAction
                                : tokens.muted,
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox.square(dimension: 8),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(child: Text(label)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _keyHint({bool compact = false}) {
    if (model.historyOpen) {
      if (model.historyItems.isEmpty) {
        return tr('Esc restore draft', 'Esc 恢复草稿');
      }
      if (compact) return '↑ ↓';
      return tr('↑ ↓ select · Enter accept', '↑ ↓ 选择 · Enter 采用');
    }
    if (model.selectedIndex >= 0) {
      if (compact) return 'Tab';
      return tr('Tab accept · Esc close', 'Tab 采用 · Esc 关闭');
    }
    if (model.ownership == ComposerOwnership.submitting) {
      return tr('Waiting for shell', '等待 Shell 接收');
    }
    if (model.ownership == ComposerOwnership.running ||
        model.ownership == ComposerOwnership.suspended) {
      return tr('Use terminal for input', '在终端中继续输入');
    }
    if (model.ownership == ComposerOwnership.unknown) {
      return tr('Check the terminal', '请先检查终端');
    }
    if (model.inlineSuggestion.isNotEmpty) {
      return tr('→ accept suggestion', '→ 接受建议');
    }
    return compact
        ? tr('Tab complete', 'Tab 补全')
        : tr('Tab complete · Shift Enter newline', 'Tab 补全 · ⇧ Enter 换行');
  }

  Widget _primary(ComposerTheme tokens, {bool iconOnly = false}) {
    final accepting =
        model.historyOpen ||
        model.primaryAction == ComposerPrimaryAction.acceptCompletion;
    final label = accepting
        ? tr('Accept', '采用')
        : _asksAi
        ? tr('Send to AI', '发送给 AI')
        : model.ownership == ComposerOwnership.submitting
        ? tr('Sending', '发送中')
        : tr('Run', '执行');
    final tooltip = model.canPerformPrimaryAction
        ? accepting
              ? tr('Accept into draft · Enter', '采用到草稿 · Enter')
              : _asksAi
              ? tr('Send to AI · Enter', '发送给 AI · Enter')
              : tr('Run command · Enter', '执行命令 · Enter')
        : model.historyOpen
        ? tr('No history result to accept', '没有可采用的历史命令')
        : model.ownership == ComposerOwnership.ready
        ? tr('Enter a complete command to run', '请输入完整命令后执行')
        : _disabled
        ? tr('Wait for the shell to be ready', '等待 Shell 恢复就绪')
        : tr(
            'A ready shell is required to run; the draft is preserved',
            'Shell 未就绪，草稿仍可编辑',
          );
    return Tooltip(
      message: tooltip,
      child: FilledButton(
        key: const Key('composer-primary-action'),
        onPressed: model.canPerformPrimaryAction
            ? () {
                final asksAi = _asksAi;
                _performPrimary();
                if (!asksAi) _focus.requestFocus();
              }
            : null,
        style: FilledButton.styleFrom(
          foregroundColor: tokens.onPrimaryAction,
          backgroundColor: tokens.primaryAction,
          disabledForegroundColor: tokens.disabledForeground,
          disabledBackgroundColor: tokens.disabledSurface,
          minimumSize: Size(iconOnly ? 44 : 76, tokens.controlHeight),
          padding: EdgeInsets.symmetric(
            horizontal: _touchCompact ? 8 : 14,
            vertical: 7,
          ),
          textStyle: tokens.actionStyle.copyWith(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ComposerTheme.controlRadius),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!iconOnly) Text(label),
            if (!_touchCompact && !iconOnly) const SizedBox(width: 8),
            if (!_touchCompact || iconOnly)
              Icon(
                accepting ? ComposerIcons.accept : ComposerIcons.run,
                size: 18,
                semanticLabel: iconOnly ? label : null,
              ),
          ],
        ),
      ),
    );
  }

  Widget _intent(
    ComposerTheme tokens, {
    bool compact = false,
  }) => PopupMenuButton<String>(
    key: const Key('composer-input-intent'),
    tooltip: tr('Input intent', '输入意图'),
    onSelected: (intent) {
      if (intent == 'ai' && widget.onAskAi == null) {
        widget.onOpenAi?.call();
        return;
      }
      model.chooseInputIntent(InputIntentChoice.values.byName(intent));
      _focus.requestFocus();
    },
    itemBuilder: (_) => [
      CheckedPopupMenuItem(
        value: 'automatic',
        checked: model.inputIntent.choice == InputIntentChoice.automatic,
        child: Text(tr('Automatic', '自动识别')),
      ),
      CheckedPopupMenuItem(
        value: 'command',
        checked: model.inputIntent.choice == InputIntentChoice.command,
        child: Text(tr('Command', '命令')),
      ),
      CheckedPopupMenuItem(
        value: 'ai',
        checked: model.inputIntent.choice == InputIntentChoice.ai,
        child: Text(tr('Ask AI', 'AI 提问')),
      ),
    ],
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: compact ? 44 : 32),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!compact) ...[
            Icon(
              _asksAi ? Icons.auto_awesome_outlined : Icons.terminal_outlined,
              size: 18,
              color: tokens.muted,
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              '${model.inputIntent.choice == InputIntentChoice.automatic ? tr('Auto · ', '自动 · ') : ''}${_asksAi ? 'AI' : tr('Command', '命令')}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tokens.metadataStyle,
            ),
          ),
          Icon(Icons.expand_more, size: 16, color: tokens.muted),
        ],
      ),
    ),
  );

  Widget _moreActions(ComposerTheme tokens) {
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    return PopupMenuButton<_ComposerMenuAction>(
      key: const Key('composer-more-actions'),
      enabled: !_disabled,
      tooltip: tr('More command actions', '更多命令操作'),
      requestFocus: true,
      icon: Icon(
        ComposerIcons.more,
        size: ComposerTheme.iconSize,
        color: _disabled ? tokens.disabledForeground : tokens.muted,
        semanticLabel: tr('More command actions', '更多命令操作'),
      ),
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.over,
      onCanceled: () {
        if (!_disabled) _focus.requestFocus();
      },
      onSelected: (action) {
        if (_disabled) return;
        switch (action) {
          case _ComposerMenuAction.askAi:
            widget.onAskAi?.call(model.editor.text);
            model.chooseInputIntent(InputIntentChoice.automatic);
            return;
          case _ComposerMenuAction.forceCommand:
            model.chooseInputIntent(
              model.inputIntent.choice == InputIntentChoice.command
                  ? InputIntentChoice.automatic
                  : InputIntentChoice.command,
            );
          case _ComposerMenuAction.copy:
            unawaited(_copyDraft());
          case _ComposerMenuAction.undo:
            model.dismissHistory();
            model.undo();
          case _ComposerMenuAction.redo:
            model.dismissHistory();
            model.redo();
          case _ComposerMenuAction.clear:
            model.clearDraft();
          case _ComposerMenuAction.terminal:
            widget.onUseTerminal?.call();
            return;
          case _ComposerMenuAction.shortcuts:
            unawaited(_showShortcuts());
            return;
          case _ComposerMenuAction.suggestions:
            model.toggleLocalSuggestions();
        }
        _focus.requestFocus();
      },
      itemBuilder: (context) => [
        if (widget.onAskAi != null) ...[
          PopupMenuItem(
            value: _ComposerMenuAction.askAi,
            child: Text(tr('Ask AI about this draft', '把草稿发给 AI')),
          ),
          CheckedPopupMenuItem(
            value: _ComposerMenuAction.forceCommand,
            checked: model.inputIntent.choice == InputIntentChoice.command,
            child: Text(tr('Submit this draft as a command', '此草稿作为命令提交')),
          ),
          const PopupMenuDivider(),
        ],
        if (_touchCompact)
          CheckedPopupMenuItem(
            value: _ComposerMenuAction.suggestions,
            checked: model.localSuggestions,
            child: Text(tr('Automatic suggestions', '自动建议')),
          ),
        _menuItem(
          tokens,
          _ComposerMenuAction.copy,
          ComposerIcons.copy,
          tr('Copy command', '复制命令'),
          enabled: model.editor.text.isNotEmpty,
          key: const Key('composer-copy-draft'),
        ),
        _menuItem(
          tokens,
          _ComposerMenuAction.undo,
          ComposerIcons.undo,
          tr('Undo', '撤销'),
          enabled: model.canUndo,
          shortcut: mac ? '⌘Z' : 'Ctrl+Z',
        ),
        _menuItem(
          tokens,
          _ComposerMenuAction.redo,
          ComposerIcons.redo,
          tr('Redo', '重做'),
          enabled: model.canRedo,
          shortcut: mac ? '⇧⌘Z' : 'Ctrl+Shift+Z',
        ),
        _menuItem(
          tokens,
          _ComposerMenuAction.clear,
          ComposerIcons.clear,
          tr('Clear draft', '清空草稿'),
          enabled: model.editor.text.isNotEmpty,
        ),
        const PopupMenuDivider(),
        if (widget.onUseTerminal != null)
          _menuItem(
            tokens,
            _ComposerMenuAction.terminal,
            ComposerIcons.useTerminal,
            tr('Use terminal input', '使用终端输入'),
            shortcut: 'Esc',
          ),
        _menuItem(
          tokens,
          _ComposerMenuAction.shortcuts,
          ComposerIcons.shortcuts,
          tr('Keyboard shortcuts', '键盘快捷键'),
          key: const Key('composer-shortcut-help'),
        ),
      ],
    );
  }

  PopupMenuItem<_ComposerMenuAction> _menuItem(
    ComposerTheme tokens,
    _ComposerMenuAction action,
    IconData icon,
    String label, {
    bool enabled = true,
    String? shortcut,
    Key? key,
  }) => PopupMenuItem(
    key: key,
    value: action,
    enabled: enabled,
    child: Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: enabled ? tokens.muted : tokens.disabledForeground,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
        if (shortcut != null) ...[
          const SizedBox(width: 12),
          Text(shortcut, style: tokens.metadataStyle),
        ],
      ],
    ),
  );

  Future<void> _copyDraft() async {
    final text = model.editor.text;
    if (text.isEmpty) return;
    String feedback;
    try {
      await Clipboard.setData(ClipboardData(text: text));
      feedback = tr('Command copied', '命令已复制');
    } on PlatformException {
      feedback = tr(
        'Could not copy. Select the text and try again.',
        '复制失败，请选中文本后重试。',
      );
    }
    if (!mounted) return;
    _feedbackTimer?.cancel();
    setState(() => _copyFeedback = feedback);
    _feedbackTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copyFeedback = '');
    });
  }

  Future<void> _showShortcuts() async {
    final entries = <(String, String)>[
      ('Enter', tr('Run command / accept selected result', '执行命令／采用选中项')),
      ('Tab', tr('Complete / accept selected result', '补全／采用选中项')),
      ('Shift / Ctrl / Option + Enter', tr('Insert newline', '插入换行')),
      ('↑ / Ctrl+R', tr('Open command history', '打开命令历史')),
      ('↑ ↓', tr('Navigate results', '选择候选')),
      ('→ / Ctrl+F / Ctrl+E', tr('Accept inline suggestion', '接受灰字建议')),
      ('Ctrl+→', tr('Accept the next suggestion segment', '接受下一段建议')),
      (
        'Esc',
        widget.onUseTerminal == null
            ? tr('Close results / dismiss suggestion', '关闭候选／取消建议')
            : tr(
                'Close results / dismiss suggestion / return to terminal',
                '关闭候选／取消建议／返回终端',
              ),
      ),
      ('Shift+Tab', tr('Move focus to controls', '将焦点移到操作控件')),
    ];
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Command shortcuts', '命令快捷键')),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.$1,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 3),
                        Text(entry.$2),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Done', '完成')),
          ),
        ],
      ),
    );
    if (mounted) _focus.requestFocus();
  }

  Widget _executionFeedback(ComposerTheme tokens) => Container(
    key: const Key('composer-execution-feedback'),
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: tokens.errorSurface,
      borderRadius: BorderRadius.circular(ComposerTheme.controlRadius),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(ComposerIcons.unknown, size: 16, color: tokens.onError),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _statusText(model.executionStatus),
                  style: tokens.statusStyle.copyWith(color: tokens.onError),
                ),
              ),
            ],
          ),
        ),
        if (model.canRecoverDraft)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  key: const Key('composer-recover-draft'),
                  onPressed: () {
                    model.recoverDraft();
                    _focus.requestFocus();
                  },
                  style: TextButton.styleFrom(foregroundColor: tokens.onError),
                  child: Text(tr('Recover draft', '恢复草稿')),
                ),
                if (widget.onUseTerminal != null)
                  TextButton(
                    onPressed: widget.onUseTerminal,
                    style: TextButton.styleFrom(
                      foregroundColor: tokens.onError,
                    ),
                    child: Text(tr('Check terminal', '查看终端')),
                  ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _completionFeedback(ComposerTheme tokens) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (model.loading) ...[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SizedBox.square(
              dimension: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: tokens.muted,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            model.loading
                ? tr('Finding completions…', '正在查找补全…')
                : _statusText(model.completionStatus),
            key: const Key('composer-completion-feedback'),
            style: tokens.statusStyle,
          ),
        ),
      ],
    ),
  );

  String _statusText(String status) => switch (status) {
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
    'no_completions' => tr('No matching completions.', '没有匹配的补全项。'),
    'completion_selection' => tr(
      'Move the cursor to the completion position first. → collapses the selection.',
      '请先将光标移到要补全的位置；按 → 可取消选区。',
    ),
    'unsupported_context' => tr(
      'No completions for this shell expression.',
      '此 shell 表达式暂不提供补全。',
    ),
    _ => '',
  };

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    model.removeListener(_changed);
    _resultsFocus.removeListener(_changed);
    _resultsFocus.dispose();
    _focus.removeListener(_changed);
    if (widget.focusNode == null) _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }
}

enum _ComposerMenuAction {
  askAi,
  forceCommand,
  copy,
  undo,
  redo,
  clear,
  terminal,
  shortcuts,
  suggestions,
}
