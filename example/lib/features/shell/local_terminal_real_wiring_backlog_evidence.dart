import 'local_terminal_completion_evidence_report.dart';
import 'local_terminal_production_wiring_bundle.dart';
import 'local_terminal_verification_evidence.dart';

class LocalTerminalRealWiringBacklogEvidence {
  const LocalTerminalRealWiringBacklogEvidence({
    this.shellActionWiring = const LocalTerminalRealWiringTaskEvidence.pending(
      LocalTerminalRealWiringTask.shellActionProductionWiring,
    ),
    this.workspaceWiring = const LocalTerminalRealWiringTaskEvidence.pending(
      LocalTerminalRealWiringTask.localWorkspaceProductionWiring,
    ),
    this.productivityWiring = const LocalTerminalRealWiringTaskEvidence.pending(
      LocalTerminalRealWiringTask.shellProductivityProductionWiring,
    ),
    this.policyWiring = const LocalTerminalRealWiringTaskEvidence.pending(
      LocalTerminalRealWiringTask.localTerminalPolicyProductionWiring,
    ),
    this.visualWiring = const LocalTerminalRealWiringTaskEvidence.pending(
      LocalTerminalRealWiringTask.localTerminalVisualProductionWiring,
    ),
    this.verificationAndClosure =
        const LocalTerminalRealWiringTaskEvidence.pending(
          LocalTerminalRealWiringTask.localTerminalVerificationAndClosure,
        ),
  });

  factory LocalTerminalRealWiringBacklogEvidence.currentImplementedUnverified({
    required LocalTerminalVerificationEvidence verificationEvidence,
  }) {
    return LocalTerminalRealWiringBacklogEvidence(
      shellActionWiring: LocalTerminalRealWiringTaskEvidence.implementedButUnverified(
        task: LocalTerminalRealWiringTask.shellActionProductionWiring,
        evidence: const [
          'ShellScreen command menu and shortcut dispatch use production action runtime for the current P1 action baseline.',
          'T-230 P1 production action baseline closure records the currently wired action set.',
          'Native clear scrollback and historical scrollback export request plumbing exist.',
        ],
      ),
      workspaceWiring: LocalTerminalRealWiringTaskEvidence.implementedButUnverified(
        task: LocalTerminalRealWiringTask.localWorkspaceProductionWiring,
        evidence: const [
          'Split, pane focus, close, resize, swap, zoom, duplicate cwd, and reopen closed tab have live ShellScreen/session wiring.',
          'Workspace production tasks T-215, T-227, T-228, T-229, and T-231 are represented in wiring.',
        ],
      ),
      productivityWiring: LocalTerminalRealWiringTaskEvidence.implementedButUnverified(
        task: LocalTerminalRealWiringTask.shellProductivityProductionWiring,
        evidence: const [
          'Search, prompt navigation, command output selection/copy, recent directory, paste history, instant replay, autocomplete, and auto composer have production dispatch coverage.',
          'Productivity production tasks T-208, T-210, T-211, T-217, and T-232 are represented in wiring.',
        ],
      ),
      policyWiring: LocalTerminalRealWiringTaskEvidence.implementedButUnverified(
        task: LocalTerminalRealWiringTask.localTerminalPolicyProductionWiring,
        evidence: const [
          'Per-session read-only mode and persisted notification toggles have ShellScreen production wiring.',
          'Policy tasks T-226, T-232, and T-238 are represented in wiring.',
        ],
      ),
      visualWiring: LocalTerminalRealWiringTaskEvidence.implementedButUnverified(
        task: LocalTerminalRealWiringTask.localTerminalVisualProductionWiring,
        evidence: const [
          'Theme picker, two-pane layout template, pane sizing, and scrollback export have production dispatch coverage.',
          'Visual/runtime tasks T-223, T-224, T-233, T-235, T-236, and T-237 are represented in wiring.',
        ],
      ),
      verificationAndClosure:
          LocalTerminalRealWiringTaskEvidence.fromVerificationEvidence(
            verificationEvidence,
          ),
    );
  }

  factory LocalTerminalRealWiringBacklogEvidence.currentVerified({
    required LocalTerminalVerificationEvidence verificationEvidence,
  }) {
    return LocalTerminalRealWiringBacklogEvidence(
      shellActionWiring: LocalTerminalRealWiringTaskEvidence.verified(
        task: LocalTerminalRealWiringTask.shellActionProductionWiring,
        evidence: const [
          'ShellScreen command menu and shortcut dispatch use production action runtime for the current P1 action baseline.',
          'P1 action/config closure passed focused, broader, integration, and manual command-menu evidence.',
        ],
      ),
      workspaceWiring: LocalTerminalRealWiringTaskEvidence.verified(
        task: LocalTerminalRealWiringTask.localWorkspaceProductionWiring,
        evidence: const [
          'Split, pane focus, close, resize, swap, zoom, duplicate cwd, and reopen closed tab have live ShellScreen/session wiring.',
          'Workspace behavior passed focused phase4, broader, integration, and manual pane evidence.',
        ],
      ),
      productivityWiring: LocalTerminalRealWiringTaskEvidence.verified(
        task: LocalTerminalRealWiringTask.shellProductivityProductionWiring,
        evidence: const [
          'Search, prompt navigation, command output selection/copy, recent directory, paste history, instant replay, autocomplete, and auto composer have production dispatch coverage.',
          'Productivity behavior passed broader and manual paste/focus evidence.',
        ],
      ),
      policyWiring: LocalTerminalRealWiringTaskEvidence.verified(
        task: LocalTerminalRealWiringTask.localTerminalPolicyProductionWiring,
        evidence: const [
          'Per-session read-only mode, paste policy, notification toggles, and hotkey-window failure feedback have ShellScreen production wiring.',
          'Policy behavior passed focused phase4, broader, integration-backed, and manual evidence.',
        ],
      ),
      visualWiring: LocalTerminalRealWiringTaskEvidence.verified(
        task: LocalTerminalRealWiringTask.localTerminalVisualProductionWiring,
        evidence: const [
          'Theme picker, two-pane layout template, pane sizing, zoom, and scrollback export have production dispatch coverage.',
          'Visual behavior passed latest broader coverage and manual pane layout evidence.',
        ],
      ),
      verificationAndClosure:
          LocalTerminalRealWiringTaskEvidence.fromVerificationEvidence(
            verificationEvidence,
          ),
    );
  }

  final LocalTerminalRealWiringTaskEvidence shellActionWiring;
  final LocalTerminalRealWiringTaskEvidence workspaceWiring;
  final LocalTerminalRealWiringTaskEvidence productivityWiring;
  final LocalTerminalRealWiringTaskEvidence policyWiring;
  final LocalTerminalRealWiringTaskEvidence visualWiring;
  final LocalTerminalRealWiringTaskEvidence verificationAndClosure;

  List<LocalTerminalRealWiringTaskEvidence> get tasks {
    return [
      shellActionWiring,
      workspaceWiring,
      productivityWiring,
      policyWiring,
      visualWiring,
      verificationAndClosure,
    ];
  }

  List<LocalTerminalCompletionBacklogItem> toBacklogItems() {
    return tasks.map((task) => task.toBacklogItem()).toList(growable: false);
  }

  LocalTerminalCompletionEvidenceReport toCompletionReport(
    LocalTerminalProductionWiringBundle bundle,
  ) {
    return LocalTerminalCompletionEvidenceReport(
      bundle: bundle,
      backlogItems: toBacklogItems(),
    );
  }
}

class LocalTerminalRealWiringTaskEvidence {
  const LocalTerminalRealWiringTaskEvidence({
    required this.task,
    required this.status,
    this.evidence = const [],
    this.blockers = const [],
  });

  const LocalTerminalRealWiringTaskEvidence.pending(this.task)
    : status = LocalTerminalCompletionBacklogStatus.pending,
      evidence = const [],
      blockers = const [];

  const LocalTerminalRealWiringTaskEvidence.verified({
    required this.task,
    required this.evidence,
    this.blockers = const [],
  }) : status = LocalTerminalCompletionBacklogStatus.verified;

  const LocalTerminalRealWiringTaskEvidence.implementedButUnverified({
    required this.task,
    required this.evidence,
  }) : status = LocalTerminalCompletionBacklogStatus.blocked,
       blockers = const ['Verification gates have not been run.'];

  factory LocalTerminalRealWiringTaskEvidence.fromVerificationEvidence(
    LocalTerminalVerificationEvidence verificationEvidence,
  ) {
    if (verificationEvidence.canClose) {
      return LocalTerminalRealWiringTaskEvidence.verified(
        task: LocalTerminalRealWiringTask.localTerminalVerificationAndClosure,
        evidence: [
          for (final item in verificationEvidence.requiredItems)
            '${item.gate.name}: ${item.status.name}',
        ],
      );
    }

    return LocalTerminalRealWiringTaskEvidence(
      task: LocalTerminalRealWiringTask.localTerminalVerificationAndClosure,
      status: LocalTerminalCompletionBacklogStatus.blocked,
      evidence: [
        for (final item in verificationEvidence.requiredItems)
          '${item.gate.name}: ${item.status.name}',
      ],
      blockers: [
        for (final item in verificationEvidence.blockingItems)
          'Verification gate ${item.gate.name} is ${item.status.name}.',
        for (final gate in verificationEvidence.missingRequiredGates)
          'Verification gate ${gate.name} is missing.',
      ],
    );
  }

  final LocalTerminalRealWiringTask task;
  final LocalTerminalCompletionBacklogStatus status;
  final List<String> evidence;
  final List<String> blockers;

  LocalTerminalCompletionBacklogItem toBacklogItem() {
    return LocalTerminalCompletionBacklogItem(
      taskId: task.taskId,
      title: task.title,
      status: status,
      evidence: evidence,
      blockers: blockers,
    );
  }
}

enum LocalTerminalRealWiringTask {
  shellActionProductionWiring,
  localWorkspaceProductionWiring,
  shellProductivityProductionWiring,
  localTerminalPolicyProductionWiring,
  localTerminalVisualProductionWiring,
  localTerminalVerificationAndClosure,
}

extension LocalTerminalRealWiringTaskX on LocalTerminalRealWiringTask {
  String get taskId {
    return switch (this) {
      LocalTerminalRealWiringTask.shellActionProductionWiring => 'T-164',
      LocalTerminalRealWiringTask.localWorkspaceProductionWiring => 'T-165',
      LocalTerminalRealWiringTask.shellProductivityProductionWiring => 'T-166',
      LocalTerminalRealWiringTask.localTerminalPolicyProductionWiring =>
        'T-167',
      LocalTerminalRealWiringTask.localTerminalVisualProductionWiring =>
        'T-168',
      LocalTerminalRealWiringTask.localTerminalVerificationAndClosure =>
        'T-169',
    };
  }

  String get title {
    return switch (this) {
      LocalTerminalRealWiringTask.shellActionProductionWiring =>
        'Shell action production wiring',
      LocalTerminalRealWiringTask.localWorkspaceProductionWiring =>
        'Local workspace production wiring',
      LocalTerminalRealWiringTask.shellProductivityProductionWiring =>
        'Shell productivity production wiring',
      LocalTerminalRealWiringTask.localTerminalPolicyProductionWiring =>
        'Local terminal policy production wiring',
      LocalTerminalRealWiringTask.localTerminalVisualProductionWiring =>
        'Local terminal visual production wiring',
      LocalTerminalRealWiringTask.localTerminalVerificationAndClosure =>
        'Local terminal verification and closure',
    };
  }
}
