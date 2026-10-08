import 'dart:math' as math;

import 'input_intent_weights.dart';

enum InputIntent { command, ai }

enum InputIntentChoice { automatic, command, ai }

/// Local evidence only. A host must replace this when its shell node changes;
/// the SSH target must never inherit the local shell's aliases or history.
class InputIntentContext {
  const InputIntentContext({
    this.scope = '',
    this.commandNames = const {},
    this.aliases = const {},
    this.agentFollowUp = false,
    this.awaitingAnswer = false,
  });

  final String scope;

  /// Names resolved by this shell: PATH executables, builtins and functions.
  /// Missing/truncated metadata is not evidence that an input is a command.
  final Set<String> commandNames;
  final Map<String, String> aliases;
  final bool agentFollowUp;
  final bool awaitingAnswer;
}

class InputIntentDecision {
  const InputIntentDecision(this.intent, this.source, {this.aiProbability});
  final InputIntent intent;
  final String source;
  final double? aiProbability;
}

/// A draft-scoped override; no networking, command execution or disk access.
/// Synchronous, bounded inference cannot publish stale asynchronous results.
class InputIntentState {
  InputIntentState({this.defaultIntent = InputIntent.command})
    : decision = InputIntentDecision(defaultIntent, 'empty');

  final InputIntent defaultIntent;
  InputIntentChoice choice = InputIntentChoice.automatic;
  InputIntentDecision decision;
  String? _scope;
  String _text = '';

  void reset() {
    choice = InputIntentChoice.automatic;
    decision = InputIntentDecision(defaultIntent, 'empty');
  }

  /// Resolves a temporary draft with the live classifier's prior decision,
  /// without changing the live override, text or shell scope.
  InputIntentDecision preview(
    String text, {
    required InputIntentChoice choice,
    InputIntentContext context = const InputIntentContext(),
    bool composing = false,
    bool agentOwnsInput = false,
  }) =>
      (InputIntentState(defaultIntent: defaultIntent)
            ..choice = choice
            ..decision = decision
            .._scope = _scope
            .._text = _text)
          .update(
            text,
            context: context,
            composing: composing,
            agentOwnsInput: agentOwnsInput,
          );

  InputIntentDecision update(
    String text, {
    InputIntentContext context = const InputIntentContext(),
    bool composing = false,
    bool agentOwnsInput = false,
  }) {
    if ((_scope != null &&
            context.scope.isNotEmpty &&
            _scope != context.scope) ||
        (_text.isNotEmpty && text.isEmpty)) {
      reset();
    }
    if (context.scope.isNotEmpty) _scope = context.scope;
    _text = text;
    if (composing) return decision;
    // Attachments / an active agent turn belong to the agent. Explicit terminal
    // takeover remains a separate action and cannot be triggered by typing.
    if (agentOwnsInput) {
      return decision = const InputIntentDecision(InputIntent.ai, 'agent');
    }
    if (choice != InputIntentChoice.automatic) {
      return decision = InputIntentDecision(
        choice == InputIntentChoice.command
            ? InputIntent.command
            : InputIntent.ai,
        'manual',
      );
    }
    if (text.trim().isEmpty) return decision;
    return decision = classifyInputIntent(
      text,
      context: context,
      current: decision.intent,
    );
  }
}

/// Evidence-first routing. Unknown inputs go to the configured agent. The local
/// language model may veto an ambiguous known command, but cannot invent one.
InputIntentDecision classifyInputIntent(
  String input, {
  InputIntentContext context = const InputIntentContext(),
  InputIntent current = InputIntent.command,
}) {
  final text = input.trim();
  if (text.isEmpty) return InputIntentDecision(current, 'empty');
  // Automatic execution needs evidence; a large unexamined paste has none.
  if (text.length > 8192) {
    return const InputIntentDecision(InputIntent.ai, 'length');
  }
  final first = text.split(RegExp(r'\s+')).first;
  const command = InputIntentDecision(InputIntent.command, 'syntax');
  const ai = InputIntentDecision(InputIntent.ai, 'language');
  if (context.awaitingAnswer &&
      !RegExp(r'\s').hasMatch(text) &&
      (text.startsWith('/') ||
          text.startsWith('~/') ||
          RegExp(r'^\d+$').hasMatch(text))) {
    return const InputIntentDecision(InputIntent.ai, 'answer');
  }
  if (text.startsWith('? ')) return ai;
  if (first.startsWith('./') ||
      first.startsWith('../') ||
      first.startsWith('/') ||
      first.startsWith('~/') ||
      RegExp('^[A-Za-z_][A-Za-z0-9_]*=').hasMatch(first)) {
    return command;
  }
  final known =
      context.commandNames.contains(first) ||
      context.aliases.containsKey(first);
  if (known &&
      {
        '#',
        'echo',
        'printf',
        'sudo',
        'man',
        'codex',
        'claude',
        'gemini',
        'warp',
        'export',
        'unset',
        'source',
        '.',
        'eval',
        'exec',
        'alias',
        'unalias',
      }.contains(first)) {
    return command;
  }
  final lower = text.toLowerCase();
  if (context.agentFollowUp &&
      {
        'continue',
        'do it',
        'yes',
        'no',
        'approve',
        'go ahead',
        'try again',
        '继续',
        '执行吧',
        '可以',
        '好的',
        '是',
        '不是',
        '重试',
        '再试一次',
      }.contains(lower)) {
    return const InputIntentDecision(InputIntent.ai, 'follow-up');
  }
  // History records attempts (including command-not-found), not resolution.
  // Flags, punctuation and a low language-model score cannot prove a command
  // exists. In particular, an unseen language must never fall through to shell.
  if (!known) {
    return const InputIntentDecision(InputIntent.ai, 'unresolved');
  }
  if (first == text) {
    return InputIntentDecision(
      InputIntent.command,
      context.aliases.containsKey(first) ? 'alias' : 'shell',
    );
  }
  // Ignore quoted literals and filename/path tokens before looking for a
  // question appended to a command: `cat "为什么"` must remain a command.
  final prose = text
      .replaceAll(RegExp(r'''"(?:\\.|[^"\\])*"|'[^']*' '''.trim()), '')
      .split(RegExp(r'\s+'))
      .where((token) => !token.contains('/') && !token.contains('.'))
      .join(' ');
  if (RegExp('什么意思|是什么|怎么|为什么|如何|报错|失败了|怎么回事|哪里有问题|连接不上').hasMatch(prose)) {
    return ai;
  }
  final rest = text.substring(first.length);
  if (RegExp(
    r'\b(why (is|does|did)|how (do|does|can|to)|what (is|does))\b',
    caseSensitive: false,
  ).hasMatch(prose)) {
    return ai;
  }
  if (context.aliases.containsKey(first)) {
    return const InputIntentDecision(InputIntent.command, 'alias');
  }
  // A name which is also an ordinary word may still take literal arguments.
  if (RegExp(r'''^\s+(--?[A-Za-z0-9]|["'./~$])''').hasMatch(rest)) {
    return command;
  }
  if (RegExp(
    r'^(please|can you|could you|would you|how|why|what|when|where|explain|help|inspect|summarize|analyze|compare|tell me|the|this|that|my|there|is|are|does|should|i)\b',
    caseSensitive: false,
  ).hasMatch(text)) {
    return ai;
  }
  // A quoted argument, pipeline, flag, etc. is shell evidence only after an
  // executable-looking first token, never merely because prose mentions it.
  final shellFirst = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_.:+-]*$').hasMatch(first);
  final naturalStart = RegExp(
    r'^(please|can|could|would|how|why|what|when|where|explain|help|show|list|find|fix|summarize|tell|compare|remove|delete|create|write|make|check|look|run)\b',
    caseSensitive: false,
  ).hasMatch(text);
  if (shellFirst &&
      !naturalStart &&
      RegExp(r'''(^|\s)(--?[A-Za-z0-9]|["'./~$])|[|;&<>]''').hasMatch(rest)) {
    return command;
  }
  // These command forms are intentionally parsed before the statistical model:
  // `find . -name foo` and `git status` differ from “find all large files”.
  if ((first == 'find' && RegExp(r'^\s+[./~]').hasMatch(rest)) ||
      (first == 'yes' && !context.agentFollowUp) ||
      (first == 'git' &&
          RegExp(
            r'^\s+(status|diff|log|add|commit|push|pull|fetch|switch|checkout|branch|merge|rebase|restore|reset|show|clone|tag)(\s|$)',
          ).hasMatch(rest) &&
          !RegExp(
            r'\b(why|explain|please|how|failed|failing)\b|为什么|怎么|如何|失败|报错',
          ).hasMatch(rest))) {
    return command;
  }
  if (RegExp(
        '^(请|帮我|如何|怎么|为什么|解释|查找|列出|显示|修复|纠正|把|将|查看|打开|在当前)',
      ).hasMatch(text) &&
      !first.contains('/')) {
    return ai;
  }
  final probability = _aiProbability(text);
  return InputIntentDecision(
    probability >= 0.5 ? InputIntent.ai : InputIntent.command,
    probability >= 0.5 ? 'language-model' : 'shell',
    aiProbability: probability,
  );
}

double _aiProbability(String text) {
  final normalized = text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  final chars = '^$normalized\$'.runes.toList();
  final features = <String>{
    for (final word in normalized.split(' ')) 'w:$word',
    for (var n = 2; n <= 4; n++)
      for (var i = 0; i + n <= chars.length; i++)
        'c:${String.fromCharCodes(chars.sublist(i, i + n))}',
  };
  var score = inputIntentBias;
  for (final feature in features) {
    score += inputIntentWeights[feature] ?? 0;
  }
  return 1 / (1 + math.exp(-score.clamp(-40, 40)));
}
