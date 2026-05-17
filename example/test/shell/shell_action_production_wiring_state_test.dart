import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/shell_action_production_action_set.dart';
import 'package:app/features/shell/shell_action_production_callbacks.dart';
import 'package:app/features/shell/shell_action_production_wiring_state.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_action_runtime_bindings.dart';

void main() {
  test('is ready when callbacks satisfy the production action set', () {
    final state = ShellActionProductionWiringState.fromCallbacks(
      actionSet: const ShellActionProductionActionSet(
        requiredActionNames: {'newTab'},
      ),
      callbacks: ShellActionProductionCallbacks(
        newTab: (_) => const ShellActionBindingResult.completed(),
      ),
    );

    expect(state.isReady, isTrue);
    expect(state.hasBlockingDiagnostics, isFalse);
  });

  test('is not ready when required callbacks are missing', () {
    final state = ShellActionProductionWiringState.fromCallbacks(
      actionSet: const ShellActionProductionActionSet(
        requiredActionNames: {'newTab', 'closeTab'},
      ),
      callbacks: ShellActionProductionCallbacks(
        newTab: (_) => const ShellActionBindingResult.completed(),
      ),
    );

    expect(state.isReady, isFalse);
    expect(state.hasBlockingDiagnostics, isTrue);
    expect(state.blockingDiagnostics, isNotEmpty);
  });

  test('runs through the built production bindings', () async {
    final state = ShellActionProductionWiringState.fromCallbacks(
      actionSet: const ShellActionProductionActionSet(
        requiredActionNames: {'newTab'},
      ),
      callbacks: ShellActionProductionCallbacks(
        newTab: (context) {
          expect(context.cwd, '/tmp/project');
          return const ShellActionBindingResult.completed('created');
        },
      ),
    );

    final result = await state.run(
      TerminalActionId.newTab,
      cwd: '/tmp/project',
    );

    expect(result.completed, isTrue);
    expect(result.message, 'created');
  });

  test('default P1 baseline is ready with matching typed callbacks', () {
    final state = ShellActionProductionWiringState.fromCallbacks(
      actionSet: ShellActionProductionActionSet.defaults(),
      callbacks: _baselineCallbacks(),
    );

    expect(state.isReady, isTrue);
    expect(state.hasBlockingDiagnostics, isFalse);
    expect(state.blockingDiagnostics, isEmpty);
    expect(state.buildResult.audit.missingRequiredActions, isEmpty);
    expect(state.bindings.contains(TerminalActionId.resizePane), isTrue);
  });
}

ShellActionProductionCallbacks _baselineCallbacks() {
  return ShellActionProductionCallbacks(
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
}

ShellActionBindingResult _complete(ShellActionBindingContext context) {
  return const ShellActionBindingResult.completed();
}
