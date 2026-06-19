enum AgentCommandRiskLevel { low, medium, high, destructive, unknown }

enum AgentCommandProposalSource { agent, mock, userEdited }

class AgentCommandProposal {
  const AgentCommandProposal({
    required this.id,
    required this.conversationId,
    required this.command,
    required this.explanation,
    required this.createdAt,
    this.cwd,
    this.riskLevel = AgentCommandRiskLevel.unknown,
    this.warnings = const <String>[],
    this.detectedEffects = const <String>[],
    this.requiresConfirmation = true,
    this.source = AgentCommandProposalSource.agent,
  });

  final String id;
  final String conversationId;
  final String command;
  final String? cwd;
  final String explanation;
  final AgentCommandRiskLevel riskLevel;
  final List<String> warnings;
  final List<String> detectedEffects;
  final bool requiresConfirmation;
  final AgentCommandProposalSource source;
  final DateTime createdAt;

  AgentCommandProposal copyWith({
    String? id,
    String? conversationId,
    String? command,
    String? cwd,
    String? explanation,
    AgentCommandRiskLevel? riskLevel,
    List<String>? warnings,
    List<String>? detectedEffects,
    bool? requiresConfirmation,
    AgentCommandProposalSource? source,
    DateTime? createdAt,
  }) {
    return AgentCommandProposal(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      command: command ?? this.command,
      cwd: cwd ?? this.cwd,
      explanation: explanation ?? this.explanation,
      riskLevel: riskLevel ?? this.riskLevel,
      warnings: warnings ?? this.warnings,
      detectedEffects: detectedEffects ?? this.detectedEffects,
      requiresConfirmation: requiresConfirmation ?? this.requiresConfirmation,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
