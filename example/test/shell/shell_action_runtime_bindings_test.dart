import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_action_runtime_bindings.dart';

void main() {
  test('runs a registered production binding', () async {
    final bindings = ShellActionRuntimeBindings(
      bindings: {
        TerminalActionId.newTab: (context) {
          expect(context.actionId, TerminalActionId.newTab);
          expect(context.cwd, '/tmp/project');
          return const ShellActionBindingResult.completed('created');
        },
      },
    );

    final result = await bindings.run(
      TerminalActionId.newTab,
      cwd: '/tmp/project',
    );

    expect(result.completed, isTrue);
    expect(result.message, 'created');
  });

  test('reports missing production bindings', () {
    final bindings = ShellActionRuntimeBindings.empty();

    expect(
      bindings.missingActions(const [
        TerminalActionId.newTab,
        TerminalActionId.splitRight,
      ]),
      {TerminalActionId.newTab, TerminalActionId.splitRight},
    );
  });

  test('unsupported action returns failed result', () async {
    final bindings = ShellActionRuntimeBindings.empty();

    final result = await bindings.run(TerminalActionId.closeActiveTab);

    expect(result.failed, isTrue);
    expect(result.failureCode, ShellActionBindingFailureCode.unsupported);
  });
}
