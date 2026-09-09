import 'package:app/features/shell/shell_action_production_action_set.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_action_runtime_bindings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves configured production action names to action ids', () {
    const actionSet = ShellActionProductionActionSet(
      requiredActionNames: {' newTab ', ' closeTab ', 'notRegisteredYet'},
    );

    expect(actionSet.requiredActionIds, contains(TerminalActionId.newTab));
    expect(
      actionSet.requiredActionIds,
      contains(TerminalActionId.closeActiveTab),
    );
    expect(actionSet.unknownRequiredActionNames, {'notRegisteredYet'});
  });

  test('audits required production bindings', () {
    const actionSet = ShellActionProductionActionSet(
      requiredActionNames: {'newTab', 'closeTab'},
    );
    final bindings = ShellActionRuntimeBindings(
      bindings: {
        TerminalActionId.newTab: (_) =>
            const ShellActionBindingResult.completed(),
      },
    );

    final audit = actionSet.auditBindings(bindings);

    expect(audit.isComplete, isFalse);
    expect(audit.missingRequiredActions, {TerminalActionId.closeActiveTab});
  });

  test('default production action set covers current P1 baseline', () {
    final actionSet = ShellActionProductionActionSet.defaults();

    expect(actionSet.unknownRequiredActionNames, isEmpty);
    expect(actionSet.unknownOptionalActionNames, isEmpty);
    expect(
      actionSet.requiredActionNames,
      containsAll({
        'newTab',
        'closeTab',
        'reopenClosedTab',
        'reopenClosedPane',
        'duplicateCurrentCwd',
        'splitRight',
        'splitDown',
        'closePane',
        'focusNextPane',
        'focusPreviousPane',
        'resizePane',
        'swapPane',
        'zoomPane',
        'copy',
        'copyCommandOutput',
        'paste',
        'instantReplay',
        'toggleReadOnly',
        'clearBuffer',
        'searchScrollback',
        'previousPrompt',
        'nextPrompt',
        'toggleCommandPalette',
        'openDefaults',
        'defaults',
        'profiles',
        'exportScrollback',
      }),
    );
    expect(
      actionSet.requiredActionIds,
      contains(TerminalActionId.closeActiveTab),
    );
    expect(actionSet.requiredActionIds, contains(TerminalActionId.search));
    expect(
      actionSet.requiredActionIds,
      contains(TerminalActionId.openCommandMenu),
    );
    expect(actionSet.requiredActionIds, contains(TerminalActionId.resizePane));
  });
}
