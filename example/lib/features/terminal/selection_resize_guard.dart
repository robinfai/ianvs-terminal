import 'package:flutter/foundation.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

/// Keeps selected source coordinates valid while keyboard/window geometry
/// changes. Only the latest resize is applied once selection is dismissed.
class SelectionResizeGuard {
  SelectionResizeGuard(this.selection) {
    selection.addListener(_selectionChanged);
  }

  final SelectionController selection;
  VoidCallback? _pendingResize;

  void resize(VoidCallback apply) {
    if (selection.selection != null) {
      _pendingResize = apply;
    } else {
      _pendingResize = null;
      apply();
    }
  }

  void _selectionChanged() {
    if (selection.selection != null) return;
    final apply = _pendingResize;
    _pendingResize = null;
    apply?.call();
  }

  void dispose() {
    selection.removeListener(_selectionChanged);
    _pendingResize = null;
  }
}
