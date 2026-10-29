import 'package:flutter/material.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

/// Combines native history and the selected AI task without copying output.
/// Existing history precedes the task. Newly observed blocks keep the content
/// anchor where they arrived, until a task entry supplies their canonical slot.
class UnifiedTerminalTimeline extends StatefulWidget {
  const UnifiedTerminalTimeline({
    required this.controller,
    required this.taskId,
    required this.sourceSessionId,
    required this.items,
    required this.builder,
    this.globalBlockIds = false,
    this.blockItemBuilder,
    this.includeBlock,
    super.key,
  });
  final CommandBlockController controller;
  final String taskId;
  final bool globalBlockIds;
  final bool Function(CommandBlock)? includeBlock;
  final CommandBlockTimelineItem Function(CommandBlock)? blockItemBuilder;
  final String sourceSessionId;
  final List<CommandBlockTimelineItem> items;
  final Widget Function(List<CommandBlockTimelineItem>) builder;

  @override
  State<UnifiedTerminalTimeline> createState() =>
      _UnifiedTerminalTimelineState();
}

class _UnifiedTerminalTimelineState extends State<UnifiedTerminalTimeline> {
  final _anchors = <String, String?>{};
  bool _initialized = false;

  @override
  void didUpdateWidget(UnifiedTerminalTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.taskId != widget.taskId ||
        oldWidget.controller != widget.controller ||
        oldWidget.sourceSessionId != widget.sourceSessionId) {
      _anchors.clear();
      _initialized = false;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (_, _) {
      final blocks = widget.controller.blocks
          .where((block) => widget.includeBlock?.call(block) ?? true)
          .toList();
      final taskItems = widget.items
          .where((item) => item.id != 'empty')
          .toList();
      final itemIds = taskItems.map((item) => item.id).toSet();
      final referenced = {
        for (final item in taskItems)
          if (item.blockId != null &&
              (widget.globalBlockIds ||
                  item.sourceSessionId == null ||
                  item.sourceSessionId == widget.sourceSessionId))
            item.blockId!,
      };
      for (final block in blocks) {
        _anchors.putIfAbsent(
          block.id,
          () => _initialized ? taskItems.lastOrNull?.id : null,
        );
      }
      // An empty initial history is still an observed baseline. The first
      // live block belongs after the current conversation, not before it.
      _initialized = true;
      final byAnchor = <String?, List<CommandBlockTimelineItem>>{};
      for (final block in blocks) {
        if (referenced.contains(block.id)) continue;
        final anchor = _anchors[block.id];
        (byAnchor[itemIds.contains(anchor) ? anchor : null] ??= []).add(
          widget.blockItemBuilder?.call(block) ??
              CommandBlockTimelineItem.block(
                block.id,
                id: 'native-${widget.sourceSessionId}-${block.id}',
                sourceSessionId: widget.sourceSessionId,
              ),
        );
      }
      return widget.builder([
        ...?byAnchor[null],
        for (final item in taskItems) ...[item, ...?byAnchor[item.id]],
        if (blocks.isEmpty && taskItems.isEmpty) ...widget.items,
      ]);
    },
  );
}
