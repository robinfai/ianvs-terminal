enum AgentContextAttachmentKind {
  cwd,
  shell,
  profile,
  sessionSummary,
  selectedBlock,
  selectedOutput,
  lastFailedBlock,
  recentCommands,
  visibleScrollback,
  gitBranch,
  gitStatus,
  gitDiffSummary,
  fileReference,
  manualText,
}

class AgentContextAttachment {
  const AgentContextAttachment({
    required this.id,
    required this.kind,
    required this.label,
    required this.preview,
    this.payload,
    this.userPinned = false,
    this.sensitive = false,
    this.removable = true,
  });

  final String id;
  final AgentContextAttachmentKind kind;
  final String label;
  final String preview;
  final Object? payload;
  final bool userPinned;
  final bool sensitive;
  final bool removable;

  AgentContextAttachment copyWith({
    String? id,
    AgentContextAttachmentKind? kind,
    String? label,
    String? preview,
    Object? payload,
    bool? userPinned,
    bool? sensitive,
    bool? removable,
  }) {
    return AgentContextAttachment(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      label: label ?? this.label,
      preview: preview ?? this.preview,
      payload: payload ?? this.payload,
      userPinned: userPinned ?? this.userPinned,
      sensitive: sensitive ?? this.sensitive,
      removable: removable ?? this.removable,
    );
  }
}

class AgentContextAttachmentSet {
  const AgentContextAttachmentSet({
    this.attachments = const <AgentContextAttachment>[],
  });

  final List<AgentContextAttachment> attachments;

  AgentContextAttachment? byId(String id) {
    for (final attachment in attachments) {
      if (attachment.id == id) {
        return attachment;
      }
    }
    return null;
  }

  AgentContextAttachmentSet upsert(AgentContextAttachment attachment) {
    var replaced = false;
    final nextAttachments = <AgentContextAttachment>[
      for (final existing in attachments)
        if (existing.id == attachment.id) ...[attachment] else ...[existing],
    ];
    replaced = attachments.any((existing) => existing.id == attachment.id);
    if (!replaced) {
      nextAttachments.add(attachment);
    }
    return AgentContextAttachmentSet(
      attachments: List<AgentContextAttachment>.unmodifiable(nextAttachments),
    );
  }

  AgentContextAttachmentSet remove(String id) {
    return AgentContextAttachmentSet(
      attachments: List<AgentContextAttachment>.unmodifiable(
        attachments.where(
          (attachment) => attachment.id != id || !attachment.removable,
        ),
      ),
    );
  }

  AgentContextAttachmentSet pin(String id) {
    return _setPinned(id: id, pinned: true);
  }

  AgentContextAttachmentSet unpin(String id) {
    return _setPinned(id: id, pinned: false);
  }

  AgentContextAttachmentSet _setPinned({
    required String id,
    required bool pinned,
  }) {
    return AgentContextAttachmentSet(
      attachments: List<AgentContextAttachment>.unmodifiable(
        attachments.map((attachment) {
          if (attachment.id != id) {
            return attachment;
          }
          return attachment.copyWith(userPinned: pinned);
        }),
      ),
    );
  }
}

String previewContextText(
  String? text, {
  int maxLength = 80,
  String emptyLabel = 'No preview',
}) {
  final normalized = text?.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized == null || normalized.isEmpty) {
    return emptyLabel;
  }
  if (normalized.length <= maxLength) {
    return normalized;
  }
  return '${normalized.substring(0, maxLength - 1)}…';
}
