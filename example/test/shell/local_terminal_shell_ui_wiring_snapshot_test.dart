import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/local_terminal_shell_ui_wiring_snapshot.dart';

void main() {
  test('pending snapshot exposes blocked counts and summary', () {
    final snapshot = LocalTerminalShellUiWiringSnapshot.pending(
      capturedAt: DateTime.utc(2026, 5, 16),
    );

    expect(snapshot.canCloseObjective, isFalse);
    expect(snapshot.blockedMilestoneCount, greaterThan(0));
    expect(snapshot.blockedBacklogItemCount, greaterThan(0));
    expect(
      snapshot.blockedBacklogItemCount,
      snapshot.facade.requiredBacklogBlockerCount,
    );
    expect(snapshot.blockedVerificationGateCount, greaterThan(0));
    expect(snapshot.summaryText, contains('blocked'));
  });

  test('pending snapshot exports json payload for UI diagnostics', () {
    final snapshot = LocalTerminalShellUiWiringSnapshot.pending(
      capturedAt: DateTime.utc(2026, 5, 16),
    );

    final json = snapshot.toJson();

    expect(json['capturedAt'], '2026-05-16T00:00:00.000Z');
    expect(json['canCloseObjective'], isFalse);
    expect(
      json['blockedBacklogItemCount'],
      snapshot.facade.requiredBacklogBlockerCount,
    );
    expect(json['facade'], isA<Map<String, Object?>>());
  });

  test('verified snapshot closes objective from latest passed records', () {
    final snapshot = LocalTerminalShellUiWiringSnapshot.verified(
      capturedAt: DateTime.utc(2026, 5, 16),
    );

    expect(snapshot.canCloseObjective, isTrue);
    expect(snapshot.blockedMilestoneCount, 0);
    expect(snapshot.blockedBacklogItemCount, 0);
    expect(snapshot.blockedVerificationGateCount, 0);
    expect(snapshot.summaryText, contains('can close'));
  });
}
