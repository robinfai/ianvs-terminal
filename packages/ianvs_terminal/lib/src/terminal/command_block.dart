import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'terminal_models.dart';

/// An immutable range in an earlier native output snapshot. Bounds are
/// zero-based and end-exclusive; the source base survives scrollback eviction.
@immutable
class CommandBlockReadRange {
  const CommandBlockReadRange({
    required this.startLine,
    required this.endLine,
    this.sourceLineBase,
  });
  final int startLine;
  final int endLine;
  final int? sourceLineBase;

  int? resolveStart(CommandBlock? current) {
    if (current == null || startLine < 0 || endLine <= startLine) return null;
    final base = current.sourceLineBase;
    if (sourceLineBase != null && base == null ||
        sourceLineBase == null && current.evicted) {
      return null;
    }
    final delta = sourceLineBase == null ? 0 : sourceLineBase! - base!;
    final start = startLine + delta;
    return start < 0 || endLine + delta > current.sourceLineCount
        ? null
        : start;
  }
}

@immutable
class CommandBlock {
  const CommandBlock({
    required this.id,
    required this.command,
    this.cwd = '',
    this.exitCode,
    this.submissionId,
    this.contextId,
    this.startedAt,
    this.finishedAt,
    this.running = false,
    this.suspended = false,
    this.evicted = false,
    this.lines = const [],
    this.hyperlinks = const [],
    this.totalLines = 0,
    int? sourceLineCount,
    this.segmented = false,
    this.matchingLines = 0,
    this.offset = 0,
    this.nextOffset,
    this.columns = 80,
    this.cursorLine = 0,
    this.cursorColumn = 0,
  }) : sourceLineCount = sourceLineCount ?? totalLines;

  final String id;
  final String command;
  final String cwd;
  final int? exitCode;
  final String? submissionId;
  final String? contextId;
  final int? startedAt;
  final int? finishedAt;
  final bool running;

  /// The command remains running while a nested shell owns terminal input.
  final bool suspended;
  final bool evicted;
  final List<TerminalRow> lines;
  final List<TerminalHyperlinkRange> hyperlinks;
  final int totalLines;

  /// Physical source span, including rows owned by nested commands. Those
  /// gaps do not appear in [lines] or count toward [totalLines] and page offsets.
  final int sourceLineCount;
  final bool segmented;
  final int matchingLines;
  final int offset;
  final int? nextOffset;
  final int columns;
  final int cursorLine;
  final int cursorColumn;

  int? get sourceLineBase {
    final first = lines.firstOrNull;
    return first?.sourceRow == null ? null : first!.sourceRow! - first.index;
  }

  int? get durationMs => startedAt == null || finishedAt == null
      ? null
      : (finishedAt! - startedAt!).clamp(0, 1 << 53);

  String get visibleOutput {
    final buffer = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      buffer.write(lines[i].text);
      if (i < lines.length - 1 &&
          (!lines[i].wrapped || lines[i + 1].index != lines[i].index + 1)) {
        buffer.writeln();
      }
    }
    return buffer.toString();
  }

  static CommandBlock? fromJson(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final id = value['id'];
    final command = value['command'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 128 ||
        command != null &&
            (command is! String ||
                command.length > 65536 ||
                utf8.encode(command).length > 65536)) {
      return null;
    }
    int count(String key) => switch (value[key]) {
      final int n when n >= 0 && n <= 1 << 53 => n,
      _ => 0,
    };
    int? optional(String key) => value[key] is int ? value[key]! as int : null;
    final rawLines = value['lines'];
    final rawLinks = value['hyperlinks'];
    return CommandBlock(
      id: id,
      command: command as String? ?? '',
      cwd: value['cwd'] is String ? value['cwd']! as String : '',
      exitCode: optional('exitCode'),
      submissionId: value['submissionId'] as String?,
      contextId: value['contextId'] as String?,
      startedAt: optional('startedAt'),
      finishedAt: optional('finishedAt'),
      running: value['running'] == true,
      suspended: value['suspended'] == true,
      evicted: value['evicted'] == true,
      lines: List.unmodifiable([
        if (rawLines is List)
          for (final row in rawLines.take(2048))
            if (row is Map<String, Object?>)
              if (TerminalRow.tryFromJson(row) case final TerminalRow parsed)
                parsed,
      ]),
      hyperlinks: List.unmodifiable([
        if (rawLinks is List)
          for (final link in rawLinks.take(4096))
            if (link is Map<String, Object?>)
              if (TerminalHyperlinkRange.tryFromJson(link)
                  case final TerminalHyperlinkRange parsed)
                parsed,
      ]),
      totalLines: count('totalLines'),
      sourceLineCount: value['sourceLineCount'] == null
          ? count('totalLines')
          : count('sourceLineCount'),
      segmented: value['segmented'] == true,
      matchingLines: count('matchingLines'),
      offset: count('offset'),
      nextOffset: optional('nextOffset'),
      columns: count('columns').clamp(1, 4096),
      cursorLine: count('cursorLine'),
      cursorColumn: count('cursorColumn'),
    );
  }
}

@immutable
class CommandBlockFilter {
  const CommandBlockFilter({
    this.query = '',
    this.regex = false,
    this.caseSensitive = false,
    this.invert = false,
    this.contextLines = 0,
  });
  final String query;
  final bool regex;
  final bool caseSensitive;
  final bool invert;
  final int contextLines;

  CommandBlockFilter copyWith({
    String? query,
    bool? regex,
    bool? caseSensitive,
    bool? invert,
    int? contextLines,
  }) => CommandBlockFilter(
    query: query ?? this.query,
    regex: regex ?? this.regex,
    caseSensitive: caseSensitive ?? this.caseSensitive,
    invert: invert ?? this.invert,
    contextLines: contextLines ?? this.contextLines,
  );

  Map<String, Object?> toJson() => {
    'query': query,
    'regex': regex,
    'caseSensitive': caseSensitive,
    'invert': invert,
    'contextLines': contextLines,
  };
}
