import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/local_terminal_completion_diagnostics_presentation.dart';
import 'package:app/features/shell/local_terminal_completion_diagnostics_presentation_resolver.dart';
import 'package:app/features/shell/local_terminal_shell_ui_wiring_snapshot.dart';

void main() {
  test('uses preferred presentation mode for blocked snapshots', () {
    final snapshot = LocalTerminalShellUiWiringSnapshot.pending(
      capturedAt: DateTime.utc(2026, 5, 16),
    );
    const resolver = LocalTerminalCompletionDiagnosticsPresentationResolver(
      preferredMode:
          LocalTerminalCompletionDiagnosticsPresentationMode.commandMenuSection,
    );

    final presentation = resolver.resolve(snapshot);

    expect(presentation.visible, isTrue);
    expect(
      presentation.mode,
      LocalTerminalCompletionDiagnosticsPresentationMode.commandMenuSection,
    );
    expect(presentation.totalBlockedCount, greaterThan(0));
  });

  test('can keep completed presentation visible when requested', () {
    final snapshot = LocalTerminalShellUiWiringSnapshot.pending(
      capturedAt: DateTime.utc(2026, 5, 16),
    );
    const resolver = LocalTerminalCompletionDiagnosticsPresentationResolver(
      hideWhenComplete: false,
    );

    final presentation = resolver.resolve(snapshot);

    expect(presentation.visible, isTrue);
  });
}
