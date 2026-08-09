import 'package:app/features/layout/terminal_layout_production_callbacks.dart';
import 'package:app/features/productivity/shell_productivity_production_callbacks.dart';
import 'package:app/features/shell/local_terminal_action_domain_router.dart';
import 'package:app/features/shell/shell_action_production_action_set.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('routes shell actions to registered domain callbacks', () async {
    final layout = TerminalLayoutProductionWiring(
      requiredOperations: const [TerminalLayoutProductionOperation.newTab],
      callbacks: TerminalLayoutProductionCallbacks(
        newTab: (context) {
          expect(context.cwd, '/tmp/project');
          return const TerminalLayoutBindingResult.completed('created');
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
      layout: layout,
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
      layout: TerminalLayoutProductionWiring(
        requiredOperations: const [],
        callbacks: const TerminalLayoutProductionCallbacks(),
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
