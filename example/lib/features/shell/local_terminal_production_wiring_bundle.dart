import '../layout/terminal_layout_production_callbacks.dart';
import '../policies/local_terminal_policy_production_callbacks.dart';
import '../productivity/shell_productivity_production_callbacks.dart';
import '../visual/local_terminal_visual_production_callbacks.dart';
import 'local_terminal_action_domain_router.dart';
import 'local_terminal_domain_wiring_summary.dart';
import 'local_terminal_p0_boundary_closure_manifest.dart';
import 'local_terminal_production_wiring_manifest.dart';
import 'local_terminal_production_wiring_manifest_builder.dart';
import 'shell_action_production_action_set.dart';
import 'shell_action_production_audit_snapshot.dart';
import 'shell_action_production_callbacks.dart';
import 'shell_action_production_closure_manifest.dart';
import 'shell_action_production_wiring_report.dart';
import 'shell_action_production_wiring_state.dart';
import 'shell_action_runtime_bindings.dart';

class LocalTerminalProductionWiringBundle {
  const LocalTerminalProductionWiringBundle._({
    required this.actionCallbacks,
    required this.actionWiringState,
    required this.actionClosureManifest,
    required this.layoutWiring,
    required this.productivityWiring,
    required this.policyWiring,
    required this.visualWiring,
    required this.layoutSummary,
    required this.productivitySummary,
    required this.policySummary,
    required this.visualSummary,
    required this.manifest,
  });

  factory LocalTerminalProductionWiringBundle.fromDomainCallbacks({
    required DateTime capturedAt,
    required LocalTerminalP0BoundaryClosureManifest p0BoundaryManifest,
    LocalTerminalMilestoneVerificationStatus p0Verification =
        LocalTerminalMilestoneVerificationStatus.notVerified,
    ShellActionProductionActionSet? actionSet,
    LocalTerminalMilestoneVerificationStatus actionVerification =
        LocalTerminalMilestoneVerificationStatus.notVerified,
    ShellActionBinding? toggleCommandPalette,
    TerminalLayoutProductionCallbacks layoutCallbacks =
        const TerminalLayoutProductionCallbacks(),
    Iterable<TerminalLayoutProductionOperation>? layoutRequiredOperations,
    LocalTerminalMilestoneVerificationStatus layoutVerification =
        LocalTerminalMilestoneVerificationStatus.notVerified,
    ShellProductivityProductionCallbacks productivityCallbacks =
        const ShellProductivityProductionCallbacks(),
    Iterable<ShellProductivityProductionOperation>?
    productivityRequiredOperations,
    LocalTerminalMilestoneVerificationStatus productivityVerification =
        LocalTerminalMilestoneVerificationStatus.notVerified,
    LocalTerminalPolicyProductionCallbacks policyCallbacks =
        const LocalTerminalPolicyProductionCallbacks(),
    Iterable<LocalTerminalPolicyProductionOperation>? policyRequiredOperations,
    LocalTerminalMilestoneVerificationStatus policyVerification =
        LocalTerminalMilestoneVerificationStatus.notVerified,
    LocalTerminalVisualProductionCallbacks visualCallbacks =
        const LocalTerminalVisualProductionCallbacks(),
    Iterable<LocalTerminalVisualProductionOperation>? visualRequiredOperations,
    LocalTerminalMilestoneVerificationStatus visualVerification =
        LocalTerminalMilestoneVerificationStatus.notVerified,
  }) {
    final layoutWiring = TerminalLayoutProductionWiring(
      callbacks: layoutCallbacks,
      requiredOperations: layoutRequiredOperations,
    );
    final productivityWiring = ShellProductivityProductionWiring(
      callbacks: productivityCallbacks,
      requiredOperations: productivityRequiredOperations,
    );
    final policyWiring = LocalTerminalPolicyProductionWiring(
      callbacks: policyCallbacks,
      requiredOperations: policyRequiredOperations,
    );
    final visualWiring = LocalTerminalVisualProductionWiring(
      callbacks: visualCallbacks,
      requiredOperations: visualRequiredOperations,
    );

    final actionCallbacks = LocalTerminalActionDomainRouter(
      layout: layoutWiring,
      productivity: productivityWiring,
      policy: policyWiring,
      visual: visualWiring,
      toggleCommandPalette: toggleCommandPalette,
    ).toActionCallbacks();
    final actionWiringState = ShellActionProductionWiringState.fromCallbacks(
      callbacks: actionCallbacks,
      actionSet: actionSet,
    );
    final actionClosureManifest = ShellActionProductionClosureManifest(
      snapshot: ShellActionProductionAuditSnapshot(
        capturedAt: capturedAt,
        wiringReport: ShellActionProductionWiringReport.fromState(
          actionWiringState,
        ),
      ),
      testsPassed: actionVerification.testsPassed,
      analysisPassed: actionVerification.analysisPassed,
      notes: actionVerification.notes,
    );

    final layoutSummary = LocalTerminalDomainWiringSummary.fromLayout(
      layoutWiring,
    );
    final productivitySummary =
        LocalTerminalDomainWiringSummary.fromProductivity(productivityWiring);
    final policySummary = LocalTerminalDomainWiringSummary.fromPolicy(
      policyWiring,
    );
    final visualSummary = LocalTerminalDomainWiringSummary.fromVisual(
      visualWiring,
    );

    final manifest = LocalTerminalProductionWiringManifestBuilder(
      capturedAt: capturedAt,
      p0BoundaryManifest: p0BoundaryManifest,
      p0Verification: p0Verification,
      actionClosureManifest: actionClosureManifest,
      layoutSummary: layoutSummary,
      layoutVerification: layoutVerification,
      productivitySummary: productivitySummary,
      productivityVerification: productivityVerification,
      policySummary: policySummary,
      policyVerification: policyVerification,
      visualSummary: visualSummary,
      visualVerification: visualVerification,
    ).build();

    return LocalTerminalProductionWiringBundle._(
      actionCallbacks: actionCallbacks,
      actionWiringState: actionWiringState,
      actionClosureManifest: actionClosureManifest,
      layoutWiring: layoutWiring,
      productivityWiring: productivityWiring,
      policyWiring: policyWiring,
      visualWiring: visualWiring,
      layoutSummary: layoutSummary,
      productivitySummary: productivitySummary,
      policySummary: policySummary,
      visualSummary: visualSummary,
      manifest: manifest,
    );
  }

  final ShellActionProductionCallbacks actionCallbacks;
  final ShellActionProductionWiringState actionWiringState;
  final ShellActionProductionClosureManifest actionClosureManifest;
  final TerminalLayoutProductionWiring layoutWiring;
  final ShellProductivityProductionWiring productivityWiring;
  final LocalTerminalPolicyProductionWiring policyWiring;
  final LocalTerminalVisualProductionWiring visualWiring;
  final LocalTerminalDomainWiringSummary layoutSummary;
  final LocalTerminalDomainWiringSummary productivitySummary;
  final LocalTerminalDomainWiringSummary policySummary;
  final LocalTerminalDomainWiringSummary visualSummary;
  final LocalTerminalProductionWiringManifest manifest;

  bool get canCloseAll => manifest.canCloseAll;
}
