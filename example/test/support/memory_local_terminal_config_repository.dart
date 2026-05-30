import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/local_terminal_config_repository.dart';

class MemoryLocalTerminalConfigRepository
    extends LocalTerminalConfigRepository {
  MemoryLocalTerminalConfigRepository(this._document);

  LocalTerminalConfigDocument? _document;
  final List<LocalTerminalConfigDocument> savedDocuments = [];

  @override
  Future<LocalTerminalConfigDocument?> load() async => _document;

  @override
  Future<void> save(LocalTerminalConfigDocument document) async {
    savedDocuments.add(document);
    _document = document;
  }
}
