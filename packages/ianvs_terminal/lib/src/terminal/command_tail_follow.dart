part of 'command_blocks_view.dart';

/// Reattach only after the user finishes scrolling toward the bottom. A small
/// upward movement must release the tail even inside the magnetic distance;
/// layout changes and nested scrollables must never reattach it by themselves.
class _CommandTailFollow {
  bool _userScrolling = false;
  ScrollDirection _direction = ScrollDirection.idle;

  bool handle(
    ScrollNotification notification, {
    required double distance,
    required VoidCallback detach,
    required VoidCallback attach,
    bool canAttach = true,
  }) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _userScrolling = true;
      detach();
    }
    if (notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle) {
      _userScrolling = true;
      _direction = notification.direction;
      detach();
    }
    if (notification is ScrollEndNotification) {
      final reattach =
          _userScrolling &&
          _direction == ScrollDirection.reverse &&
          notification.metrics.extentAfter <= distance &&
          canAttach;
      _userScrolling = false;
      _direction = ScrollDirection.idle;
      if (reattach) attach();
    }
    return false;
  }
}
