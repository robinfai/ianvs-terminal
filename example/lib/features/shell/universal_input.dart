enum UniversalInputMode { auto, terminal, agent }

enum UniversalInputKind { empty, command, naturalLanguage }

enum UniversalInputDecisionSource {
  empty,
  explicitTerminalMode,
  explicitAgentMode,
  naturalLanguageOneOffAllowlist,
  shellCommandAllowlist,
  commandVocabulary,
  shellSyntax,
  cjkNaturalLanguage,
  naturalLanguageScore,
  fallbackCommand,
}

class UniversalInputClassification {
  const UniversalInputClassification({
    required this.mode,
    required this.kind,
    required this.source,
    required this.confidence,
    required this.tokens,
  });

  const UniversalInputClassification.empty({required UniversalInputMode mode})
    : this(
        mode: mode,
        kind: UniversalInputKind.empty,
        source: UniversalInputDecisionSource.empty,
        confidence: 1,
        tokens: const <String>[],
      );

  final UniversalInputMode mode;
  final UniversalInputKind kind;
  final UniversalInputDecisionSource source;
  final double confidence;
  final List<String> tokens;

  bool get isCommand => kind == UniversalInputKind.command;
  bool get isNaturalLanguage => kind == UniversalInputKind.naturalLanguage;

  String get modeLabel {
    return switch (mode) {
      UniversalInputMode.auto => 'Auto',
      UniversalInputMode.terminal => 'Terminal',
      UniversalInputMode.agent => 'Agent',
    };
  }

  String get kindLabel {
    return switch (kind) {
      UniversalInputKind.empty => 'Ready',
      UniversalInputKind.command => 'Command',
      UniversalInputKind.naturalLanguage => 'Natural language',
    };
  }
}

class UniversalInputCommandSuggestion {
  const UniversalInputCommandSuggestion({
    required this.command,
    required this.reason,
  });

  final String command;
  final String reason;
}

class UniversalInputClassifier {
  const UniversalInputClassifier({this.commandVocabulary = const <String>{}});

  final Set<String> commandVocabulary;

  UniversalInputClassification classify(
    String input, {
    UniversalInputMode mode = UniversalInputMode.auto,
  }) {
    final normalizedInput = input.trim();
    final tokens = parseUniversalInputTokens(normalizedInput);
    if (normalizedInput.isEmpty || tokens.isEmpty) {
      return UniversalInputClassification.empty(mode: mode);
    }

    if (mode == UniversalInputMode.terminal) {
      return UniversalInputClassification(
        mode: mode,
        kind: UniversalInputKind.command,
        source: UniversalInputDecisionSource.explicitTerminalMode,
        confidence: 1,
        tokens: tokens,
      );
    }

    if (mode == UniversalInputMode.agent) {
      return UniversalInputClassification(
        mode: mode,
        kind: UniversalInputKind.naturalLanguage,
        source: UniversalInputDecisionSource.explicitAgentMode,
        confidence: 1,
        tokens: tokens,
      );
    }

    final firstToken = _normalizeToken(tokens.first);
    if (tokens.length == 1 && _isNaturalLanguageOneOffOrPrefix(firstToken)) {
      return UniversalInputClassification(
        mode: mode,
        kind: UniversalInputKind.naturalLanguage,
        source: UniversalInputDecisionSource.naturalLanguageOneOffAllowlist,
        confidence: 0.94,
        tokens: tokens,
      );
    }

    if (_oneOffShellCommandKeywords.contains(firstToken)) {
      return UniversalInputClassification(
        mode: mode,
        kind: UniversalInputKind.command,
        source: UniversalInputDecisionSource.shellCommandAllowlist,
        confidence: 0.98,
        tokens: tokens,
      );
    }

    if (_isLikelyCommandFromVocabulary(tokens)) {
      return UniversalInputClassification(
        mode: mode,
        kind: UniversalInputKind.command,
        source: UniversalInputDecisionSource.commandVocabulary,
        confidence: tokens.length < 3 ? 0.95 : 0.88,
        tokens: tokens,
      );
    }

    if (_startsLikeShellCommand(normalizedInput, tokens) ||
        _hasShellSyntaxMajority(tokens)) {
      return UniversalInputClassification(
        mode: mode,
        kind: UniversalInputKind.command,
        source: UniversalInputDecisionSource.shellSyntax,
        confidence: 0.9,
        tokens: tokens,
      );
    }

    if (_containsCjkNaturalLanguage(normalizedInput)) {
      return UniversalInputClassification(
        mode: mode,
        kind: UniversalInputKind.naturalLanguage,
        source: UniversalInputDecisionSource.cjkNaturalLanguage,
        confidence: 0.9,
        tokens: tokens,
      );
    }

    final score = _naturalLanguageScore(tokens);
    final threshold = _naturalLanguageThreshold(tokens.length);
    final requiredScore = tokens.length * threshold;
    if (score >= requiredScore) {
      return UniversalInputClassification(
        mode: mode,
        kind: UniversalInputKind.naturalLanguage,
        source: UniversalInputDecisionSource.naturalLanguageScore,
        confidence: (score / tokens.length).clamp(0, 1),
        tokens: tokens,
      );
    }

    return UniversalInputClassification(
      mode: mode,
      kind: UniversalInputKind.command,
      source: UniversalInputDecisionSource.fallbackCommand,
      confidence: (1 - (score / tokens.length)).clamp(0.55, 1),
      tokens: tokens,
    );
  }

  bool _isLikelyCommandFromVocabulary(List<String> tokens) {
    final firstToken = _normalizeToken(tokens.first);
    if (_knownShellCommands.contains(firstToken) ||
        commandVocabulary.contains(firstToken)) {
      return true;
    }
    if (tokens.length > 1 && commandVocabulary.contains(tokens.first)) {
      return true;
    }
    return false;
  }
}

List<String> parseUniversalInputTokens(String query) {
  final tokens = <String>[];
  final activeToken = StringBuffer();
  _UniversalInputDelimiter? activeDelimiter;

  void flushToken() {
    if (activeToken.isEmpty) {
      return;
    }
    final token = activeToken.toString();
    activeToken.clear();
    if (token == '""' || token == "''") {
      return;
    }
    tokens.add(token);
  }

  for (var index = 0; index < query.length; index += 1) {
    final character = query[index];
    final delimiter = _delimiterFor(character);
    final nextDelimiter = index + 1 < query.length
        ? _delimiterFor(query[index + 1])
        : null;

    if (delimiter == _UniversalInputDelimiter.whitespace &&
        activeDelimiter == null) {
      flushToken();
      continue;
    }

    if (delimiter == _UniversalInputDelimiter.separator &&
        activeDelimiter == null) {
      if (activeToken.isEmpty) {
        continue;
      }
      if (nextDelimiter == _UniversalInputDelimiter.whitespace ||
          nextDelimiter == null) {
        flushToken();
      } else {
        activeToken.write(character);
      }
      continue;
    }

    if (delimiter != null &&
        delimiter != _UniversalInputDelimiter.whitespace &&
        delimiter != _UniversalInputDelimiter.separator) {
      if (activeDelimiter == delimiter) {
        activeToken.write(character);
        activeDelimiter = null;
        flushToken();
        continue;
      }
      if (activeDelimiter == null && activeToken.isEmpty) {
        activeDelimiter = delimiter;
      }
      activeToken.write(character);
      continue;
    }

    activeToken.write(character);
  }

  flushToken();
  return tokens;
}

List<UniversalInputCommandSuggestion> universalInputCommandSuggestionsForText(
  String input,
) {
  final normalized = input.trim().toLowerCase();
  if (normalized.isEmpty) {
    return const <UniversalInputCommandSuggestion>[];
  }

  final suggestions = <UniversalInputCommandSuggestion>[];
  void add(String command, String reason) {
    if (suggestions.any((suggestion) => suggestion.command == command)) {
      return;
    }
    suggestions.add(
      UniversalInputCommandSuggestion(command: command, reason: reason),
    );
  }

  if (_matchesAny(normalized, const [
    'git status',
    'what changed',
    'changes in git',
    'repo status',
    'working tree',
    '仓库状态',
    'git 状态',
    '有什么改动',
  ])) {
    add('git status --short --branch', 'Show repository status');
  }
  if (_matchesAny(normalized, const [
    'git diff',
    'show diff',
    '查看 diff',
    '查看改动',
    '代码改动',
  ])) {
    add('git diff --stat', 'Summarize changed files');
  }
  if (_matchesAny(normalized, const [
    'list files',
    'show files',
    'directory files',
    '列出文件',
    '看看文件',
    '显示文件',
  ])) {
    add('ls -la', 'List files');
  }
  if (_matchesAny(normalized, const [
    'where am i',
    'current directory',
    'print working directory',
    '当前目录',
    '我在哪',
  ])) {
    add('pwd', 'Print current directory');
  }
  if (_matchesAny(normalized, const [
    'find text',
    'search text',
    'search files',
    '查找文本',
    '搜索文本',
    '搜索文件',
  ])) {
    add('rg ', 'Search files');
  }
  if (_matchesAny(normalized, const [
    'run tests',
    'flutter tests',
    '跑测试',
    '运行测试',
    '执行测试',
  ])) {
    add('flutter test', 'Run Flutter tests');
  }
  if (_matchesAny(normalized, const [
    'analyze dart',
    'dart analyze',
    'static analysis',
    '静态分析',
    '代码分析',
  ])) {
    add('dart analyze', 'Run Dart analyzer');
  }
  if (_matchesAny(normalized, const [
    'clear screen',
    'clean terminal',
    '清屏',
    '清空终端',
  ])) {
    add('clear', 'Clear the terminal');
  }

  return suggestions.take(5).toList(growable: false);
}

bool _matchesAny(String normalized, List<String> needles) {
  return needles.any(normalized.contains);
}

bool _startsLikeShellCommand(String input, List<String> tokens) {
  if (input.startsWith('./') ||
      input.startsWith('../') ||
      input.startsWith('/') ||
      input.startsWith('~/')) {
    return true;
  }
  if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*=').hasMatch(input)) {
    return true;
  }
  final first = tokens.first;
  return first.startsWith('-') ||
      first.contains('/') ||
      first.contains('=') ||
      first.endsWith(':');
}

bool _hasShellSyntaxMajority(List<String> tokens) {
  var shellSyntaxTokens = 0;
  for (final token in tokens) {
    if (_hasShellSyntax(token)) {
      shellSyntaxTokens += 1;
    }
  }
  if (tokens.length <= 2) {
    return shellSyntaxTokens == tokens.length;
  }
  return shellSyntaxTokens >= (tokens.length * 0.5).ceil();
}

bool _hasShellSyntax(String token) {
  if (token.contains(' ')) {
    return false;
  }
  return token.contains(RegExp(r'[$={}\[\]><*~&()|/\-;:]'));
}

bool _containsCjkNaturalLanguage(String input) {
  if (!RegExp(r'[\u3400-\u9fff]').hasMatch(input)) {
    return false;
  }
  final trimmed = input.trimLeft();
  if (trimmed.startsWith('./') || trimmed.startsWith('/') || trimmed == 'ls') {
    return false;
  }
  return RegExp(
    r'(帮|请|如何|怎么|为什么|什么|列出|查看|解释|修复|运行|搜索|查找|创建|删除|总结)',
  ).hasMatch(input);
}

int _naturalLanguageScore(List<String> tokens) {
  var score = 0;
  for (var index = 0; index < tokens.length; index += 1) {
    final token = _normalizeToken(tokens[index]);
    if (token.isEmpty) {
      continue;
    }
    if (index == 0 &&
        (_knownShellCommands.contains(token) ||
            _oneOffShellCommandKeywords.contains(token)) &&
        token != 'what') {
      continue;
    }
    if (_naturalLanguageWords.contains(token) ||
        _technicalNaturalLanguageWords.contains(token) ||
        _knownShellCommands.contains(token)) {
      score += 1;
      continue;
    }
    if (!_wrappedInQuotes(token) && _hasShellSyntax(token)) {
      score -= score > 0 ? 1 : 0;
    }
  }
  return score;
}

double _naturalLanguageThreshold(int tokenCount) {
  if (tokenCount <= 3) {
    return 1;
  }
  if (tokenCount <= 4) {
    return 0.8;
  }
  return 0.6;
}

String _normalizeToken(String token) {
  var normalized = token.toLowerCase().trim();
  if (normalized == "can't") {
    return 'can';
  }
  normalized = normalized.replaceFirst(
    RegExp(r"('s|'re|n't|'t|'m|'ve|'ll)$"),
    '',
  );
  return normalized;
}

bool _wrappedInQuotes(String token) {
  return (token.startsWith('"') && token.endsWith('"')) ||
      (token.startsWith("'") && token.endsWith("'"));
}

bool _isNaturalLanguageOneOffOrPrefix(String input) {
  return _oneOffNaturalLanguageWords.any((word) => word.startsWith(input));
}

_UniversalInputDelimiter? _delimiterFor(String character) {
  return switch (character) {
    '\'' => _UniversalInputDelimiter.singleQuote,
    '"' => _UniversalInputDelimiter.doubleQuote,
    '`' => _UniversalInputDelimiter.backtick,
    ',' || '.' || '!' || '?' => _UniversalInputDelimiter.separator,
    _ when character.trim().isEmpty => _UniversalInputDelimiter.whitespace,
    _ => null,
  };
}

enum _UniversalInputDelimiter {
  separator,
  doubleQuote,
  singleQuote,
  backtick,
  whitespace,
}

const _oneOffShellCommandKeywords = <String>{
  '#',
  'echo',
  'man',
  'sudo',
  'claude',
  'codex',
  'gemini',
};

const _oneOffNaturalLanguageWords = <String>{
  'hello',
  'hi',
  'hey',
  'hola',
  'thanks',
  'explain',
  'yes',
  'no',
  'what',
  'why',
  'how',
  'nice',
  '1. ',
};

const _knownShellCommands = <String>{
  'adb',
  'awk',
  'bash',
  'cat',
  'cd',
  'chmod',
  'clear',
  'cp',
  'curl',
  'dart',
  'diff',
  'docker',
  'echo',
  'find',
  'flutter',
  'git',
  'grep',
  'head',
  'jq',
  'kill',
  'less',
  'ls',
  'make',
  'mkdir',
  'mv',
  'node',
  'npm',
  'pnpm',
  'pwd',
  'python',
  'python3',
  'rg',
  'rm',
  'rsync',
  'sed',
  'sh',
  'ssh',
  'sudo',
  'tail',
  'tar',
  'touch',
  'tree',
  'vim',
  'yarn',
  'zsh',
};

const _naturalLanguageWords = <String>{
  'a',
  'about',
  'add',
  'after',
  'all',
  'and',
  'any',
  'are',
  'ask',
  'build',
  'can',
  'change',
  'check',
  'clean',
  'compare',
  'could',
  'create',
  'debug',
  'delete',
  'describe',
  'do',
  'does',
  'explain',
  'file',
  'files',
  'find',
  'fix',
  'for',
  'from',
  'help',
  'how',
  'in',
  'install',
  'is',
  'list',
  'make',
  'me',
  'need',
  'open',
  'please',
  'remove',
  'run',
  'search',
  'show',
  'summarize',
  'tell',
  'test',
  'the',
  'this',
  'to',
  'what',
  'where',
  'why',
  'with',
};

const _technicalNaturalLanguageWords = <String>{
  'agent',
  'analysis',
  'app',
  'branch',
  'bug',
  'command',
  'commit',
  'dart',
  'directory',
  'docker',
  'error',
  'fail',
  'failing',
  'file',
  'flutter',
  'folder',
  'git',
  'issue',
  'log',
  'node',
  'project',
  'repo',
  'repository',
  'shell',
  'status',
  'terminal',
  'test',
  'tests',
};
