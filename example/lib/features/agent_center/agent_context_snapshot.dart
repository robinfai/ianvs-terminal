import 'agent_context_attachment.dart';

enum AgentRecentCommandStatus { succeeded, failed, running, unknown }

class AgentCommandBlockSnapshot {
  const AgentCommandBlockSnapshot({
    required this.id,
    required this.command,
    this.cwd,
    this.exitCode,
    this.outputExcerpt,
    this.startedAt,
    this.finishedAt,
  });

  final String id;
  final String command;
  final String? cwd;
  final int? exitCode;
  final String? outputExcerpt;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  bool get failed => exitCode != null && exitCode != 0;
}

class AgentTerminalOutputSelection {
  const AgentTerminalOutputSelection({
    required this.text,
    this.blockId,
    this.startRow,
    this.endRowExclusive,
  });

  final String text;
  final String? blockId;
  final int? startRow;
  final int? endRowExclusive;
}

class AgentRecentCommandSnapshot {
  const AgentRecentCommandSnapshot({
    required this.command,
    required this.status,
    this.cwd,
    this.exitCode,
    this.startedAt,
  });

  final String command;
  final AgentRecentCommandStatus status;
  final String? cwd;
  final int? exitCode;
  final DateTime? startedAt;
}

class AgentSessionSummary {
  const AgentSessionSummary({
    required this.terminalSessionId,
    this.cwd,
    this.shell,
    this.profileName,
    this.selectedBlockCommand,
    this.lastFailedCommand,
    this.lastFailedExitCode,
    this.recentCommandCount = 0,
    this.failedRecentCommandCount = 0,
  });

  final String terminalSessionId;
  final String? cwd;
  final String? shell;
  final String? profileName;
  final String? selectedBlockCommand;
  final String? lastFailedCommand;
  final int? lastFailedExitCode;
  final int recentCommandCount;
  final int failedRecentCommandCount;

  bool get hasContent {
    return _hasText(cwd) ||
        _hasText(shell) ||
        _hasText(profileName) ||
        _hasText(selectedBlockCommand) ||
        _hasText(lastFailedCommand) ||
        recentCommandCount > 0;
  }

  String get preview {
    final parts = <String>[
      if (_hasText(profileName)) profileName!.trim(),
      if (_hasText(cwd)) cwd!.trim(),
      if (recentCommandCount > 0) '$recentCommandCount recent commands',
      if (_hasText(lastFailedCommand))
        'last failed ${lastFailedCommand!.trim()}',
    ];
    return parts.isEmpty ? 'Session summary ready' : parts.join(' · ');
  }

  String toMemoryText() {
    final lines = <String>[
      'Terminal session: $terminalSessionId',
      if (_hasText(profileName)) 'Profile: ${profileName!.trim()}',
      if (_hasText(shell)) 'Shell: ${shell!.trim()}',
      if (_hasText(cwd)) 'CWD: ${cwd!.trim()}',
      if (recentCommandCount > 0)
        'Recent commands: $recentCommandCount'
            '${failedRecentCommandCount > 0 ? ' ($failedRecentCommandCount failed)' : ''}',
      if (_hasText(selectedBlockCommand))
        'Selected block: ${selectedBlockCommand!.trim()}',
      if (_hasText(lastFailedCommand))
        'Last failed: ${lastFailedCommand!.trim()}'
            '${lastFailedExitCode == null ? '' : ' (exit $lastFailedExitCode)'}',
    ];
    return lines.join('\n');
  }
}

class AgentContextSnapshot {
  const AgentContextSnapshot({
    required this.terminalSessionId,
    required this.readOnly,
    required this.shellHookAvailable,
    this.cwd,
    this.shell,
    this.profileId,
    this.profileName,
    this.sessionSummary,
    this.selectedBlock,
    this.selectedOutput,
    this.lastFailedBlock,
    this.recentCommands = const <AgentRecentCommandSnapshot>[],
    this.visibleScrollbackExcerpt,
    this.attachments = const <AgentContextAttachment>[],
  });

  final String terminalSessionId;
  final String? cwd;
  final String? shell;
  final String? profileId;
  final String? profileName;
  final AgentSessionSummary? sessionSummary;
  final bool readOnly;
  final bool shellHookAvailable;
  final AgentCommandBlockSnapshot? selectedBlock;
  final AgentTerminalOutputSelection? selectedOutput;
  final AgentCommandBlockSnapshot? lastFailedBlock;
  final List<AgentRecentCommandSnapshot> recentCommands;
  final String? visibleScrollbackExcerpt;
  final List<AgentContextAttachment> attachments;

  AgentContextAttachmentSet get attachmentSet {
    return AgentContextAttachmentSet(attachments: attachments);
  }

  AgentContextSnapshot copyWith({
    String? terminalSessionId,
    String? cwd,
    String? shell,
    String? profileId,
    String? profileName,
    AgentSessionSummary? sessionSummary,
    bool? readOnly,
    bool? shellHookAvailable,
    AgentCommandBlockSnapshot? selectedBlock,
    AgentTerminalOutputSelection? selectedOutput,
    AgentCommandBlockSnapshot? lastFailedBlock,
    List<AgentRecentCommandSnapshot>? recentCommands,
    String? visibleScrollbackExcerpt,
    List<AgentContextAttachment>? attachments,
  }) {
    return AgentContextSnapshot(
      terminalSessionId: terminalSessionId ?? this.terminalSessionId,
      cwd: cwd ?? this.cwd,
      shell: shell ?? this.shell,
      profileId: profileId ?? this.profileId,
      profileName: profileName ?? this.profileName,
      sessionSummary: sessionSummary ?? this.sessionSummary,
      readOnly: readOnly ?? this.readOnly,
      shellHookAvailable: shellHookAvailable ?? this.shellHookAvailable,
      selectedBlock: selectedBlock ?? this.selectedBlock,
      selectedOutput: selectedOutput ?? this.selectedOutput,
      lastFailedBlock: lastFailedBlock ?? this.lastFailedBlock,
      recentCommands: recentCommands ?? this.recentCommands,
      visibleScrollbackExcerpt:
          visibleScrollbackExcerpt ?? this.visibleScrollbackExcerpt,
      attachments: attachments ?? this.attachments,
    );
  }
}

bool _hasText(String? value) {
  final trimmed = value?.trim();
  return trimmed != null && trimmed.isNotEmpty;
}
