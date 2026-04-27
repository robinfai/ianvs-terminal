import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/profiles/profile_repository.dart';

class MemoryProfileRepository extends ProfileRepository {
  MemoryProfileRepository(this._document);

  TerminalProfilesDocument _document;

  @override
  Future<TerminalProfilesDocument> load() async => _document;

  @override
  Future<void> save(TerminalProfilesDocument document) async {
    _document = document;
  }
}
