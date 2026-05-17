import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/shell_action_production_action_set.dart';
import 'package:app/features/shell/shell_action_production_callbacks.dart';
import 'package:app/features/shell/shell_action_production_executor.dart';
import 'package:app/features/shell/shell_action_production_wiring_state.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_action_runtime_bindings.dart';

void main() {
  test('executes through ready production wiring', () async {
    final wiringState = ShellActionProductionWiringState.fromCallbacks(
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

    final result = await ShellActionProductionExecutor(
      wiringState: wiringState,
    ).execute(TerminalActionId.newTab, cwd: '/tmp/project');

    expect(result.completed, isTrue);
    expect(result.message, 'created');
  });

  test('fails before execution when production wiring is not ready', () async {
    final wiringState = ShellActionProductionWiringState.fromCallbacks(
      actionSet: const ShellActionProductionActionSet(
        requiredActionNames: {'newTab', 'closeTab'},
      ),
      callbacks: ShellActionProductionCallbacks(
        newTab: (_) => const ShellActionBindingResult.completed(),
      ),
    );

    final result = await ShellActionProductionExecutor(
      wiringState: wiringState,
    ).execute(TerminalActionId.closeActiveTab);

    expect(result.failed, isTrue);
    expect(result.failureCode, ShellActionBindingFailureCode.unavailable);
    expect(result.message, contains('closeActiveTab'));
  });

  test('captures callback exceptions as platform failures', () async {
    final wiringState = ShellActionProductionWiringState.fromCallbacks(
      actionSet: const ShellActionProductionActionSet(
        requiredActionNames: {'newTab'},
      ),
      callbacks: ShellActionProductionCallbacks(
        newTab: (_) => throw StateError('boom'),
      ),
    );

    final result = await ShellActionProductionExecutor(
      wiringState: wiringState,
    ).execute(TerminalActionId.newTab);

    expect(result.failed, isTrue);
    expect(result.failureCode, ShellActionBindingFailureCode.platformFailure);
    expect(result.error, isA<StateError>());
  });

  test('executes default P1 baseline aliases through ready wiring', () async {
    final wiringState = ShellActionProductionWiringState.fromCallbacks(
      actionSet: ShellActionProductionActionSet.defaults(),
      callbacks: _baselineCallbacks(),
    );
    final executor = ShellActionProductionExecutor(wiringState: wiringState);

    expect(executor.isReady, isTrue);

    final closeResult = await executor.execute(TerminalActionId.closeActiveTab);
    final resizeResult = await executor.execute(
      TerminalActionId.resizePane,
      paneId: 'pane-1',
    );
    final paletteResult = await executor.execute(
      TerminalActionId.openCommandMenu,
    );

    expect(closeResult.completed, isTrue);
    expect(resizeResult.completed, isTrue);
    expect(paletteResult.completed, isTrue);
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
