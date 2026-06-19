import 'agent_command_proposal.dart';
import 'agent_context_snapshot.dart';
import 'agent_conversation_models.dart';

enum AgentToolPolicy { disabled, proposalsOnly }

class AgentRequestContext {
  const AgentRequestContext({
    this.terminalSessionId,
    this.cwd,
    this.readOnly = false,
    this.snapshot,
  });

  final String? terminalSessionId;
  final String? cwd;
  final bool readOnly;
  final AgentContextSnapshot? snapshot;
}

class AgentModelConfig {
  const AgentModelConfig({
    required this.providerLabel,
    required this.model,
    this.providerId,
    this.secretBoundary,
  });

  final String? providerId;
  final String providerLabel;
  final String model;
  final String? secretBoundary;
}

class AgentRequest {
  const AgentRequest({
    required this.id,
    required this.conversationId,
    required this.messages,
    this.context = const AgentRequestContext(),
    this.modelConfig,
    this.toolPolicy = AgentToolPolicy.proposalsOnly,
  });

  final String id;
  final String conversationId;
  final List<AgentMessage> messages;
  final AgentRequestContext context;
  final AgentModelConfig? modelConfig;
  final AgentToolPolicy toolPolicy;
}

abstract class AgentRuntimeAdapter {
  Stream<AgentResponseEvent> send(AgentRequest request);

  Future<void> cancel(String requestId);
}

sealed class AgentResponseEvent {
  const AgentResponseEvent({required this.requestId});

  final String requestId;
}

class AgentResponseStarted extends AgentResponseEvent {
  const AgentResponseStarted({required super.requestId});
}

class AgentResponseTextDelta extends AgentResponseEvent {
  const AgentResponseTextDelta({required super.requestId, required this.delta});

  final String delta;
}

class AgentResponseCommandProposal extends AgentResponseEvent {
  const AgentResponseCommandProposal({
    required super.requestId,
    required this.proposal,
  });

  final AgentCommandProposal proposal;
}

class AgentResponseCompleted extends AgentResponseEvent {
  const AgentResponseCompleted({required super.requestId});
}

class AgentResponseCancelled extends AgentResponseEvent {
  const AgentResponseCancelled({required super.requestId});
}

class AgentResponseFailed extends AgentResponseEvent {
  const AgentResponseFailed({required super.requestId, required this.error});

  final Object error;
}
