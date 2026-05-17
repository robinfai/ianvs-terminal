import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/local_terminal_completion_evidence_report.dart';
import 'package:app/features/shell/local_terminal_current_completion_state.dart';
import 'package:app/features/shell/local_terminal_completion_diagnostics_presentation.dart';
import 'package:app/features/shell/local_terminal_real_wiring_backlog_evidence.dart';
import 'package:app/features/shell/local_terminal_shell_ui_wiring_facade.dart';
import 'package:app/features/shell/local_terminal_shell_ui_wiring_snapshot.dart';
import 'package:app/features/shell/local_terminal_verification_evidence.dart';

void main() {
  test('builds visible blocked presentation from pending snapshot', () {
    final snapshot = LocalTerminalShellUiWiringSnapshot.pending(
      capturedAt: DateTime.utc(2026, 5, 16),
    );

    final presentation =
        LocalTerminalCompletionDiagnosticsPresentation.fromSnapshot(
          snapshot: snapshot,
          mode: LocalTerminalCompletionDiagnosticsPresentationMode.modalSheet,
        );

    expect(presentation.visible, isTrue);
    expect(presentation.title, contains('blocked'));
    expect(
      presentation.mode,
      LocalTerminalCompletionDiagnosticsPresentationMode.modalSheet,
    );
    expect(presentation.totalBlockedCount, greaterThan(0));
  });

  test('exports presentation state as json', () {
    final snapshot = LocalTerminalShellUiWiringSnapshot.pending(
      capturedAt: DateTime.utc(2026, 5, 16),
    );

    final presentation =
        LocalTerminalCompletionDiagnosticsPresentation.fromSnapshot(
          snapshot: snapshot,
        );

    final json = presentation.toJson();

    expect(json['mode'], 'inlinePanel');
    expect(json['visible'], isTrue);
    expect(json['totalBlockedCount'], presentation.totalBlockedCount);
  });

  test('counts missing required backlog items as presentation blockers', () {
    final snapshot = _snapshotWithMissingRequiredBacklog();

    final presentation =
        LocalTerminalCompletionDiagnosticsPresentation.fromSnapshot(
          snapshot: snapshot,
        );
    final json = presentation.toJson();

    expect(presentation.visible, isTrue);
    expect(presentation.blockedBacklogItemCount, 4);
    expect(json['blockedBacklogItemCount'], 4);
    expect(
      presentation.totalBlockedCount,
      presentation.blockedMilestoneCount +
          presentation.blockedVerificationGateCount +
          4,
    );
  });

  test('counts missing verification gates as presentation blockers', () {
    final snapshot = _snapshotWithMissingVerificationEvidence();

    final presentation =
        LocalTerminalCompletionDiagnosticsPresentation.fromSnapshot(
          snapshot: snapshot,
        );

    expect(
      presentation.blockedVerificationGateCount,
      LocalTerminalVerificationEvidence.defaultRequiredGates.length,
    );
    expect(
      presentation.totalBlockedCount,
      presentation.blockedMilestoneCount +
          presentation.blockedBacklogItemCount +
          LocalTerminalVerificationEvidence.defaultRequiredGates.length,
    );
  });
}

LocalTerminalShellUiWiringSnapshot _snapshotWithMissingRequiredBacklog() {
  final capturedAt = DateTime.utc(2026, 5, 16);
  final state = LocalTerminalCurrentCompletionState.pending(
    capturedAt: capturedAt,
  );

  return LocalTerminalShellUiWiringSnapshot(
    capturedAt: capturedAt,
    facade: LocalTerminalShellUiWiringFacade(
      bundle: state.bundle,
      backlogEvidence: const _MissingRequiredBacklogEvidence(),
      verificationEvidence: state.verificationEvidence,
    ),
  );
}

LocalTerminalShellUiWiringSnapshot _snapshotWithMissingVerificationEvidence() {
  final capturedAt = DateTime.utc(2026, 5, 16);
  final state = LocalTerminalCurrentCompletionState.pending(
    capturedAt: capturedAt,
  );

  return LocalTerminalShellUiWiringSnapshot(
    capturedAt: capturedAt,
    facade: LocalTerminalShellUiWiringFacade(
      bundle: state.bundle,
      backlogEvidence: state.backlogEvidence,
      verificationEvidence: const LocalTerminalVerificationEvidence(items: []),
    ),
  );
}

class _MissingRequiredBacklogEvidence
    extends LocalTerminalRealWiringBacklogEvidence {
  const _MissingRequiredBacklogEvidence() : super();

  @override
  List<LocalTerminalCompletionBacklogItem> toBacklogItems() {
    return const [
      LocalTerminalCompletionBacklogItem(
        taskId: 'T-164',
        title: 'Shell action production wiring',
        status: LocalTerminalCompletionBacklogStatus.verified,
      ),
      LocalTerminalCompletionBacklogItem(
        taskId: 'T-169',
        title: 'Verification and closure',
        status: LocalTerminalCompletionBacklogStatus.verified,
      ),
    ];
  }
}
