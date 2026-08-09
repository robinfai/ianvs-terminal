import 'package:app/features/shell/shell_action_production_action_set.dart';
import 'package:app/features/shell/shell_action_production_binding_builder.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_action_runtime_bindings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds runtime bindings from action names', () async {
    final builder = ShellActionProductionBindingBuilder(
      actionSet: const ShellActionProductionActionSet(
        requiredActionNames: {' newTab '},
      ),
      bindingsByName: {
        ' newTab ': (_) => const ShellActionBindingResult.completed('created'),
      },
    );

    final result = builder.build();
    final bindingResult = await result.bindings.run(TerminalActionId.newTab);

    expect(result.isComplete, isTrue);
    expect(bindingResult.completed, isTrue);
    expect(bindingResult.message, 'created');
  });

  test('reports unknown binding names', () {
    final builder = ShellActionProductionBindingBuilder(
      actionSet: const ShellActionProductionActionSet(
        requiredActionNames: {'newTab'},
      ),
      bindingsByName: {
        'notRegisteredYet': (_) => const ShellActionBindingResult.completed(),
      },
    );

    final result = builder.build();

    expect(result.hasUnknownNames, isTrue);
    expect(result.unknownBindingNames, {'notRegisteredYet'});
    expect(result.audit.missingRequiredActions, {TerminalActionId.newTab});
  });

  test('reports unknown planned action names', () {
    final builder = ShellActionProductionBindingBuilder(
      actionSet: const ShellActionProductionActionSet(
        requiredActionNames: {'newTab', 'notRegisteredYet'},
      ),
      bindingsByName: {
        'newTab': (_) => const ShellActionBindingResult.completed(),
      },
    );

    final result = builder.build();

    expect(result.isComplete, isFalse);
    expect(result.unknownRequiredActionNames, {'notRegisteredYet'});
  });
}
