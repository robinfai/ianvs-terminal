import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/shell_action_production_action_set.dart';
import 'package:app/features/shell/shell_action_production_callbacks.dart';
import 'package:app/features/shell/shell_action_production_runtime_adapter.dart';
import 'package:app/features/shell/shell_action_registry.dart';
import 'package:app/features/shell/shell_action_runtime_bindings.dart';

void main() {
  test(
    'adapts production callbacks to an external executor function',
    () async {
      final adapter = ShellActionProductionRuntimeAdapter.fromCallbacks(
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

      final executor = adapter.asExternalExecutor();
      final result = await executor(
        const ShellActionBindingContext(
          actionId: TerminalActionId.newTab,
          cwd: '/tmp/project',
        ),
      );

      expect(adapter.isReady, isTrue);
      expect(result.completed, isTrue);
      expect(result.message, 'created');
    },
  );

  test('returns unavailable when production wiring is not ready', () async {
    final adapter = ShellActionProductionRuntimeAdapter.fromCallbacks(
      actionSet: const ShellActionProductionActionSet(
        requiredActionNames: {'newTab', 'closeTab'},
      ),
      callbacks: ShellActionProductionCallbacks(
        newTab: (_) => const ShellActionBindingResult.completed(),
      ),
    );

    final result = await adapter.execute(
      const ShellActionBindingContext(
        actionId: TerminalActionId.closeActiveTab,
      ),
    );

    expect(adapter.isReady, isFalse);
    expect(result.failed, isTrue);
    expect(result.failureCode, ShellActionBindingFailureCode.unavailable);
  });

  test('external executor runs default P1 baseline aliases', () async {
    final adapter = ShellActionProductionRuntimeAdapter.fromCallbacks(
      actionSet: ShellActionProductionActionSet.defaults(),
      callbacks: _baselineCallbacks(),
    );
    final executor = adapter.asExternalExecutor();

    expect(adapter.isReady, isTrue);

    final closeResult = await executor(
      const ShellActionBindingContext(
        actionId: TerminalActionId.closeActiveTab,
      ),
    );
    final resizeResult = await executor(
      const ShellActionBindingContext(
        actionId: TerminalActionId.resizePane,
        paneId: 'pane-1',
      ),
    );
    final paletteResult = await executor(
      const ShellActionBindingContext(
        actionId: TerminalActionId.openCommandMenu,
      ),
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
    reopenClosedPane: _complete,
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
