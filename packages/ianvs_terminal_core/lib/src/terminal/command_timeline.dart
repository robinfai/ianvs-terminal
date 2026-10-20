import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A point inside an identified message/block, independent of preceding heights.
@immutable
class CommandTimelineAnchor {
  const CommandTimelineAnchor({
    required this.itemId,
    required this.offset,
    required this.scrollOffset,
  });
  final String itemId;
  final double offset;
  final double scrollOffset;
}

/// Hosts can retain an anchor per task without owning the timeline's render tree.
class CommandTimelineScrollController extends ScrollController {
  CommandTimelineScrollController({
    super.initialScrollOffset,
    this.onReadingAnchorChanged,
  });
  final ValueChanged<CommandTimelineAnchor>? onReadingAnchorChanged;
  _CommandTimelineViewState? _view;
  CommandTimelineAnchor? get readingAnchor => _view?._capture();

  /// An explicit navigation action. Ordinary content updates correct layout
  /// inside the sliver instead, so they never cancel a drag or fling.
  Future<bool> restoreReadingAnchor(CommandTimelineAnchor anchor) async =>
      await _view?._restore(anchor) ?? false;

  /// A newer explicit navigation must win over an in-flight anchor restore.
  void cancelReadingRestoration() => _view?._cancelRestoration();
}

class CommandTimelineView extends StatefulWidget {
  const CommandTimelineView({
    required this.controller,
    required this.itemIds,
    required this.itemBuilder,
    required this.followTail,
    this.padding = EdgeInsets.zero,
    super.key,
  });
  final ScrollController controller;
  final List<String> itemIds;
  final IndexedWidgetBuilder itemBuilder;
  final bool Function() followTail;
  final EdgeInsets padding;

  @override
  State<CommandTimelineView> createState() => _CommandTimelineViewState();
}

class _CommandTimelineViewState extends State<CommandTimelineView> {
  final GlobalKey _sliverKey = GlobalKey();
  int _navigation = 0;
  bool _restoring = false;
  bool _reportScheduled = false;
  _ReadingSliverList? get _sliver =>
      _sliverKey.currentContext?.findRenderObject() as _ReadingSliverList?;

  @override
  void initState() {
    super.initState();
    _attach(widget.controller);
  }

  void _attach(ScrollController scroll) {
    if (scroll is CommandTimelineScrollController) scroll._view = this;
    scroll.addListener(_publish);
  }

  void _detach(ScrollController scroll) {
    if (scroll is CommandTimelineScrollController && scroll._view == this) {
      scroll._view = null;
    }
    scroll.removeListener(_publish);
  }

  @override
  void didUpdateWidget(CommandTimelineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller &&
        !widget.followTail() &&
        !_restoring) {
      // Capture before SliverMultiBoxAdaptorElement remaps keyed children and
      // replaces their old layout offsets with offsets at the new indices.
      final anchor = _capture();
      if (anchor != null) _sliver?.prepareAnchor(anchor);
    }
    if (oldWidget.controller != widget.controller) {
      _detach(oldWidget.controller);
      _attach(widget.controller);
    }
  }

  @override
  void dispose() {
    _navigation++;
    _detach(widget.controller);
    super.dispose();
  }

  CommandTimelineAnchor? _capture() => widget.controller.hasClients
      ? _sliver?.capture(widget.controller.offset - widget.padding.top)
      : null;

  void _publish() {
    if (!mounted || _restoring) return;
    if (widget.controller case final CommandTimelineScrollController scroll) {
      final anchor = _capture();
      if (anchor != null) scroll.onReadingAnchorChanged?.call(anchor);
    }
  }

  void _afterLayout() {
    if (_reportScheduled) return;
    _reportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportScheduled = false;
      if (!mounted) return;
      if (widget.followTail() && !_restoring && widget.controller.hasClients) {
        final position = widget.controller.position;
        if ((position.pixels - position.maxScrollExtent).abs() > .1) {
          widget.controller.jumpTo(position.maxScrollExtent);
        }
      }
      _publish();
    });
  }

  Future<bool> _restore(CommandTimelineAnchor anchor) async {
    final serial = ++_navigation;
    if (!widget.itemIds.contains(anchor.itemId)) return false;
    _restoring = true;
    try {
      for (var attempt = 0; attempt < 24; attempt++) {
        WidgetsBinding.instance.scheduleFrame();
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted ||
            serial != _navigation ||
            !widget.controller.hasClients) {
          return false;
        }
        final sliver = _sliver;
        if (sliver == null) return false;
        final index = widget.itemIds.indexOf(anchor.itemId);
        if (index < 0) return false;
        final exact = sliver.offsetFor(anchor);
        final next =
            (exact ?? sliver.estimateOffset(index, anchor.scrollOffset)) +
            widget.padding.top;
        final position = widget.controller.position;
        final target = next.clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        if (exact != null && (target - position.pixels).abs() < .1) return true;
        if ((target - position.pixels).abs() > .1) {
          widget.controller.jumpTo(target);
        }
      }
      return false;
    } finally {
      if (serial == _navigation) {
        _restoring = false;
        _publish();
      }
    }
  }

  void _cancelRestoration() {
    _navigation++;
    _restoring = false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.depth == 0 &&
              (notification is ScrollStartNotification &&
                      notification.dragDetails != null ||
                  notification is UserScrollNotification &&
                      notification.direction != ScrollDirection.idle)) {
            _cancelRestoration();
          }
          return false;
        },
        child: CustomScrollView(
          controller: widget.controller,
          semanticChildCount: widget.itemIds.length,
          slivers: [
            SliverPadding(
              padding: widget.padding,
              sliver: _ReadingList(
                key: _sliverKey,
                itemIds: widget.itemIds,
                preserveAnchor: () => !widget.followTail() && !_restoring,
                afterLayout: _afterLayout,
                delegate: SliverChildBuilderDelegate(
                  (context, index) => KeyedSubtree(
                    key: ValueKey(widget.itemIds[index]),
                    child: widget.itemBuilder(context, index),
                  ),
                  childCount: widget.itemIds.length,
                  findChildIndexCallback: (key) {
                    if (key is! ValueKey<String>) return null;
                    final index = widget.itemIds.indexOf(key.value);
                    return index < 0 ? null : index;
                  },
                ),
              ),
            ),
          ],
        ),
      );
}

class _ReadingList extends SliverList {
  const _ReadingList({
    required super.delegate,
    required this.itemIds,
    required this.preserveAnchor,
    required this.afterLayout,
    super.key,
  });
  final List<String> itemIds;
  final bool Function() preserveAnchor;
  final VoidCallback afterLayout;

  @override
  _ReadingSliverList createRenderObject(BuildContext context) =>
      _ReadingSliverList(
        childManager: context as SliverMultiBoxAdaptorElement,
        itemIds: itemIds,
        preserveAnchor: preserveAnchor,
        afterLayout: afterLayout,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _ReadingSliverList renderObject,
  ) {
    renderObject
      ..itemIds = itemIds
      ..preserveAnchor = preserveAnchor
      ..afterLayout = afterLayout;
  }
}

class _ReadingSliverList extends RenderSliverList {
  _ReadingSliverList({
    required super.childManager,
    required this.itemIds,
    required this.preserveAnchor,
    required this.afterLayout,
  });
  List<String> itemIds;
  bool Function() preserveAnchor;
  VoidCallback afterLayout;
  CommandTimelineAnchor? _pendingAnchor;
  int _corrections = 0;

  void prepareAnchor(CommandTimelineAnchor anchor) {
    _pendingAnchor ??= anchor;
    _corrections = 0;
  }

  RenderBox? _at(double scrollOffset) {
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final top = childScrollOffset(child);
      if (top != null &&
          child.hasSize &&
          (top <= scrollOffset || indexOf(child) == 0 && scrollOffset < 0) &&
          top + paintExtentOf(child) > scrollOffset) {
        return child;
      }
    }
    return null;
  }

  CommandTimelineAnchor? capture(double scrollOffset) {
    final child = _at(scrollOffset);
    if (child == null) return null;
    final index = indexOf(child);
    if (index < 0 || index >= itemIds.length) return null;
    return CommandTimelineAnchor(
      itemId: itemIds[index],
      offset: scrollOffset - childScrollOffset(child)!,
      scrollOffset: scrollOffset,
    );
  }

  double? offsetFor(CommandTimelineAnchor anchor) {
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final index = indexOf(child);
      if (index >= itemIds.length || itemIds[index] != anchor.itemId) continue;
      final top = childScrollOffset(child);
      if (top == null || !child.hasSize) return null;
      return top + anchor.offset.clamp(0, paintExtentOf(child));
    }
    return null;
  }

  double estimateOffset(int target, double fallback) {
    final first = firstChild;
    final last = lastChild;
    if (first == null || last == null || !last.hasSize) return fallback;
    final start = childScrollOffset(first);
    final end = childScrollOffset(last);
    if (start == null || end == null) return fallback;
    final average =
        (end + paintExtentOf(last) - start) /
        (indexOf(last) - indexOf(first) + 1);
    return start + (target - indexOf(first)) * average;
  }

  @override
  void performLayout() {
    final anchor = preserveAnchor() ? _at(constraints.scrollOffset) : null;
    final before = anchor == null ? null : childScrollOffset(anchor);
    super.performLayout();
    if (geometry?.scrollOffsetCorrection != null) return;
    final pending = _pendingAnchor;
    if (pending != null) {
      final index = itemIds.indexOf(pending.itemId);
      if (index >= 0 && preserveAnchor()) {
        final target =
            offsetFor(pending) ??
            estimateOffset(index, pending.scrollOffset) + pending.offset;
        final delta = target - pending.scrollOffset;
        if (delta.abs() > .1 && _corrections++ < 6) {
          _pendingAnchor = CommandTimelineAnchor(
            itemId: pending.itemId,
            offset: pending.offset,
            scrollOffset: pending.scrollOffset + delta,
          );
          geometry = SliverGeometry(scrollOffsetCorrection: delta);
          return;
        }
      }
      _pendingAnchor = null;
      afterLayout();
      return;
    }
    if (anchor != null && anchor.parent == this && before != null) {
      final after = childScrollOffset(anchor);
      if (after != null && (after - before).abs() > .1) {
        // Viewport applies this during layout, preserving the active drag or
        // ballistic velocity. A post-frame jumpTo would stop that gesture.
        geometry = SliverGeometry(scrollOffsetCorrection: after - before);
        return;
      }
    }
    afterLayout();
  }
}
