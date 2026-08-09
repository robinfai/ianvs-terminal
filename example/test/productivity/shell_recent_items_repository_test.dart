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

    test(
      'restores valid recent items after malformed persisted prefixes',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ianvs terminal-recent-items-sparse-load',
        );
        final file = File('${directory.path}/ianvs_recent_items.json');
        await file.writeAsString(
          jsonEncode({
            'commands': [
              for (var index = 0; index < maxShellRecentItems * 2; index += 1)
                'not a command $index',
              for (var index = 0; index < maxShellRecentItems + 5; index += 1)
                {'command': 'cmd-$index', 'cwd': '/repo', 'exitCode': 0},
            ],
            'directories': [
              for (var index = 0; index < maxShellRecentItems * 2; index += 1)
                'not a directory $index',
              for (var index = 0; index < maxShellRecentItems + 5; index += 1)
                {'path': '/repo/$index'},
            ],
          }),
        );
        final repository = ShellRecentItemsRepository(
          directoryResolver: () async => directory,
        );

        final loaded = await repository.load();

        expect(loaded.commands, hasLength(maxShellRecentItems));
        expect(loaded.commands.first.command, 'cmd-0');
        expect(loaded.commands.last.command, 'cmd-${maxShellRecentItems - 1}');
        expect(loaded.directories, hasLength(maxShellRecentItems));
        expect(loaded.directories.first.path, '/repo/0');
        expect(
          loaded.directories.last.path,
          '/repo/${maxShellRecentItems - 1}',
        );
      },
    );

    test('save writes only normalized recent items', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-recent-items-normalized-save',
      );
      final repository = ShellRecentItemsRepository(
        directoryResolver: () async => directory,
      );

      await repository.save(
        ShellRecentItemsState(
          limit: maxShellRecentItems + 5,
          commands: [
            const ShellRecentCommandEntry(
              command: '   ',
              cwd: '/repo',
              exitCode: 0,
            ),
            for (var index = 0; index < maxShellRecentItems + 5; index += 1)
              ShellRecentCommandEntry(
                command: 'cmd-$index',
                cwd: '/repo',
                exitCode: 0,
              ),
            const ShellRecentCommandEntry(
              command: 'cmd-0',
              cwd: '/repo',
              exitCode: 1,
            ),
          ],
          directories: [
            const ShellRecentDirectoryEntry(path: '   ', label: 'Blank'),
            for (var index = 0; index < maxShellRecentItems + 5; index += 1)
              ShellRecentDirectoryEntry(path: '/repo/$index'),
            const ShellRecentDirectoryEntry(
              path: '/repo/0',
              label: 'Duplicate',
            ),
          ],
        ),
      );

      final raw = await File(
        '${directory.path}/ianvs_recent_items.json',
      ).readAsString();
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      final commands = decoded['commands']! as List<Object?>;
      final directories = decoded['directories']! as List<Object?>;

      expect(decoded['limit'], maxShellRecentItems);
      expect(commands, hasLength(maxShellRecentItems));
      expect(commands.first, containsPair('command', 'cmd-0'));
      expect(commands.last, containsPair('command', 'cmd-49'));
      expect(directories, hasLength(maxShellRecentItems));
      expect(directories.first, containsPair('path', '/repo/0'));
      expect(directories.last, containsPair('path', '/repo/49'));
    });
  });
}
