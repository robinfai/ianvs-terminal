import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/shell_action_production_action_set.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_action_runtime_bindings.dart';

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
        'toolbelt',
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
        'copyMode',
        'paste',
        'advancedPaste',
        'pasteHistory',
        'instantReplay',
        'toggleReadOnly',
        'clearBuffer',
        'globalSearch',
        'autocomplete',
        'autoComposer',
        'searchScrollback',
        'previousPrompt',
        'nextPrompt',
        'selectCommandOutput',
        'shellIntegrationUtilities',
        'openRecentDirectory',
        'tmuxIntegration',
        'coprocess',
        'annotations',
        'capturedOutput',
        'passwordManager',
        'toggleCommandPalette',
        'toggleHotkeyWindow',
        'openDefaults',
        'defaults',
        'profiles',
        'dynamicProfiles',
        'openThemePicker',
        'applyLayoutTemplate',
        'exportScrollback',
        'toggleCommandFinishedNotify',
        'toggleBellNotify',
        'toggleActivityMonitor',
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
    expect(
      actionSet.requiredActionIds,
      contains(TerminalActionId.hotkeyWindow),
    );
    expect(actionSet.requiredActionIds, contains(TerminalActionId.resizePane));
  });
}
