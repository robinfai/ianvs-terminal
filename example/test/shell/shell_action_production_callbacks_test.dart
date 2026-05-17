import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/shell_action_production_action_set.dart';
import 'package:app/features/shell/shell_action_production_callbacks.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_action_runtime_bindings.dart';

void main() {
  test('builds named bindings from typed callbacks', () async {
    const actionSet = ShellActionProductionActionSet(
      requiredActionNames: {'newTab'},
    );
    final callbacks = ShellActionProductionCallbacks(
      newTab: (_) => const ShellActionBindingResult.completed('created'),
    );

    final result = callbacks.build(actionSet: actionSet);
    final bindingResult = await result.bindings.run(TerminalActionId.newTab);

    expect(result.isComplete, isTrue);
    expect(bindingResult.message, 'created');
  });

  test('omitted required callbacks remain visible in the audit', () {
    const actionSet = ShellActionProductionActionSet(
      requiredActionNames: {'newTab', 'closeTab'},
    );
    final callbacks = ShellActionProductionCallbacks(
      newTab: (_) => const ShellActionBindingResult.completed(),
    );

    final result = callbacks.build(actionSet: actionSet);

    expect(result.isComplete, isFalse);
    expect(result.audit.missingRequiredActions, {
      TerminalActionId.closeActiveTab,
    });
  });

  test('optional callbacks do not become unplanned bindings', () {
    const actionSet = ShellActionProductionActionSet(
      requiredActionNames: {},
      optionalActionNames: {'closeTab'},
    );
    final callbacks = ShellActionProductionCallbacks(
      closeTab: (_) => const ShellActionBindingResult.completed(),
    );

    final result = callbacks.build(actionSet: actionSet);

    expect(result.audit.unplannedRegisteredActions, isEmpty);
  });

  test('typed callbacks can satisfy the default P1 baseline', () {
    final callbacks = ShellActionProductionCallbacks(
      newTab: _complete,
      closeTab: _complete,
      reopenClosedTab: _complete,
      duplicateCurrentCwd: _complete,
      toolbelt: _complete,
      splitRight: _complete,
      splitDown: _complete,
      closePane: _complete,
      focusNextPane: _complete,
      focusPreviousPane: _complete,
      copy: _complete,
      copyMode: _complete,
      paste: _complete,
      advancedPaste: _complete,
      pasteHistory: _complete,
      instantReplay: _complete,
      globalSearch: _complete,
      autocomplete: _complete,
      autoComposer: _complete,
      copyCommandOutput: _complete,
      searchScrollback: _complete,
      nextPrompt: _complete,
      previousPrompt: _complete,
      selectCommandOutput: _complete,
      shellIntegrationUtilities: _complete,
      openRecentDirectory: _complete,
      tmuxIntegration: _complete,
      coprocess: _complete,
      annotations: _complete,
      capturedOutput: _complete,
      passwordManager: _complete,
      clearScrollback: _complete,
      toggleReadOnly: _complete,
      toggleCommandPalette: _complete,
      toggleHotkeyWindow: _complete,
      openDefaults: _complete,
      defaults: _complete,
      profiles: _complete,
      dynamicProfiles: _complete,
      openThemePicker: _complete,
      applyLayoutTemplate: _complete,
      exportScrollback: _complete,
      resizePaneLeft: _complete,
      swapPane: _complete,
      zoomPane: _complete,
      toggleCommandFinishedNotify: _complete,
      toggleBellNotify: _complete,
      toggleActivityMonitor: _complete,
    );

    final result = callbacks.build(
      actionSet: ShellActionProductionActionSet.defaults(),
    );

    expect(result.isComplete, isTrue);
    expect(result.hasUnknownNames, isFalse);
    expect(result.audit.missingRequiredActions, isEmpty);
    expect(result.audit.unplannedRegisteredActions, isEmpty);
    expect(result.bindings.contains(TerminalActionId.resizePane), isTrue);
  });
}

ShellActionBindingResult _complete(ShellActionBindingContext context) {
  return const ShellActionBindingResult.completed();
}
