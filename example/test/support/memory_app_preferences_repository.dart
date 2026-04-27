import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/preferences/app_preferences_repository.dart';

class MemoryAppPreferencesRepository extends AppPreferencesRepository {
  MemoryAppPreferencesRepository(this._document);

  TerminalAppPreferencesDocument? _document;

  @override
  Future<TerminalAppPreferencesDocument?> load() async => _document;

  @override
  Future<void> save(TerminalAppPreferencesDocument document) async {
    _document = document;
  }
}
