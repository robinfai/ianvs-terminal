import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'command_search_overlay_controller.dart';

class CommandSearchOverlayHost extends StatefulWidget {
  const CommandSearchOverlayHost({
    required this.controller,
    required this.child,
    this.onInsert,
    this.onExplicitExecute,
    this.onViewBlock,
    this.onClose,
    this.loading = false,
    this.unavailableReason,
    super.key,
  });

  final CommandSearchOverlayController controller;
  final Widget child;
  final ValueChanged<String>? onInsert;
  final ValueChanged<String>? onExplicitExecute;
  final ValueChanged<String>? onViewBlock;
  final VoidCallback? onClose;
  final bool loading;
  final String? unavailableReason;

  @override
  State<CommandSearchOverlayHost> createState() =>
      _CommandSearchOverlayHostState();
}

class _CommandSearchOverlayHostState extends State<CommandSearchOverlayHost> {
  late final FocusNode _focusNode;
  var _visible = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'command-search-overlay-host');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (_visible)
            Positioned(
              top: 12,
              right: 12,
              child: CommandSearchOverlay(
                controller: widget.controller,
                onInsert: widget.onInsert,
                onExplicitExecute: widget.onExplicitExecute,
                onViewBlock: widget.onViewBlock,
                onClose: () {
                  setState(() {
                    _visible = false;
                  });
                  widget.onClose?.call();
                },
                loading: widget.loading,
                unavailableReason: widget.unavailableReason,
              ),
            ),
        ],
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.keyR) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) {
      return KeyEventResult.handled;
    }
    if (!HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    setState(() {
      _visible = true;
    });
    return KeyEventResult.handled;
  }
}

class CommandSearchOverlay extends StatefulWidget {
  const CommandSearchOverlay({
    required this.controller,
    this.onInsert,
    this.onExplicitExecute,
    this.onViewBlock,
    this.onClose,
    this.loading = false,
    this.unavailableReason,
    super.key,
  });

  final CommandSearchOverlayController controller;
  final ValueChanged<String>? onInsert;
  final ValueChanged<String>? onExplicitExecute;
  final ValueChanged<String>? onViewBlock;
  final VoidCallback? onClose;
  final bool loading;
  final String? unavailableReason;

  @override
  State<CommandSearchOverlay> createState() => _CommandSearchOverlayState();
}

class _CommandSearchOverlayState extends State<CommandSearchOverlay> {
  late final TextEditingController _queryController;
  late final FocusNode _focusNode;
  late final FocusNode _queryFocusNode;

  @override
  void initState() {
    super.initState();
    widget.controller.handleIntent(CommandSearchOverlayKeyIntent.openSearch);
    _queryController = TextEditingController(
      text: widget.controller.state.query,
    );
    _focusNode = FocusNode(debugLabel: 'command-search-overlay');
    _queryFocusNode = FocusNode(debugLabel: 'command-search-overlay-field');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _queryFocusNode.requestFocus();
      }
    });
  }

  @override
  void didUpdateWidget(covariant CommandSearchOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller &&
        !widget.controller.state.isOpen) {
      widget.controller.handleIntent(CommandSearchOverlayKeyIntent.openSearch);
      _queryController.text = widget.controller.state.query;
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    _focusNode.dispose();
    _queryFocusNode.dispose();
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
        key: const Key('command-search-overlay'),
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
                  key: const Key('command-search-overlay-field'),
                  controller: _queryController,
                  focusNode: _queryFocusNode,
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search command history',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.search,
                  onChanged: (value) {
                    widget.controller.updateQuery(value);
                    setState(() {});
                  },
                  onSubmitted: (_) => _submitSelection(),
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
        text: widget.unavailableReason ?? 'No command history matches',
      );
    }
    return ListView.builder(
      key: const Key('command-search-overlay-results'),
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      itemCount: state.results.length,
      itemBuilder: (context, index) {
        final result = state.results[index];
        final selected = index == state.selectedIndex;
        return _CommandSearchResultTile(
          key: Key(
            selected
                ? 'command-search-result-$index-selected'
                : 'command-search-result-$index',
          ),
          command: result.entry.command,
          cwd: result.entry.cwd,
          statusLabel: _statusLabel(result.entry.exitCode),
          lastRunLabel: _lastRunLabel(result.entry.finishedAt),
          selected: selected,
          onTap: () => _submitOutput(
            CommandSearchOverlayOutput.insert(result.entry.command),
          ),
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
      widget.controller.handleIntent(CommandSearchOverlayKeyIntent.closeSearch);
      widget.onClose?.call();
      setState(() {});
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      widget.controller.handleIntent(CommandSearchOverlayKeyIntent.moveNext);
      setState(() {});
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      widget.controller.handleIntent(
        CommandSearchOverlayKeyIntent.movePrevious,
      );
      setState(() {});
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _submitSelection();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyR &&
        (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed)) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void dispatchOutput(CommandSearchOverlayOutput output) {
    switch (output.kind) {
      case CommandSearchOverlayOutputKind.insert:
        final command = output.command;
        if (command != null) {
          widget.onInsert?.call(command);
        }
      case CommandSearchOverlayOutputKind.explicitExecute:
        final command = output.command;
        if (command != null) {
          widget.onExplicitExecute?.call(command);
        }
      case CommandSearchOverlayOutputKind.viewBlock:
        final invocationId = output.invocationId;
        if (invocationId != null) {
          widget.onViewBlock?.call(invocationId);
        }
      case CommandSearchOverlayOutputKind.none:
        break;
    }
  }

  void debugDispatchOutput(CommandSearchOverlayOutput output) {
    dispatchOutput(output);
  }

  void _submitSelection() {
    final execute =
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final output = widget.controller.handleIntent(
      execute
          ? CommandSearchOverlayKeyIntent.executeSelection
          : CommandSearchOverlayKeyIntent.insertSelection,
    );
    _submitOutput(output);
  }

  void _submitOutput(CommandSearchOverlayOutput output) {
    dispatchOutput(output);
  }
}

bool _isOverlayShortcutKey(LogicalKeyboardKey key) {
  return key == LogicalKeyboardKey.escape ||
      key == LogicalKeyboardKey.arrowDown ||
      key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.keyR;
}

class _CommandSearchResultTile extends StatelessWidget {
  const _CommandSearchResultTile({
    required this.command,
    required this.cwd,
    required this.statusLabel,
    required this.lastRunLabel,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String command;
  final String? cwd;
  final String statusLabel;
  final String lastRunLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? colorScheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  command,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: selected
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (cwd != null && cwd!.isNotEmpty)
                      Text(cwd!, style: theme.textTheme.bodySmall),
                    Text(statusLabel, style: theme.textTheme.bodySmall),
                    Text(lastRunLabel, style: theme.textTheme.bodySmall),
                  ],
                ),
              ],
            ),
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

String _statusLabel(int? exitCode) {
  if (exitCode == 0) {
    return 'Succeeded';
  }
  if (exitCode != null) {
    return 'Failed';
  }
  return 'Unknown';
}

String _lastRunLabel(DateTime finishedAt) {
  return 'Last run ${finishedAt.year.toString().padLeft(4, '0')}-'
      '${finishedAt.month.toString().padLeft(2, '0')}-'
      '${finishedAt.day.toString().padLeft(2, '0')} '
      '${finishedAt.hour.toString().padLeft(2, '0')}:'
      '${finishedAt.minute.toString().padLeft(2, '0')}';
}
