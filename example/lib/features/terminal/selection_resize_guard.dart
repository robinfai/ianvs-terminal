import 'package:flutter/foundation.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

/// Drops source coordinates before reflow instead of freezing terminal geometry.
/// Call after layout, since clearing selection notifies the viewport.
class SelectionResizeGuard {
  SelectionResizeGuard(this.selection);

  final SelectionController selection;
  bool _disposed = false;

  void resize(VoidCallback apply) {
    if (_disposed) return;
    if (selection.selection != null) selection.clear();
    apply();
  }

  void dispose() {
    _disposed = true;
  }
}
