part of 'command_blocks_view.dart';

extension _CommandBlocksCompact on _CommandBlocksViewState {
  Future<void> _openReader(
    String id, {
    bool bottom = false,
    double? row,
  }) async {
    if (_readerOpen) return;
    _follow = false;
    ++_revealSerial;
    _readerOpen = true;
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    if (!mounted) return;
    final block = c.blocks.where((b) => b.id == id).firstOrNull;
    if (block == null) {
      _readerOpen = false;
      return;
    }
    final reinput = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _CommandBlockReader(
          controller: c,
          id: id,
          font: widget.font,
          chinese: widget.chinese,
          initialRow: bottom ? null : row ?? _readingRows[id],
          followTail:
              bottom ||
              row == null && block.running && !_readingRows.containsKey(id),
          onSaveRow: (row) => _readingRows[id] = row,
          onOpenLinkTarget: widget.onOpenLinkTarget,
        ),
      ),
    );
    if (!mounted) return;
    _readerOpen = false;
    // Returning to output must not restore the editor's previous IME focus.
    if (reinput != null) {
      widget.onReinput(reinput);
    } else {
      _focus.requestFocus();
    }
  }

  Widget _compactBlock(CommandBlock block, ComposerTheme tokens) {
    final folded = !block.running && c.collapsed.contains(block.id);
    final failed = block.exitCode != null && block.exitCode != 0;
    final status = block.running
        ? t('Running', '运行中')
        : t('Exit ${block.exitCode ?? "?"}', '退出码 ${block.exitCode ?? "?"}');
    return Semantics(
      key: _keys.putIfAbsent(block.id, GlobalKey.new),
      label: '${t('Command block', '命令块')}: ${block.command}, $status',
      child: Container(
        key: ValueKey('command-block-${block.id}'),
        padding: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: c.dividers
              ? Border(bottom: BorderSide(color: tokens.divider))
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    key: _commandKeys.putIfAbsent(block.id, GlobalKey.new),
                    onTap: () => _openReader(block.id),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          child: Text(
                            block.command.isEmpty
                                ? t('Command', '命令')
                                : block.command,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tokens.resultStyle.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Tooltip(
                  message: status,
                  child: Icon(
                    block.running
                        ? Icons.schedule
                        : failed
                        ? Icons.error_outline
                        : Icons.check,
                    size: 16,
                    color: failed ? tokens.error : tokens.muted,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: t('Block actions', '命令块操作'),
                  icon: Icon(Icons.more_horiz, size: 18, color: tokens.muted),
                  onSelected: (action) => _action(block, action),
                  itemBuilder: (_) => _menuItems(block),
                ),
              ],
            ),
            if (!folded && block.lines.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: CommandBlockTerminal(
                  key: ValueKey('block-terminal-${block.id}'),
                  block: block,
                  font: widget.font,
                  previewLines: 6,
                  scrollOutput: false,
                  requestLiveFocus: false,
                  liveInput: block.running ? widget.liveInput : null,
                  liveFocus: block.running ? widget.liveFocus : null,
                  modes: block.running
                      ? widget.liveModes
                      : TerminalFrameModes.empty,
                  onMeasuredCellSizeChanged: widget.onMeasuredCellSizeChanged,
                  onOpenLinkTarget: widget.onOpenLinkTarget,
                ),
              ),
            if (!folded && block.lines.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  t(
                    block.running ? 'Waiting for output…' : 'No output',
                    block.running ? '等待输出…' : '无输出',
                  ),
                  style: tokens.metadataStyle,
                ),
              ),
            if (folded ||
                block.totalLines > 6 ||
                block.lines.isEmpty && block.totalLines > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: ValueKey('block-expand-${block.id}'),
                  onPressed: () => _openReader(block.id),
                  style: TextButton.styleFrom(
                    foregroundColor: tokens.muted,
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: tokens.metadataStyle,
                  ),
                  icon: const Icon(Icons.open_in_full, size: 14),
                  label: Text(
                    !folded && block.totalLines > 6 && block.lines.isNotEmpty
                        ? t(
                            'Last ${block.lines.length.clamp(1, 6)} of ${block.totalLines} lines · View all',
                            '末尾 ${block.lines.length.clamp(1, 6)} / ${block.totalLines} 行 · 查看全部',
                          )
                        : t(
                            'View all · ${block.totalLines} lines',
                            '查看全部 · ${block.totalLines} 行',
                          ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
