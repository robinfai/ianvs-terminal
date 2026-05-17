import 'dart:io';

import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/productivity/shell_recent_items_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shell recent items repository', () {
    test('returns defaults when recent items file is absent', () async {
      final directory = await Directory.systemTemp.createTemp(
        'flutterm-recent-items-missing',
      );
      final repository = ShellRecentItemsRepository(
        directoryResolver: () async => directory,
      );

      expect((await repository.load()).commands, isEmpty);
    });

    test('persists recent commands and directories', () async {
      final directory = await Directory.systemTemp.createTemp(
        'flutterm-recent-items-roundtrip',
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
        'flutterm-recent-items-corrupt',
      );
      final file = File('${directory.path}/flutterm_recent_items.json');
      await file.writeAsString('{bad json');
      final repository = ShellRecentItemsRepository(
        directoryResolver: () async => directory,
      );

      final loaded = await repository.load();

      expect(loaded.commands, isEmpty);
      expect(
        directory.listSync().any(
          (entry) => entry.path.contains('flutterm_recent_items.json.corrupt'),
        ),
        isTrue,
      );
    });
  });
}
