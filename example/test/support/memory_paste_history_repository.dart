import 'package:app/features/shell/paste_history_repository.dart';

class MemoryPasteHistoryRepository extends PasteHistoryRepository {
  MemoryPasteHistoryRepository([this.document]);

  PasteHistoryDocument? document;
  bool cleared = false;

  @override
  Future<PasteHistoryDocument?> load() async => document;

  @override
  Future<void> save(PasteHistoryDocument document) async {
    this.document = document;
    cleared = false;
  }

  @override
  Future<void> clearDiskHistory() async {
    document = null;
    cleared = true;
  }
}
