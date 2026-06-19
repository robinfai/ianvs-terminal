import 'package:app/features/agent_center/agent_center.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentCommandSafetyPipeline', () {
    const pipeline = AgentCommandSafetyPipeline();

    test('allows low-risk proposals that do not request confirmation', () {
      final decision = pipeline.evaluate(
        AgentCommandSafetyRequest(
          proposal: _proposal(
            command: 'pwd',
            riskLevel: AgentCommandRiskLevel.low,
            requiresConfirmation: false,
          ),
        ),
      );

      expect(decision.disposition, AgentCommandSafetyDisposition.allowed);
      expect(decision.reason, AgentCommandSafetyReason.allowedLowRisk);
      expect(decision.canExecute, isTrue);
      expect(decision.writesToPty, isTrue);
    });

    test('requires confirmation for caution-level proposals', () {
      final proposal = _proposal(
        command: 'sudo lsof -i :8080',
        riskLevel: AgentCommandRiskLevel.medium,
        requiresConfirmation: false,
      );
      final pending = pipeline.evaluate(
        AgentCommandSafetyRequest(proposal: proposal),
      );
      final confirmed = pipeline.evaluate(
        AgentCommandSafetyRequest(proposal: proposal, userConfirmed: true),
      );

      expect(
        pending.disposition,
        AgentCommandSafetyDisposition.confirmationRequired,
      );
      expect(pending.canExecute, isFalse);
      expect(confirmed.disposition, AgentCommandSafetyDisposition.allowed);
      expect(
        confirmed.reason,
        AgentCommandSafetyReason.allowedAfterConfirmation,
      );
    });

    test('requires confirmation for destructive proposals', () {
      final proposal = _proposal(
        command: 'rm -rf build',
        riskLevel: AgentCommandRiskLevel.destructive,
        requiresConfirmation: false,
      );

      expect(pipeline.requiresExplicitConfirmation(proposal), isTrue);
      expect(
        pipeline
            .evaluate(AgentCommandSafetyRequest(proposal: proposal))
            .requiresConfirmation,
        isTrue,
      );
    });

    test('blocks execution in read-only mode', () {
      final decision = pipeline.evaluate(
        AgentCommandSafetyRequest(
          proposal: _proposal(command: 'pwd'),
          readOnly: true,
          userConfirmed: true,
        ),
      );

      expect(decision.disposition, AgentCommandSafetyDisposition.blocked);
      expect(decision.reason, AgentCommandSafetyReason.readOnly);
      expect(decision.canExecute, isFalse);
      expect(decision.writesToPty, isFalse);
    });

    test('blocks empty commands', () {
      final decision = pipeline.evaluate(
        AgentCommandSafetyRequest(proposal: _proposal(command: '  ')),
      );

      expect(decision.disposition, AgentCommandSafetyDisposition.blocked);
      expect(decision.reason, AgentCommandSafetyReason.emptyCommand);
      expect(decision.canExecute, isFalse);
    });
  });
}

AgentCommandProposal _proposal({
  required String command,
  AgentCommandRiskLevel riskLevel = AgentCommandRiskLevel.low,
  bool requiresConfirmation = false,
}) {
  return AgentCommandProposal(
    id: 'proposal',
    conversationId: 'conversation',
    command: command,
    explanation: 'Generated for testing.',
    riskLevel: riskLevel,
    requiresConfirmation: requiresConfirmation,
    createdAt: DateTime(2026),
  );
}
