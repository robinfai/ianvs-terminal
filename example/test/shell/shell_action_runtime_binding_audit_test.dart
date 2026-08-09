import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_action_runtime_binding_audit.dart';
import 'package:app/features/shell/shell_action_runtime_bindings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports missing required production bindings', () {
    final bindings = ShellActionRuntimeBindings(
      bindings: {
        TerminalActionId.newTab: (_) =>
            const ShellActionBindingResult.completed(),
      },
    );

    final audit = ShellActionRuntimeBindingAudit.fromBindings(
      bindings: bindings,
      requiredActions: const [
        TerminalActionId.newTab,
        TerminalActionId.closeActiveTab,
      ],
    );

    expect(audit.isComplete, isFalse);
    expect(audit.missingRequiredActions, {TerminalActionId.closeActiveTab});
    expect(
      audit.missingRequiredItems.single.severity,
      ShellActionRuntimeBindingAuditSeverity.required,
    );
  });

  test('reports unplanned registered bindings', () {
    final bindings = ShellActionRuntimeBindings(
      bindings: {
        TerminalActionId.newTab: (_) =>
            const ShellActionBindingResult.completed(),
        TerminalActionId.clearBuffer: (_) =>
            const ShellActionBindingResult.completed(),
      },
    );

    final audit = ShellActionRuntimeBindingAudit.fromBindings(
      bindings: bindings,
      requiredActions: const [TerminalActionId.newTab],
    );

    expect(audit.unplannedRegisteredActions, {TerminalActionId.clearBuffer});
    expect(
      audit.unplannedRegisteredItems.single.severity,
      ShellActionRuntimeBindingAuditSeverity.unplanned,
    );
  });
}
