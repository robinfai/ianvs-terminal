import 'agent_command_proposal.dart';

enum AgentCommandSafetyDisposition { allowed, confirmationRequired, blocked }

enum AgentCommandSafetyReason {
  allowedLowRisk,
  allowedAfterConfirmation,
  emptyCommand,
  readOnly,
  confirmationRequired,
}

class AgentCommandSafetyRequest {
  const AgentCommandSafetyRequest({
    required this.proposal,
    this.readOnly = false,
    this.userConfirmed = false,
  });

  final AgentCommandProposal proposal;
  final bool readOnly;
  final bool userConfirmed;
}

class AgentCommandSafetyDecision {
  const AgentCommandSafetyDecision({
    required this.disposition,
    required this.reason,
    required this.message,
    required this.writesToPty,
  });

  final AgentCommandSafetyDisposition disposition;
  final AgentCommandSafetyReason reason;
  final String message;
  final bool writesToPty;

  bool get canExecute => disposition == AgentCommandSafetyDisposition.allowed;
  bool get blocked => disposition == AgentCommandSafetyDisposition.blocked;
  bool get requiresConfirmation =>
      disposition == AgentCommandSafetyDisposition.confirmationRequired;
}

class AgentCommandSafetyPipeline {
  const AgentCommandSafetyPipeline();

  AgentCommandSafetyDecision evaluate(AgentCommandSafetyRequest request) {
    final proposal = request.proposal;
    if (proposal.command.trim().isEmpty) {
      return const AgentCommandSafetyDecision(
        disposition: AgentCommandSafetyDisposition.blocked,
        reason: AgentCommandSafetyReason.emptyCommand,
        message: 'Agent proposal has no command to run.',
        writesToPty: false,
      );
    }
    if (request.readOnly) {
      return const AgentCommandSafetyDecision(
        disposition: AgentCommandSafetyDisposition.blocked,
        reason: AgentCommandSafetyReason.readOnly,
        message: 'Read-only mode is enabled. Agent proposals cannot run.',
        writesToPty: false,
      );
    }
    if (requiresExplicitConfirmation(proposal) && !request.userConfirmed) {
      return const AgentCommandSafetyDecision(
        disposition: AgentCommandSafetyDisposition.confirmationRequired,
        reason: AgentCommandSafetyReason.confirmationRequired,
        message: 'Confirm this reviewed Agent command before running it.',
        writesToPty: false,
      );
    }

    final confirmed = requiresExplicitConfirmation(proposal);
    return AgentCommandSafetyDecision(
      disposition: AgentCommandSafetyDisposition.allowed,
      reason: confirmed
          ? AgentCommandSafetyReason.allowedAfterConfirmation
          : AgentCommandSafetyReason.allowedLowRisk,
      message: confirmed
          ? 'Confirmed Agent command is ready to run in the terminal.'
          : 'Low-risk Agent command is ready to run in the terminal.',
      writesToPty: true,
    );
  }

  bool requiresExplicitConfirmation(AgentCommandProposal proposal) {
    return proposal.requiresConfirmation ||
        switch (proposal.riskLevel) {
          AgentCommandRiskLevel.low => false,
          AgentCommandRiskLevel.medium ||
          AgentCommandRiskLevel.high ||
          AgentCommandRiskLevel.destructive ||
          AgentCommandRiskLevel.unknown => true,
        };
  }
}
