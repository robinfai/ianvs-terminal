enum CommandHistoryPrivacyReason {
  sensitivePassword,
  sensitiveToken,
  sensitiveSecret,
  sensitivePrivateKey,
  historyDisabled,
  clearRequested,
}

enum CommandHistoryWriteIntent { save, clear }

class CommandHistoryPrivacyDecision {
  const CommandHistoryPrivacyDecision._({
    required this.allowed,
    required this.reason,
  });

  const CommandHistoryPrivacyDecision.allowed()
    : this._(allowed: true, reason: null);

  const CommandHistoryPrivacyDecision.blocked(
    CommandHistoryPrivacyReason reason,
  ) : this._(allowed: false, reason: reason);

  final bool allowed;
  final CommandHistoryPrivacyReason? reason;
}

class CommandHistoryPersistenceDecision {
  const CommandHistoryPersistenceDecision._({
    required this.shouldWrite,
    required this.shouldClear,
    this.reason,
  });

  const CommandHistoryPersistenceDecision.write()
    : this._(shouldWrite: true, shouldClear: false);

  const CommandHistoryPersistenceDecision.skip(
    CommandHistoryPrivacyReason reason,
  ) : this._(shouldWrite: false, shouldClear: false, reason: reason);

  const CommandHistoryPersistenceDecision.clear(
    CommandHistoryPrivacyReason reason,
  ) : this._(shouldWrite: false, shouldClear: true, reason: reason);

  final bool shouldWrite;
  final bool shouldClear;
  final CommandHistoryPrivacyReason? reason;
}

class CommandHistoryPrivacyFilter {
  const CommandHistoryPrivacyFilter({this.historyEnabled = true});

  final bool historyEnabled;

  CommandHistoryPrivacyDecision evaluateCommand(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) {
      return const CommandHistoryPrivacyDecision.allowed();
    }
    final normalized = trimmed.toLowerCase();
    if (_privateKeyPattern.hasMatch(normalized)) {
      return const CommandHistoryPrivacyDecision.blocked(
        CommandHistoryPrivacyReason.sensitivePrivateKey,
      );
    }
    if (_passwordPattern.hasMatch(normalized)) {
      return const CommandHistoryPrivacyDecision.blocked(
        CommandHistoryPrivacyReason.sensitivePassword,
      );
    }
    if (_tokenPattern.hasMatch(normalized)) {
      return const CommandHistoryPrivacyDecision.blocked(
        CommandHistoryPrivacyReason.sensitiveToken,
      );
    }
    if (_secretPattern.hasMatch(normalized)) {
      return const CommandHistoryPrivacyDecision.blocked(
        CommandHistoryPrivacyReason.sensitiveSecret,
      );
    }
    return const CommandHistoryPrivacyDecision.allowed();
  }

  Iterable<T> allowedEntries<T>(
    Iterable<T> entries,
    String Function(T entry) commandOf,
  ) {
    return entries.where((entry) => evaluateCommand(commandOf(entry)).allowed);
  }

  CommandHistoryPersistenceDecision persistenceDecision({
    CommandHistoryWriteIntent intent = CommandHistoryWriteIntent.save,
  }) {
    if (intent == CommandHistoryWriteIntent.clear) {
      return const CommandHistoryPersistenceDecision.clear(
        CommandHistoryPrivacyReason.clearRequested,
      );
    }
    if (!historyEnabled) {
      return const CommandHistoryPersistenceDecision.skip(
        CommandHistoryPrivacyReason.historyDisabled,
      );
    }
    return const CommandHistoryPersistenceDecision.write();
  }
}

final _passwordPattern = RegExp(
  r'(^|\s)(?:--?password(?:=|\s+\S)|(?:export\s+)?[a-z0-9_]*password[a-z0-9_]*\s*=)',
);

final _tokenPattern = RegExp(
  r'(^|\s)(?:--?token(?:=|\s+\S)|(?:export\s+)?[a-z0-9_]*token[a-z0-9_]*\s*=)',
);

final _secretPattern = RegExp(
  r'(^|\s)(?:--?secret(?:=|\s+\S)|(?:export\s+)?[a-z0-9_]*secret[a-z0-9_]*\s*=)',
);

final _privateKeyPattern = RegExp(
  r'(?:-----begin [a-z ]*private key-----|private[_\s-]?key\s*=)',
);
