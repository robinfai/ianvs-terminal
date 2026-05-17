import '../policies/local_terminal_policy_production_callbacks.dart';
import '../productivity/shell_productivity_production_callbacks.dart';
import '../visual/local_terminal_visual_production_callbacks.dart';
import '../workspace/local_workspace_production_callbacks.dart';
import 'shell_action_production_callbacks.dart';
import 'shell_action_runtime_bindings.dart';

class LocalTerminalActionDomainRouter {
  const LocalTerminalActionDomainRouter({
    this.workspace,
    this.productivity,
    this.policy,
    this.visual,
    this.toggleCommandPalette,
  });

  final LocalWorkspaceProductionWiring? workspace;
  final ShellProductivityProductionWiring? productivity;
  final LocalTerminalPolicyProductionWiring? policy;
  final LocalTerminalVisualProductionWiring? visual;
  final ShellActionBinding? toggleCommandPalette;

  ShellActionProductionCallbacks toActionCallbacks() {
    return ShellActionProductionCallbacks(
      newTab: _workspace(LocalWorkspaceProductionOperation.newTab),
      closeTab: _workspace(LocalWorkspaceProductionOperation.closeTab),
      reopenClosedTab: _workspace(
        LocalWorkspaceProductionOperation.reopenClosedTab,
      ),
      duplicateCurrentCwd: _workspace(
        LocalWorkspaceProductionOperation.duplicateCurrentCwd,
      ),
      splitRight: _workspace(LocalWorkspaceProductionOperation.splitRight),
      splitDown: _workspace(LocalWorkspaceProductionOperation.splitDown),
      closePane: _workspace(LocalWorkspaceProductionOperation.closePane),
      focusNextPane: _workspace(
        LocalWorkspaceProductionOperation.focusNextPane,
      ),
      focusPreviousPane: _workspace(
        LocalWorkspaceProductionOperation.focusPreviousPane,
      ),
      copy: _policy(LocalTerminalPolicyProductionOperation.copy),
      paste: _policy(LocalTerminalPolicyProductionOperation.paste),
      pasteHistory: _policy(
        LocalTerminalPolicyProductionOperation.pasteHistory,
      ),
      copyCommandOutput: _productivity(
        ShellProductivityProductionOperation.copyCommandOutput,
      ),
      searchScrollback: _productivity(
        ShellProductivityProductionOperation.searchScrollback,
      ),
      nextSearchMatch: _productivity(
        ShellProductivityProductionOperation.nextSearchMatch,
      ),
      previousSearchMatch: _productivity(
        ShellProductivityProductionOperation.previousSearchMatch,
      ),
      clearSearch: _productivity(
        ShellProductivityProductionOperation.clearSearch,
      ),
      nextPrompt: _productivity(
        ShellProductivityProductionOperation.nextPrompt,
      ),
      previousPrompt: _productivity(
        ShellProductivityProductionOperation.previousPrompt,
      ),
      selectCommandOutput: _productivity(
        ShellProductivityProductionOperation.selectCommandOutput,
      ),
      openRecentDirectory: _productivity(
        ShellProductivityProductionOperation.openRecentDirectory,
      ),
      clearScrollback: _productivity(
        ShellProductivityProductionOperation.clearScrollback,
      ),
      toggleReadOnly: _productivity(
        ShellProductivityProductionOperation.toggleReadOnly,
      ),
      toggleCommandPalette: toggleCommandPalette,
      toggleHotkeyWindow: _policy(
        LocalTerminalPolicyProductionOperation.toggleHotkeyWindow,
      ),
      openThemePicker: _visual(
        LocalTerminalVisualProductionOperation.openThemePicker,
      ),
      applyLayoutTemplate: _visual(
        LocalTerminalVisualProductionOperation.applyLayoutTemplate,
      ),
      exportScrollback: _visual(
        LocalTerminalVisualProductionOperation.exportScrollback,
      ),
      resizePaneLeft: _workspace(LocalWorkspaceProductionOperation.resizePane),
      resizePaneRight: _workspace(LocalWorkspaceProductionOperation.resizePane),
      resizePaneUp: _workspace(LocalWorkspaceProductionOperation.resizePane),
      resizePaneDown: _workspace(LocalWorkspaceProductionOperation.resizePane),
      swapPane: _workspace(LocalWorkspaceProductionOperation.swapPane),
      zoomPane: _workspace(LocalWorkspaceProductionOperation.zoomPane),
      applyTheme: _visual(LocalTerminalVisualProductionOperation.applyTheme),
    );
  }

  ShellActionBinding? _workspace(LocalWorkspaceProductionOperation operation) {
    final wiring = workspace;
    if (wiring == null || !wiring.registeredOperations.contains(operation)) {
      return null;
    }
    return (context) async {
      final result = await wiring.run(
        operation,
        tabId: context.tabId,
        paneId: context.paneId,
        cwd: context.cwd,
        payload: context.payload,
      );
      return _fromWorkspaceResult(result);
    };
  }

  ShellActionBinding? _productivity(
    ShellProductivityProductionOperation operation,
  ) {
    final wiring = productivity;
    if (wiring == null || !wiring.registeredOperations.contains(operation)) {
      return null;
    }
    return (context) async {
      final result = await wiring.run(
        operation,
        tabId: context.tabId,
        paneId: context.paneId,
        query: context.payload is String ? context.payload as String : null,
        payload: context.payload,
      );
      return _fromProductivityResult(result);
    };
  }

  ShellActionBinding? _policy(
    LocalTerminalPolicyProductionOperation operation,
  ) {
    final wiring = policy;
    if (wiring == null || !wiring.registeredOperations.contains(operation)) {
      return null;
    }
    return (context) async {
      final result = await wiring.run(
        operation,
        tabId: context.tabId,
        paneId: context.paneId,
        text: context.payload is String ? context.payload as String : null,
        payload: context.payload,
      );
      return _fromPolicyResult(result);
    };
  }

  ShellActionBinding? _visual(
    LocalTerminalVisualProductionOperation operation,
  ) {
    final wiring = visual;
    if (wiring == null || !wiring.registeredOperations.contains(operation)) {
      return null;
    }
    return (context) async {
      final result = await wiring.run(
        operation,
        tabId: context.tabId,
        paneId: context.paneId,
        themeId: context.payload is String ? context.payload as String : null,
        templateId: context.payload is String
            ? context.payload as String
            : null,
        destinationPath: context.payload is String
            ? context.payload as String
            : null,
        payload: context.payload,
      );
      return _fromVisualResult(result);
    };
  }

  ShellActionBindingResult _fromWorkspaceResult(
    LocalWorkspaceBindingResult result,
  ) {
    if (result.completed) {
      return ShellActionBindingResult.completed(result.message);
    }
    return ShellActionBindingResult.failed(
      failureCode: _workspaceFailure(result.failureCode),
      message: result.message,
    );
  }

  ShellActionBindingResult _fromProductivityResult(
    ShellProductivityBindingResult result,
  ) {
    if (result.completed) {
      return ShellActionBindingResult.completed(result.message);
    }
    return ShellActionBindingResult.failed(
      failureCode: _productivityFailure(result.failureCode),
      message: result.message,
    );
  }

  ShellActionBindingResult _fromPolicyResult(
    LocalTerminalPolicyBindingResult result,
  ) {
    if (result.completed) {
      return ShellActionBindingResult.completed(result.message);
    }
    return ShellActionBindingResult.failed(
      failureCode: _policyFailure(result.failureCode),
      message: result.message,
    );
  }

  ShellActionBindingResult _fromVisualResult(
    LocalTerminalVisualBindingResult result,
  ) {
    if (result.completed) {
      return ShellActionBindingResult.completed(result.message);
    }
    return ShellActionBindingResult.failed(
      failureCode: _visualFailure(result.failureCode),
      message: result.message,
    );
  }

  ShellActionBindingFailureCode _workspaceFailure(
    LocalWorkspaceBindingFailureCode? failureCode,
  ) {
    return switch (failureCode) {
      LocalWorkspaceBindingFailureCode.unavailable =>
        ShellActionBindingFailureCode.unavailable,
      LocalWorkspaceBindingFailureCode.unsupported =>
        ShellActionBindingFailureCode.unsupported,
      LocalWorkspaceBindingFailureCode.rejected =>
        ShellActionBindingFailureCode.rejected,
      LocalWorkspaceBindingFailureCode.platformFailure =>
        ShellActionBindingFailureCode.platformFailure,
      null => ShellActionBindingFailureCode.platformFailure,
    };
  }

  ShellActionBindingFailureCode _productivityFailure(
    ShellProductivityBindingFailureCode? failureCode,
  ) {
    return switch (failureCode) {
      ShellProductivityBindingFailureCode.unavailable =>
        ShellActionBindingFailureCode.unavailable,
      ShellProductivityBindingFailureCode.unsupported =>
        ShellActionBindingFailureCode.unsupported,
      ShellProductivityBindingFailureCode.rejected =>
        ShellActionBindingFailureCode.rejected,
      ShellProductivityBindingFailureCode.shellIntegrationDisabled =>
        ShellActionBindingFailureCode.unavailable,
      ShellProductivityBindingFailureCode.platformFailure =>
        ShellActionBindingFailureCode.platformFailure,
      null => ShellActionBindingFailureCode.platformFailure,
    };
  }

  ShellActionBindingFailureCode _policyFailure(
    LocalTerminalPolicyBindingFailureCode? failureCode,
  ) {
    return switch (failureCode) {
      LocalTerminalPolicyBindingFailureCode.unavailable =>
        ShellActionBindingFailureCode.unavailable,
      LocalTerminalPolicyBindingFailureCode.unsupported =>
        ShellActionBindingFailureCode.unsupported,
      LocalTerminalPolicyBindingFailureCode.rejected =>
        ShellActionBindingFailureCode.rejected,
      LocalTerminalPolicyBindingFailureCode.permissionDenied =>
        ShellActionBindingFailureCode.permissionDenied,
      LocalTerminalPolicyBindingFailureCode.platformFailure =>
        ShellActionBindingFailureCode.platformFailure,
      null => ShellActionBindingFailureCode.platformFailure,
    };
  }

  ShellActionBindingFailureCode _visualFailure(
    LocalTerminalVisualBindingFailureCode? failureCode,
  ) {
    return switch (failureCode) {
      LocalTerminalVisualBindingFailureCode.unavailable =>
        ShellActionBindingFailureCode.unavailable,
      LocalTerminalVisualBindingFailureCode.unsupported =>
        ShellActionBindingFailureCode.unsupported,
      LocalTerminalVisualBindingFailureCode.rejected =>
        ShellActionBindingFailureCode.rejected,
      LocalTerminalVisualBindingFailureCode.fileSystemFailure =>
        ShellActionBindingFailureCode.platformFailure,
      LocalTerminalVisualBindingFailureCode.platformFailure =>
        ShellActionBindingFailureCode.platformFailure,
      null => ShellActionBindingFailureCode.platformFailure,
    };
  }
}
