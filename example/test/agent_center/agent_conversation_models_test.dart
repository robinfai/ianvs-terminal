import 'package:app/features/agent_center/agent_center.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentConversation', () {
    final createdAt = DateTime.utc(2026, 6, 19, 10);

    test('creates an empty provider-independent conversation', () {
      final conversation = AgentConversation.empty(
        id: 'conversation-1',
        terminalSessionId: 'terminal-1',
        now: createdAt,
      );

      expect(conversation.id, 'conversation-1');
      expect(conversation.terminalSessionId, 'terminal-1');
      expect(conversation.status, AgentConversationStatus.idle);
      expect(conversation.messages, isEmpty);
      expect(conversation.createdAt, createdAt);
      expect(conversation.updatedAt, createdAt);
    });

    test('appends messages in stable order', () {
      final conversation = AgentConversation.empty(
        id: 'conversation-1',
        now: createdAt,
      );
      final userMessage = AgentMessage.userText(
        id: 'message-1',
        conversationId: conversation.id,
        text: 'Explain the last command',
        createdAt: createdAt.add(const Duration(seconds: 1)),
      );
      final assistantMessage = AgentMessage.assistantText(
        id: 'message-2',
        conversationId: conversation.id,
        text: 'The command printed the working directory.',
        createdAt: createdAt.add(const Duration(seconds: 2)),
      );

      final updated = conversation
          .appendMessage(userMessage)
          .appendMessage(assistantMessage);

      expect(updated.messages.map((message) => message.id), <String>[
        'message-1',
        'message-2',
      ]);
      expect(updated.status, AgentConversationStatus.completed);
      expect(updated.updatedAt, assistantMessage.createdAt);
    });

    test('represents streaming and completed assistant messages', () {
      final streaming = AgentMessage.assistantText(
        id: 'message-1',
        conversationId: 'conversation-1',
        text: 'Working',
        createdAt: createdAt,
        status: AgentMessageStatus.streaming,
      );
      final completed = streaming.copyWith(
        parts: <AgentMessagePart>[AgentMessagePart.text('Working done')],
        status: AgentMessageStatus.completed,
      );

      final conversation = AgentConversation.empty(
        id: 'conversation-1',
        now: createdAt,
      ).appendMessage(streaming);

      expect(conversation.status, AgentConversationStatus.streaming);
      expect(conversation.messages.single.plainText, 'Working');

      final replaced = conversation.replaceMessage(completed);

      expect(replaced.status, AgentConversationStatus.completed);
      expect(replaced.messages.single.status, AgentMessageStatus.completed);
      expect(replaced.messages.single.plainText, 'Working done');
    });

    test('represents command proposal message parts', () {
      final proposal = AgentCommandProposal(
        id: 'proposal-1',
        conversationId: 'conversation-1',
        command: 'git status --short',
        explanation: 'Inspect local changes.',
        riskLevel: AgentCommandRiskLevel.low,
        requiresConfirmation: false,
        source: AgentCommandProposalSource.mock,
        createdAt: createdAt,
      );
      final message = AgentMessage(
        id: 'message-1',
        conversationId: 'conversation-1',
        role: AgentMessageRole.assistant,
        parts: <AgentMessagePart>[
          AgentMessagePart.markdown('Try this command:'),
          AgentMessagePart.commandProposal(proposal),
        ],
        createdAt: createdAt,
      );

      expect(message.hasCommandProposal, isTrue);
      expect(message.parts.last.commandProposal?.command, 'git status --short');
      expect(message.plainText, 'Try this command:git status --short');
    });

    test('marks failed messages and conversations', () {
      final failed = AgentMessage.assistantText(
        id: 'message-1',
        conversationId: 'conversation-1',
        text: 'Provider failed',
        createdAt: createdAt,
        status: AgentMessageStatus.failed,
      );
      final conversation = AgentConversation.empty(
        id: 'conversation-1',
        now: createdAt,
      ).appendMessage(failed);

      expect(conversation.status, AgentConversationStatus.failed);
      expect(conversation.messages.single.status, AgentMessageStatus.failed);
    });
  });

  group('InMemoryAgentConversationStore', () {
    test('saves and appends to existing conversations', () {
      final now = DateTime.utc(2026, 6, 19, 11);
      final store = InMemoryAgentConversationStore();
      store.save(AgentConversation.empty(id: 'conversation-1', now: now));

      final updated = store.appendMessage(
        'conversation-1',
        AgentMessage.userText(
          id: 'message-1',
          conversationId: 'conversation-1',
          text: 'Hello',
          createdAt: now.add(const Duration(seconds: 1)),
        ),
      );

      expect(store.byId('conversation-1'), same(updated));
      expect(updated.messages.single.plainText, 'Hello');
      expect(updated.status, AgentConversationStatus.waitingForUser);
    });
  });
}
