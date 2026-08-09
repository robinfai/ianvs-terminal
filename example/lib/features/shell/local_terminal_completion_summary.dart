import 'local_terminal_completion_evidence_report.dart';
import 'local_terminal_current_completion_state.dart';
import 'local_terminal_verification_evidence.dart';

class LocalTerminalCompletionSummary {
  const LocalTerminalCompletionSummary({
    required this.canCloseObjective,
    required this.lines,
  });

  factory LocalTerminalCompletionSummary.fromCurrentState(
    LocalTerminalCurrentCompletionState state,
  ) {
    return LocalTerminalCompletionSummary.fromEvidence(
      report: state.report,
      verificationEvidence: state.verificationEvidence,
    );
  }

  factory LocalTerminalCompletionSummary.fromEvidence({
    required LocalTerminalCompletionEvidenceReport report,
    required LocalTerminalVerificationEvidence verificationEvidence,
  }) {
    final canCloseObjective =
        report.canCloseObjective && verificationEvidence.canClose;
    final lines = <String>[
      if (canCloseObjective)
        'Local terminal objective can close.'
      else
        'Local terminal objective is blocked.',
    ];

    if (report.blockedMilestones.isNotEmpty) {
      lines.add('Blocked milestones:');
      for (final milestone in report.blockedMilestones) {
        lines.add('- ${milestone.milestone.name}');
        for (final blocker in milestone.effectiveBlockers) {
          lines.add('  - $blocker');
        }
      }
    }

    if (report.missingRequiredProductionMilestones.isNotEmpty) {
      lines.add('Missing production milestones:');
      for (final milestone in report.missingRequiredProductionMilestones) {
        lines.add('- ${milestone.name}');
      }
    }

    if (report.blockedBacklogItems.isNotEmpty) {
      lines.add('Blocked real-wiring backlog items:');
      for (final item in report.blockedBacklogItems) {
        lines.add('- ${item.taskId}: ${item.title} (${item.status.name})');
        for (final blocker in item.blockers) {
          lines.add('  - $blocker');
        }
      }
    }

    if (report.missingRequiredBacklogTaskIds.isNotEmpty) {
      lines.add('Missing real-wiring backlog items:');
      for (final taskId in report.missingRequiredBacklogTaskIds) {
        lines.add('- $taskId');
      }
    }

    if (verificationEvidence.blockingItems.isNotEmpty) {
      lines.add('Blocked verification gates:');
      for (final item in verificationEvidence.blockingItems) {
        lines.add('- ${item.gate.name}: ${item.status.name}');
      }
    }

    if (verificationEvidence.missingRequiredGates.isNotEmpty) {
      lines.add('Missing verification gates:');
      for (final gate in verificationEvidence.missingRequiredGates) {
        lines.add('- ${gate.name}');
      }
    }

    return LocalTerminalCompletionSummary(
      canCloseObjective: canCloseObjective,
      lines: List.unmodifiable(lines),
    );
  }

  final bool canCloseObjective;
  final List<String> lines;

  String toPlainText() {
    return lines.join('\n');
  }

  Map<String, Object?> toJson() {
    return {'canCloseObjective': canCloseObjective, 'lines': lines};
  }
}
