import '../layout/terminal_layout_production_callbacks.dart';
import '../policies/local_terminal_policy_production_callbacks.dart';
import '../productivity/shell_productivity_production_callbacks.dart';
import '../visual/local_terminal_visual_production_callbacks.dart';
import 'local_terminal_production_wiring_manifest.dart';

class LocalTerminalDomainWiringSummary {
  const LocalTerminalDomainWiringSummary({
    required this.milestone,
    required this.ready,
    required this.registeredOperationNames,
    required this.missingOperationNames,
  });

  factory LocalTerminalDomainWiringSummary.fromLayout(
    TerminalLayoutProductionWiring wiring,
  ) {
    return LocalTerminalDomainWiringSummary(
      milestone: LocalTerminalProductionMilestone.p2Layout,
      ready: wiring.isReady,
      registeredOperationNames: wiring.registeredOperations
          .map((operation) => operation.name)
          .toList(growable: false),
      missingOperationNames: wiring.missingRequiredOperations
          .map((operation) => operation.name)
          .toList(growable: false),
    );
  }

  factory LocalTerminalDomainWiringSummary.fromProductivity(
    ShellProductivityProductionWiring wiring,
  ) {
    return LocalTerminalDomainWiringSummary(
      milestone: LocalTerminalProductionMilestone.p3Productivity,
      ready: wiring.isReady,
      registeredOperationNames: wiring.registeredOperations
          .map((operation) => operation.name)
          .toList(growable: false),
      missingOperationNames: wiring.missingRequiredOperations
          .map((operation) => operation.name)
          .toList(growable: false),
    );
  }

  factory LocalTerminalDomainWiringSummary.fromPolicy(
    LocalTerminalPolicyProductionWiring wiring,
  ) {
    return LocalTerminalDomainWiringSummary(
      milestone: LocalTerminalProductionMilestone.p4Policy,
      ready: wiring.isReady,
      registeredOperationNames: wiring.registeredOperations
          .map((operation) => operation.name)
          .toList(growable: false),
      missingOperationNames: wiring.missingRequiredOperations
          .map((operation) => operation.name)
          .toList(growable: false),
    );
  }

  factory LocalTerminalDomainWiringSummary.fromVisual(
    LocalTerminalVisualProductionWiring wiring,
  ) {
    return LocalTerminalDomainWiringSummary(
      milestone: LocalTerminalProductionMilestone.p5Visual,
      ready: wiring.isReady,
      registeredOperationNames: wiring.registeredOperations
          .map((operation) => operation.name)
          .toList(growable: false),
      missingOperationNames: wiring.missingRequiredOperations
          .map((operation) => operation.name)
          .toList(growable: false),
    );
  }

  final LocalTerminalProductionMilestone milestone;
  final bool ready;
  final List<String> registeredOperationNames;
  final List<String> missingOperationNames;

  bool get hasMissingOperations => missingOperationNames.isNotEmpty;

  LocalTerminalProductionMilestoneManifest toMilestoneManifest({
    required bool testsPassed,
    required bool analysisPassed,
    List<String> notes = const [],
  }) {
    return LocalTerminalProductionMilestoneManifest(
      milestone: milestone,
      wiringReady: ready,
      testsPassed: testsPassed,
      analysisPassed: analysisPassed,
      blockers: [
        for (final operationName in missingOperationNames)
          'Missing production callback for $operationName.',
      ],
      notes: [
        ...notes,
        'Registered operations: ${registeredOperationNames.join(', ')}',
      ],
    );
  }

  Map<String, Object?> toJson() {
    return {
      'milestone': milestone.name,
      'ready': ready,
      'registeredOperationNames': registeredOperationNames,
      'missingOperationNames': missingOperationNames,
    };
  }
}
