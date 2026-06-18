import 'dart:convert';
import 'dart:io';

import 'package:app/features/command_center/global_command_history_repository.dart';
import 'package:app/features/command_center/session_command_history_buffer.dart';
import 'package:app/features/command_center/shell_hook_lifecycle_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GlobalCommandHistoryRepository', () {
    final firstFinishedAt = DateTime.utc(2026, 6, 15, 10);
    final secondFinishedAt = DateTime.utc(2026, 6, 15, 10, 0, 1);
    final thirdFinishedAt = DateTime.utc(2026, 6, 15, 10, 0, 2);

    test('returns empty history when file is absent', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-command-history-missing',
      );
      final repository = GlobalCommandHistoryRepository(
        directoryResolver: () async => directory,
      );

      expect((await repository.load()).entries, isEmpty);
    });

    test('persists and loads global command history json', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-command-history-roundtrip',
      );
      final repository = GlobalCommandHistoryRepository(
        directoryResolver: () async => directory,
      );
      final file = File('${directory.path}/ianvs_command_history.json');
      final document = GlobalCommandHistoryDocument(
        limit: 20,
        entries: [
          GlobalCommandHistoryEntry(
            command: 'flutter test',
            cwd: '/repo',
            exitCode: 0,
            finishedAt: firstFinishedAt,
            invocationId: 'invocation-1',
          ),
        ],
      );

      await repository.save(document);
      final loaded = await repository.load();
      final raw = jsonDecode(await file.readAsString()) as Map<String, Object?>;

      expect(loaded.entries.single.command, 'flutter test');
      expect(loaded.entries.single.cwd, '/repo');
      expect(loaded.entries.single.exitCode, 0);
      expect(loaded.entries.single.finishedAt, firstFinishedAt);
      expect(loaded.entries.single.invocationId, 'invocation-1');
      expect(raw['schemaVersion'], GlobalCommandHistoryDocument.schemaVersion);
      expect(raw['limit'], 20);
      expect(raw.containsKey('remote'), isFalse);
      expect(raw.containsKey('cloud'), isFalse);
      expect(raw.containsKey('sessionId'), isFalse);
      expect(
        (raw['entries'] as List<Object?>).single as Map<String, Object?>,
        isNot(contains('remote')),
      );
    });

    test(
      'quarantines corrupt history file and returns empty history',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-command-history-corrupt',
        );
        final file = File('${directory.path}/ianvs_command_history.json');
        await file.writeAsString('{bad json');
        final repository = GlobalCommandHistoryRepository(
          directoryResolver: () async => directory,
        );

        final loaded = await repository.load();

        expect(loaded.entries, isEmpty);
        expect(
          directory.listSync().any(
            (entry) =>
                entry.path.contains('ianvs_command_history.json.corrupt'),
          ),
          isTrue,
        );
      },
    );

    test('trims to the newest entries within the configured limit', () {
      final document = GlobalCommandHistoryDocument(
        limit: 2,
        entries: [
          GlobalCommandHistoryEntry(
            command: 'first',
            finishedAt: firstFinishedAt,
          ),
          GlobalCommandHistoryEntry(
            command: 'third',
            finishedAt: thirdFinishedAt,
          ),
          GlobalCommandHistoryEntry(
            command: 'second',
            finishedAt: secondFinishedAt,
          ),
        ],
      ).trimmed();

      expect(document.entries.map((entry) => entry.command), [
        'third',
        'second',
      ]);
    });

    test('merges session-local history ahead of older global duplicates', () {
      final global = GlobalCommandHistoryDocument(
        limit: 3,
        entries: [
          GlobalCommandHistoryEntry(
            command: 'flutter test',
            cwd: '/repo',
            exitCode: 1,
            finishedAt: firstFinishedAt,
            invocationId: 'global-old',
          ),
          GlobalCommandHistoryEntry(
            command: 'git status',
            cwd: '/repo',
            exitCode: 0,
            finishedAt: secondFinishedAt,
          ),
        ],
      );
      final session = const SessionCommandHistoryBuffer()
          .recordFinished(
            _finished(
              command: 'flutter test',
              cwd: '/repo',
              exitCode: 0,
              finishedAt: thirdFinishedAt,
            ),
            invocationId: 'session-new',
          )
          .recordFinished(
            _finished(
              command: 'pwd',
              cwd: '/repo',
              exitCode: 0,
              finishedAt: secondFinishedAt.add(const Duration(seconds: 1)),
            ),
          );

      final merged = global.mergeSessionEntries(
        session.entriesForSession('session-a'),
      );

      expect(merged.entries.map((entry) => entry.command), [
        'pwd',
        'flutter test',
        'git status',
      ]);
      expect(merged.entries[1].exitCode, 0);
      expect(merged.entries[1].invocationId, 'session-new');
    });

    test('drops v1-unrelated remote and cloud fields on save', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-command-history-no-remote-cloud',
      );
      final file = File('${directory.path}/ianvs_command_history.json');
      await file.writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'remote': {'host': 'prod.example.com'},
          'cloud': {'workspace': 'shared'},
          'entries': [
            {
              'command': 'flutter test',
              'cwd': '/repo',
              'exitCode': 0,
              'finishedAt': firstFinishedAt.toIso8601String(),
              'remote': {'host': 'prod.example.com'},
              'cloud': true,
              'sessionId': 'session-a',
            },
          ],
        }),
      );
      final repository = GlobalCommandHistoryRepository(
        directoryResolver: () async => directory,
      );

      await repository.save(await repository.load());
      final raw = jsonDecode(await file.readAsString()) as Map<String, Object?>;
      final rawEntry =
          (raw['entries'] as List<Object?>).single as Map<String, Object?>;

      expect(raw.containsKey('remote'), isFalse);
      expect(raw.containsKey('cloud'), isFalse);
      expect(rawEntry.containsKey('remote'), isFalse);
      expect(rawEntry.containsKey('cloud'), isFalse);
      expect(rawEntry.containsKey('sessionId'), isFalse);
    });
  });
}

CommandLifecycleFinishedEvent _finished({
  String sessionId = 'session-a',
  required String command,
  String? cwd,
  int? exitCode,
  required DateTime finishedAt,
}) {
  return CommandLifecycleFinishedEvent(
    sessionId: sessionId,
    receivedAt: finishedAt,
    command: command,
    cwd: cwd,
    exitCode: exitCode,
  );
}
