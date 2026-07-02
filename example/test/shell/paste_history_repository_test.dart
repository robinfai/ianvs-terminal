import 'dart:convert';
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

  test('skips malformed history entries without quarantine', () async {
    final file = File('${directory.path}/ianvs_paste_history.json');
    await file.writeAsString(
      jsonEncode({
        'entries': [
          'not an entry',
          {
            'text': 'kept',
            'kind': ' Copy ',
            'createdAt': '2026-05-14T01:02:03.000Z',
          },
          {'text': 7, 'kind': 'paste', 'createdAt': false},
          {'text': 'epoch fallback', 'kind': 'unknown', 'createdAt': 42},
        ],
      }),
    );

    final loaded = await repository.load();
    final quarantinedFiles = await directory
        .list()
        .where((entity) => entity.path.contains('.corrupt.'))
        .toList();

    expect(loaded?.entries, hasLength(2));
    expect(loaded?.entries.first.text, 'kept');
    expect(loaded?.entries.first.kind, PasteHistoryKind.copy);
    expect(loaded?.entries.first.createdAt, DateTime.utc(2026, 5, 14, 1, 2, 3));
    expect(loaded?.entries.last.text, 'epoch fallback');
    expect(loaded?.entries.last.kind, PasteHistoryKind.paste);
    expect(
      loaded?.entries.last.createdAt,
      DateTime.fromMillisecondsSinceEpoch(0),
    );
    expect(quarantinedFiles, isEmpty);
  });

  test(
    'normalizes duplicated and excessive persisted history entries',
    () async {
      final file = File('${directory.path}/ianvs_paste_history.json');
      await file.writeAsString(
        jsonEncode({
          'entries': [
            {
              'text': 'first  ',
              'kind': 'copy',
              'createdAt': '2026-05-14T00:00:00.000Z',
            },
            {
              'text': 'first',
              'kind': 'paste',
              'createdAt': '2026-05-15T00:00:00.000Z',
            },
            {
              'text': '   ',
              'kind': 'paste',
              'createdAt': '2026-05-16T00:00:00.000Z',
            },
            for (var index = 0; index < maxPasteHistoryEntries + 5; index += 1)
              {
                'text': 'item-$index',
                'kind': 'paste',
                'createdAt': '2026-05-17T00:00:00.000Z',
              },
          ],
        }),
      );

      final loaded = await repository.load();

      expect(loaded?.entries, hasLength(maxPasteHistoryEntries));
      expect(loaded?.entries.first.text, 'first');
      expect(
        loaded?.entries.map((entry) => entry.text),
        isNot(contains('first  ')),
      );
      expect(
        loaded?.entries.where((entry) => entry.text == 'first'),
        hasLength(1),
      );
      expect(loaded?.entries.last.text, 'item-${maxPasteHistoryEntries - 2}');
    },
  );

  test('restores valid history after a malformed persisted prefix', () async {
    final file = File('${directory.path}/ianvs_paste_history.json');
    await file.writeAsString(
      jsonEncode({
        'entries': [
          for (var index = 0; index < maxPasteHistoryEntries * 2; index += 1)
            'not an entry $index',
          for (var index = 0; index < maxPasteHistoryEntries + 5; index += 1)
            {
              'text': 'late-item-$index',
              'kind': 'paste',
              'createdAt': '2026-05-17T00:00:00.000Z',
            },
        ],
      }),
    );

    final loaded = await repository.load();

    expect(loaded?.entries, hasLength(maxPasteHistoryEntries));
    expect(loaded?.entries.first.text, 'late-item-0');
    expect(
      loaded?.entries.last.text,
      'late-item-${maxPasteHistoryEntries - 1}',
    );
  });

  test('save writes only normalized persisted history entries', () async {
    await repository.save(
      PasteHistoryDocument(
        entries: [
          for (var index = 0; index < maxPasteHistoryEntries + 5; index += 1)
            PasteHistoryEntry(
              text: 'item-$index',
              kind: PasteHistoryKind.paste,
              createdAt: DateTime.utc(2026, 5, 14),
            ),
          PasteHistoryEntry(
            text: 'item-0',
            kind: PasteHistoryKind.copy,
            createdAt: DateTime.utc(2026, 5, 15),
          ),
        ],
      ),
    );

    final raw = await File(
      '${directory.path}/ianvs_paste_history.json',
    ).readAsString();
    final decoded = jsonDecode(raw) as Map<String, Object?>;
    final entries = decoded['entries'] as List<Object?>;

    expect(entries, hasLength(maxPasteHistoryEntries));
    expect(
      entries.last,
      containsPair('text', 'item-${maxPasteHistoryEntries - 1}'),
    );
  });
}
