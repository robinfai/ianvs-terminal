import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'terminal_models.dart';

enum TerminalTextDocumentKind { markdown, json, code, plainText }

@immutable
class TerminalTextDocumentPalette {
  const TerminalTextDocumentPalette({
    required this.foreground,
    required this.accent,
    required this.secondary,
    required this.tertiary,
    required this.muted,
  });

  final Color foreground;
  final Color accent;
  final Color secondary;
  final Color tertiary;
  final Color muted;
}

class TerminalTextDocumentStyler {
  const TerminalTextDocumentStyler._();

  static TerminalTextDocumentKind kindFor({
    required String? type,
    required Iterable<String> visibleLines,
  }) {
    final normalized = _normalizedType(type);
    if (_markdownTypes.contains(normalized)) {
      return TerminalTextDocumentKind.markdown;
    }
    if (_jsonTypes.contains(normalized) || normalized.endsWith('+json')) {
      return TerminalTextDocumentKind.json;
    }
    if (_plainTextTypes.contains(normalized)) {
      return TerminalTextDocumentKind.plainText;
    }
    if (normalized.isNotEmpty) {
      return TerminalTextDocumentKind.code;
    }

    final lines = visibleLines
        .map((line) => line.trim())
        .toList(growable: false);
    final nonEmpty = lines
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (nonEmpty.isEmpty) {
      return TerminalTextDocumentKind.plainText;
    }
    final first = nonEmpty.first;
    final last = nonEmpty.last;
    if (((first.startsWith('{') && last.endsWith('}')) ||
            (first.startsWith('[') && last.endsWith(']'))) &&
        nonEmpty.any((line) => line.contains(':'))) {
      return TerminalTextDocumentKind.json;
    }
    if (nonEmpty.any(
      (line) =>
          RegExp(r'^#{1,6}\s').hasMatch(line) ||
          line.startsWith('```') ||
          RegExp(r'^[-*+]\s').hasMatch(line),
    )) {
      return TerminalTextDocumentKind.markdown;
    }
    return TerminalTextDocumentKind.code;
  }

  static String displayLabel(String? type, TerminalTextDocumentKind kind) {
    final trimmed = type?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed.length <= 32 ? trimmed : '${trimmed.substring(0, 31)}…';
    }
    return switch (kind) {
      TerminalTextDocumentKind.markdown => 'Markdown',
      TerminalTextDocumentKind.json => 'JSON',
      TerminalTextDocumentKind.code => 'Code',
      TerminalTextDocumentKind.plainText => 'Plain text',
    };
  }

  static List<TerminalStyleRun> styleRow({
    required String text,
    required TerminalTextDocumentKind kind,
    required TerminalTextDocumentPalette palette,
  }) {
    if (text.isEmpty) {
      return const <TerminalStyleRun>[];
    }
    final tokens = switch (kind) {
      TerminalTextDocumentKind.markdown => _markdownTokens(text, palette),
      TerminalTextDocumentKind.json => _jsonTokens(text, palette),
      TerminalTextDocumentKind.code => _codeTokens(text, palette),
      TerminalTextDocumentKind.plainText => const <_DocumentToken>[],
    };
    return _runsForTokens(text, tokens);
  }

  static List<_DocumentToken> _markdownTokens(
    String text,
    TerminalTextDocumentPalette palette,
  ) {
    final tokens = <_DocumentToken>[];
    final heading = RegExp(r'^\s{0,3}(#{1,6})\s+(.+)$').firstMatch(text);
    if (heading != null) {
      tokens
        ..add(
          _DocumentToken(
            heading.start,
            heading.end,
            foreground: palette.accent,
            bold: true,
            priority: 2,
          ),
        )
        ..add(
          _DocumentToken(
            heading.start,
            heading.start + heading.group(1)!.length,
            foreground: palette.muted,
            priority: 3,
          ),
        );
    }
    _addMatches(
      tokens,
      text,
      RegExp('`[^`]+`'),
      foreground: palette.secondary,
      priority: 4,
    );
    _addMatches(
      tokens,
      text,
      RegExp(r'\*\*[^*]+\*\*|__[^_]+__'),
      foreground: palette.foreground,
      bold: true,
      priority: 3,
    );
    _addMatches(
      tokens,
      text,
      RegExp(r'\[[^\]]+\]\([^\)]+\)'),
      foreground: palette.tertiary,
      underline: true,
      priority: 3,
    );
    _addMatches(
      tokens,
      text,
      RegExp(r'^\s*(?:>|[-*+]\s|\d+[.)]\s)'),
      foreground: palette.accent,
      bold: true,
      priority: 3,
    );
    if (text.trimLeft().startsWith('```')) {
      tokens.add(
        _DocumentToken(
          0,
          text.length,
          foreground: palette.muted,
          italic: true,
          priority: 5,
        ),
      );
    }
    return tokens;
  }

  static List<_DocumentToken> _jsonTokens(
    String text,
    TerminalTextDocumentPalette palette,
  ) {
    final tokens = <_DocumentToken>[];
    _addMatches(
      tokens,
      text,
      RegExp(r'"(?:\\.|[^"\\])*"'),
      foreground: palette.secondary,
      priority: 3,
    );
    _addMatches(
      tokens,
      text,
      RegExp(r'"(?:\\.|[^"\\])*"(?=\s*:)'),
      foreground: palette.accent,
      bold: true,
      priority: 5,
    );
    _addMatches(
      tokens,
      text,
      RegExp(r'(?<![\w.])-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?'),
      foreground: palette.tertiary,
      priority: 4,
    );
    _addMatches(
      tokens,
      text,
      RegExp(r'\b(?:true|false|null)\b'),
      foreground: palette.tertiary,
      bold: true,
      priority: 4,
    );
    _addMatches(
      tokens,
      text,
      RegExp(r'[{}\[\],:]'),
      foreground: palette.muted,
      priority: 1,
    );
    return tokens;
  }

  static List<_DocumentToken> _codeTokens(
    String text,
    TerminalTextDocumentPalette palette,
  ) {
    final tokens = <_DocumentToken>[];
    _addMatches(
      tokens,
      text,
      RegExp(r'//.*$|/\*.*?\*/|^\s*#.*$'),
      foreground: palette.muted,
      italic: true,
      priority: 6,
    );
    _addMatches(
      tokens,
      text,
      RegExp("\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'"),
      foreground: palette.secondary,
      priority: 5,
    );
    _addMatches(
      tokens,
      text,
      RegExp(
        r'\b(?:abstract|as|async|await|break|case|catch|class|const|continue|def|default|do|else|enum|export|extends|false|final|finally|fn|for|from|func|function|if|implements|import|in|interface|let|match|new|nil|null|override|package|private|protected|pub|public|raise|return|self|static|struct|super|switch|this|throw|throws|trait|true|try|type|var|void|while|with|yield)\b',
      ),
      foreground: palette.accent,
      bold: true,
      priority: 4,
    );
    _addMatches(
      tokens,
      text,
      RegExp(r'\b[A-Za-z_]\w*(?=\s*\()'),
      foreground: palette.tertiary,
      priority: 3,
    );
    _addMatches(
      tokens,
      text,
      RegExp(r'(?<![\w.])(?:0[xX][0-9a-fA-F]+|\d+(?:\.\d+)?)'),
      foreground: palette.tertiary,
      priority: 3,
    );
    return tokens;
  }

  static List<TerminalStyleRun> _runsForTokens(
    String text,
    List<_DocumentToken> tokens,
  ) {
    if (tokens.isEmpty) {
      return const <TerminalStyleRun>[];
    }
    final styleByCodeUnit = List<_DocumentToken?>.filled(text.length, null);
    for (final token in tokens) {
      final start = token.start.clamp(0, text.length);
      final end = token.end.clamp(start, text.length);
      for (var index = start; index < end; index += 1) {
        final current = styleByCodeUnit[index];
        if (current == null || token.priority >= current.priority) {
          styleByCodeUnit[index] = token;
        }
      }
    }

    final textCells = TerminalTextCells.fromText(text);
    final runs = <TerminalStyleRun>[];
    var start = 0;
    while (start < styleByCodeUnit.length) {
      final token = styleByCodeUnit[start];
      if (token == null) {
        start += 1;
        continue;
      }
      var end = start + 1;
      while (end < styleByCodeUnit.length &&
          styleByCodeUnit[end]?.sameStyle(token) == true) {
        end += 1;
      }
      final startColumn = textCells.columnForCodeUnit(start);
      final endColumn = textCells.columnForCodeUnit(end);
      if (endColumn > startColumn) {
        runs.add(
          TerminalStyleRun(
            start: startColumn,
            end: endColumn,
            foreground: token.foreground,
            bold: token.bold,
            italic: token.italic,
            underline: token.underline,
          ),
        );
      }
      start = end;
    }
    return runs;
  }

  static void _addMatches(
    List<_DocumentToken> tokens,
    String text,
    RegExp pattern, {
    required Color foreground,
    required int priority,
    bool bold = false,
    bool italic = false,
    bool underline = false,
  }) {
    for (final match in pattern.allMatches(text)) {
      tokens.add(
        _DocumentToken(
          match.start,
          match.end,
          foreground: foreground,
          bold: bold,
          italic: italic,
          underline: underline,
          priority: priority,
        ),
      );
    }
  }

  static String _normalizedType(String? type) {
    final normalized = type?.trim().toLowerCase().split(';').first ?? '';
    return normalized.startsWith('.') ? normalized.substring(1) : normalized;
  }

  static const Set<String> _markdownTypes = <String>{
    'markdown',
    'md',
    'mdown',
    'mkd',
    'text/markdown',
  };
  static const Set<String> _jsonTypes = <String>{
    'json',
    'jsonc',
    'application/json',
    'text/json',
  };
  static const Set<String> _plainTextTypes = <String>{
    'plain',
    'plaintext',
    'text',
    'txt',
    'text/plain',
  };
}

class _DocumentToken {
  const _DocumentToken(
    this.start,
    this.end, {
    required this.foreground,
    required this.priority,
    this.bold = false,
    this.italic = false,
    this.underline = false,
  });

  final int start;
  final int end;
  final Color foreground;
  final int priority;
  final bool bold;
  final bool italic;
  final bool underline;

  bool sameStyle(_DocumentToken other) {
    return foreground == other.foreground &&
        bold == other.bold &&
        italic == other.italic &&
        underline == other.underline;
  }
}
