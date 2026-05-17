import 'local_terminal_production_wiring_bundle.dart';
import 'local_terminal_production_wiring_manifest.dart';

class LocalTerminalCompletionEvidenceReport {
  const LocalTerminalCompletionEvidenceReport({
    required this.bundle,
    required this.backlogItems,
  });

  static const requiredBacklogTaskIds = {
    'T-164',
    'T-165',
    'T-166',
    'T-167',
    'T-168',
    'T-169',
  };

  final LocalTerminalProductionWiringBundle bundle;
  final List<LocalTerminalCompletionBacklogItem> backlogItems;

  bool get canCloseObjective {
    return bundle.canCloseAll &&
        missingRequiredBacklogTaskIds.isEmpty &&
        backlogItems.every((item) => item.status.isClosed);
  }

  List<LocalTerminalProductionMilestoneManifest> get blockedMilestones {
    return bundle.manifest.blockedMilestones;
  }

  List<LocalTerminalProductionMilestone>
  get missingRequiredProductionMilestones {
    return bundle.manifest.missingRequiredMilestones;
  }

  int get productionMilestoneBlockerCount {
    return blockedMilestones.length +
        missingRequiredProductionMilestones.length;
  }

  List<LocalTerminalCompletionBacklogItem> get blockedBacklogItems {
    return backlogItems
        .where((item) => !item.status.isClosed)
        .toList(growable: false);
  }

  int get requiredBacklogBlockerCount {
    return blockedBacklogItems.length + missingRequiredBacklogTaskIds.length;
  }

  Set<String> get missingRequiredBacklogTaskIds {
    final taskIds = backlogItems.map((item) => item.taskId).toSet();
    return requiredBacklogTaskIds.difference(taskIds);
  }

  Map<String, Object?> toJson() {
    return {
      'canCloseObjective': canCloseObjective,
      'manifest': bundle.manifest.toJson(),
      'blockedMilestones': blockedMilestones
          .map((milestone) => milestone.milestone.name)
          .toList(growable: false),
      'missingRequiredProductionMilestones': missingRequiredProductionMilestones
          .map((milestone) => milestone.name)
          .toList(growable: false),
      'productionMilestoneBlockerCount': productionMilestoneBlockerCount,
      'backlogItems': backlogItems.map((item) => item.toJson()).toList(),
      'blockedBacklogItems': blockedBacklogItems
          .map((item) => item.taskId)
          .toList(growable: false),
      'requiredBacklogBlockerCount': requiredBacklogBlockerCount,
      'missingRequiredBacklogTaskIds': missingRequiredBacklogTaskIds.toList(
        growable: false,
      ),
    };
  }
}

class LocalTerminalCompletionBacklogItem {
  const LocalTerminalCompletionBacklogItem({
    required this.taskId,
    required this.title,
    required this.status,
    this.evidence = const [],
    this.blockers = const [],
  });

  final String taskId;
  final String title;
  final LocalTerminalCompletionBacklogStatus status;
  final List<String> evidence;
  final List<String> blockers;

  Map<String, Object?> toJson() {
    return {
      'taskId': taskId,
      'title': title,
      'status': status.name,
      'evidence': evidence,
      'blockers': blockers,
    };
  }
}

enum LocalTerminalCompletionBacklogStatus {
  pending,
  inProgress,
  blocked,
  verified,
}

extension LocalTerminalCompletionBacklogStatusX
    on LocalTerminalCompletionBacklogStatus {
  bool get isClosed {
    return this == LocalTerminalCompletionBacklogStatus.verified;
  }
}
