enum CommandSearchFilterKind { history, block, action, cwd, status }

class CommandSearchFilter {
  const CommandSearchFilter({required this.kind, required this.value});

  final CommandSearchFilterKind kind;
  final String value;
}

class CommandSearchQuery {
  const CommandSearchQuery({
    required this.text,
    this.filters = const <CommandSearchFilter>[],
  });

  final String text;
  final List<CommandSearchFilter> filters;

  bool get isEmpty => text.isEmpty && filters.isEmpty;

  String? valueFor(CommandSearchFilterKind kind) {
    for (final filter in filters) {
      if (filter.kind == kind) {
        return filter.value;
      }
    }
    return null;
  }
}

class CommandSearchQueryParser {
  const CommandSearchQueryParser();

  CommandSearchQuery parse(String rawQuery) {
    final textTokens = <String>[];
    final filters = <CommandSearchFilter>[];
    for (final token in _tokenize(rawQuery)) {
      final filter = _filterFromToken(token);
      if (filter == null) {
        textTokens.add(_unquote(token));
      } else {
        filters.add(filter);
      }
    }
    return CommandSearchQuery(
      text: textTokens.where((token) => token.isNotEmpty).join(' '),
      filters: filters,
    );
  }
}

CommandSearchFilter? _filterFromToken(String token) {
  final colonIndex = token.indexOf(':');
  if (colonIndex <= 0) {
    return null;
  }
  final kind = _kindForPrefix(token.substring(0, colonIndex).toLowerCase());
  if (kind == null) {
    return null;
  }
  final value = _unquote(token.substring(colonIndex + 1)).trim();
  if (value.isEmpty) {
    return null;
  }
  return CommandSearchFilter(kind: kind, value: value);
}

CommandSearchFilterKind? _kindForPrefix(String prefix) {
  return switch (prefix) {
    'history' => CommandSearchFilterKind.history,
    'block' => CommandSearchFilterKind.block,
    'action' => CommandSearchFilterKind.action,
    'cwd' => CommandSearchFilterKind.cwd,
    'status' => CommandSearchFilterKind.status,
    _ => null,
  };
}

List<String> _tokenize(String rawQuery) {
  final tokens = <String>[];
  final buffer = StringBuffer();
  String? quote;
  var escaping = false;

  void flush() {
    if (buffer.isEmpty) {
      return;
    }
    tokens.add(buffer.toString());
    buffer.clear();
  }

  for (var index = 0; index < rawQuery.length; index++) {
    final char = rawQuery[index];
    if (escaping) {
      buffer.write(char);
      escaping = false;
      continue;
    }
    if (quote != null) {
      if (char == r'\') {
        escaping = true;
        continue;
      }
      if (char == quote) {
        quote = null;
      }
      buffer.write(char);
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      buffer.write(char);
      continue;
    }
    if (char.trim().isEmpty) {
      flush();
      continue;
    }
    buffer.write(char);
  }
  flush();
  return tokens;
}

String _unquote(String value) {
  final trimmed = value.trim();
  if (trimmed.length < 2) {
    return trimmed;
  }
  final first = trimmed[0];
  final last = trimmed[trimmed.length - 1];
  if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
    return trimmed.substring(1, trimmed.length - 1).trim();
  }
  return trimmed;
}
