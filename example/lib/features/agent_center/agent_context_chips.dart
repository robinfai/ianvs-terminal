import 'agent_context_attachment.dart';
import 'agent_context_snapshot.dart';

enum AgentContextChipTone { normal, warning, danger, disabled }

class AgentContextChipModel {
  const AgentContextChipModel({
    required this.attachmentId,
    required this.kind,
    required this.label,
    required this.preview,
    required this.semanticLabel,
    required this.tone,
    this.pinned = false,
    this.removable = true,
    this.sensitive = false,
    this.detailsAvailable = true,
  });

  final String attachmentId;
  final AgentContextAttachmentKind kind;
  final String label;
  final String preview;
  final String semanticLabel;
  final AgentContextChipTone tone;
  final bool pinned;
  final bool removable;
  final bool sensitive;
  final bool detailsAvailable;
}

class AgentContextChipState {
  const AgentContextChipState({required this.attachments, required this.chips});

  factory AgentContextChipState.fromSnapshot(AgentContextSnapshot snapshot) {
    return AgentContextChipState.fromAttachments(snapshot.attachments);
  }

  factory AgentContextChipState.fromAttachments(
    List<AgentContextAttachment> attachments,
  ) {
    final attachmentSet = AgentContextAttachmentSet(
      attachments: List<AgentContextAttachment>.unmodifiable(attachments),
    );
    return AgentContextChipState(
      attachments: attachmentSet.attachments,
      chips: List<AgentContextChipModel>.unmodifiable(
        attachmentSet.attachments.map(_chipForAttachment),
      ),
    );
  }

  final List<AgentContextAttachment> attachments;
  final List<AgentContextChipModel> chips;

  AgentContextChipModel? chipByAttachmentId(String id) {
    for (final chip in chips) {
      if (chip.attachmentId == id) {
        return chip;
      }
    }
    return null;
  }

  AgentContextChipState remove(String attachmentId) {
    return AgentContextChipState.fromAttachments(
      AgentContextAttachmentSet(
        attachments: attachments,
      ).remove(attachmentId).attachments,
    );
  }

  AgentContextChipState pin(String attachmentId) {
    return AgentContextChipState.fromAttachments(
      AgentContextAttachmentSet(
        attachments: attachments,
      ).pin(attachmentId).attachments,
    );
  }

  AgentContextChipState unpin(String attachmentId) {
    return AgentContextChipState.fromAttachments(
      AgentContextAttachmentSet(
        attachments: attachments,
      ).unpin(attachmentId).attachments,
    );
  }
}

AgentContextChipModel _chipForAttachment(AgentContextAttachment attachment) {
  final preview = attachment.sensitive
      ? 'Sensitive context hidden'
      : previewContextText(attachment.preview, maxLength: 72);
  return AgentContextChipModel(
    attachmentId: attachment.id,
    kind: attachment.kind,
    label: _stableChipLabel(attachment.kind),
    preview: preview,
    semanticLabel: '${_stableChipLabel(attachment.kind)}: $preview',
    tone: _toneForAttachment(attachment),
    pinned: attachment.userPinned,
    removable: attachment.removable,
    sensitive: attachment.sensitive,
    detailsAvailable: attachment.payload != null,
  );
}

String _stableChipLabel(AgentContextAttachmentKind kind) {
  return switch (kind) {
    AgentContextAttachmentKind.cwd => 'CWD',
    AgentContextAttachmentKind.shell => 'Shell',
    AgentContextAttachmentKind.profile => 'Profile',
    AgentContextAttachmentKind.sessionSummary => 'Summary',
    AgentContextAttachmentKind.selectedBlock => 'Block',
    AgentContextAttachmentKind.selectedOutput => 'Selection',
    AgentContextAttachmentKind.lastFailedBlock => 'Last failed',
    AgentContextAttachmentKind.recentCommands => 'Recent',
    AgentContextAttachmentKind.visibleScrollback => 'Scrollback',
    AgentContextAttachmentKind.gitBranch => 'Git branch',
    AgentContextAttachmentKind.gitStatus => 'Git status',
    AgentContextAttachmentKind.gitDiffSummary => 'Git diff',
    AgentContextAttachmentKind.fileReference => 'File',
    AgentContextAttachmentKind.manualText => 'Note',
  };
}

AgentContextChipTone _toneForAttachment(AgentContextAttachment attachment) {
  if (attachment.sensitive) {
    return AgentContextChipTone.warning;
  }
  return switch (attachment.kind) {
    AgentContextAttachmentKind.lastFailedBlock => AgentContextChipTone.danger,
    AgentContextAttachmentKind.sessionSummary ||
    AgentContextAttachmentKind.selectedBlock ||
    AgentContextAttachmentKind.selectedOutput ||
    AgentContextAttachmentKind.recentCommands ||
    AgentContextAttachmentKind.visibleScrollback ||
    AgentContextAttachmentKind.manualText => AgentContextChipTone.normal,
    AgentContextAttachmentKind.cwd ||
    AgentContextAttachmentKind.shell ||
    AgentContextAttachmentKind.profile ||
    AgentContextAttachmentKind.gitBranch ||
    AgentContextAttachmentKind.gitStatus ||
    AgentContextAttachmentKind.gitDiffSummary ||
    AgentContextAttachmentKind.fileReference => AgentContextChipTone.normal,
  };
}
