import 'agent_detection_policy.dart';

enum InputIntentKind {
  empty,
  shellCommand,
  naturalLanguageQuestion,
  naturalLanguageCommandRequest,
  explainSelectedBlock,
  debugLastFailure,
  commandSearch,
  actionSearch,
  savedCommandSearch,
  ambiguous,
}

enum InputIntentRoute {
  none,
  shell,
  commandSearch,
  actionSearch,
  savedCommandSearch,
  agent,
  ambiguous,
}

enum AgentIntentShortcut { ctrlR }

class InputIntentAlternative {
  const InputIntentAlternative({
    required this.kind,
    required this.label,
    required this.confidence,
  });

  final InputIntentKind kind;
  final String label;
  final double confidence;
}

class InputIntentDecision {
  const InputIntentDecision({
    required this.kind,
    required this.confidence,
    required this.reason,
    this.normalizedInput = '',
    this.requiresUserChoice = false,
    this.alternatives = const <InputIntentAlternative>[],
    this.visible = true,
  });

  final InputIntentKind kind;
  final double confidence;
  final String reason;
  final String normalizedInput;
  final bool requiresUserChoice;
  final List<InputIntentAlternative> alternatives;
  final bool visible;

  InputIntentRoute get route {
    return switch (kind) {
      InputIntentKind.empty => InputIntentRoute.none,
      InputIntentKind.shellCommand => InputIntentRoute.shell,
      InputIntentKind.commandSearch => InputIntentRoute.commandSearch,
      InputIntentKind.actionSearch => InputIntentRoute.actionSearch,
      InputIntentKind.savedCommandSearch => InputIntentRoute.savedCommandSearch,
      InputIntentKind.naturalLanguageQuestion ||
      InputIntentKind.naturalLanguageCommandRequest ||
      InputIntentKind.explainSelectedBlock ||
      InputIntentKind.debugLastFailure => InputIntentRoute.agent,
      InputIntentKind.ambiguous => InputIntentRoute.ambiguous,
    };
  }

  bool get ambiguous {
    return kind == InputIntentKind.ambiguous || requiresUserChoice;
  }
}

class AgentIntentRouter {
  const AgentIntentRouter({
    this.policy = const AgentDetectionPolicy(),
    this.commandVocabulary = const <String>{},
  });

  final AgentDetectionPolicy policy;
  final Set<String> commandVocabulary;

  InputIntentDecision routeShortcut(AgentIntentShortcut shortcut) {
    return switch (shortcut) {
      AgentIntentShortcut.ctrlR => const InputIntentDecision(
        kind: InputIntentKind.commandSearch,
        confidence: 1,
        reason: 'shortcut-ctrl-r',
      ),
    };
  }

  InputIntentDecision routeText(String input) {
    final normalized = input.trim();
    if (normalized.isEmpty) {
      return const InputIntentDecision(
        kind: InputIntentKind.empty,
        confidence: 1,
        reason: 'empty-input',
        visible: false,
      );
    }

    if (!policy.enabled) {
      return InputIntentDecision(
        kind: InputIntentKind.shellCommand,
        confidence: 1,
        reason: 'auto-detection-disabled',
        normalizedInput: normalized,
      );
    }

    final forced = _routeForcedPrefix(normalized);
    if (forced != null) {
      return forced;
    }

    if (_looksLikeShellCommand(normalized)) {
      return InputIntentDecision(
        kind: InputIntentKind.shellCommand,
        confidence: 0.95,
        reason: 'shell-syntax-or-vocabulary',
        normalizedInput: normalized,
      );
    }

    if (_referencesLastFailure(normalized)) {
      return InputIntentDecision(
        kind: InputIntentKind.debugLastFailure,
        confidence: 0.93,
        reason: 'last-failure-reference',
        normalizedInput: normalized,
      );
    }

    if (_referencesSelectedBlock(normalized)) {
      return InputIntentDecision(
        kind: InputIntentKind.explainSelectedBlock,
        confidence: 0.91,
        reason: 'selected-block-reference',
        normalizedInput: normalized,
      );
    }

    if (_looksAmbiguous(normalized)) {
      return _ambiguous(
        normalized,
        reason: 'ambiguous-shell-agent-language',
        confidence: 0.62,
      );
    }

    if (_looksLikeNaturalLanguage(normalized)) {
      if (!policy.naturalLanguageAutoDetectionEnabled) {
        return _ambiguous(
          normalized,
          reason: 'natural-language-auto-detection-disabled',
        );
      }
      const confidence = 0.88;
      if (confidence < policy.directRouteThreshold) {
        return _ambiguous(
          normalized,
          reason: 'below-direct-route-threshold',
          confidence: confidence,
        );
      }
      return InputIntentDecision(
        kind: _looksLikeCommandRequest(normalized)
            ? InputIntentKind.naturalLanguageCommandRequest
            : InputIntentKind.naturalLanguageQuestion,
        confidence: confidence,
        reason: 'natural-language-rule',
        normalizedInput: normalized,
      );
    }

    return _ambiguous(normalized, reason: 'low-confidence-fallback');
  }

  InputIntentDecision? _routeForcedPrefix(String normalized) {
    if (_hasPrefix(normalized, policy.shellPrefix)) {
      return InputIntentDecision(
        kind: InputIntentKind.shellCommand,
        confidence: 1,
        reason: 'forced-shell-prefix',
        normalizedInput: _removePrefix(normalized, policy.shellPrefix),
      );
    }
    if (_hasPrefix(normalized, policy.agentPrefix)) {
      final unprefixed = _removePrefix(normalized, policy.agentPrefix);
      return InputIntentDecision(
        kind: _looksLikeCommandRequest(unprefixed)
            ? InputIntentKind.naturalLanguageCommandRequest
            : InputIntentKind.naturalLanguageQuestion,
        confidence: 1,
        reason: 'forced-agent-prefix',
        normalizedInput: unprefixed,
      );
    }
    if (_hasPrefix(normalized, policy.actionPrefix)) {
      return InputIntentDecision(
        kind: InputIntentKind.actionSearch,
        confidence: 1,
        reason: 'action-prefix',
        normalizedInput: _removePrefix(normalized, policy.actionPrefix),
      );
    }
    return null;
  }

  bool _looksLikeShellCommand(String input) {
    final firstToken = _firstToken(input);
    return _knownShellCommands.contains(firstToken) ||
        commandVocabulary.contains(firstToken) ||
        _containsShellSyntax(input) ||
        _startsWithEnvAssignment(input) ||
        input.startsWith('./') ||
        input.startsWith('../');
  }

  bool _containsShellSyntax(String input) {
    return RegExp(r'(\s[|&]{1,2}\s|\s[<>]{1,2}\s|;|\$\(|`)').hasMatch(input);
  }

  bool _startsWithEnvAssignment(String input) {
    return RegExp(r'^[A-Za-z_][A-Za-z0-9_]*=').hasMatch(input);
  }

  bool _referencesLastFailure(String input) {
    final lower = input.toLowerCase();
    return lower.contains('last failed') ||
        lower.contains('last failure') ||
        lower.contains('last error') ||
        lower.contains('failed command') ||
        input.contains('上一个失败命令') ||
        input.contains('上一条失败命令') ||
        input.contains('最近失败命令');
  }

  bool _referencesSelectedBlock(String input) {
    final lower = input.toLowerCase();
    return lower.contains('selected block') ||
        lower.contains('selected command') ||
        input.contains('选中的命令块') ||
        input.contains('当前命令块');
  }

  bool _looksAmbiguous(String input) {
    final lower = input.toLowerCase();
    return lower == 'show files modified today' ||
        lower.startsWith('show files ') ||
        lower.startsWith('list files ') ||
        lower.startsWith('open files ');
  }

  bool _looksLikeNaturalLanguage(String input) {
    final lower = input.toLowerCase();
    return _containsCjk(input) ||
        _naturalLanguageStarts.any((prefix) => lower.startsWith(prefix)) ||
        lower.split(RegExp(r'\s+')).length >= 4;
  }

  bool _looksLikeCommandRequest(String input) {
    final lower = input.toLowerCase();
    return lower.startsWith('run ') ||
        lower.startsWith('create ') ||
        lower.startsWith('fix ') ||
        lower.startsWith('generate ') ||
        input.startsWith('帮我') ||
        input.startsWith('创建') ||
        input.startsWith('修复');
  }

  InputIntentDecision _ambiguous(
    String input, {
    required String reason,
    double? confidence,
  }) {
    final resolvedConfidence = confidence ?? policy.ambiguousRouteThreshold;
    final shellAlternative = InputIntentAlternative(
      kind: InputIntentKind.shellCommand,
      label: 'Shell',
      confidence: resolvedConfidence,
    );
    final agentAlternative = InputIntentAlternative(
      kind: InputIntentKind.naturalLanguageQuestion,
      label: 'Agent',
      confidence: resolvedConfidence,
    );
    switch (policy.ambiguousInputBehavior) {
      case AgentAmbiguousInputBehavior.preferShell:
        return InputIntentDecision(
          kind: InputIntentKind.shellCommand,
          confidence: resolvedConfidence,
          reason: '$reason-prefer-shell',
          normalizedInput: input,
          alternatives: <InputIntentAlternative>[
            shellAlternative,
            agentAlternative,
          ],
        );
      case AgentAmbiguousInputBehavior.preferAgent:
        return InputIntentDecision(
          kind: InputIntentKind.naturalLanguageQuestion,
          confidence: resolvedConfidence,
          reason: '$reason-prefer-agent',
          normalizedInput: input,
          alternatives: <InputIntentAlternative>[
            agentAlternative,
            shellAlternative,
          ],
        );
      case AgentAmbiguousInputBehavior.requireChoice:
        break;
    }
    return InputIntentDecision(
      kind: InputIntentKind.ambiguous,
      confidence: resolvedConfidence,
      reason: reason,
      normalizedInput: input,
      requiresUserChoice: true,
      alternatives: <InputIntentAlternative>[
        shellAlternative,
        agentAlternative,
      ],
    );
  }
}

bool _hasPrefix(String input, String prefix) {
  return prefix.isNotEmpty && input.startsWith(prefix);
}

String _removePrefix(String input, String prefix) {
  return input.substring(prefix.length).trim();
}

String _firstToken(String input) {
  final token = input.split(RegExp(r'\s+')).first.trim();
  return token.toLowerCase();
}

bool _containsCjk(String input) {
  return RegExp(r'[\u3400-\u9FFF]').hasMatch(input);
}

const _knownShellCommands = <String>{
  'bash',
  'cat',
  'cd',
  'chmod',
  'chown',
  'cp',
  'cargo',
  'dart',
  'docker',
  'echo',
  'find',
  'flutter',
  'git',
  'grep',
  'just',
  'kill',
  'ls',
  'make',
  'mkdir',
  'mv',
  'node',
  'npm',
  'open',
  'pnpm',
  'pwd',
  'python',
  'python3',
  'rg',
  'rm',
  'sed',
  'sudo',
  'touch',
  'yarn',
  'zsh',
};

const _naturalLanguageStarts = <String>[
  'can ',
  'could ',
  'debug ',
  'explain ',
  'fix ',
  'generate ',
  'help ',
  'how ',
  'summarize ',
  'tell ',
  'what ',
  'why ',
];
