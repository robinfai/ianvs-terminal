import 'package:app/features/layout/local_terminal_layout_models.dart';
import 'package:app/features/layout/local_terminal_layout_repository.dart';

LocalTerminalLayoutRepository noIoLocalTerminalLayoutRepository() {
  return _NoIoLocalTerminalLayoutRepository();
}

final class _NoIoLocalTerminalLayoutRepository
    extends LocalTerminalLayoutRepository {
  @override
  Future<TerminalLayout?> load() async => null;

  @override
  Future<void> save(TerminalLayout layout) async {}
}
