import 'agent_context_attachment.dart';
import 'agent_context_privacy_filter.dart';
import 'agent_context_snapshot.dart';

class AgentContextSource {
  const AgentContextSource({
    required this.terminalSessionId,
    this.cwd,
    this.shell,
    this.profileId,
    this.profileName,
    this.readOnly = false,
    this.shellHookAvailable = false,
    this.selectedBlock,
    this.selectedOutput,
    this.lastFailedBlock,
    this.recentCommands = const <AgentRecentCommandSnapshot>[],
    this.visibleScrollback,
  });

  final String terminalSessionId;
  final String? cwd;
  final String? shell;
  final String? profileId;
  final String? profileName;
  final bool readOnly;
  final bool shellHookAvailable;
  final AgentCommandBlockSnapshot? selectedBlock;
  final AgentTerminalOutputSelection? selectedOutput;
  final AgentCommandBlockSnapshot? lastFailedBlock;
  final List<AgentRecentCommandSnapshot> recentCommands;
  final String? visibleScrollback;
}

class AgentContextBuilder {
  const AgentContextBuilder({
    this.selectedOutputMaxChars = 12000,
    this.visibleScrollbackMaxChars = 8000,
    this.blockOutputMaxChars = 4000,
    this.commandMaxChars = 512,
    this.metadataMaxChars = 512,
    this.recentCommandMaxChars = 240,
    this.recentCommandLimit = 50,
    this.privacyFilter = const AgentContextPrivacyFilter(),
  });

  final int selectedOutputMaxChars;
  final int visibleScrollbackMaxChars;
  final int blockOutputMaxChars;
  final int commandMaxChars;
  final int metadataMaxChars;
  final int recentCommandMaxChars;
  final int recentCommandLimit;
  final AgentContextPrivacyFilter privacyFilter;

  AgentContextSnapshot build(AgentContextSource source) {
    final effectiveRecentCommandLimit = recentCommandLimit < 0
        ? 0
        : recentCommandLimit;
    final cwd = _filterText(source.cwd, metadataMaxChars);
    final shell = _filterText(source.shell, metadataMaxChars);
    final profileId = _filterText(source.profileId, metadataMaxChars);
    final profileName = _filterText(source.profileName, metadataMaxChars);
    final recentCommands = source.recentCommands
        .take(effectiveRecentCommandLimit)
        .map(_filterRecentCommand)
        .whereType<AgentRecentCommandSnapshot>()
        .toList(growable: false);
    final selectedBlock = _trimBlock(source.selectedBlock);
    final selectedOutput = _trimSelection(source.selectedOutput);
    final lastFailedBlock = _trimBlock(source.lastFailedBlock);
    final visibleScrollbackExcerpt = _filterText(
      source.visibleScrollback,
      visibleScrollbackMaxChars,
    );
    final sessionSummary = _sessionSummaryFor(
      terminalSessionId: source.terminalSessionId,
      cwd: cwd,
      shell: shell,
      profileName: profileName ?? profileId,
      selectedBlock: selectedBlock,
      lastFailedBlock: lastFailedBlock,
      recentCommands: recentCommands,
    );

    final attachments = <AgentContextAttachment>[
      if (_hasText(cwd)) _cwdAttachment(cwd!),
      if (_hasText(shell)) _shellAttachment(shell!),
      if (_hasText(profileName) || _hasText(profileId))
        _profileAttachment(profileId: profileId, profileName: profileName),
      if (sessionSummary != null) _sessionSummaryAttachment(sessionSummary),
      if (selectedBlock != null) _selectedBlockAttachment(selectedBlock),
      if (selectedOutput != null) _selectedOutputAttachment(selectedOutput),
      if (lastFailedBlock != null) _lastFailedBlockAttachment(lastFailedBlock),
      if (recentCommands.isNotEmpty) _recentCommandsAttachment(recentCommands),
      if (_hasText(visibleScrollbackExcerpt))
        _visibleScrollbackAttachment(visibleScrollbackExcerpt!),
    ];

    return AgentContextSnapshot(
      terminalSessionId: source.terminalSessionId,
      cwd: cwd,
      shell: shell,
      profileId: profileId,
      profileName: profileName,
      sessionSummary: sessionSummary,
      readOnly: source.readOnly,
      shellHookAvailable: source.shellHookAvailable,
      selectedBlock: selectedBlock,
      selectedOutput: selectedOutput,
      lastFailedBlock: lastFailedBlock,
      recentCommands: recentCommands,
      visibleScrollbackExcerpt: visibleScrollbackExcerpt,
      attachments: List<AgentContextAttachment>.unmodifiable(attachments),
    );
  }

  AgentSessionSummary? _sessionSummaryFor({
    required String terminalSessionId,
    required String? cwd,
    required String? shell,
    required String? profileName,
    required AgentCommandBlockSnapshot? selectedBlock,
    required AgentCommandBlockSnapshot? lastFailedBlock,
    required List<AgentRecentCommandSnapshot> recentCommands,
  }) {
    final summary = AgentSessionSummary(
      terminalSessionId: terminalSessionId,
      cwd: cwd,
      shell: shell,
      profileName: profileName,
      selectedBlockCommand: _trimmedOrNull(selectedBlock?.command),
      lastFailedCommand: _trimmedOrNull(lastFailedBlock?.command),
      lastFailedExitCode: lastFailedBlock?.exitCode,
      recentCommandCount: recentCommands.length,
      failedRecentCommandCount: recentCommands
          .where((command) => command.status == AgentRecentCommandStatus.failed)
          .length,
    );
    return summary.hasContent ? summary : null;
  }

  AgentCommandBlockSnapshot? _trimBlock(AgentCommandBlockSnapshot? block) {
    if (block == null) {
      return null;
    }
    final command = _filterText(block.command, commandMaxChars);
    if (!_hasText(command)) {
      return null;
    }
    return AgentCommandBlockSnapshot(
      id: block.id,
      command: command!,
      cwd: _filterText(block.cwd, metadataMaxChars),
      exitCode: block.exitCode,
      outputExcerpt: _filterText(block.outputExcerpt, blockOutputMaxChars),
      startedAt: block.startedAt,
      finishedAt: block.finishedAt,
    );
  }

  AgentTerminalOutputSelection? _trimSelection(
    AgentTerminalOutputSelection? selection,
  ) {
    if (selection == null) {
      return null;
    }
    final text = _filterText(selection.text, selectedOutputMaxChars);
    if (!_hasText(text)) {
      return null;
    }
    return AgentTerminalOutputSelection(
      text: text!,
      blockId: _filterText(selection.blockId, metadataMaxChars),
      startRow: selection.startRow,
      endRowExclusive: selection.endRowExclusive,
    );
  }

  AgentRecentCommandSnapshot? _filterRecentCommand(
    AgentRecentCommandSnapshot command,
  ) {
    final text = _filterText(command.command, recentCommandMaxChars);
    if (!_hasText(text)) {
      return null;
    }
    return AgentRecentCommandSnapshot(
      command: text!,
      status: command.status,
      cwd: _filterText(command.cwd, metadataMaxChars),
      exitCode: command.exitCode,
      startedAt: command.startedAt,
    );
  }

  String? _filterText(String? text, int maxChars) {
    final trimmed = _trimmedOrNull(text);
    if (trimmed == null) {
      return null;
    }
    return _trimText(privacyFilter.redactText(trimmed), maxChars);
  }

  AgentContextAttachment _cwdAttachment(String cwd) {
    return AgentContextAttachment(
      id: 'cwd',
      kind: AgentContextAttachmentKind.cwd,
      label: 'CWD',
      preview: previewContextText(cwd),
      payload: <String, Object?>{'cwd': cwd.trim()},
      removable: false,
    );
  }

  AgentContextAttachment _shellAttachment(String shell) {
    return AgentContextAttachment(
      id: 'shell',
      kind: AgentContextAttachmentKind.shell,
      label: 'Shell',
      preview: previewContextText(shell),
      payload: <String, Object?>{'shell': shell.trim()},
      removable: false,
    );
  }

  AgentContextAttachment _profileAttachment({
    required String? profileId,
    required String? profileName,
  }) {
    final label = _trimmedOrNull(profileName) ?? _trimmedOrNull(profileId)!;
    return AgentContextAttachment(
      id: 'profile',
      kind: AgentContextAttachmentKind.profile,
      label: 'Profile',
      preview: previewContextText(label),
      payload: <String, Object?>{
        'profileId': _trimmedOrNull(profileId),
        'profileName': _trimmedOrNull(profileName),
      },
      removable: false,
    );
  }

  AgentContextAttachment _sessionSummaryAttachment(
    AgentSessionSummary summary,
  ) {
    return AgentContextAttachment(
      id: 'session-summary',
      kind: AgentContextAttachmentKind.sessionSummary,
      label: 'Session summary',
      preview: previewContextText(summary.preview),
      payload: summary,
    );
  }

  AgentContextAttachment _selectedBlockAttachment(
    AgentCommandBlockSnapshot block,
  ) {
    return AgentContextAttachment(
      id: 'selected-block:${block.id}',
      kind: AgentContextAttachmentKind.selectedBlock,
      label: 'Selected block',
      preview: previewContextText(block.command),
      payload: block,
    );
  }

  AgentContextAttachment _selectedOutputAttachment(
    AgentTerminalOutputSelection selection,
  ) {
    return AgentContextAttachment(
      id: selection.blockId == null
          ? 'selected-output'
          : 'selected-output:${selection.blockId}',
      kind: AgentContextAttachmentKind.selectedOutput,
      label: 'Selected output',
      preview: previewContextText(selection.text),
      payload: selection,
    );
  }

  AgentContextAttachment _lastFailedBlockAttachment(
    AgentCommandBlockSnapshot block,
  ) {
    return AgentContextAttachment(
      id: 'last-failed-block:${block.id}',
      kind: AgentContextAttachmentKind.lastFailedBlock,
      label: 'Last failed',
      preview: previewContextText(block.command),
      payload: block,
    );
  }

  AgentContextAttachment _recentCommandsAttachment(
    List<AgentRecentCommandSnapshot> recentCommands,
  ) {
    return AgentContextAttachment(
      id: 'recent-commands',
      kind: AgentContextAttachmentKind.recentCommands,
      label: 'Recent commands',
      preview: '${recentCommands.length} recent commands',
      payload: recentCommands,
    );
  }

  AgentContextAttachment _visibleScrollbackAttachment(String excerpt) {
    return AgentContextAttachment(
      id: 'visible-scrollback',
      kind: AgentContextAttachmentKind.visibleScrollback,
      label: 'Visible scrollback',
      preview: previewContextText(excerpt),
      payload: excerpt,
    );
  }
}

String? _trimText(String? text, int maxChars) {
  final trimmed = _trimmedOrNull(text);
  if (trimmed == null) {
    return null;
  }
  if (maxChars <= 0) {
    return null;
  }
  if (trimmed.length <= maxChars) {
    return trimmed;
  }
  return trimmed.substring(trimmed.length - maxChars);
}

String? _trimmedOrNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

bool _hasText(String? value) {
  return _trimmedOrNull(value) != null;
}
