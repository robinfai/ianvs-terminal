import 'saved_command_repository.dart';

enum CommandActionSearchItemKind { appAction, savedCommand }

enum CommandActionSelection { openAction, insertSavedCommand }

enum CommandActionSearchMatchKind { all, exact, prefix, substring, fuzzy }

class CommandActionSearchItem {
  const CommandActionSearchItem._({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.command,
    required this.cwd,
    required this.keywords,
    required this.tags,
    required this.updatedAt,
    required this.useCount,
  });

  const CommandActionSearchItem.appAction({
    required String id,
    required String title,
    String? subtitle,
    List<String> keywords = const <String>[],
  }) : this._(
         kind: CommandActionSearchItemKind.appAction,
         id: id,
         title: title,
         subtitle: subtitle,
         command: null,
         cwd: null,
         keywords: keywords,
         tags: const <String>[],
         updatedAt: null,
         useCount: 0,
       );

  factory CommandActionSearchItem.savedCommand(SavedCommandEntry entry) {
    return CommandActionSearchItem._(
      kind: CommandActionSearchItemKind.savedCommand,
      id: entry.id,
      title: entry.title,
      subtitle: entry.cwd,
      command: entry.command,
      cwd: entry.cwd,
      keywords: const <String>[],
      tags: entry.tags,
      updatedAt: entry.updatedAt,
      useCount: entry.useCount,
    );
  }

  final CommandActionSearchItemKind kind;
  final String id;
  final String title;
  final String? subtitle;
  final String? command;
  final String? cwd;
  final List<String> keywords;
  final List<String> tags;
  final DateTime? updatedAt;
  final int useCount;

  CommandActionSelection get selection {
    return switch (kind) {
      CommandActionSearchItemKind.appAction =>
        CommandActionSelection.openAction,
      CommandActionSearchItemKind.savedCommand =>
        CommandActionSelection.insertSavedCommand,
    };
  }

  bool get writesToTerminalOnSelect => false;
}

class CommandActionSearchResult {
  const CommandActionSearchResult({
    required this.item,
    required this.score,
    required this.matchKind,
  });

  final CommandActionSearchItem item;
  final double score;
  final CommandActionSearchMatchKind matchKind;
}

class CommandActionSearchIndex {
  CommandActionSearchIndex({
    Iterable<CommandActionSearchItem> actions =
        const <CommandActionSearchItem>[],
    Iterable<SavedCommandEntry> savedCommands = const <SavedCommandEntry>[],
  }) : _items = [
         ...actions,
         for (final command in savedCommands)
           CommandActionSearchItem.savedCommand(command),
       ];

  final List<CommandActionSearchItem> _items;

  List<CommandActionSearchResult> search(String query, {int limit = 20}) {
    final normalizedQuery = _normalized(query);
    final results = <CommandActionSearchResult>[];
    for (final item in _items) {
      final matchKind = _matchKind(item, normalizedQuery);
      if (matchKind == null) {
        continue;
      }
      results.add(
        CommandActionSearchResult(
          item: item,
          score: _score(item, matchKind),
          matchKind: matchKind,
        ),
      );
    }
    results.sort(_compareResults);
    return results.take(_effectiveLimit(limit)).toList(growable: false);
  }
}

CommandActionSearchMatchKind? _matchKind(
  CommandActionSearchItem item,
  String query,
) {
  if (query.isEmpty) {
    return CommandActionSearchMatchKind.all;
  }

  var bestMatchKind = CommandActionSearchMatchKind.fuzzy;
  var matched = false;
  for (final value in _searchValues(item)) {
    final matchKind = _valueMatchKind(value, query);
    if (matchKind == null) {
      continue;
    }
    matched = true;
    if (_matchRank(matchKind) > _matchRank(bestMatchKind)) {
      bestMatchKind = matchKind;
    }
  }

  return matched ? bestMatchKind : null;
}

CommandActionSearchMatchKind? _valueMatchKind(String value, String query) {
  final normalizedValue = _normalized(value);
  if (normalizedValue.isEmpty) {
    return null;
  }
  if (normalizedValue == query) {
    return CommandActionSearchMatchKind.exact;
  }
  if (normalizedValue.startsWith(query) ||
      normalizedValue
          .split(RegExp(r'[\s\-_]+'))
          .any((token) => token.startsWith(query))) {
    return CommandActionSearchMatchKind.prefix;
  }
  if (normalizedValue.contains(query)) {
    return CommandActionSearchMatchKind.substring;
  }
  if (_isFuzzyMatch(query, normalizedValue)) {
    return CommandActionSearchMatchKind.fuzzy;
  }
  return null;
}

Iterable<String> _searchValues(CommandActionSearchItem item) sync* {
  yield item.title;
  final subtitle = item.subtitle;
  if (subtitle != null) {
    yield subtitle;
  }
  final command = item.command;
  if (command != null) {
    yield command;
  }
  yield* item.keywords;
  yield* item.tags;
}

double _score(
  CommandActionSearchItem item,
  CommandActionSearchMatchKind matchKind,
) {
  return _matchScore(matchKind) + _kindScore(item) + _useScore(item);
}

double _matchScore(CommandActionSearchMatchKind kind) {
  return switch (kind) {
    CommandActionSearchMatchKind.exact => 1300,
    CommandActionSearchMatchKind.prefix => 900,
    CommandActionSearchMatchKind.substring => 650,
    CommandActionSearchMatchKind.fuzzy => 420,
    CommandActionSearchMatchKind.all => 100,
  };
}

double _kindScore(CommandActionSearchItem item) {
  return switch (item.kind) {
    CommandActionSearchItemKind.appAction => 260,
    CommandActionSearchItemKind.savedCommand => 0,
  };
}

double _useScore(CommandActionSearchItem item) {
  return item.useCount.clamp(0, 12).toDouble() * 20;
}

int _compareResults(
  CommandActionSearchResult left,
  CommandActionSearchResult right,
) {
  final scoreCompare = right.score.compareTo(left.score);
  if (scoreCompare != 0) {
    return scoreCompare;
  }

  final kindCompare = _kindRank(
    right.item.kind,
  ).compareTo(_kindRank(left.item.kind));
  if (kindCompare != 0) {
    return kindCompare;
  }

  final leftUpdatedAt = left.item.updatedAt;
  final rightUpdatedAt = right.item.updatedAt;
  if (leftUpdatedAt != null && rightUpdatedAt != null) {
    final timeCompare = rightUpdatedAt.compareTo(leftUpdatedAt);
    if (timeCompare != 0) {
      return timeCompare;
    }
  }

  return left.item.title.compareTo(right.item.title);
}

int _matchRank(CommandActionSearchMatchKind kind) {
  return switch (kind) {
    CommandActionSearchMatchKind.exact => 4,
    CommandActionSearchMatchKind.prefix => 3,
    CommandActionSearchMatchKind.substring => 2,
    CommandActionSearchMatchKind.fuzzy => 1,
    CommandActionSearchMatchKind.all => 0,
  };
}

int _kindRank(CommandActionSearchItemKind kind) {
  return switch (kind) {
    CommandActionSearchItemKind.appAction => 1,
    CommandActionSearchItemKind.savedCommand => 0,
  };
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

String _normalized(String value) {
  return value.trim().toLowerCase();
}

int _effectiveLimit(int limit) {
  return limit <= 0 ? 20 : limit;
}
