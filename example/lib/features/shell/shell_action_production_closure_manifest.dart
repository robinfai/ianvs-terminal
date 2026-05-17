import 'shell_action_production_audit_snapshot.dart';

class ShellActionProductionClosureManifest {
  const ShellActionProductionClosureManifest({
    required this.snapshot,
    required this.testsPassed,
    required this.analysisPassed,
    this.notes = const [],
  });

  final ShellActionProductionAuditSnapshot snapshot;
  final bool testsPassed;
  final bool analysisPassed;
  final List<String> notes;

  bool get wiringReady => snapshot.canCloseP1ActionWiring;

  bool get canClose {
    return wiringReady && testsPassed && analysisPassed;
  }

  List<String> get blockers {
    final result = <String>[];
    if (!snapshot.wiringReport.ready ||
        snapshot.wiringReport.hasBlockingItems) {
      result.add('Production action wiring is not ready.');
    }
    if (snapshot.hasFailedDispatches) {
      result.add('Recent production action dispatch failed.');
    }
    if (!testsPassed) {
      result.add('Required action wiring tests have not passed.');
    }
    if (!analysisPassed) {
      result.add('Static analysis has not passed.');
    }
    return result;
  }

  Map<String, Object?> toJson() {
    return {
      'canClose': canClose,
      'wiringReady': wiringReady,
      'testsPassed': testsPassed,
      'analysisPassed': analysisPassed,
      'blockers': blockers,
      'notes': notes,
      'snapshot': snapshot.toJson(),
    };
  }
}
