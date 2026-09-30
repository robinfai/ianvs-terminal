part of 'command_blocks_view.dart';

extension _CommandBlocksControls on _CommandBlocksViewState {
  Widget _icon(IconData icon, String label, VoidCallback action) => IconButton(
    tooltip: label,
    onPressed: action,
    icon: Icon(icon, size: 17),
    style: IconButton.styleFrom(
      minimumSize: Size.square(ComposerTheme.of(context).controlHeight),
      padding: const EdgeInsets.all(7),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  );

  Widget _toolbar(ComposerTheme tokens) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 4, 12, 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            c.selected.length > 1
                ? t(
                    '${c.selected.length} selected',
                    '已选择 ${c.selected.length} 个',
                  )
                : t('Blocks · ${c.blocks.length}', '命令块 · ${c.blocks.length}'),
            style: tokens.metadataStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _icon(
          Icons.search,
          t('Find in blocks', '在命令块中查找'),
          () => _openFind(null),
        ),
        if (c.bookmarks.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: t('Bookmarks', '书签'),
            icon: Icon(Icons.bookmark_outline, size: 17, color: tokens.muted),
            onSelected: (id) => c.select(id, reveal: true),
            itemBuilder: (_) => [
              for (final block in c.blocks.where(
                (b) => c.bookmarks.contains(b.id),
              ))
                PopupMenuItem(
                  value: block.id,
                  child: Text(
                    block.command,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        _icon(
          Icons.vertical_align_bottom,
          t('Jump to latest output', '跳到最新输出'),
          () {
            _follow = true;
            _tail();
          },
        ),
        PopupMenuButton<String>(
          tooltip: t('Block view options', '命令块显示选项'),
          icon: Icon(Icons.tune, size: 17, color: tokens.muted),
          onSelected: (value) {
            switch (value) {
              case 'compact':
                c.setAppearance(compact: !c.compact);
              case 'dividers':
                c.setAppearance(dividers: !c.dividers);
              case 'sticky':
                c.setAppearance(stickyHeader: !c.stickyHeader);
              case 'terminal':
                widget.onUseTerminal?.call();
            }
          },
          itemBuilder: (_) => [
            if (!_readerLayout)
              CheckedPopupMenuItem(
                value: 'compact',
                checked: c.compact,
                child: Text(t('Compact spacing', '紧凑间距')),
              ),
            CheckedPopupMenuItem(
              value: 'dividers',
              checked: c.dividers,
              child: Text(t('Block dividers', '命令块分隔线')),
            ),
            if (!_readerLayout)
              CheckedPopupMenuItem(
                value: 'sticky',
                checked: c.stickyHeader,
                child: Text(t('Sticky command header', '固定命令标题')),
              ),
            if (widget.onUseTerminal != null)
              PopupMenuItem(
                value: 'terminal',
                child: Text(t('Use terminal input', '使用终端输入')),
              ),
          ],
        ),
      ],
    ),
  );
  List<PopupMenuEntry<String>> _menuItems(CommandBlock block) => [
    PopupMenuItem(value: 'command', child: Text(t('Copy command', '复制命令'))),
    PopupMenuItem(value: 'output', child: Text(t('Copy output', '复制输出'))),
    PopupMenuItem(
      value: 'both',
      child: Text(
        t(
          c.selected.length > 1
              ? 'Copy selected blocks'
              : 'Copy command and output',
          c.selected.length > 1 ? '复制所选命令块' : '复制命令和输出',
        ),
      ),
    ),
    const PopupMenuDivider(),
    PopupMenuItem(
      value: 'reinput',
      enabled: block.command.isNotEmpty,
      child: Text(t('Insert into Composer', '放入 Composer 编辑')),
    ),
    PopupMenuItem(value: 'find', child: Text(t('Find within block', '在此块中查找'))),
    CheckedPopupMenuItem(
      value: 'filter',
      enabled: !block.running,
      checked: c.filtering.contains(block.id),
      child: Text(t('Filter output', '过滤输出')),
    ),
    CheckedPopupMenuItem(
      value: 'bookmark',
      checked: c.bookmarks.contains(block.id),
      child: Text(t('Bookmark', '书签')),
    ),
    PopupMenuItem(
      value: 'collapse',
      enabled: !block.running,
      child: Text(
        t(
          c.collapsed.contains(block.id) ? 'Expand output' : 'Collapse output',
          c.collapsed.contains(block.id) ? '展开输出' : '折叠输出',
        ),
      ),
    ),
    PopupMenuItem(value: 'top', child: Text(t('Jump to start', '跳到开头'))),
    PopupMenuItem(value: 'bottom', child: Text(t('Jump to end', '跳到末尾'))),
    const PopupMenuDivider(),
    PopupMenuItem(
      value: 'share',
      enabled: !block.running,
      child: Text(t('Export as Markdown…', '导出为 Markdown…')),
    ),
  ];
  Future<void> _menu(CommandBlock block, Offset point) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(point.dx, point.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: _menuItems(block),
    );
    if (mounted && value != null) _action(block, value);
  }

  void _action(CommandBlock block, String action) {
    switch (action) {
      case 'command':
      case 'output':
      case 'both':
        unawaited(
          _copy(
            action,
            id: action == 'both' && c.selected.length > 1 ? null : block.id,
          ),
        );
      case 'reinput':
        widget.onReinput(block.command);
      case 'find':
        _openFind(block.id);
      case 'filter':
        c.toggleFilter(block.id);
        if (_readerLayout) unawaited(_openReader(block.id));
      case 'bookmark':
        c.toggleBookmark(block.id);
      case 'collapse':
        c.toggleCollapsed(block.id);
      case 'top':
        if (_readerLayout) {
          unawaited(_openReader(block.id, row: 0));
        } else {
          c.reveal(block.id);
        }
      case 'bottom':
        if (_readerLayout) {
          unawaited(_openReader(block.id, bottom: true));
        } else {
          c.reveal(block.id, bottom: true);
        }
      case 'share':
        unawaited(_export(block));
    }
  }

  Future<void> _export(CommandBlock block) async {
    try {
      final output = await c.outputText(block.id);
      if (!mounted) return;
      var commandIncluded = true;
      var outputIncluded = true;
      var contextIncluded = false;
      String markdown() {
        final content = [
          if (commandIncluded) block.command,
          if (outputIncluded) output,
        ].join('\n');
        var fenceLength = 3;
        while (content.contains('`' * fenceLength)) {
          fenceLength++;
        }
        final fence = '`' * fenceLength;
        return '${contextIncluded ? '${block.cwd}\nExit ${block.exitCode ?? "unknown"}\n\n' : ''}$fence\n$content\n$fence';
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(t('Export block', '导出命令块')),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t(
                        'Choose what to include in the Markdown copy.',
                        '选择复制到 Markdown 的内容。',
                      ),
                    ),
                    CheckboxListTile(
                      value: commandIncluded,
                      onChanged: (v) =>
                          setDialogState(() => commandIncluded = v!),
                      title: Text(t('Command', '命令')),
                      contentPadding: EdgeInsets.zero,
                    ),
                    CheckboxListTile(
                      value: outputIncluded,
                      onChanged: (v) =>
                          setDialogState(() => outputIncluded = v!),
                      title: Text(t('Output', '输出')),
                      contentPadding: EdgeInsets.zero,
                    ),
                    CheckboxListTile(
                      value: contextIncluded,
                      onChanged: (v) =>
                          setDialogState(() => contextIncluded = v!),
                      title: Text(t('Directory and exit status', '目录和退出状态')),
                      contentPadding: EdgeInsets.zero,
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          markdown(),
                          style: ComposerTheme.of(context).metadataStyle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t('Cancel', '取消')),
              ),
              FilledButton(
                onPressed: !commandIncluded && !outputIncluded
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(text: markdown()),
                        );
                        if (context.mounted) Navigator.pop(context);
                        _announce(t('Markdown copied', '已复制 Markdown'));
                      },
                child: Text(t('Copy Markdown', '复制 Markdown')),
              ),
            ],
          ),
        ),
      );
    } on Object catch (error) {
      _announce(error.toString());
    }
  }

  Widget _findBar(ComposerTheme tokens) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _find,
                focusNode: _findFocus,
                onChanged: (_) => _search(),
                onSubmitted: (_) {
                  if (_matches.isNotEmpty) _showMatch(_matches.first);
                },
                decoration: InputDecoration(
                  isDense: true,
                  hintText: t('Find commands and output', '查找命令和输出'),
                  prefixIcon: const Icon(Icons.search, size: 17),
                  errorText: _findError,
                ),
                style: tokens.resultStyle,
              ),
            ),
            _icon(Icons.close, t('Close find', '关闭查找'), () {
              _update(() => _finding = false);
              _focus.requestFocus();
            }),
          ],
        ),
        Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChip(
              label: const Text('Aa'),
              tooltip: t('Case sensitive', '区分大小写'),
              selected: _findCase,
              onSelected: (v) {
                _update(() => _findCase = v);
                _search();
              },
            ),
            FilterChip(
              label: const Text('.*'),
              tooltip: t('Regular expression', '正则表达式'),
              selected: _findRegex,
              onSelected: (v) {
                _update(() => _findRegex = v);
                _search();
              },
            ),
            if (_findScope != null)
              InputChip(
                label: Text(t('This block', '当前块')),
                onDeleted: () {
                  _update(() => _findScope = null);
                  _search();
                },
              ),
            Text(
              t('${_matches.length} matching lines', '${_matches.length} 行匹配'),
              style: tokens.metadataStyle,
            ),
          ],
        ),
        if (_find.text.isNotEmpty && _matches.isEmpty && _findError == null)
          Padding(
            padding: const EdgeInsets.all(6),
            child: Text(t('No matches', '无匹配结果'), style: tokens.metadataStyle),
          ),
        if (_matches.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 130),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _matches.length,
              itemBuilder: (context, index) {
                final match = _matches[index];
                return ListTile(
                  dense: true,
                  title: Text(
                    match.$2.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.resultStyle,
                  ),
                  subtitle: Text(
                    match.$1.command,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.metadataStyle,
                  ),
                  onTap: () => _showMatch(match),
                );
              },
            ),
          ),
      ],
    ),
  );
  void _showMatch((CommandBlock, TerminalRow) match) {
    c.expandedOutput.add(match.$1.id);
    if (c.filtering.contains(match.$1.id)) c.toggleFilter(match.$1.id);
    if (c.collapsed.contains(match.$1.id)) c.toggleCollapsed(match.$1.id);
    if (_readerLayout) {
      unawaited(_openReader(match.$1.id, row: match.$2.index.toDouble()));
      return;
    }
    if (match.$2.index >= 0) c.page(match.$1.id, match.$2.index);
    c.select(match.$1.id, reveal: true);
  }
}

class _BlockFilterEditor extends StatefulWidget {
  const _BlockFilterEditor({
    super.key,
    required this.value,
    required this.chinese,
    required this.onChanged,
    required this.onClose,
    this.error,
  });
  final CommandBlockFilter value;
  final bool chinese;
  final ValueChanged<CommandBlockFilter> onChanged;
  final VoidCallback onClose;
  final String? error;
  @override
  State<_BlockFilterEditor> createState() => _BlockFilterEditorState();
}

class _BlockFilterEditorState extends State<_BlockFilterEditor> {
  late final _query = TextEditingController(text: widget.value.query);
  Timer? _debounce;
  String t(String en, String zh) => widget.chinese ? zh : en;
  @override
  void dispose() {
    _query.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _query,
                style: ComposerTheme.of(context).resultStyle,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: t('Filter output', '过滤输出'),
                  errorText: widget.error,
                  prefixIcon: const Icon(Icons.filter_list, size: 17),
                ),
                onChanged: (query) {
                  _debounce?.cancel();
                  _debounce = Timer(
                    const Duration(milliseconds: 160),
                    () => widget.onChanged(widget.value.copyWith(query: query)),
                  );
                },
              ),
            ),
            IconButton(
              tooltip: t('Close filter', '关闭过滤'),
              onPressed: widget.onClose,
              icon: const Icon(Icons.close, size: 17),
            ),
          ],
        ),
        Wrap(
          spacing: 4,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChip(
              label: const Text('Aa'),
              tooltip: t('Case sensitive', '区分大小写'),
              selected: widget.value.caseSensitive,
              onSelected: (v) =>
                  widget.onChanged(widget.value.copyWith(caseSensitive: v)),
            ),
            FilterChip(
              label: const Text('.*'),
              tooltip: t('Regular expression', '正则表达式'),
              selected: widget.value.regex,
              onSelected: (v) =>
                  widget.onChanged(widget.value.copyWith(regex: v)),
            ),
            FilterChip(
              label: Text(t('Invert', '反向')),
              selected: widget.value.invert,
              onSelected: (v) =>
                  widget.onChanged(widget.value.copyWith(invert: v)),
            ),
            PopupMenuButton<int>(
              tooltip: t('Context lines', '上下文行数'),
              onSelected: (v) =>
                  widget.onChanged(widget.value.copyWith(contextLines: v)),
              itemBuilder: (_) => [
                for (final n in [0, 1, 2, 3, 5, 10, 20])
                  PopupMenuItem(value: n, child: Text('$n')),
              ],
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  t(
                    'Context ${widget.value.contextLines}',
                    '上下文 ${widget.value.contextLines}',
                  ),
                  style: ComposerTheme.of(context).actionStyle,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
