import 'command_search_query_parser.dart';
import 'global_command_history_repository.dart';

enum CommandSearchMatchKind { all, exact, prefix, substring, fuzzy }
enum CommandSearchHistoryScope { currentSession, global }

class CommandSearchResult {
  const CommandSearchResult({
    required this.entry,
    required this.score,
    required this.matchKind,
  });

  final GlobalCommandHistoryEntry entry;
  final double score;
  final CommandSearchMatchKind matchKind;
}

class CommandSearchIndex {
  CommandSearchIndex(Iterable<GlobalCommandHistoryEntry> entries)
    : _entries = entries
          .where((entry) => entry.hasBlockLocator)
          .toList(growable: false);

  final List<GlobalCommandHistoryEntry> _entries;

  List<CommandSearchResult> search(
    CommandSearchQuery query, {
    String? currentCwd,
    int limit = 20,
    CommandSearchHistoryScope scope = CommandSearchHistoryScope.global,
    String? sessionId,
  }) {
    final normalizedText = query.text.toLowerCase();
    final candidates = _deduplicatedEntriesForScope(scope, sessionId: sessionId);
    final frequencies = _commandFrequencies(candidates);
    final newestFinishedAt = _newest(candidates);
    final results = <CommandSearchResult>[];
    for (final entry in candidates) {
      if (!_passesFilters(entry, query)) {
        continue;
      }
      final matchKind = _matchKind(entry.command, normalizedText);
      if (matchKind == null) {
        continue;
      }
      results.add(
        CommandSearchResult(
          entry: entry,
          score: _score(
            entry,
            matchKind: matchKind,
            currentCwd: currentCwd,
            frequencies: frequencies,
            newestFinishedAt: newestFinishedAt,
          ),
          matchKind: matchKind,
        ),
      );
    }
    results.sort(_compareResults);
    return results.take(_effectiveLimit(limit)).toList(growable: false);
  }

  Iterable<GlobalCommandHistoryEntry> _entriesForScope(
    CommandSearchHistoryScope scope, {
    String? sessionId,
  }) {
    return switch (scope) {
      CommandSearchHistoryScope.currentSession when sessionId != null => _entries
          .where((entry) => entry.sessionId == sessionId),
      CommandSearchHistoryScope.currentSession => const <GlobalCommandHistoryEntry>[],
      CommandSearchHistoryScope.global => _entries,
    };
  }

  List<GlobalCommandHistoryEntry> _deduplicatedEntriesForScope(
    CommandSearchHistoryScope scope, {
    String? sessionId,
  }) {
    final deduplicated = <GlobalCommandHistoryEntry>[];
    final seenKeys = <String>{};
    for (final entry in _entriesForScope(scope, sessionId: sessionId)) {
      if (!seenKeys.add(_historyKey(entry.command, entry.cwd))) {
        continue;
      }
      deduplicated.add(entry);
    }
    return deduplicated;
  }

  double _score(
    GlobalCommandHistoryEntry entry, {
    required CommandSearchMatchKind matchKind,
    required String? currentCwd,
    required Map<String, int> frequencies,
    required DateTime? newestFinishedAt,
  }) {
    return _matchScore(matchKind) +
        _recencyScore(entry, newestFinishedAt: newestFinishedAt) +
        _cwdScore(entry, currentCwd) +
        _statusScore(entry) +
        _frequencyScore(entry, frequencies: frequencies);
  }

  double _recencyScore(
    GlobalCommandHistoryEntry entry, {
    required DateTime? newestFinishedAt,
  }) {
    if (newestFinishedAt == null) {
      return 0;
    }
    final ageSeconds = newestFinishedAt
        .difference(entry.finishedAt)
        .inSeconds
        .abs();
    return 220 / (1 + ageSeconds / 3600);
  }

  double _frequencyScore(
    GlobalCommandHistoryEntry entry, {
    required Map<String, int> frequencies,
  }) {
    final frequency = frequencies[_normalizedCommand(entry.command)] ?? 1;
    return (frequency - 1).clamp(0, 8).toDouble() * 14;
  }
}

bool _passesFilters(GlobalCommandHistoryEntry entry, CommandSearchQuery query) {
  for (final filter in query.filters) {
    final value = filter.value.toLowerCase();
    switch (filter.kind) {
      case CommandSearchFilterKind.status:
        if (!_statusMatches(entry, value)) {
          return false;
        }
        break;
      case CommandSearchFilterKind.cwd:
        if ((entry.cwd ?? '').toLowerCase() != value) {
          return false;
        }
        break;
      case CommandSearchFilterKind.action:
        if (!entry.command.toLowerCase().contains(value)) {
          return false;
        }
        break;
      case CommandSearchFilterKind.history:
      case CommandSearchFilterKind.block:
        break;
    }
  }
  return true;
}

bool _statusMatches(GlobalCommandHistoryEntry entry, String status) {
  return switch (status) {
    'success' || 'succeeded' => entry.exitCode == 0,
    'failed' || 'failure' => entry.exitCode != null && entry.exitCode != 0,
    'unknown' => entry.exitCode == null,
    _ => true,
  };
}

CommandSearchMatchKind? _matchKind(String command, String queryText) {
  final normalizedCommand = command.toLowerCase();
  if (queryText.isEmpty) {
    return CommandSearchMatchKind.all;
  }
  if (normalizedCommand == queryText) {
    return CommandSearchMatchKind.exact;
  }
  if (normalizedCommand.startsWith(queryText) ||
      normalizedCommand
          .split(RegExp(r'\s+'))
          .any((part) => part.startsWith(queryText))) {
    return CommandSearchMatchKind.prefix;
  }
  if (normalizedCommand.contains(queryText)) {
    return CommandSearchMatchKind.substring;
  }
  if (_isFuzzyMatch(queryText, normalizedCommand)) {
    return CommandSearchMatchKind.fuzzy;
  }
  return null;
}

bool _isFuzzyMatch(String pattern, String value) {
  if (pattern.isEmpty) {
    return true;
  }
  var patternIndex = 0;
  for (var valueIndex = 0; valueIndex < value.length; valueIndex++) {
    if (value[valueIndex] == pattern[patternIndex]) {
      patternIndex += 1;
      if (patternIndex == pattern.length) {
        return true;
      }
    }
  }
  return false;
}

double _matchScore(CommandSearchMatchKind kind) {
  return switch (kind) {
    CommandSearchMatchKind.exact => 1300,
    CommandSearchMatchKind.prefix => 900,
    CommandSearchMatchKind.substring => 650,
    CommandSearchMatchKind.fuzzy => 420,
    CommandSearchMatchKind.all => 100,
  };
}

double _cwdScore(GlobalCommandHistoryEntry entry, String? currentCwd) {
  final normalizedCurrent = currentCwd?.trim().toLowerCase();
  if (normalizedCurrent == null || normalizedCurrent.isEmpty) {
    return 0;
  }
  return (entry.cwd ?? '').toLowerCase() == normalizedCurrent ? 260 : 0;
}

double _statusScore(GlobalCommandHistoryEntry entry) {
  if (entry.exitCode == 0) {
    return 24;
  }
  if (entry.exitCode != null) {
    return 8;
  }
  return 0;
}

int _compareResults(CommandSearchResult left, CommandSearchResult right) {
  final scoreCompare = right.score.compareTo(left.score);
  if (scoreCompare != 0) {
    return scoreCompare;
  }
  final timeCompare = right.entry.finishedAt.compareTo(left.entry.finishedAt);
  if (timeCompare != 0) {
    return timeCompare;
  }
  return left.entry.command.compareTo(right.entry.command);
}

Map<String, int> _commandFrequencies(
  Iterable<GlobalCommandHistoryEntry> entries,
) {
  final frequencies = <String, int>{};
  for (final entry in entries) {
    frequencies.update(
      _normalizedCommand(entry.command),
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }
  return frequencies;
}

DateTime? _newest(Iterable<GlobalCommandHistoryEntry> entries) {
  DateTime? newest;
  for (final entry in entries) {
    if (newest == null || entry.finishedAt.isAfter(newest)) {
      newest = entry.finishedAt;
    }
  }
  return newest;
}

String _normalizedCommand(String command) {
  return command.trim().toLowerCase();
}

String _historyKey(String command, String? cwd) {
  return '${_normalizedCommand(command)}\n${cwd?.trim().toLowerCase() ?? ''}';
}

int _effectiveLimit(int limit) {
  return limit <= 0 ? 20 : limit;
}
