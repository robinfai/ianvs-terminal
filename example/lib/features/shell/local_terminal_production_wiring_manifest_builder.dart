import 'local_terminal_domain_wiring_summary.dart';
import 'local_terminal_p0_boundary_closure_manifest.dart';
import 'local_terminal_production_wiring_manifest.dart';
import 'shell_action_production_closure_manifest.dart';

class LocalTerminalProductionWiringManifestBuilder {
  const LocalTerminalProductionWiringManifestBuilder({
    required this.capturedAt,
    required this.actionClosureManifest,
    this.p0BoundaryManifest,
    this.p0Verification = LocalTerminalMilestoneVerificationStatus.notVerified,
    this.layoutSummary,
    this.layoutVerification =
        LocalTerminalMilestoneVerificationStatus.notVerified,
    this.productivitySummary,
    this.productivityVerification =
        LocalTerminalMilestoneVerificationStatus.notVerified,
    this.policySummary,
    this.policyVerification =
        LocalTerminalMilestoneVerificationStatus.notVerified,
    this.visualSummary,
    this.visualVerification =
        LocalTerminalMilestoneVerificationStatus.notVerified,
  });

  final DateTime capturedAt;
  final ShellActionProductionClosureManifest actionClosureManifest;
  final LocalTerminalP0BoundaryClosureManifest? p0BoundaryManifest;
  final LocalTerminalMilestoneVerificationStatus p0Verification;
  final LocalTerminalDomainWiringSummary? layoutSummary;
  final LocalTerminalMilestoneVerificationStatus layoutVerification;
  final LocalTerminalDomainWiringSummary? productivitySummary;
  final LocalTerminalMilestoneVerificationStatus productivityVerification;
  final LocalTerminalDomainWiringSummary? policySummary;
  final LocalTerminalMilestoneVerificationStatus policyVerification;
  final LocalTerminalDomainWiringSummary? visualSummary;
  final LocalTerminalMilestoneVerificationStatus visualVerification;

  LocalTerminalProductionWiringManifest build() {
    return LocalTerminalProductionWiringManifest(
      capturedAt: capturedAt,
      milestones: [
        _p0MilestoneManifest(),
        _actionMilestoneManifest(),
        _domainMilestoneManifest(
          milestone: LocalTerminalProductionMilestone.p2Layout,
          summary: layoutSummary,
          verification: layoutVerification,
        ),
        _domainMilestoneManifest(
          milestone: LocalTerminalProductionMilestone.p3Productivity,
          summary: productivitySummary,
          verification: productivityVerification,
        ),
        _domainMilestoneManifest(
          milestone: LocalTerminalProductionMilestone.p4Policy,
          summary: policySummary,
          verification: policyVerification,
        ),
        _domainMilestoneManifest(
          milestone: LocalTerminalProductionMilestone.p5Visual,
          summary: visualSummary,
          verification: visualVerification,
        ),
      ],
    );
  }

  LocalTerminalProductionMilestoneManifest _p0MilestoneManifest() {
    final manifest = p0BoundaryManifest;
    if (manifest == null) {
      return LocalTerminalProductionMilestoneManifest(
        milestone: LocalTerminalProductionMilestone.p0Documentation,
        wiringReady: false,
        testsPassed: p0Verification.testsPassed,
        analysisPassed: p0Verification.analysisPassed,
        blockers: const ['P0 boundary closure manifest is missing.'],
        notes: p0Verification.notes,
      );
    }

    return manifest.toMilestoneManifest(
      documentationReviewed: p0Verification.testsPassed,
      analysisPassed: p0Verification.analysisPassed,
      notes: p0Verification.notes,
    );
  }

  LocalTerminalProductionMilestoneManifest _actionMilestoneManifest() {
    return LocalTerminalProductionMilestoneManifest(
      milestone: LocalTerminalProductionMilestone.p1ActionConfig,
      wiringReady: actionClosureManifest.wiringReady,
      testsPassed: actionClosureManifest.testsPassed,
      analysisPassed: actionClosureManifest.analysisPassed,
      blockers: [
        for (final item
            in actionClosureManifest.snapshot.wiringReport.blockingItems)
          item.description,
      ],
      notes: actionClosureManifest.notes,
    );
  }

  LocalTerminalProductionMilestoneManifest _domainMilestoneManifest({
    required LocalTerminalProductionMilestone milestone,
    required LocalTerminalDomainWiringSummary? summary,
    required LocalTerminalMilestoneVerificationStatus verification,
  }) {
    if (summary == null) {
      return LocalTerminalProductionMilestoneManifest(
        milestone: milestone,
        wiringReady: false,
        testsPassed: verification.testsPassed,
        analysisPassed: verification.analysisPassed,
        blockers: const ['Production wiring summary is missing.'],
        notes: verification.notes,
      );
    }

    return summary.toMilestoneManifest(
      testsPassed: verification.testsPassed,
      analysisPassed: verification.analysisPassed,
      notes: verification.notes,
    );
  }
}

class LocalTerminalMilestoneVerificationStatus {
  const LocalTerminalMilestoneVerificationStatus({
    required this.testsPassed,
    required this.analysisPassed,
    this.notes = const [],
  });

  static const notVerified = LocalTerminalMilestoneVerificationStatus(
    testsPassed: false,
    analysisPassed: false,
  );

  static const verified = LocalTerminalMilestoneVerificationStatus(
    testsPassed: true,
    analysisPassed: true,
  );

  final bool testsPassed;
  final bool analysisPassed;
  final List<String> notes;
}
