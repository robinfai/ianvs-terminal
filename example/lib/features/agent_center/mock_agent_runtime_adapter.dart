import 'agent_command_proposal.dart';
import 'agent_runtime_adapter.dart';

enum MockAgentResponseStepKind { textDelta, commandProposal, failure }

class MockAgentResponseStep {
  const MockAgentResponseStep._({
    required this.kind,
    this.textDelta,
    this.commandProposal,
    this.error,
  });

  factory MockAgentResponseStep.text(String delta) {
    return MockAgentResponseStep._(
      kind: MockAgentResponseStepKind.textDelta,
      textDelta: delta,
    );
  }

  factory MockAgentResponseStep.commandProposal(AgentCommandProposal proposal) {
    return MockAgentResponseStep._(
      kind: MockAgentResponseStepKind.commandProposal,
      commandProposal: proposal,
    );
  }

  factory MockAgentResponseStep.failure(Object error) {
    return MockAgentResponseStep._(
      kind: MockAgentResponseStepKind.failure,
      error: error,
    );
  }

  final MockAgentResponseStepKind kind;
  final String? textDelta;
  final AgentCommandProposal? commandProposal;
  final Object? error;
}

class MockAgentRuntimeAdapter implements AgentRuntimeAdapter {
  MockAgentRuntimeAdapter({
    List<MockAgentResponseStep> steps = const <MockAgentResponseStep>[],
    this.stepDelay = Duration.zero,
  }) : steps = steps.isEmpty
           ? <MockAgentResponseStep>[
               MockAgentResponseStep.text('Mock response'),
             ]
           : List<MockAgentResponseStep>.unmodifiable(steps);

  final List<MockAgentResponseStep> steps;
  final Duration stepDelay;
  final Set<String> _cancelledRequestIds = <String>{};

  @override
  Stream<AgentResponseEvent> send(AgentRequest request) async* {
    _cancelledRequestIds.remove(request.id);
    yield AgentResponseStarted(requestId: request.id);

    for (final step in steps) {
      if (_cancelledRequestIds.contains(request.id)) {
        yield AgentResponseCancelled(requestId: request.id);
        _cancelledRequestIds.remove(request.id);
        return;
      }

      if (stepDelay > Duration.zero) {
        await Future<void>.delayed(stepDelay);
      }

      if (_cancelledRequestIds.contains(request.id)) {
        yield AgentResponseCancelled(requestId: request.id);
        _cancelledRequestIds.remove(request.id);
        return;
      }

      switch (step.kind) {
        case MockAgentResponseStepKind.textDelta:
          yield AgentResponseTextDelta(
            requestId: request.id,
            delta: step.textDelta ?? '',
          );
        case MockAgentResponseStepKind.commandProposal:
          final proposal = step.commandProposal;
          if (proposal != null) {
            yield AgentResponseCommandProposal(
              requestId: request.id,
              proposal: proposal,
            );
          }
        case MockAgentResponseStepKind.failure:
          yield AgentResponseFailed(
            requestId: request.id,
            error: step.error ?? StateError('Mock Agent failure'),
          );
          return;
      }
    }

    if (_cancelledRequestIds.remove(request.id)) {
      yield AgentResponseCancelled(requestId: request.id);
      return;
    }
    yield AgentResponseCompleted(requestId: request.id);
  }

  @override
  Future<void> cancel(String requestId) async {
    _cancelledRequestIds.add(requestId);
  }
}
