import 'local_terminal_completion_controller.dart';
import 'local_terminal_completion_evidence_report.dart';
import 'local_terminal_verification_evidence.dart';

class LocalTerminalCompletionDiagnosticsViewModel {
  const LocalTerminalCompletionDiagnosticsViewModel({
    required this.title,
    required this.status,
    required this.sections,
  });

  factory LocalTerminalCompletionDiagnosticsViewModel.fromController(
    LocalTerminalCompletionController controller,
  ) {
    return LocalTerminalCompletionDiagnosticsViewModel.fromEvidence(
      report: controller.currentState.report,
      verificationEvidence: controller.currentState.verificationEvidence,
    );
  }

  factory LocalTerminalCompletionDiagnosticsViewModel.fromEvidence({
    required LocalTerminalCompletionEvidenceReport report,
    required LocalTerminalVerificationEvidence verificationEvidence,
  }) {
    final canCloseObjective =
        report.canCloseObjective && verificationEvidence.canClose;
    final sections = <LocalTerminalCompletionDiagnosticsSection>[];

    if (report.blockedMilestones.isNotEmpty) {
      sections.add(
        LocalTerminalCompletionDiagnosticsSection(
          title: 'Blocked milestones',
          items: [
            for (final milestone in report.blockedMilestones)
              LocalTerminalCompletionDiagnosticsItem(
                label: milestone.milestone.name,
                description: milestone.effectiveBlockers.join('\n'),
                severity: LocalTerminalCompletionDiagnosticsSeverity.blocker,
              ),
          ],
        ),
      );
    }

    if (report.missingRequiredProductionMilestones.isNotEmpty) {
      sections.add(
        LocalTerminalCompletionDiagnosticsSection(
          title: 'Missing production milestones',
          items: [
            for (final milestone in report.missingRequiredProductionMilestones)
              LocalTerminalCompletionDiagnosticsItem(
                label: milestone.name,
                description:
                    'Required production milestone is absent from the wiring manifest.',
                severity: LocalTerminalCompletionDiagnosticsSeverity.blocker,
              ),
          ],
        ),
      );
    }

    if (report.blockedBacklogItems.isNotEmpty) {
      sections.add(
        LocalTerminalCompletionDiagnosticsSection(
          title: 'Blocked real-wiring backlog',
          items: [
            for (final item in report.blockedBacklogItems)
              LocalTerminalCompletionDiagnosticsItem(
                label: '${item.taskId}: ${item.title}',
                description: item.blockers.isEmpty
                    ? 'Task is ${item.status.name}.'
                    : item.blockers.join('\n'),
                severity: LocalTerminalCompletionDiagnosticsSeverity.blocker,
              ),
          ],
        ),
      );
    }

    if (report.missingRequiredBacklogTaskIds.isNotEmpty) {
      sections.add(
        LocalTerminalCompletionDiagnosticsSection(
          title: 'Missing real-wiring backlog',
          items: [
            for (final taskId in report.missingRequiredBacklogTaskIds)
              LocalTerminalCompletionDiagnosticsItem(
                label: taskId,
                description:
                    'Required backlog task is absent from completion evidence.',
                severity: LocalTerminalCompletionDiagnosticsSeverity.blocker,
              ),
          ],
        ),
      );
    }

    if (verificationEvidence.blockingItems.isNotEmpty) {
      sections.add(
        LocalTerminalCompletionDiagnosticsSection(
          title: 'Blocked verification gates',
          items: [
            for (final item in verificationEvidence.blockingItems)
              LocalTerminalCompletionDiagnosticsItem(
                label: item.gate.name,
                description: 'Gate is ${item.status.name}.',
                severity: LocalTerminalCompletionDiagnosticsSeverity.blocker,
              ),
          ],
        ),
      );
    }

    if (verificationEvidence.missingRequiredGates.isNotEmpty) {
      sections.add(
        LocalTerminalCompletionDiagnosticsSection(
          title: 'Missing verification gates',
          items: [
            for (final gate in verificationEvidence.missingRequiredGates)
              LocalTerminalCompletionDiagnosticsItem(
                label: gate.name,
                description:
                    'Required verification gate is absent from verification evidence.',
                severity: LocalTerminalCompletionDiagnosticsSeverity.blocker,
              ),
          ],
        ),
      );
    }

    if (sections.isEmpty) {
      sections.add(
        const LocalTerminalCompletionDiagnosticsSection(
          title: 'Completion',
          items: [
            LocalTerminalCompletionDiagnosticsItem(
              label: 'Objective can close',
              description:
                  'Production wiring and verification evidence are complete.',
              severity: LocalTerminalCompletionDiagnosticsSeverity.info,
            ),
          ],
        ),
      );
    }

    return LocalTerminalCompletionDiagnosticsViewModel(
      title: canCloseObjective
          ? 'Local terminal objective is complete'
          : 'Local terminal objective is blocked',
      status: canCloseObjective
          ? LocalTerminalCompletionDiagnosticsStatus.closeable
          : LocalTerminalCompletionDiagnosticsStatus.blocked,
      sections: List.unmodifiable(sections),
    );
  }

  final String title;
  final LocalTerminalCompletionDiagnosticsStatus status;
  final List<LocalTerminalCompletionDiagnosticsSection> sections;

  bool get canCloseObjective {
    return status == LocalTerminalCompletionDiagnosticsStatus.closeable;
  }

  Map<String, Object?> toJson() {
    return {
      'title': title,
      'status': status.name,
      'canCloseObjective': canCloseObjective,
      'sections': sections.map((section) => section.toJson()).toList(),
    };
  }
}

class LocalTerminalCompletionDiagnosticsSection {
  const LocalTerminalCompletionDiagnosticsSection({
    required this.title,
    required this.items,
  });

  final String title;
  final List<LocalTerminalCompletionDiagnosticsItem> items;

  Map<String, Object?> toJson() {
    return {
      'title': title,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }
}

class LocalTerminalCompletionDiagnosticsItem {
  const LocalTerminalCompletionDiagnosticsItem({
    required this.label,
    required this.description,
    required this.severity,
  });

  final String label;
  final String description;
  final LocalTerminalCompletionDiagnosticsSeverity severity;

  Map<String, Object?> toJson() {
    return {
      'label': label,
      'description': description,
      'severity': severity.name,
    };
  }
}

enum LocalTerminalCompletionDiagnosticsStatus { blocked, closeable }

enum LocalTerminalCompletionDiagnosticsSeverity { blocker, info }
