import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/local_terminal_p0_boundary_closure_manifest.dart';
import 'package:app/features/shell/local_terminal_production_wiring_manifest.dart';

void main() {
  test('converts ready P0 boundary state into a closeable manifest input', () {
    const p0 = LocalTerminalP0BoundaryClosureManifest(
      localTerminalPlanDocumented: true,
      roadmapTerminalLayoutAligned: true,
      remoteScopeExcluded: true,
      perMilestoneExecutionPlansCreated: true,
      competitorCoverageMapped: true,
      productionWiringChecklistCreated: true,
    );

    final manifest = p0.toMilestoneManifest(
      documentationReviewed: true,
      analysisPassed: true,
    );

    expect(p0.boundaryReady, isTrue);
    expect(
      manifest.milestone,
      LocalTerminalProductionMilestone.p0Documentation,
    );
    expect(manifest.canClose, isTrue);
  });

  test('keeps missing P0 boundary artifacts as blockers', () {
    const p0 = LocalTerminalP0BoundaryClosureManifest(
      localTerminalPlanDocumented: false,
      roadmapTerminalLayoutAligned: true,
      remoteScopeExcluded: false,
      perMilestoneExecutionPlansCreated: true,
      competitorCoverageMapped: true,
      productionWiringChecklistCreated: true,
    );

    final manifest = p0.toMilestoneManifest(
      documentationReviewed: true,
      analysisPassed: true,
    );

    expect(p0.boundaryReady, isFalse);
    expect(manifest.canClose, isFalse);
    expect(
      manifest.effectiveBlockers,
      contains('Local terminal feature plan is missing.'),
    );
    expect(
      manifest.effectiveBlockers,
      contains('SSH/remote/serial/SFTP exclusions are not documented.'),
    );
  });
}
