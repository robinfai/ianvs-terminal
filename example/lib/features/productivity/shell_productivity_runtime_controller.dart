import 'shell_productivity_models.dart';
import 'shell_productivity_reducer.dart';

class ShellProductivityRuntimeController {
  ShellProductivityRuntimeController({
    ShellProductivitySnapshot initialSnapshot =
        const ShellProductivitySnapshot(),
  }) : _snapshot = initialSnapshot;

  ShellProductivitySnapshot _snapshot;

  ShellProductivitySnapshot get snapshot => _snapshot;

  Future<ShellProductivitySnapshot> apply({
    required ShellProductivityEvent event,
    Future<void> Function(ShellRecentItemsState recentItems)?
    persistRecentItems,
  }) async {
    _snapshot = ShellProductivityReducer.reduce(_snapshot, event);
    await persistRecentItems?.call(_snapshot.recentItems);
    return _snapshot;
  }
}
