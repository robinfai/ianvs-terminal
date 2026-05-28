import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/paste_history_repository.dart';

void main() {
  late Directory directory;
  late PasteHistoryRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'ianvs_paste_history_test_',
    );
    repository = PasteHistoryRepository(
      directoryResolver: () async => directory,
    );
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('saves and loads copied and pasted entries', () async {
    final copiedAt = DateTime.utc(2026, 5, 14, 1, 2, 3);
    final pastedAt = DateTime.utc(2026, 5, 14, 2, 3, 4);

    await repository.save(
      PasteHistoryDocument(
        entries: [
          PasteHistoryEntry(
            text: 'copied text',
            kind: PasteHistoryKind.copy,
            createdAt: copiedAt,
          ),
          PasteHistoryEntry(
            text: 'pasted text',
            kind: PasteHistoryKind.paste,
            createdAt: pastedAt,
          ),
        ],
      ),
    );

    final loaded = await repository.load();

    expect(loaded?.entries, hasLength(2));
    expect(loaded?.entries.first.text, 'copied text');
    expect(loaded?.entries.first.kind, PasteHistoryKind.copy);
    expect(loaded?.entries.first.createdAt, copiedAt);
    expect(loaded?.entries.last.text, 'pasted text');
    expect(loaded?.entries.last.kind, PasteHistoryKind.paste);
    expect(loaded?.entries.last.createdAt, pastedAt);
  });

  test('clearDiskHistory removes the saved history document', () async {
    await repository.save(
      PasteHistoryDocument(
        entries: [
          PasteHistoryEntry(
            text: 'temporary',
            kind: PasteHistoryKind.paste,
            createdAt: DateTime.utc(2026, 5, 14),
          ),
        ],
      ),
    );

    await repository.clearDiskHistory();

    expect(await repository.load(), isNull);
  });

  test(
    'corrupt history is quarantined and replaced with an empty document',
    () async {
      final file = File('${directory.path}/ianvs_paste_history.json');
      await file.writeAsString('not json');

      final loaded = await repository.load();
      final quarantinedFiles = await directory
          .list()
          .where((entity) => entity.path.contains('.corrupt.'))
          .toList();

      expect(loaded?.entries, isEmpty);
      expect(await file.exists(), isTrue);
      expect(quarantinedFiles, hasLength(1));
    },
  );
}
