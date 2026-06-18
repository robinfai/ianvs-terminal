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
        _entry('flutter test', finishedAt: baseTime, invocationId: 'inv-1'),
        _entry(
          'git commit -m init',
          finishedAt: baseTime,
          invocationId: 'inv-2',
        ),
        _entry('dart analyze', finishedAt: baseTime, invocationId: 'inv-3'),
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
          invocationId: 'inv-1',
        ),
        _entry(
          'flutter test',
          cwd: '/repo',
          finishedAt: baseTime,
          invocationId: 'inv-2',
        ),
      ]);

      final results = index.search(
        parser.parse('flutter'),
        currentCwd: '/repo',
      );

      expect(results.first.entry.cwd, '/repo');
    });

    test('filters by command status', () {
      final index = CommandSearchIndex([
        _entry(
          'flutter test',
          exitCode: 0,
          finishedAt: baseTime,
          invocationId: 'inv-1',
        ),
        _entry(
          'flutter test --broken',
          exitCode: 1,
          finishedAt: baseTime.add(const Duration(seconds: 1)),
          invocationId: 'inv-2',
        ),
        _entry(
          'flutter test --unknown',
          exitCode: null,
          finishedAt: baseTime.add(const Duration(seconds: 2)),
          invocationId: 'inv-3',
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
          invocationId: 'old-$index',
        ),
      );
      final searchIndex = CommandSearchIndex([
        ...oldFrequentEntries,
        _entry(
          'npm test',
          cwd: '/repo',
          finishedAt: baseTime.add(const Duration(seconds: 1)),
          invocationId: 'new-hit',
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
          invocationId: 'inv-$index',
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

    test('omits records without invocation id from results', () {
      final index = CommandSearchIndex([
        _entry('flutter test', finishedAt: baseTime),
        _entry(
          'flutter test --block',
          finishedAt: baseTime.add(const Duration(seconds: 1)),
          invocationId: 'inv-1',
        ),
      ]);

      final results = index.search(parser.parse('flutter'));

      expect(results.map((result) => result.entry.command), [
        'flutter test --block',
      ]);
    });

    test('supports current session scope and global scope', () {
      final index = CommandSearchIndex([
        _entry(
          'flutter test',
          finishedAt: baseTime,
          invocationId: 'session-a-1',
          sessionId: 'session-a',
        ),
        _entry(
          'flutter pub get',
          finishedAt: baseTime.add(const Duration(seconds: 1)),
          invocationId: 'session-b-1',
          sessionId: 'session-b',
        ),
        _entry(
          'flutter analyze',
          finishedAt: baseTime.add(const Duration(seconds: 2)),
          invocationId: 'global-1',
        ),
      ]);

      final currentSessionResults = index.search(
        parser.parse('flutter'),
        scope: CommandSearchHistoryScope.currentSession,
        sessionId: 'session-a',
      );
      final globalResults = index.search(
        parser.parse('flutter'),
        scope: CommandSearchHistoryScope.global,
        sessionId: 'session-a',
      );

      expect(currentSessionResults.map((result) => result.entry.command), [
        'flutter test',
      ]);
      expect(globalResults.map((result) => result.entry.command), [
        'flutter analyze',
        'flutter pub get',
        'flutter test',
      ]);
    });

    test('current-session ordering is not polluted by external history', () {
      final index = CommandSearchIndex([
        _entry(
          'npm build',
          cwd: '/repo',
          finishedAt: baseTime,
          invocationId: 'session-a-old',
          sessionId: 'session-a',
        ),
        _entry(
          'npm deploy',
          cwd: '/repo',
          finishedAt: baseTime.add(const Duration(minutes: 1)),
          invocationId: 'session-a-new',
          sessionId: 'session-a',
        ),
        for (var count = 0; count < 8; count += 1)
          _entry(
            'npm build',
            cwd: '/repo-$count',
            finishedAt: baseTime.add(const Duration(days: 365)),
            invocationId: 'session-b-$count',
            sessionId: 'session-b',
          ),
      ]);

      final results = index.search(
        parser.parse('npm'),
        scope: CommandSearchHistoryScope.currentSession,
        sessionId: 'session-a',
      );

      expect(results.map((result) => result.entry.command), [
        'npm deploy',
        'npm build',
      ]);
    });

    test('global scope deduplicates session and global copies by command and cwd', () {
      final index = CommandSearchIndex([
        _entry(
          'flutter test',
          cwd: '/repo',
          finishedAt: baseTime.add(const Duration(seconds: 2)),
          invocationId: 'session-a-copy',
          sessionId: 'session-a',
        ),
        _entry(
          'flutter test',
          cwd: '/repo',
          finishedAt: baseTime.add(const Duration(seconds: 1)),
          invocationId: 'global-copy',
        ),
        _entry(
          'flutter analyze',
          cwd: '/repo',
          finishedAt: baseTime,
          invocationId: 'analyze-copy',
        ),
      ]);

      final results = index.search(
        parser.parse('flutter'),
        scope: CommandSearchHistoryScope.global,
      );

      expect(results.map((result) => result.entry.command), [
        'flutter test',
        'flutter analyze',
      ]);
      expect(
        results.where((result) => result.entry.command == 'flutter test'),
        hasLength(1),
      );
    });
  });
}

GlobalCommandHistoryEntry _entry(
  String command, {
  String? cwd,
  int? exitCode = 0,
  required DateTime finishedAt,
  String? invocationId,
  String? sessionId,
}) {
  return GlobalCommandHistoryEntry(
    command: command,
    cwd: cwd,
    exitCode: exitCode,
    finishedAt: finishedAt,
    invocationId: invocationId,
    sessionId: sessionId,
  );
}
