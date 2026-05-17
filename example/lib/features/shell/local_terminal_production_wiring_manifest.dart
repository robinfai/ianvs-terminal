class LocalTerminalProductionWiringManifest {
  const LocalTerminalProductionWiringManifest({
    required this.capturedAt,
    required this.milestones,
  });

  final DateTime capturedAt;
  final List<LocalTerminalProductionMilestoneManifest> milestones;

  static const requiredMilestones = [
    LocalTerminalProductionMilestone.p0Documentation,
    LocalTerminalProductionMilestone.p1ActionConfig,
    LocalTerminalProductionMilestone.p2Workspace,
    LocalTerminalProductionMilestone.p3Productivity,
    LocalTerminalProductionMilestone.p4Policy,
    LocalTerminalProductionMilestone.p5Visual,
  ];

  bool get canCloseAll {
    return missingRequiredMilestones.isEmpty &&
        milestones.every((milestone) => milestone.canClose);
  }

  List<LocalTerminalProductionMilestoneManifest> get blockedMilestones {
    return milestones
        .where((milestone) => !milestone.canClose)
        .toList(growable: false);
  }

  List<LocalTerminalProductionMilestone> get missingRequiredMilestones {
    return requiredMilestones
        .where((milestone) => milestoneFor(milestone) == null)
        .toList(growable: false);
  }

  LocalTerminalProductionMilestoneManifest? milestoneFor(
    LocalTerminalProductionMilestone milestone,
  ) {
    for (final entry in milestones) {
      if (entry.milestone == milestone) {
        return entry;
      }
    }
    return null;
  }

  Map<String, Object?> toJson() {
    return {
      'capturedAt': capturedAt.toIso8601String(),
      'canCloseAll': canCloseAll,
      'milestones': milestones.map((milestone) => milestone.toJson()).toList(),
      'blockedMilestones': blockedMilestones
          .map((milestone) => milestone.milestone.name)
          .toList(growable: false),
      'missingRequiredMilestones': missingRequiredMilestones
          .map((milestone) => milestone.name)
          .toList(growable: false),
    };
  }
}

class LocalTerminalProductionMilestoneManifest {
  const LocalTerminalProductionMilestoneManifest({
    required this.milestone,
    required this.wiringReady,
    required this.testsPassed,
    required this.analysisPassed,
    this.blockers = const [],
    this.notes = const [],
  });

  final LocalTerminalProductionMilestone milestone;
  final bool wiringReady;
  final bool testsPassed;
  final bool analysisPassed;
  final List<String> blockers;
  final List<String> notes;

  bool get canClose {
    return wiringReady && testsPassed && analysisPassed && blockers.isEmpty;
  }

  List<String> get effectiveBlockers {
    final result = <String>[...blockers];
    if (!wiringReady) {
      result.add('Production wiring is not ready.');
    }
    if (!testsPassed) {
      result.add('Required tests have not passed.');
    }
    if (!analysisPassed) {
      result.add('Static analysis has not passed.');
    }
    return result;
  }

  Map<String, Object?> toJson() {
    return {
      'milestone': milestone.name,
      'wiringReady': wiringReady,
      'testsPassed': testsPassed,
      'analysisPassed': analysisPassed,
      'canClose': canClose,
      'blockers': effectiveBlockers,
      'notes': notes,
    };
  }
}

enum LocalTerminalProductionMilestone {
  p0Documentation,
  p1ActionConfig,
  p2Workspace,
  p3Productivity,
  p4Policy,
  p5Visual,
}
