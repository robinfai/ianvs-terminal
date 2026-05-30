import 'shell_action_registry.dart';

class ShellActionProductionActionNameResolver {
  const ShellActionProductionActionNameResolver();

  static const Map<String, TerminalActionId> aliases = {
    'closeTab': TerminalActionId.closeActiveTab,
    'searchScrollback': TerminalActionId.search,
    'toggleCommandPalette': TerminalActionId.openCommandMenu,
    'toggleHotkeyWindow': TerminalActionId.hotkeyWindow,
    'resizePaneLeft': TerminalActionId.resizePane,
    'resizePaneRight': TerminalActionId.resizePane,
    'resizePaneUp': TerminalActionId.resizePane,
    'resizePaneDown': TerminalActionId.resizePane,
  };

  TerminalActionId? resolve(String actionName) {
    final normalized = actionName.trim();
    final directMatch = _directActionIdsByName[normalized];
    if (directMatch != null) {
      return directMatch;
    }
    return aliases[normalized];
  }

  bool contains(String actionName) {
    return resolve(actionName) != null;
  }

  static final Map<String, TerminalActionId> _directActionIdsByName =
      Map.unmodifiable({
        for (final actionId in TerminalActionId.values) actionId.name: actionId,
      });
}
