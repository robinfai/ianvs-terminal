import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';

import '../composer/composer_theme.dart';
import '../config/terminal_config.dart';
import 'command_block.dart';
import 'command_block_controller.dart';
import 'selection_controller.dart';
import 'terminal_input_controller.dart';
import 'terminal_input_sink.dart';
import 'terminal_models.dart';
import 'terminal_viewport.dart';
import 'terminal_viewport_colors.dart';

part 'command_blocks_controls.dart';
part 'command_blocks_output.dart';
part 'command_blocks_compact.dart';
part 'command_block_reader.dart';

/// A selectable, session-local command transcript. The host retains its native
/// terminal for PTY input and switches back for alternate-screen/mouse apps.
class TerminalCommandBlocksView extends StatefulWidget {
  const TerminalCommandBlocksView({
    required this.controller,
    required this.onReinput,
    this.onReturnToInput,
    this.onUseTerminal,
    this.chinese = false,
    this.liveInput,
    this.liveFocus,
    this.liveModes = TerminalFrameModes.empty,
    this.font = const TerminalFontConfig(),
    this.onMeasuredCellSizeChanged,
    this.onOpenLinkTarget,
    this.onAskAi,
    super.key,
  });
  final CommandBlockController controller;
  final ValueChanged<String> onReinput;
  final VoidCallback? onReturnToInput;
  final VoidCallback? onUseTerminal;
  final bool chinese;
  final TerminalInputController? liveInput;
  final FocusNode? liveFocus;
  final TerminalFrameModes liveModes;
  final TerminalFontConfig font;
  final ValueChanged<Size>? onMeasuredCellSizeChanged;
  final ValueChanged<TerminalLinkTarget>? onOpenLinkTarget;
  final ValueChanged<CommandBlock>? onAskAi;

  @override
  State<TerminalCommandBlocksView> createState() => _CommandBlocksViewState();
}

class _CommandBlocksViewState extends State<TerminalCommandBlocksView> {
  final _scroll = ScrollController();
  final _focus = FocusNode(debugLabel: 'Command blocks');
  final GlobalKey<State<StatefulWidget>> _listKey = GlobalKey();
  final _keys = <String, GlobalKey>{};
  final _commandKeys = <String, GlobalKey>{};
  final _find = TextEditingController();
  final _findFocus = FocusNode(debugLabel: 'Find in blocks');
  Timer? _findDebounce;
  String? _stickyId;
  String? _feedback;
  Timer? _feedbackTimer;
  bool _follow = true;
  bool _finding = false;
  bool _findRegex = false;
  bool _findCase = false;
  String? _findScope;
  String? _findError;
  List<(CommandBlock, TerminalRow)> _matches = const [];
  int _findSerial = 0;
  int _revealed = 0;
  int _revealSerial = 0;
  String? _runningId;
  double? _cellHeight;
  bool _readerLayout = false;
  bool _readerOpen = false;
  final _readingRows = <String, double>{};
  CommandBlockController get c => widget.controller;
  String t(String en, String zh) => widget.chinese ? zh : en;
  void _update(VoidCallback action) => setState(action);

  @override
  void initState() {
    super.initState();
    // Mounting an already-running transcript is not a new execution. Its
    // first refresh must not re-enable tail following during a user's scroll.
    _runningId = c.blocks.where((block) => block.running).lastOrNull?.id;
    c.addListener(_changed);
    _scroll.addListener(_scrolled);
    WidgetsBinding.instance.addPostFrameCallback((_) => _tail());
  }

  @override
  void didUpdateWidget(TerminalCommandBlocksView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != c) {
      oldWidget.controller.removeListener(_changed);
      c.addListener(_changed);
    }
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    _scroll.dispose();
    _focus.dispose();
    _find.dispose();
    _findFocus.dispose();
    _findDebounce?.cancel();
    _feedbackTimer?.cancel();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final ids = c.blocks.map((b) => b.id).toSet();
    _keys.removeWhere((id, _) => !ids.contains(id));
    _commandKeys.removeWhere((id, _) => !ids.contains(id));
    _readingRows.removeWhere((id, _) => !ids.contains(id));
    final runningId = c.blocks.where((b) => b.running).lastOrNull?.id;
    if (runningId != null && runningId != _runningId) {
      _follow = true;
      c.selected.clear();
    }
    _runningId = runningId;
    setState(() {});
    if (c.revealRevision != _revealed) {
      _revealed = c.revealRevision;
      _focus.requestFocus();
      unawaited(_reveal(c.activeId, bottom: c.revealBottom));
    } else if (_follow && c.selected.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tail());
    }
  }

  void _tail([int remaining = 3]) {
    if (!mounted || !_scroll.hasClients || !_follow) return;
    if ((_scroll.offset - _scroll.position.maxScrollExtent).abs() > .1) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
    if (remaining > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tail(remaining - 1));
    }
  }

  void _scrolled() {
    if (!_scroll.hasClients) return;
    final box = _listKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    String? sticky;
    for (final entry in _keys.entries) {
      final block = entry.value.currentContext?.findRenderObject();
      if (block is! RenderBox || !block.attached || !block.hasSize) continue;
      final y = block.localToGlobal(Offset.zero).dy;
      final command = _commandKeys[entry.key]?.currentContext
          ?.findRenderObject();
      final commandIsAbove =
          command is RenderBox &&
          command.attached &&
          command.hasSize &&
          command.localToGlobal(Offset.zero).dy + command.size.height < top;
      if (commandIsAbove && y + block.size.height > top + 36) {
        sticky = entry.key;
        break;
      }
    }
    if (_stickyId != sticky) setState(() => _stickyId = sticky);
  }

  Future<void> _reveal(String? id, {bool bottom = false}) async {
    if (id == null) return;
    _follow = false;
    final serial = ++_revealSerial;
    // Lazy children have no RenderObject until brought into the viewport.
    // Refine an estimated offset using the currently mounted block indices.
    for (var attempt = 0; attempt < 18; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || serial != _revealSerial || !_scroll.hasClients) return;
      final context = _keys[id]?.currentContext;
      if (context != null && context.mounted) {
        await Scrollable.ensureVisible(context, alignment: bottom ? 1 : 0);
        return;
      }
      final target = c.blocks.indexWhere((b) => b.id == id);
      if (target < 0) return;
      final mountedIndices = <int>[];
      var sum = 0.0;
      for (var i = 0; i < c.blocks.length; i++) {
        final box = _keys[c.blocks[i].id]?.currentContext?.findRenderObject();
        if (box is RenderBox && box.attached && box.hasSize) {
          mountedIndices.add(i);
          sum += box.size.height;
        }
      }
      final center = mountedIndices.isEmpty
          ? 0
          : mountedIndices[mountedIndices.length ~/ 2];
      final average = mountedIndices.isEmpty
          ? 180.0
          : sum / mountedIndices.length;
      final offset = (_scroll.offset + (target - center) * average).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      _scroll.jumpTo(offset);
      WidgetsBinding.instance.scheduleFrame();
    }
  }

  void _select(String id) {
    final keys = HardwareKeyboard.instance;
    c.select(
      id,
      extend: keys.isShiftPressed,
      toggle: Theme.of(context).platform == TargetPlatform.macOS
          ? keys.isMetaPressed
          : keys.isControlPressed && keys.isShiftPressed,
    );
    _focus.requestFocus();
  }

  void _toggleOutputHeight(String id) {
    _follow = false;
    if (_readerLayout) {
      unawaited(_openReader(id));
      return;
    }
    if (!c.expandedOutput.contains(id)) c.collapsed.remove(id);
    c.toggleExpandedOutput(id);
    unawaited(_reveal(id));
  }

  KeyEventResult _key(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    final mac = Theme.of(context).platform == TargetPlatform.macOS;
    final app = mac ? keys.isMetaPressed : keys.isControlPressed;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_finding) {
        setState(() => _finding = false);
        _focus.requestFocus();
      } else {
        c.clearSelection();
        widget.onReturnToInput?.call();
      }
      return KeyEventResult.handled;
    }
    if (_findFocus.hasFocus) return KeyEventResult.ignored;
    if (app && key == LogicalKeyboardKey.keyC && c.selected.isNotEmpty) {
      unawaited(_copy('both'));
      return KeyEventResult.handled;
    }
    if (app && key == LogicalKeyboardKey.keyF) {
      _openFind(c.activeId);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF &&
        keys.isAltPressed &&
        keys.isShiftPressed) {
      final id = c.activeId ?? c.blocks.lastOrNull?.id;
      if (id != null) c.toggleFilter(id);
      return KeyEventResult.handled;
    }
    if (app && key == LogicalKeyboardKey.keyB && c.activeId != null) {
      c.toggleBookmark(c.activeId!);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final delta = key == LogicalKeyboardKey.arrowUp ? -1 : 1;
      if (app && keys.isShiftPressed && c.activeId != null) {
        c.reveal(c.activeId!, bottom: delta > 0);
      } else {
        c.move(
          delta,
          extend: keys.isShiftPressed,
          bookmarked: keys.isAltPressed,
        );
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter && c.active != null) {
      widget.onReinput(c.active!.command);
      return KeyEventResult.handled;
    }
    if (_scroll.hasClients &&
        (key == LogicalKeyboardKey.home ||
            key == LogicalKeyboardKey.end ||
            key == LogicalKeyboardKey.pageUp ||
            key == LogicalKeyboardKey.pageDown)) {
      final position = _scroll.position;
      final next = key == LogicalKeyboardKey.home
          ? 0.0
          : key == LogicalKeyboardKey.end
          ? position.maxScrollExtent
          : _scroll.offset +
                (key == LogicalKeyboardKey.pageUp ? -1 : 1) *
                    position.viewportDimension *
                    .9;
      _scroll.jumpTo(next.clamp(0.0, position.maxScrollExtent));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _announce(String message) {
    if (!mounted) return;
    _feedbackTimer?.cancel();
    setState(() => _feedback = message);
    _feedbackTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _feedback = null);
    });
  }

  Future<void> _copy(String kind, {String? id}) async {
    final blocks = c.blocks
        .where((b) => id != null ? b.id == id : c.selected.contains(b.id))
        .toList();
    try {
      final values = <String>[];
      for (final block in blocks) {
        final output = kind == 'command' ? '' : await c.outputText(block.id);
        values.add(
          kind == 'command'
              ? block.command
              : kind == 'output'
              ? output
              : '${block.command}${output.isEmpty ? '' : '\n$output'}',
        );
      }
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: values.join('\n\n')));
      _announce(t('Copied', '已复制'));
    } on Object catch (error) {
      _announce(error.toString());
    }
  }

  void _openFind(String? id) {
    setState(() {
      _finding = true;
      _findScope = id;
    });
    _findFocus.requestFocus();
    _search();
  }

  void _search() {
    _findDebounce?.cancel();
    final serial = ++_findSerial;
    _findDebounce = Timer(const Duration(milliseconds: 180), () async {
      final matches = <(CommandBlock, TerminalRow)>[];
      String? error;
      if (_find.text.isNotEmpty) {
        for (final block in c.blocks.reversed.where(
          (b) => _findScope == null || b.id == _findScope,
        )) {
          final response = c.request({
            'id': block.id,
            'query': _find.text,
            'regex': _findRegex,
            'caseSensitive': _findCase,
            'limit': 200,
            'tail': true,
          });
          if (response?['error'] case final String message) {
            error = message;
            break;
          }
          if (response?['block'] case final Map<String, Object?> result
              when result['commandMatch'] == true) {
            matches.add((block, TerminalRow(index: -1, text: block.command)));
          }
          final found = CommandBlock.fromJson(response?['block']);
          if (found != null) {
            matches.addAll(found.lines.reversed.map((line) => (block, line)));
          }
          if (matches.length >= 1000) break;
          await Future<void>.delayed(Duration.zero);
          if (!mounted || serial != _findSerial) return;
        }
      }
      if (mounted && serial == _findSerial) {
        setState(() {
          _matches = matches;
          _findError = error;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ComposerTheme.of(context);
    return Material(
      color: tokens.surface,
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _key,
        child: LayoutBuilder(
          builder: (context, bounds) {
            _readerLayout =
                tokens.controlHeight >= 44 &&
                (bounds.maxWidth < 600 ||
                    MediaQuery.sizeOf(context).shortestSide < 600 ||
                    bounds.maxHeight < tokens.controlHeight * 7);
            return Column(
              children: [
                if (bounds.maxHeight >=
                    tokens.controlHeight * (_readerLayout ? 3 : 1) + 24)
                  _toolbar(tokens),
                if (_finding)
                  Flexible(
                    child: SingleChildScrollView(child: _findBar(tokens)),
                  ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Stack(
                      children: [
                        if (c.blocks.isEmpty)
                          Center(
                            child: Text(
                              t(
                                'Run a command to start a block',
                                '执行命令后会显示命令块',
                              ),
                              style: tokens.contextStyle,
                            ),
                          )
                        else
                          NotificationListener<ScrollMetricsNotification>(
                            onNotification: (notification) {
                              // A keyboard/viewport resize should reveal the
                              // tail only while the user is still following it.
                              if (notification.depth == 0 &&
                                  notification.metrics.axis == Axis.vertical &&
                                  _follow &&
                                  c.selected.isEmpty) {
                                WidgetsBinding.instance.addPostFrameCallback(
                                  (_) => _tail(),
                                );
                              }
                              return false;
                            },
                            child: NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                if (notification is ScrollStartNotification &&
                                        notification.dragDetails != null ||
                                    notification is UserScrollNotification &&
                                        notification.direction !=
                                            ScrollDirection.idle) {
                                  _follow = false;
                                  ++_revealSerial;
                                }
                                return false;
                              },
                              child: Scrollbar(
                                controller: _scroll,
                                child: ListView.builder(
                                  key: _listKey,
                                  controller: _scroll,
                                  padding: EdgeInsets.fromLTRB(
                                    10,
                                    0,
                                    10,
                                    _readerLayout ? 0 : 16,
                                  ),
                                  itemCount: c.blocks.length,
                                  itemBuilder: (context, index) => _readerLayout
                                      ? _compactBlock(c.blocks[index], tokens)
                                      : _block(
                                          c.displayBlock(c.blocks[index]),
                                          tokens,
                                          constraints.maxHeight / 3,
                                        ),
                                ),
                              ),
                            ),
                          ),
                        if (c.stickyHeader &&
                            !_readerLayout &&
                            _stickyId != null &&
                            (!_follow || c.blocks.every((b) => !b.running)))
                          if (c.blocks
                                  .where((b) => b.id == _stickyId)
                                  .firstOrNull
                              case final CommandBlock block)
                            Positioned(
                              top: 0,
                              left: 10,
                              right: 10,
                              child: Material(
                                color: tokens.surface,
                                shape: Border(
                                  bottom: BorderSide(color: tokens.border),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => c.reveal(block.id),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 9,
                                          ),
                                          child: Text(
                                            block.command,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: tokens.resultStyle,
                                          ),
                                        ),
                                      ),
                                    ),
                                    _icon(
                                      Icons.keyboard_arrow_down,
                                      t('Jump to end of block', '跳到块末尾'),
                                      () => c.reveal(block.id, bottom: true),
                                    ),
                                    _icon(
                                      Icons.close,
                                      t('Hide sticky header', '隐藏固定标题'),
                                      () =>
                                          c.setAppearance(stickyHeader: false),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
                if (_feedback != null)
                  Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(_feedback!, style: tokens.statusStyle),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _block(
    CommandBlock block,
    ComposerTheme tokens,
    double previewHeight,
  ) {
    final selected = c.selected.contains(block.id);
    final folded = !block.running && c.collapsed.contains(block.id);
    final expanded = c.expandedOutput.contains(block.id);
    final lineHeight =
        _cellHeight ??
        MediaQuery.textScalerOf(context).scale(widget.font.size) *
            widget.font.lineHeight;
    double textHeight(TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: 'Mg', style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    // Reserve the actual text heights, the existing header controls, padding,
    // divider and inter-block spacing before allocating whole output rows.
    final chromeHeight =
        48 +
        textHeight(tokens.resultStyle) +
        8 +
        textHeight(tokens.metadataStyle) +
        (c.compact ? 12 : 24) +
        (c.compact ? 2 : 8) +
        2 +
        14;
    final summaryOnly = !expanded && previewHeight < chromeHeight + lineHeight;
    return Semantics(
      selected: selected,
      label: '${t('Command block', '命令块')}: ${block.command}',
      child: GestureDetector(
        key: _keys.putIfAbsent(block.id, GlobalKey.new),
        onSecondaryTapDown: (details) {
          _select(block.id);
          unawaited(_menu(block, details.globalPosition));
        },
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: expanded ? double.infinity : previewHeight,
          ),
          child: Container(
            key: ValueKey('command-block-${block.id}'),
            margin: EdgeInsets.only(
              bottom: summaryOnly
                  ? 0
                  : c.compact
                  ? 2
                  : 8,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? Color.alphaBlend(
                      tokens.selection.withValues(alpha: .28),
                      tokens.surface,
                    )
                  : tokens.surface,
              border: selected
                  ? Border.all(
                      color: tokens.border,
                      width: tokens.highContrast ? 1.5 : 1,
                    )
                  : c.dividers
                  ? Border(bottom: BorderSide(color: tokens.divider))
                  : null,
              borderRadius: selected ? BorderRadius.circular(8) : null,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: summaryOnly
                    ? 0
                    : c.compact
                    ? 6
                    : 12,
              ),
              child: summaryOnly
                  ? _blockSummary(block, tokens, folded)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Tooltip(
                                message: block.cwd,
                                child: Text(
                                  block.cwd.isEmpty
                                      ? t('Terminal', '终端')
                                      : block.cwd,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tokens.contextStyle,
                                ),
                              ),
                            ),
                            if (c.bookmarks.contains(block.id))
                              Icon(
                                Icons.bookmark_outline,
                                size: 16,
                                color: tokens.accent,
                              ),
                            if (!folded &&
                                (expanded ||
                                    chromeHeight +
                                            block.lines.length * lineHeight >
                                        previewHeight))
                              KeyedSubtree(
                                key: ValueKey('block-expand-${block.id}'),
                                child: _icon(
                                  expanded
                                      ? Icons.unfold_less
                                      : Icons.unfold_more,
                                  t(
                                    expanded
                                        ? 'Use default block height'
                                        : 'Expand block',
                                    expanded ? '恢复默认高度' : '扩大命令块',
                                  ),
                                  () => _toggleOutputHeight(block.id),
                                ),
                              ),
                            if (!block.running)
                              _icon(
                                folded
                                    ? Icons.chevron_right
                                    : Icons.keyboard_arrow_down,
                                t(
                                  folded ? 'Expand output' : 'Collapse output',
                                  folded ? '展开输出' : '折叠输出',
                                ),
                                () => c.toggleCollapsed(block.id),
                              ),
                            PopupMenuButton<String>(
                              tooltip: t('Block actions', '命令块操作'),
                              icon: Icon(
                                Icons.more_horiz,
                                size: 18,
                                color: tokens.muted,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 200,
                                maxWidth: 300,
                              ),
                              padding: EdgeInsets.zero,
                              onSelected: (action) => _action(block, action),
                              itemBuilder: (_) => _menuItems(block),
                            ),
                          ],
                        ),
                        InkWell(
                          key: _commandKeys.putIfAbsent(
                            block.id,
                            GlobalKey.new,
                          ),
                          onTap: () => _select(block.id),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              block.command.isEmpty
                                  ? t('Command', '命令')
                                  : block.command,
                              style: tokens.resultStyle.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: expanded ? null : 1,
                              overflow: expanded
                                  ? TextOverflow.clip
                                  : TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        if (!block.running && c.filtering.contains(block.id))
                          _BlockFilterEditor(
                            key: ValueKey('filter-${block.id}'),
                            value:
                                c.filters[block.id] ??
                                const CommandBlockFilter(),
                            chinese: widget.chinese,
                            error: c.errors[block.id],
                            onChanged: (value) => c.filter(block.id, value),
                            onClose: () => c.toggleFilter(block.id),
                          ),
                        if (!folded)
                          Flexible(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (expanded &&
                                    !block.running &&
                                    block.offset > 0)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton(
                                      onPressed: () => c.page(block.id, 0),
                                      child: Text(
                                        t(
                                          'Show earlier output · ${block.totalLines} lines',
                                          '查看较早输出 · 共 ${block.totalLines} 行',
                                        ),
                                      ),
                                    ),
                                  ),
                                if (block.running || block.lines.isNotEmpty)
                                  Flexible(
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        top: 6,
                                        bottom: 8,
                                      ),
                                      child: _blockTerminal(block),
                                    ),
                                  )
                                else
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Text(
                                      t(
                                        c.filtering.contains(block.id) &&
                                                (c
                                                        .filters[block.id]
                                                        ?.query
                                                        .isNotEmpty ??
                                                    false)
                                            ? 'No matching output'
                                            : block.running
                                            ? 'Waiting for output…'
                                            : 'No output',
                                        c.filtering.contains(block.id) &&
                                                (c
                                                        .filters[block.id]
                                                        ?.query
                                                        .isNotEmpty ??
                                                    false)
                                            ? '没有匹配的输出'
                                            : block.running
                                            ? '等待输出…'
                                            : '无输出',
                                      ),
                                      style: tokens.metadataStyle,
                                    ),
                                  ),
                                if (expanded &&
                                    !block.running &&
                                    block.nextOffset != null)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton(
                                      onPressed: () =>
                                          c.page(block.id, block.nextOffset!),
                                      child: Text(
                                        t('Next output page', '下一页输出'),
                                      ),
                                    ),
                                  ),
                                if (expanded && block.evicted)
                                  Text(
                                    t(
                                      'Earlier output has left scrollback',
                                      '较早的输出已超出滚动历史保留范围',
                                    ),
                                    style: tokens.metadataStyle,
                                  ),
                              ],
                            ),
                          ),
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  block.running
                                      ? Icons.schedule
                                      : block.exitCode == null
                                      ? Icons.help_outline
                                      : block.exitCode == 0
                                      ? Icons.check
                                      : Icons.error_outline,
                                  size: 14,
                                  color:
                                      block.exitCode != null &&
                                          block.exitCode != 0
                                      ? tokens.error
                                      : tokens.muted,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  block.running
                                      ? t('Running', '运行中')
                                      : block.exitCode == null
                                      ? t('Status unknown', '状态未知')
                                      : t(
                                          'Exit ${block.exitCode}',
                                          '退出码 ${block.exitCode}',
                                        ),
                                  style: tokens.metadataStyle.copyWith(
                                    color:
                                        block.exitCode != null &&
                                            block.exitCode != 0
                                        ? tokens.error
                                        : tokens.muted,
                                  ),
                                ),
                              ],
                            ),
                            if (block.durationMs case final int duration)
                              Text(
                                duration < 1000
                                    ? '${duration}ms'
                                    : '${(duration / 1000).toStringAsFixed(1)}s',
                                style: tokens.metadataStyle,
                              ),
                            if (folded)
                              Text(
                                t(
                                  '${block.totalLines} lines hidden',
                                  '已收起 ${block.totalLines} 行',
                                ),
                                style: tokens.metadataStyle,
                              ),
                            if (c.filtering.contains(block.id))
                              Text(
                                t(
                                  '${block.matchingLines} / ${block.totalLines} lines',
                                  '${block.matchingLines} / ${block.totalLines} 行',
                                ),
                                style: tokens.metadataStyle,
                              ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _blockTerminal(CommandBlock block) => CommandBlockTerminal(
    key: ValueKey('block-terminal-${block.id}'),
    block: block,
    font: widget.font,
    liveInput: block.running ? widget.liveInput : null,
    liveFocus: block.running ? widget.liveFocus : null,
    modes: block.running ? widget.liveModes : TerminalFrameModes.empty,
    onMeasuredCellSizeChanged: (size) {
      widget.onMeasuredCellSizeChanged?.call(size);
      if (mounted && _cellHeight != size.height) {
        setState(() => _cellHeight = size.height);
      }
    },
    onOpenLinkTarget: widget.onOpenLinkTarget,
  );

  Widget _blockSummary(CommandBlock block, ComposerTheme tokens, bool folded) =>
      LayoutBuilder(
        builder: (context, constraints) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight),
              child: Row(
                children: [
                  Expanded(
                    child: Tooltip(
                      message: '${block.cwd}\n${block.command}',
                      child: InkWell(
                        key: _commandKeys.putIfAbsent(block.id, GlobalKey.new),
                        onTap: () => _select(block.id),
                        child: Text(
                          block.command,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tokens.resultStyle,
                        ),
                      ),
                    ),
                  ),
                  Tooltip(
                    message: block.running
                        ? t('Running', '运行中')
                        : t(
                            'Exit ${block.exitCode ?? "?"}',
                            '退出码 ${block.exitCode ?? "?"}',
                          ),
                    child: Icon(
                      block.running
                          ? Icons.schedule
                          : block.exitCode == 0
                          ? Icons.check
                          : Icons.error_outline,
                      size: 14,
                      color: block.exitCode != null && block.exitCode != 0
                          ? tokens.error
                          : tokens.muted,
                    ),
                  ),
                  KeyedSubtree(
                    key: ValueKey('block-expand-${block.id}'),
                    child: _icon(
                      Icons.unfold_more,
                      t('Expand block', '扩大命令块'),
                      () => _toggleOutputHeight(block.id),
                    ),
                  ),
                  PopupMenuButton<String>(
                    key: ValueKey('block-actions-${block.id}'),
                    tooltip: t('Block actions', '命令块操作'),
                    icon: Icon(Icons.more_horiz, size: 17, color: tokens.muted),
                    onSelected: (action) => _action(block, action),
                    itemBuilder: (_) => _menuItems(block),
                  ),
                ],
              ),
            ),
            if (!folded && (block.running || block.lines.isNotEmpty))
              Flexible(child: _blockTerminal(block)),
          ],
        ),
      );
}
