import 'local_terminal_production_wiring_manifest.dart';

class LocalTerminalP0BoundaryClosureManifest {
  const LocalTerminalP0BoundaryClosureManifest({
    required this.localTerminalPlanDocumented,
    required this.roadmapLocalWorkspaceAligned,
    required this.remoteScopeExcluded,
    required this.perMilestoneExecutionPlansCreated,
    required this.competitorCoverageMapped,
    required this.productionWiringChecklistCreated,
    this.notes = const [],
  });

  final bool localTerminalPlanDocumented;
  final bool roadmapLocalWorkspaceAligned;
  final bool remoteScopeExcluded;
  final bool perMilestoneExecutionPlansCreated;
  final bool competitorCoverageMapped;
  final bool productionWiringChecklistCreated;
  final List<String> notes;

  bool get boundaryReady {
    return localTerminalPlanDocumented &&
        roadmapLocalWorkspaceAligned &&
        remoteScopeExcluded &&
        perMilestoneExecutionPlansCreated &&
        competitorCoverageMapped &&
        productionWiringChecklistCreated;
  }

  List<String> get blockers {
    final result = <String>[];
    if (!localTerminalPlanDocumented) {
      result.add('Local terminal feature plan is missing.');
    }
    if (!roadmapLocalWorkspaceAligned) {
      result.add('Roadmap is not aligned to local workspace expansion.');
    }
    if (!remoteScopeExcluded) {
      result.add('SSH/remote/serial/SFTP exclusions are not documented.');
    }
    if (!perMilestoneExecutionPlansCreated) {
      result.add('Per-milestone execution plans are missing.');
    }
    if (!competitorCoverageMapped) {
      result.add('Competitor-derived feature coverage is not mapped.');
    }
    if (!productionWiringChecklistCreated) {
      result.add('Production wiring checklist is missing.');
    }
    return result;
  }

  LocalTerminalProductionMilestoneManifest toMilestoneManifest({
    required bool documentationReviewed,
    required bool analysisPassed,
    List<String> notes = const [],
  }) {
    return LocalTerminalProductionMilestoneManifest(
      milestone: LocalTerminalProductionMilestone.p0Documentation,
      wiringReady: boundaryReady,
      testsPassed: documentationReviewed,
      analysisPassed: analysisPassed,
      blockers: blockers,
      notes: [...this.notes, ...notes],
    );
  }

  Map<String, Object?> toJson() {
    return {
      'boundaryReady': boundaryReady,
      'localTerminalPlanDocumented': localTerminalPlanDocumented,
      'roadmapLocalWorkspaceAligned': roadmapLocalWorkspaceAligned,
      'remoteScopeExcluded': remoteScopeExcluded,
      'perMilestoneExecutionPlansCreated': perMilestoneExecutionPlansCreated,
      'competitorCoverageMapped': competitorCoverageMapped,
      'productionWiringChecklistCreated': productionWiringChecklistCreated,
      'blockers': blockers,
      'notes': notes,
    };
  }
}
