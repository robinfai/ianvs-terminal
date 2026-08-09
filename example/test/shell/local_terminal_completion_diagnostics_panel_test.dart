import 'package:app/features/shell/local_terminal_completion_diagnostics_panel.dart';
import 'package:app/features/shell/local_terminal_completion_evidence_report.dart';
import 'package:app/features/shell/local_terminal_current_completion_state.dart';
import 'package:app/features/shell/local_terminal_real_wiring_backlog_evidence.dart';
import 'package:app/features/shell/local_terminal_shell_ui_wiring_facade.dart';
import 'package:app/features/shell/local_terminal_shell_ui_wiring_snapshot.dart';
import 'package:app/features/shell/local_terminal_verification_evidence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders blocked completion diagnostics', (tester) async {
    final snapshot = LocalTerminalShellUiWiringSnapshot.pending(
      capturedAt: DateTime.utc(2026, 5, 16),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalTerminalCompletionDiagnosticsPanel(
            snapshot: snapshot,
            maxItemsPerSection: 2,
          ),
        ),
      ),
    );

    expect(find.text('Local terminal objective is blocked'), findsOneWidget);
    expect(find.text('Milestones: 6'), findsOneWidget);
    expect(find.text('Backlog: 6'), findsOneWidget);
    expect(find.text('Verification: 10'), findsOneWidget);
    expect(find.text('Blocked milestones'), findsOneWidget);
  });

  testWidgets('renders missing required backlog blockers', (tester) async {
    final snapshot = _snapshotWithMissingRequiredBacklog();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalTerminalCompletionDiagnosticsPanel(
            snapshot: snapshot,
            maxItemsPerSection: 6,
          ),
        ),
      ),
    );

    expect(find.text('Backlog: 4'), findsOneWidget);
    expect(find.text('Missing real-wiring backlog'), findsOneWidget);
    expect(find.text('T-165'), findsOneWidget);
    expect(find.text('T-168'), findsOneWidget);
  });

  testWidgets('renders missing verification gate blockers', (tester) async {
    final snapshot = _snapshotWithMissingVerificationEvidence();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalTerminalCompletionDiagnosticsPanel(
            snapshot: snapshot,
            maxItemsPerSection: 12,
          ),
        ),
      ),
    );

    expect(find.text('Verification: 10'), findsOneWidget);
    expect(find.text('Missing verification gates'), findsOneWidget);
    expect(
      find.text(LocalTerminalVerificationGate.integrationTests.name),
      findsOneWidget,
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
