import 'shell_action_production_action_name_resolver.dart';
import 'shell_action_registry.dart';
import 'shell_action_runtime_binding_audit.dart';
import 'shell_action_runtime_bindings.dart';

class ShellActionProductionActionSet {
  const ShellActionProductionActionSet({
    required this.requiredActionNames,
    this.optionalActionNames = const {},
  });

  factory ShellActionProductionActionSet.defaults() {
    return const ShellActionProductionActionSet(
      requiredActionNames: _defaultRequiredActionNames,
      optionalActionNames: _defaultOptionalActionNames,
    );
  }

  static const Set<String> _defaultRequiredActionNames = {
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
    'clearScrollback',
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
  };

  static const Set<String> _defaultOptionalActionNames = {};

  final Set<String> requiredActionNames;
  final Set<String> optionalActionNames;

  Set<TerminalActionId> get requiredActionIds {
    return _resolveActionNames(requiredActionNames);
  }

  Set<TerminalActionId> get optionalActionIds {
    return _resolveActionNames(optionalActionNames);
  }

  Set<String> get unknownRequiredActionNames {
    return _unknownActionNames(requiredActionNames);
  }

  Set<String> get unknownOptionalActionNames {
    return _unknownActionNames(optionalActionNames);
  }

  bool get hasUnknownActionNames {
    return unknownRequiredActionNames.isNotEmpty ||
        unknownOptionalActionNames.isNotEmpty;
  }

  ShellActionRuntimeBindingAudit auditBindings(
    ShellActionRuntimeBindings bindings,
  ) {
    return ShellActionRuntimeBindingAudit.fromBindings(
      bindings: bindings,
      requiredActions: requiredActionIds,
      optionalActions: optionalActionIds,
    );
  }

  Set<TerminalActionId> _resolveActionNames(Set<String> actionNames) {
    const actionNameResolver = ShellActionProductionActionNameResolver();
    return actionNames
        .map(actionNameResolver.resolve)
        .whereType<TerminalActionId>()
        .toSet();
  }

  Set<String> _unknownActionNames(Set<String> actionNames) {
    const actionNameResolver = ShellActionProductionActionNameResolver();
    return actionNames
        .where((name) => !actionNameResolver.contains(name))
        .toSet();
  }
}
