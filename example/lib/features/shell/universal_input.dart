enum UniversalInputMode { auto, terminal, agent }

enum UniversalInputKind { empty, command, naturalLanguage }

enum UniversalInputDecisionSource {
  empty,
  explicitTerminalMode,
  explicitAgentMode,
  naturalLanguageOneOffAllowlist,
  naturalLanguageDenylist,
  shellCommandAllowlist,
  multilineCommand,
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
    this.source = CommandSuggestionSource.localHeuristic,
    this.confidence = 0.86,
    this.riskLevel = CommandRiskLevel.safe,
  });

  final String command;
  final String reason;
  final CommandSuggestionSource source;
  final double confidence;
  final CommandRiskLevel riskLevel;
}

enum CommandSuggestionSource { localHeuristic, localCorrectionRule, deepSeek }

enum CommandRiskLevel { safe, caution, destructive }

extension CommandSuggestionSourceLabel on CommandSuggestionSource {
  String get label {
    return switch (this) {
      CommandSuggestionSource.localHeuristic => 'Local',
      CommandSuggestionSource.localCorrectionRule => 'Rule',
      CommandSuggestionSource.deepSeek => 'DeepSeek',
    };
  }
}

extension CommandRiskLevelLabel on CommandRiskLevel {
  String get label {
    return switch (this) {
      CommandRiskLevel.safe => 'Safe',
      CommandRiskLevel.caution => 'Caution',
      CommandRiskLevel.destructive => 'Destructive',
    };
  }
}

class CommandDraft {
  const CommandDraft({
    required this.command,
    required this.reason,
    this.source = CommandSuggestionSource.localHeuristic,
    this.confidence = 0.86,
    this.riskLevel = CommandRiskLevel.safe,
  });

  final String command;
  final String reason;
  final CommandSuggestionSource source;
  final double confidence;
  final CommandRiskLevel riskLevel;

  UniversalInputCommandSuggestion toSuggestion() {
    return UniversalInputCommandSuggestion(
      command: command,
      reason: reason,
      source: source,
      confidence: confidence,
      riskLevel: riskLevel,
    );
  }
}

class CommandCorrection {
  const CommandCorrection({
    required this.command,
    required this.reason,
    required this.ruleId,
    this.source = CommandSuggestionSource.localCorrectionRule,
    this.confidence = 0.82,
    this.riskLevel = CommandRiskLevel.safe,
  });

  final String command;
  final String reason;
  final String ruleId;
  final CommandSuggestionSource source;
  final double confidence;
  final CommandRiskLevel riskLevel;
}

class CommandDraftRequest {
  const CommandDraftRequest({
    required this.input,
    this.cwd,
    this.recentCommands = const <String>[],
    this.contextChips = const <String>[],
    this.modelLabel,
    this.apiBaseUrl,
    this.apiKey,
    this.apiModel,
    this.allowRemote = true,
    this.preferRemote = false,
  });

  final String input;
  final String? cwd;
  final List<String> recentCommands;
  final List<String> contextChips;
  final String? modelLabel;
  final String? apiBaseUrl;
  final String? apiKey;
  final String? apiModel;
  final bool allowRemote;
  final bool preferRemote;
}

class CommandCorrectionRequest {
  const CommandCorrectionRequest({
    required this.command,
    this.cwd,
    this.exitCode,
    this.outputTail = '',
    this.recentCommands = const <String>[],
    this.recentDirectories = const <String>[],
    this.apiBaseUrl,
    this.apiKey,
    this.apiModel,
    this.allowRemote = true,
    this.preferRemote = false,
  });

  final String command;
  final String? cwd;
  final int? exitCode;
  final String outputTail;
  final List<String> recentCommands;
  final List<String> recentDirectories;
  final String? apiBaseUrl;
  final String? apiKey;
  final String? apiModel;
  final bool allowRemote;
  final bool preferRemote;
}

class UniversalInputClassifier {
  const UniversalInputClassifier({
    this.commandVocabulary = const <String>{},
    this.naturalLanguageDenylist = const <String>{},
  });

  final Set<String> commandVocabulary;
  final Set<String> naturalLanguageDenylist;

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
    if (_matchesNaturalLanguageDenylist(normalizedInput, tokens)) {
      return UniversalInputClassification(
        mode: mode,
        kind: UniversalInputKind.command,
        source: UniversalInputDecisionSource.naturalLanguageDenylist,
        confidence: 0.99,
        tokens: tokens,
      );
    }

    if (tokens.length == 1 && _isNaturalLanguageOneOffOrPrefix(firstToken)) {
      return UniversalInputClassification(
        mode: mode,
        kind: UniversalInputKind.naturalLanguage,
        source: UniversalInputDecisionSource.naturalLanguageOneOffAllowlist,
        confidence: 0.94,
        tokens: tokens,
      );
    }

    if (_isLikelyMultilineCommand(normalizedInput)) {
      return UniversalInputClassification(
        mode: mode,
        kind: UniversalInputKind.command,
        source: UniversalInputDecisionSource.multilineCommand,
        confidence: 0.92,
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

  bool _matchesNaturalLanguageDenylist(String input, List<String> tokens) {
    if (naturalLanguageDenylist.isEmpty) {
      return false;
    }
    final normalizedInput = input.toLowerCase();
    final firstToken = _normalizeToken(tokens.first);
    return naturalLanguageDenylist.any((entry) {
      final normalizedEntry = entry.trim().toLowerCase();
      if (normalizedEntry.isEmpty) {
        return false;
      }
      return firstToken == normalizedEntry ||
          normalizedInput == normalizedEntry ||
          normalizedInput.startsWith('$normalizedEntry ');
    });
  }

  bool _isLikelyMultilineCommand(String input) {
    if (!input.contains('\n')) {
      return false;
    }
    final lines = input
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.length < 2) {
      return false;
    }
    var commandLines = 0;
    for (final line in lines) {
      final lineTokens = parseUniversalInputTokens(line);
      if (lineTokens.isEmpty) {
        continue;
      }
      final firstToken = _normalizeToken(lineTokens.first);
      if (_knownShellCommands.contains(firstToken) ||
          commandVocabulary.contains(firstToken) ||
          _oneOffShellCommandKeywords.contains(firstToken) ||
          _startsLikeShellCommand(line, lineTokens) ||
          _hasShellSyntaxMajority(lineTokens) ||
          line.endsWith('\\')) {
        commandLines += 1;
      }
    }
    return commandLines >= (lines.length * 0.66).ceil();
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
  return const <UniversalInputCommandSuggestion>[];
}

List<CommandDraft> universalInputCommandDraftsForText(
  String input, {
  String? cwd,
}) {
  return const <CommandDraft>[];
}

CommandCorrection? universalInputLocalCorrectionFor(
  CommandCorrectionRequest request,
) {
  final command = request.command.trim();
  if (command.isEmpty) {
    return null;
  }
  final output = request.outputTail;
  final outputLower = output.toLowerCase();
  final tokens = parseUniversalInputTokens(command);
  if (tokens.isEmpty) {
    return null;
  }

  final upstream = _gitPushUpstreamCorrection(command, output, outputLower);
  if (upstream != null) {
    return upstream;
  }

  final permission = _permissionCorrection(command, outputLower);
  if (permission != null) {
    return permission;
  }

  final cdCorrection = _cdPathCorrection(command, tokens, request);
  if (cdCorrection != null) {
    return cdCorrection;
  }

  final typo = _executableTypoCorrection(command, tokens);
  if (typo != null) {
    return typo;
  }

  return null;
}

CommandRiskLevel universalInputRiskLevelForCommand(String command) {
  final normalized = command.trim().toLowerCase();
  if (normalized.isEmpty) {
    return CommandRiskLevel.safe;
  }
  if (RegExp(
        r'(^|[;&|]\s*)rm\s+-[^\n;&|]*[rf][^\n;&|]*\s+',
      ).hasMatch(normalized) ||
      RegExp(r'\b(dd|mkfs|shutdown|reboot)\b').hasMatch(normalized)) {
    return CommandRiskLevel.destructive;
  }
  if (RegExp(
    r'(^|[;&|]\s*)(sudo|chmod|chown|chgrp|kill|pkill)\b',
  ).hasMatch(normalized)) {
    return CommandRiskLevel.caution;
  }
  if (RegExp(
    r'\b(brew|npm|pnpm|yarn|pip|gem|cargo)\s+(install|add|remove|uninstall|update|upgrade)\b',
  ).hasMatch(normalized)) {
    return CommandRiskLevel.caution;
  }
  if (RegExp(r'(^|[^>])>{1,2}\s*\S+').hasMatch(normalized)) {
    return CommandRiskLevel.caution;
  }
  return CommandRiskLevel.safe;
}

String redactUniversalInputCommandContext(
  String input, {
  int maxLines = 80,
  int maxChars = 8192,
}) {
  final tail = input
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .toList(growable: false);
  final limitedLines = tail.length <= maxLines
      ? tail
      : tail.sublist(tail.length - maxLines);
  var redacted = limitedLines.join('\n');
  if (redacted.length > maxChars) {
    redacted = redacted.substring(redacted.length - maxChars);
  }
  redacted = redacted.replaceAllMapped(
    RegExp(
      r'''\b([A-Z0-9_]*(?:KEY|TOKEN|SECRET|PASSWORD|PASS)[A-Z0-9_]*\s*=\s*)([^\s'"]+)''',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}[REDACTED]',
  );
  redacted = redacted.replaceAllMapped(
    RegExp(
      r'\b(token|api[_-]?key|secret|password)=([^&\s]+)',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}=[REDACTED]',
  );
  redacted = redacted.replaceAllMapped(
    RegExp(r'\b(bearer\s+)[A-Za-z0-9._~+/=-]{12,}', caseSensitive: false),
    (match) => '${match.group(1)}[REDACTED]',
  );
  return redacted;
}

CommandCorrection? _executableTypoCorrection(
  String command,
  List<String> tokens,
) {
  final firstToken = _normalizeToken(tokens.first);
  if (firstToken.isEmpty ||
      _knownShellCommands.contains(firstToken) ||
      _oneOffShellCommandKeywords.contains(firstToken)) {
    return null;
  }
  final explicitCorrection = _commonExecutableTypos[firstToken];
  final correctedExecutable =
      explicitCorrection ?? _nearestKnownExecutable(firstToken);
  if (correctedExecutable == null) {
    return null;
  }
  final corrected = command.replaceFirst(
    RegExp(RegExp.escape(tokens.first)),
    correctedExecutable,
  );
  if (corrected == command) {
    return null;
  }
  return CommandCorrection(
    command: corrected,
    reason: 'Corrects the executable name to $correctedExecutable.',
    ruleId: 'executable-typo',
    confidence: explicitCorrection == null ? 0.74 : 0.92,
    riskLevel: universalInputRiskLevelForCommand(corrected),
  );
}

CommandCorrection? _gitPushUpstreamCorrection(
  String command,
  String output,
  String outputLower,
) {
  final normalized = command.trim().toLowerCase();
  if (normalized != 'git push' && !normalized.startsWith('git push ')) {
    return null;
  }
  if (!outputLower.contains('set-upstream') &&
      !outputLower.contains('no upstream branch')) {
    return null;
  }
  final explicit = RegExp(
    r'git push --set-upstream\s+origin\s+([^\s]+)',
    caseSensitive: false,
  ).firstMatch(output);
  final branch =
      explicit?.group(1) ??
      RegExp(
        r'current branch\s+([A-Za-z0-9._/-]+)',
        caseSensitive: false,
      ).firstMatch(output)?.group(1) ??
      'HEAD';
  final corrected = 'git push --set-upstream origin $branch';
  return CommandCorrection(
    command: corrected,
    reason: 'Adds the missing upstream branch for git push.',
    ruleId: 'git-push-upstream',
    confidence: branch == 'HEAD' ? 0.72 : 0.9,
    riskLevel: universalInputRiskLevelForCommand(corrected),
  );
}

CommandCorrection? _permissionCorrection(String command, String output) {
  if (!output.contains('permission denied')) {
    return null;
  }
  final tokens = parseUniversalInputTokens(command);
  if (tokens.isEmpty) {
    return null;
  }
  final executable = RegExp(r'^\s*(\S+)').firstMatch(command)?.group(1);
  if (executable != null &&
      (executable.startsWith('./') || executable.startsWith('../'))) {
    final corrected = 'chmod +x $executable && $command';
    return CommandCorrection(
      command: corrected,
      reason: 'Makes the script executable before running it again.',
      ruleId: 'permission-script-executable',
      confidence: 0.84,
      riskLevel: universalInputRiskLevelForCommand(corrected),
    );
  }
  if (!command.trimLeft().startsWith('sudo ')) {
    final corrected = 'sudo $command';
    return CommandCorrection(
      command: corrected,
      reason: 'Retries the command with elevated permissions.',
      ruleId: 'permission-sudo',
      confidence: 0.68,
      riskLevel: universalInputRiskLevelForCommand(corrected),
    );
  }
  return null;
}

CommandCorrection? _cdPathCorrection(
  String command,
  List<String> tokens,
  CommandCorrectionRequest request,
) {
  if (_normalizeToken(tokens.first) != 'cd' || tokens.length < 2) {
    return null;
  }
  final requestedPath = tokens[1].replaceAll(RegExp(r'''^['"]|['"]$'''), '');
  if (requestedPath.trim().isEmpty || request.recentDirectories.isEmpty) {
    return null;
  }
  String? bestPath;
  var bestDistance = 1 << 20;
  final requestedLeaf = _pathLeaf(requestedPath).toLowerCase();
  for (final directory in request.recentDirectories) {
    final candidate = directory.trim();
    if (candidate.isEmpty) {
      continue;
    }
    final distance = _levenshteinDistance(
      requestedLeaf,
      _pathLeaf(candidate).toLowerCase(),
    );
    if (distance < bestDistance) {
      bestDistance = distance;
      bestPath = candidate;
    }
  }
  if (bestPath == null || bestDistance > 3) {
    return null;
  }
  final corrected = 'cd ${_shellQuotePath(bestPath)}';
  return CommandCorrection(
    command: corrected,
    reason: 'Uses the closest recent directory path.',
    ruleId: 'cd-path-fuzzy',
    confidence: 0.72,
    riskLevel: universalInputRiskLevelForCommand(corrected),
  );
}

String? _nearestKnownExecutable(String token) {
  String? best;
  var bestDistance = 1 << 20;
  for (final candidate in _knownShellCommands) {
    final distance = _levenshteinDistance(token, candidate);
    if (distance < bestDistance) {
      bestDistance = distance;
      best = candidate;
    }
  }
  if (best == null) {
    return null;
  }
  final maxDistance = token.length <= 4 ? 2 : 3;
  return bestDistance <= maxDistance ? best : null;
}

int _levenshteinDistance(String left, String right) {
  if (left == right) {
    return 0;
  }
  if (left.isEmpty) {
    return right.length;
  }
  if (right.isEmpty) {
    return left.length;
  }
  var previous = List<int>.generate(right.length + 1, (index) => index);
  for (var leftIndex = 0; leftIndex < left.length; leftIndex += 1) {
    final current = List<int>.filled(right.length + 1, 0);
    current[0] = leftIndex + 1;
    for (var rightIndex = 0; rightIndex < right.length; rightIndex += 1) {
      final substitutionCost = left[leftIndex] == right[rightIndex] ? 0 : 1;
      current[rightIndex + 1] = [
        current[rightIndex] + 1,
        previous[rightIndex + 1] + 1,
        previous[rightIndex] + substitutionCost,
      ].reduce((value, element) => value < element ? value : element);
    }
    previous = current;
  }
  return previous.last;
}

String _pathLeaf(String path) {
  final withoutTrailingSlash = path.endsWith('/') && path.length > 1
      ? path.substring(0, path.length - 1)
      : path;
  final slashIndex = withoutTrailingSlash.lastIndexOf('/');
  return slashIndex == -1
      ? withoutTrailingSlash
      : withoutTrailingSlash.substring(slashIndex + 1);
}

String _shellQuotePath(String path) {
  if (!RegExp(r'\s').hasMatch(path)) {
    return path;
  }
  return "'${path.replaceAll("'", r"'\''")}'";
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

const _commonExecutableTypos = <String, String>{
  'gti': 'git',
  'gut': 'git',
  'got': 'git',
  'pyhton': 'python',
  'pythno': 'python',
  'pythong': 'python',
  'fluter': 'flutter',
  'flutetr': 'flutter',
  'drat': 'dart',
  'sl': 'ls',
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
