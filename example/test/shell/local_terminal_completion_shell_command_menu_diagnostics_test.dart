import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/local_terminal_completion_controller.dart';
import 'package:app/features/shell/local_terminal_completion_evidence_report.dart';
import 'package:app/features/shell/local_terminal_completion_menu_model.dart';
import 'package:app/features/shell/local_terminal_completion_shell_command_menu_diagnostics.dart';
import 'package:app/features/shell/local_terminal_current_completion_state.dart';

void main() {
  test(
    'adapts blocked completion entries to command menu disabled reasons',
    () {
      final model = LocalTerminalCompletionMenuModel.fromController(
        LocalTerminalCompletionController.pending(
          capturedAt: DateTime.utc(2026, 5, 16),
        ),
      );

      final diagnostics =
          LocalTerminalCompletionShellCommandMenuDiagnostics.fromMenuModel(
            model,
          );

      expect(diagnostics.hasDisabledEntries, isTrue);
      expect(diagnostics.disabledEntries, isNotEmpty);
      expect(diagnostics.disabledEntries.first.disabledReason, isNotNull);
      expect(
        diagnostics.disabledEntries.first.disabledReason?.description,
        isNotEmpty,
      );
    },
  );

  test('exports disabled completion diagnostics as json', () {
    final model = LocalTerminalCompletionMenuModel.fromController(
      LocalTerminalCompletionController.pending(
        capturedAt: DateTime.utc(2026, 5, 16),
      ),
    );

    final diagnostics =
        LocalTerminalCompletionShellCommandMenuDiagnostics.fromMenuModel(model);
    final json = diagnostics.toJson();

    expect(json['hasDisabledEntries'], isTrue);
    expect(json['entries'], isNotEmpty);
  });

  test('keeps missing required backlog disabled reasons visible', () {
    final model = LocalTerminalCompletionMenuModel.fromController(
      _controllerWithMissingRequiredBacklog(),
    );

    final diagnostics =
        LocalTerminalCompletionShellCommandMenuDiagnostics.fromMenuModel(model);
    final missingEntries = diagnostics.disabledEntries
        .where((entry) => entry.sectionTitle == 'Missing real-wiring backlog')
        .toList(growable: false);

    expect(missingEntries.map((entry) => entry.label), contains('T-165'));
    expect(missingEntries.map((entry) => entry.label), contains('T-168'));
    expect(
      missingEntries.map((entry) => entry.disabledReason?.description),
      everyElement('Required backlog task is absent from completion evidence.'),
    );
  });
}

LocalTerminalCompletionController _controllerWithMissingRequiredBacklog() {
  final state = LocalTerminalCurrentCompletionState.pending(
    capturedAt: DateTime.utc(2026, 5, 16),
  );
  final report = LocalTerminalCompletionEvidenceReport(
    bundle: state.bundle,
    backlogItems: const [
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
    ],
  );

  return LocalTerminalCompletionController(
    currentState: LocalTerminalCurrentCompletionState(
      bundle: state.bundle,
      verificationEvidence: state.verificationEvidence,
      backlogEvidence: state.backlogEvidence,
      report: report,
    ),
  );
}
