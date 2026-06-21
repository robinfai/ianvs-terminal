part of 'shell_screen.dart';

extension _ShellScreenStateContextChips on _ShellScreenState {
  void _navigateToContextChipBlock({
    required SessionController sessionController,
    required SessionState sessionState,
    required String sessionId,
    required String? blockId,
  }) {
    if (blockId == null) {
      _showContextChipMessage('Command block is unavailable.');
      return;
    }
    final block = _commandBlockCommandCenterAdapter.commandBlockById(
      snapshot:
          _commandBlockSnapshotsBySession[sessionId] ??
          const ShellCommandBlockSnapshot(),
      sessionId: sessionId,
      blockId: blockId,
    );
    if (block == null) {
      _showContextChipMessage('Command block range is unavailable.');
      return;
    }
    _mutateState(() {
      _selectedCommandBlockIdsBySession[sessionId] = block.id;
    });
    final inputRange = block.inputRange;
    if (inputRange != null) {
      ref
          .read(terminalRuntimeControllerProvider)
          .scrollViewportTo(sessionId, inputRange.startRow);
    }
    _focusSession(sessionId);
  }

  Future<void> _openContextChipBlockActions({
    required SessionController sessionController,
    required SessionState sessionState,
    required String sessionId,
    required String? blockId,
    Rect? anchorRect,
    bool showSelectedBlockChip = true,
  }) async {
    final block = _contextChipBlockFor(
      sessionState: sessionState,
      sessionId: sessionId,
      blockId: blockId,
    );
    if (block == null) {
      _showContextChipMessage('Command block is unavailable.');
      return;
    }
    if (showSelectedBlockChip) {
      _mutateState(() {
        _selectedCommandBlockIdsBySession[sessionId] = block.id;
      });
    }
    void runAction(CommandBlockAction action) {
      if (!mounted) {
        return;
      }
      unawaited(
        _runContextChipBlockAction(
          sessionController: sessionController,
          sessionId: sessionId,
          sessionState: action == CommandBlockAction.openReviewEntrypoint
              ? sessionState
              : null,
          block: block,
          action: action,
        ),
      );
    }

    final bookmarked =
        _bookmarkedCommandBlockIdsBySession[sessionId]?.contains(block.id) ??
        false;
    await showMenu<void>(
      context: context,
      position: _contextBlockActionMenuPosition(anchorRect),
      items: [
        PopupMenuItem<void>(
          key: const Key('context-block-action-toggle-bookmark'),
          onTap: () => _toggleCommandBlockBookmark(sessionId, block.id),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                bookmarked ? Icons.bookmark : Icons.bookmark_border,
                size: 18,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(bookmarked ? 'Remove bookmark' : 'Toggle bookmark'),
              ),
            ],
          ),
        ),
        _contextBlockActionMenuItem(
          key: const Key('context-block-action-copy-command'),
          action: CommandBlockAction.copyCommand,
          icon: Icons.content_copy,
          title: 'Copy block command',
          onTap: runAction,
        ),
        _contextBlockActionMenuItem(
          key: const Key('context-block-action-copy-output'),
          action: CommandBlockAction.copyOutput,
          icon: Icons.copy_all,
          title: 'Copy block output',
          onTap: runAction,
        ),
        _contextBlockActionMenuItem(
          key: const Key('context-block-action-copy-both'),
          action: CommandBlockAction.copyBoth,
          icon: Icons.library_books,
          title: 'Copy command and output',
          onTap: runAction,
        ),
        _contextBlockActionMenuItem(
          key: const Key('context-block-action-save-output'),
          action: CommandBlockAction.saveOutput,
          icon: Icons.save_alt,
          title: 'Save block output',
          onTap: runAction,
        ),
        _contextBlockActionMenuItem(
          key: const Key('context-block-action-open-review'),
          action: CommandBlockAction.openReviewEntrypoint,
          icon: Icons.rate_review,
          title: 'Open in review',
          onTap: runAction,
        ),
        _contextBlockActionMenuItem(
          key: const Key('context-block-action-search-within'),
          action: CommandBlockAction.searchWithinBlock,
          icon: Icons.manage_search,
          title: 'Search within block',
          onTap: runAction,
        ),
        _contextBlockActionMenuItem(
          key: const Key('context-block-action-reinput'),
          action: CommandBlockAction.reInput,
          icon: Icons.keyboard_return,
          title: 'Reinput block command',
          onTap: runAction,
        ),
        _contextBlockActionMenuItem(
          key: const Key('context-block-action-rerun'),
          action: CommandBlockAction.rerun,
          icon: Icons.replay,
          title: 'Rerun block command',
          onTap: runAction,
        ),
      ],
    );
  }

  PopupMenuItem<void> _contextBlockActionMenuItem({
    required Key key,
    required CommandBlockAction action,
    required IconData icon,
    required String title,
    required ValueChanged<CommandBlockAction> onTap,
  }) {
    return PopupMenuItem<void>(
      key: key,
      onTap: () => onTap(action),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 10),
          Flexible(child: Text(title)),
        ],
      ),
    );
  }

  RelativeRect _contextBlockActionMenuPosition(Rect? anchorRect) {
    final overlay = Overlay.of(context).context.findRenderObject();
    final overlaySize = overlay is RenderBox
        ? overlay.size
        : MediaQuery.sizeOf(context);
    final overlayBounds = Offset.zero & overlaySize;
    if (anchorRect == null || overlay is! RenderBox) {
      return RelativeRect.fromRect(
        const Rect.fromLTWH(16, 16, 1, 1),
        overlayBounds,
      );
    }
    final topLeft = overlay.globalToLocal(anchorRect.topLeft);
    final bottomRight = overlay.globalToLocal(anchorRect.bottomRight);
    return RelativeRect.fromRect(
      Rect.fromPoints(topLeft, bottomRight),
      overlayBounds,
    );
  }

  CommandBlock? _contextChipBlockFor({
    required SessionState sessionState,
    required String sessionId,
    required String? blockId,
  }) {
    return _commandBlockCommandCenterAdapter.commandBlockById(
      snapshot:
          _commandBlockSnapshotsBySession[sessionId] ??
          const ShellCommandBlockSnapshot(),
      sessionId: sessionId,
      blockId: blockId,
    );
  }

  Future<void> _runContextChipBlockAction({
    required SessionController sessionController,
    required String sessionId,
    SessionState? sessionState,
    required CommandBlock block,
    required CommandBlockAction action,
  }) async {
    final result = const CommandBlockActionReducer().reduce(
      action,
      block,
      readOnly: _isSessionReadOnly(sessionId),
    );
    if (!result.enabled) {
      _showContextChipMessage(
        _contextChipBlockDisabledMessage(result.disabledReason),
      );
      _focusSession(sessionId);
      return;
    }
    await _dispatchCommandActionSearchBlockIntent(
      sessionId,
      sessionController,
      result.intent,
      sessionState: sessionState,
      block: block,
    );
  }

  String _contextChipBlockDisabledMessage(
    CommandBlockActionDisabledReason? reason,
  ) {
    return switch (reason) {
      CommandBlockActionDisabledReason.emptyCommand =>
        'No command block command is available.',
      CommandBlockActionDisabledReason.missingOutputRange =>
        'No command block output is available.',
      CommandBlockActionDisabledReason.missingTerminalFrame =>
        'No terminal frame is available.',
      CommandBlockActionDisabledReason.readOnly => 'Read-only mode is enabled.',
      CommandBlockActionDisabledReason.requiresPastePolicy =>
        'Command block paste requires confirmation.',
      null => 'Command block action is unavailable.',
    };
  }

  void _showContextChipMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
