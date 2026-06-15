import 'dart:convert';
import 'dart:io';

import 'package:app/features/command_center/saved_command_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SavedCommandRepository', () {
    final createdAt = DateTime.utc(2026, 6, 15, 10);
    final updatedAt = createdAt.add(const Duration(minutes: 2));

    test('persists and loads saved commands as local-only json', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-saved-commands-roundtrip',
      );
      final repository = SavedCommandRepository(
        directoryResolver: () async => directory,
      );
      final file = File('${directory.path}/ianvs_saved_commands.json');
      final document = SavedCommandDocument(
        limit: 20,
        entries: [
          SavedCommandEntry(
            id: 'build',
            title: 'Build app',
            command: 'flutter build macos',
            cwd: '/repo',
            tags: const ['flutter', 'release'],
            createdAt: createdAt,
            updatedAt: updatedAt,
            useCount: 3,
            lastUsedAt: updatedAt,
          ),
        ],
      );

      await repository.save(document);
      final loaded = await repository.load();
      final raw = jsonDecode(await file.readAsString()) as Map<String, Object?>;

      expect(loaded.entries.single.id, 'build');
      expect(loaded.entries.single.title, 'Build app');
      expect(loaded.entries.single.command, 'flutter build macos');
      expect(loaded.entries.single.cwd, '/repo');
      expect(loaded.entries.single.tags, ['flutter', 'release']);
      expect(loaded.entries.single.useCount, 3);
      expect(loaded.entries.single.lastUsedAt, updatedAt);
      expect(raw['schemaVersion'], SavedCommandDocument.schemaVersion);
      expect(raw['limit'], 20);
      expect(raw.containsKey('remote'), isFalse);
      expect(raw.containsKey('cloud'), isFalse);
      expect(
        (raw['entries'] as List<Object?>).single as Map<String, Object?>,
        isNot(contains('sessionId')),
      );
    });

    test('normalizes entries, filters sensitive commands, and trims limit', () {
      final document = SavedCommandDocument(
        limit: 2,
        entries: [
          SavedCommandEntry(
            id: 'old',
            title: 'Old',
            command: 'pwd',
            createdAt: createdAt,
            updatedAt: createdAt,
          ),
          SavedCommandEntry(
            id: 'new',
            title: 'New',
            command: ' git status ',
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          SavedCommandEntry(
            id: 'new',
            title: 'Duplicate New',
            command: 'git diff',
            createdAt: createdAt,
            updatedAt: updatedAt.add(const Duration(seconds: 1)),
          ),
          SavedCommandEntry(
            id: 'secret',
            title: 'Secret',
            command: 'export API_TOKEN=abc123',
            createdAt: createdAt,
            updatedAt: updatedAt.add(const Duration(seconds: 2)),
          ),
        ],
      ).trimmed();

      expect(document.entries.map((entry) => entry.id), ['new', 'old']);
      expect(document.entries.first.title, 'Duplicate New');
      expect(document.entries.first.command, 'git diff');
      expect(document.entries.any((entry) => entry.id == 'secret'), isFalse);
    });

    test('marks saved command usage metadata by id', () {
      final usedAt = updatedAt.add(const Duration(minutes: 5));
      final document = SavedCommandDocument(
        entries: [
          SavedCommandEntry(
            id: 'build',
            title: 'Build app',
            command: 'flutter build macos',
            createdAt: createdAt,
            updatedAt: updatedAt,
            useCount: 3,
          ),
          SavedCommandEntry(
            id: 'status',
            title: 'Git status',
            command: 'git status --short',
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
        ],
      );

      final marked = document.markUsed('build', usedAt);

      expect(marked.entries.first.id, 'build');
      expect(marked.entries.first.useCount, 4);
      expect(marked.entries.first.lastUsedAt, usedAt);
      expect(marked.entries.first.updatedAt, updatedAt);
      expect(marked.entries.last.id, 'status');
      expect(marked.entries.last.useCount, 0);
    });

    test('leaves saved command usage unchanged for an unknown id', () {
      final document = SavedCommandDocument(
        entries: [
          SavedCommandEntry(
            id: 'status',
            title: 'Git status',
            command: 'git status --short',
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
        ],
      );

      final marked = document.markUsed(
        'missing',
        updatedAt.add(const Duration(minutes: 5)),
      );

      expect(identical(marked, document), isTrue);
    });

    test(
      'quarantines corrupt saved command file and returns empty document',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-saved-commands-corrupt',
        );
        final file = File('${directory.path}/ianvs_saved_commands.json');
        await file.writeAsString('{bad json');
        final repository = SavedCommandRepository(
          directoryResolver: () async => directory,
        );

        final loaded = await repository.load();

        expect(loaded.entries, isEmpty);
        expect(
          directory.listSync().any(
            (entry) => entry.path.contains('ianvs_saved_commands.json.corrupt'),
          ),
          isTrue,
        );
      },
    );
  });
}
