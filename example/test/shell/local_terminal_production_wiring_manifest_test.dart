import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/local_terminal_production_wiring_manifest.dart';

void main() {
  test('closes only when every required milestone can close', () {
    final manifest = LocalTerminalProductionWiringManifest(
      capturedAt: DateTime.utc(2026, 5, 16),
      milestones: [
        for (final milestone
            in LocalTerminalProductionWiringManifest.requiredMilestones)
          LocalTerminalProductionMilestoneManifest(
            milestone: milestone,
            wiringReady: true,
            testsPassed: true,
            analysisPassed: true,
          ),
      ],
    );

    expect(manifest.canCloseAll, isTrue);
    expect(manifest.blockedMilestones, isEmpty);
    expect(manifest.toJson()['canCloseAll'], isTrue);
  });

  test('missing required milestones block closure', () {
    final manifest = LocalTerminalProductionWiringManifest(
      capturedAt: DateTime.utc(2026, 5, 16),
      milestones: const [
        LocalTerminalProductionMilestoneManifest(
          milestone: LocalTerminalProductionMilestone.p1ActionConfig,
          wiringReady: true,
          testsPassed: true,
          analysisPassed: true,
        ),
      ],
    );

    expect(manifest.canCloseAll, isFalse);
    expect(
      manifest.missingRequiredMilestones,
      contains(LocalTerminalProductionMilestone.p0Documentation),
    );
    expect(
      manifest.toJson()['missingRequiredMilestones'],
      contains('p0Documentation'),
    );
  });

  test('keeps incomplete milestone verification as a blocker', () {
    final manifest = LocalTerminalProductionWiringManifest(
      capturedAt: DateTime.utc(2026, 5, 16),
      milestones: const [
        LocalTerminalProductionMilestoneManifest(
          milestone: LocalTerminalProductionMilestone.p1ActionConfig,
          wiringReady: true,
          testsPassed: false,
          analysisPassed: false,
        ),
      ],
    );

    final milestone = manifest.milestoneFor(
      LocalTerminalProductionMilestone.p1ActionConfig,
    );

    expect(manifest.canCloseAll, isFalse);
    expect(manifest.blockedMilestones, hasLength(1));
    expect(
      milestone?.effectiveBlockers,
      contains('Required tests have not passed.'),
    );
    expect(
      milestone?.effectiveBlockers,
      contains('Static analysis has not passed.'),
    );
  });
}
