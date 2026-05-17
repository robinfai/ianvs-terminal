import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/productivity/shell_productivity_production_callbacks.dart';
import 'package:app/features/shell/local_terminal_action_domain_router.dart';
import 'package:app/features/shell/shell_action_production_action_set.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/workspace/local_workspace_production_callbacks.dart';

void main() {
  test('routes shell actions to registered domain callbacks', () async {
    final workspace = LocalWorkspaceProductionWiring(
      requiredOperations: const [LocalWorkspaceProductionOperation.newTab],
      callbacks: LocalWorkspaceProductionCallbacks(
        newTab: (context) {
          expect(context.cwd, '/tmp/project');
          return const LocalWorkspaceBindingResult.completed('created');
        },
      ),
    );
    final productivity = ShellProductivityProductionWiring(
      requiredOperations: const [
        ShellProductivityProductionOperation.searchScrollback,
      ],
      callbacks: ShellProductivityProductionCallbacks(
        searchScrollback: (context) {
          expect(context.query, 'needle');
          return const ShellProductivityBindingResult.completed('searched');
        },
      ),
    );

    final callbacks = LocalTerminalActionDomainRouter(
      workspace: workspace,
      productivity: productivity,
    ).toActionCallbacks();
    final buildResult = callbacks.build(
      actionSet: const ShellActionProductionActionSet(
        requiredActionNames: {'newTab', 'searchScrollback'},
      ),
    );

    final newTabResult = await buildResult.bindings.run(
      TerminalActionId.newTab,
      cwd: '/tmp/project',
    );
    final searchResult = await buildResult.bindings.run(
      TerminalActionId.search,
      payload: 'needle',
    );

    expect(buildResult.isComplete, isTrue);
    expect(newTabResult.message, 'created');
    expect(searchResult.message, 'searched');
  });

  test('omits action callbacks for missing domain operations', () {
    final callbacks = LocalTerminalActionDomainRouter(
      workspace: LocalWorkspaceProductionWiring(
        requiredOperations: const [],
        callbacks: const LocalWorkspaceProductionCallbacks(),
      ),
    ).toActionCallbacks();
    final buildResult = callbacks.build(
      actionSet: const ShellActionProductionActionSet(
        requiredActionNames: {'newTab'},
      ),
    );

    expect(buildResult.isComplete, isFalse);
    expect(buildResult.audit.missingRequiredActions, {TerminalActionId.newTab});
  });
}
