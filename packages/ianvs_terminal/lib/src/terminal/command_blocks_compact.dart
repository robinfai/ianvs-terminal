part of 'command_blocks_view.dart';

extension _CommandBlocksCompact on _CommandBlocksViewState {
  Future<void> _openReader(
    String id, {
    bool bottom = false,
    double? row,
    CommandBlockReadRange? range,
  }) async {
    if (_readerOpen) return;
    _follow = false;
    ++_revealSerial;
    _readerOpen = true;
    final readerHost = CommandBlockReaderHost.maybeOf(context);
    final block = c.blocks.where((b) => b.id == id).firstOrNull;
    if (block == null) {
      _readerOpen = false;
      return;
    }
    final source = _items.where((item) => item.blockId == id).firstOrNull;
    final reinput = await showCommandBlockReader(
      context,
      controller: c,
      id: id,
      sourceLabel: source?.sourceLabel,
      sourceDetails: source?.sourceSessionId == null
          ? null
          : '${source!.sourceSessionId} · $id',
      returnFocus: _focus,
      font: widget.font,
      chinese: widget.chinese,
      initialRow: bottom ? null : row,
      initialRange: range,
      followTail:
          bottom ||
          row == null &&
              range == null &&
              block.running &&
              !c.readingStates.containsKey(id),
      onOpenLinkTarget: widget.onOpenLinkTarget,
      onAttachRange: widget.onAttachRange,
    );
    if (!mounted) return;
    _readerOpen = false;
    // Returning to output must not restore the editor's previous IME focus.
    if (readerHost != null &&
        (!readerHost.active || readerHost.widget.controller.isOpen)) {
      return;
    }
    if (reinput != null) {
      widget.onReinput(reinput);
    } else if (readerHost == null) {
      _focus.requestFocus();
    }
  }

  Widget _compactBlock(CommandBlock block, ComposerTheme tokens) {
    final folded = !block.running && c.collapsed.contains(block.id);
    final failed =
        !block.running && block.exitCode != null && block.exitCode != 0;
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
                            maxLines: 2,
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
                        : block.exitCode == 0
                        ? Icons.check
                        : Icons.help_outline,
                    size: 16,
                    color: failed ? tokens.error : tokens.muted,
                  ),
                ),
                if (block.durationMs != null ||
                    block.running && block.startedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: _CommandBlockElapsed(
                      block: block,
                      style: tokens.metadataStyle,
                      chinese: widget.chinese,
                    ),
                  ),
                PopupMenuButton<String>(
                  popUpAnimationStyle: ComposerTheme.overlayAnimation(context),
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
                  liveInput: block.running && !block.suspended
                      ? widget.liveInput
                      : null,
                  liveFocus: block.running && !block.suspended
                      ? widget.liveFocus
                      : null,
                  modes: block.running && !block.suspended
                      ? widget.liveModes
                      : TerminalFrameModes.empty,
                  onMeasuredCellSizeChanged: widget.onMeasuredCellSizeChanged,
                  onOpenLinkTarget: widget.onOpenLinkTarget,
                ),
              ),
            if (failed && widget.onAskAi != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: ValueKey('block-ai-diagnose-${block.id}'),
                  onPressed: () => widget.onAskAi!(block),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: tokens.metadataStyle,
                  ),
                  icon: const Icon(Icons.auto_awesome_outlined, size: 16),
                  label: Text(t('AI diagnosis', 'AI 诊断')),
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
