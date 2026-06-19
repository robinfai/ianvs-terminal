import 'agent_command_proposal.dart';

enum AgentConversationStatus {
  idle,
  streaming,
  waitingForUser,
  toolRunning,
  completed,
  cancelled,
  failed,
}

enum AgentMessageRole { user, assistant, system, tool }

enum AgentMessageStatus { pending, streaming, completed, cancelled, failed }

enum AgentMessagePartKind {
  text,
  markdown,
  codeBlock,
  commandProposal,
  terminalOutputExcerpt,
  diagnostic,
  toolCall,
  toolResult,
}

class AgentConversation {
  const AgentConversation({
    required this.id,
    required this.title,
    required this.status,
    required this.messages,
    required this.createdAt,
    required this.updatedAt,
    this.terminalSessionId,
  });

  factory AgentConversation.empty({
    required String id,
    required DateTime now,
    String? terminalSessionId,
    String title = 'Agent',
  }) {
    return AgentConversation(
      id: id,
      title: title,
      terminalSessionId: terminalSessionId,
      status: AgentConversationStatus.idle,
      messages: const <AgentMessage>[],
      createdAt: now,
      updatedAt: now,
    );
  }

  final String id;
  final String title;
  final String? terminalSessionId;
  final AgentConversationStatus status;
  final List<AgentMessage> messages;
  final DateTime createdAt;
  final DateTime updatedAt;

  AgentConversation appendMessage(AgentMessage message) {
    return copyWith(
      messages: <AgentMessage>[...messages, message],
      updatedAt: message.createdAt,
      status: _statusAfterAppending(message),
    );
  }

  AgentConversation replaceMessage(AgentMessage message) {
    final replaced = messages.any((existing) => existing.id == message.id);
    if (!replaced) {
      return appendMessage(message);
    }
    final nextMessages = <AgentMessage>[
      for (final existing in messages)
        if (existing.id == message.id) ...[message] else ...[existing],
    ];
    return copyWith(
      messages: nextMessages,
      updatedAt: message.createdAt,
      status: _statusAfterAppending(message),
    );
  }

  AgentConversation markStreaming(DateTime updatedAt) {
    return copyWith(
      status: AgentConversationStatus.streaming,
      updatedAt: updatedAt,
    );
  }

  AgentConversation markCompleted(DateTime updatedAt) {
    return copyWith(
      status: AgentConversationStatus.completed,
      updatedAt: updatedAt,
    );
  }

  AgentConversation markCancelled(DateTime updatedAt) {
    return copyWith(
      status: AgentConversationStatus.cancelled,
      updatedAt: updatedAt,
    );
  }

  AgentConversation markFailed(DateTime updatedAt) {
    return copyWith(
      status: AgentConversationStatus.failed,
      updatedAt: updatedAt,
    );
  }

  AgentMessage? messageById(String id) {
    for (final message in messages) {
      if (message.id == id) {
        return message;
      }
    }
    return null;
  }

  AgentConversation copyWith({
    String? id,
    String? title,
    String? terminalSessionId,
    AgentConversationStatus? status,
    List<AgentMessage>? messages,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AgentConversation(
      id: id ?? this.id,
      title: title ?? this.title,
      terminalSessionId: terminalSessionId ?? this.terminalSessionId,
      status: status ?? this.status,
      messages: messages ?? this.messages,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  AgentConversationStatus _statusAfterAppending(AgentMessage message) {
    if (message.status == AgentMessageStatus.failed) {
      return AgentConversationStatus.failed;
    }
    if (message.status == AgentMessageStatus.cancelled) {
      return AgentConversationStatus.cancelled;
    }
    if (message.status == AgentMessageStatus.streaming) {
      return AgentConversationStatus.streaming;
    }
    if (message.role == AgentMessageRole.user) {
      return AgentConversationStatus.waitingForUser;
    }
    return AgentConversationStatus.completed;
  }
}

class AgentMessage {
  const AgentMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.parts,
    required this.createdAt,
    this.status = AgentMessageStatus.completed,
  });

  factory AgentMessage.userText({
    required String id,
    required String conversationId,
    required String text,
    required DateTime createdAt,
  }) {
    return AgentMessage(
      id: id,
      conversationId: conversationId,
      role: AgentMessageRole.user,
      parts: <AgentMessagePart>[AgentMessagePart.text(text)],
      createdAt: createdAt,
    );
  }

  factory AgentMessage.assistantText({
    required String id,
    required String conversationId,
    required String text,
    required DateTime createdAt,
    AgentMessageStatus status = AgentMessageStatus.completed,
  }) {
    return AgentMessage(
      id: id,
      conversationId: conversationId,
      role: AgentMessageRole.assistant,
      parts: <AgentMessagePart>[AgentMessagePart.text(text)],
      createdAt: createdAt,
      status: status,
    );
  }

  final String id;
  final String conversationId;
  final AgentMessageRole role;
  final List<AgentMessagePart> parts;
  final DateTime createdAt;
  final AgentMessageStatus status;

  bool get hasCommandProposal {
    return parts.any(
      (part) => part.kind == AgentMessagePartKind.commandProposal,
    );
  }

  String get plainText {
    return parts
        .where((part) => part.text.isNotEmpty)
        .map((part) => part.text)
        .join();
  }

  AgentMessage copyWith({
    String? id,
    String? conversationId,
    AgentMessageRole? role,
    List<AgentMessagePart>? parts,
    DateTime? createdAt,
    AgentMessageStatus? status,
  }) {
    return AgentMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      role: role ?? this.role,
      parts: parts ?? this.parts,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
    );
  }
}

class AgentMessagePart {
  const AgentMessagePart({
    required this.kind,
    this.text = '',
    this.language,
    this.commandProposal,
  });

  factory AgentMessagePart.text(String text) {
    return AgentMessagePart(kind: AgentMessagePartKind.text, text: text);
  }

  factory AgentMessagePart.markdown(String text) {
    return AgentMessagePart(kind: AgentMessagePartKind.markdown, text: text);
  }

  factory AgentMessagePart.codeBlock(String code, {String? language}) {
    return AgentMessagePart(
      kind: AgentMessagePartKind.codeBlock,
      text: code,
      language: language,
    );
  }

  factory AgentMessagePart.commandProposal(AgentCommandProposal proposal) {
    return AgentMessagePart(
      kind: AgentMessagePartKind.commandProposal,
      text: proposal.command,
      commandProposal: proposal,
    );
  }

  factory AgentMessagePart.terminalOutputExcerpt(String text) {
    return AgentMessagePart(
      kind: AgentMessagePartKind.terminalOutputExcerpt,
      text: text,
    );
  }

  factory AgentMessagePart.diagnostic(String text) {
    return AgentMessagePart(kind: AgentMessagePartKind.diagnostic, text: text);
  }

  final AgentMessagePartKind kind;
  final String text;
  final String? language;
  final AgentCommandProposal? commandProposal;
}

class InMemoryAgentConversationStore {
  final Map<String, AgentConversation> _conversations =
      <String, AgentConversation>{};

  List<AgentConversation> get conversations {
    final values = _conversations.values.toList(growable: false)
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return List<AgentConversation>.unmodifiable(values);
  }

  AgentConversation? byId(String id) {
    return _conversations[id];
  }

  AgentConversation save(AgentConversation conversation) {
    _conversations[conversation.id] = conversation;
    return conversation;
  }

  AgentConversation appendMessage(String conversationId, AgentMessage message) {
    final conversation = _conversations[conversationId];
    if (conversation == null) {
      throw StateError('Missing Agent conversation: $conversationId');
    }
    final updated = conversation.appendMessage(message);
    _conversations[conversationId] = updated;
    return updated;
  }
}
