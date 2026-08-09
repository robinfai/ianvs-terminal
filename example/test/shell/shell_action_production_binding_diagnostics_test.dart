import 'package:app/features/shell/shell_action_production_action_set.dart';
import 'package:app/features/shell/shell_action_production_binding_builder.dart';
import 'package:app/features/shell/shell_action_production_binding_diagnostics.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_action_runtime_bindings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports blocking diagnostics for unknown and missing bindings', () {
    final result = ShellActionProductionBindingBuilder(
      actionSet: const ShellActionProductionActionSet(
        requiredActionNames: {'newTab', 'notRegisteredYet'},
      ),
      bindingsByName: {
        'unknownBinding': (_) => const ShellActionBindingResult.completed(),
      },
    ).build();

    final diagnostics = ShellActionProductionBindingDiagnostics.fromBuildResult(
      result,
    );

    expect(diagnostics.canCloseProductionWiring, isFalse);
    expect(diagnostics.hasBlockingIssues, isTrue);
    expect(
      diagnostics.items.map((item) => item.kind),
      containsAll(const [
        ShellActionProductionBindingDiagnosticKind.unknownRequiredActionName,
        ShellActionProductionBindingDiagnosticKind.unknownBindingName,
        ShellActionProductionBindingDiagnosticKind.missingRequiredBinding,
      ]),
    );
  });

  test('reports unplanned bindings as advisory diagnostics', () {
    final result = ShellActionProductionBindingBuilder(
      actionSet: const ShellActionProductionActionSet(
        requiredActionNames: {'newTab'},
      ),
      bindingsByName: {
        'newTab': (_) => const ShellActionBindingResult.completed(),
        'closeTab': (_) => const ShellActionBindingResult.completed(),
      },
    ).build();

    final diagnostics = ShellActionProductionBindingDiagnostics.fromBuildResult(
      result,
    );
    final unplannedItem = diagnostics.items.singleWhere(
      (item) =>
          item.kind ==
          ShellActionProductionBindingDiagnosticKind.unplannedBinding,
    );

    expect(unplannedItem.actionId, TerminalActionId.closeActiveTab);
    expect(
      unplannedItem.severity,
      ShellActionProductionBindingDiagnosticSeverity.advisory,
    );
  });
}
