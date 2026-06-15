import 'package:app/features/command_center/command_search_index.dart';
import 'package:app/features/command_center/command_search_query_parser.dart';
import 'package:app/features/command_center/global_command_history_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandSearchIndex', () {
    final baseTime = DateTime.utc(2026, 6, 15, 10);
    const parser = CommandSearchQueryParser();

    test('matches prefix and fuzzy command queries', () {
      final index = CommandSearchIndex([
        _entry('flutter test', finishedAt: baseTime),
        _entry('git commit -m init', finishedAt: baseTime),
        _entry('dart analyze', finishedAt: baseTime),
      ]);

      final prefix = index.search(parser.parse('flu'));
      final fuzzy = index.search(parser.parse('gcm'));

      expect(prefix.first.entry.command, 'flutter test');
      expect(prefix.first.matchKind, CommandSearchMatchKind.prefix);
      expect(fuzzy.first.entry.command, 'git commit -m init');
      expect(fuzzy.first.matchKind, CommandSearchMatchKind.fuzzy);
    });

    test('boosts results from the current cwd', () {
      final index = CommandSearchIndex([
        _entry(
          'flutter test',
          cwd: '/tmp',
          finishedAt: baseTime.add(const Duration(seconds: 4)),
        ),
        _entry('flutter test', cwd: '/repo', finishedAt: baseTime),
      ]);

      final results = index.search(
        parser.parse('flutter'),
        currentCwd: '/repo',
      );

      expect(results.first.entry.cwd, '/repo');
    });

    test('filters by command status', () {
      final index = CommandSearchIndex([
        _entry('flutter test', exitCode: 0, finishedAt: baseTime),
        _entry(
          'flutter test --broken',
          exitCode: 1,
          finishedAt: baseTime.add(const Duration(seconds: 1)),
        ),
        _entry(
          'flutter test --unknown',
          exitCode: null,
          finishedAt: baseTime.add(const Duration(seconds: 2)),
        ),
      ]);

      expect(
        index
            .search(parser.parse('status:success flutter'))
            .map((result) => result.entry.command),
        ['flutter test'],
      );
      expect(
        index
            .search(parser.parse('status:failed flutter'))
            .map((result) => result.entry.command),
        ['flutter test --broken'],
      );
      expect(
        index
            .search(parser.parse('status:unknown flutter'))
            .map((result) => result.entry.command),
        ['flutter test --unknown'],
      );
    });

    test('lets frequency help without outranking a newer exact hit', () {
      final oldFrequentEntries = List<GlobalCommandHistoryEntry>.generate(
        8,
        (index) => _entry(
          'npm run test',
          cwd: '/repo-$index',
          finishedAt: baseTime.subtract(Duration(days: 8 - index)),
        ),
      );
      final searchIndex = CommandSearchIndex([
        ...oldFrequentEntries,
        _entry(
          'npm test',
          cwd: '/repo',
          finishedAt: baseTime.add(const Duration(seconds: 1)),
        ),
      ]);

      final results = searchIndex.search(parser.parse('npm test'));

      expect(results.first.entry.command, 'npm test');
    });

    test('keeps 10k entry search within an interactive baseline', () {
      final entries = List<GlobalCommandHistoryEntry>.generate(
        10000,
        (index) => _entry(
          index == 9876 ? 'flutter test integration' : 'echo item-$index',
          cwd: index.isEven ? '/repo' : '/tmp',
          exitCode: index % 3 == 0 ? 1 : 0,
          finishedAt: baseTime.add(Duration(seconds: index)),
        ),
      );
      final index = CommandSearchIndex(entries);

      final stopwatch = Stopwatch()..start();
      final results = index.search(
        parser.parse('flutter'),
        currentCwd: '/repo',
      );
      stopwatch.stop();

      expect(results.first.entry.command, 'flutter test integration');
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });
  });
}

GlobalCommandHistoryEntry _entry(
  String command, {
  String? cwd,
  int? exitCode = 0,
  required DateTime finishedAt,
}) {
  return GlobalCommandHistoryEntry(
    command: command,
    cwd: cwd,
    exitCode: exitCode,
    finishedAt: finishedAt,
  );
}
