import 'package:app/features/agent_center/agent_center.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MockAgentRuntimeAdapter', () {
    final createdAt = DateTime.utc(2026, 6, 19, 12);

    AgentRequest request() {
      return AgentRequest(
        id: 'request-1',
        conversationId: 'conversation-1',
        messages: <AgentMessage>[
          AgentMessage.userText(
            id: 'message-1',
            conversationId: 'conversation-1',
            text: 'Explain pwd',
            createdAt: createdAt,
          ),
        ],
        context: const AgentRequestContext(
          terminalSessionId: 'terminal-1',
          cwd: '/Users/luobinghui',
        ),
      );
    }

    test('streams text deltas without network credentials', () async {
      final adapter = MockAgentRuntimeAdapter(
        steps: <MockAgentResponseStep>[
          MockAgentResponseStep.text('First '),
          MockAgentResponseStep.text('second.'),
        ],
      );

      final events = await adapter.send(request()).toList();

      expect(events, hasLength(4));
      expect(events[0], isA<AgentResponseStarted>());
      expect(
        events.whereType<AgentResponseTextDelta>().map((event) => event.delta),
        <String>['First ', 'second.'],
      );
      expect(events.last, isA<AgentResponseCompleted>());
    });

    test('streams command proposal events', () async {
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
      final adapter = MockAgentRuntimeAdapter(
        steps: <MockAgentResponseStep>[
          MockAgentResponseStep.text('I can suggest a command.'),
          MockAgentResponseStep.commandProposal(proposal),
        ],
      );

      final events = await adapter.send(request()).toList();
      final proposals = events.whereType<AgentResponseCommandProposal>();

      expect(proposals, hasLength(1));
      expect(proposals.single.proposal.command, 'git status --short');
      expect(events.last, isA<AgentResponseCompleted>());
    });

    test('cancel stops future deltas and emits cancelled', () async {
      final adapter = MockAgentRuntimeAdapter(
        steps: <MockAgentResponseStep>[
          MockAgentResponseStep.text('first'),
          MockAgentResponseStep.text('second'),
        ],
      );
      final events = <AgentResponseEvent>[];

      await for (final event in adapter.send(request())) {
        events.add(event);
        if (event is AgentResponseTextDelta) {
          await adapter.cancel(event.requestId);
        }
      }

      expect(
        events.whereType<AgentResponseTextDelta>().map((event) => event.delta),
        <String>['first'],
      );
      expect(events.last, isA<AgentResponseCancelled>());
    });

    test('emits failed event from a failure step', () async {
      final adapter = MockAgentRuntimeAdapter(
        steps: <MockAgentResponseStep>[
          MockAgentResponseStep.failure(StateError('boom')),
        ],
      );

      final events = await adapter.send(request()).toList();

      expect(events[0], isA<AgentResponseStarted>());
      expect(events.last, isA<AgentResponseFailed>());
      expect(
        (events.last as AgentResponseFailed).error.toString(),
        contains('boom'),
      );
    });
  });
}
