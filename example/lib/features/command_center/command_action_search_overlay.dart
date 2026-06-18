import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'command_action_search_controller.dart';
import 'command_action_search_index.dart';

class CommandActionSearchOverlay extends StatefulWidget {
  const CommandActionSearchOverlay({
    required this.controller,
    this.onOpenAction,
    this.onInsertSavedCommand,
    this.onInsertSavedCommandItem,
    this.onClose,
    this.loading = false,
    this.unavailableReason,
    super.key,
  });

  final CommandActionSearchController controller;
  final ValueChanged<String>? onOpenAction;
  final ValueChanged<String>? onInsertSavedCommand;
  final ValueChanged<CommandActionSearchItem>? onInsertSavedCommandItem;
  final VoidCallback? onClose;
  final bool loading;
  final String? unavailableReason;

  @override
  State<CommandActionSearchOverlay> createState() =>
      _CommandActionSearchOverlayState();
}

class _CommandActionSearchOverlayState
    extends State<CommandActionSearchOverlay> {
  late final TextEditingController _queryController;
  late final FocusNode _focusNode;
  late final FocusNode _queryFocusNode;

  @override
  void initState() {
    super.initState();
    widget.controller.handleIntent(CommandActionSearchIntent.openSearch);
    _queryController = TextEditingController(
      text: widget.controller.state.query,
    );
    _focusNode = FocusNode(debugLabel: 'command-action-search-overlay');
    _queryFocusNode = FocusNode(
      debugLabel: 'command-action-search-overlay-query',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _queryFocusNode.requestFocus();
      }
    });
  }

  @override
  void didUpdateWidget(covariant CommandActionSearchOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller &&
        !widget.controller.state.isOpen) {
      widget.controller.handleIntent(CommandActionSearchIntent.openSearch);
      _queryController.text = widget.controller.state.query;
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    _queryFocusNode.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    if (!state.isOpen) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: Material(
        key: const Key('command-action-search-overlay'),
        elevation: 6,
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: TextField(
                  key: const Key('command-action-search-overlay-field'),
                  controller: _queryController,
                  focusNode: _queryFocusNode,
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.manage_search),
                    hintText: 'Search actions and saved commands',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.search,
                  onChanged: (value) {
                    widget.controller.updateQuery(value);
                    setState(() {});
                  },
                ),
              ),
              if (widget.loading) const LinearProgressIndicator(minHeight: 2),
              Flexible(child: _buildBody(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final state = widget.controller.state;
    if (state.results.isEmpty) {
      return _OverlayMessage(
        text: widget.unavailableReason ?? 'No actions or saved commands match',
      );
    }
    return ListView.builder(
      key: const Key('command-action-search-overlay-results'),
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      itemCount: state.results.length,
      itemBuilder: (context, index) {
        final result = state.results[index];
        final selected = index == state.selectedIndex;
        return _CommandActionSearchResultTile(
          key: Key(
            selected
                ? 'command-action-search-result-$index-selected'
                : 'command-action-search-result-$index',
          ),
          item: result.item,
          selected: selected,
        );
      },
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (event is! KeyDownEvent) {
      return _isOverlayShortcutKey(key)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.escape) {
      widget.controller.handleIntent(CommandActionSearchIntent.closeSearch);
      widget.onClose?.call();
      setState(() {});
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      widget.controller.handleIntent(CommandActionSearchIntent.moveNext);
      setState(() {});
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      widget.controller.handleIntent(CommandActionSearchIntent.movePrevious);
      setState(() {});
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final output = widget.controller.handleIntent(
        CommandActionSearchIntent.acceptSelection,
      );
      _dispatchOutput(output);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _dispatchOutput(CommandActionSearchOutput output) {
    switch (output.kind) {
      case CommandActionSearchOutputKind.openAction:
        final actionId = output.actionId;
        if (actionId != null) {
          widget.onOpenAction?.call(actionId);
        }
      case CommandActionSearchOutputKind.insertSavedCommand:
        final item = output.item;
        if (item != null) {
          widget.onInsertSavedCommandItem?.call(item);
        }
        final command = output.command;
        if (command != null) {
          widget.onInsertSavedCommand?.call(command);
        }
      case CommandActionSearchOutputKind.none:
        break;
    }
  }
}

bool _isOverlayShortcutKey(LogicalKeyboardKey key) {
  return key == LogicalKeyboardKey.escape ||
      key == LogicalKeyboardKey.arrowDown ||
      key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter;
}

class _CommandActionSearchResultTile extends StatelessWidget {
  const _CommandActionSearchResultTile({
    required this.item,
    required this.selected,
    super.key,
  });

  final CommandActionSearchItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedTextColor = selected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? colorScheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _iconForKind(item.kind),
              size: 20,
              color: selected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: selectedTextColor,
                    ),
                  ),
                  if (_supportingText(item) case final supporting?
                      when supporting.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      supporting,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: selected
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _MetaPill(
                        label: _kindLabel(item.kind),
                        selected: selected,
                      ),
                      for (final tag in item.tags)
                        Text(tag, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.primary.withValues(alpha: 0.16)
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: selected
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _OverlayMessage extends StatelessWidget {
  const _OverlayMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

IconData _iconForKind(CommandActionSearchItemKind kind) {
  return switch (kind) {
    CommandActionSearchItemKind.appAction => Icons.bolt,
    CommandActionSearchItemKind.savedCommand => Icons.bookmark_border,
  };
}

String _kindLabel(CommandActionSearchItemKind kind) {
  return switch (kind) {
    CommandActionSearchItemKind.appAction => 'Action',
    CommandActionSearchItemKind.savedCommand => 'Saved command',
  };
}

String? _supportingText(CommandActionSearchItem item) {
  return switch (item.kind) {
    CommandActionSearchItemKind.appAction => item.subtitle,
    CommandActionSearchItemKind.savedCommand => item.command,
  };
}
