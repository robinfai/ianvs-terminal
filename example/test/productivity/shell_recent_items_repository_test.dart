import 'dart:convert';
import 'dart:io';

import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/productivity/shell_recent_items_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shell recent items repository', () {
    test('returns defaults when recent items file is absent', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-recent-items-missing',
      );
      final repository = ShellRecentItemsRepository(
        directoryResolver: () async => directory,
      );

      expect((await repository.load()).commands, isEmpty);
    });

    test('persists recent commands and directories', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-recent-items-roundtrip',
      );
      final repository = ShellRecentItemsRepository(
        directoryResolver: () async => directory,
      );
      final state = const ShellRecentItemsState()
          .addCommand(
            const ShellRecentCommandEntry(
              command: 'flutter test',
              cwd: '/repo',
              exitCode: 0,
            ),
          )
          .addDirectory(const ShellRecentDirectoryEntry(path: '/repo'));

      await repository.save(state);
      final loaded = await repository.load();

      expect(loaded.commands.single.command, 'flutter test');
      expect(loaded.directories.single.path, '/repo');
    });

    test('quarantines corrupt recent items file', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-recent-items-corrupt',
      );
      final file = File('${directory.path}/ianvs_recent_items.json');
      await file.writeAsString('{bad json');
      final repository = ShellRecentItemsRepository(
        directoryResolver: () async => directory,
      );

      final loaded = await repository.load();

      expect(loaded.commands, isEmpty);
      expect(
        directory.listSync().any(
          (entry) => entry.path.contains('ianvs_recent_items.json.corrupt'),
        ),
        isTrue,
      );
    });

    test('skips malformed recent items without quarantine', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-recent-items-invalid-entries',
      );
      final file = File('${directory.path}/ianvs_recent_items.json');
      await file.writeAsString(
        jsonEncode({
          'limit': 'many',
          'commands': [
            'not a command',
            {'command': 'flutter test', 'cwd': '/repo', 'exitCode': 0.0},
            {'command': 7, 'cwd': false, 'exitCode': 'ok'},
          ],
          'directories': [
            7,
            {'path': '/repo', 'label': 'Repo'},
            {'path': false, 'label': 9},
          ],
        }),
      );
      final repository = ShellRecentItemsRepository(
        directoryResolver: () async => directory,
      );

      final loaded = await repository.load();

      expect(loaded.limit, 50);
      expect(loaded.commands, hasLength(1));
      expect(loaded.commands.single.command, 'flutter test');
      expect(loaded.commands.single.cwd, '/repo');
      expect(loaded.commands.single.exitCode, 0);
      expect(loaded.directories, hasLength(1));
      expect(loaded.directories.single.path, '/repo');
      expect(loaded.directories.single.label, 'Repo');
      expect(
        directory.listSync().any(
          (entry) => entry.path.contains('ianvs_recent_items.json.corrupt'),
        ),
        isFalse,
      );
    });
  });
}
